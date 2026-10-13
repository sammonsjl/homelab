# Lab 2 — Installing OpenShift GitOps

## What you will have at the end

The OpenShift GitOps operator installed, and its Argo CD instance running in the namespace
`openshift-gitops`, trimmed to fit in what OpenShift Local has left.

## The bootstrap folder

`bootstrap/` is the only part of the repository that is applied by hand, because it installs the
thing that applies everything else. It holds four objects:

| Object                                          | Why                                                                                       |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Namespace `openshift-gitops-operator`           | Where the operator runs                                                                   |
| OperatorGroup                                   | Tells the Operator Lifecycle Manager the operator watches every namespace                 |
| Subscription `openshift-gitops-operator`        | Installs the operator from the `redhat-operators` catalog and keeps it updated            |
| ClusterRoleBinding `openshift-gitops-cluster-admin` | Lets Argo CD's controller manage the whole cluster                                    |

The last one deserves a second look. Out of the box, the operator's Argo CD may only touch a
short list of cluster-wide resources. This repository installs operators, storage classes and
security bindings, so its controller is given `cluster-admin`. Whoever can push to the branch the
cluster follows is, from then on, an administrator of the cluster.

```bash
cd ~/homelab
oc apply -k bootstrap
```

```
namespace/openshift-gitops-operator created
clusterrolebinding.rbac.authorization.k8s.io/openshift-gitops-cluster-admin created
operatorgroup.operators.coreos.com/openshift-gitops-operator created
subscription.operators.coreos.com/openshift-gitops-operator created
```

## Wait for the instance

The command returns at once. The operator is installed a few minutes later, and creates an
Argo CD instance named `openshift-gitops` by itself. Watch for it:

```bash
oc get csv -n openshift-gitops-operator
oc get argocd -n openshift-gitops
```

Repeat until the first shows `Succeeded` and the second lists `openshift-gitops`:

```
NAME                                DISPLAY                    VERSION   PHASE
openshift-gitops-operator.v1.22.1   Red Hat OpenShift GitOps   1.22.1    Succeeded

NAME               AGE
openshift-gitops   40s
```

## The controller is Pending

```bash
oc get pods -n openshift-gitops
```

```
NAME                                                          READY   STATUS    RESTARTS   AGE
cluster-6fd95fbc9c-ph4n7                                      1/1     Running   0          2m
gitops-plugin-746cf889-l2mks                                  1/1     Running   0          2m
openshift-gitops-application-controller-0                     0/1     Pending   0          2m
openshift-gitops-applicationset-controller-85958f8c59-9vdfx   0/1     Pending   0          2m
openshift-gitops-dex-server-76d87d5d65-4sttj                  1/1     Running   0          2m
openshift-gitops-redis-66d5c48c8c-8xvcz                       1/1     Running   0          2m
openshift-gitops-repo-server-6c855879dc-5nx9c                 1/1     Running   0          2m
openshift-gitops-server-7d5d47449-kcjn4                       1/1     Running   0          2m
```

The application controller is the part of Argo CD that does the work, and it has nowhere to run:

```bash
oc describe pod openshift-gitops-application-controller-0 -n openshift-gitops | tail -3
oc describe node crc | grep -A5 'Allocated resources'
```

```
  Warning  FailedScheduling  default-scheduler  0/1 nodes are available: 1 Insufficient memory.

Allocated resources:
  Resource           Requests       Limits
  --------           --------       ------
  cpu                3696m (63%)    3510m (60%)
  memory             10492Mi (99%)  16640Mi (158%)
```

A pod's memory *request* is a reservation. The scheduler places a pod only where its request
still fits, whatever the node is really using. OpenShift's own pods reserve nearly all of an
11 GB node, and Argo CD as the operator sets it up reserves 2.4 GB more:

| Pod                        | Reserves |
| -------------------------- | -------- |
| application controller     | 1 Gi     |
| applicationset controller  | 512 Mi   |
| repo server                | 256 Mi   |
| server, redis, dex, and the operator's two helper pods | 128 Mi each |

Your figures will differ by a few hundred Mi. If everything is `Running`, you have room to
spare; apply the trim anyway, so that the next lab's pods have somewhere to go.

## Trim the instance

`clusters/bahamut/argocd.yaml` is the same `ArgoCD` object the operator created, with smaller
requests and with the applicationset controller switched off (nothing here uses it). Limits are
left alone: a request decides where a pod may be placed, not how much it may use.

```bash
oc apply -f clusters/bahamut/argocd.yaml
```

`oc` warns that the object was not created by `oc apply`. That is true and harmless: the
operator made it.

The operator rolls the pods out again with the smaller requests, and the rollout gets stuck: a
new pod cannot start until an old one stops, and an old one is not stopped until a new one is
ready. Remove the old ones yourself:

```bash
oc delete pods --all -n openshift-gitops
oc wait --for=jsonpath='{.status.phase}'=Available argocd/openshift-gitops -n openshift-gitops --timeout=10m
oc get pods -n openshift-gitops
```

Every pod should be `Running`, and the applicationset controller gone.

## Look at Argo CD

Argo CD has a console of its own, at a route the operator made:

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='https://{.spec.host}{"\n"}'
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-
```

The first line is the address. The second prints the password of the user `admin`. Your browser
warns about the certificate, as it does for the OpenShift console. The list of applications is
empty.

Next: [The Root Application](03-the-root-application.md)
