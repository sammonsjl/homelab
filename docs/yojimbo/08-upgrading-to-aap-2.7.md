# Lab 8 — Upgrading to AAP 2.7

## What you will have at the end

The platform of Lab 7 on AAP 2.7, upgraded through git: a backup taken first, the 2.7 images in
the mirror, and the operator moved to the new version by a one-line commit.

## A version is a channel

Lab 7 ended with how updates within 2.6 arrive: run `oc-mirror` again, and the operator follows
its catalog. A new minor version does not arrive that way. Red Hat publishes each minor version
of the operator as a channel of its own, and a Subscription follows exactly one channel. Red
Hat's catalog lists them:

```bash
oc get packagemanifest -n openshift-marketplace -l catalog=redhat-operators \
  --field-selector metadata.name=ansible-automation-platform-operator -o json \
  | jq -r '.items[0].status.channels[] | "\(.name)  \(.currentCSV)"'
```

```
stable-2.6  aap-operator.v2.6.0-0.1791996347
stable-2.6-cluster-scoped  aap-operator.v2.6.0-0.1791996292
stable-2.7  aap-operator.v2.7.0-0.1792432839
stable-2.7-cluster-scoped  aap-operator.v2.7.0-0.1792432849
```

The `-cluster-scoped` channels are for an operator installed for all namespaces. This one
manages only `aap` (its OperatorGroup says so), so its channel is `stable-2.7`.

Moving from one channel to the other is allowed only if the new version says it may replace the
one installed. Each version carries the range it replaces:

```bash
oc get packagemanifest -n openshift-marketplace -l catalog=redhat-operators \
  --field-selector metadata.name=ansible-automation-platform-operator -o json \
  | jq -r '.items[0].status.channels[] | select(.name=="stable-2.7")
           | .currentCSVDesc.annotations["olm.skipRange"]'
oc get subscription ansible-automation-platform-operator -n aap -o jsonpath='{.status.installedCSV}{"\n"}'
```

```
>=2.6.0-0 <2.7.1
aap-operator.v2.6.0-0.1789677985
```

Any 2.6 is in the range, so OLM goes from the installed version to the newest 2.7 in one step,
with no stop at the newest 2.6.

## What changes

Two questions before touching anything: does the new version need images the mirror does not
know about, and does it change the kinds of object the platform is described with? Compare the
images each channel names, with the version number taken out of the path:

```bash
images() {
  oc get packagemanifest -n openshift-marketplace -l catalog=redhat-operators \
    --field-selector metadata.name=ansible-automation-platform-operator -o json \
    | jq -r --arg c $1 '.items[0].status.channels[] | select(.name==$c) | .currentCSVDesc.relatedImages[]' \
    | sed -E 's/[@:].*//; s#registry.redhat.io/##; s#-2[0-9]/#-2x/#' | sort -u
}
diff <(images stable-2.6) <(images stable-2.7)
```

```
18a19,20
> ansible-automation-platform-2x/metrics-service-rhel9
> ansible-automation-platform-2x/metrics-service-rhel9-operator
21,22d22
< ansible-automation-platform-tech-preview/metrics-service-rhel9
< ansible-automation-platform-tech-preview/metrics-service-rhel9-operator
24d23
< openshift4/ose-kube-rbac-proxy-rhel9
```

Three things:

| Change | What it means here |
| ------ | ------------------ |
| Every image moves from `ansible-automation-platform-26/` to `-27/` | The mirror set needs the new path, or the node fetches 2.7 from Red Hat and not from Quay |
| The metrics service leaves `tech-preview` | It is supported in 2.7, and the platform now runs it by default: three more pods |
| `ose-kube-rbac-proxy` is gone | The operator's managers lose a sidecar each |

PostgreSQL stays `postgresql-15` and Redis `redis-6`: there is no database upgrade between major
versions. And the kinds are the same 29:

