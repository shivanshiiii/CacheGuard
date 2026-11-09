# Workload and latency sweep

Status: **passed**.

24 executed simulations: four patterns × three response scheduling delays × two variants, 256 reads per run, **6,144 additional scoreboard-checked reads**. These counts are separate from the 21,996-read main regression. Both variants match each other and a Python tag model; each transaction also passes golden-data, traffic and analytic latency checks in SystemVerilog.

| Pattern | Hits / 256 | Misses / 256 | Hit rate | Mean cycles, L=1 | L=3 | L=7 |
|---|---:|---:|---:|---:|---:|---:|
| Repeated word | 255 | 1 | 99.61% | 2.051 | 2.082 | 2.145 |
| Sequential stream | 192 | 64 | 75.00% | 5.250 | 7.250 | 11.250 |
| Alternating conflicts | 0 | 256 | 0.00% | 15.000 | 23.000 | 39.000 |
| Uniform 4-KiB random | 4 | 252 | 1.56% | 14.797 | 22.672 | 38.422 |

Every run starts with an empty cache. No jitter, request stalls or CPU response stalls are enabled here; those are covered by the main regression. L means the memory model's delay to asserting response-valid; the transfer is sampled on the following edge. For this controller, a hit takes two sampled cycles and a miss takes 4×(L+2)+3. Reported averages exclude gaps between CPU requests and are latency, not throughput.

## Engineering conclusions

- Repeated-word reads show the cost of one cold fill followed by temporal reuse.
- A sequential stream reuses three of the four words fetched per line.
- Alternating addresses 0 and 128 collide at index zero and miss on every read.
- Uniform 4-KiB random accesses have little locality in a 128-byte cache.
- Longer memory delays penalize misses. A single hit-rate number cannot describe every workload.
- Protected and baseline cycle counts match; generic synthesis shows hardware overhead. There is no claim that their maximum clock frequencies are equal.

This sweep is synthetic. It does not compare against an uncached CPU path, use real software traces, or establish application speedup.

Reproduce with `python scripts/benchmark.py`. Raw metrics, logs, source hashes and tool version are alongside this report. Windows execution and hosted CI remain unverified.
