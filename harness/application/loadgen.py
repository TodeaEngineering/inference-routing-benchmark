#!/usr/bin/env python3
"""Load generator for the inference routing benchmark.

Sends OpenAI chat completions through one front door (a plain Service,
Kinference or llm-d) and records, for every request, the time to first token
measured at the client and the cached prompt tokens the engine reports.

Standard library only, so it runs on a stock python image. Every setting is an
environment variable; run.sh sets them through loadgen-job.yaml.

Workloads (WORKLOAD):
  shared-prefix     long system prompts, each visited several times
  multi-turn        conversations that grow turn by turn
  control           the same sizes, every prompt unique
  pressure          shared-prefix with more prefixes than the fleet can hold
  burst             every new prefix arrives as several requests at once
  mixed             short requests next to long prompts with long answers
  rate-sweep        open loop: arrivals at rising rates over warm prefixes
  replica-restart   steady traffic while run.sh deletes one replica
  router-restart    steady traffic while run.sh deletes the router
  overhead          one tiny request through the front door and one straight
                    to the engines, in turns

Output is one JSON object per line on stdout:
  {"type": "meta", ...}      the settings and the calibrated prompt sizes
  {"type": "pods", ...}      per-replica engine counters, before and after
  {"type": "plan", ...}      what the workload is going to send
  {"type": "request", ...}   one line per request
  {"type": "burst", ...}     burst: the replicas that served one burst
  {"type": "stage", ...}     rate-sweep: one arrival rate
  {"type": "mark", ...}      restarts: "disrupt" tells run.sh to act now
  {"type": "replicas", ...}  restarts: the ready replicas, on every change
  {"type": "summary", ...}   percentiles, cache share and per-replica deltas
"""

import http.client
import json
import math
import os
import queue
import random
import re
import socket
import sys
import threading
import time
from urllib.parse import urlparse


def env(name, default, cast=str):
    raw = os.environ.get(name, "")
    return cast(raw) if raw != "" else default


BASE_URL = env("BASE_URL", "http://vllm:8000")  # the front door under test
ENGINE_URL = env("ENGINE_URL", BASE_URL)  # straight to the engines, for calibration
PODS_HOST = env("PODS_HOST", "")  # headless Service resolving to every replica
PODS_PORT = env("PODS_PORT", 8000, int)
PODS_METRICS_PATH = env("PODS_METRICS_PATH", "/metrics")
POD_URLS = env("POD_URLS", "")  # or explicit replica URLs, comma separated
ROUTER_METRICS_URL = env("ROUTER_METRICS_URL", "")  # optional, scraped after the run
MODEL = env("MODEL", "Qwen/Qwen2.5-7B-Instruct")
STACK = env("STACK", "service")
WORKLOAD = env("WORKLOAD", "shared-prefix")  # one of WORKLOADS, near the end of this file
SEED = env("SEED", 1, int)
CONCURRENCY = env("CONCURRENCY", 6, int)
TIMEOUT_S = env("TIMEOUT_S", 300, int)
MAX_TOKENS = env("MAX_TOKENS", 48, int)
ALLOW_DEGRADED = env("ALLOW_DEGRADED", "", str) == "1"  # measure even if the router cannot tokenize

# shared-prefix and control: one long system prompt plus a short question.
PREFIX_TOKENS = env("PREFIX_TOKENS", 8000, int)
QUESTION_TOKENS = env("QUESTION_TOKENS", 60, int)
VISITS = env("VISITS", 6, int)  # requests per prefix
# 0 sizes the prefix set from the engines' KV cache: PRESSURE times the tokens
# one replica can hold, so that no single replica can keep every prefix warm.
PREFIX_COUNT = env("PREFIX_COUNT", 0, int)
PRESSURE = env("PRESSURE", 1.8, float)
PREFIX_COUNT_MIN = env("PREFIX_COUNT_MIN", 9, int)
PREFIX_COUNT_MAX = env("PREFIX_COUNT_MAX", 60, int)
CONTROL_REQUESTS = env("CONTROL_REQUESTS", 0, int)  # 0: as many as shared-prefix
# Tokens that one replica's KV cache holds. 0 reads it from the engines' metrics;
# set it for a fleet whose engines do not publish vLLM's cache info.
CAPACITY_TOKENS = env("CAPACITY_TOKENS", 0, int)

# pressure: shared-prefix with this many times the prefixes and the concurrency.
PRESSURE_FACTOR = env("PRESSURE_FACTOR", 2, int)

# burst: every new prefix arrives as BURST_SIZE requests at the same moment.
BURST_PREFIXES = env("BURST_PREFIXES", 24, int)
BURST_SIZE = env("BURST_SIZE", 6, int)
BURST_PAUSE_S = env("BURST_PAUSE_S", 1.0, float)

# mixed: workers that keep sending long unique prompts with long answers, next
# to workers that send short prompts. The short ones are what is measured.
LIGHT_REQUESTS = env("LIGHT_REQUESTS", 240, int)
LIGHT_TOKENS = env("LIGHT_TOKENS", 200, int)
LIGHT_MAX_TOKENS = env("LIGHT_MAX_TOKENS", 16, int)
LIGHT_CONCURRENCY = env("LIGHT_CONCURRENCY", 3, int)
HEAVY_CONCURRENCY = env("HEAVY_CONCURRENCY", 3, int)
HEAVY_MAX_TOKENS = env("HEAVY_MAX_TOKENS", 256, int)

