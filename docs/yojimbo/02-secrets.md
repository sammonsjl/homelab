# Lab 2 — Secrets

## What you will have at the end

The five secrets the Applications expect, on the cluster and nowhere in git.

## Why these are done by hand

The repository is public, and a `Secret` in Kubernetes is only encoded, not encrypted. There are
tools that close this gap, by encrypting secrets in git or by fetching them from a vault at sync
time. This cluster uses neither yet. Five secrets are made by hand, once, and the Applications
refer to them by name:

| Secret                 | Namespace      | Keys                  | Used by                                         |
| ---------------------- | -------------- | --------------------- | ----------------------------------------------- |
| `cloudflare-api-token` | `cert-manager` | `token`               | cert-manager, to answer Let's Encrypt's DNS check |
| `cloudflare`           | `cloudflare`   | `ACCOUNT_ID`, `TOKEN` | The tunnel controller                           |
| `client-info-secret`   | `synology-csi` | `client-info.yml`     | The storage driver, to log in to the NAS        |
| `garage`               | `quay`         | `GARAGE_RPC_SECRET`, `GARAGE_ADMIN_TOKEN` | Garage, the mirror's object storage |
| `quay-config`          | `quay`         | `config.yaml`         | Quay, the mirror: its name and Garage's key     |

Until a secret exists, the component that needs it does not start, and its Application is not
`Healthy`. Nothing else is held up by it.

## What each one holds

**The Cloudflare API token** is made in the Cloudflare dashboard, under *My Profile → API
Tokens*. For certificates it needs *Zone → DNS → Edit* and *Zone → Zone → Read* on your domain. The tunnel controller also
needs *Account → Cloudflare Tunnel → Edit*. One token with all of these serves both secrets; two
narrower tokens are better.

**The account ID** is on the overview page of your domain in the same dashboard.

**`client-info.yml`** is the storage driver's own file: the address of the NAS and a user that
may create LUNs.

```yaml
clients:
  - host: 192.168.1.4
    port: 5000
    https: false
    username: <a DSM user in the administrators group>
    password: <its password>
```

**Garage's two secrets** are random strings you make yourself. The RPC secret is 32 bytes of hex,
which its nodes use to trust each other. There is only one node, but Garage does not start without
it. The admin token is for its admin API.

**`config.yaml`** is Quay's own configuration. Most of Quay's settings come from the operator. These
are the ones it cannot know: the name Quay is served at, the first administrator, and where the
image layers go. Garage's access key is made here, ahead of time, and imported into Garage in Lab
7. That way this secret can exist before Garage does. An access key ID is `GK` and 24 hex
characters, and its secret is 64 hex characters.

```yaml
SERVER_HOSTNAME: quay.neokube.net
SUPER_USERS:
  - quayadmin
FEATURE_USER_INITIALIZE: true
FEATURE_USER_CREATION: false
CREATE_NAMESPACE_ON_PUSH: true
CREATE_PRIVATE_REPO_ON_PUSH: false
BROWSER_API_CALLS_XHR_ONLY: false
FEATURE_PROXY_STORAGE: true
DISTRIBUTED_STORAGE_CONFIG:
  garage:
    - RadosGWStorage
    - hostname: garage.quay.svc.cluster.local
      port: 3900
      is_secure: false
      region_name: garage
      signature_version: s3v4
      bucket_name: quay
      storage_path: /datastorage/registry
      access_key: <the access key ID>
      secret_key: <its secret>
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
  - garage
```

`RadosGWStorage` is Quay's driver for any S3 server that is not Amazon's. By default Quay
answers a request for an image layer by sending the client to the S3 server itself, at
`garage.quay.svc.cluster.local`, a name that exists only inside the cluster;
`FEATURE_PROXY_STORAGE` makes Quay pass the layer through instead. The name has to be complete,
with `.cluster.local`: the proxy inside Quay does not try the cluster's search domains.
`FEATURE_USER_INITIALIZE` lets the first user, `quayadmin`, be made through the API, once, while
there are no users. With `FEATURE_USER_CREATION: false`, nobody can sign up afterwards. The two
`CREATE_` settings let a push make the organizations and public repositories the mirror needs
(Lab 7).

To make the four values, and a password for `quayadmin` while you are at it:

```bash
openssl rand -hex 32                     # GARAGE_RPC_SECRET
openssl rand -base64 32                  # GARAGE_ADMIN_TOKEN
echo GK$(openssl rand -hex 12)           # S3_ACCESS_KEY, the access key ID
openssl rand -hex 32                     # S3_SECRET_KEY, its secret
openssl rand -base64 18                  # QUAY_ADMIN_PASSWORD
```

## Create them

On a new cluster the four namespaces do not exist yet. Create them first; the Applications
adopt a namespace that is already there. On a cluster where these components are already
running, the namespaces and the secrets exist and this lab is a check.

```bash
for namespace in cert-manager cloudflare synology-csi quay; do
  oc get namespace $namespace >/dev/null 2>&1 || oc create namespace $namespace
done
```

With the values in Vault, where mine are:

```bash
export VAULT_ADDR=http://192.168.1.4:8200

oc create secret generic cloudflare-api-token -n cert-manager \
  --from-literal=token="$(vault kv get -field=TOKEN secrets/cloudflare)"

oc create secret generic cloudflare -n cloudflare \
  --from-literal=ACCOUNT_ID="$(vault kv get -field=ACCOUNT_ID secrets/cloudflare)" \
  --from-literal=TOKEN="$(vault kv get -field=TOKEN secrets/cloudflare)"

vault kv get -field=client-info.yml secrets/synology > /tmp/client-info.yml
oc create secret generic client-info-secret -n synology-csi --from-file=/tmp/client-info.yml
rm /tmp/client-info.yml

oc create secret generic garage -n quay \
  --from-literal=GARAGE_RPC_SECRET="$(vault kv get -field=GARAGE_RPC_SECRET secrets/quay)" \
  --from-literal=GARAGE_ADMIN_TOKEN="$(vault kv get -field=GARAGE_ADMIN_TOKEN secrets/quay)"
```

For `quay-config`, write the file above to `/tmp/config.yaml` with the key from
`vault kv get -field=S3_ACCESS_KEY secrets/quay` and its secret from `S3_SECRET_KEY`, then:

```bash
oc create secret generic quay-config -n quay --from-file=/tmp/config.yaml
rm /tmp/config.yaml
```

The same `secrets/quay` holds `QUAY_ADMIN_PASSWORD`, for `quayadmin` in Lab 7.

Without Vault, put the values where the `$(vault ...)` calls are, and write `client-info.yml` and
`config.yaml` yourself.

## Check

```bash
oc get secret cloudflare-api-token -n cert-manager -o name
oc get secret cloudflare -n cloudflare -o name
oc get secret client-info-secret -n synology-csi -o name
oc get secret garage quay-config -n quay -o name
```

```
secret/cloudflare-api-token
secret/cloudflare
secret/client-info-secret
secret/garage
secret/quay-config
```

> These five are the part of the cluster that a rebuild from git does not bring back. Keep the
> values somewhere that is not the cluster.

Next: [Before the First Sync](03-before-the-first-sync.md)
