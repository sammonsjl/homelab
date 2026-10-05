# ansible

Playbooks that AAP on lud (`https://aap.neokube.net`) runs against the homelab.

| File | What |
|---|---|
| `playbooks/liferay_backup.yml` | Nightly backup of neokube.net (Liferay on lud), with a restore test |
| `playbooks/liferay_restore.yml` | Restore: over the live site on demand, and into a second Liferay every week as a test |
| `playbooks/aap_setup.yml` | The AAP objects that run them: credential, container group, inventory, project, job templates, schedules |
| `playbooks/templates/backup-README.md.j2` | The restore instructions written into every backup |
| `files/lud-restore-rehearsal.yaml` | The restore test's namespace and what the `backup` service account may do in it |
| `files/lud-backup-access.yaml` | The cluster side: a `backup` service account limited to these jobs, and the NAS folder as a volume |
| `collections/requirements.yml` | `kubernetes.core`, for running the backup outside AAP (AAP's execution environment has it) |

## The backup

Every night at 02:30 (Chicago) AAP runs `liferay_backup.yml` in a job pod on lud
that has the NAS folder mounted at `/backups`
(`192.168.1.4:/volume1/homes/jamie/projects/backups/liferay-lud`, which is
`~/projects/backups/liferay-lud` on the laptop).

1. Checks the folder is writable and Liferay's three pods are ready.
2. Counts the rows of the content tables in the live database.
3. `pg_dump` in the database pod; copies the dump to the NAS and checks the copy's SHA-256 against the pod's.
4. Archives the document library in Liferay's pod; copies and checks it the same way, and that every file is in it.
5. Writes the two secrets a restore needs, and which image was running.
6. **Restore test:** sends the dump back *from the NAS*, restores it into a scratch database, counts the same
   tables, compares, and drops the scratch database.
7. Asks Liferay for the home page and a lesson and checks their titles.
8. Writes `summary.json`, `README.md` (how to restore) and `SHA256SUMS`, renames the folder from
   `.incoming-<stamp>` to `<stamp>` (UTC) and points `latest` at it.
9. Removes all but the newest fourteen.

A failure anywhere fails the job, publishes nothing and leaves `latest` on the last good backup. The
half-written `.incoming-*` folder is removed by the next run.

Not backed up: the search index (a reindex rebuilds it) and the image, chart values and site sources (in git).
The dump and the document archive are taken seconds apart, not in one snapshot.

The service account works only in the `liferay` and `liferay-restore` namespaces. In `liferay` it can read pods
and statefulsets, run commands in the pods, read two secrets by name, and (for the restore job) scale and patch
the statefulsets. Running commands in a pod and patching a statefulset are wide permissions inside that
namespace; it has none outside these two.

## Restoring neokube.net

In AAP: launch **"Restore neokube.net (Liferay on lud)"**. It asks two things:

- **Backup to restore:** a folder name under `~/projects/backups/liferay-lud` (UTC, such as `2026-10-05-1636`),
  or `latest`.
- **Type neokube.net to confirm.** Anything else and the job stops before touching the site.

It then runs `liferay_restore.yml` against the live site:

1. Checks the backup against its `SHA256SUMS`.
2. **Saves what the live site holds right now** (database dump and document library) to
   `pre-restore/<stamp>/` next to the backups; the newest three are kept. If the site is too broken to dump, it
   says so in the result and goes on.
3. Replaces the document library, stops Liferay, replaces the database, and starts Liferay with the search
   index being rebuilt.
4. Checks the rows, the documents, three pages and that the home page lists every lesson again.
5. Takes the reindex setting off again (one more restart of Liferay) and writes `last-restore.json`.

The site is down for about ten minutes. To go back to what was there before a restore, follow the `README.md`
of any backup by hand, using the two files in `pre-restore/<stamp>/` instead of that backup's.

Liferay's container has to be able to start for the job to reach its data volume. If it cannot start at all,
restore by hand: each backup carries its own `README.md` with the commands.

## The restore test

Every Sunday at 03:30 (Chicago), and whenever you launch "Test the restore of neokube.net (rehearsal copy on
lud)", AAP runs the same `liferay_restore.yml` against the **rehearsal copy**, so the restore job is exercised
every week without touching the live site:
a second Liferay in the namespace `liferay-restore`, with its own PostgreSQL and search server on lud's local
disk, scaled to 0 between tests.