# rate-sweep: requests per second, one stage per rate.
SWEEP_RATES = env("SWEEP_RATES", "1,2,3,4,6")
SWEEP_STAGE_S = env("SWEEP_STAGE_S", 45, int)
SWEEP_MAX_IN_FLIGHT = env("SWEEP_MAX_IN_FLIGHT", 96, int)  # arrivals beyond it are dropped and counted

# replica-restart and router-restart: seconds of steady traffic, and when in
# them run.sh is told to delete the pod. A replica takes minutes to load the
# model again, so its workload runs longer than the router's.
DISRUPT_DURATION_S = env("DISRUPT_DURATION_S", 240, int)
REPLICA_DURATION_S = env("REPLICA_DURATION_S", 360, int)
DISRUPT_AT_S = env("DISRUPT_AT_S", 45, int)
WINDOW_S = env("WINDOW_S", 15, int)

# overhead: pairs of tiny requests. DIRECT_URL=none measures the front door only.
OVERHEAD_PAIRS = env("OVERHEAD_PAIRS", 300, int)
DIRECT_URL = env("DIRECT_URL", ENGINE_URL)
if DIRECT_URL.lower() == "none":
    DIRECT_URL = ""

# multi-turn: conversations that grow by one user and one assistant message.
CONVERSATIONS = env("CONVERSATIONS", 36, int)
TURNS = env("TURNS", 8, int)
FIRST_TURN_TOKENS = env("FIRST_TURN_TOKENS", 3000, int)
TURN_TOKENS = env("TURN_TOKENS", 250, int)
THINK_S = env("THINK_S", 1.0, float)

SYLLABLES = (
    "ba be bi bo bu da de di do du fa fe fi fo fu ga ge gi go gu ka ke ki ko ku "
    "la le li lo lu ma me mi mo mu na ne ni no nu pa pe pi po pu ra re ri ro ru "
    "sa se si so su ta te ti to tu va ve vi vo vu za ze zi zo zu"
).split()

print_lock = threading.Lock()


def emit(obj):
    with print_lock:
        sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
        sys.stdout.flush()


def log(msg):
    with print_lock:
        sys.stderr.write(f"[loadgen] {msg}\n")
        sys.stderr.flush()


def words(rng, n):
    return " ".join(
        "".join(rng.choice(SYLLABLES) for _ in range(rng.randint(2, 3))) for _ in range(n)
    )


# ---------------------------------------------------------------- HTTP


def chat(url, messages, max_tokens, request_id=""):
    """One streaming chat completion on a fresh connection.

    A new connection per request makes a plain Service balance every request;
    with keep-alive, kube-proxy would pin a client to one replica.
    """
    u = urlparse(url)
    body = json.dumps(
        {
            "model": MODEL,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": 0,
            "stream": True,
            "stream_options": {"include_usage": True},
        }
    )
    headers = {"Content-Type": "application/json", "Connection": "close"}
    if request_id:
        headers["x-request-id"] = request_id
    out = {"status": 0, "ttft_ms": None, "total_ms": None, "prompt_tokens": None,
           "cached_tokens": None, "completion_tokens": None, "error": None, "text": ""}
    conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=TIMEOUT_S)
    t0 = time.perf_counter()
    try:
        conn.request("POST", u.path.rstrip("/") + "/v1/chat/completions", body=body, headers=headers)
        resp = conn.getresponse()
        out["status"] = resp.status
        if resp.status != 200:
            out["error"] = resp.read(600).decode("utf-8", "replace")
            return out
        first_event = None
        pieces = []
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except ValueError:
                continue
            if obj.get("error"):
                out["error"] = json.dumps(obj["error"])[:600]
                continue
            usage = obj.get("usage")
            if usage:
                out["prompt_tokens"] = usage.get("prompt_tokens")
                out["completion_tokens"] = usage.get("completion_tokens")
                details = usage.get("prompt_tokens_details") or {}
                out["cached_tokens"] = details.get("cached_tokens")
            for choice in obj.get("choices") or []:
                if first_event is None:
                    first_event = time.perf_counter() - t0
                delta = choice.get("delta") or {}
                piece = delta.get("content") or delta.get("reasoning_content") or delta.get("reasoning") or ""
                if piece:
                    if out["ttft_ms"] is None:
                        out["ttft_ms"] = round((time.perf_counter() - t0) * 1000, 1)
                    pieces.append(piece)
        if out["ttft_ms"] is None and first_event is not None:
            out["ttft_ms"] = round(first_event * 1000, 1)
        out["text"] = "".join(pieces)
        if out["ttft_ms"] is None and out["error"] is None:
            out["error"] = "stream ended without a token"
    except Exception as exc:  # timeouts, resets, refused connections
        out["error"] = f"{type(exc).__name__}: {exc}"[:600]
    finally:
        out["total_ms"] = round((time.perf_counter() - t0) * 1000, 1)
        conn.close()
    return out


def http_get(url, timeout=10):
    u = urlparse(url)
    conn = http.client.HTTPConnection(u.hostname, u.port or 80, timeout=timeout)
    try:
        conn.request("GET", u.path or "/", headers={"Connection": "close"})
        resp = conn.getresponse()
        return resp.status, resp.read().decode("utf-8", "replace")
    finally:
        conn.close()


# ------------------------------------------------------------- metrics

SERIES = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+(\S+)")
WANTED = ("prefix_cache_queries", "prefix_cache_hits", "request_success", "prompt_tokens_total",
          "num_requests_running", "num_requests_waiting", "cache_usage_perc")


