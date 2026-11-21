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
k delete ns -l app.kubernetes.io/part-of=crossplane-local-demo --wait=true --timeout=180s || true

step "2. Platform API (XRD deletion removes the App CRD)"
k delete -f crossplane/compositions/ --ignore-not-found
k delete -f crossplane/apis/app-xrd.yaml --ignore-not-found --wait=true --timeout=120s
k delete -f crossplane/apis/crossplane-rbac.yaml --ignore-not-found

step "3. ProviderConfigs, providers, functions (their CRDs go with them)"
for crd in clusterproviderconfigs.kubernetes.m.crossplane.io clusterproviderconfigs.helm.m.crossplane.io; do
  crd_exists "$crd" && k delete "$crd" --all --wait=true --timeout=60s
done
if crd_exists providers.pkg.crossplane.io; then
  k delete -f crossplane/providers/02-providers.yaml -f crossplane/functions/functions.yaml --ignore-not-found --wait=true --timeout=180s
  k delete -f crossplane/providers/01-runtime-config.yaml --ignore-not-found
fi
k delete -f crossplane/providers/03-rbac.yaml --ignore-not-found

step "4. CloudNativePG operator"
h uninstall cnpg -n cnpg-system --wait --timeout 3m 2>/dev/null || echo "(cnpg release not installed)"
k get crd -o name | grep '\.cnpg\.io$' | xargs -r kubectl --context "$CTX" delete --wait=true
k delete ns cnpg-system --ignore-not-found --wait=true --timeout=120s

step "5. Crossplane core"
h uninstall crossplane -n crossplane-system --wait --timeout 3m 2>/dev/null || echo "(crossplane release not installed)"
# Crossplane creates its own CRDs and webhook configs at runtime (not via Helm),
# so helm uninstall leaves them behind.
k get crd -o name | grep '\.crossplane\.io$' | xargs -r kubectl --context "$CTX" delete --wait=true
k get validatingwebhookconfigurations,mutatingwebhookconfigurations -o name | grep -i crossplane \
  | xargs -r kubectl --context "$CTX" delete
k delete ns crossplane-system --ignore-not-found --wait=true --timeout=180s

step "6. Verify nothing is left"
left=$(
  { k get crd -o name | grep -E '\.(crossplane|cnpg)\.io$|platform\.demo\.io'
    k get clusterroles,clusterrolebindings -o name | grep -E 'crossplane|cnpg'
    k get validatingwebhookconfigurations,mutatingwebhookconfigurations -o name | grep -Ei 'crossplane|cnpg'
    k get ns -o name | grep -E 'crossplane-system|cnpg-system|team-a'
  } 2>/dev/null || true)
if [[ -n "$left" ]]; then
  echo "Leftovers:"; echo "$left"; exit 1
fi
printf '\033[1;32mclean: no Crossplane, CNPG or demo resources remain on %s\033[0m\n' "$CTX"
