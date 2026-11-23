#!/usr/bin/env bash
# Inference routing benchmark: the same model behind several front doors, one
# after the other. The Makefile runs it (make quick, make benchmark) on the
# cluster that make up creates. From the folder that holds harness/:
#
#   bash harness/scripts/run.sh all          # Service, Kinference, llm-d
#   bash harness/scripts/run.sh kthena       # one stack
#   bash harness/scripts/matrix.sh           # every stack, repeated and averaged
#
# Every setting below is an environment variable with a default. Written for
# the bash 3.2 that macOS ships.
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/gpu-sharing-demo}"
export KUBECONFIG
# Everything lives in one namespace. The Kinference guide installs into default.
: "${NS:=default}"
# How the replicas share the GPU: hami (a memory quota per replica) or
# time-slicing (NVIDIA device plugin, no quota).
: "${SHARING:=hami}"
: "${MODEL:=Qwen/Qwen2.5-7B-Instruct}"
# Kinference asks for vLLM 0.28.0 or later.
: "${VLLM_IMAGE:=vllm/vllm-openai:v0.31.0}"
: "${REPLICAS:=3}"
# HAMi: GPU memory per replica, in MiB. Three of them fit the 96 GB card.
: "${GPUMEM_MIB:=28000}"
: "${MAX_MODEL_LEN:=16384}"
: "${GWAPI_VERSION:=1.5.1}"
# The Buoyant Gateway and Kinference charts that every published repetition ran.
: "${GATEWAY_VERSION:=0.1.0-alpha.6}"
: "${KINFERENCE_VERSION:=0.1.0-alpha.7}"
: "${LLMD_VERSION:=v1.0.0}"
# The engines' prefill batch size (--max-num-batched-tokens), which llm-d's
# calibration needs. vLLM 0.31 runs its API server with 2048 on this GPU.
: "${LLMD_CHUNK_SIZE:=2048}"
: "${PSTACK_VERSION:=0.1.14}"
: "${KTHENA_VERSION:=v1.1.0}"
: "${DYNAMO_VERSION:=1.6.2}"
# The two weights that the tuned Kthena and Dynamo stacks set. Both decide how
# much a cache hit counts against load. Sweeps before the published runs chose
# them; harness/README.md has their results.
: "${KTHENA_PREFIX_WEIGHT:=4}"
: "${DYNAMO_PREFILL_LOAD_SCALE:=8}"
: "${WORKLOADS:=shared-prefix multi-turn control}"
# Seconds between the replicas turning ready and the first request.
: "${SETTLE_S:=45}"
# Extra settings for loadgen.py, for example LOADGEN_ENV="CONCURRENCY=12 VISITS=8".
: "${LOADGEN_ENV:=}"
# Extra arguments for the Kinference chart, for example a fitted profile:
# KINFERENCE_HELM_ARGS="-f harness/manifests/profile-fitted.yaml".
: "${KINFERENCE_HELM_ARGS:=}"
# 1 removes a stack again after its benchmark, so that the next one runs alone.
: "${TEARDOWN:=0}"
# 1 skips a workload that already has a summary in this result folder.
: "${SKIP_DONE:=0}"

case "$SHARING" in
  hami)
    GPU_RESOURCE=nvidia.com/gpu
    GPUMEM_LINE="nvidia.com/gpumem: \"$GPUMEM_MIB\""
    : "${GPU_MEM_UTIL:=0.90}" ;;
  time-slicing)
    GPU_RESOURCE=nvidia.com/gpu.shared
    GPUMEM_LINE=''
    : "${GPU_MEM_UTIL:=0.28}" ;;
  *)
    echo 'SHARING must be hami or time-slicing' >&2; exit 1 ;;
esac

HERE=$(cd "$(dirname "$0")" && pwd)
# The harness: scripts/ (this folder), application/, manifests/ and analysis/.
HARNESS=$(cd "$HERE/.." && pwd)
MANIFESTS="$HARNESS/manifests"
# The folder that holds the harness. matrix.sh sets it, because it runs a copy of the harness.
ROOT=${ROOT:-$(cd "$HARNESS/.." && pwd)}
CACHE="$ROOT/results/.cache"
STACKS='service kinference kinference-tuned llm-d llm-d-baseline llm-d-precise production-stack production-stack-prefix kthena kthena-tuned dynamo dynamo-kv dynamo-kv-tuned'

