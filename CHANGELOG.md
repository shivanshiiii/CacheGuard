# Release history

## v1.1 — Verification and publication improvements

- Added 24 fault-free workload/delay simulations and 6,144 checked reads, using a SystemVerilog scoreboard and an independent Python metric calculation.
- Recorded how temporal locality, spatial locality, same-index conflicts and uniform random access affect hit rate and latency.
- Extended CI to execute mutation checks and workload comparisons in addition to regression, lint and synthesis. Hosted execution remains pending.
- Made mutation-check status fail safely on missing tools, changed mutation anchors, timeouts and execution errors.
- Updated documentation and resume wording with measured results. The cache interface, geometry and RTL are unchanged from v1.

## v1 — Initial verified implementation

- Added the fixed 8-line read-only cache, per-word parity and automatic invalidate/refill/verify recovery.
- Executed six main regressions, protection-limit tests, four checker mutations, RTL lint and baseline/protected generic synthesis.
- Supplied Windows run instructions, waveform guidance, architecture documentation and raw reference evidence.
