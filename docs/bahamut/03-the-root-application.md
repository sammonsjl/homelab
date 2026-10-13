# Lab 3 — The Root Application

## What you will have at the end

Four Applications, synced from your fork: the root, the cert-manager operator, a private
certificate authority, and a portal page served at `https://homepage.apps-crc.testing`.

## One Application that holds the others

An `Application` is Argo CD's unit of work. It names a folder in a repository, a branch, and a
cluster to keep equal to that folder:

```bash
cat clusters/bahamut/root.yaml
```

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bahamut
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/<you>/homelab.git
    targetRevision: openshift-gitops
    path: clusters/bahamut/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: openshift-gitops
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

The folder it names, `clusters/bahamut/apps`, contains three more Applications. So applying this
one file creates the root, the root creates the other three, and each of those creates what is
in its own folder. This is known as the *app of apps* pattern. Adding a component to the cluster
later is one new file in `clusters/bahamut/apps`.

The three lines under `syncPolicy` are what make it hands-off:

| Setting     | Meaning                                                              |
| ----------- | -------------------------------------------------------------------- |
| `automated` | Sync when git changes. Without it, Argo CD only reports the difference |
| `prune`     | Delete from the cluster what has been deleted from git               |
| `selfHeal`  | Undo a change made on the cluster by hand                            |

## Apply it

```bash
oc apply -f clusters/bahamut/root.yaml
oc get applications -n openshift-gitops -w
```

Within a few minutes all four settle. Press Ctrl-C when they have:

```
NAME                    SYNC STATUS   HEALTH STATUS
bahamut                 Synced        Healthy
cert-manager            Synced        Healthy
cert-manager-operator   Synced        Healthy
homepage                Synced        Healthy
```

> On the first test run for this lab, on a laptop that was short of memory, `cert-manager-operator`
> stayed `Degraded` while cert-manager itself was installed and issuing. On the second run, and on
> the production cluster, it was `Healthy`. If you see it, check `oc get pods -n cert-manager`: three
> pods `Running` is what matters for the rest of this module.

## Order without ordering

All three Applications are created at the same moment, yet one depends on another:
`cert-manager` holds a `ClusterIssuer`, a kind of object that does not exist until the operator
from `cert-manager-operator` has installed cert-manager. Nothing in the repository says which
goes first. Instead, every Application carries this:

```yaml
    retry:
      limit: 20
      backoff:
        duration: 30s
        factor: 2
        maxDuration: 3m
    syncOptions:
      - SkipDryRunOnMissingResource=true
```

The first sync of `cert-manager` fails, because the cluster has never heard of a
`ClusterIssuer`. Argo CD waits thirty seconds and tries again, then a minute, then two, until
the operator has caught up. `SkipDryRunOnMissingResource` stops Argo CD from refusing the whole
sync up front for the same reason. You may have seen `cert-manager` report `OutOfSync` or
`Missing` for a minute in the watch above. That was this.

## What the three Applications made

| Application             | Folder                                 | What it is                                              |
| ----------------------- | -------------------------------------- | ------------------------------------------------------- |
| `cert-manager-operator` | `infrastructure/cert-manager/operator` | A Subscription, like the one in `bootstrap/`. Shared with Yojimbo |
| `cert-manager`          | `infrastructure/cert-manager/bahamut`  | A self-signed root and an issuer that signs with it     |
| `homepage`              | `apps/homepage/bahamut`                | [Homepage](https://gethomepage.dev), a page of links to what the cluster runs |

Bahamut's names end in `apps-crc.testing` and exist only on your workstation, so a public
certificate authority has nothing to check. Bahamut gets a private one instead:

```bash
oc get clusterissuer
```

```
NAME         READY   AGE
bahamut-ca   True    4m
selfsigned   True    4m
```

The portal:

```bash
oc get pods,route -n homepage
curl -sk -o /dev/null -w '%{http_code}\n' https://homepage.apps-crc.testing/
```

```
200
```

Open `https://homepage.apps-crc.testing` in a browser. It links to the OpenShift console and to
Argo CD, where the four Applications now show as a tree.

## Base and overlay

`apps/homepage` has three folders:

```
apps/homepage/base/      the Deployment, Service, Route and most of the configuration
apps/homepage/bahamut/   Bahamut's links, and the Route's host name
apps/homepage/yojimbo/   Yojimbo's links, its host name, and the cluster figures
```

Each cluster's folder is a [Kustomize](https://kustomize.io) overlay: it pulls in `base` and
changes only what differs. To see what an Application applies, build its folder yourself:

```bash
oc kustomize apps/homepage/bahamut | grep -E '^kind:|host:'
```

Next: [A Change Through Git](04-a-change-through-git.md)