# One result folder per run. `all` starts a new one; every other step
# continues the latest, so that steps run one by one end up together.
# RUN=<id> picks a folder explicitly.
if [ -z "${RUN:-}" ]; then
  RUN=$(date +%Y%m%d-%H%M%S)
  if [ "${1:-}" != all ]; then
    for dir in "$ROOT"/results/*/05-inference-routing; do
      if [ -d "$dir" ]; then RUN=$(basename "$(dirname "$dir")"); fi
    done
  fi
fi
RESULTS="$ROOT/results/$RUN/05-inference-routing"

k() { kubectl -n "$NS" "$@"; }
say() { printf '\n==> %s\n' "$*"; }
gpu_node() { kubectl get nodes -l pool=gpu -o jsonpath='{.items[0].metadata.name}'; }

# Fill the placeholders of a manifest template.
render() {
  sed -e "s|__NS__|$NS|g" \
      -e "s|__VLLM_IMAGE__|$VLLM_IMAGE|g" \
      -e "s|__MODEL__|$MODEL|g" \
      -e "s|__REPLICAS__|$REPLICAS|g" \
      -e "s|__GPU_RESOURCE__|$GPU_RESOURCE|g" \
      -e "s|__GPUMEM_LINE__|$GPUMEM_LINE|g" \
      -e "s|__GPU_MEM_UTIL__|$GPU_MEM_UTIL|g" \
      -e "s|__MAX_MODEL_LEN__|$MAX_MODEL_LEN|g" \
      -e "s|__DYNAMO_VERSION__|$DYNAMO_VERSION|g" \
      -e "s|__DYNAMO_PREFILL_LOAD_SCALE__|$DYNAMO_PREFILL_LOAD_SCALE|g" \
      "$1"
}

# Wait for a Job to complete, and stop early when it fails.
wait_job() { # name, timeout in seconds
  local name=$1 deadline=$((SECONDS + $2)) conditions
  while [ "$SECONDS" -lt "$deadline" ]; do
    conditions=$(k get "job/$name" \
      -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{" "}{end}' 2>/dev/null || true)
    case " $conditions " in
      *" Complete "*) return 0 ;;
      *" Failed "*) echo "job/$name failed" >&2; return 1 ;;
    esac
    sleep 10
  done
  echo "job/$name did not finish within $2 seconds" >&2
  return 1
}

# The engine pods that the stack under test routes to. Dynamo brings its own.
ENGINE_SELECTOR='app=vllm'

# Wait until every replica is Ready. Stop early when a container keeps
# restarting, and show why.
wait_replicas() { # timeout in seconds
  local deadline=$((SECONDS + $1)) states restarts state pair ready count last='' line first
  while [ "$SECONDS" -lt "$deadline" ]; do
    states=$(k get pods -l "$ENGINE_SELECTOR" \
      -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{" "}{end}' 2>/dev/null || true)
    restarts=$(k get pods -l "$ENGINE_SELECTOR" \
      -o jsonpath='{range .items[*]}{.metadata.name}={.status.containerStatuses[0].restartCount}{" "}{end}' 2>/dev/null || true)
    ready=0
    count=0
    for state in $states; do
      count=$((count + 1))
      if [ "$state" = True ]; then ready=$((ready + 1)); fi
    done
    if [ "$count" -eq "$REPLICAS" ] && [ "$ready" -eq "$REPLICAS" ]; then
      echo "  $ready/$REPLICAS replicas ready"
      return 0
    fi
    line="  $ready/$REPLICAS replicas ready, loading the model"
    if [ "$line" != "$last" ]; then
      echo "$line"
      last=$line
    fi
    for pair in $restarts; do
      count=${pair##*=}
      if [ "${count:-0}" -ge 2 ]; then
        echo "${pair%%=*} keeps restarting. The errors in its previous log:" >&2
        show_errors "${pair%%=*}"
        exit 1
      fi
    done
    sleep 10
  done
  echo "The replicas were not ready within $1 seconds." >&2
  k get pods -l "$ENGINE_SELECTOR" -o wide || true
  first=$(k get pods -l "$ENGINE_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$first" ]; then show_errors "$first"; fi
  exit 1
}

show_errors() { # pod
  {
    k logs "$1" --previous --tail=400 2>/dev/null || k logs "$1" --tail=400 2>/dev/null || true
  } | grep -E 'Error|OOM|Killed' | grep -v Traceback | tail -n 8 | cut -c1-320 >&2 || true
  echo "For the full picture: bash $HERE/diagnose.sh" >&2
}

prepare() {
  local tool node existed
  for tool in kubectl helm jq git python3 curl; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
  done
  node=$(gpu_node)
  [ -n "$node" ] || { echo 'No GPU node. Run make up first.' >&2; exit 1; }

  say "Let the routers and the load generator schedule on the GPU node ($node)"
  # GKE taints GPU nodes. The gateway and router charts take no tolerations,
  # and the default node is too small for them. clean puts the taint back.
  kubectl taint node "$node" nvidia.com/gpu:NoSchedule- 2>/dev/null || true

  if [ "$SHARING" = hami ]; then
    say 'Share the GPU with HAMi'
    if kubectl get node "$node" -o json \
      | jq -e '.metadata.labels | has("nvidia.com/device-plugin.config") or has("dra")' >/dev/null; then
      echo 'Another sharing mode holds the GPU node. Release it first, or start from a fresh cluster.' >&2
      exit 1
    fi
    kubectl -n kube-system create configmap hami-node-config --dry-run=client -o yaml \
      --from-literal="config.json=$(jq -nc --arg node "$node" \
        '{nodeconfig:[{name:$node,operatingmode:"hami-core"}]}')" | kubectl apply -f -
    kubectl label node "$node" gpu=on --overwrite
    kubectl wait "node/$node" --for=jsonpath='{.status.allocatable.nvidia\.com/gpu}'=10 --timeout=300s
    sleep 20 # HAMi refreshes its scheduler cache every 15 seconds.
  else
    say 'Share the GPU with NVIDIA time-slicing'
    kubectl apply -f "$MANIFESTS/nvidia-time-slicing.yaml"
    kubectl label node "$node" nvidia.com/device-plugin.config=time-slicing --overwrite
    kubectl wait "node/$node" --for=jsonpath='{.status.allocatable.nvidia\.com/gpu\.shared}'=4 --timeout=300s
  fi

  say "Download $MODEL once, to the node's disk"
  k delete job model-download --ignore-not-found
  render "$MANIFESTS/model-download.yaml" | kubectl apply -f -
  if ! wait_job model-download 2400; then
    k logs job/model-download --tail=40 || true
    exit 1
  fi

  say "Start $REPLICAS vLLM replicas"
  existed=$(k get statefulset vllm -o name 2>/dev/null || true)
  render "$MANIFESTS/vllm.yaml" | kubectl apply -f -
  if [ -n "$existed" ]; then
    # A changed pod template rolls out one replica at a time, and not at all
    # past a replica that never turns ready. Recreate them together instead.
    k delete pod -l app=vllm --wait=true --timeout=300s
    sleep 5
  fi
  ENGINE_SELECTOR='app=vllm' wait_replicas 1800
  mkdir -p "$CACHE"
  echo "$node" > "$CACHE/prepared-node"
  record_versions
}

# A reclaimed Spot node comes back under a new name, without the model and
# without its labels. Prepare the fleet again when that has happened.
ensure_fleet() {
  local node
  node=$(gpu_node 2>/dev/null || true)
  if [ -z "$node" ] || [ "$node" != "$(cat "$CACHE/prepared-node" 2>/dev/null || true)" ] \
    || ! k get statefulset vllm >/dev/null 2>&1; then
    say 'The GPU node is new or not prepared yet'
    prepare
  fi
}

record_versions() {
  mkdir -p "$RESULTS"
  {
    echo "run: $RUN"
    echo "sharing: $SHARING"
    echo "model: $MODEL"
    echo "vllm_image: $VLLM_IMAGE"
    echo "replicas: $REPLICAS"
    echo "gpu_memory_per_replica_mib: ${GPUMEM_MIB:-}"
    echo "gpu_memory_utilization: $GPU_MEM_UTIL"
    echo "max_model_len: $MAX_MODEL_LEN"
    echo "llm_d_router: $LLMD_VERSION"
    echo "production_stack_chart: $PSTACK_VERSION"
    echo "kthena: $KTHENA_VERSION"
    echo "dynamo: $DYNAMO_VERSION"
    echo "buoyant_gateway: $GATEWAY_VERSION"
    echo "kinference: $KINFERENCE_VERSION"
    echo "loadgen_env: ${LOADGEN_ENV:-}"
    echo "kinference_helm_args: ${KINFERENCE_HELM_ARGS:-}"
  } > "$RESULTS/settings.yaml"
  # The profile that Kinference runs with, chart defaults included.
  helm get values kinference -n "$NS" -a -o yaml > "$RESULTS/kinference-values.yaml" 2>/dev/null \
    || rm -f "$RESULTS/kinference-values.yaml"
  kubectl version -o json > "$RESULTS/kubernetes-version.json" 2>/dev/null || true
  kubectl get nodes -o wide > "$RESULTS/nodes.txt" 2>/dev/null || true
  k get statefulset vllm -o yaml > "$RESULTS/vllm-statefulset.yaml" 2>/dev/null || true
  # Releases accumulate over the stacks of a run: every stack is removed again.
  helm list -A -o json 2>/dev/null \
    | jq -c '.[] | {name, namespace, chart, app_version}' >> "$RESULTS/helm-releases.jsonl" 2>/dev/null || true
  # The engine's own account of its KV cache: size in tokens and block size.
  k logs vllm-0 2>/dev/null | grep -i -E 'kv cache|maximum concurrency|block' \
    > "$RESULTS/vllm-kv-cache.txt" || true
}

# ---------------------------------------------------------------- stacks

# What a stack is: its front door, the pods that it adds and the engines that
# it routes to. Sets url, router_metrics, router_refs (namespace/kind/name of
# every workload that the stack adds), restart_ref (what router-restart
# deletes), engine_url, direct_url, pods_host, pods_port and ENGINE_SELECTOR.
stack_info() { # stack
  router_metrics=''
  router_refs=''
  restart_ref=''
  ENGINE_SELECTOR='app=vllm'
  engine_url="http://vllm.$NS.svc:8000"
  direct_url=$engine_url
  pods_host="vllm-pods.$NS.svc"
  pods_port=8000
  case "$1" in
    service)
      url=$engine_url ;;
    kinference|kinference-tuned)
      url="http://kinference-gw-gatewayd.$NS.svc:8080"
      router_metrics="http://kinference.$NS.svc:9001/metrics"
      router_refs="$NS/deploy/kinference $NS/deploy/kinference-gw-gatewayd"
      restart_ref="$NS/deploy/kinference" ;;
    llm-d|llm-d-baseline|llm-d-precise)
      url="http://llm-d-epp.$NS.svc:8081"
      router_refs="$NS/deploy/llm-d-epp"
      restart_ref=$router_refs ;;
    production-stack|production-stack-prefix)
      url="http://pstack-router-service.$NS.svc:80"
      router_refs="$NS/deploy/pstack-deployment-router"
      restart_ref=$router_refs ;;
    kthena|kthena-tuned)
      url="http://kthena-router.kthena-system.svc:80"
      router_refs="kthena-system/deploy/kthena-router"
      restart_ref=$router_refs ;;
    dynamo|dynamo-kv|dynamo-kv-tuned)
      ENGINE_SELECTOR='app=dynamo-worker'
      url="http://bench-frontend.$NS.svc:8000"
      # No door leads straight to a Dynamo worker: calibration goes through
      # the Frontend, and the overhead workload has nothing to compare with.
      engine_url=$url
      direct_url=none
      pods_host="dynamo-worker-pods.$NS.svc"
      pods_port=9090
      router_refs="$NS/deploy/bench-frontend dynamo-system/deploy/dynamo-platform-dynamo-operator-controller-manager"
      restart_ref="$NS/deploy/bench-frontend" ;;
    *)
      echo "unknown stack: $1 (one of: $STACKS)" >&2; exit 1 ;;
  esac
}

# The label selector of a workload, as kubectl -l takes it.
selector_of() { # namespace/kind/name
  local ns=${1%%/*} rest=${1#*/}
  kubectl -n "$ns" get "${rest%%/*}" "${rest#*/}" -o json 2>/dev/null \
    | jq -r '.spec.selector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")'
}

