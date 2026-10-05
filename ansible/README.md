# ansible

Playbooks that AAP on lud (`https://aap.neokube.net`) runs against the homelab.

| File | What |
|---|---|
| `playbooks/liferay_backup.yml` | Nightly backup of neokube.net (Liferay on lud), with a restore test |
| `playbooks/aap_setup.yml` | The AAP objects that run it: credential, container group, inventory, project, job template, schedule |
| `playbooks/templates/backup-README.md.j2` | The restore instructions written into every backup |
| `files/lud-backup-access.yaml` | The cluster side: a `backup` service account limited to the job, and the NAS folder as a volume |
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

The service account can read pods, run commands in the pods of the `liferay` namespace, and read two secrets by
name. Running commands in a pod is a wide permission inside that namespace; it has none outside it.

### Restoring

Each backup carries its own `README.md` with the commands. Start there.

### Running it by hand

In AAP: launch "Back up neokube.net (Liferay on lud)".

From a laptop with `ansible-core`, the `kubernetes` Python package and this folder's collections
(`ansible-galaxy collection install -r collections/requirements.yml`), as a cluster administrator:

    export KUBECONFIG=~/sno/lud/auth/kubeconfig
    ansible-playbook playbooks/liferay_backup.yml \
      -e backup_root=$HOME/projects/backups/liferay-lud -e site_url=https://neokube.net

To see the restore test fail on purpose: add `-e restore_check_offset=1`.

## Setting AAP up

Once, and again whenever the objects need putting back.

    oc apply -f files/lud-backup-access.yaml

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