```bash
kinds() {
  oc get packagemanifest -n openshift-marketplace -l catalog=redhat-operators \
    --field-selector metadata.name=ansible-automation-platform-operator -o json \
    | jq -r --arg c $1 '.items[0].status.channels[] | select(.name==$c)
                        | .currentCSVDesc.customresourcedefinitions.owned[].kind' | sort
}
diff <(kinds stable-2.6) <(kinds stable-2.7) && echo same
```

```
same
```

So `platform.yaml` does not change. The upgrade is two commits: the mirror, then the channel.

## Back up first

OLM does not go back. Once 2.7 has migrated the database, the way back to 2.6 is a reinstall
from a backup. Take one now. It is one object, and [Lab 9](09-backup-and-restore.md) explains
what it holds and how to restore from it:

```bash
oc apply -f - <<'EOF'
apiVersion: aap.ansible.com/v1alpha1
kind: AnsibleAutomationPlatformBackup
metadata:
  name: aap-pre-27
  namespace: aap
spec:
  deployment_name: aap
EOF
oc wait aapbackup/aap-pre-27 -n aap --for=condition=Successful --timeout=20m
```

It took five minutes on `lud`. It is made by hand and not kept in git: it is a one-off event,
not a description of the platform, and Argo CD leaves alone what it did not create.

## The mirror

Ask the mirror for the new channel, and send the new path to Quay. The first edit is in
`infrastructure/aap/operator/imageset-config.yaml`, the second in `mirror.yaml`, above the `-26`
entry:

```bash
sed -i -E 's/(Channel|name): stable-2\.6/\1: stable-2.7/' infrastructure/aap/operator/imageset-config.yaml
```

```yaml
    - source: registry.redhat.io/ansible-automation-platform-27
      mirrors: [quay.neokube.net/ansible-automation-platform-27]
```

The `-26` entry stays until the upgrade is done and checked: the 2.6 pods still running pull
through it if they restart. The dry run, then the commit:

```bash
oc diff -k infrastructure/aap/operator | grep -E '^[-+] ' | grep -v -e tracking-id -e generation
```

```
+    - quay.neokube.net/ansible-automation-platform-27
+    source: registry.redhat.io/ansible-automation-platform-27
+  - mirrors:
```

Only the mirror set changes. `imageset-config.yaml` is not applied to the cluster, so it does
not show.

```bash
git commit -am "AAP: mirror the stable-2.7 channel into Quay"
git push
```

Within three minutes Argo CD applies the mirror set, and the Machine Config Operator writes it
into the node's `registries.conf`. That took 40 seconds and did not restart the node:

```bash
oc get mcp master -w
oc debug node/lud -- chroot /host grep -A4 'platform-27' /etc/containers/registries.conf
```

Then fill the mirror, with the logins and the command of Lab 7:

```bash
oc-mirror --v2 -c infrastructure/aap/operator/imageset-config.yaml \
  --workspace file://$HOME/.cache/oc-mirror/aap docker://quay.neokube.net --image-timeout 120m
```

```
 ✓  28 / 28 operator images mirrored successfully
mirror time     : 10m17.316085926s
```

Ten minutes, not three hours. 2.6 and 2.7 are built on the same base images, and Quay already
held most of their layers. A first mirror into an empty Quay takes as long as Lab 7's.

The copy replaces the catalog behind the same tag, and it now holds `stable-2.7` only. The
catalog's pod notices within ten minutes:

```bash
oc get packagemanifest -n openshift-marketplace -l catalog=aap-mirror -o json \
  | jq -r '.items[0].status.channels[] | "\(.name)  \(.currentCSV)"'
```

```
stable-2.7  aap-operator.v2.7.0-0.1792432839
```

From this moment the Subscription, still on `stable-2.6`, reports that it cannot find its
channel:

```bash
oc get subscription ansible-automation-platform-operator -n aap \
  -o jsonpath='{.status.conditions[?(@.type=="ResolutionFailed")].message}{"\n"}'
```

```
constraints not satisfiable: no operators found in channel stable-2.6 of package ansible-automation-platform-operator in the catalog referenced by subscription ansible-automation-platform-operator, ...
```

Nothing breaks: the installed operator keeps running. It only means the next commit is due.

## The upgrade