install_kinference() {
  say 'Install the Gateway API, the Buoyant Gateway and Kinference'
  kubectl apply --server-side --force-conflicts \
    -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/v$GWAPI_VERSION/standard-install.yaml"
  helm upgrade -i gateway-crds oci://ghcr.io/buoyantio/charts/gateway-crds -n "$NS" --version "$GATEWAY_VERSION"
  helm upgrade -i gateway oci://ghcr.io/buoyantio/charts/gateway -n "$NS" --version "$GATEWAY_VERSION" --wait
  helm upgrade -i kinference-crds oci://cr.kinference.ai/kinference-ai/charts/kinference-crds -n "$NS" --version "$KINFERENCE_VERSION"
  # logFormat and logLevel turn on one event per streaming request with the
  # predicted and the observed time to first token. A changed profile restarts
  # Kinference: the chart puts a checksum of the config on the pod.
  # shellcheck disable=SC2086 # one argument per word is the point
  helm upgrade -i kinference oci://cr.kinference.ai/kinference-ai/charts/kinference -n "$NS" --version "$KINFERENCE_VERSION" --wait \
    --set extension.enabled=true \
    --set logFormat=json \
    --set logLevel='kinference=info\,kinference::observation=debug\,dynamo_kv_router::indexer::radix_tree=error\,dynamo_kv_router=warn' \
    $KINFERENCE_HELM_ARGS

  render "$MANIFESTS/kinference.yaml" | kubectl apply -f -
  k wait inferenceworkersets.kinference.buoyant.io/vllm --for=jsonpath='{.status.state}'=Accepted --timeout=180s
  k wait inferencepools.kinference.buoyant.io/vllm-pool --for=jsonpath='{.status.state}'=Accepted --timeout=180s
  k wait gateways.gateway.networking.k8s.io/kinference-gw --for=condition=Programmed --timeout=300s
  k rollout status deploy/kinference-gw-gatewayd --timeout=300s
  record_versions
}

