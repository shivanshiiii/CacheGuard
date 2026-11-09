# Technical interview discussion

## 1. Why is the cache direct-mapped?

Each memory block has exactly one possible cache index. This keeps lookup and replacement understandable while allowing meaningful tag-conflict, parity-recovery and handshake verification. It trades simplicity for conflict misses; there is no LRU logic.

## 2. How did you calculate the fields?

Sixteen bytes per line requires four offset bits. Eight lines requires three index bits. A 32-bit address leaves 25 tag bits. The low two offset bits identify the byte and must be zero for this word-read interface; the other two select the word.

## 3. Why are valid bits needed?

After reset, data and tags may contain arbitrary values. A matching tag alone cannot prove the line contains valid memory data. A line becomes valid only when all four refill words and its tag are committed.

## 4. What makes this more than a basic cache exercise?

The integrated work covers fault detection and retry, revalidation after refill, response backpressure, a documented reset cancellation contract, systematic bit-position fault injection, an independent scoreboard, protocol assertions, reproducible baseline measurements and synthesis overhead. The merit lies in implementation and evidence, not claiming that parity itself is novel.

## 5. Can parity correct an error?

No. It detects a mismatch but does not identify the damaged bit. This read-only design uses a clean backing-memory copy to recover the entire line. A dirty write-back line would need a different policy because the latest data might exist only in the damaged cache.

## 6. What does parity miss?

An even number of flipped bits in one protected word can preserve parity. The project includes an explicit two-bit demonstration. Tag, valid, control and output-register faults are also outside this design's protection boundary.

## 7. Why a VERIFY state after refill?

A requested word can be corrupted after it is written while the remaining refill words are still arriving. Rechecking after line commit prevents that fault from slipping through. The testbench injects exactly such a fault and checks for a second full refill before delivery.

## 8. What happens if the CPU is not ready?

RESP keeps response-valid, data and error stable. The cache cannot accept another request until the current response is consumed. Assertions verify payload stability and request conservation.

## 9. What happens on reset during refill?

The cache clears all valid bits and abandons the CPU transaction. The memory peer resets with it to flush pending responses. Without transaction IDs, resetting only the cache is unsafe; a stale memory response could be mistaken for a later request.

## 10. How do you know returned data is correct?

The scoreboard derives the expected word from the accepted full address using an independent reference function. It checks data on every cycle where CPU response-valid is asserted, including stalled cycles. A separate tag/valid model checks hit/miss classification. Passing a waveform inspection alone would not provide this evidence.

## 11. What was measured?

The reference report records 21,996 completed reads across six regressions, 3,078 main-campaign fault recoveries, workload-specific hit rates and cycle latency, and generic synthesis counts. Always name the workload and tool flow alongside numbers; the benchmark is synthetic and does not represent application performance.

## 12. Is parity free if cycle latency is unchanged?

No. The XOR tree and parity storage add hardware and can affect combinational delay, power and maximum clock frequency. The current cycle schedule is unchanged, but physical timing/power have not been measured. Yosys reports 5.90% more generic cells in this flow.

## 13. How was the testbench checked?

Four deliberate RTL mutations are required to fail with specific assertions: disabled protection, corrupt refill data, accepting a second request while busy and dropping a held response. This gives evidence that those checker paths are active, not proof that every possible design bug will be found.

## 14. What would you improve next?

Choose one justified extension: memory timeouts/error responses for liveness, tag/control protection for a wider fault boundary, parameterized geometry, SECDED, or a CPU integration adapter. Each changes the specification and needs targeted verification. Keep present results reproducible before extending the scope.
