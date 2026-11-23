#!/usr/bin/env bash
# The whole comparison: every stack, every workload, several times, averaged.
#
#   bash harness/scripts/matrix.sh
#   REPEATS=3 NAME=20261116-compare bash harness/scripts/matrix.sh
#
# A repetition is one result folder, results/<NAME>-r<n>. It runs every stack
# once, with its own prompts (SEED=<n>) and in an order that rotates from one
# repetition to the next, so that neither one set of prompts nor the time of
# the run favors a stack. Each stack is installed, measured and removed again,
# so that no other router runs next to it.
#
# The script can be interrupted and started again: workloads that have a
# summary are not repeated. It stops with exit code 3 when it cannot reach the
# cluster, which on GKE usually means that the gcloud login has expired.
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/gpu-sharing-demo}"
export KUBECONFIG
: "${REPEATS:=5}"
: "${NAME:=$(date +%Y%m%d)-compare}"
# Stacks that get every workload: the Service, and each router in its best
# documented setup for cache reuse, with the values that depend on the
# hardware, the engine and the model fitted to this fleet.
: "${FULL_STACKS:=service kinference-tuned llm-d-baseline llm-d-precise production-stack-prefix kthena-tuned dynamo-kv-tuned}"
# Routers as their own defaults leave them, where that differs from the setup above.
: "${PLAIN_STACKS:=kinference llm-d production-stack kthena dynamo dynamo-kv}"
: "${CORE:=shared-prefix multi-turn control pressure burst mixed}"
: "${EXTENDED:=rate-sweep replica-restart router-restart overhead}"
: "${PLAIN:=shared-prefix multi-turn control}"
# The extended workloads and the plain stacks run in the first repetitions only.
: "${EXTENDED_REPEATS:=3}"
: "${PLAIN_REPEATS:=3}"
# How often to try a stack again after a failed run.
: "${RETRIES:=2}"

HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS=$(cd "$HERE/.." && pwd)
ROOT=${ROOT:-$(cd "$HARNESS/.." && pwd)}
export ROOT
CASE=05-inference-routing
OUT="$ROOT/results/$NAME"
mkdir -p "$OUT"
LOG="$OUT/matrix.log"

# Run from a copy of the harness. Bash reads a script while it runs, so an edit
# here would otherwise change a run that is under way. The copy also records
# what produced the results. A restart takes a fresh copy.
if [ -z "${MATRIX_SNAPSHOT:-}" ]; then
  rm -rf "$OUT/harness"
  mkdir -p "$OUT/harness"
  cp -R "$HARNESS/application" "$HARNESS/analysis" "$HARNESS/manifests" "$HARNESS/scripts" "$OUT/harness/"
  MATRIX_SNAPSHOT=1 exec bash "$OUT/harness/scripts/matrix.sh" "$@"
fi

note() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$LOG"; }

# The workloads of one stack in one repetition.
workloads_for() { # stack, repetition
  case " $FULL_STACKS " in
    *" $1 "*)
      if [ "$2" -le "$EXTENDED_REPEATS" ]; then echo "$CORE $EXTENDED"; else echo "$CORE"; fi
      return ;;
  esac
  if [ "$2" -le "$PLAIN_REPEATS" ]; then echo "$PLAIN"; fi
}

# A workload counts when it has a summary. A restart workload also needs the
# record that run.sh writes when it deletes the pod: without it, nothing was
# restarted, for example because this machine slept through the mark.
valid() { # run folder, stack, workload
  local base="$ROOT/results/$1/$CASE/$2/$3"
  grep -q '"type":"summary"' "$base.jsonl" 2>/dev/null || return 1
  case "$3" in
    replica-restart|router-restart) [ -s "$base.disruption.json" ] || return 1 ;;
  esac
}

# The workloads that still have no valid result.
missing() { # run folder, stack, workloads...
  local run=$1 stack=$2 workload
  shift 2
  for workload in "$@"; do
    # The Service has no router to restart.
    if [ "$stack" = service ] && [ "$workload" = router-restart ]; then continue; fi
    valid "$run" "$stack" "$workload" || printf '%s ' "$workload"
  done
}

# Stop when the cluster does not answer; wait when its Spot GPU node is away.
cluster_ready() {
  local waited=0
  if ! kubectl get nodes >/dev/null 2>&1; then
    note 'Cannot reach the cluster. Log in again (gcloud auth login) and restart this script.'
    exit 3
  fi
  until kubectl get nodes -l pool=gpu --no-headers 2>/dev/null | grep -q ' Ready'; do
    if [ "$waited" -ge 3600 ]; then
      note 'No ready GPU node for an hour. Stopping.'
      exit 4
    fi
    if [ "$waited" -eq 0 ]; then note 'The GPU node is away (a reclaimed Spot node). Waiting for a new one.'; fi
    sleep 60
    waited=$((waited + 60))
  done
}

report() {
  local folders='' dir
  for dir in "$ROOT"/results/"$NAME"-r*/"$CASE"; do
    if [ -d "$dir" ]; then folders="$folders $dir"; fi
  done
  # shellcheck disable=SC2086 # one argument per folder is the point
  [ -z "$folders" ] || python3 "$HARNESS/analysis/report.py" "$OUT" $folders > /dev/null
}

set -- $FULL_STACKS $PLAIN_STACKS
count=$#
note "Matrix $NAME: $REPEATS repetitions of $count stacks"
failed=''
rep=1
while [ "$rep" -le "$REPEATS" ]; do
  run="$NAME-r$rep"
  position=0
  while [ "$position" -lt "$count" ]; do
    # Rotate the order: repetition n starts with stack n.
    index=$(( (position + rep - 1) % count + 1 ))
    stack=$(eval "echo \${$index}")
    position=$((position + 1))
    # shellcheck disable=SC2046 # one argument per workload is the point
    todo=$(missing "$run" "$stack" $(workloads_for "$stack" "$rep"))
    if [ -z "$todo" ]; then continue; fi
    attempt=0
    while [ -n "$todo" ]; do
      cluster_ready
      attempt=$((attempt + 1))
      note "Repetition $rep of $REPEATS, $stack (attempt $attempt): $todo"
      # run.sh skips a workload that has a summary, so clear what does not count.
      for workload in $todo; do
        rm -f "$ROOT/results/$run/$CASE/$stack/$workload.jsonl"
      done
      if RUN="$run" WORKLOADS="$todo" TEARDOWN=1 SKIP_DONE=1 LOADGEN_ENV="SEED=$rep ${LOADGEN_ENV:-}" \
        bash "$HERE/run.sh" "$stack" >> "$OUT/$run.$stack.log" 2>&1; then
        :
      else
        note "  run.sh failed for $stack; its log is $OUT/$run.$stack.log"
        cluster_ready
        RUN="$run" bash "$HERE/run.sh" uninstall "$stack" >> "$OUT/$run.$stack.log" 2>&1 || true
      fi
      # shellcheck disable=SC2046
      todo=$(missing "$run" "$stack" $(workloads_for "$stack" "$rep"))
      if [ -n "$todo" ] && [ "$attempt" -gt "$RETRIES" ]; then
        note "  giving up on $stack in repetition $rep: no result for $todo"
        failed="$failed $run/$stack"
        break
      fi
    done
  done
  report
  note "Repetition $rep is complete. The averages so far are in $OUT/repeats.md"
  rep=$((rep + 1))
done

if [ -n "$failed" ]; then note "Without a complete result:$failed"; fi
note 'Done.'
