# Verification plan and evidence

## Environment

The Icarus-compatible SystemVerilog testbench has a CPU driver, deterministic backing-memory BFM, independent reference-word function, reference cache tag/valid model, scoreboard, protocol assertions, fault injection and metrics collection. It uses no classes, UVM or unsupported concurrent assertion syntax.

Stimulus changes on falling edges. The monitor samples actual ready/valid transfers on rising edges before nonblocking updates. This avoids racing the driver against DUT state updates. The reference function computes the same documented ROM contents independently and does not call the BFM or inspect DUT data for expected values.

The immutable ROM word for aligned address A is `(A × 0x9E3779B1 mod 2^32) XOR rotate16(A) XOR 0xC0DECAFE`. All 32 address bits influence the calculation. This is synthetic verification data, not a firmware image or realistic memory workload.

## Test matrix

| Requirement | Stimulus | Check/evidence |
|---|---|---|
| Cold miss | Read address 0 after reset | Four ordered memory words; data correct; 15-cycle latency at L=1 |
| Spatial/temporal hit | Read every word in loaded lines | No extra memory requests; 2-cycle clean hit |
| Index decode | Sweep all eight lines and 32 slots | All word-slot bins reached |
| Tag conflict | Addresses separated by 128 bytes | Replacement and renewed miss |
| Full address width | High-bit addresses, `0xFFFFFFFC` | Reference data and exact refill addresses |
| Alignment | Offsets 1, 2, 3 | Error response, zero data, no memory request |
| CPU backpressure | Hold response-ready low | Valid/data/error remain stable |
| Consecutive demand | Continuous request-valid stream | Correct ordering, one outstanding request, no dropped reads |
| Memory timing | Scheduling delays 1/2/7; jitter; ready stalls | Exact data, held request address, no protocol timeout |
| Reset cancellation | LOOKUP, MEM_REQ, each of four MEM_WAIT beats, VERIFY, RESP | Eight cancellation cases per run, subsequent clean read |
| Data-fault campaign | Flip each bit at each of 32 word slots | 1,024 distinct positions; exactly one detection and four-word recovery per injection |
| Other-word fault | Corrupt word 2, read word 0, then word 2 | Deferred detection on affected word only |
| Fault during refill | Corrupt stored word 0 while remaining words arrive | VERIFY detects it; eight total memory reads; correct final data |
| Random addresses | 1,000 reads per seed, four address distributions | Scoreboard and reference tag model |
| Baseline comparison | Repeat isolated 1,000-read workload with parity off/on | Exact benchmark equality per seed |
| Parity metadata fault | Flip one stored parity bit | Correct data after recovery, one detection |
| Protection boundaries | Single-bit fault without parity; two-bit fault with parity | Expected silent wrong data is explicitly demonstrated in a separate bench |

Every protected main regression injects 1,026 transient data faults: 1,024 distinct data-bit positions plus the deferred-word and during-refill cases. Three seeds repeat the exhaustive campaign; they are 3,078 injections, not 3,078 unique positions. The separate limits bench adds one protected single-data-bit recovery and one parity-bit recovery. Main-regression totals intentionally exclude its transactions.

## Scoreboard and assertions

For each CPU acceptance the scoreboard stores the address, acceptance cycle, expected initial tag-hit status and memory request count. It tracks one outstanding transaction; resets cancel it explicitly. Every cycle containing a valid CPU response checks golden data and alignment status, including cycles where ready is low.

Immediate SystemVerilog `assert ... else $fatal` checks cover:

- No CPU response without an outstanding request, and no second request accepted while one is pending.
- Request/response payloads and valid remain stable under backpressure.
- No active handshake during reset; legal controller states during operation.
- Initial hit/miss pulses agree with a reference tag/valid model.
- Refill addresses follow line base + 0, 4, 8, 12, repeating only on retry.
- Memory responses correspond to an outstanding memory word request.
- Full refill completion occurs before CPU delivery; refill event counts match beats.
- Every successful valid read matches reference memory; errors occur only for misalignment.
- Detected parity errors never coincide with a CPU response.
- Accepted requests = completed responses + reset-aborted requests at regression end.
- Required coverage bins, error detection counts and reset/stall exercises are reached.

