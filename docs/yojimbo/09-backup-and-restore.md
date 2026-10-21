# Lab 9 — Backup and Restore

## What you will have at the end

A backup of the platform on the NAS, a look at what is in it, and proof that it restores: a
second platform made from the backup, beside the real one, holding what the real one held when
the backup was taken.

## What a backup is

Lab 7 ended with what git does not hold: everything inside the platform's databases. The
subscription, organizations, credentials, projects, job templates and their history exist only
in PostgreSQL. A reinstall from git gives you an empty platform. A backup is what puts the rest
back.

The operator makes one when asked, through one object, `AnsibleAutomationPlatformBackup`. The
object is an event, not a description of the platform, so it is created by hand and not kept in
git. Argo CD leaves alone what it did not create.

## Something to recognise

So that the restore has something to prove, make a change you will recognise: an organization,
through the gateway's API.

```bash
password=$(oc get secret aap-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d)
curl -s -u admin:"$password" -X POST -H 'Content-Type: application/json' \
  -d '{"name": "Restore check"}' https://aap.neokube.net/api/gateway/v1/organizations/ | jq -r .name
curl -s -u admin:"$password" https://aap.neokube.net/api/controller/v2/organizations/ | jq -c '[.results[].name]'
```

```
Restore check
["Default","Restore check"]
```

The gateway owns organizations and passes them on to the controller, so the second command,
which asks the controller, sees it too.

## Taking one

```bash
oc apply -f - <<'EOF'
apiVersion: aap.ansible.com/v1alpha1
kind: AnsibleAutomationPlatformBackup
metadata:
  name: aap-20261021
  namespace: aap
spec:
  deployment_name: aap
EOF
oc wait aapbackup/aap-20261021 -n aap --for=condition=Successful --timeout=20m
```

Name each backup by its date. `deployment_name` is the platform to back up, `aap`. It took three
minutes on `lud`. The operator backs the platform up part by part. Each part gets an object of
its own, and the platform's object lists them when it is done:

```bash
oc get aapbackup aap-20261021 -n aap -o jsonpath='{.status}' | jq 'del(.conditions)'
```

```json
{
  "backupClaim": "aap-backup-claim",
  "backupDirectory": "/backups/aap-openshift-backup-2026-10-21-20:05:17",
  "backupPostgres": true,
  "controllerBackup": "aap-20261021-controller",
  "mcpBackup": "aap-20261021-mcp",
  "metricsBackup": "aap-20261021-automationmetricsservice"
}
```

## Where it is

Each part writes to a claim of its own, made the first time and used again by every backup after
that, each backup in a directory named by its time:

```bash
oc get pvc -n aap | grep backup
```

```
aap-backup-claim               Bound   ...   5Gi   RWO   synology-iscsi
aap-controller-backup-claim    Bound   ...   5Gi   RWO   synology-iscsi
aap-mcp-backup-claim           Bound   ...   5Gi   RWO   synology-iscsi
aap-metrics-backup-claim       Bound   ...   5Gi   RWO   synology-iscsi
```

They are on `synology-iscsi`, the cluster's default storage class, so the backups are LUNs on
the NAS and outlive `lud`. They are 5 GiB each, the operator's default, and no object owns them:
deleting a backup object leaves both the claim and its files.

To look inside, mount one in a pod. The security settings are the ones OpenShift's `restricted`
profile asks for; without them the pod still runs, and sets off an alert:

```bash
oc run backup-ls -n aap --rm -i --restart=Never --image=registry.redhat.io/ubi9-minimal:latest \
  --overrides='{"spec": {
    "securityContext": {"runAsNonRoot": true, "seccompProfile": {"type": "RuntimeDefault"}},
    "containers": [{"name": "backup-ls", "image": "registry.redhat.io/ubi9-minimal:latest",
      "command": ["ls", "-R", "/gateway", "/controller"],
      "securityContext": {"allowPrivilegeEscalation": false, "capabilities": {"drop": ["ALL"]}},
      "volumeMounts": [{"name": "g", "mountPath": "/gateway"}, {"name": "c", "mountPath": "/controller"}]}],
    "volumes": [{"name": "g", "persistentVolumeClaim": {"claimName": "aap-backup-claim"}},
                {"name": "c", "persistentVolumeClaim": {"claimName": "aap-controller-backup-claim"}}]}}'
```

```
/controller:
lost+found
tower-openshift-backup-2026-10-21-190818
tower-openshift-backup-2026-10-21-200608
...
/controller/tower-openshift-backup-2026-10-21-200608:
awx_object
secrets.yml
tower.db

/gateway:
aap-openshift-backup-2026-10-21-19:06:06
aap-openshift-backup-2026-10-21-20:05:17
lost+found
...
/gateway/aap-openshift-backup-2026-10-21-20:05:17:
aap.db
aap_object
secrets.yml
```

