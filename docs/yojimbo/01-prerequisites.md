# Lab 1 — Prerequisites

## What you will have at the end

A list of what the production cluster needs from outside itself, and your fork's copy of
`clusters/yojimbo` and its folders edited to describe your machine, your storage and your names
in place of mine.

## What Yojimbo is

Yojimbo is my production cluster: single-node OpenShift on one real machine, `lud`, a mini PC
with 8 threads and 32 GB of RAM. It serves [neokube.net](https://neokube.net). This module hands
that cluster to the same repository that built [Bahamut](../bahamut/01-prerequisites.md), with
eleven Applications in place of three.

Unlike Bahamut, Yojimbo cannot be copied as it is. It depends on a storage server, a domain and
accounts that are mine. This lab is the list of them. The labs after it show how each part
works, on a cluster that is running, so you can keep the parts you have the hardware for and
leave out the rest.

## What you need

|                      |                                                                                                                             |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **The cluster**      | Single-node OKD or OpenShift on a real machine with 32 GB of RAM, and `oc` logged in as a cluster administrator. The module before this one, [OKD on One Machine](https://github.com/sammonsjl/okd-single-node), installs it. |
| **Bahamut**          | Module 05, done. You have a fork, and its Applications point at it.                                                          |
| **A storage server** | Mine is a Synology NAS. The cluster makes iSCSI LUNs on it through its API, and folders on one NFS share.                    |
| **A domain at Cloudflare** | For certificates from Let's Encrypt without opening a port, and for the tunnel that publishes one site.                |
| **A place for secrets** | Mine is HashiCorp Vault on the NAS. A password manager does the same job here.                                            |
| **A subscription**   | For Ansible Automation Platform. The free Developer Subscription covers it.                                                  |

> **OKD or OpenShift.** These labs were run on OpenShift 4.22, which is what `lud` ran when they
> were written. Nothing here has been run on OKD yet. What is known: three operators in this
> module come from the `redhat-operators` catalog, OpenShift GitOps, cert-manager and Ansible
> Automation Platform, and that catalog for OKD 5.0 carries all three, on the channels this
> repository subscribes to (checked 2026-10-13).

## What Yojimbo needs from the install

If you built the machine with OKD on One Machine, three of the choices you made there matter here:

| Choice                    | Where                 | What Yojimbo needs                                                                 |
| ------------------------- | --------------------- | ---------------------------------------------------------------------------------- |
| The pull secret           | Lab 4 of that module  | The real one. With the placeholder, Red Hat's catalogs do not load, and the public catalog that replaces them does not carry these operators |
| The cluster's names       | Labs 2 and 4          | `api.<cluster>.<domain>` and `*.apps.<cluster>.<domain>`. The certificates in this module are for exactly those names |
| The optional capabilities | `install-config.yaml` | Left on, as that module's own config has them. The operators here need the Operator Lifecycle Manager and the marketplace |

Check the first one now:

```bash
oc get catalogsource -n openshift-marketplace
oc get pods -n openshift-marketplace
```

`redhat-operators` should be listed, and its pod `Running`. If you installed with the
placeholder, Lab 7 of that module shows how to switch to a real pull secret without reinstalling.

## The eleven Applications

```bash
cd ~/homelab
ls clusters/yojimbo/apps
```

| Application             | Folder                                  | What it is                                              | Lab |
| ----------------------- | --------------------------------------- | ------------------------------------------------------- | --- |
| `machine-config`        | `infrastructure/machine-config/yojimbo` | Switches on `iscsid` on the node                        | 5   |
| `synology-csi`          | `infrastructure/synology-csi/yojimbo`   | A LUN on the NAS per volume. The default storage class  | 5   |
| `nfs-csi`               | a Helm chart                            | The NFS driver                                          | 5   |
| `nfs-csi-config`        | `infrastructure/nfs-csi/yojimbo`        | The NFS storage class and what OpenShift needs added    | 5   |
| `local-path`            | `infrastructure/local-path`             | Volumes on the node's own disk                          | 5   |
| `cert-manager-operator` | `infrastructure/cert-manager/operator`  | The same folder Bahamut uses                            | 6   |
| `cert-manager`          | `infrastructure/cert-manager/yojimbo`   | Let's Encrypt, and certificates for the router and the API | 6 |
| `cloudflare`            | `infrastructure/cloudflare`             | The tunnel that publishes neokube.net                   | 6   |
| `aap-operator`          | `infrastructure/aap/operator`           | The Ansible Automation Platform operator                | 7   |
| `aap`                   | `infrastructure/aap/yojimbo`            | The platform itself                                     | 7   |
| `quay-operator`         | `infrastructure/quay/operator`          | The Red Hat Quay operator                               | 7   |
| `quay`                  | `infrastructure/quay/yojimbo`           | The mirror AAP installs from, and its object storage    | 7   |
| `homepage`              | `apps/homepage/yojimbo`                 | The portal, as on Bahamut, with this cluster's links    | 4   |

Not in the repository: neokube.net itself, which is deployed from its own repository, and the
secrets of the next lab.

## What is mine in these folders

Every value below is true of my network and false of yours. Find them all:

```bash
grep -rnE '192\.168\.1\.|neokube\.net|sammonsjl@' clusters/yojimbo infrastructure apps \
  | grep -v 'repoURL' | cut -c1-140
```

| Value                         | Where                                               | What it is                                  |
| ----------------------------- | --------------------------------------------------- | ------------------------------------------- |
| `192.168.1.4`                 | `infrastructure/synology-csi/base/storage-class.yaml`, `infrastructure/nfs-csi/yojimbo/storage-class.yaml`, the portal's settings | The NAS |
| `/volume1/k8s-nfs-yojimbo`    | `infrastructure/nfs-csi/yojimbo/storage-class.yaml` | The NFS share                               |
| `*.apps.lud.neokube.net`, `api.lud.neokube.net`, `lud.neokube.net` | `infrastructure/cert-manager/yojimbo` | The cluster's names: the ones you chose when you installed it |
| The e-mail address            | `infrastructure/cert-manager/yojimbo/clusterissuers.yaml` | Where Let's Encrypt sends expiry warnings |
| `aap.neokube.net`             | `infrastructure/aap/yojimbo`                        | The platform's address                      |
| `quay.neokube.net`            | `infrastructure/quay/yojimbo`, `infrastructure/aap/operator`, `quay-config` | The mirror's address |
| `home.apps.lud.neokube.net`   | `apps/homepage/yojimbo`                             | The portal's address, and its links         |

Change them in your fork and commit. If there is a part you have nothing for, a NAS for
instance, take its line out of `clusters/yojimbo/apps/kustomization.yaml` and the Application is
never created. `aap` asks for the `synology-iscsi` storage class by name, so it goes too, or
gets another class.

Do not push to the branch a running cluster follows until you have done Lab 3.

Next: [Secrets](02-secrets.md)
