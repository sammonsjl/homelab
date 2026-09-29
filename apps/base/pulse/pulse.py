"""pulse: a read-only, public summary of the cluster for the NeoKube site.

GET /pulse/status.json returns node readiness, versions, the GitOps revision,
the ACE platform's state and a short list of recent events. Everything comes
from the kube API through this pod's service account; nothing else is read.

The document is public, so it is built from an allow-list: no IPs, no event
messages, and events only from the namespaces and kinds listed below.
"""

import json
import os
import ssl
import threading
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

API = "https://kubernetes.default.svc"
SA = "/var/run/secrets/kubernetes.io/serviceaccount"
TTL = 20                 # seconds a built document is reused
EVENT_WINDOW = 6 * 3600  # how far back events may come from
EVENT_MAX = 12

EVENT_NAMESPACES = {"ghost", "ace", "flux-system", "kube-system", "monitoring", "default"}
EVENT_KINDS = {
    "Pod", "Deployment", "ReplicaSet", "StatefulSet", "DaemonSet", "Job", "Node",
    "Kustomization", "HelmRelease", "GitRepository", "HelmRepository", "HelmChart",
    "ClusterSecretStore", "AutomationPlatform",
}
EVENT_REASONS = {
    "Scheduled", "Pulled", "Started", "Killing", "SuccessfulCreate", "ScalingReplicaSet",
    "ReconciliationSucceeded", "Progressing", "NodeReady", "Upgraded", "GitOperationSucceeded",
    "ArtifactUpToDate", "InstallSucceeded", "UpgradeSucceeded", "Valid",
}

_ctx = ssl.create_default_context(cafile=f"{SA}/ca.crt")


def get(path):
    with open(f"{SA}/token") as f:
        token = f.read().strip()
    req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, context=_ctx, timeout=5) as r:
        return json.load(r)


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")) if s else None


def condition(obj, kind):
    for c in obj.get("status", {}).get("conditions", []):
        if c.get("type") == kind:
            return c.get("status") == "True"
    return False


def build():
    now = datetime.now(timezone.utc)
    doc = {"generated": now.isoformat(timespec="seconds"), "stale": False}

    nodes = get("/api/v1/nodes")["items"]
    doc["nodes"] = {
        "ready": sum(condition(n, "Ready") for n in nodes),
        "total": len(nodes),
        "names": sorted(n["metadata"]["name"] for n in nodes),
    }
    doc["cluster_born"] = min(n["metadata"]["creationTimestamp"] for n in nodes) if nodes else None
    info = nodes[0]["status"]["nodeInfo"] if nodes else {}
    os_image = info.get("osImage", "")  # "Talos (v1.14.1)"
    versions = {
        "talos": os_image[os_image.find("(") + 1:os_image.find(")")] if "(" in os_image else None,
        "kubernetes": info.get("kubeletVersion"),
    }
    try:
        ds = get("/apis/apps/v1/namespaces/kube-system/daemonsets/cilium")
        image = ds["spec"]["template"]["spec"]["containers"][0]["image"].split("@")[0]
        versions["cilium"] = image.rsplit(":", 1)[-1]
    except Exception:
        versions["cilium"] = None
    doc["versions"] = versions

    try:
        repo = get("/apis/source.toolkit.fluxcd.io/v1/namespaces/flux-system/gitrepositories/flux-system")
        artifact = repo.get("status", {}).get("artifact", {})
        kss = get("/apis/kustomize.toolkit.fluxcd.io/v1/namespaces/flux-system/kustomizations")["items"]
        url = repo["spec"]["url"]  # ssh://git@github.com/owner/repo.git
        doc["gitops"] = {
            "repo": "https://github.com/" + url.split("github.com/", 1)[-1].removesuffix(".git"),
            "sha": artifact.get("revision", "").rsplit(":", 1)[-1][:7],
            "committed": artifact.get("lastUpdateTime"),  # when this revision was fetched
            "checked": None,  # when Flux last pulled the repo, filled in from events below
            "ready": sum(condition(k, "Ready") for k in kss),
            "total": len(kss),
        }
    except Exception:
        doc["gitops"] = None

    try:
        ap = get("/apis/automation.ace.io/v1alpha1/namespaces/ace/automationplatforms/ace")
        status = ap.get("status", {})
        pods = get("/api/v1/namespaces/ace/pods")["items"]
        last = next((c.get("lastTransitionTime") for c in status.get("conditions", [])
                     if c.get("type") == "Successful"), None)
        doc["ace"] = {
            "ready": condition(ap, "Successful") and not condition(ap, "Failure"),
            "tag": status.get("images", {}).get("controller", "").rsplit(":", 1)[-1] or None,
            "components": status.get("components", []),
            "pods_running": sum(p.get("status", {}).get("phase") == "Running" for p in pods),
            "last_reconcile": last,
        }
    except Exception:
        doc["ace"] = None

    events, seen = [], set()
    items = get("/api/v1/events?limit=500")["items"]
    items.sort(key=lambda e: e.get("lastTimestamp") or e.get("eventTime") or "", reverse=True)
    if doc["gitops"]:
        doc["gitops"]["checked"] = next(
            (e.get("lastTimestamp") or e.get("eventTime") for e in items
             if e.get("reason") == "GitOperationSucceeded"
             and e.get("involvedObject", {}).get("name") == "flux-system"), None)
    for e in items:
        obj = e.get("involvedObject", {})
        when = ts(e.get("lastTimestamp") or e.get("eventTime"))
        key = (e.get("reason"), obj.get("kind"), obj.get("name"))
        if (e.get("metadata", {}).get("namespace") not in EVENT_NAMESPACES
                or obj.get("kind") not in EVENT_KINDS
                or e.get("reason") not in EVENT_REASONS
                or not when or (now - when).total_seconds() > EVENT_WINDOW
                or key in seen):
            continue
        seen.add(key)
        events.append({"type": e.get("type"), "reason": e.get("reason"), "kind": obj.get("kind"),
                       "name": obj.get("name"), "age_s": int((now - when).total_seconds())})
        if len(events) == EVENT_MAX:
            break
    doc["events"] = events
    return doc


class Cache:
    def __init__(self):
        self.lock = threading.Lock()
        self.doc, self.at = None, 0.0

    def current(self):
        with self.lock:
            if self.doc and time.monotonic() - self.at < TTL:
                return 200, self.doc
            try:
                self.doc, self.at = build(), time.monotonic()
                return 200, self.doc
            except Exception as exc:  # serve the last good document, marked stale
                print(f"build failed: {exc}", flush=True)
                if self.doc:
                    return 503, {**self.doc, "stale": True}
                return 503, {"stale": True}


cache = Cache()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/pulse/healthz":
            return self.reply(200, b"ok", "text/plain")
        if self.path.split("?")[0] != "/pulse/status.json":
            return self.reply(404, b"not found", "text/plain")
        code, doc = cache.current()
        self.reply(code, json.dumps(doc).encode(), "application/json")

    def reply(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "public, max-age=15")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
