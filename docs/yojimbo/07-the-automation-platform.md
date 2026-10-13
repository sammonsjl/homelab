# Lab 7 — The Automation Platform

## What you will have at the end

Ansible Automation Platform described by two folders in git: its operator, and one object that
is the whole platform, sized to share a 32 GB machine with a site.

## Two Applications

If you did [Ansible Automation Platform on OpenShift Local](https://github.com/sammonsjl/aap-on-openshift-local),
you installed this by hand: a Subscription for the operator, then one
`AnsibleAutomationPlatform` object that the operator turns into a gateway, a controller, a
database and the rest. Here the same two steps are two Applications.

| Application    | Folder                        | Holds                                              |
| -------------- | ----------------------------- | -------------------------------------------------- |
| `aap-operator` | `infrastructure/aap/operator` | The namespace, an OperatorGroup and the Subscription |
| `aap`          | `infrastructure/aap/yojimbo`  | A `Certificate` and the `AnsibleAutomationPlatform` |

`aap` needs three things that other Applications bring: the platform's kind from the operator, a
`Certificate` kind and an issuer from cert-manager, and the `synology-iscsi` storage class. It
retries until all three are there.

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

## Changing it

The platform is now changed like the portal was on Bahamut. To bring automation hub back, for
example, replace its `disabled: true` in `platform.yaml` with its settings, commit and push.
Argo CD applies the object, and the operator does the rest over the next several minutes. The
Application shows `Progressing` until the operator reports the platform ready.

Do the dry run of Lab 3 first:

```bash
oc diff -k infrastructure/aap/yojimbo | grep -E '^[-+] ' | grep -v -e tracking-id -e generation
```

Next: [From Bahamut to Yojimbo](08-from-bahamut-to-yojimbo.md)
