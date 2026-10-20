# 🏠 Homelab

## Introduction

This repo contains everything that runs on my homelab clusters. The purpose of my homelab is to have an environment that I maintain and that lets me expand my knowledge of OpenShift, GitOps and Ansible. Both clusters are OpenShift, and both are built from this repo by [OpenShift GitOps](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops) (Argo CD): one command installs the GitOps operator, one more hands it the cluster's list of applications, and git is the source of truth from there.

Running a real site on it ([neokube.net](https://neokube.net)) makes me responsible for the whole process of deploying and maintaining an application, and makes me think about backups, security and how a change gets to production.

## Tutorials

Each cluster has a set of labs that build it from this repo, step by step. They are also
published as modules 05 and 07 of the path on [neokube.net](https://neokube.net).

| Cluster | Labs | Start here |
|---|---|---|
| Bahamut | Fork the repo, install OpenShift GitOps on OpenShift Local, apply the root Application, which deploys Ghost among others, and change it through git | [`docs/bahamut`](docs/bahamut/01-prerequisites.md) |
| Yojimbo | Secrets, a dry run before the first sync, handing a running cluster to git, then storage, certificates, the tunnel and the automation platform | [`docs/yojimbo`](docs/yojimbo/01-prerequisites.md) |

> **2026-10-16:** Bahamut now runs Ghost and its MySQL (`apps/ghost`), the same Ghost module 04
> deploys by hand, in place of Uptime Kuma and Headlamp, which had never run on it. Labs 2 to 4
> and 99 of Bahamut were run with it on a new OpenShift Local, by Claude, from a branch that only
> Bahamut followed. Lab 1's fork was not run (it would be a fork of the same account).

> **Status, 2026-10-13: written from one test of each cluster, not yet followed from the text.**
> On 2026-10-12 the commands in these labs were run on both clusters: Bahamut on an OpenShift
> Local VM that already held another install, Yojimbo by handing the running cluster on `lud` to
> Argo CD. The labs were written afterwards from that run. Nobody has followed them from the
> page. Not run at all: Bahamut on an empty cluster and from a fork, Yojimbo from an empty
> cluster (Lab 4 says so), the branch routine in Yojimbo's Lab 8, and any of it on OKD. Red Hat's catalog for OKD 5.0 does
> carry the three operators these clusters install (checked 2026-10-13).

## Clusters

<table>
    <tr>
        <th>Number</th>
        <th>Name</th>
        <th>Description</th>
    </tr>
    <tr>
        <td>1</td>
        <td>Bahamut</td>
        <td>DEV cluster: <a href="https://developers.redhat.com/products/openshift-local">OpenShift Local</a> on my laptop. A change to anything the two clusters share is tried here before it goes to Yojimbo.</td>
    </tr>
    <tr>
        <td>2</td>
        <td>Yojimbo</td>
        <td>PRD cluster: single-node OpenShift on bare metal (<code>lud</code>, a mini PC with 32 GB RAM). Treated as a production system with the goal of keeping it running as much as possible.</td>
    </tr>
</table>

## How a cluster is built

```
bootstrap/                 the OpenShift GitOps operator: the only thing applied by hand
clusters/<name>/root.yaml  one Argo CD Application that brings in all the others
clusters/<name>/apps/      an Application per component
infrastructure/            operators, storage, certificates, the tunnel
apps/                      what runs on top
ansible/                   the playbooks AAP runs (backup and restore of neokube.net)
docs/                      the labs: docs/bahamut and docs/yojimbo
```

On a cluster you are logged in to as a cluster administrator:

```bash
oc apply -k bootstrap
oc wait --for=jsonpath='{.status.phase}'=Available argocd/openshift-gitops -n openshift-gitops --timeout=10m
oc apply -f clusters/bahamut/root.yaml      # or clusters/yojimbo/root.yaml
oc get applications -n openshift-gitops -w
```

The first command returns before the operator has created its Argo CD instance, so the `oc wait` fails with "not found" for the first minute or two; repeat it until it waits.

**Bahamut only**, before `root.yaml`: OpenShift Local at 11 GB has almost no memory left to reserve, Argo CD's controller stays Pending, and the `oc wait` above never returns. As soon as `oc get argocd -n openshift-gitops` lists the instance, trim it, wait until the operator has passed the smaller requests on to the controller's StatefulSet, remove the pods that started with the larger reservation so the smaller ones can be scheduled, and wait then:

```bash
oc apply -f clusters/bahamut/argocd.yaml
oc get statefulset openshift-gitops-application-controller -n openshift-gitops \
  -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}{"\n"}'   # repeat until 128Mi
oc delete pods --all -n openshift-gitops
oc wait --for=jsonpath='{.status.phase}'=Available argocd/openshift-gitops -n openshift-gitops --timeout=10m
```

For the same reason Bahamut's 11 GB hold one Ghost: if the one from module 04 is still on the cluster, remove it first.

The Applications are all created at once. One that needs something another one installs (an issuer needs cert-manager, the platform needs its operator) fails its first sync and retries until it goes through; that is what the `retry` block in each of them is for. Every Application syncs by itself, removes what is taken out of git (`prune`) and puts back what is changed by hand (`selfHeal`).

Components shared by both clusters have a common folder (`infrastructure/cert-manager/operator`, `apps/homepage/base`) and a folder per cluster for what differs.

### Trying a change

1. Make the change on a branch and point Bahamut's Applications at it (`targetRevision`), or commit it to the branch Bahamut already follows.
2. Watch it sync: `oc get applications -n openshift-gitops`, or the Argo CD console.
3. When Bahamut is healthy, merge. Yojimbo picks it up within three minutes.

### Secrets

Secrets are kept in HashiCorp Vault on the NAS and are not in this repo. Yojimbo needs four, created by hand before `root.yaml` is applied. The portal starts without the fourth; its Pi-hole and Synology widgets then show an error:

| Secret | Namespace | Keys | Vault |
|---|---|---|---|
| `cloudflare-api-token` | `cert-manager` | `token` | `secrets/cloudflare`, `TOKEN` |
| `cloudflare` | `cloudflare` | `ACCOUNT_ID`, `TOKEN` | `secrets/cloudflare` |
| `client-info-secret` | `synology-csi` | `client-info.yml` | `secrets/synology` |
| `homepage-widgets` | `homepage` | `HOMEPAGE_VAR_PIHOLE_KEY`, `HOMEPAGE_VAR_SYNOLOGY_USERNAME`, `HOMEPAGE_VAR_SYNOLOGY_PASSWORD` | `secrets/pihole`, `secrets/synology` |

Bahamut needs one, made by hand before `root.yaml` (Lab 3 of Bahamut): `ghost-db` in `ghost`, with two random passwords, `root-password` and `password`. Yojimbo has the same Secret, made the same way, for neokube.net.

## What runs where

| Component | Bahamut | Yojimbo | Folder |
|---|---|---|---|
| OpenShift GitOps (Argo CD) | ✅ | ✅ | `bootstrap` |
| cert-manager operator | ✅ | ✅ | `infrastructure/cert-manager/operator` |
| Certificate issuers | a private CA | Let's Encrypt over DNS-01 at Cloudflare; certificates for the router, the API and the console | `infrastructure/cert-manager/<cluster>` |
| Homepage | ✅ | ✅ | `apps/homepage` |
| Ghost and MySQL | ✅ `ghost.apps-crc.testing` | ✅ `neokube.net` (since 2026-10-20) | `apps/ghost` |
| Uptime Kuma (Helm chart) | | ✅ `uptime.neokube.net` | `apps/uptime-kuma` |
| Headlamp (Helm chart) | | ✅ `headlamp.neokube.net` | `apps/headlamp` |
| Synology CSI (iSCSI LUNs on the NAS, the default class) | | ✅ | `infrastructure/synology-csi` |
| NFS CSI (folders on the NAS) | | ✅ | `infrastructure/nfs-csi` |
| Local path (the node's own disk) | | ✅ | `infrastructure/local-path` |
| `iscsid` on the node | | ✅ | `infrastructure/machine-config` |
| Cloudflare tunnel | | ✅ | `infrastructure/cloudflare` |
| Ansible Automation Platform | no room | ✅ | `infrastructure/aap` |

Not in this repo: the image registry's volume, and what neokube.net's Ghost holds. The site's lessons and pages are
synced into Ghost from `neokube/content` in the Social Office workspace (`scripts/neokube-ghost-sync.py`, checked with
`scripts/neokube-check-ghost.py`); the theme ([sammonsjl/neokube](https://github.com/sammonsjl/neokube), `ghost-theme/`),
`settings/routes.yaml` (modules at `/module/<tag>/`) and `data/redirects.yaml` (the Liferay addresses `/b/<slug>`) are
files on Ghost's content volume, copied in with `oc exec ... tar`, and take effect when the Ghost pod restarts.
neokube.net ran on Liferay from 2026-10-07 to 2026-10-20.

## :computer: Hardware

`lud` is a mini PC with 32 GB RAM that runs OpenShift directly, with no hypervisor under it. A Synology DS224+ is the storage layer: cluster volumes are provisioned on it over iSCSI and NFS, depending on what the workload needs, and the backups land on it.

## Networking

OpenShift's own network (OVN-Kubernetes) and its router do the work: every app is published with a `Route` under the cluster's `*.apps` name, and the router serves a wildcard certificate that cert-manager keeps renewed. Names resolve on the LAN through Pi-hole. The one public name, neokube.net, comes in through a Cloudflare tunnel and never needs an open port.

## Storage

The [Synology CSI driver](https://github.com/SynologyOpenSource/synology-csi) provisions a LUN on the NAS per volume, and the [NFS CSI driver](https://github.com/kubernetes-csi/csi-driver-nfs) a folder per volume for data several pods share.

## Backups

Ansible Automation Platform on Yojimbo backed up neokube.net to the NAS every night while the site ran on Liferay, and tested the restore. See [`ansible/`](ansible/README.md). **Since the move back to Ghost (2026-10-20) nothing backs the site up on a schedule:** the playbooks are Liferay's, and AAP was reinstalled on 2026-10-16 without a subscription. A Ghost backup taken by hand is in `~/projects/backups/ghost-20261020-lud-cutover/` on the NAS.
