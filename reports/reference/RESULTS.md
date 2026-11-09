# CacheGuard measured results

Generated from executed tool runs. Raw logs and JSON are in this directory.

Simulation: **passed** — Icarus Verilog version 12.0 (stable) ()

6 regression runs; 21,996 completed reads; 48 deliberately reset-aborted requests.

| Variant | Seed | Completed | Detected/injected data faults | Reset scenarios |
|---|---:|---:|---:|---:|
| Baseline | 1 | 2128 | 0/0 | 8 |
| Baseline | 17 | 2128 | 0/0 | 8 |
| Baseline | 2026 | 2128 | 0/0 | 8 |
| Protected | 1 | 5204 | 1026/1026 | 8 |
| Protected | 17 | 5204 | 1026/1026 | 8 |
| Protected | 2026 | 5204 | 1026/1026 | 8 |

Three additional protection-limit scenarios passed: baseline single-bit corruption, protected parity-bit recovery, and expected undetected two-bit corruption.

## Fault-free benchmark

1,000 accepted reads per seed and variant; 80% of generated addresses come from a 128-byte hot region. The remaining 20% come from a 4-KiB region. Backing-memory response scheduling delay is 3 cycles plus deterministic 0–2-cycle jitter (response transfer is sampled on the following edge); request-ready stalls every fourth memory-model tick. CPU response ready is asserted at first availability.

| Seed | Hits | Misses | Hit rate | Miss rate | First-response average (cycles) | Memory word reads |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 635 | 365 | 63.5% | 36.5% | 11.733 | 1460 |
| 17 | 636 | 364 | 63.6% | 36.4% | 11.707 | 1456 |
| 2026 | 634 | 366 | 63.4% | 36.6% | 11.761 | 1464 |

Baseline and protected benchmark results are exactly equal for each seed. This is a cycle-count comparison at the RTL level, not proof of equal maximum clock frequency.

## Fault recovery

- Seed 1: 1026 recovered data faults; mean 21.970 cycles, maximum 24 cycles.
- Seed 17: 1026 recovered data faults; mean 21.970 cycles, maximum 24 cycles.
- Seed 2026: 1026 recovered data faults; mean 21.970 cycles, maximum 24 cycles.

Recovery is measured from the clock edge sampling the parity-error event to the edge sampling the first valid correct response. It excludes time from injection until the affected word is read. This campaign varies memory latency and stalls; its maximum is not a universal bound.

Each protected run covers all 1,024 data-bit positions once, all 32 word slots, all six FSM states, and eight reset-abort scenarios. These are explicit testbench bins, not simulator code/toggle coverage or formal proof.

## Generic synthesis

Status: **passed** — Yosys 0.33 (git sha1 2584903a060)

| Variant | Generic cells | Flip-flop cells |
|---|---:|---:|
| Baseline | 2863 | 1313 |
| Protected | 3032 | 1346 |

Generic cell-count overhead: **5.90%**. Both variants use the same flattened Yosys/ABC flow and interfaces. Parity stores 32 additional bits (3.125% of the 1,024 data bits). Generic gates/flip-flops are not FPGA LUTs, SRAM macros, silicon area, timing, power, or signoff evidence. No target technology or clock constraint is applied.

## RTL lint

Status: **passed** — Verilator 5.020 2024-01-01 rev (Debian 5.020-1)

Both parity configurations checked with `--lint-only -Wall`; warnings are fatal. Verilator was used for lint, not functional simulation.

## Checker validation

Mutation-check status: **passed**.

The regression rejected all four deliberately broken RTL copies with the expected data/protocol failures. See `mutations.json` and the four failure logs. These expected failures are separate from the passing production-RTL regressions.

## Reproduction and scope

Run `python scripts/run.py all --seeds 1 17 2026 --random 1000`. Results from a new run go to `reports/latest/`. Tool versions and SHA-256 source hashes are recorded in each stage manifest. Reference reports were run on Linux; Windows scripts are supplied but have not been executed on Windows. Simulation uses a synthetic immutable backing-memory model.