One line in `infrastructure/aap/operator/operator.yaml`:

```bash
sed -i 's/channel: stable-2\.6/channel: stable-2.7/' infrastructure/aap/operator/operator.yaml
oc diff -k infrastructure/aap/operator | grep -E '^[-+] ' | grep -v -e tracking-id -e generation
```

```
-  channel: stable-2.6
+  channel: stable-2.7
```

```bash
git commit -am "AAP: upgrade the operator to stable-2.7"
git push
```

Then watch, from three terminals. Times are from `lud`, counted from the push:

```bash
oc get csv -n aap -w
oc get pods -n aap -w
oc get aap aap -n aap -w -o jsonpath='{.status.version}{"  "}{.status.conditions[?(@.type=="Successful")].status}{"\n"}'
```

| After | What happens |
| ----- | ------------ |
| 0:30 | OLM makes an `InstallPlan` for `aap-operator.v2.7.0-0.1792432839` and approves it (the Subscription says `Automatic`). The 2.6 CSV goes to `Replacing` |
| 2:40 | Seven new manager pods have pulled their images; the 2.7 CSV is `Succeeded` and the 2.6 one is gone |
| 2:50 | The 2.7 operator starts reconciling the platform. Its `Successful` condition goes to `False` |
| 3:15 | PostgreSQL and Redis restart on their new images. The gateway answers `503` until the database is back |
| 7:20 | The controller's migration job, `aap-controller-migration-4.8.12`, moves the database to 2.7 |
| 9:40 | The new gateway is up. The ping says `2.7` |
| 12:00 | The metrics service's three pods start, and the controller restarts once more to use it |
| 17:50 | The platform's `Successful` condition is `True` again, with version `2.7.20261019` |

The API was down for about four minutes, while the database restarted. Two other things showed
up along the way on `lud` and went away by themselves:

- The platform's `Failure` condition turned `True` once, with *unknown playbook failure*. The
  controller's operator had tried to reach the database while it was restarting. It retried, and
  the next attempt succeeded.
- A few of the managers restarted with *leader election lost*. With every pod on the one node
  restarting at once, the API server answered too slowly for them to renew their lease.

## Checking it

```bash
password=$(oc get secret aap-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d)
curl -s https://aap.neokube.net/api/gateway/v1/ping/ | jq -r .version
curl -s -u admin:"$password" https://aap.neokube.net/api/controller/v2/ping/ | jq -r .version
oc get pods -n aap -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sed -E 's/@.*//' | sort | uniq -c
```

```
2.7
4.8.12
```

Every AAP image is from `ansible-automation-platform-27`, and only the `migration-4.7.17` pod,
finished, still names a `-26` one. To see that they came from Quay, ask Quay's log, as in Lab 7:

```bash
oc logs -n quay deploy/registry-quay-app --since=30m \
  | grep -o '"GET /v2/ansible-automation-platform-27/[a-z0-9-]*/manifests' | sort | uniq -c
```

One line per image, and Argo CD shows every Application `Synced` and `Healthy`.

The metrics service is the one new thing on the node: three pods asking 50m and 256 MiB each.
The managers' lost sidecars give most of it back. The node's CPU requests went from 5093m to
5183m, memory from 19651 MiB to 20035 MiB:

```bash
oc describe node lud | grep -A5 'Allocated resources'
```

## What is left of 2.6

- The `-26` and `tech-preview` entries in `mirror.yaml`. Nothing pulls through them any more.
  Delete them in a commit of their own, once you no longer want a way back to 2.6.
- 2.6's images in Quay, about 35 GB on `lud`'s disk. The new catalog no longer names them.
- The backup `aap-pre-27`, of the platform as it was on 2.6. Lab 9 shows how to restore a
  backup and how to delete one.

The way back, if 2.7 had failed: revert both commits, delete the platform and the operator as in
Lab 7's [Throwing it away](07-the-automation-platform.md#throwing-it-away), mirror 2.6 again,
let Argo CD install it, and restore the backup into it. That has not been run here.

Next: [Backup and Restore](09-backup-and-restore.md)
