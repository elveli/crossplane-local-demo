#!/usr/bin/env bash
# Pre-pull images into the Docker Desktop engine (CLUSTER=docker-desktop only).
#
# Why: Docker Desktop's kind-based Kubernetes pulls every image through a
# built-in mirror (http://registry-mirror:1273, see the node's
# /etc/containerd/certs.d/_default/hosts.toml). For xpkg.crossplane.io packages
# that mirror fails with "short read: expected 641 bytes but got 0: unexpected
# EOF" unless the engine already has the image cached -> pods stuck in
# ImagePullBackOff. Pulling on the host first makes the mirror serve from cache.
#
# Usage: scripts/prepull.sh <group>   groups: packages | cnpg | app
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

[[ "${CLUSTER:-docker-desktop}" == docker-desktop ]] || { echo "prepull: skipped (CLUSTER=${CLUSTER})"; exit 0; }

R="$XPKG_REGISTRY/crossplane-contrib"
case "${1:-packages}" in
  packages) imgs=(
      "$R/provider-kubernetes:$PROVIDER_KUBERNETES_VERSION"
      "$R/provider-helm:$PROVIDER_HELM_VERSION"
      "$R/function-patch-and-transform:$FUNCTION_PATCH_AND_TRANSFORM_VERSION"
      "$R/function-go-templating:$FUNCTION_GO_TEMPLATING_VERSION"
      "$R/function-auto-ready:$FUNCTION_AUTO_READY_VERSION") ;;
  cnpg) imgs=(
      "ghcr.io/cloudnative-pg/cloudnative-pg:$CNPG_OPERATOR_VERSION"
      "$POSTGRES_IMAGE") ;;
  app) imgs=("$APP_IMAGE") ;;
  *) echo "unknown group $1" >&2; exit 1 ;;
esac

for i in "${imgs[@]}"; do
  printf 'prepull %-75s ' "$i"
  docker pull -q "$i" >/dev/null && echo ok
done
