# Lab 99 — Cleaning Up

## What you will have at the end

Your choice of two: the cluster paused with everything kept, or nothing left at all.

## Pause it

The cluster holds 11 GB of your workstation's memory for as long as it runs. To get that back and
keep everything:

```bash
crc stop
```

`crc start` brings it back as it was. Argo CD then syncs to whatever your branch says by then,
so commits made while the cluster was off arrive when it starts.

## Remove everything

```bash
crc delete
```

This deletes the VM and its disk. Nothing of Bahamut's setup is lost with it: the cluster's
contents are in your fork. `crc start`, then Labs 2 and 3, and it is back. What Ghost had in its
database is not in the fork, and goes with the VM.

## If you take it apart by hand

`crc delete` is the clean way. To keep the cluster and remove only what this module added, the
order that worked on the test run is below. It leaves the cluster-wide definitions and roles the
two operators installed, which do no harm.

```bash
N=openshift-gitops

# 1. The root first, so that it does not put the others back
oc delete application bahamut -n $N

# 2. Ghost's volumes keep their data when their claims go (the storage class
#    says Retain). Let them go with the claims
for pv in $(oc get pvc -n ghost -o jsonpath='{.items[*].spec.volumeName}'); do
  oc patch pv $pv -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
done

# 3. The other four, each taking what it made with it
for app in cert-manager homepage ghost cert-manager-operator; do
  oc patch application $app -n $N --type merge \
    -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}'
done
oc delete application cert-manager homepage ghost -n $N
oc delete application cert-manager-operator -n $N

# 4. The GitOps operator, then its instance
oc delete subscription openshift-gitops-operator -n openshift-gitops-operator
oc delete csv --all -n openshift-gitops-operator
oc delete namespace openshift-gitops openshift-gitops-operator cert-manager --wait=false
oc delete clusterrolebinding openshift-gitops-cluster-admin
```

An Application deleted as it is leaves everything it created. With the finalizer added first,
Argo CD removes what the Application made and then the Application.

The namespace `openshift-gitops` then hangs in `Terminating`. The `ArgoCD` object in it carries a
finalizer that only the operator clears, and the operator is gone. Deleting the instance first
does not help: the operator makes a new one. Clear the finalizer by hand:

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{"metadata":{"finalizers":null}}'
oc patch certmanager cluster --type merge -p '{"metadata":{"finalizers":null}}'
```
