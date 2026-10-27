# Lab 1 — Prerequisites

## What you will have at the end

OpenShift Local running with room for Argo CD, and your own copy of this repository whose
Applications point at it. Nothing is installed on the cluster yet.

## What you need

|                    |                                                                                                                              |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| **OpenShift Local** | `crc` installed, with your pull secret at `~/.crc/pull-secret.json`. Lab 1 of [AAP on MicroShift](https://github.com/sammonsjl/aap-on-openshift-local) sets both up. Below you switch it from MicroShift to full OpenShift. |
| **RAM**            | 16 GB on the workstation, 11 GB of it given to the cluster's VM.                                                             |
| **A GitHub account** | Argo CD reads the cluster's contents from a repository you can push to. A public fork needs no credentials on the cluster.   |
| **git**            | On the workstation.                                                                                                          |

## Start OpenShift Local

The module before this one ran MicroShift, OpenShift Local's small preset. Bahamut needs full
OpenShift: OpenShift GitOps comes from OpenShift's own operator catalog and expects the console,
OAuth and the cluster operators around it. OpenShift Local builds one kind of cluster at a time,
so delete the MicroShift one (and the platform on it) and switch the preset:

```bash
crc delete
crc config set preset openshift
crc config set memory 11264
crc config set cpus 6
crc config set disk-size 80
crc setup
crc start
```

`crc setup` downloads the OpenShift bundle (~6 GB) the first time. `crc start` takes about five
minutes: it boots the VM and waits for the cluster operators to settle. Then put `oc` on your path
and switch to the administrator's context:

```bash
eval $(crc oc-env)
oc config use-context crc-admin
```

If you skipped the last module, set up `crc` as its Lab 1 describes, then run the commands above
from `crc config set preset openshift`. If `crc start` gives up with `Failed to connect to the CRC
VM with SSH`, your firmware has the boot fault that the last module's
[Lab 2](https://github.com/sammonsjl/aap-on-openshift-local/blob/main/docs/02-cluster.md#start-it)
describes, with its fix.

Check where you are:

```bash
oc whoami
oc get nodes
```

The first should answer `kubeadmin`, and the second list one node, `crc`, that is `Ready`.

## What GitOps changes

Until now you have built clusters by running commands. From here on you run two, once, and
after that a cluster is changed by a commit:

1. **`oc apply -k bootstrap`** installs OpenShift GitOps, the operator that runs
   [Argo CD](https://argo-cd.readthedocs.io) on OpenShift.
2. **`oc apply -f clusters/bahamut/root.yaml`** gives Argo CD one `Application`: a folder in
   git to keep the cluster equal to. That folder holds more Applications, one per component.

Argo CD then compares the cluster with git every few minutes. What is in git and not on the
cluster is created. What you change by hand is put back. What you take out of git is removed.

## Fork and clone the repository

Fork [sammonsjl/homelab](https://github.com/sammonsjl/homelab) on GitHub. On the fork page,
**clear "Copy the `main` branch only"**: the labs are on the branch `openshift-gitops` until it
is merged.

```bash
GITHUB_USER=<your GitHub user name>

git clone https://github.com/$GITHUB_USER/homelab.git ~/homelab
cd ~/homelab
git switch openshift-gitops
```

## The layout

```
bootstrap/                 the OpenShift GitOps operator: the only thing applied by hand
clusters/bahamut/root.yaml one Application that brings in all the others
clusters/bahamut/apps/     an Application per component
infrastructure/            operators, storage, certificates
apps/                      what runs on top
docs/                      the labs
```

There is a `clusters/yojimbo` beside `clusters/bahamut`. That is the production cluster of
module 08. The two share folders under `infrastructure/` and `apps/`, and that sharing is the
point of having Bahamut: a change to a shared folder is seen here first.

## Point the Applications at your fork

Every Application names the repository it reads. They name mine:

```bash
grep -rh repoURL clusters/bahamut | sort | uniq -c
```

```
      5     repoURL: https://github.com/sammonsjl/homelab.git
```

If you left them, your cluster would follow my commits and ignore yours. Change them, in both
clusters' folders, and push:

```bash
grep -rl 'github.com/sammonsjl/homelab' clusters \
  | xargs sed -i "s#github.com/sammonsjl/homelab#github.com/$GITHUB_USER/homelab#"

git commit -am "Follow my fork"
git push
```

`git commit` should report 20 files changed: 5 for Bahamut and 15 for Yojimbo.

The branch each Application follows is on the next line of the same files:

```bash
grep -rh 'targetRevision: openshift' clusters/bahamut | sort | uniq -c
```

```
      5     targetRevision: openshift-gitops
```

Next: [Installing OpenShift GitOps](02-openshift-gitops.md)
