#!/usr/bin/env bash
# Narrated Crossplane v2 demo. Press Enter between scenes.
#   DEMO_AUTO=1     run straight through (no pauses) -- for testing/recording
#   CLUSTER=kind    target the kind fallback cluster (uses port-forward for curl)
# Prereq: `make up` (Crossplane, providers, functions, App API installed).
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
APP=hello
AUTO="${DEMO_AUTO:-0}"
PF_PID=""; WATCH_PID=""

# ---------------------------------------------------------------- helpers
k()     { kubectl --context "$CTX" "$@"; }
trace() { crossplane resource trace "app/$APP" -n "$NS" --context "$CTX"; }
scene() { printf '\n\033[1;35m━━━ %s ━━━\033[0m\n' "$*"; }
say()   { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
note()  { printf '  \033[2m%s\033[0m\n' "$*"; }
ok()    { printf '  \033[1;32m✔ %s\033[0m\n' "$*"; }
show()  { printf '\033[1;33m$ %s\033[0m\n' "$*"; }   # display only
# show a command (with `k` displayed as plain kubectl), then run it
run()   { printf '\033[1;33m$ %s\033[0m\n' "$(sed -e 's/^k /kubectl /' -e 's/^trace$/crossplane resource trace app\/'"$APP"' -n '"$NS"'/' <<<"$*")"; eval "$*"; }
pause() {
  if [[ "$AUTO" == 1 ]]; then sleep "${DEMO_PAUSE:-1}"
  else read -rp $'\n  \033[2m⏎ Enter to continue (Ctrl-C to quit)\033[0m ' _; fi
}
# wait_until <timeout-seconds> <description> <shell-condition>; prints elapsed time
wait_until() {
  local t0=$SECONDS
  until eval "$3" >/dev/null 2>&1; do
    (( SECONDS - t0 > $1 )) && { echo "  ✘ timed out after $1s waiting for: $2" >&2; return 1; }
    sleep 2
  done
  ok "$2  ($((SECONDS - t0))s)"
}
app_ready() { [[ "$(k -n "$NS" get app "$APP" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == True ]]; }
composed()  { k -n "$NS" get deploy,svc,secret,pdb,releases.helm.m.crossplane.io,objects.kubernetes.m.crossplane.io \
                -l "crossplane.io/composite=$APP" --no-headers 2>/dev/null; }
conn_secret() { # decode the composed Secret, masking the password
  k -n "$NS" get secret "$APP-db-conn" -o json | python3 -c '
import json, sys, base64
for key, v in sorted(json.load(sys.stdin)["data"].items()):
    if key == "uri": continue
    print(f"  {key:9} " + ("********" if key == "password" else base64.b64decode(v).decode()))'
}
db_login() { # psql into the CNPG pod using only the composed Secret's values
  local pw; pw=$(k -n "$NS" get secret "$APP-db-conn" -o jsonpath='{.data.password}' | base64 -d)
  k -n "$NS" exec "$APP-db-1" -c postgres -- env PGPASSWORD="$pw" \
    psql -h "$APP-db-rw" -U app -d app -tAc "select current_user, split_part(version(), ' on ', 1)"
}
cleanup()   { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null; [[ -n "$WATCH_PID" ]] && kill "$WATCH_PID" 2>/dev/null; true; }
trap cleanup EXIT

# ---------------------------------------------------------------- preflight
k get xrd apps.platform.demo.io >/dev/null 2>&1 || { echo "App API not installed -- run: make up" >&2; exit 1; }
PORT=$(sed -n 's/^ *port: *\([0-9]*\).*/\1/p' examples/hello.yaml | head -1)
# How will the Mac reach the app? Docker Desktop forwards LoadBalancer ports to
# localhost -- unless another process already owns 127.0.0.1:<port> (seen in
# the wild: rclone on 8080). kind has no LB implementation -> port-forward.
ACCESS=localhost
if [[ "$CLUSTER" == kind ]]; then ACCESS=port-forward
elif lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 && $1 !~ /^com\.docke/' | grep -q .; then
  note "127.0.0.1:$PORT is taken by another process -> will use kubectl port-forward instead"
  ACCESS=port-forward
fi
# kind has no LoadBalancer implementation: an exposed App's Service would stay
# <pending> forever, and function-auto-ready (correctly) never marks it Ready.
APP_YAML=$(cat examples/hello.yaml)
if [[ "$CLUSTER" == kind ]]; then
  APP_YAML=$(sed 's/expose: true/expose: false/' <<<"$APP_YAML")
fi
if k -n "$NS" get app "$APP" >/dev/null 2>&1; then
  note "Removing a leftover App/$APP from a previous run..."
  k -n "$NS" delete app "$APP" --wait=true --timeout=180s >/dev/null
  wait_until 180 "previous run cleaned up" '[[ -z "$(composed)" ]]'
fi

cat <<EOF

  Crossplane v2 local demo   context=$CTX   namespace=$NS
  A developer asks for an "App"; the platform's Composition turns it into a
  Deployment, Service, a CloudNativePG Postgres (via provider-helm) and a
  connection Secret -- and keeps them that way.
EOF
pause

# ================================================================= 1
scene "1/7  Request an App and watch it come up"
run "cat examples/hello.yaml"
if [[ "$CLUSTER" == kind ]]; then
  note "kind: applying with expose: false (no LoadBalancer on kind; scene 2 uses port-forward)"
  run "k apply -f examples/namespace.yaml && sed 's/expose: true/expose: false/' examples/hello.yaml | k apply -f -"
else
  run "k apply -f examples/namespace.yaml -f examples/hello.yaml"
fi
say "Watching the XR (SYNCED → READY). Postgres takes ~1 minute on a laptop:"
show "kubectl get app -n $NS -w"
# kubectl directly, not via the k() function: backgrounding a function
# forks a subshell, so $! would be the subshell and kill would orphan kubectl.
kubectl --context "$CTX" -n "$NS" get app -w & WATCH_PID=$!
wait_until 300 "App/$APP is Ready" app_ready
kill "$WATCH_PID" 2>/dev/null; wait "$WATCH_PID" 2>/dev/null || true; WATCH_PID=""
say "The tree of everything Crossplane composed for this one App:"
run "trace"
run "k -n $NS get app $APP -o jsonpath='{.status}' | python3 -m json.tool | grep -vE 'lastTransitionTime|observedGeneration'"
pause

# ================================================================= 2
scene "2/7  Use it from the Mac"
URL=$(k -n "$NS" get app "$APP" -o jsonpath='{.status.url}')
if [[ "$ACCESS" == port-forward ]]; then
  say "Port-forwarding the composed Service to localhost:18080"
  kubectl --context "$CTX" -n "$NS" port-forward "svc/$APP" 18080:"$PORT" >/dev/null 2>&1 & PF_PID=$!
  sleep 3; URL=http://localhost:18080
fi
say "status.url = $URL  (expose: true → Service type LoadBalancer → Docker Desktop forwards it)"
run "curl -s $URL"
say "8 more requests -- which replicas answered?"
show "for i in \$(seq 8); do curl -s $URL | sed -n 's/Server name: //p'; done | sort | uniq -c"
for _ in $(seq 8); do curl -s "$URL" | sed -n 's/Server name: //p'; done | sort | uniq -c
note "Pod names = the replicas behind the Service (kube-proxy picks one per connection)."
say "The App's connection Secret (composed from the CNPG-generated credentials):"
show "kubectl -n $NS get secret $APP-db-conn -o jsonpath='{.data}'   # (decoded, password masked)"
conn_secret
say "Prove it works -- log in to Postgres with exactly those credentials:"
show "kubectl -n $NS exec $APP-db-1 -- psql -h $APP-db-rw -U app -d app   # password from $APP-db-conn"
db_login
pause

# ================================================================= 3
scene "3/7  Drift correction: Crossplane puts things back"
gen() { k -n "$NS" get deploy "$APP" -o jsonpath='{.metadata.generation}'; }
G0=$(gen)
say "Someone scales the Deployment by hand to 5 replicas..."
run "k -n $NS scale deploy/$APP --replicas=5"
wait_until 120 "Crossplane reverted spec.replicas to 2" \
  '[[ "$(k -n "$NS" get deploy "$APP" -o jsonpath="{.spec.replicas}")" == 2 && $(gen) -ge $((G0 + 2)) ]]'
note "metadata.generation $G0 → $(gen): one bump for our scale to 5, one for Crossplane's revert to 2."
note "Who wrote spec.replicas last? (server-side apply field managers):"
k -n "$NS" get deploy "$APP" --show-managed-fields -o json | python3 -c '
import json, sys
for m in json.load(sys.stdin)["metadata"]["managedFields"]:
    if "f:replicas" in json.dumps(m.get("fieldsV1", {})) and m.get("subresource") != "status":
        mgr = m["manager"]; mgr = mgr[:44] + "…" if len(mgr) > 45 else mgr
        print("    %-45s %-6s %s" % (mgr, m["operation"], m["time"]))'
run "k -n $NS get deploy $APP"
say "...then deletes the Deployment outright:"
UID0=$(k -n "$NS" get deploy "$APP" -o jsonpath='{.metadata.uid}')
run "k -n $NS delete deploy/$APP"
wait_until 120 "Deployment recreated" \
  '[[ -n "$(k -n "$NS" get deploy "$APP" -o jsonpath="{.metadata.uid}")" && "$(k -n "$NS" get deploy "$APP" -o jsonpath="{.metadata.uid}")" != "$UID0" ]]'
note "uid ${UID0:0:8}… → $(k -n "$NS" get deploy "$APP" -o jsonpath='{.metadata.uid}' | cut -c1-8)… (a brand-new object)"
wait_until 120 "and back to 2/2 available" \
  '[[ "$(k -n "$NS" get deploy "$APP" -o jsonpath="{.status.availableReplicas}")" == 2 ]]'
run "k -n $NS get deploy $APP"
note "Crossplane v2 watches composed resources, so drift is fixed in seconds -- not at the next poll."
pause

# ================================================================= 4
scene "4/7  Change propagation: edit the App, not the resources"
# Crossplane v2 has a per-XR watch circuit breaker: a burst of watch events on
# composed resources (scene 3's churn) opens it and throttles that XR's
# reconciles for ~1 min. The XR reports it as condition Responsive=False.
if [[ "$(k -n "$NS" get app "$APP" -o jsonpath='{.status.conditions[?(@.type=="Responsive")].status}')" != True ]]; then
  note "Creating the App + scene 3's churn tripped Crossplane's watch circuit breaker for App/$APP (Responsive=False)."
  note "It protects the control plane from hot loops. It re-closes after the cooldown"
  note "(1m here), but the condition only refreshes on the App's *next* reconcile -- a quiet"
  note "App may not get one. So we touch an annotation every 10s to give it that event."
  t0=$SECONDS
  until [[ "$(k -n "$NS" get app "$APP" -o jsonpath='{.status.conditions[?(@.type=="Responsive")].status}')" == True ]]; do
    (( SECONDS - t0 > 180 )) && { echo "  ✘ circuit still open after 180s" >&2; exit 1; }
    k -n "$NS" annotate app "$APP" demo.platform.demo.io/nudge="$SECONDS" --overwrite >/dev/null
    sleep 10
  done
  ok "circuit closed (Responsive=True)  ($((SECONDS - t0))s)"
fi
say "Scale through the platform API (spec.replicas 2 → 3):"
run "k -n $NS patch app $APP --type merge -p '{\"spec\":{\"replicas\":3}}'"
wait_until 120 "Deployment now has 3 available replicas" \
  '[[ "$(k -n "$NS" get deploy "$APP" -o jsonpath="{.status.availableReplicas}")" == 3 ]]'
run "k -n $NS get app,deploy"
say "Turn the database off (database.enabled: false):"
run "k -n $NS patch app $APP --type merge -p '{\"spec\":{\"database\":{\"enabled\":false}}}'"
wait_until 180 "Release, Postgres Cluster, observers and connection Secret removed" \
  '[[ -z "$(k -n "$NS" get releases.helm.m.crossplane.io,objects.kubernetes.m.crossplane.io,clusters.postgresql.cnpg.io --no-headers 2>/dev/null | grep "$APP-db")" ]] && ! k -n "$NS" get secret "$APP-db-conn"'
run "trace"
run "k -n $NS get app $APP"
pause

# ================================================================= 5
scene "5/7  Policy-like validation: the XRD schema is the contract"
say "Ask for a database size the platform doesn't offer:"
show 'sed "s/size: small/size: huge/" examples/hello.yaml | kubectl apply -f -'
if sed 's/size: small/size: huge/' <<<"$APP_YAML" | k apply -f - 2>&1; then
  echo "  ✘ expected the API server to reject this" >&2; exit 1
fi
ok "Rejected by the API server -- Crossplane never even saw it"
say "Same for out-of-range replicas:"
show 'sed "s/replicas: 2/replicas: 50/" examples/hello.yaml | kubectl apply -f -'
if sed 's/replicas: 2/replicas: 50/' <<<"$APP_YAML" | k apply -f - 2>&1; then
  echo "  ✘ expected the API server to reject this" >&2; exit 1
fi
ok "Rejected (maximum: 10)"
pause

# ================================================================= 6
scene "6/7  Offline testing with crossplane composition render (no cluster)"
note "render runs the real function containers in local Docker, against files only."
run "crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml crossplane/functions/functions.yaml | grep -E '^kind:|^  name:|dbReady|url:'"
say "Simulate 'Postgres is up' with observed resources -> the connection Secret appears:"
run "crossplane composition render examples/hello.yaml crossplane/compositions/app-dev.yaml crossplane/functions/functions.yaml --observed-resources tests/fixtures/observed-db-ready.yaml | grep -E '^kind:|^  name:|dbReady|connectionSecret:'"
say "Same App against the prod Composition (2 Postgres instances + PDBs):"
run "crossplane composition render examples/hello-prod.yaml crossplane/compositions/app-prod.yaml crossplane/functions/functions.yaml | grep -E '^kind:|instances:|enablePDB|minAvailable'"
pause

# ================================================================= 7
scene "7/7  Delete the App: everything cascades away"
run "k -n $NS delete app $APP --wait=false"
wait_until 180 "all composed resources gone" '[[ -z "$(composed)" ]]'
run "k -n $NS get all,secret,pvc,clusters.postgresql.cnpg.io"
note "(the namespace itself stays; 'make down' removes it)"

printf '\n\033[1;32mDemo complete.\033[0m  Try: make render · make test · examples/hello-prod.yaml\n'
