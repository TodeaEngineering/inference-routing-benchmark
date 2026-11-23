#!/usr/bin/env python3
"""Compare Kinference with the chart's profile and with the fitted one.

    compare_profiles.py RUN_DIR [RUN_DIR ...]

RUN_DIR is results/<run>/05-inference-routing from make benchmark. Each run
has the kinference stack (the chart's profile) and kinference-tuned (the
fitted profile, profile-fitted.yaml), measured with the same prompts. Prints
how close each profile's predictions came to the observed TTFT, and the TTFT
that each profile got.
"""
import json
import statistics
import sys
from pathlib import Path

PROFILES = [("kinference", "Chart's profile"), ("kinference-tuned", "Fitted profile")]
WORKLOADS = ["shared-prefix", "multi-turn", "control"]


def read_jsonl(path):
    rows = []
    if path.exists():
        for line in path.read_text(errors="replace").splitlines():
            if line.startswith("{"):
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    pass
    return rows


def ms(v):
    return f"{v / 1000:.2f} s" if v >= 1000 else f"{v:.0f} ms"


def prediction(runs, stack):
    """What Kinference predicted for each request against what it observed, on the workloads both stacks run."""
    events = [e for run in runs for workload in WORKLOADS
              for e in read_jsonl(run / stack / f"{workload}.observations.jsonl")
              if e.get("upstream_status") == 200 and "observed_ms" in e and e["total_blocks"] > 5]
    if not events:
        return None
    predicted = [float(e["predicted_ms"]) for e in events]
    observed = [float(e["observed_ms"]) for e in events]
    ratios = [p / o for p, o in zip(predicted, observed)]
    out = {"requests": len(events),
           "ratio": statistics.median(ratios),
           "error": statistics.median(abs(p - o) for p, o in zip(predicted, observed)),
           "within_25": sum(0.8 <= r <= 1.25 for r in ratios) / len(ratios)}
    warm = [i for i, e in enumerate(events) if e["overlap_blocks"] / e["total_blocks"] >= 0.9]
    cold = [i for i, e in enumerate(events) if e["overlap_blocks"] == 0]
    for kind, picks in (("warm", warm), ("cold", cold)):
        if picks:
            out[kind] = (statistics.median(predicted[i] for i in picks), statistics.median(observed[i] for i in picks))
    return out


def ttft(runs, stack, workload):
    """Median TTFT, p95 TTFT and cached share of each run, from the load generator's summary line."""
    out = []
    for run in runs:
        summaries = [r for r in read_jsonl(run / stack / f"{workload}.jsonl") if r.get("type") == "summary"]
        if summaries:
            s = summaries[-1]
            scope = s["eligible"] if s["eligible"]["ok"] else s["all"]
            out.append((scope["ttft_ms"]["p50"], scope["ttft_ms"]["p95"], scope["cached_share"]))
    return out


def cell(values):
    return f"{ms(statistics.mean(values))} ({ms(min(values))} to {ms(max(values))})"


def main():
    runs = [Path(arg) for arg in sys.argv[1:]]
    if not runs:
        sys.exit(__doc__)

    print("## Predictions\n")
    print("| Profile | Requests | Predicted / observed, median | Median error | Within 25% | "
          "Warm: predicted / observed | Cold: predicted / observed |")
    print("|---|---|---|---|---|---|---|")
    for stack, name in PROFILES:
        p = prediction(runs, stack)
        if p:
            warm = " / ".join(ms(v) for v in p["warm"]) if "warm" in p else "n/a"
            cold = " / ".join(ms(v) for v in p["cold"]) if "cold" in p else "n/a"
            print(f"| {name} | {p['requests']} | {p['ratio']:.2f} | {ms(p['error'])} | {p['within_25']:.0%} "
                  f"| {warm} | {cold} |")

    print("\n## TTFT\n")
    print("Mean of the runs, lowest to highest run in parentheses.\n")
    print("| Workload | Profile | Runs | Median TTFT | p95 TTFT | Cached share |")
    print("|---|---|---|---|---|---|")
    for workload in WORKLOADS:
        for stack, name in PROFILES:
            per_run = ttft(runs, stack, workload)
            if per_run:
                p50, p95, cached = zip(*per_run)
                print(f"| {workload} | {name} | {len(per_run)} | {cell(p50)} | {cell(p95)} | {statistics.mean(cached):.0%} |")


if __name__ == "__main__":
    main()