uninstall_kinference() {
  render "$MANIFESTS/kinference.yaml" | kubectl delete --ignore-not-found -f - 2>/dev/null || true
  helm uninstall kinference -n "$NS" --wait 2>/dev/null || true
  helm uninstall gateway -n "$NS" --wait 2>/dev/null || true
}

# One file of the llm-d guides at the pinned tag, kept in the cache.
llm_d_guide_file() { # path inside llm-d/llm-d
  local file
  file="$CACHE/llm-d-guides-$LLMD_VERSION/$(basename "$1")"
  mkdir -p "$(dirname "$file")"
  [ -s "$file" ] || curl -fsSL "https://raw.githubusercontent.com/llm-d/llm-d/$LLMD_VERSION/$1" -o "$file"
  echo "$file"
}

# llm-d's prefix-cache-affinity-filter estimates each replica's time to first
# token from the fleet's peak prefill throughput, a value that llm-d tells
# operators to measure per model and accelerator. Its guides ship a Job for
# that; run it once against the idle replicas and keep the result.
llm_d_peak_prefill() {
  local file="$CACHE/llm-d-peak-prefill-throughput" dir="$CACHE/llm-d-guides-$LLMD_VERSION/calibration" name
  if [ ! -s "$file" ]; then
    mkdir -p "$dir"
    for name in calibrate.sh calibration-peak-throughput.yaml; do
      [ -s "$dir/$name" ] || curl -fsSL \
        "https://raw.githubusercontent.com/llm-d/llm-d/$LLMD_VERSION/guides/recipes/router/calibration/$name" -o "$dir/$name"
    done
    if ! VLLM_ENDPOINT="http://vllm.$NS.svc:8000" MODEL_NAME="$MODEL" CHUNK_SIZE="$LLMD_CHUNK_SIZE" NAMESPACE="$NS" \
      bash "$dir/calibrate.sh" > "$CACHE/llm-d-calibration.log" 2>&1; then
      tail -n 20 "$CACHE/llm-d-calibration.log" >&2
      exit 1
    fi
    k logs job/calibrate-peak-throughput >> "$CACHE/llm-d-calibration.log" 2>/dev/null || true
    grep -o 'peakPrefillThroughput = [0-9]*' "$CACHE/llm-d-calibration.log" | head -n 1 | awk '{print $3}' > "$file"
    k delete job calibrate-peak-throughput --ignore-not-found >/dev/null
    k delete configmap calibrate-script --ignore-not-found >/dev/null
    [ -s "$file" ] || { echo 'The llm-d calibration printed no value.' >&2; exit 1; }
  fi
  cat "$file"
}

