#!/usr/bin/env bash
# Bring up (or verify) the local cluster and print preflight info.
#   CLUSTER=docker-desktop (default) -> verifies Docker Desktop's built-in Kubernetes
#   CLUSTER=kind                     -> creates a single-node kind cluster if missing
# Never touches any non-local context: everything uses an explicit --context.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=../versions.env
source versions.env

CLUSTER="${CLUSTER:-docker-desktop}"
case "$CLUSTER" in
  docker-desktop) CTX=docker-desktop ;;
  kind)           CTX="kind-${KIND_CLUSTER_NAME}" ;;
  *) echo "CLUSTER must be docker-desktop or kind (got '$CLUSTER')" >&2; exit 1 ;;
esac

echo "== Host"
echo "arch: $(uname -m)  macOS: $(sw_vers -productVersion)"
[[ "$(uname -m)" == "x86_64" ]] || echo "WARN: expected x86_64 (Intel); this demo is tested on Intel Macs"

echo "== Tools"
for t in docker kubectl helm crossplane; do
  command -v "$t" >/dev/null || { echo "MISSING: $t (brew install $t)" >&2; exit 1; }
done
[[ "$CLUSTER" == kind ]] && { command -v kind >/dev/null || { echo "MISSING: kind (brew install kind)" >&2; exit 1; }; }
echo "kubectl $(kubectl version --client -o json | sed -n 's/.*"gitVersion": "\(.*\)".*/\1/p' | head -1)" \
     "| helm $(helm version --short) | crossplane CLI $(crossplane version --client 2>/dev/null | awk '{print $NF}')"

echo "== Docker Desktop resources"
docker info >/dev/null 2>&1 || { echo "Docker is not running — start Docker Desktop" >&2; exit 1; }
cpus=$(docker info --format '{{.NCPU}}')
mem_gib=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 / 1024 ))
echo "CPUs: $cpus  Memory: ~${mem_gib} GiB"
if (( cpus < 4 || mem_gib < 7 )); then
  echo "WARN: <4 CPU / <8 GB. Raise it in Docker Desktop > Settings > Resources > Advanced"
  echo "      (recommend 4+ CPU, 8+ GB), or deploy Apps with database.enabled=false."
fi

if [[ "$CLUSTER" == kind ]]; then
  # (no `| grep -q` under pipefail: early grep exit SIGPIPEs the producer -> false negative)
  if ! kind get kubeconfig --name "$KIND_CLUSTER_NAME" >/dev/null 2>&1; then
    echo "== Creating kind cluster $KIND_CLUSTER_NAME"
    kind create cluster --name "$KIND_CLUSTER_NAME" --config cluster/kind-config.yaml --wait 120s
  fi
else
  if ! kubectl config get-contexts docker-desktop >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Context 'docker-desktop' not found. Enable Kubernetes:
  Docker Desktop > Settings > Kubernetes > Enable Kubernetes (kind provisioner, 1 node) > Apply & restart
Or use the fallback:  CLUSTER=kind make up
EOF
    exit 1
  fi
fi

echo "== Cluster ($CTX)"
kubectl --context "$CTX" wait --for=condition=Ready nodes --all --timeout=120s >/dev/null
kubectl --context "$CTX" get nodes -o wide
