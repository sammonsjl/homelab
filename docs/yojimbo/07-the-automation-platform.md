# Lab 7 — The Automation Platform

## What you will have at the end

Ansible Automation Platform described by four folders in git: a mirror of every image it installs
from, the mirror's operator, the platform's operator, and one object that is the whole platform,
sized to share a 32 GB machine with a site.

## Four Applications

If you did [Ansible Automation Platform on OpenShift Local](https://github.com/sammonsjl/aap-on-openshift-local),
you installed this by hand: a Subscription for the operator, then one
`AnsibleAutomationPlatform` object that the operator turns into a gateway, a controller, a
database and the rest. Here the same two steps are two Applications. Two more put a mirror in
front of them, so that what the operator installs comes from the cluster's own registry and not
from Red Hat's.

| Application     | Folder                         | Holds                                                    |
| --------------- | ------------------------------ | -------------------------------------------------------- |
| `quay-operator` | `infrastructure/quay/operator` | The namespace, an OperatorGroup and the Subscription for Red Hat Quay |
| `quay`          | `infrastructure/quay/yojimbo`  | Garage, an S3 server for Quay's layers, and the `QuayRegistry` |
| `aap-operator`  | `infrastructure/aap/operator`  | The namespace, an OperatorGroup and the Subscription, and the mirror's catalog |
| `aap`           | `infrastructure/aap/yojimbo`   | A `Certificate` and the `AnsibleAutomationPlatform`      |

`aap` needs three things that other Applications bring: the platform's kind from the operator, a
`Certificate` kind and an issuer from cert-manager, and the `synology-iscsi` storage class. It
retries until all three are there. `aap-operator` needs the mirror to hold the operator before
it can install it.

## Making room

A pod's CPU *request* is a claim on the node, like its memory request: the scheduler places a
pod only where its request still fits. Before Quay, the claims on `lud` stood at 7.2 of the 7.5
CPUs the node offers, though it was using under 2:

```bash
oc describe node lud | grep -A4 'Allocated resources'
```

```
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests       Limits
  --------           --------       ------
  cpu                7248m (96%)    271210m (3616%)
```

The largest single claim was Argo CD's, 1.9 CPUs, for pods that use 0.1. The fix is the one from
Bahamut's Lab 2: `clusters/yojimbo/argocd.yaml` is the `ArgoCD` object the operator made, with
smaller requests and the applicationset controller switched off. Nothing in this repository
uses ApplicationSets.

```bash
oc apply -f clusters/yojimbo/argocd.yaml
```

Afterwards the claims are at 6.2. Quay needs that much room, though not to run: before it starts,
and again before each new version, the operator runs a job that prepares Quay's database, and
that job asks for a whole CPU and 3 GiB. It cannot be made smaller. Until it has run, the
operator applies nothing else.

## The mirror

Without a mirror, every install of the operator downloads its images from `registry.redhat.io`.
That is 27 images for AAP 2.6. A reinstall depends on Red Hat's registry being reachable, and
gets whatever version is newest that day. A mirror is how a cluster with no internet installs
operators. Here it does the same job for a cluster that has internet. The operator is installed
from a copy on the NAS, made when you chose to make it, of exactly the version you tested.

Red Hat has two answers for the registry. *Mirror registry for Red Hat OpenShift* is a small
Quay that its installer sets up with podman on a RHEL host, outside any cluster. It is meant
for a cluster that does not exist yet. The *Red Hat Quay operator* runs Quay on the cluster as
one more object. This cluster already exists, and everything else on it is in git, so it runs
the operator.

### Quay, trimmed

```bash
cat infrastructure/quay/yojimbo/registry.yaml
```

Quay as the operator installs it by default is built for a company: two or more replicas, an
autoscaler, a vulnerability scanner with a database of its own, and object storage from
OpenShift Data Foundation. A mirror needs a fraction of that:

| Component                           | Here         | Why                                                            |
| ----------------------------------- | ------------ | -------------------------------------------------------------- |
| `quay`, `postgres`, `redis`         | On, smaller  | The registry itself. One replica, and requests near what each uses. Redis alone asks for 500m by default |
| `route`                             | On           | A passthrough route at `quay.neokube.net`                      |
| `tls`                               | Off          | cert-manager's certificate for `quay.neokube.net` instead of the operator's own |
| `objectstorage`                     | Off          | Garage, below, instead of OpenShift Data Foundation            |
| `clair`, `clairpostgres`            | Off          | Scanning Red Hat's own images for vulnerabilities is Red Hat's job |
| `horizontalpodautoscaler`, `mirror` | Off          | One replica is enough; `mirror` is Quay pulling repositories by itself |
| `monitoring`                        | Off          | Needs the operator installed for all namespaces                |

One setting is not a component: what Quay runs inside its pod. That is about 35 programs:
gunicorn web servers, started by the node's CPU count (four registry workers per CPU, so 32 on
`lud`), and a background worker for every feature Quay has, builds, quotas, scanning
notifications and more. Together they outgrew a 4 GiB limit within a minute of starting. The
first time this ran, the operator rolled out a fix while the old pod was still restarting, two
Quays took the last of the node's memory, and with no swap `lud` stalled for four minutes, the
site with it.