# The llm-d router in standalone mode: the endpoint picker with an Envoy
# sidecar. Without a profile it runs the chart's default scorers. `baseline` is
# the profile of the quickstart guide, `precise` the guide for prefix-cache
# routing on KV events. Both guide profiles get the calibrated throughput.
install_llm_d() { # profile: default, baseline or precise
  say "Install the llm-d router $LLMD_VERSION in standalone mode (${1:-default})"
  local src="$CACHE/llm-d-router-$LLMD_VERSION" base values peak
  mkdir -p "$CACHE"
  [ -d "$src" ] || git clone --quiet --depth 1 --branch "$LLMD_VERSION" \
    https://github.com/llm-d/llm-d-router.git "$src"
  helm dependency update "$src/config/charts/llm-d-router-standalone" >/dev/null
  set -- "${1:-default}"
  case "$1" in
    default)
      set -- -f "$MANIFESTS/llm-d-values.yaml" ;;
    baseline|precise)
      base=$(llm_d_guide_file guides/recipes/router/base.values.yaml)
      peak=$(llm_d_peak_prefill)
      echo "  peakPrefillThroughput: $peak tokens per second, from llm-d's calibration Job"
      values="$CACHE/llm-d-$1-values.yaml"
      render "$MANIFESTS/llm-d-$1-values.yaml" | sed -e "s|__LLMD_PEAK_PREFILL__|$peak|g" > "$values"
      set -- -f "$base" -f "$values" -f "$MANIFESTS/llm-d-values.yaml" ;;
    *)
      echo "unknown llm-d profile: $1" >&2; exit 1 ;;
  esac
  helm upgrade -i llm-d "$src/config/charts/llm-d-router-standalone" -n "$NS" "$@" \
    --set router.epp.image.tag="$LLMD_VERSION" \
    --wait --timeout 10m
  record_versions
}

# The production-stack router alone, in front of the shared replicas. Its
# Kubernetes discovery finds them by label.
install_production_stack() { # routing logic
  say "Install the production-stack router $PSTACK_VERSION ($1)"
  helm repo add vllm https://vllm-project.github.io/production-stack --force-update >/dev/null
  helm upgrade -i pstack vllm/vllm-stack --version "$PSTACK_VERSION" -n "$NS" \
    -f "$MANIFESTS/production-stack-values.yaml" \
    --set routerSpec.routingLogic="$1" \
    --set routerSpec.tag="v$PSTACK_VERSION" \
    --wait --timeout 10m
  record_versions
}

# The Kthena router alone, with one ModelServer that selects the shared
# replicas by label and one ModelRoute for the model name. Without a weight the
# scheduler plugins keep the chart's weights, 1 each.
install_kthena() { # weight of the prefix-cache plugin, optional
  say "Install the Kthena router $KTHENA_VERSION${1:+ (prefix-cache weight $1)}"
  helm upgrade -i kthena oci://ghcr.io/volcano-sh/charts/kthena --version "$KTHENA_VERSION" \
    -n kthena-system --create-namespace \
    --set workload.enabled=false \
    --set networking.kthenaRouter.service.type=ClusterIP \
    --set networking.kthenaRouter.image.tag="$KTHENA_VERSION" \
    --wait --timeout 10m
  if [ -n "${1:-}" ]; then
    # The chart writes the plugin weights into a ConfigMap and has no value
    # for them. The router reads the ConfigMap at start.
    kubectl -n kthena-system get configmap kthena-router-config -o json | python3 -c '
import json, re, sys
config = json.load(sys.stdin)["data"]["routerConfiguration"]
config, found = re.subn(r"(- name: prefix-cache\n\s+weight: )\d+", r"\g<1>" + sys.argv[1], config)
if found != 1:
    sys.exit("no prefix-cache weight in the router configuration")
print(json.dumps({"data": {"routerConfiguration": config}}))' "$1" > "$CACHE/kthena-config-patch.json"
    kubectl -n kthena-system patch configmap kthena-router-config --type merge \
      --patch-file "$CACHE/kthena-config-patch.json"
    kubectl -n kthena-system rollout restart deploy/kthena-router
    kubectl -n kthena-system rollout status deploy/kthena-router --timeout=300s
  fi
  render "$MANIFESTS/kthena.yaml" | kubectl apply -f -
  record_versions
}

