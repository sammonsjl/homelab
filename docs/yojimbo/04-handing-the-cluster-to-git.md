# Lab 4 — Handing the Cluster to Git

## What you will have at the end

Argo CD on the production cluster and twelve Applications, the root and its eleven, all `Synced`
and `Healthy`.

## Take a backup first

Whatever the dry run said, take a backup of anything on the cluster you could not rebuild, and
check that it finished. On `lud` that is the site's database and documents.

## Bootstrap

The same two commands as on Bahamut, with nothing to trim: this machine has memory to spare.

```bash
cd ~/homelab
oc apply -k bootstrap
```

```
namespace/openshift-gitops-operator created
clusterrolebinding.rbac.authorization.k8s.io/openshift-gitops-cluster-admin created
operatorgroup.operators.coreos.com/openshift-gitops-operator created
subscription.operators.coreos.com/openshift-gitops-operator created
```

```bash
oc wait --for=jsonpath='{.status.phase}'=Available argocd/openshift-gitops -n openshift-gitops --timeout=10m
```

For the first minute or two the `oc wait` fails with `not found`, because the operator has not
created the instance yet. Repeat it until it waits. On `lud` the instance was `Available` two
minutes after the `oc apply`:

```bash
oc get pods -n openshift-gitops
```

```
NAME                                                          READY   STATUS    RESTARTS   AGE
cluster-6fd95fbc9c-cdz7z                                      1/1     Running   0          2m
gitops-plugin-746cf889-77v76                                  1/1     Running   0          2m
openshift-gitops-application-controller-0                     1/1     Running   0          2m
openshift-gitops-applicationset-controller-85958f8c59-l7w5g   1/1     Running   0          2m
openshift-gitops-dex-server-76d87d5d65-swzgq                  1/1     Running   0          2m
openshift-gitops-redis-66d5c48c8c-gz242                       1/1     Running   0          2m
openshift-gitops-repo-server-6c855879dc-xfnc8                 1/1     Running   0          2m
openshift-gitops-server-7d5d47449-nmmc5                       1/1     Running   0          2m
```

Up to here nothing on the cluster is managed by git. Argo CD is running with no Applications.

## Note what is running

So that you can tell afterwards whether anything was touched:

```bash
oc get pods -A --no-headers | grep -vE 'Running|Completed'
oc get mcp
oc get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,STARTED:.status.startTime \
  --no-headers | sort > /tmp/pods-before.txt
```

The first command should print nothing. The second shows the node's rendered configuration.

## The root

```bash
oc apply -f clusters/yojimbo/root.yaml
oc get applications -n openshift-gitops -w
```

```
NAME                    SYNC STATUS   HEALTH STATUS
aap                     Synced        Healthy
aap-operator            Synced        Healthy
cert-manager            Synced        Healthy
cert-manager-operator   Synced        Healthy
cloudflare              Synced        Healthy
homepage                Synced        Healthy
local-path              Synced        Healthy
machine-config          Synced        Healthy
nfs-csi                 Synced        Healthy
nfs-csi-config          Synced        Healthy
synology-csi            Synced        Healthy
yojimbo                 Synced        Healthy
```

On `lud`, where everything was already running, all twelve were `Synced` and `Healthy` 43
seconds after the `oc apply`. The first sync of each found the objects it wanted already there
and equal to git, so it added its annotation to them and did nothing else.

On a new cluster this takes far longer and is not a straight line. The storage driver waits for
`iscsid`, which waits for a reboot. The certificates wait for cert-manager, which waits for its
operator. The platform waits for its operator, for a certificate and for a storage class.
Nothing in git orders them: each Application fails, backs off and tries again, as you saw on
Bahamut. Expect half an hour, most of it the platform.

> **Not yet run on a new cluster.** The path above from an empty cluster to twelve healthy
> Applications follows from how each part behaves, and each part was installed on `lud` from
> these manifests. The whole of it, in one go from `root.yaml`, has not been run.

## Was anything touched?

```bash
oc get pods -A --no-headers | grep -vE 'Running|Completed'
oc get mcp
oc get pods -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,STARTED:.status.startTime \
  --no-headers | sort > /tmp/pods-after.txt
diff /tmp/pods-before.txt /tmp/pods-after.txt
```

On an adopted cluster the rendered configuration is the same as before, and the `diff` shows
only pods that come and go by themselves, such as scheduled jobs. No storage, database or
application pod should have a new start time.

Then check from outside, the way a visitor would: the site answers, and the portal is up at its
route.

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://home.apps.lud.neokube.net/
```

```
200
```

## The same proof as on Bahamut

Delete something Argo CD owns and watch it return:

```bash
oc delete route homepage -n homepage
oc get route -n homepage
```

```
NAME       HOST/PORT                   PATH   SERVICES   PORT   TERMINATION     WILDCARD
homepage   home.apps.lud.neokube.net          homepage   http   edge/Redirect   None
```

From this point the cluster does what the branch says. The command that changes production is
`git push`.

Next: [Storage](05-storage.md)
