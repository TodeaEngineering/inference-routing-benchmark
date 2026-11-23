#!/usr/bin/env python3
"""Fit Kinference's predictor to the observation events of earlier runs.

    fit_profile.py OUT.yaml RUN_DIR [RUN_DIR ...]

RUN_DIR is results/<run>/05-inference-routing of a run with a Kinference
stack. For every request, Kinference logs the blocks it had to prefill, the
load on the worker it picked and the TTFT it observed. This script finds the
coefficients whose predictions come closest to the observed TTFT and writes
them as Helm values for the Kinference chart.
"""
import json
import math
import statistics
import sys
from datetime import datetime
from pathlib import Path

NAMES = ["base_ms", "attention_uncached_block_ms", "attention_uncached_per_every_block_ms", "forward_pass_ms"]


def load(run_dir):
    events = []
    for line in (Path(run_dir) / "kinference" / "observations.jsonl").read_text(errors="replace").splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get("upstream_status") != 200 or "observed_ms" not in e:
            continue
        # Kinference logs the event when the first token comes back.
        first_token = datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")).timestamp() * 1000
        events.append({
            "worker": e["worker"],
            "observed": float(e["observed_ms"]),
            "total": int(e["total_blocks"]),
            "uncached": int(e["total_blocks"]) - int(e["overlap_blocks"]),
            "running": int(e["q_running"]),
            "waiting": int(e["q_waiting"]),
            "capacity": int(e.get("inflight_concurrent_capacity", 5)),
            "first_token": first_token,
            "sent": first_token - float(e["observed_ms"]),
        })

    # For each request, the requests sent earlier to the same worker that had no first token yet.
    by_worker = {}
    for e in events:
        by_worker.setdefault(e["worker"], []).append(e)
    for queue in by_worker.values():
        queue.sort(key=lambda e: e["sent"])
        for i, e in enumerate(queue):
            e["ahead"] = [(o["uncached"], o["total"], e["sent"] - o["sent"])
                          for o in queue[:i] if o["first_token"] > e["sent"]]
    return [e for e in events if e["total"] > 5]  # skip the load generator's tiny probe requests


def predict(e, base, a, c, forward_pass):
    """Kinference's predicted TTFT for the worker it picked."""
    def prefill(uncached, total):
        return a * uncached + c * uncached * total

    queue = 0.0
    capacity = 0 if e["waiting"] > 0 else e["capacity"]  # a waiting request means the batch is full
    for position, (uncached, total, elapsed) in enumerate(e["ahead"], start=1):
        cost = prefill(uncached, total)
        if position > capacity:
            queue += cost
        elif cost > 0:
            queue += max(0.0, 1.0 - elapsed / cost) * cost
    return base + queue + prefill(e["uncached"], e["total"]) + forward_pass * (e["running"] + len(e["ahead"]))


def loss(events, params):
    """Mean absolute log of predicted over observed, so a 0.1 s request counts as much as a 1 s one."""
    if min(params) < 0:
        return math.inf
    total = 0.0
    for e in events:
        predicted = predict(e, *params)
        if predicted <= 0:
            return math.inf
        total += abs(math.log(predicted / e["observed"]))
    return total / len(events)


def minimize(f, start, steps):
    """Nelder-Mead, restarted four times from its best point with smaller steps."""
    best = start
    for _ in range(4):
        points = [best] + [[v + (steps[i] if i == j else 0.0) for i, v in enumerate(best)] for j in range(len(best))]
        values = [f(p) for p in points]
        for _ in range(400):
            order = sorted(range(len(points)), key=values.__getitem__)
            points = [points[i] for i in order]
            values = [values[i] for i in order]
            centre = [sum(col) / (len(points) - 1) for col in zip(*points[:-1])]
            worst = points[-1]
            reflected = [2 * c - w for c, w in zip(centre, worst)]
            fr = f(reflected)
            if fr < values[0]:
                expanded = [3 * c - 2 * w for c, w in zip(centre, worst)]
                fe = f(expanded)
                points[-1], values[-1] = (expanded, fe) if fe < fr else (reflected, fr)
            elif fr < values[-2]:
                points[-1], values[-1] = reflected, fr
            else:
                contracted = [(c + w) / 2 for c, w in zip(centre, worst)]
                fc = f(contracted)
                if fc < values[-1]:
                    points[-1], values[-1] = contracted, fc
                else:  # shrink towards the best point
                    points = [points[0]] + [[(v + b) / 2 for v, b in zip(p, points[0])] for p in points[1:]]
                    values = [values[0]] + [f(p) for p in points[1:]]
        best = points[values.index(min(values))]
        steps = [s / 4 for s in steps]
    return best


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    runs = sys.argv[2:]
    events = [e for run in runs for e in load(run)]

    # Start from the chart's defaults.
    base, a, c, forward_pass = minimize(lambda p: loss(events, p), [400.0, 2.3, 0.03, 5.0], [100.0, 1.0, 0.01, 5.0])
    params = [round(base), round(a, 2), round(c, 4), round(forward_pass, 1)]

    ratios = [predict(e, *params) / e["observed"] for e in events]
    print(f"{len(events)} requests, median predicted/observed {statistics.median(ratios):.2f}")
    for name, value in zip(NAMES, params):
        print(f"  {name}: {value}")

    names = ", ".join(Path(run).resolve().parent.name for run in runs)
    Path(sys.argv[1]).write_text(
        "# Predictor coefficients fitted by fit_profile.py to the observation events of\n"
        f"# {names}.\n"
        "# Everything that is not listed keeps the chart's default.\n"
        "config:\n  profiles:\n    default:\n      predictor:\n"
        + "".join(f"        {name}: {value}\n" for name, value in zip(NAMES, params)))


if __name__ == "__main__":
    main()