# Dynamo's Frontend routes only to Dynamo's own workers. Its stacks stop the
# shared replicas and run the same number of Dynamo vLLM workers instead.
# dynamo.yaml marks the lines of KV-aware routing with "# kv" and the lines of
# the tuned stack with "# tuned".
install_dynamo() { # router mode: round-robin, kv or kv-tuned
  say "Install the Dynamo platform $DYNAMO_VERSION, its Frontend ($1) and $REPLICAS Dynamo vLLM workers"
  helm upgrade -i dynamo-platform \
    "https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-$DYNAMO_VERSION.tgz" \
    -n dynamo-system --create-namespace --wait --timeout 10m
  k scale statefulset vllm --replicas=0
  k wait pod -l app=vllm --for=delete --timeout=300s 2>/dev/null || true
  case "$1" in
    kv-tuned)
      render "$MANIFESTS/dynamo.yaml" | sed -e 's|__ROUTER_MODE__|kv|g' | kubectl apply -f - ;;
    kv)
      render "$MANIFESTS/dynamo.yaml" | sed -e 's|__ROUTER_MODE__|kv|g' -e '/# tuned$/d' | kubectl apply -f - ;;
    *)
      render "$MANIFESTS/dynamo.yaml" | sed -e 's|__ROUTER_MODE__|round-robin|g' -e '/# kv$/d' -e '/# tuned$/d' \
        | kubectl apply -f - ;;
  esac
  render "$MANIFESTS/dynamo-service.yaml" | kubectl apply -f -
  sleep 20 # the operator creates the pods
  wait_replicas 1800
  k rollout status deploy/bench-frontend --timeout=600s
  record_versions
}

uninstall_dynamo() {
  render "$MANIFESTS/dynamo.yaml" | sed -e 's|__ROUTER_MODE__|kv|g' | kubectl delete --ignore-not-found -f - 2>/dev/null || true
  render "$MANIFESTS/dynamo-service.yaml" | kubectl delete --ignore-not-found -f - 2>/dev/null || true
  k wait pod -l app=dynamo-worker --for=delete --timeout=300s 2>/dev/null || true
  # Bring the shared replicas back for the next stack. Its cold start waits
  # for them.
  if k get statefulset vllm >/dev/null 2>&1; then
    k scale statefulset vllm --replicas="$REPLICAS"
  fi
}

install_stack() { # stack
  case "$1" in
    service) ;;
    kinference) install_kinference ;;
    kinference-tuned)
      # The chart calls its profile a starting point. This one has the
      # predictor fitted to this fleet from Kinference's own observation
      # events (fit_profile.py). The tokenize mode stays "render": the chart
      # says to move to "local" only after "compare" has shown no divergence,
      # and with this model the local tokenizer cannot render the chat
      # template (checked in a separate run before the published ones).
      KINFERENCE_HELM_ARGS="-f $MANIFESTS/profile-fitted.yaml $KINFERENCE_HELM_ARGS"
      install_kinference ;;
    llm-d) install_llm_d default ;;
    llm-d-baseline) install_llm_d baseline ;;
    llm-d-precise) install_llm_d precise ;;
    production-stack) install_production_stack roundrobin ;;
    production-stack-prefix) install_production_stack prefixaware ;;
    kthena) install_kthena ;;
    kthena-tuned) install_kthena "$KTHENA_PREFIX_WEIGHT" ;;
    dynamo) install_dynamo round-robin ;;
    dynamo-kv) install_dynamo kv ;;
    dynamo-kv-tuned) install_dynamo kv-tuned ;;
  esac
}

uninstall_stack() { # stack
  say "Remove $1"
  case "$1" in
    service) ;;
    kinference|kinference-tuned) uninstall_kinference ;;
    llm-d|llm-d-baseline|llm-d-precise) helm uninstall llm-d -n "$NS" --wait 2>/dev/null || true ;;
    production-stack|production-stack-prefix) helm uninstall pstack -n "$NS" --wait 2>/dev/null || true ;;
    kthena|kthena-tuned)
      render "$MANIFESTS/kthena.yaml" | kubectl delete --ignore-not-found -f - 2>/dev/null || true
      helm uninstall kthena -n kthena-system --wait 2>/dev/null || true ;;
    dynamo|dynamo-kv|dynamo-kv-tuned) uninstall_dynamo ;;
  esac
}

# --------------------------------------------------------------- measuring

# Recreate every replica so that no KV cache survives from the previous run.
cold_start() { # stack
  say 'Cold start: recreate every replica'
  k delete pod -l "$ENGINE_SELECTOR" --wait=true --timeout=300s
  sleep 5
  wait_replicas 1800
  case "$1" in
    kinference*)
      k wait inferenceworkersets.kinference.buoyant.io/vllm --for=jsonpath='{.status.endpoints.ready}'="$REPLICAS" --timeout=300s ;;
  esac
}

