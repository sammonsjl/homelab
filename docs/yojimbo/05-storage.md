# Lab 5 — Storage

## What you will have at the end

An understanding of the five Applications that give the cluster its three kinds of volume, and
of which data belongs on which.

## Three classes

OpenShift Local came with storage. A cluster installed on your own machine has none: a claim for
a volume stays `Pending` until something can make one. Yojimbo has three things that can.

```bash
oc get storageclass
```

```
NAME                       PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path                 rancher.io/local-path   Delete          WaitForFirstConsumer   false                  9d
nfs-csi                    nfs.csi.k8s.io          Retain          Immediate              false                  7d21h
synology-iscsi (default)   csi.san.synology.com    Retain          Immediate              true                   7d21h
```

| Class            | A volume is              | Lives   | Use it for                                                       |
| ---------------- | ------------------------ | ------- | ---------------------------------------------------------------- |
| `synology-iscsi` | A LUN on the NAS, attached to the node as a disk | On the NAS | Databases. One pod, a real block device, survives the node |
| `nfs-csi`        | A folder on one NFS share | On the NAS | Files that several pods share, or that you want to read from outside: documents, backups, the image registry |
| `local-path`     | A folder on the node's own disk | On the node | Data a rebuild can lose and regenerate, such as a search index |

The question to ask of any volume is what happens to it when the node's disk is wiped. With one
node, that is the same question as what happens when the cluster is reinstalled. `Retain` on the
two NAS classes means that deleting a claim leaves the data on the NAS.

What uses them today:

```bash
oc get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CAPACITY:.status.capacity.storage,STORAGECLASS:.spec.storageClassName
```

```
NAMESPACE                  NAME                            CAPACITY   STORAGECLASS
aap                        neokube-backups                 20Gi       nfs-csi
aap                        postgres-15-aap-postgres-15-0   8Gi        synology-iscsi
ghost                      data-mysql-0                    5Gi        synology-iscsi
ghost                      ghost-content                   1Gi        synology-iscsi
openshift-image-registry   image-registry-nfs              30Gi       nfs-csi
quay                       garage                          100Gi      local-path
quay                       registry-quay-postgres-13       50Gi       local-path
uptime-kuma                uptime-kuma-pvc                 1Gi        synology-iscsi
```

neokube.net's two volumes, its database and Ghost's content folder (the theme and the pictures),
are on the NAS: neither asks for a class, so they get the default. Quay's are on the node's own
disk on purpose: everything in the mirror is a copy that `oc-mirror` makes again (Lab 7).

## iSCSI needs something from the node

The Synology driver attaches a LUN with the node's own `iscsiadm`, which talks to the node's own
`iscsid`. Red Hat CoreOS ships that service switched off. The node's operating system is not
changed by logging in to it. It is changed by a `MachineConfig`, and that is an object like any
other, so it is in git:

```bash
cat infrastructure/machine-config/yojimbo/iscsid.yaml
```

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-master-iscsid
  labels:
    machineconfiguration.openshift.io/role: master
spec:
  config:
    ignition:
      version: 3.2.0
    systemd:
      units:
        - name: iscsid.service
          enabled: true
```

The role is `master` because a single node is a control plane node that also runs workloads.
Applying it reboots the node, once.

```bash
oc get machineconfig 99-master-iscsid
oc debug node/lud -q -- chroot /host systemctl is-active iscsid
```

```
active
```

## The Synology driver

`infrastructure/synology-csi` is a base and an overlay, like the portal. The base is the driver
as upstream publishes it. The overlay holds what OpenShift and this node need changed:

```bash
cat infrastructure/synology-csi/yojimbo/kustomization.yaml
```

| Change                                  | Why                                                                                   |
| --------------------------------------- | ------------------------------------------------------------------------------------- |
| A binding to the `privileged` SCC       | The driver's pods use the host's network and paths. OpenShift refuses that by default |
| `--chroot-dir=/host` on the node plugin | The driver runs the host's `iscsiadm`, not the one in its image. A newer `iscsiadm` talking to an older `iscsid` hangs the daemon, and nothing checks the versions |
| The default-class annotation            | A claim that names no class gets a LUN on the NAS                                      |

A security context constraint, or SCC, is OpenShift's rule for what a pod may ask of the node. A
manifest written for plain Kubernetes that wants host access is refused until its service
account is bound to an SCC that allows it. You will see the same binding in every storage
folder here.

```bash
oc get pods -n synology-csi
```

```
NAME                        READY   STATUS    RESTARTS   AGE
synology-csi-controller-0   4/4     Running   0          7d21h
synology-csi-node-jnqpm     2/2     Running   0          7d21h
```

## The NFS driver: a Helm chart in Argo CD

The NFS driver is published as a Helm chart. Its Application names a chart where the others name
a folder:

```bash
cat clusters/yojimbo/apps/nfs-csi.yaml
```

```yaml
  source:
    repoURL: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
    chart: csi-driver-nfs
    targetRevision: 4.13.4
    helm:
      releaseName: nfs-csi
```

Argo CD renders the chart and applies the result. There is no Helm release on the cluster, and
`helm list` shows nothing. Here `targetRevision` is the chart's version, so upgrading the driver
is a one-line commit.

The chart knows nothing about SCCs or about my NAS, so a second Application, `nfs-csi-config`,
adds the binding and the storage class from `infrastructure/nfs-csi/yojimbo`. The class makes one
folder per claim, named after its namespace and claim:

```yaml
parameters:
  server: 192.168.1.4
  share: /volume1/k8s-nfs-yojimbo
  subDir: lud/${pvc.metadata.namespace}-${pvc.metadata.name}
```

A folder name you can predict is what lets a reinstalled cluster find the old data again.

## Local path

`infrastructure/local-path` shows a third way to bring something in: a Kustomize folder whose
resource is a URL.

```yaml
resources:
  - github.com/rancher/local-path-provisioner/deploy?ref=v0.0.37
  - scc.yaml
```

Upstream's manifests are fetched at that tag, and the patches below them change three things:
where on the node the folders go, that this class is not the default, and the namespace's pod
security level.

## What you have seen

Three ways for an Application to get its manifests, all in one cluster: files in the repository,
a Helm chart, and a remote Kustomize base. And one rule that held each time: what OpenShift
needs added sits in the cluster's overlay, beside the upstream manifests, never inside them.

Next: [Certificates and the Tunnel](06-certificates-and-the-tunnel.md)