def parse_metrics(text, prefixes):
    sums, info = {}, {}
    for line in text.splitlines():
        if not line or line[0] == "#":
            continue
        m = SERIES.match(line)
        if not m:
            continue
        name, labels, value = m.group(1), m.group(2) or "", m.group(3)
        if not name.startswith(prefixes) or name.endswith(("_bucket", "_created")):
            continue
        if "cache_config_info" in name:
            for key in ("num_gpu_blocks", "block_size"):
                found = re.search(key + r'="([^"]+)"', labels)
                if found:
                    info[key] = found.group(1)
            continue
        try:
            number = float(value)
        except ValueError:
            continue
        if math.isfinite(number):
            sums[name] = sums.get(name, 0.0) + number
    return sums, info


def replica_urls():
    if POD_URLS:
        return [u.strip().rstrip("/") for u in POD_URLS.split(",") if u.strip()]
    if not PODS_HOST:
        return []
    try:
        infos = socket.getaddrinfo(PODS_HOST, PODS_PORT, type=socket.SOCK_STREAM)
    except OSError as exc:
        log(f"cannot resolve {PODS_HOST}: {exc}")
        return []
    return [f"http://{ip}:{PODS_PORT}" for ip in sorted({i[4][0] for i in infos})]


ENGINE_PREFIXES = ("vllm:", "vllm_", "sglang:", "sglang_")


def scrape_pods(when):
    pods = []
    for url in replica_urls():
        entry = {"pod": url, "metrics": {}, "info": {}}
        try:
            status, text = http_get(url + PODS_METRICS_PATH)
            if status == 200:
                sums, info = parse_metrics(text, ENGINE_PREFIXES)
                entry["metrics"] = {k: v for k, v in sums.items() if any(w in k for w in WANTED)}
                entry["info"] = info
            else:
                entry["error"] = f"HTTP {status}"
        except Exception as exc:
            entry["error"] = f"{type(exc).__name__}: {exc}"
        pods.append(entry)
    emit({"type": "pods", "when": when, "pods": pods})
    return pods


ROUTER_PREFIXES = ("kinference", "inference_", "llm_d", "llmd")


def router_counters():
    """The router's own counters, summed by name. None when there are none."""
    if not ROUTER_METRICS_URL:
        return None
    try:
        status, text = http_get(ROUTER_METRICS_URL)
        if status != 200:
            return None
        sums, _ = parse_metrics(text, ROUTER_PREFIXES)
        return sums
    except Exception as exc:
        log(f"router metrics: {exc}")
        return None


def cache_capacity_tokens(pods):
    sizes = []
    for pod in pods:
        try:
            sizes.append(int(pod["info"]["num_gpu_blocks"]) * int(pod["info"].get("block_size", 16)))
        except (KeyError, ValueError):
            pass
    return min(sizes) if sizes else None


def metric(pod, needle):
    return sum(v for k, v in pod.get("metrics", {}).items() if needle in k)


def finished_per_replica():
    """Requests that each replica has finished so far, by replica URL."""
    counts = {}
    for url in replica_urls():
        try:
            status, text = http_get(url + PODS_METRICS_PATH)
            if status == 200:
                sums, _ = parse_metrics(text, ENGINE_PREFIXES)
                counts[url] = sum(v for k, v in sums.items() if "request_success" in k)
        except Exception:  # a replica that is restarting
            pass
    return counts


# --------------------------------------------------------- calibration


def calibrate():
    """Tokens per generated word and the fixed chat-template overhead."""
    rng = random.Random(SEED * 7919 + 13)
    points = []
    for n in (400, 2000):
        res = chat(ENGINE_URL, [{"role": "system", "content": "Calibration " + words(rng, n)},
                                {"role": "user", "content": "ok"}], 1)
        if res["status"] != 200 or not res["prompt_tokens"]:
            raise RuntimeError(f"calibration request failed: HTTP {res['status']} {res['error']}")
        points.append((n, res["prompt_tokens"]))
    (n1, t1), (n2, t2) = points
    slope = (t2 - t1) / (n2 - n1)
    return slope, t1 - slope * n1


class Sizer:
    def __init__(self, slope, intercept):
        self.slope, self.intercept = slope, intercept

    def word_count(self, tokens, with_overhead=True):
        budget = tokens - (self.intercept if with_overhead else 0)
        return max(4, int(round(budget / self.slope)))


# ----------------------------------------------------------- workloads


def record(base, res, **extra):
    row = {"type": "request", "stack": STACK, "workload": WORKLOAD}
    row.update(base)
    row.update({k: res[k] for k in ("status", "ttft_ms", "total_ms", "prompt_tokens",
                                    "cached_tokens", "completion_tokens", "error")})
    row.update(extra)
    emit(row)
    return row


