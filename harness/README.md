# Harness

What `make quick` and `make benchmark` run.

| Folder | Content |
| --- | --- |
| `scripts/` | `run.sh` installs and measures one stack. `matrix.sh` runs every stack and averages the repetitions. `token-kubeconfig.sh` and `diagnose.sh` help with long runs and failures |
| `application/` | `loadgen.py`, the load generator. It runs in the cluster as a Job |
| `manifests/` | GPU node setup, vLLM replicas, model download, load-generator Job, and each stack's manifests and Helm values |
| `analysis/` | `report.py` averages the runs into tables. `kinference/` has `fit_profile.py`, which fits Kinference's profile, and `compare_profiles.py`, which compares it with the chart's |

## Stacks

| Stack | Routing |
| --- | --- |
| `service` | ClusterIP Service, kube-proxy picks at random |
| `kinference-tuned` | Buoyant Gateway asks Kinference for the replica with the lowest predicted TTFT. Profile fitted to this fleet |
| `kinference` | Same, with the chart's profile |
| `llm-d-baseline` | llm-d router, standalone, quickstart profile: prefix affinity from its own history, then token load |
| `llm-d-precise` | Same router, precise prefix-cache guide: index built from the engines' KV events |
| `llm-d` | Same router, the chart's scorers |
| `production-stack-prefix` | production-stack router, `prefixaware` |
| `production-stack` | Same router, round robin (default) |
| `kthena-tuned` | Kthena router, `prefix-cache` weight 4 |
| `kthena` | Same router, the chart's weights |
| `dynamo-kv-tuned` | Dynamo Frontend, KV routing, `DYN_ROUTER_PREFILL_LOAD_SCALE=8` |
| `dynamo-kv` | Same, default weights |
| `dynamo` | Same Frontend, round robin (default) |

`service` and the `-tuned`, `-baseline`, `-precise` and `-prefix` stacks run every workload. The other stacks run shared-prefix, multi-turn and control. The default stacks and the last four workloads run in the first three of the five repetitions.

Dynamo only routes to its own workers, so its stacks swap the three vLLM pods for three Dynamo vLLM workers with the same model, GPU memory and vLLM version.

## Workloads

| Workload | Requests |
| --- | --- |
| `shared-prefix` | System prompts of about 8,000 tokens, six visits each. Together 1.8x one replica's KV cache |
| `multi-turn` | 36 conversations of eight turns |
| `control` | Same sizes, every prompt unique |
| `pressure` | Twice the prefixes and twice the requests in flight of shared-prefix |
| `burst` | Each new prefix arrives as six requests at once, then gets one more visit |
| `mixed` | Short requests next to long prompts with long answers |
| `rate-sweep` | 1, 2, 3, 4 and 6 requests/s over warm prefixes, 45 s per rate |
| `replica-restart` | Six minutes of steady traffic, one replica deleted after 45 s |
| `router-restart` | Four minutes of steady traffic, router pods deleted after 45 s |
| `overhead` | Tiny requests, alternating between the front door and an engine |

Each workload starts from recreated replicas with empty caches. The load generator opens a new connection per request; with keep-alive, kube-proxy would pin each client to one replica.

## Results

`results/<run>/05-inference-routing/`:

- `summary.md`, `summary.json`: percentiles, cached share, requests per replica
- `<stack>/<workload>.jsonl`: one line per request
- `<stack>/<workload>.top.tsv`: CPU and memory of the stack's pods, every 10 s
- `<stack>/<workload>.*.log`: router logs
- `settings.yaml`, `helm-releases.jsonl`: what ran

`make benchmark` also writes `results/<NAME>/repeats.md` and `repeats.json`: mean, standard deviation and range across repetitions.

## Settings

Environment variables, for example `WORKLOADS="burst mixed" make quick`.

| Variable | Default | |
| --- | --- | --- |
| `MODEL` | `Qwen/Qwen2.5-7B-Instruct` | any ungated model vLLM serves |
| `VLLM_IMAGE` | `vllm/vllm-openai:v0.31.0` | |
| `GPUMEM_MIB` | `28000` | GPU memory per replica |
| `WORKLOADS` | `shared-prefix multi-turn control` | for `run.sh` steps |
| `LOADGEN_ENV` | | extra load generator settings, e.g. `CONCURRENCY=12` |
| `LLMD_VERSION` | `v1.0.0` | llm-d router and guides |
| `LLMD_CHUNK_SIZE` | `2048` | engine prefill batch, for llm-d's calibration |
| `KTHENA_VERSION` | `v1.1.0` | |
| `KTHENA_PREFIX_WEIGHT` | `4` | |
| `DYNAMO_VERSION` | `1.6.2` | |
| `DYNAMO_PREFILL_LOAD_SCALE` | `8` | |
| `PSTACK_VERSION` | `0.1.14` | |
| `GATEWAY_VERSION` | `0.1.0-alpha.6` | |
| `KINFERENCE_VERSION` | `0.1.0-alpha.7` | |

`matrix.sh` has its own settings at the top: repetitions, stacks, workloads.

## Tuning

The engines are the same for every stack: vLLM 0.31.0, 166,576 tokens of KV cache per replica (10,411 blocks of 16), prefill batch 2,048 tokens. Their flags aren't tuned.

| Stack | Setting | Why |
| --- | --- | --- |
| `kinference-tuned` | `kvBlockSize: 16` | Engine block size. One shared-prefix run indexed 21,246 blocks with no degraded picks |
| | `profile-fitted.yaml` | Fitted with `fit_profile.py`. On the published runs its median prediction is 1.02x the observed TTFT, against 7.2x with the chart's profile |
| | tokenize mode `render` | The local tokenizer can't render this model's chat template. Adds about 42 ms to a tiny request |
| `llm-d-baseline`, `llm-d-precise` | `peakPrefillThroughput: 24914` | From llm-d's calibration Job at `CHUNK_SIZE=2048`. The guides' value is for a 32B model on an H100 |
| `llm-d-precise` | `blockSizeTokens: 16` | Engine block size. The guide uses 64 |
| | KV topic `kv@<pod IP>:8000@<model>` in `vllm.yaml` | With a bare `kv@` topic it routed like a random pick: 42% cached instead of 99% |
| `kthena-tuned` | `prefix-cache` weight 4 | 82% cached at weight 1, 98.5% at 2, 99% at 4 |
| `dynamo-kv-tuned` | `DYN_ROUTER_PREFILL_LOAD_SCALE=8` | 58% cached at 1, 94% at 4, 98.5% at 8 with a shorter tail |
| | `DYN_ROUTER_PREDICTED_TTL_SECS=5` | From Dynamo's tuning guidelines, for bursts that share a prefix |
| `production-stack-prefix` | `routingLogic: prefixaware` | Nothing hardware-specific: it hashes the prompt text in 128-character chunks |

To fit Kinference's profile for another model or GPU, and to compare it with the chart's profile on the first three repetitions of `make benchmark`, where both run:

```bash
python3 harness/analysis/kinference/fit_profile.py harness/manifests/profile-fitted.yaml results/<run>/05-inference-routing
python3 harness/analysis/kinference/compare_profiles.py results/compare-r{1,2,3}/05-inference-routing
```

## Caveats

- The replicas share one GPU. HAMi caps memory, not compute, so a cold prefill on one replica slows the other two.
- The routers and the load generator run on the GPU node too.
- Dynamo's numbers come from its own vLLM workers, not the shared pods.
- Comments in `manifests/` say where a value differs from the project's docs.
- Kinference's gateway gets a ClusterIP Service. Its default, LoadBalancer, would put a public address in front of the model on GKE.
