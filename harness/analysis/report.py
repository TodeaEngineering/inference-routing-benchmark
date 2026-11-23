#!/usr/bin/env python3
"""Summarize benchmark runs into one table per workload.

    report.py OUT_DIR RUN_DIR [RUN_DIR ...]

RUN_DIR is results/<run>/05-inference-routing. The load generator ends every
<stack>/<workload>.jsonl with a summary line; this script reads those lines
and averages them across runs. One run gives summary.md and summary.json,
several give repeats.md and repeats.json.
"""
import json
import statistics
import sys
from pathlib import Path

STACKS = ["service", "kinference-tuned", "kinference", "llm-d-baseline", "llm-d-precise", "llm-d",
          "production-stack-prefix", "production-stack", "kthena-tuned", "kthena",
          "dynamo-kv-tuned", "dynamo-kv", "dynamo"]
WORKLOADS = ["shared-prefix", "multi-turn", "control", "pressure", "burst", "mixed", "rate-sweep",
             "replica-restart", "router-restart", "overhead"]


def ms(v):
    return f"{v / 1000:.2f} s" if v >= 1000 else f"{v:.0f} ms"


def pct(v):
    return f"{v * 100:.0f}%"


def num(v):
    return f"{v:.1f}"


COLUMNS = [("p50", "Median TTFT", ms), ("p95", "p95 TTFT", ms), ("cached", "Cached share", pct),
           ("total_p50", "Median total time", ms), ("errors", "Failed requests", num)]
RESTART = [("cached_before", "Cached share before", pct), ("cached_last", "Cached share, last minute", pct)]
EXTRA = {
    "burst": [("replicas", "Replicas per burst", num), ("burst_p50", "Median TTFT in a burst", ms),
              ("burst_cached", "Cached share in a burst", pct)],
    "mixed": [("long_p50", "Median TTFT, long requests", ms)],
    "replica-restart": RESTART,
    "router-restart": RESTART,
    "overhead": [("added_p50", "Added, median", ms), ("added_p95", "Added, p95", ms)],
}
FOOTPRINT = [("cpu_idle", "CPU idle, millicores", num), ("cpu_load", "CPU under load, millicores", num),
             ("mem_load", "Memory under load, MiB", num)]


def read_jsonl(path):
    rows = []
    for line in path.read_text(errors="replace").splitlines():
        if line.strip().startswith("{"):
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    return rows


def quantity(text):
    """kubectl top values (250m, 2, 85Mi, 1Gi) as millicores or MiB."""
    for unit, factor in (("n", 1e-6), ("u", 1e-3), ("m", 1.0), ("Ki", 1 / 1024), ("Mi", 1.0), ("Gi", 1024.0)):
        if text.endswith(unit):
            return float(text[:-len(unit)]) * factor
    return float(text) * 1000


def footprint(path):
    """Mean CPU and peak memory of the stack's pods, from the samples run.sh takes every 10 s."""
    if not path.exists():
        return {}
    samples = {}  # (phase, time) -> [millicores, MiB] summed over the stack's containers
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) != 6:
            continue
        try:
            cpu, mem = quantity(parts[4]), quantity(parts[5])
        except ValueError:
            continue
        total = samples.setdefault((parts[1], parts[0]), [0.0, 0.0])
        total[0] += cpu
        total[1] += mem
    idle = [v for (phase, _), v in samples.items() if phase == "idle"]
    load = [v for (phase, _), v in samples.items() if phase == "load"]
    out = {}
    if idle:
        out["cpu_idle"] = statistics.mean(cpu for cpu, _ in idle)
    if load:
        out["cpu_load"] = statistics.mean(cpu for cpu, _ in load)
        out["mem_load"] = max(mem for _, mem in load)
    return out


