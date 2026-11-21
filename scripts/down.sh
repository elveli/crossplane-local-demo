#!/usr/bin/env bash
# Remove everything this demo installed from the docker-desktop cluster, in
# dependency order, then verify nothing is left behind. Other workloads on the
# (shared) docker-desktop cluster are not touched.
# (CLUSTER=kind is handled by the Makefile: it simply deletes the kind cluster.)
set -euo pipefail
cd "$(dirname "$0")/.."
CTX=docker-desktop
k() { kubectl --context "$CTX" "$@"; }
h() { helm --kube-context "$CTX" "$@"; }
step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
crd_exists() { k get crd "$1" >/dev/null 2>&1; }

step "1. Apps (lets providers uninstall Helm releases + finalize observers)"
if crd_exists apps.platform.demo.io; then
  k delete apps.platform.demo.io --all -A --wait=true --timeout=300s || true
fi
# Composed managed resources are garbage-collected *after* their App is gone.
# Wait for them before deleting namespaces: AWS MRs need LocalStack (and Helm
# Releases need their namespace) to finish deleting, or they hang on finalizers.
if crd_exists providers.pkg.crossplane.io; then
  for _ in $(seq 1 60); do
    [[ -z "$(k get managed -A -o name 2>/dev/null)" ]] && break
    sleep 3
  done
  k get managed -A 2>/dev/null | grep . && echo "(managed resources still present; continuing)" || echo "no managed resources left"
fi
k delete ns -l app.kubernetes.io/part-of=crossplane-local-demo --wait=true --timeout=180s || true

step "2. Platform API (XRD deletion removes the App CRD)"
# (kubectl delete -f errors on kinds whose CRD is gone, so guard: idempotent re-runs)
if crd_exists compositions.apiextensions.crossplane.io; then
  k delete -f crossplane/compositions/ --ignore-not-found
  k delete -f crossplane/apis/app-xrd.yaml --ignore-not-found --wait=true --timeout=120s
fi
k delete -f crossplane/apis/crossplane-rbac.yaml --ignore-not-found

step "3. ProviderConfigs, providers, functions (their CRDs go with them)"
for crd in clusterproviderconfigs.kubernetes.m.crossplane.io clusterproviderconfigs.helm.m.crossplane.io \
           clusterproviderconfigs.aws.m.upbound.io; do
  crd_exists "$crd" && k delete "$crd" --all --wait=true --timeout=60s
done
if crd_exists providers.pkg.crossplane.io; then
  k delete -f crossplane/providers/02-providers.yaml -f crossplane/functions/functions.yaml --ignore-not-found --wait=true --timeout=180s
  k delete -f crossplane/providers/01-runtime-config.yaml --ignore-not-found
  # Phase 6 (optional): delete the AWS family *members* first and let their
  # revisions finish. If the family goes while a member still exists, the
  # dependency manager re-installs the family on its own (default runtime
  # config), and that copy is then orphaned when Crossplane is uninstalled.
  k delete providers.pkg.crossplane.io -l platform.demo.io/aws-member=true --wait=true --timeout=180s
  for _ in $(seq 1 60); do
    [[ -z "$(k get providerrevisions.pkg.crossplane.io -o name 2>/dev/null | grep -E 'provider-aws-(s3|dynamodb)')" ]] && break
    sleep 3
  done
  # Then ALL remaining packages (incl. anything the dependency manager
  # installed itself, which isn't in our manifests).
  k delete providers.pkg.crossplane.io,functions.pkg.crossplane.io --all --wait=true --timeout=180s
  k delete -f crossplane/providers/aws/01-runtime-config.yaml --ignore-not-found
  # `delete provider --wait` returns when the Provider object is gone, but its
  # *revisions* (which own the provider CRDs) finalize asynchronously -- the
  # AWS family revision takes longest. Uninstalling Crossplane before they
  # finish orphans their finalizers (and the package Lock's) forever.
  for _ in $(seq 1 60); do
    [[ -z "$(k get providerrevisions.pkg.crossplane.io,functionrevisions.pkg.crossplane.io -o name 2>/dev/null)" ]] && break
    sleep 3
  done
  echo "package revisions finalized: $(k get providerrevisions.pkg.crossplane.io,functionrevisions.pkg.crossplane.io -o name 2>/dev/null | wc -l | tr -d ' ') left"
fi
k delete secret -n crossplane-system localstack-dummy-creds --ignore-not-found
k delete -f cluster/localstack.yaml --ignore-not-found --wait=true --timeout=120s
k delete -f crossplane/providers/03-rbac.yaml --ignore-not-found

step "4. CloudNativePG operator"
h uninstall cnpg -n cnpg-system --wait --timeout 3m 2>/dev/null || echo "(cnpg release not installed)"
k get crd -o name | { grep '\.cnpg\.io$' || true; } | xargs -r kubectl --context "$CTX" delete --ignore-not-found --wait=true
k delete ns cnpg-system --ignore-not-found --wait=true --timeout=120s

step "5. Crossplane core"
h uninstall crossplane -n crossplane-system --wait --timeout 3m 2>/dev/null || echo "(crossplane release not installed)"
# Crossplane creates its own CRDs and webhook configs at runtime (not via Helm),
# so helm uninstall leaves them behind.
k get crd -o name | { grep '\.crossplane\.io$' || true; } | xargs -r kubectl --context "$CTX" delete --ignore-not-found --wait=true
k get validatingwebhookconfigurations,mutatingwebhookconfigurations -o name | { grep -i crossplane || true; } \
  | xargs -r kubectl --context "$CTX" delete --ignore-not-found
k delete ns crossplane-system --ignore-not-found --wait=true --timeout=180s

step "6. Verify nothing is left"
left=$(
  { k get crd -o name | grep -E '\.(crossplane|cnpg|upbound)\.io$|platform\.demo\.io'
    k get clusterroles,clusterrolebindings -o name | grep -E 'crossplane|cnpg'
    k get validatingwebhookconfigurations,mutatingwebhookconfigurations -o name | grep -Ei 'crossplane|cnpg'
    k get ns -o name | grep -E 'crossplane-system|cnpg-system|team-a|localstack'
  } 2>/dev/null || true)
if [[ -n "$left" ]]; then
  echo "Leftovers:"; echo "$left"; exit 1
fi
printf '\033[1;32mclean: no Crossplane, CNPG, LocalStack/AWS or demo resources remain on %s\033[0m\n' "$CTX"
