# Lab 1 — Prerequisites

## What you will have at the end

OpenShift Local running with room for Argo CD, and your own copy of this repository whose
Applications point at it. Nothing is installed on the cluster yet.

## What you need

|                    |                                                                                                                              |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| **OpenShift Local** | Installed and started, with `oc` logged in as `kubeadmin`. Labs 1 and 2 of [Ansible Automation Platform on OpenShift Local](https://github.com/sammonsjl/aap-on-openshift-local) do exactly this. |
| **RAM**            | 16 GB on the workstation, 11 GB of it given to the cluster's VM.                                                             |
| **A GitHub account** | Argo CD reads the cluster's contents from a repository you can push to. A public fork needs no credentials on the cluster.   |
| **git**            | On the workstation.                                                                                                          |

> **One cluster, one job.** If you did the module before this one, Ansible Automation Platform
> is still on your cluster, and there is not enough memory for both. With the two installed
> together on an 11 GB VM, the platform's database is left `Pending`. Remove the platform first
> (Lab 99 of that module, "Remove the platform, keep the cluster"), or start again from an empty
> cluster with `crc delete` and `crc start`.

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
module 07. The two share folders under `infrastructure/` and `apps/`, and that sharing is the
point of having Bahamut: a change to a shared folder is seen here first.

## Point the Applications at your fork

Every Application names the repository it reads. They name mine:

```bash
grep -rh repoURL clusters/bahamut | sort | uniq -c
```

```
      4     repoURL: https://github.com/sammonsjl/homelab.git
```

If you left them, your cluster would follow my commits and ignore yours. Change them, in both
clusters' folders, and push:

```bash
grep -rl 'github.com/sammonsjl/homelab' clusters \
  | xargs sed -i "s#github.com/sammonsjl/homelab#github.com/$GITHUB_USER/homelab#"

git commit -am "Follow my fork"
git push
```

`git commit` should report 15 files changed: 4 for Bahamut and 11 for Yojimbo.

The branch each Application follows is on the next line of the same files:

```bash
grep -rh 'targetRevision: openshift' clusters/bahamut | sort | uniq -c
```

```
      4     targetRevision: openshift-gitops
```

Next: [Installing OpenShift GitOps](02-openshift-gitops.md)
