#!/usr/bin/env bash
# Show why the benchmark is waiting or failing, and save the full picture.
# Safe to run in a second terminal while run.sh is still going:
#
#   bash harness/scripts/diagnose.sh
#
# It only reads from the cluster. The files go to results/diagnostics/<time>/.
set -uo pipefail

: "${KUBECONFIG:=$HOME/.kube/gpu-sharing-demo}"
export KUBECONFIG
: "${NS:=default}"

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT="$ROOT/results/diagnostics/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

k() { kubectl -n "$NS" "$@"; }
save() { # file, command...
  local file=$1
  shift
  "$@" > "$OUT/$file" 2>&1 || true
}

save pods.txt k get pods -o wide
save pods-all-namespaces.txt kubectl get pods -A -o wide
save nodes.txt kubectl get nodes -o wide -L pool,gpu,dra,nvidia.com/device-plugin.config
save gpu-node.txt kubectl describe nodes -l pool=gpu
save events.txt k get events --sort-by=.lastTimestamp
save statefulset.txt k describe statefulset vllm
save services.txt k get svc,endpointslices -o wide
save model-download.log k logs job/model-download --tail=60
save loadgen.log k logs job/loadgen --tail=200
save nvidia-smi.txt kubectl -n kube-system exec ds/gpu-setup -- nvidia-smi
save hami-scheduler.log kubectl -n kube-system logs deploy/hami-scheduler --all-containers --tail=300
save hami-pods.log kubectl -n kube-system logs -l app.kubernetes.io/name=hami --all-containers --prefix --tail=150
save helm-releases.txt helm list -A
save kinference-resources.yaml k get inferenceworkersets.kinference.buoyant.io,inferencepools.kinference.buoyant.io,gateways.gateway.networking.k8s.io,httproutes.gateway.networking.k8s.io -o yaml
save kinference.log k logs deploy/kinference --tail=400
save gateway-data-plane.log k logs deploy/kinference-gw-gatewayd --tail=200
save gateway-control-plane.log k logs -l app.kubernetes.io/name=gateway --all-containers --prefix --tail=200
save llm-d-epp.log k logs deploy/llm-d-epp --all-containers --tail=300

for pod in $(k get pods -l app=vllm -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  save "$pod.describe.txt" k describe pod "$pod"
  save "$pod.log" k logs "$pod" --tail=400
  save "$pod.previous.log" k logs "$pod" --previous --tail=400
done

echo
echo "==> Pods in $NS"
cat "$OUT/pods.txt"
for pod in $(k get pods -l app=vllm -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  echo
  echo "==> $pod"
  k get pod "$pod" -o jsonpath='phase={.status.phase}  restarts={.status.containerStatuses[0].restartCount}  waiting={.status.containerStatuses[0].state.waiting.reason}  last-exit={.status.containerStatuses[0].lastState.terminated.reason}/{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}' 2>/dev/null || true
  # Scheduling and container events explain a pod that never starts.
  grep -E 'Warning|FailedScheduling|Failed|BackOff|OOM|Unhealthy' "$OUT/$pod.describe.txt" | tail -n 5 || true
  echo "--- last log lines"
  if [ -s "$OUT/$pod.previous.log" ] && ! grep -q 'previous terminated container' "$OUT/$pod.previous.log"; then
    tail -n 12 "$OUT/$pod.previous.log"
  else
    tail -n 8 "$OUT/$pod.log"
  fi
done
echo
echo "==> Saved to $OUT"
