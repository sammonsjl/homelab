# Lab 3 — Before the First Sync

## What you will have at the end

A list of exactly what Argo CD would change on the cluster, read before it is allowed to change
anything.

## Why this lab exists

On Bahamut you applied `root.yaml` and watched. A mistake there costs a `crc delete`. Here,
every Application has `prune` and `selfHeal` switched on, and from the moment `root.yaml` is
applied, whatever git says is done to a machine that serves a site, within seconds.

On a new cluster that is harmless: there is nothing to overwrite. `lud` was not new. Everything
in `clusters/yojimbo` was already running there, installed by hand over the weeks before, and
the folders in git were written afterwards from those same manifests. Handing a running cluster
to git is safe only if git and the cluster already agree.

## Render, then compare

`oc kustomize` builds a folder into the objects Argo CD would apply. `oc diff` sends them to the
API server as a dry run and prints what would change, without changing it:

```bash
cd ~/homelab
for folder in \
    infrastructure/machine-config/yojimbo infrastructure/synology-csi/yojimbo \
    infrastructure/nfs-csi/yojimbo infrastructure/local-path \
    infrastructure/cert-manager/operator infrastructure/cert-manager/yojimbo \
    infrastructure/cloudflare infrastructure/aap/operator infrastructure/aap/yojimbo \
    apps/homepage/yojimbo; do
  echo "== $folder"
  oc diff -k $folder
done
```

The NFS driver is a Helm chart, so it is rendered with `helm`:

```bash
helm template nfs-csi csi-driver-nfs \
  --repo https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts \
  --version 4.13.4 -n kube-system | oc diff -n kube-system -f -
```

## Reading the result

| What you see                               | What it means                                                         |
| ------------------------------------------ | --------------------------------------------------------------------- |
| Nothing under a folder's name              | Git and the cluster agree. The sync will change nothing                |
| Lines starting with `+` for a whole object | The object is not on the cluster. The sync will create it              |
| A few `-` and `+` lines inside an object   | The sync will change a running object. Read every one                  |
| `no matches for kind ...`                  | The kind comes from an operator that is not installed yet. Expected on a new cluster |

On a new cluster the whole output is `+` lines and missing kinds, and there is little to learn
from it. On a running one, the third row is the reason for the lab.

## What it caught

When this was run against `lud`, one folder showed a difference that mattered:

```diff
   listeners:
-  - allowedRoutes:
-      namespaces:
-        from: All
-    name: http
+  - name: http
```

The tunnel's `Gateway` on the cluster let routes from any namespace attach to it. The copy in
git had lost that setting, which leaves the default: routes from the gateway's own namespace
only. The site's route lives in another namespace. Had `root.yaml` been applied, Argo CD would
have "corrected" the gateway within the minute, the route would have been detached, and
neokube.net would have gone offline through no fault of its own.

The fix was three lines in `infrastructure/cloudflare/gateway.yaml`, and a second run that
printed nothing for that folder.

## One difference to expect on a new cluster

`infrastructure/machine-config/yojimbo` adds a `MachineConfig`. When one is created, the Machine
Config Operator renders a new configuration for the node and **reboots it**. On one node, that
is the whole cluster off for a few minutes, Argo CD included, in the middle of its first sync.
The sync carries on when the node is back. On `lud` the `MachineConfig` was already there, and
nothing rebooted.

## Afterwards

Once Argo CD manages an object it adds an annotation of its own, and `oc diff` reports it:

```diff
-    argocd.argoproj.io/tracking-id: homepage:route.openshift.io/Route:homepage/homepage
```

That line means only that git does not contain Argo CD's bookkeeping. To use the same check
later, before pushing a change, filter it out:

```bash
oc diff -k infrastructure/cloudflare | grep -E '^[-+] ' | grep -v -e tracking-id -e generation
```

Next: [Handing the Cluster to Git](04-handing-the-cluster-to-git.md)