1. Checks the newest backup against its `SHA256SUMS`.
2. Starts the rehearsal copy.
3. Replaces its document library with the backup's, stops Liferay, replaces its database with the dump, starts
   Liferay.
4. Checks: the content tables hold the rows the backup recorded, every document is back, the home page, a
   lesson and Social Office answer with the right titles, and the home page lists every lesson again (which
   needs the search index rebuilt).
5. Stops the rehearsal copy and writes `last-restore-test.json` next to the backups.

It takes about four minutes and about 4 GiB of lud's memory while it runs. The live site is not touched.

### Making the rehearsal copy

Once (it is there since 2026-10-05). From the Liferay workspace, with the secrets of any backup:

    oc apply -f files/lud-restore-rehearsal.yaml
    for s in liferay-database liferay-default; do
      sed 's/"namespace": "liferay"/"namespace": "liferay-restore"/' ~/projects/backups/liferay-lud/latest/secrets/$s.json | oc apply -f -
    done
    oc adm policy add-scc-to-user nonroot-v2 --serviceaccount liferay-default --namespace liferay-restore
    oc policy add-role-to-group system:image-puller system:serviceaccounts:liferay-restore --namespace liferay
    sed 's/storageClassName: synology-iscsi/storageClassName: local-path/' deploy/lud/values.yaml > /tmp/values-restore.yaml
    helm upgrade --install liferay <liferay-portal>/cloud/helm/default --namespace liferay-restore \
      --values /tmp/values-restore.yaml --set image.tag=<the tag in the backup's release.json>
    oc scale --namespace liferay-restore statefulset --all --replicas=0

It has no Route, so it is not reachable from outside the cluster. When the live site moves to a new image,
repeat the `helm upgrade` line with the new tag, then the `oc scale` line.

### Running the backup by hand

In AAP: launch "Back up neokube.net (Liferay on lud)".

From a laptop with `ansible-core`, the `kubernetes` Python package and this folder's collections
(`ansible-galaxy collection install -r collections/requirements.yml`), as a cluster administrator:

    export KUBECONFIG=~/sno/lud/auth/kubeconfig
    ansible-playbook playbooks/liferay_backup.yml \
      -e backup_root=$HOME/projects/backups/liferay-lud -e site_url=https://neokube.net

To see the restore test fail on purpose: add `-e restore_check_offset=1`.

## Setting AAP up

Once, and again whenever the objects need putting back.

    oc apply -f files/lud-backup-access.yaml -f files/lud-restore-rehearsal.yaml

`aap_setup.yml` uses the `ansible.controller` collection. AAP's execution environment image has it, so the
simplest way is to run the playbook in that image (`podman run`, `ansible-navigator`, or a pod on lud) with:

    export CONTROLLER_HOST=https://aap.neokube.net CONTROLLER_USERNAME=admin CONTROLLER_PASSWORD=...
    export LUD_BACKUP_TOKEN=$(oc get secret backup-token -n liferay -o jsonpath='{.data.token}' | base64 -d)
    export LUD_BACKUP_CA=$(oc get secret backup-token -n liferay -o jsonpath='{.data.ca\.crt}' | base64 -d)
    ansible-playbook playbooks/aap_setup.yml

The project pulls this repository from GitHub (`main`), so the playbooks have to be pushed before the job
template can be created. `--tags base` creates only what does not need that.

## lud's storage

The backup assumes lud's volumes are on the NAS, as on the other clusters:

- `infrastructure/configs/lud/synology-csi` — the base synology-csi with three changes for single-node OpenShift on
  RHCOS (host `iscsiadm` through `--chroot-dir=/host`, the privileged SCC, no ExternalSecret). `iscsid` is enabled
  on the node by a MachineConfig, and `client-info-secret` is created by hand from Vault (`secrets/synology`).
- `infrastructure/controllers/lud/nfs-csi` — the `nfs-csi` class for lud. The driver is the same chart and version
  as `infrastructure/controllers/base/nfs-csi`, installed with Helm because lud has no Flux:

      helm upgrade --install nfs-csi csi-driver-nfs/csi-driver-nfs --version 4.13.4 -n kube-system
      oc adm policy add-scc-to-user privileged -z csi-nfs-controller-sa -z csi-nfs-node-sa -n kube-system

Liferay's PostgreSQL and data volume and AAP's PostgreSQL are on `synology-iscsi`; the image registry is on
`nfs-csi`; Liferay's search index stays on lud's own disk.
