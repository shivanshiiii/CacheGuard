# Verified project descriptions

Use these only after reproducing the project and being able to explain the design, testbench and measurement limits. These statements describe completed repository evidence; they do not claim deployment, silicon signoff, personal work history or an automated screening score.

## Suggested two-bullet version

- Developed a synthesizable 128-byte direct-mapped cache in Verilog with a 32-bit address interface, per-word parity, automatic invalidation/refill recovery, and ready/valid flow control.
- Verified 21,996 completed reads across six Icarus Verilog regression runs using a SystemVerilog scoreboard and assertions; recovered 3,078 injected single-bit data faults and measured 5.90% generic cell overhead with Yosys.

## Verification-focused alternative

- Built a self-checking SystemVerilog environment covering all 1,024 cache-data bit positions, six controller states, eight reset-abort scenarios, randomized reads, conflicts, memory stalls and response backpressure.
- Compared parity-enabled and baseline caches with identical seeded workloads; demonstrated parity's two-bit-error limitation and validated checker behavior against four deliberate RTL mutations.

## Numbers and boundaries

An optional architecture-focused bullet for v1.1:

- Evaluated four memory-access patterns across three memory delays and two cache variants in 24 simulations, validating 6,144 reads against independent reference models and quantifying locality/conflict effects on average access latency.

Choose two or three bullets that fit the role. Keep the main regression count and the additional benchmark count distinct.

| Claim | Evidence / exact meaning |
|---|---|
| 21,996 completed reads | Main regression totals across three seeds and two variants |
| 3,078 recovered data faults | 1,026 injections per protected run, repeated for three seeds |
| 1,024 positions | 8 lines × 4 words × 32 bits; these are unique storage positions |
| Eight reset scenarios | LOOKUP, MEM_REQ, four MEM_WAIT beat positions, VERIFY, RESP |
| 5.90% cell overhead | (3,032 − 2,863) / 2,863 in the documented generic Yosys flow |
| Identical benchmark cycles | Same address trace and microarchitecture; no frequency claim |

Do not replace “generic cell overhead” with “silicon area overhead” or claim FPGA implementation, SECDED, UVM, cache coherence, formal proof, achieved clock frequency or processor integration. Those are outside the completed scope.
