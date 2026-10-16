# Lab 8 — From Bahamut to Yojimbo

## What you will have at the end

A routine for getting a change to production: which commits reach which cluster, how to check
one before it lands, and how to try it on Bahamut first.

## Which cluster does a commit change?

Both clusters follow the same branch. What a commit touches decides who notices:

| The commit changes                                              | Bahamut | Yojimbo |
| --------------------------------------------------------------- | ------- | ------- |
| `clusters/bahamut`, or a folder named `bahamut`                 | Yes     | No      |
| `clusters/yojimbo`, or a folder named `yojimbo`                 | No      | Yes     |
| A folder only Yojimbo uses: storage, the tunnel, the platform   | No      | Yes     |
| A shared folder: `infrastructure/cert-manager/operator`, `apps/homepage/base` | Yes | Yes |

An Application only looks at its own `path`. A commit elsewhere moves the branch, and the
Application notes the new commit and changes nothing.

You saw the first two rows at work already: the portal's links on Bahamut and on Yojimbo are in
different folders, and a change to one never restarted the other.

## A change to one cluster's folder

For anything in Yojimbo's own folders, the routine is the dry run, then the push:

```bash
cd ~/homelab
# edit, then:
oc diff -k <the folder> | grep -E '^[-+] ' | grep -v -e tracking-id -e generation
git commit -am "<what and why>"
git push
oc get applications -n openshift-gitops -w
```

Read the diff with the question from Lab 3: is every line something I meant?

## A change to a shared folder

The last row of the table is where Bahamut earns its keep. A change to the shared base of the
portal, or a new version of the cert-manager operator, reaches production the moment it is on
the branch. To see it on Bahamut first, put it on a branch of its own and point Bahamut at that
branch.

> **Not yet run as written.** The steps below follow from how the Applications are built, and
> each piece was used in the labs before this one. The sequence as a whole has not been run.

Start OpenShift Local, and with `oc` logged in to **Bahamut**:

```bash
git switch -c try-homepage
sed -i 's/targetRevision: openshift-gitops/targetRevision: try-homepage/' \
  clusters/bahamut/root.yaml clusters/bahamut/apps/*.yaml
git commit -am "bahamut: follow try-homepage"
```

Make the change itself as a second commit, so that it can be told apart from the first:

```bash
# edit apps/homepage/base/..., then:
git commit -am "homepage: <the change>"
git push -u origin try-homepage
oc apply -f clusters/bahamut/root.yaml
```

The root has to be applied by hand because nothing manages the root. It then moves its three
children to the new branch by itself. Watch Bahamut until it is `Synced` and `Healthy`, and look
at the result.

When you are satisfied, undo the first commit, merge, and put Bahamut back:

```bash
git revert --no-edit HEAD~1
git switch openshift-gitops
git merge try-homepage
git push
oc apply -f clusters/bahamut/root.yaml
```

After the revert the branch differs from `openshift-gitops` by the change alone. Yojimbo picks it
up from the push, within three minutes.

## When a sync goes wrong

```bash
oc get applications -n openshift-gitops
oc get application <name> -n openshift-gitops \
  -o jsonpath='{.status.operationState.phase}: {.status.operationState.message}{"\n"}'
```

| You see                 | Usually means                                                               |
| ----------------------- | --------------------------------------------------------------------------- |
| `OutOfSync`, and stays  | The sync failed. The message above says on which object                     |
| `Synced`, `Progressing` | Git was applied. A pod, a certificate or an operator is still working       |
| `Synced`, `Degraded`    | Git was applied and something it made is unhealthy. Look at the pods         |
| `Unknown`               | Argo CD cannot render the folder: a YAML error, or a file missing from a `kustomization.yaml` |

The way back from a bad commit is another commit: `git revert`, then `git push`. Changing the
cluster by hand to fix it does not last, as Lab 4 showed.

## What you have

A laptop cluster and a production cluster that are folders in one repository, and a production
cluster that can be read: what runs on it, at which version, with which settings, and when each
of those last changed and why.

What is still done by hand is short, and worth knowing by heart: the five secrets of Lab 2, the
site itself, and whatever lives inside a database.
