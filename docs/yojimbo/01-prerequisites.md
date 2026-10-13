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
| **The cluster**      | Single-node OpenShift 4.22 with 32 GB of RAM, and `oc` logged in as a cluster administrator.                                 |
| **Bahamut**          | The module before this one, done. You have a fork, and its Applications point at it.                                         |
| **A storage server** | Mine is a Synology NAS. The cluster makes iSCSI LUNs on it through its API, and folders on one NFS share.                    |
| **A domain at Cloudflare** | For certificates from Let's Encrypt without opening a port, and for the tunnel that publishes one site.                |
| **A place for secrets** | Mine is HashiCorp Vault on the NAS. A password manager does the same job here.                                            |
| **A subscription**   | For Ansible Automation Platform. The free Developer Subscription covers it.                                                  |

> **OpenShift or OKD.** The cluster on `lud` is OpenShift, and that is what these labs were run
> on. Three operators here come from the `redhat-operators` catalog: OpenShift GitOps,
> cert-manager and Ansible Automation Platform. A cluster built with
> [OKD on One Machine](https://github.com/sammonsjl/okd-single-node) does not have that catalog
> out of the box. Check before you start:
>
> ```bash
> oc get catalogsource -n openshift-marketplace
> ```
>
> If `redhat-operators` is not listed, these labs will not work as written. They have not been
> run on OKD.

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
| `home.apps.lud.neokube.net`   | `apps/homepage/yojimbo`                             | The portal's address, and its links         |

Change them in your fork and commit. If there is a part you have nothing for, a NAS for
instance, take its line out of `clusters/yojimbo/apps/kustomization.yaml` and the Application is
never created. `aap` asks for the `synology-iscsi` storage class by name, so it goes too, or
gets another class.

Do not push to the branch a running cluster follows until you have done Lab 3.

Next: [Secrets](02-secrets.md)
