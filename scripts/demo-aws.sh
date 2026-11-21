#!/usr/bin/env bash
# Phase 6 (optional) narrated demo: the same App API, now also asking for an
# S3 bucket and a DynamoDB table -- served by LocalStack, provisioned by the
# provider-aws family. Nothing talks to real AWS.
#   DEMO_AUTO=1     run straight through (no pauses)
#   CLUSTER=kind    target the kind fallback cluster (port-forwards LocalStack)
# Prereq: `make up && make aws`.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

CLUSTER="${CLUSTER:-docker-desktop}"
case "$CLUSTER" in
  docker-desktop) CTX=docker-desktop ;;
  kind)           CTX="kind-${KIND_CLUSTER_NAME}" ;;
  *) echo "CLUSTER must be docker-desktop or kind" >&2; exit 1 ;;
esac
NS=team-a
APP=shop
PHYS="$NS-$APP"          # bucket/table name the Composition derives
AUTO="${DEMO_AUTO:-0}"
PF_PID=""

# ---------------------------------------------------------------- helpers
k()     { kubectl --context "$CTX" "$@"; }
trace() { crossplane resource trace "app/$APP" -n "$NS" --context "$CTX"; }
scene() { printf '\n\033[1;35m━━━ %s ━━━\033[0m\n' "$*"; }
say()   { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
note()  { printf '  \033[2m%s\033[0m\n' "$*"; }
ok()    { printf '  \033[1;32m✔ %s\033[0m\n' "$*"; }
run()   { printf '\033[1;33m$ %s\033[0m\n' "$(sed -e 's/^k /kubectl /' -e 's/^trace$/crossplane resource trace app\/'"$APP"' -n '"$NS"'/' -e 's|^aws_l |'"$AWS_SHOWN"' |' <<<"$*")"; eval "$*"; }
pause() {
  if [[ "$AUTO" == 1 ]]; then sleep "${DEMO_PAUSE:-1}"
  else read -rp $'\n  \033[2m⏎ Enter to continue (Ctrl-C to quit)\033[0m ' _; fi
}
wait_until() {
  local t0=$SECONDS
  until eval "$3" >/dev/null 2>&1; do
    (( SECONDS - t0 > $1 )) && { echo "  ✘ timed out after $1s waiting for: $2" >&2; return 1; }
    sleep 2
  done
  ok "$2  ($((SECONDS - t0))s)"
}
app_ready() { [[ "$(k -n "$NS" get app "$APP" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == True ]]; }
aws_mrs()   { k -n "$NS" get buckets.s3.aws.m.upbound.io,tables.dynamodb.aws.m.upbound.io -l "crossplane.io/composite=$APP" -o name 2>/dev/null; }
# AWS CLI from the Mac against LocalStack only: dummy keys, no ~/.aws config
# or profile (so real profiles can never be picked up), explicit endpoint.
aws_l() {
  env -u AWS_PROFILE -u AWS_SESSION_TOKEN AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
      AWS_DEFAULT_REGION=us-west-2 AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
      AWS_ENDPOINT_URL=http://localhost:4566 "${AWS_CMD[@]}" "$@"
}
cleanup() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null; true; }
trap cleanup EXIT

# ---------------------------------------------------------------- preflight
k get clusterproviderconfigs.aws.m.upbound.io localstack >/dev/null 2>&1 \
  || { echo "Phase 6 not installed -- run: make aws" >&2; exit 1; }
if command -v awslocal >/dev/null; then AWS_CMD=(awslocal); AWS_SHOWN=awslocal
else AWS_CMD=(aws --endpoint-url http://localhost:4566); AWS_SHOWN="aws --endpoint-url http://localhost:4566"
     note "awslocal not found -> using the plain aws CLI with --endpoint-url (same thing)"; fi
# Docker Desktop forwards the localstack-external LoadBalancer to localhost:4566;
# kind has no LoadBalancer -> port-forward.
if ! curl -sf -m 3 http://localhost:4566/_localstack/health >/dev/null; then
  note "localhost:4566 not reachable -> kubectl port-forward svc/localstack-external 4566"
  kubectl --context "$CTX" -n localstack port-forward svc/localstack-external 4566:4566 >/dev/null 2>&1 & PF_PID=$!
  wait_until 30 "LocalStack reachable on localhost:4566" 'curl -sf -m 2 http://localhost:4566/_localstack/health'
fi
if k -n "$NS" get app "$APP" >/dev/null 2>&1; then
  note "Removing a leftover App/$APP from a previous run..."
  k -n "$NS" delete app "$APP" --wait=true --timeout=180s >/dev/null
  wait_until 180 "previous run cleaned up" '[[ -z "$(aws_mrs)" ]]'
fi

cat <<EOF

  Phase 6: AWS flavour on LocalStack   context=$CTX   namespace=$NS
  Same App API, two new fields: bucket: true, table: true. The Composition
  adds an S3 Bucket and a DynamoDB Table (provider-aws family, namespaced
  v2 managed resources) -- all pointed at LocalStack $(curl -s http://localhost:4566/_localstack/health | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["edition"], d["version"])').
EOF
pause

# ================================================================= 1
scene "1/5  Guardrails: why nothing can reach real AWS"
say "Family providers (one per service, not the monolith), pinned to $PROVIDER_AWS_VERSION:"
run "k get providers.pkg.crossplane.io | grep -E 'NAME|aws'"
say "The ClusterProviderConfig: static LocalStack endpoint, explicit service list, no AWS lookups, dummy keys:"
run "k get clusterproviderconfigs.aws.m.upbound.io localstack -o yaml | sed -n '/^spec:/,\$p'"
say "Backstop in the provider pods: HTTPS (= every real AWS endpoint) goes to a dead-end proxy:"
run "k -n crossplane-system get pod -l pkg.crossplane.io/provider=provider-aws-s3 -o jsonpath='{range .items[0].spec.containers[0].env[*]}{.name}={.value}{\"\\n\"}{end}' | grep -E '^(HTTPS_PROXY|AWS_ENDPOINT_URL)='"
note "Anything that slips past the endpoint config fails inside the pod with"
note "'proxyconnect tcp: dial tcp 127.0.0.1:9: connect: connection refused'."
pause

# ================================================================= 2
scene "2/5  Request an App with a bucket and a table"
run "cat examples/hello-aws.yaml"
run "k apply -f examples/namespace.yaml -f examples/hello-aws.yaml"
wait_until 300 "App/$APP is Ready (bucket + table Available in LocalStack)" app_ready
run "trace"
run "k -n $NS get app $APP -o jsonpath='{.status}' | python3 -c 'import json,sys; d=json.load(sys.stdin); [print(f\"  {k:18} {d[k]}\") for k in (\"bucket\",\"table\",\"awsConfig\",\"url\")]'"
pause

# ================================================================= 3
scene "3/5  Check from the Mac"
run "aws_l s3 ls"
run "aws_l dynamodb list-tables --output text"
say "Crossplane tags what it manages -- visible on the 'cloud' side:"
run "aws_l s3api get-bucket-tagging --bucket $PHYS --output text"
pause

# ================================================================= 4
scene "4/5  A workload uses it -- configured only by the composed ConfigMap"
run "k -n $NS get configmap $APP-aws -o jsonpath='{.data}' | python3 -m json.tool"
say "A one-shot pod with envFrom: $APP-aws (no AWS settings of its own) writes an object and an item:"
run "grep -A1 envFrom examples/aws-writer.yaml"
k -n "$NS" delete pod writer --ignore-not-found >/dev/null
run "k apply -f examples/aws-writer.yaml"
wait_until 90 "writer pod finished" '[[ "$(k -n '"$NS"' get pod writer -o jsonpath={.status.phase})" == Succeeded ]]'
run "k -n $NS logs writer | tail -1"
k -n "$NS" delete pod writer --wait=false >/dev/null
run "aws_l s3 ls s3://$PHYS/"
run "aws_l dynamodb scan --table-name $PHYS --query 'Items[].id.S' --output text"
pause

# ================================================================= 5
scene "5/5  Drift, then turning features off"
say "Delete the bucket (and its object) behind Crossplane's back:"
run "aws_l s3 rb s3://$PHYS --force"
note "provider-aws-s3 polls every minute here (--poll=1m in the runtime config)..."
wait_until 150 "bucket $PHYS re-created by Crossplane" 'aws_l s3api head-bucket --bucket '"$PHYS"
say "Turn the table off -- the Composition stops rendering it, Crossplane deletes it:"
run "k -n $NS patch app $APP --type merge -p '{\"spec\":{\"table\":false}}'"
wait_until 120 "table $PHYS gone from LocalStack" '! aws_l dynamodb describe-table --table-name '"$PHYS"
run "aws_l dynamodb list-tables --output text"
say "Delete the App -- everything it composed goes, in-cluster and 'in AWS':"
run "k -n $NS delete app $APP --wait=true --timeout=180s"
wait_until 120 "AWS managed resources finalized" '[[ -z "$(aws_mrs)" ]]'
run "aws_l s3 ls"
run "aws_l dynamodb list-tables --output text"
ok "LocalStack is empty again."
