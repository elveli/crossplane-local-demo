# Live Transcript: `make up`, `make demo`, status, logs, render and test

A real, unedited run on the reference Intel Mac (Docker Desktop Kubernetes v1.34.3,
Crossplane 2.4.3, crossplane CLI v2.5.0), recorded on 2026-11-23. Use it to see what
each step prints before running it yourself, or to compare against your own run.

Back to the [README](../README.md#the-demo-scene-by-scene).

- [`make up`](#make-up): Crossplane, providers, functions, CNPG operator, App API (about 3 min here)
- [`make demo`](#make-demo): the 7 scenes
  1. [Request an App](#17-request-an-app-and-watch-it-come-up)
  2. [Use it from the Mac](#27-use-it-from-the-mac)
  3. [Drift correction](#37-drift-correction)
  4. [Change propagation](#47-change-propagation)
  5. [Validation](#57-validation)
  6. [Offline render](#67-offline-render)
  7. [Delete the App](#77-delete-the-app)
- [`make status`](#make-status): health check afterwards
- [`make crossplane-status` and `make providers-status`](#make-crossplane-status-and-make-providers-status): narrower status views
- [`make logs-crossplane`](#make-logs-crossplane): the core Crossplane log, and what its warnings mean
- [Re-running `make providers` and `make apis`](#re-running-make-providers-and-make-apis): safe to repeat; everything reports `unchanged`
- [`make render`](#make-render): the full desired state, offline
- [`make test`](#make-test): golden renders and schema validation, offline

The demo script sets the context itself, so its `kubectl` and `crossplane` lines omit
`--context docker-desktop`. Add it when you type them yourself (see
[Crossplane CLI by Example](../README.md#crossplane-cli-by-example)).

## `make up`

```text
$ make up
CLUSTER=docker-desktop ./scripts/cluster-up.sh
== Host
arch: x86_64  macOS: 26.7.3
== Tools
kubectl v1.37.2 | helm v4.3.1+gc0d08d0 | crossplane CLI v2.5.0
== Docker Desktop resources
CPUs: 16  Memory: ~15 GiB
== Cluster (docker-desktop)
NAME                    STATUS   ROLES           AGE    VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION    CONTAINER-RUNTIME
desktop-control-plane   Ready    control-plane   249d   v1.34.3   172.18.0.9    <none>        Debian GNU/Linux 12 (bookworm)   7.0.14-linuxkit   containerd://2.2.0
/Library/Developer/CommandLineTools/usr/bin/make crossplane providers apis
helm --kube-context docker-desktop repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
helm --kube-context docker-desktop repo update crossplane-stable >/dev/null
helm --kube-context docker-desktop upgrade --install crossplane crossplane-stable/crossplane \
	  --version 2.4.3 --namespace crossplane-system --create-namespace \
	  -f cluster/crossplane-values.yaml --wait --timeout 5m
Release "crossplane" does not exist. Installing it now.
NAME: crossplane
LAST DEPLOYED: Mon Nov 23 21:01:36 2026
NAMESPACE: crossplane-system
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
Release: crossplane

Chart Name: crossplane
Chart Description: Crossplane is an open source Kubernetes add-on that enables platform teams to assemble infrastructure from multiple vendors, and expose higher level self-service APIs for application teams to consume.
Chart Version: 2.4.3
Chart Application Version: 2.4.3

Kube Version: v1.34.3
kubectl --context docker-desktop -n crossplane-system rollout status deploy/crossplane deploy/crossplane-rbac-manager --timeout=180s
deployment "crossplane" successfully rolled out
deployment "crossplane-rbac-manager" successfully rolled out
kubectl --context docker-desktop wait --for=condition=Established --timeout=120s \
	  crd/compositeresourcedefinitions.apiextensions.crossplane.io \
	  crd/compositions.apiextensions.crossplane.io \
	  crd/providers.pkg.crossplane.io crd/functions.pkg.crossplane.io
customresourcedefinition.apiextensions.k8s.io/compositeresourcedefinitions.apiextensions.crossplane.io condition met
customresourcedefinition.apiextensions.k8s.io/compositions.apiextensions.crossplane.io condition met
customresourcedefinition.apiextensions.k8s.io/providers.pkg.crossplane.io condition met
customresourcedefinition.apiextensions.k8s.io/functions.pkg.crossplane.io condition met
ok    provider-kubernetes              v1.4.1
ok    provider-helm                    v1.5.0
ok    function-patch-and-transform     v0.11.2
ok    function-go-templating           v0.13.2
ok    function-auto-ready              v0.7.3
ok    provider-family-aws              v2.10.0
ok    provider-aws-s3                  v2.10.0
ok    provider-aws-dynamodb            v2.10.0
ok    localstack image (localstack.yaml) 4.14.0
ok    localstack image (aws-writer.yaml) 4.14.0
ok    cnpg/cluster chart (app-dev.yaml) 0.9.0
ok    postgres image (app-dev.yaml)    18.7-minimal-trixie
ok    cnpg/cluster chart (app-prod.yaml) 0.9.0
ok    postgres image (app-prod.yaml)   18.7-minimal-trixie
CLUSTER=docker-desktop ./scripts/prepull.sh packages
prepull xpkg.crossplane.io/crossplane-contrib/provider-kubernetes:v1.4.1            ok
prepull xpkg.crossplane.io/crossplane-contrib/provider-helm:v1.5.0                  ok
prepull xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.11.2  ok
prepull xpkg.crossplane.io/crossplane-contrib/function-go-templating:v0.13.2        ok
prepull xpkg.crossplane.io/crossplane-contrib/function-auto-ready:v0.7.3            ok
kubectl --context docker-desktop apply -f crossplane/providers/01-runtime-config.yaml \
	           -f crossplane/providers/02-providers.yaml \
	           -f crossplane/providers/03-rbac.yaml \
	           -f crossplane/functions/functions.yaml
deploymentruntimeconfig.pkg.crossplane.io/provider-kubernetes created
deploymentruntimeconfig.pkg.crossplane.io/provider-helm created
provider.pkg.crossplane.io/provider-kubernetes created
provider.pkg.crossplane.io/provider-helm created
clusterrole.rbac.authorization.k8s.io/crossplane-demo:provider-helm created
clusterrolebinding.rbac.authorization.k8s.io/crossplane-demo:provider-helm created
clusterrole.rbac.authorization.k8s.io/crossplane-demo:provider-kubernetes created
clusterrolebinding.rbac.authorization.k8s.io/crossplane-demo:provider-kubernetes created
function.pkg.crossplane.io/function-patch-and-transform created
function.pkg.crossplane.io/function-go-templating created
function.pkg.crossplane.io/function-auto-ready created
kubectl --context docker-desktop wait --for=condition=Healthy --timeout=8m providers.pkg.crossplane.io,functions.pkg.crossplane.io --all
provider.pkg.crossplane.io/provider-helm condition met
provider.pkg.crossplane.io/provider-kubernetes condition met
function.pkg.crossplane.io/function-auto-ready condition met
function.pkg.crossplane.io/function-go-templating condition met
function.pkg.crossplane.io/function-patch-and-transform condition met
kubectl --context docker-desktop apply -f crossplane/providers/04-providerconfigs.yaml
clusterproviderconfig.kubernetes.m.crossplane.io/default created
clusterproviderconfig.helm.m.crossplane.io/default created
/Library/Developer/CommandLineTools/usr/bin/make cnpg
CLUSTER=docker-desktop ./scripts/prepull.sh cnpg
prepull ghcr.io/cloudnative-pg/cloudnative-pg:1.30.2                                ok
prepull ghcr.io/cloudnative-pg/postgresql:18.7-minimal-trixie                       ok
helm --kube-context docker-desktop repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
helm --kube-context docker-desktop repo update cnpg >/dev/null
helm --kube-context docker-desktop upgrade --install cnpg cnpg/cloudnative-pg --version 0.29.2 \
	  --namespace cnpg-system --create-namespace -f cluster/cnpg-values.yaml --wait --timeout 5m
Release "cnpg" does not exist. Installing it now.
NAME: cnpg
LAST DEPLOYED: Mon Nov 23 21:04:13 2026
NAMESPACE: cnpg-system
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
CloudNativePG operator should be installed in namespace "cnpg-system".
You can now create a PostgreSQL cluster with 3 nodes as follows:

cat <<EOF | kubectl apply -f -
# Example of PostgreSQL cluster
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: cluster-example

spec:
  instances: 3
  storage:
    size: 1Gi
EOF

kubectl get -A cluster
kubectl --context docker-desktop wait --for=condition=Established --timeout=120s crd/clusters.postgresql.cnpg.io
customresourcedefinition.apiextensions.k8s.io/clusters.postgresql.cnpg.io condition met
CLUSTER=docker-desktop ./scripts/prepull.sh app
prepull nginxdemos/hello:plain-text                                                 ok
kubectl --context docker-desktop apply -f crossplane/apis/crossplane-rbac.yaml -f crossplane/apis/app-xrd.yaml
clusterrole.rbac.authorization.k8s.io/crossplane-demo:compose-native created
compositeresourcedefinition.apiextensions.crossplane.io/apps.platform.demo.io created
kubectl --context docker-desktop wait --for=condition=Established --timeout=120s xrd/apps.platform.demo.io
compositeresourcedefinition.apiextensions.crossplane.io/apps.platform.demo.io condition met
kubectl --context docker-desktop apply -f crossplane/compositions/
composition.apiextensions.crossplane.io/app-dev created
composition.apiextensions.crossplane.io/app-prod created
kubectl --context docker-desktop get xrd,compositions
NAME                                                                            ESTABLISHED   OFFERED   AGE
compositeresourcedefinition.apiextensions.crossplane.io/apps.platform.demo.io   True                    2s

NAME                                               XR-KIND   XR-APIVERSION               AGE
composition.apiextensions.crossplane.io/app-dev    App       platform.demo.io/v1alpha1   0s
composition.apiextensions.crossplane.io/app-prod   App       platform.demo.io/v1alpha1   0s
```

## `make demo`

```text
$ make demo
CLUSTER=docker-desktop ./scripts/demo.sh

  Crossplane v2 local demo   context=docker-desktop   namespace=team-a
  A developer asks for an "App"; the platform's Composition turns it into a
  Deployment, Service, a CloudNativePG Postgres (via provider-helm) and a
  connection Secret -- and keeps them that way.

  ⏎ Enter to continue (Ctrl-C to quit)
```

### 1/7 Request an App and watch it come up

```text
━━━ 1/7  Request an App and watch it come up ━━━
$ cat examples/hello.yaml
# The developer-facing request. No compositionSelector -> the XRD's default
# Composition (app-dev) is used.
apiVersion: platform.demo.io/v1alpha1
kind: App
metadata:
  name: hello
  namespace: team-a
spec:
  image: nginxdemos/hello:plain-text
  replicas: 2
  port: 80
  database:
    enabled: true
    size: small   # small|medium
  expose: true
$ kubectl apply -f examples/namespace.yaml -f examples/hello.yaml
namespace/team-a created
app.platform.demo.io/hello created
▶ Watching the XR (SYNCED → READY). Postgres takes ~1 minute on a laptop:
$ kubectl get app -n team-a -w
NAME    IMAGE                         REPLICAS   URL   DB-READY   SYNCED   READY   COMPOSITION   AGE
hello   nginxdemos/hello:plain-text   2                                                          0s
hello   nginxdemos/hello:plain-text   2                                            app-dev       0s
hello   nginxdemos/hello:plain-text   2                                            app-dev       0s
hello   nginxdemos/hello:plain-text   2                                            app-dev       1s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false                       app-dev       1s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       1s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       1s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       1s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       2s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       2s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       2s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       2s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       3s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       3s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       4s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       4s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       4s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       4s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       57s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       57s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       57s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       57s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       57s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   false      True     False   app-dev       57s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   true       True     False   app-dev       60s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   true       True     True    app-dev       61s
hello   nginxdemos/hello:plain-text   2          http://localhost:80   true       True     True    app-dev       61s
  ✔ App/hello is Ready  (62s)
▶ The tree of everything Crossplane composed for this one App:
$ crossplane resource trace app/hello -n team-a
NAME                                     SYNCED   READY   STATUS
App/hello (team-a)                       True     True    Available
├─ Deployment/hello (team-a)             -        -
├─ Release/hello-db (team-a)             True     True    Available
├─ Object/hello-db-app-secret (team-a)   True     True    Available
├─ Object/hello-db-cluster (team-a)      True     True    Available
├─ Secret/hello-db-conn (team-a)         -        -
└─ Service/hello (team-a)                -        -
$ kubectl -n team-a get app hello -o jsonpath='{.status}' | python3 -m json.tool | grep -vE 'lastTransitionTime|observedGeneration'
{
    "availableReplicas": 2,
    "awsConfig": "",
    "bucket": "",
    "conditions": [
        {
            "reason": "ReconcileSuccess",
            "status": "True",
            "type": "Synced"
        },
        {
            "reason": "Available",
            "status": "True",
            "type": "Ready"
        },
        {
            "reason": "WatchCircuitClosed",
            "status": "True",
            "type": "Responsive"
        }
    ],
    "connectionSecret": "hello-db-conn",
    "dbReady": true,
    "table": "",
    "url": "http://localhost:80"
}

  ⏎ Enter to continue (Ctrl-C to quit)
```

### 2/7 Use it from the Mac

```text
━━━ 2/7  Use it from the Mac ━━━
▶ status.url = http://localhost:80  (expose: true → Service type LoadBalancer → Docker Desktop forwards it)
$ curl -s http://localhost:80
Server address: 10.244.0.47:80
Server name: hello-bf89fb5cc-5pvbt
Date: 24/Nov/2026:05:06:16 +0000
URI: /
Request ID: e89e4b1f165eeea85b4b313627b5ac16
▶ 8 more requests -- which replicas answered?
$ for i in $(seq 8); do curl -s http://localhost:80 | sed -n 's/Server name: //p'; done | sort | uniq -c
   3 hello-bf89fb5cc-5pvbt
   5 hello-bf89fb5cc-jbcvj
  Pod names = the replicas behind the Service (kube-proxy picks one per connection).
▶ The App's connection Secret (composed from the CNPG-generated credentials):
$ kubectl -n team-a get secret hello-db-conn -o jsonpath='{.data}'   # (decoded, password masked)
  dbname    app
  host      hello-db-rw
  password  ********
  port      5432
  username  app
▶ Prove it works -- log in to Postgres with exactly those credentials:
$ kubectl -n team-a exec hello-db-1 -- psql -h hello-db-rw -U app -d app   # password from hello-db-conn
app|PostgreSQL 18.7 (Debian 18.7-1.pgdg13+5)

  ⏎ Enter to continue (Ctrl-C to quit)
```

### 3/7 Drift correction

```text
━━━ 3/7  Drift correction: Crossplane puts things back ━━━
▶ Someone scales the Deployment by hand to 5 replicas...
$ kubectl -n team-a scale deploy/hello --replicas=5
deployment.apps/hello scaled
  ✔ Crossplane reverted spec.replicas to 2  (2s)
  metadata.generation 1 → 3: one bump for our scale to 5, one for Crossplane's revert to 2.
  Who wrote spec.replicas last? (server-side apply field managers):
    apiextensions.crossplane.io/composed/1626c37… Apply  2026-11-24T05:07:19Z
$ kubectl -n team-a get deploy hello
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
hello   2/2     2            2           2m20s
▶ ...then deletes the Deployment outright:
$ kubectl -n team-a delete deploy/hello
deployment.apps "hello" deleted from team-a namespace
  ✔ Deployment recreated  (0s)
  uid 090c0d04… → 4f074a1e… (a brand-new object)
  ✔ and back to 2/2 available  (5s)
$ kubectl -n team-a get deploy hello
NAME    READY   UP-TO-DATE   AVAILABLE   AGE
hello   2/2     2            2           5s
  Crossplane v2 watches composed resources, so drift is fixed in seconds -- not at the next poll.

  ⏎ Enter to continue (Ctrl-C to quit)
```

### 4/7 Change propagation

```text
━━━ 4/7  Change propagation: edit the App, not the resources ━━━
▶ Scale through the platform API (spec.replicas 2 → 3):
$ kubectl -n team-a patch app hello --type merge -p '{"spec":{"replicas":3}}'
app.platform.demo.io/hello patched
  ✔ Deployment now has 3 available replicas  (2s)
$ kubectl -n team-a get app,deploy
NAME                         IMAGE                         REPLICAS   URL                   DB-READY   SYNCED   READY   COMPOSITION   AGE
app.platform.demo.io/hello   nginxdemos/hello:plain-text   3          http://localhost:80   true       True     True    app-dev       3m17s

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/hello   3/3     3            3           56s
▶ Turn the database off (database.enabled: false):
$ kubectl -n team-a patch app hello --type merge -p '{"spec":{"database":{"enabled":false}}}'
app.platform.demo.io/hello patched
  ✔ Release, Postgres Cluster, observers and connection Secret removed  (5s)
$ crossplane resource trace app/hello -n team-a
NAME                           SYNCED   READY   STATUS
App/hello (team-a)             True     True    Available
├─ Deployment/hello (team-a)   -        -
└─ Service/hello (team-a)      -        -
$ kubectl -n team-a get app hello
NAME    IMAGE                         REPLICAS   URL                   DB-READY   SYNCED   READY   COMPOSITION   AGE
hello   nginxdemos/hello:plain-text   3          http://localhost:80   false      True     True    app-dev       3m23s

  ⏎ Enter to continue (Ctrl-C to quit)
```

### 5/7 Validation

```text
━━━ 5/7  Policy-like validation: the XRD schema is the contract ━━━
▶ Ask for a database size the platform doesn't offer:
$ sed "s/size: small/size: huge/" examples/hello.yaml | kubectl apply -f -
The App "hello" is invalid: spec.database.size: Unsupported value: "huge": supported values: "small", "medium"
  ✔ Rejected by the API server -- Crossplane never even saw it
▶ Same for out-of-range replicas:
$ sed "s/replicas: 2/replicas: 50/" examples/hello.yaml | kubectl apply -f -
The App "hello" is invalid: spec.replicas: Invalid value: 50: spec.replicas in body should be less than or equal to 10
  ✔ Rejected (maximum: 10)

  ⏎ Enter to continue (Ctrl-C to quit)
```

### 6/7 Offline render

```text
━━━ 6/7  Offline testing with crossplane composition render (no cluster) ━━━
  render runs the real function containers in local Docker, against files only.
$ crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml crossplane/functions/functions.yaml | grep -E '^kind:|^  name:|dbReady|url:'
kind: App
  name: hello
  dbReady: false
  url: http://localhost:80
kind: Release
  name: hello-db
kind: Deployment
  name: hello
kind: Service
  name: hello
▶ Simulate 'Postgres is up' with observed resources -> the connection Secret appears:
$ crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml crossplane/functions/functions.yaml --observed-resources tests/fixtures/observed-db-ready.yaml | grep -E '^kind:|^  name:|dbReady|connectionSecret:'
kind: App
  name: hello
  connectionSecret: hello-db-conn
  dbReady: true
kind: Secret
  name: hello-db-conn
kind: Object
  name: hello-db-app-secret
kind: Object
  name: hello-db-cluster
kind: Release
  name: hello-db
kind: Deployment
  name: hello
kind: Service
  name: hello
▶ Same App against the prod Composition (2 Postgres instances + PDBs):
$ crossplane composition render examples/hello-prod.yaml crossplane/compositions/app-prod.yaml crossplane/functions/functions.yaml | grep -E '^kind:|instances:|enablePDB|minAvailable'
kind: App
kind: Release
        enablePDB: true
        instances: 2
kind: Deployment
kind: PodDisruptionBudget
  minAvailable: 1
kind: Service

  ⏎ Enter to continue (Ctrl-C to quit)
```

### 7/7 Delete the App

```text
━━━ 7/7  Delete the App: everything cascades away ━━━
$ kubectl -n team-a delete app hello --wait=false
app.platform.demo.io "hello" deleted from team-a namespace
  ✔ all composed resources gone  (3s)
$ kubectl -n team-a get all,secret,pvc,clusters.postgresql.cnpg.io
No resources found in team-a namespace.
  (the namespace itself stays; 'make down' removes it)

Demo complete.  Try: make render · make test · examples/hello-prod.yaml
```

## `make status`

Run after the demo: packages healthy, all Crossplane pods running, ProviderConfigs in
place. The 2 restarts of provider-kubernetes happened while it was starting up and
didn't recur.

```text
$ make status
kubectl --context docker-desktop get providers.pkg.crossplane.io,functions.pkg.crossplane.io
NAME                                             INSTALLED   HEALTHY   PACKAGE                                                            AGE
provider.pkg.crossplane.io/provider-helm         True        True      xpkg.crossplane.io/crossplane-contrib/provider-helm:v1.5.0         11m
provider.pkg.crossplane.io/provider-kubernetes   True        True      xpkg.crossplane.io/crossplane-contrib/provider-kubernetes:v1.4.1   11m

NAME                                                      INSTALLED   HEALTHY   PACKAGE                                                                      AGE
function.pkg.crossplane.io/function-auto-ready            True        True      xpkg.crossplane.io/crossplane-contrib/function-auto-ready:v0.7.3             11m
function.pkg.crossplane.io/function-go-templating         True        True      xpkg.crossplane.io/crossplane-contrib/function-go-templating:v0.13.2         11m
function.pkg.crossplane.io/function-patch-and-transform   True        True      xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.11.2   11m
kubectl --context docker-desktop get pods -n crossplane-system
NAME                                                       READY   STATUS    RESTARTS        AGE
crossplane-585f4f744-rnpb9                                 1/1     Running   0               11m
crossplane-rbac-manager-f8d4dfc7b-25kzd                    1/1     Running   0               11m
function-auto-ready-df22d0b05328-547f5776d7-nmztj          1/1     Running   0               9m48s
function-go-templating-c12e0186ed5d-68cd656b58-cmjmj       1/1     Running   0               9m48s
function-patch-and-transform-e9fec78aeef5-9d86957f-lbfww   1/1     Running   0               9m48s
provider-helm-a3eada4a7cf4-6c9d58779f-8tnf9                1/1     Running   0               9m45s
provider-kubernetes-2d25dda0c83d-569b8d8b5d-bpbxw          1/1     Running   2 (9m42s ago)   9m45s
kubectl --context docker-desktop get pods -n cnpg-system 2>/dev/null || true
NAME                                   READY   STATUS    RESTARTS   AGE
cnpg-cloudnative-pg-76756d86b5-dzwgc   1/1     Running   0          9m22s
kubectl --context docker-desktop get deploymentruntimeconfigs,clusterproviderconfigs.kubernetes.m.crossplane.io,clusterproviderconfigs.helm.m.crossplane.io
NAME                                                            AGE
deploymentruntimeconfig.pkg.crossplane.io/default               11m
deploymentruntimeconfig.pkg.crossplane.io/provider-helm         11m
deploymentruntimeconfig.pkg.crossplane.io/provider-kubernetes   11m

NAME                                                       AGE
clusterproviderconfig.kubernetes.m.crossplane.io/default   9m27s

NAME                                                 AGE
clusterproviderconfig.helm.m.crossplane.io/default   9m27s
```

## `make crossplane-status` and `make providers-status`

Narrower views than `make status`. `crossplane-status` adds the Helm release and
`crossplane version`. That command has no `--context` flag, so the Makefile runs it
against the generated single-context `.local/kubeconfig`.

```text
$ make crossplane-status && make providers-status
kubectl --context docker-desktop get pods -n crossplane-system
NAME                                                       READY   STATUS    RESTARTS      AGE
crossplane-585f4f744-rnpb9                                 1/1     Running   0             13m
crossplane-rbac-manager-f8d4dfc7b-25kzd                    1/1     Running   0             13m
function-auto-ready-df22d0b05328-547f5776d7-nmztj          1/1     Running   0             11m
function-go-templating-c12e0186ed5d-68cd656b58-cmjmj       1/1     Running   0             11m
function-patch-and-transform-e9fec78aeef5-9d86957f-lbfww   1/1     Running   0             11m
provider-helm-a3eada4a7cf4-6c9d58779f-8tnf9                1/1     Running   0             11m
provider-kubernetes-2d25dda0c83d-569b8d8b5d-bpbxw          1/1     Running   2 (11m ago)   11m
helm --kube-context docker-desktop list -n crossplane-system
NAME      	NAMESPACE        	REVISION	UPDATED                             	STATUS  	CHART           	APP VERSION
crossplane	crossplane-system	1       	2026-11-23 21:01:36.055874 -0800 PST	deployed	crossplane-2.4.3	2.4.3
KUBECONFIG=.local/kubeconfig crossplane version
Client Version: v2.5.0
Server Version: v2.4.3
kubectl --context docker-desktop get providers.pkg.crossplane.io,functions.pkg.crossplane.io
NAME                                             INSTALLED   HEALTHY   PACKAGE                                                            AGE
provider.pkg.crossplane.io/provider-helm         True        True      xpkg.crossplane.io/crossplane-contrib/provider-helm:v1.5.0         13m
provider.pkg.crossplane.io/provider-kubernetes   True        True      xpkg.crossplane.io/crossplane-contrib/provider-kubernetes:v1.4.1   13m

NAME                                                      INSTALLED   HEALTHY   PACKAGE                                                                      AGE
function.pkg.crossplane.io/function-auto-ready            True        True      xpkg.crossplane.io/crossplane-contrib/function-auto-ready:v0.7.3             13m
function.pkg.crossplane.io/function-go-templating         True        True      xpkg.crossplane.io/crossplane-contrib/function-go-templating:v0.13.2         13m
function.pkg.crossplane.io/function-patch-and-transform   True        True      xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.11.2   13m
```

## `make logs-crossplane`

Tails the core Crossplane pod. It was stopped with Ctrl-C, which is why make reports
`Error 1`; that's expected. The `Warning:` lines are Kubernetes API server warnings
about Crossplane's own built-in types: the legacy `Usage` API, the v1 XRD API, and
finalizer names without a `/`. Crossplane triggers them at startup. They don't come
from this demo's manifests and are harmless.

```text
$ make logs-crossplane
kubectl --context docker-desktop logs -n crossplane-system -l app=crossplane -f
Defaulted container "crossplane" out of: crossplane, crossplane-init (init)
{"level":"info","ts":"2026-11-24T05:02:00Z","logger":"crossplane","msg":"Beta feature enabled","flag":"EnableBetaDeploymentRuntimeConfigs"}
{"level":"info","ts":"2026-11-24T05:02:00Z","logger":"crossplane","msg":"Beta feature enabled","flag":"EnableBetaClaimSSA"}
{"level":"info","ts":"2026-11-24T05:02:00Z","logger":"crossplane","msg":"Package Runtime for Provider: Deployment"}
{"level":"info","ts":"2026-11-24T05:02:00Z","logger":"crossplane","msg":"Package Runtime for Function: Deployment"}
Warning: apiextensions.crossplane.io Usage is deprecated; migrate to protection.crossplane.io Usage or ClusterUsage
Warning: CompositeResourceDefinition v1 is deprecated and will be removed in a future release; consider migrating to v2
Warning: metadata.finalizers: "revision.pkg.crossplane.io": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers
Warning: metadata.finalizers: "lock.pkg.crossplane.io": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers
Warning: metadata.finalizers: "defined.apiextensions.crossplane.io": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers
Warning: metadata.finalizers: "composite.apiextensions.crossplane.io": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers
^Cmake: *** [logs-crossplane] Error 1
```

## Re-running `make providers` and `make apis`

Both targets are safe to run again on an installed cluster. Every `kubectl apply`
reports `unchanged` and the waits return at once. The only visible change is that
Helm bumps the CNPG release to `REVISION: 2`, even though nothing in it changed.

```text
$ make providers
ok    provider-kubernetes              v1.4.1
ok    provider-helm                    v1.5.0
ok    function-patch-and-transform     v0.11.2
ok    function-go-templating           v0.13.2
ok    function-auto-ready              v0.7.3
ok    provider-family-aws              v2.10.0
ok    provider-aws-s3                  v2.10.0
ok    provider-aws-dynamodb            v2.10.0
ok    localstack image (localstack.yaml) 4.14.0
ok    localstack image (aws-writer.yaml) 4.14.0
ok    cnpg/cluster chart (app-dev.yaml) 0.9.0
ok    postgres image (app-dev.yaml)    18.7-minimal-trixie
ok    cnpg/cluster chart (app-prod.yaml) 0.9.0
ok    postgres image (app-prod.yaml)   18.7-minimal-trixie
CLUSTER=docker-desktop ./scripts/prepull.sh packages
prepull xpkg.crossplane.io/crossplane-contrib/provider-kubernetes:v1.4.1            ok
prepull xpkg.crossplane.io/crossplane-contrib/provider-helm:v1.5.0                  ok
prepull xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.11.2  ok
prepull xpkg.crossplane.io/crossplane-contrib/function-go-templating:v0.13.2        ok
prepull xpkg.crossplane.io/crossplane-contrib/function-auto-ready:v0.7.3            ok
kubectl --context docker-desktop apply -f crossplane/providers/01-runtime-config.yaml \
	           -f crossplane/providers/02-providers.yaml \
	           -f crossplane/providers/03-rbac.yaml \
	           -f crossplane/functions/functions.yaml
deploymentruntimeconfig.pkg.crossplane.io/provider-kubernetes unchanged
deploymentruntimeconfig.pkg.crossplane.io/provider-helm unchanged
provider.pkg.crossplane.io/provider-kubernetes unchanged
provider.pkg.crossplane.io/provider-helm unchanged
clusterrole.rbac.authorization.k8s.io/crossplane-demo:provider-helm unchanged
clusterrolebinding.rbac.authorization.k8s.io/crossplane-demo:provider-helm unchanged
clusterrole.rbac.authorization.k8s.io/crossplane-demo:provider-kubernetes unchanged
clusterrolebinding.rbac.authorization.k8s.io/crossplane-demo:provider-kubernetes unchanged
function.pkg.crossplane.io/function-patch-and-transform unchanged
function.pkg.crossplane.io/function-go-templating unchanged
function.pkg.crossplane.io/function-auto-ready unchanged
kubectl --context docker-desktop wait --for=condition=Healthy --timeout=8m providers.pkg.crossplane.io,functions.pkg.crossplane.io --all
provider.pkg.crossplane.io/provider-helm condition met
provider.pkg.crossplane.io/provider-kubernetes condition met
function.pkg.crossplane.io/function-auto-ready condition met
function.pkg.crossplane.io/function-go-templating condition met
function.pkg.crossplane.io/function-patch-and-transform condition met
kubectl --context docker-desktop apply -f crossplane/providers/04-providerconfigs.yaml
clusterproviderconfig.kubernetes.m.crossplane.io/default unchanged
clusterproviderconfig.helm.m.crossplane.io/default unchanged
/Library/Developer/CommandLineTools/usr/bin/make cnpg
CLUSTER=docker-desktop ./scripts/prepull.sh cnpg
prepull ghcr.io/cloudnative-pg/cloudnative-pg:1.30.2                                ok
prepull ghcr.io/cloudnative-pg/postgresql:18.7-minimal-trixie                       ok
helm --kube-context docker-desktop repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
helm --kube-context docker-desktop repo update cnpg >/dev/null
helm --kube-context docker-desktop upgrade --install cnpg cnpg/cloudnative-pg --version 0.29.2 \
	  --namespace cnpg-system --create-namespace -f cluster/cnpg-values.yaml --wait --timeout 5m
Release "cnpg" has been upgraded. Happy Helming!
NAME: cnpg
LAST DEPLOYED: Mon Nov 23 21:14:42 2026
NAMESPACE: cnpg-system
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
TEST SUITE: None
NOTES:
CloudNativePG operator should be installed in namespace "cnpg-system".
You can now create a PostgreSQL cluster with 3 nodes as follows:

cat <<EOF | kubectl apply -f -
# Example of PostgreSQL cluster
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: cluster-example

spec:
  instances: 3
  storage:
    size: 1Gi
EOF

kubectl get -A cluster
kubectl --context docker-desktop wait --for=condition=Established --timeout=120s crd/clusters.postgresql.cnpg.io
customresourcedefinition.apiextensions.k8s.io/clusters.postgresql.cnpg.io condition met
```

```text
$ make apis
ok    provider-kubernetes              v1.4.1
ok    provider-helm                    v1.5.0
ok    function-patch-and-transform     v0.11.2
ok    function-go-templating           v0.13.2
ok    function-auto-ready              v0.7.3
ok    provider-family-aws              v2.10.0
ok    provider-aws-s3                  v2.10.0
ok    provider-aws-dynamodb            v2.10.0
ok    localstack image (localstack.yaml) 4.14.0
ok    localstack image (aws-writer.yaml) 4.14.0
ok    cnpg/cluster chart (app-dev.yaml) 0.9.0
ok    postgres image (app-dev.yaml)    18.7-minimal-trixie
ok    cnpg/cluster chart (app-prod.yaml) 0.9.0
ok    postgres image (app-prod.yaml)   18.7-minimal-trixie
CLUSTER=docker-desktop ./scripts/prepull.sh app
prepull nginxdemos/hello:plain-text                                                 ok
kubectl --context docker-desktop apply -f crossplane/apis/crossplane-rbac.yaml -f crossplane/apis/app-xrd.yaml
clusterrole.rbac.authorization.k8s.io/crossplane-demo:compose-native unchanged
compositeresourcedefinition.apiextensions.crossplane.io/apps.platform.demo.io unchanged
kubectl --context docker-desktop wait --for=condition=Established --timeout=120s xrd/apps.platform.demo.io
compositeresourcedefinition.apiextensions.crossplane.io/apps.platform.demo.io condition met
kubectl --context docker-desktop apply -f crossplane/compositions/
composition.apiextensions.crossplane.io/app-dev unchanged
composition.apiextensions.crossplane.io/app-prod unchanged
kubectl --context docker-desktop get xrd,compositions
NAME                                                                            ESTABLISHED   OFFERED   AGE
compositeresourcedefinition.apiextensions.crossplane.io/apps.platform.demo.io   True                    10m

NAME                                               XR-KIND   XR-APIVERSION               AGE
composition.apiextensions.crossplane.io/app-dev    App       platform.demo.io/v1alpha1   10m
composition.apiextensions.crossplane.io/app-prod   App       platform.demo.io/v1alpha1   10m
```

## `make render`

Offline, with no cluster needed: the full desired state for `examples/hello.yaml`
from the dev Composition, then a filtered render with simulated "Postgres ready"
observed state. Things to notice in the first render:

- The XR's `spec.crossplane.resourceRefs` lists what was composed, and `Ready` is
  `False` with `Unready resources: db-release, deployment, and service`. Nothing
  exists yet, so nothing can be ready.
- There's no connection Secret yet. It only appears once the CNPG Cluster and its
  Secret are observed, which is what the second render simulates.
- Each composed resource has an owner reference to the App, plus the
  `crossplane.io/composition-resource-name` annotation that maps it back to its
  pipeline step.
- Timestamps are fixed (`2024-01-01T00:00:00Z`) and the owner UID is stable, so
  renders are deterministic. That's what lets `make test` compare them to golden files.

```text
$ make render
crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml \
	  crossplane/functions/functions.yaml --xrd crossplane/apis/app-xrd.yaml
---
apiVersion: platform.demo.io/v1alpha1
kind: App
metadata:
  name: hello
  namespace: team-a
spec:
  crossplane:
    resourceRefs:
    - apiVersion: apps/v1
      kind: Deployment
      name: hello
    - apiVersion: helm.m.crossplane.io/v1beta1
      kind: Release
      name: hello-db
    - apiVersion: v1
      kind: Service
      name: hello
status:
  awsConfig: ""
  bucket: ""
  conditions:
  - lastTransitionTime: "2024-01-01T00:00:00Z"
    reason: WatchCircuitClosed
    status: "True"
    type: Responsive
  - lastTransitionTime: "2024-01-01T00:00:00Z"
    reason: ReconcileSuccess
    status: "True"
    type: Synced
  - lastTransitionTime: "2024-01-01T00:00:00Z"
    message: 'Unready resources: db-release, deployment, and service'
    reason: Creating
    status: "False"
    type: Ready
  connectionSecret: ""
  dbReady: false
  table: ""
  url: http://localhost:80
---
apiVersion: helm.m.crossplane.io/v1beta1
kind: Release
metadata:
  annotations:
    crossplane.io/composition-resource-name: db-release
  labels:
    crossplane.io/composite: hello
  name: hello-db
  namespace: team-a
  ownerReferences:
  - apiVersion: platform.demo.io/v1alpha1
    blockOwnerDeletion: true
    controller: true
    kind: App
    name: hello
    uid: e1db648d-795d-5492-b013-605891baec6a
spec:
  forProvider:
    chart:
      name: cluster
      repository: https://cloudnative-pg.github.io/charts
      version: 0.9.0
    namespace: team-a
    skipCreateNamespace: true
    values:
      cluster:
        enablePDB: false
        enableSuperuserAccess: false
        imageName: ghcr.io/cloudnative-pg/postgresql:18.7-minimal-trixie
        initdb:
          database: app
          owner: app
        instances: 1
        resources:
          limits:
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
        storage:
          size: 1Gi
      fullnameOverride: hello-db
  providerConfigRef:
    kind: ClusterProviderConfig
    name: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    crossplane.io/composition-resource-name: deployment
  labels:
    crossplane.io/composite: hello
  name: hello
  namespace: team-a
  ownerReferences:
  - apiVersion: platform.demo.io/v1alpha1
    blockOwnerDeletion: true
    controller: true
    kind: App
    name: hello
    uid: e1db648d-795d-5492-b013-605891baec6a
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: hello
  template:
    metadata:
      labels:
        app.kubernetes.io/name: hello
    spec:
      containers:
      - image: nginxdemos/hello:plain-text
        name: app
        ports:
        - containerPort: 80
          name: http
        readinessProbe:
          periodSeconds: 5
          tcpSocket:
            port: http
        resources:
          limits:
            cpu: 200m
            memory: 64Mi
          requests:
            cpu: 10m
            memory: 16Mi
---
apiVersion: v1
kind: Service
metadata:
  annotations:
    crossplane.io/composition-resource-name: service
  labels:
    crossplane.io/composite: hello
  name: hello
  namespace: team-a
  ownerReferences:
  - apiVersion: platform.demo.io/v1alpha1
    blockOwnerDeletion: true
    controller: true
    kind: App
    name: hello
    uid: e1db648d-795d-5492-b013-605891baec6a
spec:
  ports:
  - name: http
    port: 80
    targetPort: http
  selector:
    app.kubernetes.io/name: hello
  type: LoadBalancer
--- with simulated 'Postgres ready' observed state:
crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml \
	  crossplane/functions/functions.yaml --xrd crossplane/apis/app-xrd.yaml \
	  --observed-resources tests/fixtures/observed-db-ready.yaml | grep -E '^kind:|^  name:|dbReady|connectionSecret'
kind: App
  name: hello
  connectionSecret: hello-db-conn
  dbReady: true
kind: Secret
  name: hello-db-conn
kind: Object
  name: hello-db-app-secret
kind: Object
  name: hello-db-cluster
kind: Release
  name: hello-db
kind: Deployment
  name: hello
kind: Service
  name: hello
```

## `make test`

The offline test suite: version pins, shellcheck, 7 golden renders, then schema
validation. That's 45 resources against the XRD and provider CRDs, plus 4 invalid
Apps that must be rejected. The rejection messages are cut at 80 characters by the
script. See [Offline Testing](../README.md#offline-testing).

```text
$ make test
ok    provider-kubernetes              v1.4.1
ok    provider-helm                    v1.5.0
ok    function-patch-and-transform     v0.11.2
ok    function-go-templating           v0.13.2
ok    function-auto-ready              v0.7.3
ok    provider-family-aws              v2.10.0
ok    provider-aws-s3                  v2.10.0
ok    provider-aws-dynamodb            v2.10.0
ok    localstack image (localstack.yaml) 4.14.0
ok    localstack image (aws-writer.yaml) 4.14.0
ok    cnpg/cluster chart (app-dev.yaml) 0.9.0
ok    postgres image (app-dev.yaml)    18.7-minimal-trixie
ok    cnpg/cluster chart (app-prod.yaml) 0.9.0
ok    postgres image (app-prod.yaml)   18.7-minimal-trixie
ok       shellcheck
./tests/render-test.sh
ok       render dev-minimal
ok       render dev-hello
ok       render dev-hello-db-ready
ok       render prod-hello
ok       render prod-hello-db-ready
ok       render dev-shop-aws
ok       render prod-shop-aws
./tests/validate.sh
ok       validate: Total 45 resources: 0 missing schemas, 45 success cases, 0 failure cases
ok       rejects invalid-bucket.yaml: spec.bucket: Invalid value: "string": spec.bucket in body must be of type boolea
ok       rejects invalid-missing-image.yaml: spec.image: Required value
ok       rejects invalid-replicas.yaml: spec.replicas: Invalid value: 50: spec.replicas in body should be less than or e
ok       rejects invalid-size.yaml: spec.database.size: Unsupported value: "huge": supported values: "small", "mediu
```