# Record what the stack's own pods use, every 10 seconds, for as long as the
# phase file exists. The file names the phase: idle before the load, then load.
sample_top() { # output file, phase file
  local ref ns stamp selector
  while [ -f "$2" ]; do
    stamp=$(date -u +%s)
    for ref in $router_refs; do
      ns=${ref%%/*}
      selector=$(selector_of "$ref")
      # An empty selector would match every pod of the namespace.
      [ -n "$selector" ] || continue
      kubectl -n "$ns" top pod -l "$selector" --containers --no-headers 2>/dev/null \
        | awk -v t="$stamp" -v p="$(cat "$2" 2>/dev/null || echo load)" '{print t "\t" p "\t" $1 "\t" $2 "\t" $3 "\t" $4}' \
        >> "$1" || true
    done
    sleep 10
  done
}

# Wait for the load generator's mark, then delete one replica or the router.
disrupt() { # workload, output file, file that exists while the job runs
  local ns selector pods
  until k logs job/loadgen --since=20s 2>/dev/null | grep -q '"name":"disrupt"'; do
    [ -f "$3" ] || return 0
    sleep 2
  done
  if [ "$1" = replica-restart ]; then
    ns=$NS
    pods=$(k get pods -l "$ENGINE_SELECTOR" -o name | sort | sed -n '2p')
  else
    ns=${restart_ref%%/*}
    selector=$(selector_of "$restart_ref")
    # An empty selector would match every pod of the namespace.
    if [ -z "$selector" ]; then
      echo "  no selector for $restart_ref: nothing deleted" >&2
      return 0
    fi
    pods=$(kubectl -n "$ns" get pods -l "$selector" -o name)
  fi
  if [ -z "$pods" ]; then
    echo "  no pod to delete for $1" >&2
    return 0
  fi
  # shellcheck disable=SC2086 # one argument per pod is the point
  kubectl -n "$ns" delete $pods --wait=false >/dev/null
  jq -nc --arg workload "$1" --arg pods "$pods" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{workload: $workload, deleted: ($pods | split("\n")), at: $at}' > "$2"
  echo "  deleted $(echo $pods)"
}

collect() { # stack, workload, start time, output directory
  local ref selector
  case "$1" in
    kinference|kinference-tuned)
      k logs deploy/kinference --since-time="$3" 2>/dev/null \
        | jq -cR 'fromjson? | select(.target == "kinference::observation")' \
        > "$4/$2.observations.jsonl" || true
      # Everything else Kinference logged: warnings about tokenization,
      # evictions and block sizes end up here.
      k logs deploy/kinference --since-time="$3" 2>/dev/null \
        | grep -v 'kinference::observation' | tail -n 400 > "$4/$2.kinference.log" || true
      k logs deploy/kinference-gw-gatewayd --since-time="$3" --tail=200 \
        > "$4/$2.gateway.log" 2>/dev/null || true
      k get inferenceworkersets.kinference.buoyant.io,inferencepools.kinference.buoyant.io -o yaml > "$4/$2.status.yaml" 2>/dev/null || true
      ;;
    llm-d|llm-d-baseline|llm-d-precise)
      k logs deploy/llm-d-epp -c epp --since-time="$3" --tail=3000 > "$4/$2.epp.log" 2>/dev/null || true
      ;;
    service) ;;
    *)
      for ref in $router_refs; do
        kubectl -n "${ref%%/*}" logs "${ref#*/}" --all-containers --since-time="$3" --tail=3000 \
          > "$4/$2.$(basename "$ref").log" 2>/dev/null || true
      done
      ;;
  esac
  k get pods -l "$ENGINE_SELECTOR" -o wide > "$4/$2.pods.txt" 2>/dev/null || true
  for ref in $router_refs; do
    selector=$(selector_of "$ref")
    [ -n "$selector" ] || continue
    kubectl -n "${ref%%/*}" get pods -l "$selector" -o wide >> "$4/$2.pods.txt" 2>/dev/null || true
  done
}

