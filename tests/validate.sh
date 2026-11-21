#!/usr/bin/env bash
# Schema validation with `crossplane resource validate` (offline):
#  - examples/ and every golden render must validate against the App XRD and
#    the provider CRDs (downloaded from the pinned Provider packages)
#  - tests/cases/invalid-*.yaml MUST be rejected
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

EXT=$(mktemp -d); RES=$(mktemp -d)
trap 'rm -rf "$EXT" "$RES"' EXIT
cp crossplane/apis/app-xrd.yaml crossplane/providers/02-providers.yaml "$EXT/"
VALIDATE=(crossplane resource validate "$EXT" --crossplane-image "$XPKG_REGISTRY/crossplane/crossplane:v$CROSSPLANE_VERSION")

fail=0
# 1) positive: Apps from examples/ + all golden renders
cp examples/hello.yaml examples/hello-prod.yaml tests/cases/minimal.yaml "$RES/"
cp tests/golden/*.yaml "$RES/"
if out=$("${VALIDATE[@]}" "$RES" --error-on-missing-schemas 2>&1); then
  echo "ok       validate: $(grep '^Total' <<<"$out")"
else
  echo "FAIL     validate:"; grep -vE '^\[✓\]' <<<"$out"; fail=1
fi

# 2) negative: each invalid case must be rejected, with the expected message
for f in tests/cases/invalid-*.yaml; do
  if out=$("${VALIDATE[@]}" "$f" 2>&1); then
    echo "FAIL     $f validated but must be rejected"; fail=1
  else
    echo "ok       rejects $(basename "$f"): $(grep -m1 -oE 'spec\.[^ ]+: .*' <<<"$out" | cut -c1-80)"
  fi
done
exit $fail
