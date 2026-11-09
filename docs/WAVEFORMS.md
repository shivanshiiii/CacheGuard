# Inspect waveforms in GTKWave

Generate a protected trace with:

```text
python scripts/run.py sim --seeds 1 --random 1000 --vcd
gtkwave build/cacheguard.vcd
```

The trace uses a 10-ns test clock. This arbitrary stimulus period is not an achieved hardware timing result.

## Signals to add

From `tb_cacheguard`, add `clk`, `rst`, `cpu_req_valid`, `cpu_req_ready`, `cpu_req_addr`, `cpu_rsp_valid`, `cpu_rsp_ready`, `cpu_rsp_data`, `cpu_rsp_error`, `mem_req_valid`, `mem_req_ready`, `mem_req_addr`, `mem_rsp_valid`, `mem_rsp_ready`, `mem_rsp_data`, `evt_hit`, `evt_miss`, `evt_parity_error`, and `evt_refill_done`.

From `dut`, add `state`, `addr_q`, `beat`, `tag_hit`, `parity_bad`, `invalidate`, `commit_line`. From `dut.u_array`, add `valid`. Set address/data buses to hexadecimal. Uninitialized storage can appear X while a line is invalid; this is expected, but successful CPU response data must never be X.

## What to look for

| Scenario | Waveform evidence |
|---|---|
| First read | Request acceptance, miss pulse, memory addresses 0/4/8/C, refill pulse, correct response |
| Following word | Hit pulse, no new memory request, response two sampled cycles after acceptance |
| Conflict | Same index, changed tag, invalidation and four new memory requests |
| Parity recovery | A parity-error pulse followed by invalidation/refill; response appears only after VERIFY |
| During-refill fault | Two consecutive four-word refills for one CPU request; only one final correct response |
| Response stall | Response valid/data/error stay constant while response ready is zero |
| Reset during work | Ready/valid suppressed, valid bits cleared, pending request cancelled; no stale response |

Use GTKWave's signal search to find a rising `evt_parity_error` rather than scrolling through the whole fault campaign. Log messages identify the order of the test phases. Raw arrays are not guaranteed to appear as useful per-word signals in every VCD viewer; the selected-word `cached_data` and `parity_bad` signals are sufficient to observe recovery.

## Initial timing example

At the initial L=1, no-stall miss, use the CPU request-acceptance edge as relative cycle 0:

| Relative cycle | Action sampled at edge |
|---:|---|
| 0 | CPU request accepted |
| 1 | LOOKUP decides miss; invalidates line |
| 2 | Memory request for word 0 accepted |
| 4 | Memory response for word 0 consumed |
| 5, 8, 11 | Memory requests for words 1, 2, 3 accepted |
| 7, 10, 13 | Their responses consumed; line committed at 13 |
| 14 | VERIFY captures correct requested data |
| 15 | First valid CPU response sampled/consumed if ready |

RTL registers change just after the edge that causes the update. Therefore the CPU response signal rises after cycle 14, and a synchronous consumer first transfers it at cycle 15. Metrics consistently use sampled rising-edge differences.