| File | What it is |
| ---- | ---------- |
| `aap.db`, `tower.db` | `pg_dump` of the gateway's and the controller's databases |
| `aap_object`, `awx_object` | The object's spec at the time, `platform.yaml` as the operator saw it |
| `secrets.yml` | The secrets the platform runs on: the admin password, the database passwords, and the key that encrypts credentials in the database |

The last row is why a backup is a secret itself. A database dump without its encryption key
restores, but every stored credential in it is unreadable. With the key, anyone holding the
backup holds every credential. On this cluster that means the LUNs on the NAS.

The directories from earlier in the day, `19:06:06` and `190818`, are `aap-pre-27`, the backup
Lab 8 took before the upgrade, in the same claims.

## Restoring beside the platform

A restore is the other object, `AnsibleAutomationPlatformRestore`. It names a backup and a
`deployment_name` for the platform it makes. It always makes a new platform. Given a new name,
that platform is a second one, next to the first, in the same namespace. That is the way to
check a backup without touching the real platform, and the way to look at old data.

A second platform must not take the first one's address, and it is thrown away, so the restore
changes four things in the backed-up spec with `spec_overrides`:

| Override | Why |
| -------- | --- |
| `route_host: aap-restore.apps.lud.neokube.net` | `aap.neokube.net` is taken. A name under `*.apps` is covered by the router's own certificate and needs no DNS record |
| `route_tls_secret: ""` | The real platform's certificate is for `aap.neokube.net`. Empty means the router's |
| `database.postgres_storage_class: local-path` | A throwaway database on `lud`'s disk, gone with its claim |
| `mcp` and `metrics` `disabled: true` | Less to start |

### A NetworkPolicy first

AAP 2.7 puts NetworkPolicies around every part of the platform. One of them is a problem for a
restore next to a running platform. The real platform's `aap-db-management` policy lets the
operator's database pods talk to PostgreSQL, but only to the real platform's:

```bash
oc get networkpolicy aap-db-management -n aap -o jsonpath='{.spec.podSelector}{"\n"}{.spec.egress[1]}{"\n"}' | jq -c .
```

```
{"matchLabels":{"app.kubernetes.io/component":"aap","app.kubernetes.io/managed-by":"aap-operator"}}
{"ports":[{"port":5432,"protocol":"TCP"}],"to":[{"podSelector":{"matchLabels":{"app.kubernetes.io/component":"database","app.kubernetes.io/instance":"postgres-15-aap"}}}]}
```

Its selector does not say which platform, so it also catches the pod the restore makes to load
the dump, `aap-restore-db-management`. That pod can then reach only `postgres-15-aap`, not the
new database it is meant to fill. The first time this ran on `lud`, the restore retried *Restore
database* for half an hour with *unknown playbook failure*, the real reason hidden by `no_log`,
until a connection test from inside the pod showed it:

```bash
oc exec -n aap aap-restore-db-management -- \
  bash -c 'timeout 5 bash -c "</dev/tcp/aap-restore-postgres-15/5432" && echo open'
```

```
command terminated with exit code 124
```

NetworkPolicies add up: a pod may go wherever any policy that selects it allows. One more,
selecting only the restore's pod, lets it reach its own database. Make it before the restore:

```bash
oc apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restore-workaround-db-egress
  namespace: aap
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: aap-restore
      app.kubernetes.io/component: aap
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/instance: postgres-15-aap-restore
      ports:
        - {port: 5432, protocol: TCP}
EOF
```

The controller's own database pod has a wider policy, port 5432 to anywhere, and needs nothing.
A restore that replaces the platform under its own name, below, does not hit this.

### The restore

```bash
oc apply -f - <<'EOF'
apiVersion: aap.ansible.com/v1alpha1
kind: AnsibleAutomationPlatformRestore
metadata:
  name: aap-restore
  namespace: aap
spec:
  deployment_name: aap-restore
  backup_source: CR
  backup_name: aap-20261021
  spec_overrides:
    route_host: aap-restore.apps.lud.neokube.net
    route_tls_secret: ""
    database:
      postgres_storage_class: local-path
    mcp:
      disabled: true
    metrics:
      disabled: true
EOF
oc get pods -n aap -w | grep --line-buffered aap-restore
```

In order, from when the database could be reached:

| After | What happens |
| ----- | ------------ |
| 0:00 | `aap-restore-postgres-15-0` runs empty, and `aap-restore-db-management` loads the gateway's dump into it |
| 2:00 | One `db-management` pod per part loads the controller's, MCP's and the metrics service's |
| 3:00 | The restore makes `AnsibleAutomationPlatform/aap-restore` from `aap_object` and the overrides, and the operator installs it like any other |
| 14:30 | `oc get aap aap-restore -n aap` reports `Successful`, version `2.7.20261019` |

