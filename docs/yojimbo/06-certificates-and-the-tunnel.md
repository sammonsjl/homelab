# Lab 6 — Certificates and the Tunnel

## What you will have at the end

An understanding of how every name on the cluster gets a certificate browsers trust without the
cluster being reachable from the internet, and of how one site is published through a tunnel.

## Names that only exist at home

The cluster's names, `api.lud.neokube.net` and everything under `apps.lud.neokube.net`, resolve
only on my network. No port is open to the internet. Let's Encrypt cannot connect to the cluster
to check that I own those names.

It does not have to. With the DNS-01 challenge, Let's Encrypt asks for a TXT record to appear in
the public DNS zone of the domain. cert-manager creates that record through Cloudflare's API,
using the token from Lab 2, and removes it afterwards. The certificate is for a name the public
cannot reach, proved through a zone the public can read.

```bash
oc get clusterissuer
oc get certificate -A
```

```
NAME                  READY   AGE
letsencrypt           True    9d
letsencrypt-staging   True    9d

NAMESPACE           NAME            READY   SECRET                AGE
aap                 aap             True    aap-neokube-net-tls   7d21h
openshift-config    api             True    api-tls               9d
openshift-config    lud-console     True    lud-neokube-net-tls   9d
openshift-ingress   apps-wildcard   True    apps-wildcard-tls     9d
```

There are two issuers on purpose. Let's Encrypt limits how many certificates it issues for a
domain in a week, and a misconfigured issuer asks again and again. Point a new `Certificate` at
`letsencrypt-staging` first. Its certificates are not trusted by browsers, and its limits are
generous. When it turns `Ready`, change the issuer's name.

## One setting behind a local DNS server

Before it asks Let's Encrypt to look, cert-manager checks for the TXT record itself. On a
network with its own DNS server, it asks that server, which may answer for the domain itself and
never see the record. The folder tells cert-manager to ask public resolvers:

```bash
cat infrastructure/cert-manager/yojimbo/certmanager.yaml
```

```yaml
apiVersion: operator.openshift.io/v1alpha1
kind: CertManager
metadata:
  name: cluster
  annotations:
    argocd.argoproj.io/sync-options: Prune=false
spec:
  controllerConfig:
    overrideArgs:
      - --dns01-recursive-nameservers-only
      - --dns01-recursive-nameservers=1.1.1.1:53,9.9.9.9:53
```

## Objects the cluster owns

Look at the annotation in that file. `CertManager/cluster` was not created by this repository.
The operator made it, and git only sets two fields on it. The same is true of three more objects
in this folder:

| Object                      | Made by            | What git sets on it                                |
| --------------------------- | ------------------ | -------------------------------------------------- |
| `CertManager/cluster`       | The cert-manager operator | The resolver arguments                      |
| `IngressController/default` | The installer      | `defaultCertificate`: the wildcard for `*.apps`    |
| `APIServer/cluster`         | The installer      | A named certificate for `api.lud.neokube.net`      |
| `Ingress/cluster`           | The installer      | A second host name for the console                 |

Every Application here has `prune: true`: take a file out of git and its objects are deleted
from the cluster. For a Deployment of your own that is what you want. For the router's
configuration it would be a disaster. `Prune=false` on an object says: manage these fields, and
never delete the object, whatever happens to the file.

Setting those fields is how the certificates get used:

```bash
oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.spec.defaultCertificate}{"\n"}'
```

```
{"name":"apps-wildcard-tls"}
```

The router serves that one wildcard certificate for every Route, which is why the portal, the
console and Argo CD all have a trusted certificate without a `Certificate` of their own. On a
new cluster, the router restarts when this is first set, and the API server restarts to pick up
its certificate. On one node, the API is away for a few minutes while it does.

## The tunnel

One name is public: neokube.net. It does not come in through a port on my router. A
`cloudflared` pod on the cluster makes an outbound connection to Cloudflare, and Cloudflare
sends the site's visitors down it.

Nobody writes that pod's configuration. A controller turns Gateway API objects into it:

| Object                       | Where                     | Becomes                                        |
| ---------------------------- | ------------------------- | ---------------------------------------------- |
| `GatewayClass` `cloudflare`  | `infrastructure/cloudflare` | Names the controller and the secret from Lab 2 |
| `Gateway` `gateway`          | `infrastructure/cloudflare` | A tunnel in my Cloudflare account, and a `cloudflared` Deployment connected to it |
| `HTTPRoute` `neokube-net`    | The site's own repository | A public host name on the tunnel and its DNS record, pointing at the site's Service |

```bash
oc get gatewayclass,gateway -A
oc get pods -n cloudflare
oc get httproute -A
```

The gateway should be `Programmed`, its class `Accepted`, and two pods `Running`: the controller
and `cloudflared`. The last command lists the one route:

```
NAMESPACE   NAME          HOSTNAMES         AGE
liferay     neokube-net   ["neokube.net"]   8d
```

The route is in the site's namespace and the gateway in another, and that is the setting Lab 3
caught:

```yaml
      allowedRoutes:
        namespaces:
          from: All
```

OpenShift ships the Gateway API kinds, so the controller is all that has to be installed. It is
pulled in at a tag, like the local-path provisioner:

```bash
cat infrastructure/cloudflare/controller/kustomization.yaml
```

Everything inside the cluster is still a Route on OpenShift's own router. The Gateway API is
used for this one job.

Next: [The Automation Platform](07-the-automation-platform.md)
