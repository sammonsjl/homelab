# Lab 3 — The Root Application

## What you will have at the end

Five Applications, synced from your fork: the root, the cert-manager operator, a private
certificate authority, a portal page served at `https://homepage.apps-crc.testing`, and Ghost
with its database at `https://ghost.apps-crc.testing`.

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

The folder it names, `clusters/bahamut/apps`, contains four more Applications. So applying this
one file creates the root, the root creates the other four, and each of those creates what is
in its own folder. This is known as the *app of apps* pattern. Adding a component to the cluster
later is one new file in `clusters/bahamut/apps`.

The three lines under `syncPolicy` are what make it hands-off:

| Setting     | Meaning                                                              |
| ----------- | -------------------------------------------------------------------- |
| `automated` | Sync when git changes. Without it, Argo CD only reports the difference |
| `prune`     | Delete from the cluster what has been deleted from git               |
| `selfHeal`  | Undo a change made on the cluster by hand                            |

## The one thing not in git

Ghost's database needs two passwords, and a password in a public fork is a password for
everyone. They go on the cluster by hand, once, before Argo CD is told about Ghost:

```bash
oc create namespace ghost
oc create secret generic ghost-db -n ghost \
  --from-literal=root-password="$(openssl rand -hex 16)" \
  --from-literal=password="$(openssl rand -hex 16)"
```

MySQL and Ghost read their passwords from it. Argo CD will take over the namespace,
because `apps/ghost/base/namespace.yaml` describes it, and leave the secret alone, because
nothing in git describes that. If you forget it, MySQL and Ghost wait in
`CreateContainerConfigError` until it exists, and then start by themselves.

## Apply it

```bash
oc apply -f clusters/bahamut/root.yaml
oc get applications -n openshift-gitops -w
```

Within a few minutes all five settle. Press Ctrl-C when they have:

```
NAME                    SYNC STATUS   HEALTH STATUS
bahamut                 Synced        Healthy
cert-manager            Synced        Healthy
cert-manager-operator   Synced        Healthy
ghost                   Synced        Healthy
homepage                Synced        Healthy
```

`ghost` is the slowest: it shows `Progressing` while MySQL creates its database and Ghost its
tables, a few minutes on the first start. Ghost starts at the same moment as MySQL, finds no
database, stops, and is started again: two or three restarts are the same order-without-ordering
as below, one level down.

> On the first test run for this lab, on a laptop that was short of memory, `cert-manager-operator`
> stayed `Degraded` while cert-manager itself was installed and issuing. On the second run, and on
> the production cluster, it was `Healthy`. If you see it, check `oc get pods -n cert-manager`: three
> pods `Running` is what matters for the rest of this module.

## Order without ordering

All four Applications are created at the same moment, yet one depends on another:
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

## What the four Applications made

| Application             | Folder                                 | What it is                                              |
| ----------------------- | -------------------------------------- | ------------------------------------------------------- |
| `cert-manager-operator` | `infrastructure/cert-manager/operator` | A Subscription, like the one in `bootstrap/`. Shared with Yojimbo |
| `cert-manager`          | `infrastructure/cert-manager/bahamut`  | A self-signed root and an issuer that signs with it     |
| `homepage`              | `apps/homepage/bahamut`                | [Homepage](https://gethomepage.dev), a page of links to what the cluster runs |
| `ghost`                 | `apps/ghost/bahamut`                   | [Ghost](https://ghost.org) and its MySQL, as a base and an overlay. The manifests are explained in [Ghost on OpenShift Local](https://github.com/sammonsjl/aap-on-openshift-local/tree/ghost-on-openshift-local), an earlier version of module 05 |

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

Open `https://homepage.apps-crc.testing` in a browser. It links to the OpenShift console, to
Ghost, and to Argo CD, where the five Applications now show as a tree.

Ghost:

```bash
oc get pods,route -n ghost
curl -sk https://ghost.apps-crc.testing/ghost/api/admin/site/ | grep -o '"version":"[^"]*"'
```

```
NAME                       READY   STATUS    RESTARTS      AGE
pod/ghost-8955dc4b-vltlc   1/1     Running   3 (75s ago)   106s
pod/mysql-0                1/1     Running   0             77s

NAME                             HOST/PORT                PATH   SERVICES   PORT   TERMINATION     WILDCARD
route.route.openshift.io/ghost   ghost.apps-crc.testing          ghost      http   edge/Redirect   None
"version":"6.70"
```

It is a new Ghost, with no owner yet. Make one at `https://ghost.apps-crc.testing/ghost/`. That
account and any post you write are in MySQL, not in git: Argo CD keeps the
Deployment equal to git, not what the blog has in it.

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
oc kustomize apps/homepage/bahamut | grep -E '^kind:| host:'
```

Next: [A Change Through Git](04-a-change-through-git.md)
