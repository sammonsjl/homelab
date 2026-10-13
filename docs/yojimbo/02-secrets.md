# Lab 2 — Secrets

## What you will have at the end

The three secrets the Applications expect, on the cluster and nowhere in git.

## Why these are done by hand

The repository is public, and a `Secret` in Kubernetes is only encoded, not encrypted. There are
tools that close this gap, by encrypting secrets in git or by fetching them from a vault at sync
time. This cluster uses neither yet. Three secrets are made by hand, once, and the Applications
refer to them by name:

| Secret                 | Namespace      | Keys                  | Used by                                         |
| ---------------------- | -------------- | --------------------- | ----------------------------------------------- |
| `cloudflare-api-token` | `cert-manager` | `token`               | cert-manager, to answer Let's Encrypt's DNS check |
| `cloudflare`           | `cloudflare`   | `ACCOUNT_ID`, `TOKEN` | The tunnel controller                           |
| `client-info-secret`   | `synology-csi` | `client-info.yml`     | The storage driver, to log in to the NAS        |

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

## Create them

On a new cluster the three namespaces do not exist yet. Create them first; the Applications
adopt a namespace that is already there. On a cluster where these components are already
running, the namespaces and the secrets exist and this lab is a check.

```bash
for namespace in cert-manager cloudflare synology-csi; do
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
```

Without Vault, put the values where the `$(vault ...)` calls are, and write `client-info.yml`
yourself.

## Check

```bash
oc get secret cloudflare-api-token -n cert-manager -o name
oc get secret cloudflare -n cloudflare -o name
oc get secret client-info-secret -n synology-csi -o name
```

```
secret/cloudflare-api-token
secret/cloudflare
secret/client-info-secret
```

> These three are the part of the cluster that a rebuild from git does not bring back. Keep the
> values somewhere that is not the cluster.

Next: [Before the First Sync](03-before-the-first-sync.md)
