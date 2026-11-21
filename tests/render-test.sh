#!/usr/bin/env bash
# Golden-file tests: `crossplane composition render` each case and diff against
# tests/golden/. Offline -- needs Docker (functions run as local containers),
# not a cluster.   UPDATE=1 tests/render-test.sh   regenerates the goldens.
set -euo pipefail
cd "$(dirname "$0")/.."

FUNCS=crossplane/functions/functions.yaml
XRD=crossplane/apis/app-xrd.yaml
DB_READY=tests/fixtures/observed-db-ready.yaml

# name | XR | Composition | observed-resources (optional)
CASES=(
  "dev-minimal|tests/cases/minimal.yaml|crossplane/compositions/app-dev.yaml|"
  "dev-hello|examples/hello.yaml|crossplane/compositions/app-dev.yaml|"
  "dev-hello-db-ready|examples/hello.yaml|crossplane/compositions/app-dev.yaml|$DB_READY"
  "prod-hello|examples/hello-prod.yaml|crossplane/compositions/app-prod.yaml|"
  "prod-hello-db-ready|examples/hello-prod.yaml|crossplane/compositions/app-prod.yaml|$DB_READY"
  # Phase 6: S3 bucket + DynamoDB table (dev: plain; prod: + versioning, PITR)
  "dev-shop-aws|examples/hello-aws.yaml|crossplane/compositions/app-dev.yaml|"
  "prod-shop-aws|examples/hello-aws.yaml|crossplane/compositions/app-prod.yaml|"
)

fail=0
for c in "${CASES[@]}"; do
  IFS='|' read -r name xr comp observed <<<"$c"
  args=("$xr" "$comp" "$FUNCS" --xrd "$XRD" --include-full-xr)
  [[ -n "$observed" ]] && args+=(--observed-resources "$observed")
  out=$(crossplane composition render "${args[@]}")
  golden="tests/golden/$name.yaml"
  if [[ "${UPDATE:-0}" == 1 ]]; then
    printf '%s\n' "$out" > "$golden"; echo "updated  $golden"
  elif diff -u "$golden" <(printf '%s\n' "$out") > /dev/null; then
    echo "ok       render $name"
  else
    echo "FAIL     render $name (diff vs $golden; UPDATE=1 to accept):"
    diff -u "$golden" <(printf '%s\n' "$out") | head -40 || true
    fail=1
  fi
done
exit $fail
