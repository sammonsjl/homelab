# Lab 4 — A Change Through Git

## What you will have at the end

A change that reached the cluster with no `oc` command, and a change made on the cluster by hand
that Argo CD reversed.

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

## What you have

A cluster whose contents are a folder in a repository, and a place to try a change before the
production cluster sees it. The next module, [Yojimbo](../yojimbo/01-prerequisites.md), hands a
real machine to the same repository.

Next: [Cleaning Up](99-cleanup.md)