MCP came up anyway: its part has a restore of its own, which does not read the override. The
metrics service did not.

The second platform uses the first one's secrets, because they are named in the spec it
restored: the same `aap-admin-password`, the same encryption key. The same password signs in to
both.

### Proving it

The organization is there:

```bash
host=aap-restore.apps.lud.neokube.net
curl -s https://$host/api/gateway/v1/ping/ | jq -r .version
curl -s -u admin:"$password" https://$host/api/controller/v2/organizations/ | jq -c '[.results[].name]'
```

```
2.7
["Default","Restore check"]
```

That alone does not show the second platform is separate: its gateway could be passing the
question on to the first one's controller. Delete the organization from the real platform, and
ask both again:

```bash
id=$(curl -s -u admin:"$password" "https://aap.neokube.net/api/gateway/v1/organizations/?name=Restore+check" \
  | jq -r '.results[0].id')
curl -s -u admin:"$password" -X DELETE https://aap.neokube.net/api/gateway/v1/organizations/$id/
for h in aap.neokube.net $host; do
  echo "$h $(curl -s -u admin:"$password" https://$h/api/controller/v2/organizations/ | jq -c '[.results[].name]')"
done
```

```
aap.neokube.net ["Default"]
aap-restore.apps.lud.neokube.net ["Default","Restore check"]
```

Two platforms, two databases, and the backup's content in the second one.

### Throwing it away

Delete the platform and the restore object. Their operators remove what they made, but not
everything:

```bash
oc delete aap aap-restore -n aap
oc delete aaprestore aap-restore -n aap
oc get pvc,secret,networkpolicy -n aap -o name | grep restore
```

```
persistentvolumeclaim/postgres-15-aap-restore-postgres-15-0
secret/aap-restore-controller-postgres-configuration
secret/aap-restore-controller-receptor-ca
secret/aap-restore-controller-receptor-work-signing
secret/aap-restore-gateway-postgres-configuration
secret/aap-restore-metrics-postgres-configuration
networkpolicy.networking.k8s.io/restore-workaround-db-egress
```

These have no owner. Delete them by name, and **not** the secrets without `restore` in their
name, which the real platform still uses:

```bash
oc get pvc,secret,networkpolicy -n aap -o name | grep restore | xargs oc delete -n aap
```

## Restoring over the platform

> **Not yet run as written.** The steps below follow from the restore above and from how the
> Applications are built. The sequence has not been run on `lud`.

When the platform itself is lost, or its database is, the restore makes a new `aap` in its place.
Two things are different from the restore beside it.

**Argo CD has to let go first.** The `aap` Application has `selfHeal`: delete the platform and
Argo CD makes it again within seconds, empty, and the restore then finds a platform of that name
already there. The Application is in turn kept by the root, so changing the Application by hand
lasts only until the root's next sync. Change it in git: take `aap.yaml` out of
`clusters/yojimbo/apps/kustomization.yaml`, commit and push. The root prunes the Application.
The Applications have no `resources-finalizer`, so removing the Application leaves the platform
running. Nothing manages it now.

**The old database goes with it.** Delete the platform, then its database's claim, so that the
restore starts a new one:

```bash
oc delete aap aap -n aap
oc delete pvc postgres-15-aap-postgres-15-0 -n aap
```

`synology-iscsi` keeps the LUN on the NAS after the claim is gone (Lab 5), which is one more
copy, until you delete it there.

Then restore with the real name and no overrides. The backup's spec is `platform.yaml`:

```bash
oc apply -f - <<'EOF'
apiVersion: aap.ansible.com/v1alpha1
kind: AnsibleAutomationPlatformRestore
metadata:
  name: aap-from-20261021
  namespace: aap
spec:
  deployment_name: aap
  backup_source: CR
  backup_name: aap-20261021
EOF
```

No NetworkPolicy is needed: the restore's pod is the one `aap-db-management` was written for.
When `aap` is `Successful`, put `aap.yaml` back in the kustomization, commit and push. Argo CD
finds a platform that matches git and adopts it.

## Keeping backups

Nothing here takes backups on a schedule. The operator does not, and the job that backed up the
site every night while it ran on Liferay is gone. Taking one is one object, so a schedule is
anything that makes that object once a day with the date in its name: a `CronJob` with a
service account allowed to create `AnsibleAutomationPlatformBackup`, or a job template in the
platform itself. Each backup adds a directory to the same 5 GiB claims. Old directories have to
be removed by whoever schedules the new ones.

To delete one backup, delete its object with `clean_backup_on_delete: true` set on it, or
delete its directories by hand through a pod like the one above. Deleting the object alone
keeps the files.

## What you have

A platform whose configuration is in git and whose content is in backups on the NAS, a restore
proved on the same cluster, and the steps for the day the platform itself is lost.

Next: [From Bahamut to Yojimbo](10-from-bahamut-to-yojimbo.md)