The `env` block in `registry.yaml` is the fix. `QUAY_SERVICES` lists the programs a mirror
needs, the registry, the API and the clean-up of unfinished uploads, and Quay starts only those.
`WORKER_COUNT_*` ask for one or two gunicorn workers instead of dozens. The limits keep Quay to
one CPU and 2 GiB, so that if it ever outgrows them it is Quay that is killed, not the node.

The route and TLS matter more than they look, because the node will pull through them and
trusts only certificates it already knows. Quay is at `quay.neokube.net`, like the platform at
`aap.neokube.net`, and not under `*.apps.lud.neokube.net`, so the router's wildcard certificate
does not cover it. `certificate.yaml` asks cert-manager for one from Let's Encrypt, which the
node trusts like any browser does. The `tls` component names its Secret, so the operator makes
a *passthrough* route: the router hands the connection to Quay unopened, Quay presents the
certificate, and the operator restarts Quay when cert-manager renews it. The name also needs a
record on your local DNS server pointing at the node, `192.168.1.2` here, as `aap.neokube.net`
has.

The database's volume is 50 Gi on `local-path`, `lud`'s own disk. 50 Gi is the operator's
minimum, and it refuses a smaller one.

### Garage

Quay keeps image layers in object storage, never on a volume of its own. Garage is a small S3
server, one pod, with its data on one volume on `lud`'s own disk:

```bash
cat infrastructure/quay/yojimbo/garage.yaml
```

Everything else that matters on this cluster is on the NAS, so that it outlives the node. The
mirror is the exception, on purpose: everything in it is a copy, and `oc-mirror` makes the copy
again in minutes. Garage also keeps an SQLite database of what it stores, and a database on
the NFS share is a way to lose it. `local-path` keeps both its volume and Quay's database on
the node's NVMe disk, which is also the fastest place to pull from.

Its secrets are from Lab 2. Its layout, bucket and key are made once, with its own CLI, inside
the pod. A Garage cluster is a set of nodes with a layout that says how much each stores. This
one has a single node:

```bash
garage() { oc exec -n quay deploy/garage -- /garage "$@"; }
node=$(garage node id -q | cut -d@ -f1)
garage layout assign -z lud -c 100GB $node
garage layout apply --version 1
garage bucket create quay
garage key import --yes -n quay "$(vault kv get -field=S3_ACCESS_KEY secrets/quay)" \
  "$(vault kv get -field=S3_SECRET_KEY secrets/quay)"
garage bucket allow --read --write --owner quay --key quay
```

The pod turns `Ready` once the layout is applied. Then Quay can store layers, and the
`QuayRegistry` becomes `Available`:

```bash
oc get quayregistry registry -n quay \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{"\n"}'
```

```
True
```

### Inside Quay

Quay starts empty, with no users. `FEATURE_USER_INITIALIZE` in `quay-config` allows exactly one
call that makes the first one, `quayadmin`:

```bash
curl -s -X POST https://quay.neokube.net/api/v1/user/initialize -H 'Content-Type: application/json' \
  -d "{\"username\": \"quayadmin\", \"email\": \"quayadmin@neokube.net\",
       \"password\": \"$(vault kv get -field=QUAY_ADMIN_PASSWORD secrets/quay)\"}"
```

That is all the setup Quay needs. The mirror keeps Red Hat's paths:
`registry.redhat.io/ansible-automation-platform-26/controller-rhel9` is copied to
`quay.neokube.net/ansible-automation-platform-26/controller-rhel9`. Quay files every repository
under an organization, the first part of its path, and two lines in `quay-config` let a push
make what is missing:

| Setting                             | What it does                                                    |
| ----------------------------------- | --------------------------------------------------------------- |
| `CREATE_NAMESPACE_ON_PUSH: true`    | A push to `ansible-automation-platform-26/...` creates the organization |
| `CREATE_PRIVATE_REPO_ON_PUSH: false` | The repositories it creates are public                         |

Public means the node pulls without logging in, so its pull secret does not change. The
images are Red Hat's own and the registry is reachable only on your network; anyone on it
could pull them from `registry.redhat.io` with a Red Hat login. Pushing still takes
`quayadmin`.

### Filling it

`oc-mirror` copies images from one registry to another. What it copies is written down in an
`ImageSetConfiguration`, next to the Subscription that uses the copy:

```bash
cat infrastructure/aap/operator/imageset-config.yaml
```

```yaml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v2alpha1
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.22
      packages:
        - name: ansible-automation-platform-operator
          # The catalog's default is stable-2.7; the copy must name one it keeps.
          defaultChannel: stable-2.6
          channels:
            - name: stable-2.6
```

From Red Hat's catalog for OpenShift 4.22, one package, one channel. A catalog names a default
channel for each package, Red Hat's says `stable-2.7` for this one, and a copy without that
channel must name another. `oc-mirror` takes the newest
version in that channel and every image that version names: the operator's own, the platform's,
PostgreSQL's and Redis's, and those of the parts this cluster leaves off, hub and EDA among them.
It also builds a catalog of its own, holding that one package.

It is a separate download from the same place as `oc`, the
[OpenShift client mirror](https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable-4.22/),
`oc-mirror.rhel9.tar.gz`. It logs in with podman's logins: to Red Hat with your Red Hat account,
and to Quay as `quayadmin`.

```bash
podman login registry.redhat.io
podman login quay.neokube.net -u quayadmin \
  -p "$(vault kv get -field=QUAY_ADMIN_PASSWORD secrets/quay)"

oc-mirror --v2 -c infrastructure/aap/operator/imageset-config.yaml \
  --workspace file://$HOME/.cache/oc-mirror/aap docker://quay.neokube.net
```

It found 29 images: the 27 of AAP 2.6, the operator's bundle, and the cut-down catalog. Expect
it to take a while. Most of these images are built for four processor architectures, and
`oc-mirror` copies all four, because the operator names each image by the digest of the list
of all four; a copy of only `amd64` would have a different digest. Quay held 35 GB at the end.
On my connection Red Hat sent about 4.5 MB/s, and the copy took a little under three hours.

Two things to know if it stops short:

- The default limit is 10 minutes per image, too short for the biggest at that speed. Add
  `--image-timeout 120m`.
- Run it again with the same command. It copies only what is missing.


### Switching the operator to the mirror

`oc-mirror` ends by writing what the cluster needs in order to use the copy, in
`~/.cache/oc-mirror/aap/working-dir/cluster-resources`: a `CatalogSource` for the copied catalog,
an `ImageDigestMirrorSet` and an `ImageTagMirrorSet`. Read the mirror sets before applying
them. Among their entries is this one, there because `ubi9-minimal` sits at the top of
`registry.redhat.io`:

```yaml
  - mirrors:
    - quay.neokube.net
    source: registry.redhat.io
```

It sends every image from `registry.redhat.io` to Quay first, and by tag as well. The
`redhat-operators` catalog is `registry.redhat.io/redhat/redhat-operator-index:v4.22`, the same
name and tag as the cut-down copy, so it would load the copy, which holds only AAP, and every
other operator on the cluster would lose its catalog.

`infrastructure/aap/operator/mirror.yaml` is the same two objects written narrowly: an
`ImageDigestMirrorSet` that names AAP's repositories and the four others the operator uses, and
no `ImageTagMirrorSet`, because the operator names its images by digest.

```bash
cat infrastructure/aap/operator/mirror.yaml
```

The `CatalogSource` is called `aap-mirror`, and the Subscription in `operator.yaml` names it as
its `source`. `redhat-operators` stays for everything else. A mirror set reaches the node through
the Machine Config Operator, which rewrites `/etc/containers/registries.conf`; that does not
restart the node.

If an image is not in Quay, or Quay is down, the node falls back to `registry.redhat.io`. To see
it use the mirror, pull an image the node does not have yet, hub's, which is in the mirror but
switched off in the platform, and look for it in Quay's logs:

```bash
hub=$(oc get packagemanifest ansible-automation-platform-operator -n openshift-marketplace -o json \
  | jq -r '.status.channels[] | select(.name=="stable-2.6") | .currentCSVDesc.relatedImages[]
           | select(test("/hub-rhel9@"))')
oc debug node/lud -- chroot /host crictl pull $hub
oc logs -n quay deploy/registry-quay-app --since=5m | grep -o '"GET /v2/[^ ]*hub-rhel9/[a-z]*' | sort | uniq -c
oc debug node/lud -- chroot /host crictl rmi $hub
```

```
      4 "GET /v2/ansible-automation-platform-26/hub-rhel9/blobs
      4 "GET /v2/ansible-automation-platform-26/hub-rhel9/manifests
```

The node asked for `registry.redhat.io`, and Quay answered.

## The operator

```bash
cat infrastructure/aap/operator/operator.yaml
```

The part worth reading is at the end of the Subscription:

```yaml
  config:
    resources:
      requests: {cpu: 10m, memory: 64Mi}
      limits: {memory: 2Gi}
```

The operator is seven controller managers in one package, one for each part of the platform.
Most sit idle. With their default requests they reserve about 1.4 GiB between them for doing
nothing. `config.resources` on a Subscription overrides the requests of everything the package
installs.

## The platform

```bash
cat infrastructure/aap/yojimbo/platform.yaml
```

| Setting                                         | Why                                                                          |
| ----------------------------------------------- | ---------------------------------------------------------------------------- |
| `route_host`, `route_tls_secret`                | Served at its own name, with the certificate the folder's `Certificate` keeps renewed |
| `database.postgres_storage_class: synology-iscsi` | The database is on the NAS and outlives the node                           |
| Smaller requests for `api` and `proxy`          | The defaults reserve far more than the gateway uses                          |
| `hub` and `eda` `disabled: true`                | This machine also runs the site. These are the two parts it can do without   |
| `lightspeed` `disabled: true`                   | It needs an AI backend this cluster does not have                            |

As the operator sets it up, the platform reserves about 11 GiB, a third of this machine, and
uses about half of that. The memory lessons of the OpenShift Local module apply at any size: a
request is a claim on the node whether or not it is used.

```bash
oc get pods -n aap
curl -s -o /dev/null -w '%{http_code}\n' https://aap.neokube.net/api/gateway/v1/ping/
```

```
200
```

The administrator's password is in a secret the operator made:

```bash
oc extract secret/aap-admin-password -n aap --to=-
```

## What git does not hold

The `AnsibleAutomationPlatform` object is the platform's shape: which parts run, how big, on what
storage, at what name. Everything inside it is in its database: the subscription you attach at
first login, organizations, credentials, projects, job templates and their history.

A reinstall from git therefore gives you an empty platform at the right address, unless the
database's LUN is still on the NAS and is attached again. The job templates on `lud`, which back
up the site every night and test the restore, are created by playbooks in this repository's
[`ansible/`](../../ansible/README.md) folder, so they can be put back by running those again.

The mirror is the other way round: git holds what it should contain, `imageset-config.yaml`, and
not the copy. Quay's database and Garage's volume are on `lud`'s own disk, so a reinstall starts
with an empty Quay. Until the steps of [Inside Quay](#inside-quay) and [Filling it](#filling-it)
are done again, `aap-operator` cannot install the operator: its catalog's image is not there
yet. The operator already installed keeps running, and so does the platform, because nothing
re-pulls an image that is already on the node.

## Changing it

The platform is now changed like the portal was on Bahamut. To bring automation hub back, for
example, replace its `disabled: true` in `platform.yaml` with its settings, commit and push.
Argo CD applies the object, and the operator does the rest over the next several minutes. The
Application shows `Progressing` until the operator reports the platform ready.

Do the dry run of Lab 3 first:

```bash
oc diff -k infrastructure/aap/yojimbo | grep -E '^[-+] ' | grep -v -e tracking-id -e generation
```

A new version of AAP no longer arrives by itself. The operator updates when the mirror's catalog
does, and that changes when you run `oc-mirror` again with the same command. It copies only what
is new, and writes `cluster-resources` again. Compare them with `mirror.yaml`; if a new image
source appears, add it, then commit. The catalog's pod notices the new catalog within ten
minutes, and the operator upgrades as it did before the mirror.

Next: [From Bahamut to Yojimbo](08-from-bahamut-to-yojimbo.md)
