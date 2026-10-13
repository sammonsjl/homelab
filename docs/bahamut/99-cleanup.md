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

This deletes the VM and its disk. Nothing of Bahamut is lost with it: the cluster's contents are
in your fork. `crc start`, then Labs 2 and 3, and it is back.

## If you take it apart by hand

To keep the cluster and remove only what this module added, delete in this order: the
Applications, then the `ArgoCD` instance, then the operator's Subscription and its
ClusterServiceVersion, and the namespaces last.

> On the test run the operator was removed before its instance. The namespace
> `openshift-gitops` then hung in `Terminating`, because the `ArgoCD` object carries a finalizer
> that only the operator can clear. The order above avoids that; it has not been run as written.
