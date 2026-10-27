# Lab 4 — A Change Through Git

## What you will have at the end

A change that reached the cluster with no `oc` command, a change made on the cluster by hand that
Argo CD reversed, and Ghost upgraded by a commit.

## Change something in git

Add a link to the portal. Its links are in `apps/homepage/bahamut/services.yaml`:

```bash
cd ~/homelab
cat >> apps/homepage/bahamut/services.yaml <<EOF
    - Homelab repo:
        href: https://github.com/$GITHUB_USER/homelab
        icon: github.png
        description: Where this cluster comes from
EOF

git commit -am "homepage: link to the repo"
git push
```

Note the configuration's name before the change arrives:

```bash
oc get configmap -n homepage | grep homepage-config
```

```
homepage-config-h26ggdcg2h   8      20m
```

## Watch it arrive

```bash
oc get application homepage -n openshift-gitops -w
```

Argo CD asks the repository for new commits every three minutes. When it sees yours, the
Application goes `OutOfSync`, then `Synced` again; on the test run that took one minute from the
push. Press Ctrl-C, and compare the commit Argo CD is at with yours:

```bash
oc get application homepage -n openshift-gitops -o jsonpath='{.status.sync.revision}{"\n"}'
git rev-parse HEAD
```

The two should be the same. To skip the wait, ask for a refresh:

```bash
oc annotate application homepage -n openshift-gitops argocd.argoproj.io/refresh=normal
```

Now look at what changed on the cluster:

```bash
oc get configmap -n homepage | grep homepage-config
oc get pods -n homepage
curl -sk https://homepage.apps-crc.testing/api/services | grep -o 'Homelab repo'
```

```
homepage-config-gbdhdtff89   8      40s
homepage-797b9d5948-tw7pl    1/1    Running   0     31s
Homelab repo
```

Three things happened from one commit:

1. Kustomize names a generated ConfigMap after a hash of its contents. New contents, new name.
2. The Deployment refers to the ConfigMap by name, so the Deployment changed too, and rolled
   out a new pod. An edit to a ConfigMap alone would not have restarted anything.
3. The old ConfigMap was no longer in what git renders, so `prune` deleted it.

## Change something by hand

Delete the portal's Route, as a tired administrator might:

```bash
oc delete route homepage -n homepage
oc get route -n homepage -w
```

```
NAME       HOST/PORT                   PATH   SERVICES   PORT   TERMINATION     WILDCARD
homepage   homepage.apps-crc.testing          homepage   http   edge/Redirect   None
```

It is back within seconds. Argo CD watches the objects it manages, and `selfHeal` puts back what
differs from git without waiting for the three-minute poll.

This cuts both ways. A fix made with `oc edit` on a managed object lasts seconds. From here on,
a fix is a commit.

## Upgrade Ghost through git

> **If a production cluster already follows this branch, do not push this commit.**
> `apps/ghost/base` is not Bahamut's alone: Yojimbo, in module 08, builds its Ghost from the same
> folder. A reader taking the modules in order has no Yojimbo yet, and nothing else reads it. If you
> are coming back to Bahamut with a Yojimbo whose Argo CD follows this repository and branch, this
> push upgrades that Ghost too, and its database migration cannot be undone. Read this section
> without running it, or first point Bahamut at a branch of its own, as Yojimbo's
> [Lab 10](../yojimbo/10-from-bahamut-to-yojimbo.md#a-change-to-a-shared-folder) does with
> `try-homepage`.

Without git, Ghost is upgraded with `oc set image`, and the file it was deployed from goes on
naming the old version. Here the file is the only place the version is set:

```bash
grep image: apps/ghost/base/ghost.yaml
```

```
          image: docker.io/library/ghost:6.70.0
```

Change it, and push:

```bash
sed -i 's#ghost:6.70.0#ghost:6.71.0#' apps/ghost/base/ghost.yaml
git commit -am "ghost: 6.71.0"
git push
oc annotate application ghost -n openshift-gitops argocd.argoproj.io/refresh=normal
oc get application ghost -n openshift-gitops -w
```

The Application goes `Progressing` (with a moment of `OutOfSync`, if you are quick) while the
old pod stops and the new one migrates the database, then `Healthy`; under twenty seconds on the
test run. Press Ctrl-C, and ask Ghost:

```bash
curl -sk https://ghost.apps-crc.testing/ghost/api/admin/site/ | grep -o '"version":"[^"]*"'
oc logs deploy/ghost -n ghost | grep -i migration
```

```
"version":"6.71"
WARN Database state requires migration.
INFO Running migrations.
```

Try the way without git, and see what becomes of it:

```bash
oc set image deployment/ghost -n ghost ghost=docker.io/library/ghost:6.70.0
oc get pods -n ghost -l app.kubernetes.io/name=ghost -w
```

Watch for a minute, then press Ctrl-C and look again:

```bash
oc get deployment ghost -n ghost -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -sk https://ghost.apps-crc.testing/ghost/api/admin/site/ | grep -o '"version":"[^"]*"'
```

```
docker.io/library/ghost:6.71.0
"version":"6.71"
```

`selfHeal` put the commit's version back within seconds. It did not stop what your change had
already set off. On the test run, the Deployment acted on `6.70.0` at once: with `Recreate` it
stopped the running Ghost and started an old one against the migrated database, then, when
Argo CD put `6.71.0` back, stopped that one and started a new 6.71.0. The site was down for about
45 seconds, for a change that lasted five.

`selfHeal` undoes a change; it does not undo what the change did in the meantime. A fix by hand
on a managed object is not just short-lived, it can cost a restart. Rolling back for real is a
commit too, with the same warning as before: an older Ghost cannot read a database a newer one
has migrated.

## What you have

A cluster whose contents are a folder in a repository, and a place to try a change before the
production cluster sees it. The next module, [OKD on One Machine](https://github.com/sammonsjl/okd-single-node),
installs a real machine, and [Yojimbo](../yojimbo/01-prerequisites.md) hands that machine to the
same repository.

Next: [Cleaning Up](99-cleanup.md)
