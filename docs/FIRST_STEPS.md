# First learning session

Start with a passing local simulation. Do not begin by modifying the controller.

## Step 1 — Run

In the extracted `CacheGuard` folder:

```powershell
py -3 scripts/run.py sim --seeds 1 --random 1000 --vcd
```

Read the PASS lines, then `reports/latest/RESULTS.md`. The protected regression checks every response against a reference memory value; it also deliberately flips data bits inside the cache and checks recovery.

## Step 2 — Understand one line

Think of the cache as eight numbered slots. Each slot holds four words from one 16-byte memory block. The index chooses the slot; the tag identifies the block currently stored there; the word offset chooses one word inside it.

| Read | Expected action after reset |
|---|---|
| `0x00000000` | Miss: fetch words at 0, 4, 8, 12 into line 0 |
| `0x00000004` | Hit: use word 1 already stored in line 0 |
| `0x00000080` | Miss: same index, different tag; replace line 0 |
| `0x00000000` | Miss again: its previous block was replaced |

## Step 3 — Understand recovery

Suppose the stored word for address 4 has one bit flipped. Its new XOR parity differs from the saved parity bit. The controller invalidates the line and reads the four original words from trusted memory. Only after refill and another parity check does it provide the response. It repairs the cached copy by fetching it again; parity does not tell the controller which bit to flip back.

## Step 4 — Read two source files

In `rtl/cacheguard_array.v`, find `valid`, `tags`, `data` and `g_parity.parity`. Then find `tag_hit` and `parity_bad`.

In `rtl/cacheguard.v`, read the state names first. Trace the path IDLE → LOOKUP → RESP for a clean hit. Then trace a miss through MEM_REQ/MEM_WAIT four times and VERIFY before RESP. Notice that request/response ready and valid decide when transitions are allowed.

## Step 5 — Observe, then explain

Open the waveform and locate the initial miss and following hit. Explain why the miss reads four words, why the next word hits, and why response data must stay stable when the CPU is not ready.

After you can explain those cases, study fault injection and reset in `tb/tb_cacheguard.sv`. The architecture and verification documents provide the full contract. Later extensions should start only after the unchanged regression passes on your machine.
