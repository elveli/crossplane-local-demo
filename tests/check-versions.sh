#!/usr/bin/env bash
# Fail if any package ref in the manifests disagrees with versions.env.
# Manifests keep literal versions (readable, GitOps-friendly); this keeps them honest.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

fail=0
check() { # <file> <package-name> <expected-version>
  local got
  got=$(grep -hoE "crossplane-contrib/$2:[^[:space:]\"]+" "$1" | head -1 | cut -d: -f2 || true)
  if [[ "$got" == "$3" ]]; then printf 'ok    %-32s %s\n' "$2" "$3"
  else printf 'FAIL  %-32s manifest=%s versions.env=%s (%s)\n' "$2" "${got:-<missing>}" "$3" "$1"; fail=1; fi
}
check crossplane/providers/02-providers.yaml provider-kubernetes          "$PROVIDER_KUBERNETES_VERSION"
check crossplane/providers/02-providers.yaml provider-helm                "$PROVIDER_HELM_VERSION"
check crossplane/functions/functions.yaml    function-patch-and-transform "$FUNCTION_PATCH_AND_TRANSFORM_VERSION"
check crossplane/functions/functions.yaml    function-go-templating       "$FUNCTION_GO_TEMPLATING_VERSION"
check crossplane/functions/functions.yaml    function-auto-ready          "$FUNCTION_AUTO_READY_VERSION"
for comp in crossplane/compositions/app-*.yaml; do
  grep -q "version: \"$CNPG_CLUSTER_CHART_VERSION\"" "$comp" \
    && printf 'ok    %-32s %s\n' "cnpg/cluster chart ($(basename "$comp"))" "$CNPG_CLUSTER_CHART_VERSION" \
    || { printf 'FAIL  cnpg/cluster chart version in %s != %s\n' "$comp" "$CNPG_CLUSTER_CHART_VERSION"; fail=1; }
  grep -q "imageName: $POSTGRES_IMAGE\$" "$comp" \
    && printf 'ok    %-32s %s\n' "postgres image ($(basename "$comp"))" "${POSTGRES_IMAGE##*:}" \
    || { printf 'FAIL  postgres image in %s != %s\n' "$comp" "$POSTGRES_IMAGE"; fail=1; }
done
exit $fail
