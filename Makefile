# Crossplane Local Demo — see README.md
# Every kubectl/helm call pins --context so nothing can reach a non-local cluster.
include versions.env
export

CLUSTER ?= docker-desktop
ifeq ($(CLUSTER),kind)
  CTX := kind-$(KIND_CLUSTER_NAME)
else
  CTX := docker-desktop
endif
K := kubectl --context $(CTX)
H := helm --kube-context $(CTX)
XP_NS := crossplane-system
CNPG_NS := cnpg-system
# Minified kubeconfig holding ONLY the local context, for CLIs without a
# --context flag (e.g. `crossplane version`). Regenerated on demand, gitignored.
LOCAL_KCFG := .local/kubeconfig

.DEFAULT_GOAL := help
.PHONY: help up crossplane providers cnpg apis demo demo-auto render test down nuke crossplane-status providers-status status \
        rbac-audit check-versions logs-crossplane logs-kubernetes logs-helm logs-cnpg

help:
	@echo "Crossplane Local Demo - Available Commands  (CLUSTER=$(CLUSTER), context=$(CTX))"
	@echo "==========================================="
	@printf "  %-24s %s\n" "make up" "Preflight + cluster, Crossplane, providers, APIs"
	@printf "  %-24s %s\n" "make crossplane" "Install/upgrade Crossplane via Helm (pinned)"
	@printf "  %-24s %s\n" "make providers" "Providers, functions, RBAC, ProviderConfigs, CNPG operator"
	@printf "  %-24s %s\n" "make apis" "XRD (App API) + dev/prod Compositions + RBAC"
	@printf "  %-24s %s\n" "make demo" "Narrated, paused demo (7 scenes; Enter to advance)"
	@printf "  %-24s %s\n" "make demo-auto" "Same demo without pauses (testing/recording)"
	@printf "  %-24s %s\n" "make render" "Offline: render examples through the Compositions (no cluster)"
	@printf "  %-24s %s\n" "make test" "Offline: versions, shellcheck, golden renders, schema validation"
	@printf "  %-24s %s\n" "make down" "Remove everything this demo installed (kind: delete the cluster)"
	@printf "  %-24s %s\n" "make nuke" "down + remove pulled demo images from Docker + local state"
	@printf "  %-24s %s\n" "make status" "Crossplane pods, packages, ProviderConfigs"
	@printf "  %-24s %s\n" "make crossplane-status" "Show Crossplane pods, release, version"
	@printf "  %-24s %s\n" "make providers-status" "Show providers/functions health"
	@printf "  %-24s %s\n" "make rbac-audit" "Show effective provider permissions (kubectl auth can-i)"
	@printf "  %-24s %s\n" "make check-versions" "Check manifests match versions.env"
	@printf "  %-24s %s\n" "make logs-crossplane" "Tail logs from the core Crossplane pod"
	@printf "  %-24s %s\n" "make logs-kubernetes" "Tail logs from provider-kubernetes"
	@printf "  %-24s %s\n" "make logs-helm" "Tail logs from provider-helm"
	@printf "  %-24s %s\n" "make logs-cnpg" "Tail logs from the CloudNativePG operator"

up:
	CLUSTER=$(CLUSTER) ./scripts/cluster-up.sh
	$(MAKE) crossplane providers apis

crossplane:
	$(H) repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
	$(H) repo update crossplane-stable >/dev/null
	$(H) upgrade --install crossplane crossplane-stable/crossplane \
	  --version $(CROSSPLANE_VERSION) --namespace $(XP_NS) --create-namespace \
	  -f cluster/crossplane-values.yaml --wait --timeout 5m
	$(K) -n $(XP_NS) rollout status deploy/crossplane deploy/crossplane-rbac-manager --timeout=180s
	$(K) wait --for=condition=Established --timeout=120s \
	  crd/compositeresourcedefinitions.apiextensions.crossplane.io \
	  crd/compositions.apiextensions.crossplane.io \
	  crd/providers.pkg.crossplane.io crd/functions.pkg.crossplane.io

providers: check-versions
	CLUSTER=$(CLUSTER) ./scripts/prepull.sh packages
	$(K) apply -f crossplane/providers/01-runtime-config.yaml \
	           -f crossplane/providers/02-providers.yaml \
	           -f crossplane/providers/03-rbac.yaml \
	           -f crossplane/functions/functions.yaml
	$(K) wait --for=condition=Healthy --timeout=8m providers.pkg.crossplane.io,functions.pkg.crossplane.io --all
	$(K) apply -f crossplane/providers/04-providerconfigs.yaml
	$(MAKE) cnpg