def figures(path):
    """The numbers of one stack and workload in one run, or None if the run doesn't count."""
    rows = read_jsonl(path)
    summaries = [r for r in rows if r.get("type") == "summary"]
    if not summaries:
        return None  # the load generator didn't finish
    s = summaries[-1]
    if (s.get("router_delta") or s.get("router_metrics") or {}).get("kinference_score_degraded_total"):
        return None  # Kinference fell back to load-only picks
    if "restart" in path.stem and not path.with_name(path.stem + ".disruption.json").exists():
        return None  # the pod was never deleted

    scope = s["eligible"] if s["eligible"]["ok"] else s["all"]
    ok = [r for r in rows if r.get("type") == "request" and r.get("status") == 200]
    done = [r for r in ok if r.get("eligible") and not r.get("error")] or ok
    total = [r["total_ms"] for r in done if r.get("total_ms")]
    f = {"p50": scope["ttft_ms"]["p50"], "p95": scope["ttft_ms"]["p95"], "cached": scope["cached_share"],
         "total_p50": statistics.median(total) if total else None, "errors": s["errors"]}

    first = s.get("first_contact") or {}
    if s.get("burst"):
        f["replicas"] = s["burst"].get("replicas_used_mean")
        f["burst_p50"] = (first.get("ttft_ms") or {}).get("p50")
        f["burst_cached"] = first.get("cached_share")
    if s.get("mixed"):
        f["long_p50"] = (first.get("ttft_ms") or {}).get("p50")
    for stage in s.get("stages") or []:
        rate = f"{stage['rate_per_s']:g}/s"
        f[rate + " p50"] = stage["ttft_ms"]["p50"]
        f[rate + " p95"] = stage["ttft_ms"]["p95"]
        f[rate + " failed"] = stage["errors"] + stage["shed"]
        f[rate + " achieved"] = stage["achieved_per_s"]
    if s.get("disruption"):
        d = s["disruption"]
        f.update(errors=d["errors"], cached_before=d["cached_share_before"], cached_last=d["cached_share_last_minute"])
    if s.get("overhead"):
        f.update(added_p50=s["overhead"]["added_ms_p50"], added_p95=s["overhead"]["added_ms_p95"])
    f.update(footprint(path.with_name(path.stem + ".top.tsv")))
    return f


def spread(values):
    values = [v for v in values if v is not None]
    if not values:
        return None
    return {"n": len(values), "mean": statistics.mean(values),
            "sd": statistics.stdev(values) if len(values) > 1 else None,
            "min": min(values), "max": max(values)}


def cell(s, fmt):
    if not s:
        return "n/a"
    if s["n"] == 1:
        return fmt(s["mean"])
    return f"{fmt(s['mean'])} ± {fmt(s['sd'])} ({fmt(s['min'])} to {fmt(s['max'])})"


def ordered(names, order):
    return [n for n in order if n in names] + sorted(n for n in names if n not in order)


def table(lines, rows, columns):
    """rows: {stack: {figure: spread}}. Leaves out columns that are empty or zero for every stack."""
    columns = [c for c in columns if any(stats.get(c[0]) and stats[c[0]]["max"] for stats in rows.values())]
    lines.append("| Stack | " + " | ".join(header for _, header, _ in columns) + " |")
    lines.append("|---|" + "---|" * len(columns))
    for stack, stats in rows.items():
        lines.append(f"| {stack} | " + " | ".join(cell(stats.get(key), fmt) for key, _, fmt in columns) + " |")
    lines.append("")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out_dir = Path(sys.argv[1])
    runs = [Path(arg) for arg in sys.argv[2:]]

    found = {}  # workload -> stack -> [figures of each run]
    for run in runs:
        for path in sorted(run.glob("*/*.jsonl")):
            if "." in path.stem or path.stem == "observations":
                continue
            f = figures(path)
            if f:
                found.setdefault(path.stem, {}).setdefault(path.parent.name, []).append(f)

    names = [run.parent.name for run in runs]
    lines = [f"# Inference routing benchmark: {', '.join(names)}", ""]
    if len(runs) > 1:
        lines += ["Each figure is computed per run, then averaged: mean ± standard deviation, "
                  "lowest to highest run in parentheses.", ""]
    result = {"runs": names, "workloads": {}, "footprint": {}}

    for workload in ordered(found, WORKLOADS):
        rows = {}
        for stack in ordered(found[workload], STACKS):
            per_run = found[workload][stack]
            rows[stack] = {key: spread([f.get(key) for f in per_run]) for key in sorted({k for f in per_run for k in f})}
        columns = COLUMNS + EXTRA.get(workload, [])
        rates = sorted({key.split("/")[0] for stats in rows.values() for key in stats if key.endswith("/s p50")}, key=float)
        for rate in rates:
            columns += [(f"{rate}/s p50", f"{rate}/s median", ms), (f"{rate}/s p95", f"{rate}/s p95", ms),
                        (f"{rate}/s failed", f"{rate}/s failed", num), (f"{rate}/s achieved", f"{rate}/s achieved", num)]
        lines += [f"## {workload}", ""]
        table(lines, rows, columns)
        result["workloads"][workload] = rows

    for stack in ordered({s for stacks in found.values() for s in stacks}, STACKS):
        merged = [f for stacks in found.values() for f in stacks.get(stack, [])]
        stats = {key: spread([f.get(key) for f in merged]) for key, _, _ in FOOTPRINT}
        if any(stats.values()):
            result["footprint"][stack] = stats
    if result["footprint"]:
        lines += ["## Router footprint", "",
                  "CPU and memory of the pods each stack adds: mean CPU and peak memory per workload, "
                  "averaged over workloads and runs.", ""]
        table(lines, result["footprint"], FOOTPRINT)

    name = "summary" if len(runs) == 1 else "repeats"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / f"{name}.md").write_text("\n".join(lines))
    (out_dir / f"{name}.json").write_text(json.dumps(result, indent=1))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