bench() { # stack
  local stack=$1 out workload started pair phase running sampler watcher
  local literals=''
  stack_info "$stack"
  out="$RESULTS/$stack"
  mkdir -p "$out"

  k create configmap loadgen --from-file=loadgen.py="$HARNESS/application/loadgen.py" --dry-run=client -o yaml \
    | kubectl apply -f -
  for pair in ${LOADGEN_ENV:-}; do
    literals="$literals --from-literal=$pair"
  done
  # shellcheck disable=SC2086 # one argument per pair is the point
  k create configmap loadgen-env $literals --dry-run=client -o yaml | kubectl apply -f -

  for workload in $WORKLOADS; do
    if [ "$workload" = router-restart ] && [ -z "$restart_ref" ]; then
      echo "  $stack has no router to restart: skipping $workload"
      continue
    fi
    if [ "$SKIP_DONE" = 1 ] && grep -q '"type":"summary"' "$out/$workload.jsonl" 2>/dev/null; then
      echo "  $stack/$workload is already done"
      continue
    fi
    if [ "$(gpu_node 2>/dev/null || true)" != "$(cat "$CACHE/prepared-node" 2>/dev/null || true)" ]; then
      echo 'The GPU node changed in the middle of this stack. Run the step again.' >&2
      exit 1
    fi
    cold_start "$stack"
    phase="$out/.$workload.phase"
    running="$out/.$workload.running"
    rm -f "$out/$workload.top.tsv" "$out/$workload.disruption.json"
    sampler=''
    if [ -n "$router_refs" ]; then
      echo idle > "$phase"
      sample_top "$out/$workload.top.tsv" "$phase" &
      sampler=$!
    fi
    sleep "$SETTLE_S" # discovery, metric polls and KV-event subscriptions
    say "$stack: $workload"
    k delete job loadgen --ignore-not-found
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ -n "$sampler" ]; then echo load > "$phase"; fi
    render "$MANIFESTS/loadgen-job.yaml" \
      | sed -e "s|__STACK__|$stack|g" -e "s|__WORKLOAD__|$workload|g" \
            -e "s|__BASE_URL__|$url|g" -e "s|__ROUTER_METRICS_URL__|$router_metrics|g" \
            -e "s|__ENGINE_URL__|$engine_url|g" -e "s|__DIRECT_URL__|$direct_url|g" \
            -e "s|__PODS_HOST__|$pods_host|g" -e "s|__PODS_PORT__|$pods_port|g" \
      | kubectl apply -f -
    watcher=''
    case "$workload" in
      replica-restart|router-restart)
        : > "$running"
        disrupt "$workload" "$out/$workload.disruption.json" "$running" &
        watcher=$! ;;
    esac
    wait_job loadgen 3600 || true
    rm -f "$phase" "$running"
    if [ -n "$watcher" ]; then wait "$watcher" 2>/dev/null || true; fi
    if [ -n "$sampler" ]; then wait "$sampler" 2>/dev/null || true; fi
    k logs job/loadgen --tail=-1 > "$out/$workload.jsonl" 2>&1 || true
    collect "$stack" "$workload" "$started" "$out"
    grep -h -E '^\[loadgen\]' "$out/$workload.jsonl" | tail -n 3 || true
    k delete job loadgen --ignore-not-found
    if grep -q '"type":"fatal"' "$out/$workload.jsonl"; then
      echo "The load generator refused to measure $stack. Its reason is the line above;" >&2
      echo "for the cluster's side: bash $HERE/diagnose.sh" >&2
      exit 1
    fi
  done

  case "$stack" in
    kinference*)
      cat "$out"/*.observations.jsonl > "$out/observations.jsonl" 2>/dev/null || true ;;
  esac
  say "Results for $stack are in $out"
}

# One stack from start to end: install it, measure it and, with TEARDOWN=1,
# remove it again.
run_stack() { # stack
  stack_info "$1"
  ensure_fleet
  install_stack "$1"
  bench "$1"
  if [ "$TEARDOWN" = 1 ]; then uninstall_stack "$1"; fi
}

status() {
  kubectl get nodes -l pool=gpu \
    -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu,TAINTS:.spec.taints[*].key'
  k get pods -o wide
  k get svc
  k get inferenceworkersets.kinference.buoyant.io,inferencepools.kinference.buoyant.io,gateways.gateway.networking.k8s.io,httproutes.gateway.networking.k8s.io 2>/dev/null || true
  helm list -A
}

clean() {
  local node stack
  for stack in $STACKS; do
    uninstall_stack "$stack" >/dev/null 2>&1 || true
  done
  helm uninstall kinference-crds -n "$NS" 2>/dev/null || true
  helm uninstall gateway-crds -n "$NS" 2>/dev/null || true
  k delete job loadgen model-download --ignore-not-found
  k delete configmap loadgen loadgen-env --ignore-not-found
  render "$MANIFESTS/vllm.yaml" | kubectl delete --ignore-not-found -f -
  rm -f "$CACHE/prepared-node"
  node=$(gpu_node)
  if [ -n "$node" ]; then
    kubectl taint node "$node" nvidia.com/gpu=present:NoSchedule --overwrite || true
    if [ "$SHARING" = hami ]; then
      kubectl label node "$node" gpu- || true
    else
      kubectl label node "$node" nvidia.com/device-plugin.config- || true
    fi
  fi
  echo 'The Gateway API CRDs and the model files on the node are left in place.'
}

usage() {
  cat <<USAGE
usage: bash harness/scripts/run.sh <step>

  all          prepare, kinference, service, llm-d and report: about an hour
  prepare      share the GPU, download the model, start the replicas
  <stack>      install one stack and benchmark it. Stacks:
               $STACKS
  uninstall <stack>   remove one stack
  report       summarize the run into results/<run>/05-inference-routing/summary.md
  status       show the benchmark's pods, routes and releases
  clean        remove the benchmark and put the GPU node's taint back

WORKLOADS picks the workloads, for example WORKLOADS="burst mixed". TEARDOWN=1
removes the stack after its benchmark.
USAGE
}

report() { python3 "$HARNESS/analysis/report.py" "$RESULTS" "$RESULTS"; }

case "${1:-}" in
  all)
    prepare
    install_kinference
    bench kinference
    bench service
    install_llm_d default
    bench llm-d
    report ;;
  prepare) prepare ;;
  uninstall) uninstall_stack "${2:?which stack}" ;;
  report) report ;;
  status) status ;;
  clean) clean ;;
  '') usage; exit 1 ;;
  *)
    case " $STACKS " in
      *" $1 "*) run_stack "$1" ;;
      *) usage; exit 1 ;;
    esac ;;
esac