def run_pool(tasks, worker_fn, concurrency=None):
    """Closed loop: CONCURRENCY workers take tasks in order."""
    todo = queue.Queue()
    for task in tasks:
        todo.put(task)
    rows, rows_lock = [], threading.Lock()

    def loop():
        while True:
            try:
                task = todo.get_nowait()
            except queue.Empty:
                return
            for row in worker_fn(task):
                with rows_lock:
                    rows.append(row)

    threads = [threading.Thread(target=loop, daemon=True) for _ in range(concurrency or CONCURRENCY)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    return rows


def prefix_count(capacity):
    """Shared prefixes that together hold PRESSURE times one replica's KV cache."""
    if PREFIX_COUNT:
        return PREFIX_COUNT
    if not capacity:
        return 24
    return max(PREFIX_COUNT_MIN, min(PREFIX_COUNT_MAX, math.ceil(PRESSURE * capacity / PREFIX_TOKENS)))


def succeeded(row):
    return row["status"] == 200 and not row["error"] and row["ttft_ms"] is not None


def cached_share(rows):
    prompt = sum(r["prompt_tokens"] or 0 for r in rows)
    return round(sum(r["cached_tokens"] or 0 for r in rows) / prompt, 4) if prompt else None


# What a workload adds to the summary line, by key.
EXTRA = {}


def shared_prefix(sizer, capacity, t_zero, factor=1, concurrency=None):
    rng = random.Random(SEED)
    count = prefix_count(capacity) * factor
    n_words = sizer.word_count(PREFIX_TOKENS - QUESTION_TOKENS)
    prefixes = [f"Document {SEED}-{p}. " + words(rng, n_words) for p in range(count)]
    q_words = sizer.word_count(QUESTION_TOKENS, with_overhead=False)
    tasks, i = [], 0
    for visit in range(VISITS):
        order = list(range(count))
        rng.shuffle(order)
        for p in order:
            tasks.append({"i": i, "group": p, "visit": visit,
                          "question": f"Question {SEED}-{i}: " + words(rng, q_words)})
            i += 1
    emit({"type": "plan", "prefix_count": count, "visits": VISITS, "requests": len(tasks),
          "prefix_tokens": PREFIX_TOKENS, "cache_capacity_tokens": capacity,
          "concurrency": concurrency or CONCURRENCY})

    def one(task):
        res = chat(BASE_URL, [{"role": "system", "content": prefixes[task["group"]]},
                              {"role": "user", "content": task["question"]}], MAX_TOKENS,
                   f"{STACK}-{WORKLOAD}-{task['i']}")
        yield record({"i": task["i"], "group": task["group"], "turn": task["visit"],
                      "eligible": task["visit"] > 0,
                      "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res)

    return run_pool(tasks, one, concurrency)


def pressure(sizer, capacity, t_zero):
    """shared-prefix with more prefixes than the fleet can hold, and more requests in flight."""
    return shared_prefix(sizer, capacity, t_zero, PRESSURE_FACTOR, CONCURRENCY * PRESSURE_FACTOR)


def control(sizer, capacity, t_zero):
    rng = random.Random(SEED + 1000)
    total = CONTROL_REQUESTS
    if total == 0:
        total = prefix_count(capacity) * VISITS
    n_words = sizer.word_count(PREFIX_TOKENS - QUESTION_TOKENS)
    q_words = sizer.word_count(QUESTION_TOKENS, with_overhead=False)
    emit({"type": "plan", "requests": total, "prefix_tokens": PREFIX_TOKENS,
          "cache_capacity_tokens": capacity})

    def one(i):
        local = random.Random(SEED * 100003 + i)
        res = chat(BASE_URL, [{"role": "system", "content": f"Document {SEED}-u{i}. " + words(local, n_words)},
                              {"role": "user", "content": f"Question {SEED}-{i}: " + words(local, q_words)}],
                   MAX_TOKENS, f"{STACK}-{WORKLOAD}-{i}")
        yield record({"i": i, "group": i, "turn": 0, "eligible": True,
                      "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res)

    return run_pool(list(range(total)), one)


def multi_turn(sizer, capacity, t_zero):
    first_words = sizer.word_count(FIRST_TURN_TOKENS)
    turn_words = sizer.word_count(TURN_TOKENS, with_overhead=False)
    emit({"type": "plan", "conversations": CONVERSATIONS, "turns": TURNS,
          "requests": CONVERSATIONS * TURNS, "cache_capacity_tokens": capacity})

    def one(c):
        local = random.Random(SEED * 99991 + c)
        messages = [{"role": "system", "content": f"Conversation {SEED}-{c}. " + words(local, first_words)}]
        for turn in range(TURNS):
            messages.append({"role": "user", "content": f"Turn {turn}: " + words(local, turn_words)})
            res = chat(BASE_URL, messages, MAX_TOKENS, f"{STACK}-{WORKLOAD}-{c}-{turn}")
            yield record({"i": c * TURNS + turn, "group": c, "turn": turn, "eligible": turn > 0,
                          "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res)
            if res["status"] != 200 or res["error"]:
                return
            messages.append({"role": "assistant", "content": res["text"] or "ok"})
            time.sleep(local.uniform(0.5, 1.5) * THINK_S)

    return run_pool(list(range(CONVERSATIONS)), one)


def burst(sizer, capacity, t_zero):
    """Every new prefix arrives as BURST_SIZE requests at once, then gets one more visit.

    The engines' counters are read after each burst, which shows how many
    replicas served it and so how many copies of the prefix the fleet now holds.
    """
    rng = random.Random(SEED * 31337 + 5)
    n_words = sizer.word_count(PREFIX_TOKENS - QUESTION_TOKENS)
    q_words = sizer.word_count(QUESTION_TOKENS, with_overhead=False)
    prefixes = [f"Burst document {SEED}-{p}. " + words(rng, n_words) for p in range(BURST_PREFIXES)]
    questions = [[f"Question {SEED}-{p}-{k}: " + words(rng, q_words) for k in range(BURST_SIZE + 1)]
                 for p in range(BURST_PREFIXES)]
    emit({"type": "plan", "prefix_count": BURST_PREFIXES, "burst_size": BURST_SIZE,
          "requests": BURST_PREFIXES * (BURST_SIZE + 1), "prefix_tokens": PREFIX_TOKENS,
          "cache_capacity_tokens": capacity})

    def ask(p, k, phase):
        res = chat(BASE_URL, [{"role": "system", "content": prefixes[p]},
                              {"role": "user", "content": questions[p][k]}], MAX_TOKENS,
                   f"{STACK}-{WORKLOAD}-{p}-{k}")
        return record({"i": p * (BURST_SIZE + 1) + k, "group": p, "turn": k, "phase": phase,
                       "eligible": phase == "follow-up",
                       "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res)

    rows, used, walls = [], [], []
    before = finished_per_replica()
    for p in range(BURST_PREFIXES):
        gate = threading.Barrier(BURST_SIZE)
        got = [None] * BURST_SIZE

        def fire(k, p=p, gate=gate, got=got):
            gate.wait()
            got[k] = ask(p, k, "burst")

        threads = [threading.Thread(target=fire, args=(k,), daemon=True) for k in range(BURST_SIZE)]
        started = time.perf_counter()
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        wall_ms = round((time.perf_counter() - started) * 1000, 1)
        time.sleep(0.5)  # let the engines publish the requests they just finished
        after = finished_per_replica()
        per_replica = [round(after[url] - before.get(url, 0)) for url in sorted(after)]
        replicas = sum(1 for n in per_replica if n > 0) if per_replica else None
        emit({"type": "burst", "group": p, "wall_ms": wall_ms, "requests_per_replica": per_replica,
              "replicas_used": replicas})
        rows.extend(got)
        walls.append(wall_ms)
        if replicas:
            used.append(replicas)
        before = after
        time.sleep(BURST_PAUSE_S)

    order = list(range(BURST_PREFIXES))
    rng.shuffle(order)
    rows.extend(run_pool(order, lambda p: [ask(p, BURST_SIZE, "follow-up")]))
    EXTRA["burst"] = {"bursts": BURST_PREFIXES, "size": BURST_SIZE,
                      "replicas_used_mean": round(sum(used) / len(used), 2) if used else None,
                      "replicas_used_max": max(used) if used else None,
                      "wall_ms_mean": round(sum(walls) / len(walls), 1) if walls else None}
    return rows


def mixed(sizer, capacity, t_zero):
    """Short requests next to long ones.

    HEAVY_CONCURRENCY workers keep sending long unique prompts with long
    answers. LIGHT_CONCURRENCY workers send LIGHT_REQUESTS short prompts, and
    the short ones are the eligible requests.
    """
    heavy_words = sizer.word_count(PREFIX_TOKENS)
    light_words = sizer.word_count(LIGHT_TOKENS)
    emit({"type": "plan", "light_requests": LIGHT_REQUESTS, "light_tokens": LIGHT_TOKENS,
          "heavy_tokens": PREFIX_TOKENS, "heavy_max_tokens": HEAVY_MAX_TOKENS,
          "light_concurrency": LIGHT_CONCURRENCY, "heavy_concurrency": HEAVY_CONCURRENCY,
          "cache_capacity_tokens": capacity})
    rows, rows_lock = [], threading.Lock()
    stop = threading.Event()
    todo = queue.Queue()
    for i in range(LIGHT_REQUESTS):
        todo.put(i)

    def keep(row):
        with rows_lock:
            rows.append(row)
        return row

    def heavy(worker):
        local = random.Random(SEED * 7907 + worker)
        n = 0
        while not stop.is_set():
            res = chat(BASE_URL, [{"role": "user",
                                   "content": f"Report {SEED}-{worker}-{n}. " + words(local, heavy_words)}],
                       HEAVY_MAX_TOKENS, f"{STACK}-{WORKLOAD}-heavy-{worker}-{n}")
            row = keep(record({"i": LIGHT_REQUESTS + worker * 100000 + n, "group": worker, "turn": n,
                               "kind": "heavy", "eligible": False,
                               "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res))
            n += 1
            if not succeeded(row):
                stop.wait(0.5)  # a refused connection returns at once

    def light():
        while True:
            try:
                i = todo.get_nowait()
            except queue.Empty:
                return
            local = random.Random(SEED * 104729 + i)
            time.sleep(local.uniform(0.1, 0.5))
            res = chat(BASE_URL, [{"role": "user", "content": f"Note {SEED}-{i}. " + words(local, light_words)}],
                       LIGHT_MAX_TOKENS, f"{STACK}-{WORKLOAD}-light-{i}")
            keep(record({"i": i, "group": i, "turn": 0, "kind": "light", "eligible": True,
                         "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res))

    heavies = [threading.Thread(target=heavy, args=(w,), daemon=True) for w in range(HEAVY_CONCURRENCY)]
    for thread in heavies:
        thread.start()
    time.sleep(2.0)  # the first short request should already meet long ones
    lights = [threading.Thread(target=light, daemon=True) for _ in range(LIGHT_CONCURRENCY)]
    for thread in lights:
        thread.start()
    for thread in lights:
        thread.join()
    stop.set()
    for thread in heavies:
        thread.join()
    EXTRA["mixed"] = {"light": sum(1 for r in rows if r["kind"] == "light"),
                      "heavy": sum(1 for r in rows if r["kind"] == "heavy")}
    return rows


def rate_sweep(sizer, capacity, t_zero):
    """Open loop over warm prefixes: requests arrive at a fixed rate per stage,
    whether or not the earlier ones have finished."""
    rng = random.Random(SEED * 50021 + 3)
    count = prefix_count(capacity)
    n_words = sizer.word_count(PREFIX_TOKENS - QUESTION_TOKENS)
    q_words = sizer.word_count(QUESTION_TOKENS, with_overhead=False)
    prefixes = [f"Sweep document {SEED}-{p}. " + words(rng, n_words) for p in range(count)]
    rates = [float(r) for r in SWEEP_RATES.split(",") if r.strip()]
    emit({"type": "plan", "prefix_count": count, "rates_per_s": rates, "stage_s": SWEEP_STAGE_S,
          "prefix_tokens": PREFIX_TOKENS, "cache_capacity_tokens": capacity})
    rows, lock, counter = [], threading.Lock(), [0]

    def ask(p, stage, rate):
        with lock:
            i = counter[0]
            counter[0] += 1
        local = random.Random(SEED * 611953 + i)
        res = chat(BASE_URL, [{"role": "system", "content": prefixes[p]},
                              {"role": "user", "content": f"Question {SEED}-{i}: " + words(local, q_words)}],
                   MAX_TOKENS, f"{STACK}-{WORKLOAD}-{i}")
        row = record({"i": i, "group": p, "turn": stage, "stage": stage, "rate": rate, "eligible": stage >= 0,
                      "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res)
        with lock:
            rows.append(row)
        return row

    run_pool(list(range(count)), lambda p: [ask(p, -1, 0)])  # warm every prefix once

    stages = []
    for stage, rate in enumerate(rates):
        local = random.Random(SEED * 15485863 + stage)
        in_flight, threads, done, shed = [0], [], [], 0

        def one(p, stage=stage, rate=rate, in_flight=in_flight, done=done):
            try:
                row = ask(p, stage, rate)
                with lock:
                    done.append(row)
            finally:
                with lock:
                    in_flight[0] -= 1

        started = time.perf_counter()
        at = local.expovariate(rate)
        while at < SWEEP_STAGE_S:
            delay = started + at - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            p = local.randrange(count)
            with lock:
                room = in_flight[0] < SWEEP_MAX_IN_FLIGHT
                if room:
                    in_flight[0] += 1
            if room:
                thread = threading.Thread(target=one, args=(p,), daemon=True)
                thread.start()
                threads.append(thread)
            else:
                shed += 1
            at += local.expovariate(rate)
        for thread in threads:
            thread.join()
        drained = time.perf_counter() - started
        ok = [r for r in done if succeeded(r)]
        ttft = [r["ttft_ms"] for r in ok]
        entry = {"stage": stage, "rate_per_s": rate, "sent": len(threads), "ok": len(ok),
                 "errors": len(done) - len(ok), "shed": shed,
                 "ttft_ms": {"p50": percentile(ttft, 0.5), "p95": percentile(ttft, 0.95),
                             "p99": percentile(ttft, 0.99)},
                 "total_ms_p50": percentile([r["total_ms"] for r in ok], 0.5),
                 "cached_share": cached_share(ok), "drained_s": round(drained, 1),
                 "achieved_per_s": round(len(ok) / drained, 2) if drained else None}
        emit(dict(entry, type="stage"))
        stages.append(entry)
    EXTRA["stages"] = stages
    return rows


def disruption(sizer, capacity, t_zero):
    """Steady traffic over warm prefixes while run.sh restarts a replica or the router.

    The line {"type": "mark", "name": "disrupt"} tells run.sh to act. t_rel
    counts seconds from the start of the steady traffic.
    """
    rng = random.Random(SEED * 70001 + 9)
    duration = REPLICA_DURATION_S if WORKLOAD == "replica-restart" else DISRUPT_DURATION_S
    count = prefix_count(capacity)
    n_words = sizer.word_count(PREFIX_TOKENS - QUESTION_TOKENS)
    q_words = sizer.word_count(QUESTION_TOKENS, with_overhead=False)
    prefixes = [f"Steady document {SEED}-{p}. " + words(rng, n_words) for p in range(count)]
    emit({"type": "plan", "prefix_count": count, "duration_s": duration, "disrupt_at_s": DISRUPT_AT_S,
          "prefix_tokens": PREFIX_TOKENS, "cache_capacity_tokens": capacity})
    rows, lock, counter, steady_zero = [], threading.Lock(), [0], [None]

    def ask(p):
        with lock:
            i = counter[0]
            counter[0] += 1
        local = random.Random(SEED * 472882027 + i)
        began = time.perf_counter()
        base = {"i": i, "group": p, "turn": 0, "eligible": steady_zero[0] is not None,
                "t_start": round(began - t_zero, 3)}
        if steady_zero[0] is not None:
            base["t_rel"] = round(began - steady_zero[0], 3)
        res = chat(BASE_URL, [{"role": "system", "content": prefixes[p]},
                              {"role": "user", "content": f"Question {SEED}-{i}: " + words(local, q_words)}],
                   MAX_TOKENS, f"{STACK}-{WORKLOAD}-{i}")
        row = record(base, res)
        with lock:
            rows.append(row)
        return row

    run_pool(list(range(count)), lambda p: [ask(p)])  # warm every prefix once
    steady_zero[0] = time.perf_counter()
    emit({"type": "mark", "name": "steady"})
    stop = threading.Event()
    changes = []

    def loop(worker):
        local = random.Random(SEED * 1299709 + worker)
        while not stop.is_set():
            if not succeeded(ask(local.randrange(count))):
                stop.wait(0.5)  # a refused connection returns at once

    def watch():
        last = None
        while not stop.is_set():
            ready = len(replica_urls())
            if ready != last:
                change = {"t_rel": round(time.perf_counter() - steady_zero[0], 1), "ready": ready}
                emit(dict(change, type="replicas"))
                changes.append(change)
                last = ready
            stop.wait(2)

    threads = [threading.Thread(target=loop, args=(w,), daemon=True) for w in range(CONCURRENCY)]
    threads.append(threading.Thread(target=watch, daemon=True))
    for thread in threads:
        thread.start()
    time.sleep(DISRUPT_AT_S)
    emit({"type": "mark", "name": "disrupt", "t_rel": round(time.perf_counter() - steady_zero[0], 1)})
    time.sleep(max(0, duration - DISRUPT_AT_S))
    stop.set()
    for thread in threads:
        thread.join()

    steady = [r for r in rows if "t_rel" in r]
    windows = []
    for start in range(0, duration, WINDOW_S):
        part = [r for r in steady if start <= r["t_rel"] < start + WINDOW_S]
        ok = [r for r in part if succeeded(r)]
        windows.append({"from_s": start, "requests": len(part), "errors": len(part) - len(ok),
                        "ttft_p50": percentile([r["ttft_ms"] for r in ok], 0.5),
                        "ttft_p95": percentile([r["ttft_ms"] for r in ok], 0.95),
                        "cached_share": cached_share(ok)})
    failed = [r["t_rel"] for r in steady if not succeeded(r)]
    before = [r for r in steady if succeeded(r) and r["t_rel"] < DISRUPT_AT_S]
    late = [r for r in steady if succeeded(r) and r["t_rel"] >= duration - 60]
    EXTRA["disruption"] = {
        "at_s": DISRUPT_AT_S, "duration_s": duration,
        "requests": len(steady), "errors": len(failed),
        "first_error_s": min(failed) if failed else None, "last_error_s": max(failed) if failed else None,
        "ttft_p50_before": percentile([r["ttft_ms"] for r in before], 0.5),
        "ttft_p95_before": percentile([r["ttft_ms"] for r in before], 0.95),
        "ttft_p50_last_minute": percentile([r["ttft_ms"] for r in late], 0.5),
        "ttft_p95_last_minute": percentile([r["ttft_ms"] for r in late], 0.95),
        "cached_share_before": cached_share(before), "cached_share_last_minute": cached_share(late),
        "replicas": changes, "windows": windows}
    return rows


def overhead(sizer, capacity, t_zero):
    """What the front door adds: one tiny request through it and one straight
    to the engines, in turns, one request at a time."""
    doors = [("front", BASE_URL)] + ([("direct", DIRECT_URL)] if DIRECT_URL else [])
    emit({"type": "plan", "pairs": OVERHEAD_PAIRS, "requests": OVERHEAD_PAIRS * len(doors),
          "direct_url": DIRECT_URL or None})
    rows, added, by_kind = [], [], {"front": [], "direct": []}
    for i in range(OVERHEAD_PAIRS):
        local = random.Random(SEED * 86028121 + i)
        pair = {}
        for kind, url in (doors if i % 2 == 0 else doors[::-1]):
            res = chat(url, [{"role": "user", "content": f"Ping {SEED}-{i}-{kind}: " + words(local, 12)}], 1,
                       f"{STACK}-{WORKLOAD}-{kind}-{i}")
            row = record({"i": i, "group": i, "turn": 0, "kind": kind, "eligible": kind == "front",
                          "t_start": round(time.perf_counter() - t_zero - res["total_ms"] / 1000, 3)}, res)
            rows.append(row)
            if succeeded(row):
                pair[kind] = row["ttft_ms"]
                by_kind[kind].append(row["ttft_ms"])
        if len(pair) == 2:
            added.append(pair["front"] - pair["direct"])
    EXTRA["overhead"] = {"pairs": len(added),
                         "front_ttft_p50": percentile(by_kind["front"], 0.5),
                         "front_ttft_p95": percentile(by_kind["front"], 0.95),
                         "direct_ttft_p50": percentile(by_kind["direct"], 0.5),
                         "added_ms_p50": percentile(added, 0.5), "added_ms_p95": percentile(added, 0.95)}
    return rows


WORKLOADS = {"shared-prefix": shared_prefix, "multi-turn": multi_turn, "control": control,
             "pressure": pressure, "burst": burst, "mixed": mixed, "rate-sweep": rate_sweep,
             "replica-restart": disruption, "router-restart": disruption, "overhead": overhead}


# -------------------------------------------------------------- report


def percentile(values, q):
    if not values:
        return None
    ordered = sorted(values)
    pos = (len(ordered) - 1) * q
    lo, hi = math.floor(pos), math.ceil(pos)
    return round(ordered[lo] + (ordered[hi] - ordered[lo]) * (pos - lo), 1)


def stats(rows):
    ok = [r for r in rows if r["status"] == 200 and not r["error"] and r["ttft_ms"] is not None]
    ttft = [r["ttft_ms"] for r in ok]
    prompt = sum(r["prompt_tokens"] or 0 for r in ok)
    cached = sum(r["cached_tokens"] or 0 for r in ok)
    reported = sum(1 for r in ok if r["cached_tokens"] is not None)
    total = [r["total_ms"] for r in ok if r["total_ms"] is not None]
    # Time per output token after the first one.
    per_token = [(r["total_ms"] - r["ttft_ms"]) / (r["completion_tokens"] - 1)
                 for r in ok if (r["completion_tokens"] or 0) > 1 and r["total_ms"] is not None]
    return {
        "requests": len(rows),
        "ok": len(ok),
        "ttft_ms": {"p50": percentile(ttft, 0.5), "p90": percentile(ttft, 0.9),
                    "p95": percentile(ttft, 0.95), "p99": percentile(ttft, 0.99),
                    "mean": round(sum(ttft) / len(ttft), 1) if ttft else None,
                    "min": min(ttft) if ttft else None, "max": max(ttft) if ttft else None},
        "total_ms": {"p50": percentile(total, 0.5), "p95": percentile(total, 0.95)},
        "tpot_ms": {"p50": percentile(per_token, 0.5), "p95": percentile(per_token, 0.95)},
        "prompt_tokens": prompt,
        "cached_tokens": cached,
        "completion_tokens": sum(r["completion_tokens"] or 0 for r in ok),
        "cached_share": round(cached / prompt, 4) if prompt else None,
        "cached_tokens_reported": reported,
    }


def main():
    emit({"type": "meta", "stack": STACK, "workload": WORKLOAD, "base_url": BASE_URL, "model": MODEL,
          "seed": SEED, "concurrency": CONCURRENCY, "max_tokens": MAX_TOKENS,
          "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})

    if WORKLOAD not in WORKLOADS:
        emit({"type": "fatal", "error": f"unknown workload {WORKLOAD}: one of {', '.join(WORKLOADS)}"})
        return 2

    router_before = router_counters()
    probe = chat(BASE_URL, [{"role": "user", "content": f"Probe {SEED} {time.time_ns()}: say ok."}], 4)
    if probe["status"] != 200 or probe["error"]:
        log(f"{BASE_URL} does not answer chat completions: HTTP {probe['status']} {probe['error']}")
        emit({"type": "fatal", "error": f"probe failed: HTTP {probe['status']} {probe['error']}"})
        return 2

    # Kinference answers even when it cannot tokenize a prompt: it then picks on
    # load alone and counts the pick as degraded. Numbers from such a run say
    # nothing about cache-aware routing, so stop instead of measuring them.
    router_start = router_counters()
    if router_before is not None and router_start is not None and not ALLOW_DEGRADED:
        key = "kinference_score_degraded_total"
        if router_start.get(key, 0) > router_before.get(key, 0):
            message = ("the router picked on load alone for the probe request (" + key + " went up): "
                       "it cannot tokenize prompts, so cache-aware routing is off. On vLLM 0.31 the "
                       "render endpoint it uses needs --enable-scale-out on the engines.")
            log(message)
            emit({"type": "fatal", "error": message})
            return 3

    slope, intercept = calibrate()
    sizer = Sizer(slope, intercept)
    emit({"type": "calibration", "tokens_per_word": round(slope, 4), "overhead_tokens": round(intercept, 1)})

    before = scrape_pods("before")
    capacity = CAPACITY_TOKENS or cache_capacity_tokens(before)
    t_zero = time.perf_counter()
    rows = WORKLOADS[WORKLOAD](sizer, capacity, t_zero)
    elapsed = time.perf_counter() - t_zero
    time.sleep(3)  # let the engines publish their last counters
    after = scrape_pods("after")

    pods = []
    by_url = {p["pod"]: p for p in before}
    for pod in after:
        prev = by_url.get(pod["pod"], {})
        served = metric(pod, "request_success") - metric(prev, "request_success")
        queries = metric(pod, "prefix_cache_queries") - metric(prev, "prefix_cache_queries")
        hits = metric(pod, "prefix_cache_hits") - metric(prev, "prefix_cache_hits")
        pods.append({"pod": pod["pod"], "requests": round(served), "prefix_queries_tokens": round(queries),
                     "prefix_hits_tokens": round(hits),
                     "prefix_hit_rate": round(hits / queries, 4) if queries else None})

    router = router_counters()
    router_delta = None
    if router is not None and router_start is not None:
        router_delta = {name: round(router.get(name, 0) - router_start.get(name, 0), 3)
                        for name in ("kinference_picks_total", "kinference_score_degraded_total",
                                     "kinference_tokenize_total", "kinference_worker_evictions_total")}

    summary = {"type": "summary", "stack": STACK, "workload": WORKLOAD, "elapsed_s": round(elapsed, 1),
               "requests_per_min": round(len(rows) / elapsed * 60, 1) if elapsed else None,
               "errors": sum(1 for r in rows if r["status"] != 200 or r["error"]),
               "all": stats(rows), "eligible": stats([r for r in rows if r["eligible"]]),
               "first_contact": stats([r for r in rows if not r["eligible"]]),
               "pods": pods, "cache_capacity_tokens": capacity}
    summary["output_tokens_per_s"] = round(summary["all"]["completion_tokens"] / elapsed, 1) if elapsed else None
    if router:
        summary["router_metrics"] = router
        summary["router_delta"] = router_delta
    summary.update(EXTRA)
    emit(summary)
    log(f"{STACK}/{WORKLOAD}: {summary['all']['ok']}/{len(rows)} ok, "
        f"p50 TTFT {summary['eligible']['ttft_ms']['p50']} ms, "
        f"cached share {summary['eligible']['cached_share']}")
    return 0 if summary["all"]["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