These are simulator-executed immediate assertions and temporal checks implemented with saved prior-cycle values. There is no claim of concurrent SVA coverage, formal proof, simulator line coverage or toggle coverage. `monitored_cycles` records actual non-reset monitor cycles, not a count of assertions executed.

## Functional coverage

Explicit bitmaps cover six FSM states, 32 index/word combinations and 1,024 word/bit fault positions. Each protected run requires every relevant bin. Reset-scenario and stall counters check that those behaviors were exercised. The campaign varies the flipped bit, addressed slot and CPU response stall length; it is not an exhaustive exploration of all state/input/time combinations.

## Randomness and performance

The driver uses a reproducible 32-bit xorshift generator with seeds 1, 17 and 2026. The randomized stress phase mixes a small hot region, 4-KiB addresses, arbitrary 32-bit aligned addresses and deliberate same-index conflicts.

The separate performance phase resets the cache and PRNG. Eight of every ten address draws use the low 128-byte region; the remaining draws use 4 KiB. This guarantees the same addresses, initial state and deterministic memory timing for each variant. There are 1,000 requests per benchmark. Hit rate, miss rate and mean first-response latency are workload-specific.

Request-to-first-response and request-to-response-transfer totals are separately recorded. Recovery latency starts when the monitor samples the registered parity event and ends when it first samples valid correct CPU data. Time from injection to access is excluded. Reporting both injection counts and recovery timing prevents a latent unaccessed fault from being described as a completed recovery.

## Mutation checks

`python scripts/mutation_check.py` compiles four temporary defective variants: disabled parity checking, corrupt refill input, request-ready asserted while busy, and dropped stalled responses. Each must fail with its expected assertion/data-check message. Compilation failure or watchdog expiration alone does not count as detecting the intended bug. Results and failure logs are stored in `reports/latest/`.

This checks selected failure-detection paths of the testbench, not its completeness. The production RTL is never modified by this script.

## Reproduce and interpret results

```text
python scripts/run.py all --seeds 1 17 2026 --random 1000
python scripts/mutation_check.py
python scripts/benchmark.py
```

Read `reports/latest/RESULTS.md`, per-run JSON and logs. `simulation.json`, `lint.json`, `synthesis.json` and `mutations.json` include source hashes. The published evidence snapshot is `reports/reference/`; ordinary runs do not overwrite it. A simulator or assertion failure gives a nonzero process exit and a failed manifest rather than a new pass report.

Verilator checks only synthesizable RTL with all `-Wall` warnings fatal. Yosys elaborates, flattens, synthesizes with generic ABC mapping, runs `check -assert`, and records cell statistics for both parameter values. This is separate evidence from functional RTL simulation. No gate-level simulation, formal equivalence, FPGA test, place-and-route, STA or power analysis was performed.

## Additional workload sweep in v1.1

`tb_workloads.sv` runs four fault-free access patterns: repeated address 0, a sequential 256-word stream, alternating addresses 0 and 128, and xorshift-generated aligned addresses in 4 KiB. Each pattern runs at memory response scheduling delays 1, 3 and 7, both with and without parity, for 24 independent simulations and 6,144 additional reads.

The SystemVerilog monitor checks every response against the ROM function, tracks a reference tag/valid model, checks memory traffic and compares each transaction's latency with the documented hit/miss schedule. The Python runner separately computes the address stream and expected hits, misses, memory reads and total cycles using integer block/index/tag arithmetic. Every reported metric must match this independent calculation.

The sweep deliberately disables stalls and jitter to isolate locality and memory scheduling delay; the main regression covers those conditions separately. `reports/reference/WORKLOADS.md` provides the measured table and its limits. The additional transactions are not silently added to the main regression count.

The CI workflow now invokes both auxiliary scripts after the main regression. Local execution of its commands passed; a hosted CI badge should be added only after an actual repository run succeeds. Mutation-run failures overwrite the prior status so a stale passing report cannot survive a new failed invocation.