cnpg:
	CLUSTER=$(CLUSTER) ./scripts/prepull.sh cnpg
	$(H) repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null 2>&1 || true
	$(H) repo update cnpg >/dev/null
	$(H) upgrade --install cnpg cnpg/cloudnative-pg --version $(CNPG_OPERATOR_CHART_VERSION) \
	  --namespace $(CNPG_NS) --create-namespace -f cluster/cnpg-values.yaml --wait --timeout 5m
	$(K) wait --for=condition=Established --timeout=120s crd/clusters.postgresql.cnpg.io

apis: check-versions
	CLUSTER=$(CLUSTER) ./scripts/prepull.sh app
	$(K) apply -f crossplane/apis/crossplane-rbac.yaml -f crossplane/apis/app-xrd.yaml
	@# v2 namespaced XRDs have no claims, so no "Offered" condition -- only Established.
	$(K) wait --for=condition=Established --timeout=120s xrd/apps.platform.demo.io
	$(K) apply -f crossplane/compositions/
	$(K) get xrd,compositions

demo:
	CLUSTER=$(CLUSTER) ./scripts/demo.sh

demo-auto:
	CLUSTER=$(CLUSTER) DEMO_AUTO=1 ./scripts/demo.sh

# ---- offline (Docker needed for functions, no cluster) ----
render:
	crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml \
	  crossplane/functions/functions.yaml --xrd crossplane/apis/app-xrd.yaml
	@echo "--- with simulated 'Postgres ready' observed state:"
	crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml \
	  crossplane/functions/functions.yaml --xrd crossplane/apis/app-xrd.yaml \
	  --observed-resources tests/fixtures/observed-db-ready.yaml | grep -E '^kind:|^  name:|dbReady|connectionSecret'

test: check-versions
	@if command -v shellcheck >/dev/null; then shellcheck -S warning scripts/*.sh tests/*.sh && echo "ok       shellcheck"; \
	 else echo "skip     shellcheck (brew install shellcheck)"; fi
	./tests/render-test.sh
	./tests/validate.sh

# ---- teardown ----
down:
ifeq ($(CLUSTER),kind)
	kind delete cluster --name $(KIND_CLUSTER_NAME)
else
	./scripts/down.sh
endif

nuke: down
	@echo "== removing demo images from the Docker engine (prepull + render)"
	@docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^(xpkg\.crossplane\.io/crossplane(-contrib)?/|ghcr\.io/cloudnative-pg/|nginxdemos/hello:)' \
	  | xargs -r docker rmi -f >/dev/null && echo "   done" || true
	rm -rf .local

crossplane-status:
	$(K) get pods -n $(XP_NS)
	$(H) list -n $(XP_NS)
	@$(MAKE) -s $(LOCAL_KCFG)
	KUBECONFIG=$(LOCAL_KCFG) crossplane version

providers-status:
	$(K) get providers.pkg.crossplane.io,functions.pkg.crossplane.io

status: providers-status
	$(K) get pods -n $(XP_NS)
	$(K) get pods -n $(CNPG_NS) 2>/dev/null || true
	$(K) get deploymentruntimeconfigs,clusterproviderconfigs.kubernetes.m.crossplane.io,clusterproviderconfigs.helm.m.crossplane.io

# What can each provider actually do? (auto-granted system role + 03-rbac.yaml)
rbac-audit:
	@for sa in provider-helm provider-kubernetes; do \
	  echo "== $$sa"; \
	  for check in "create clusters.postgresql.cnpg.io -n team-a" "get clusters.postgresql.cnpg.io -n team-a" \
	               "create secrets -n team-a" "create configmaps -n team-a" \
	               "create deployments.apps -n team-a" "create namespaces" "get nodes"; do \
	    printf '  %-48s %s\n' "$$check" "$$($(K) auth can-i $$check --as=system:serviceaccount:$(XP_NS):$$sa 2>/dev/null)"; \
	  done; \
	done

check-versions:
	@./tests/check-versions.sh

.PHONY: $(LOCAL_KCFG)
$(LOCAL_KCFG):
	@mkdir -p .local
	@kubectl config view --minify --flatten --context $(CTX) > $@

logs-crossplane:
	$(K) logs -n $(XP_NS) -l app=crossplane -f
logs-kubernetes:
	$(K) logs -n $(XP_NS) -l pkg.crossplane.io/provider=provider-kubernetes -f
logs-helm:
	$(K) logs -n $(XP_NS) -l pkg.crossplane.io/provider=provider-helm -f
logs-cnpg:
	$(K) logs -n $(CNPG_NS) -l app.kubernetes.io/name=cloudnative-pg -f
