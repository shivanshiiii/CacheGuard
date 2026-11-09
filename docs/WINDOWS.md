# Run on Windows

## 1. Extract and open the project

Extract the ZIP using **Extract All**. Open the extracted `CacheGuard` folder; it must contain `rtl`, `tb`, `scripts` and `README.md`. In File Explorer, type `powershell` in the address bar and press Enter. Commands below assume this folder is the current directory.

## 2. Check existing tools

```powershell
iverilog -V
vvp -V
py -3 --version
```

Use uppercase `-V`, not `-- e`. If Icarus is not found, add the `bin` directory from your existing Icarus installation to PATH, then reopen PowerShell. `vvp.exe` is usually installed with it. If `py` is not found, try `python --version`; the scripts require Python 3.9 or newer and no extra packages.

You can specify explicit executable paths for the runner without editing source files:

```powershell
$env:IVERILOG = 'C:\iverilog\bin\iverilog.exe'
$env:VVP = 'C:\iverilog\bin\vvp.exe'
```

Use your actual installation paths. `YOSYS` and `VERILATOR` are similarly supported when those tools are installed. They are not needed for the first simulation.

## 3. Run one seed first

```powershell
py -3 scripts/run.py sim --seeds 1 --random 1000 --vcd
```

This runs baseline and protected regressions plus the protection-limit bench. Expect baseline `completed=2128`, protected `completed=5204`, and protected `faults=1026 detected=1026` in the detailed logs. The main console prints PASS summaries and the report path.

If a command reports FAIL, open its named log in `reports/latest/`. Do not treat a generated waveform or a completed compilation as proof that the assertions passed.

## 4. Open the waveform

```powershell
gtkwave build/cacheguard.vcd
```

Alternatively, open GTKWave normally and load that file. See [WAVEFORMS.md](WAVEFORMS.md) for signals and expected behavior. The full trace can be several megabytes; it is generated locally and omitted from the source package.

## 5. Run the full regression

```powershell
py -3 scripts/run.py sim --seeds 1 17 2026 --random 1000
py -3 scripts/mutation_check.py
py -3 scripts/benchmark.py
```

If Python commands start the Microsoft Store, use the installed Python launcher's `py -3` command or the full path to your actual Python executable.

The benchmark command prints `PASS workload sweep: 24 runs, 6144 checked reads, independent model matches` and writes `reports/latest/WORKLOADS.md`.

## 6. Optional local synthesis and lint

Once Yosys and Verilator are available on PATH:

```powershell
yosys -V
verilator --version
py -3 scripts/run.py synth
py -3 scripts/run.py lint
```

Or use `py -3 scripts/run.py all`. A Linux/WSL environment can run the same Python entry point with `python3`. No Windows synthesis result is claimed until you run it. The ZIP already contains executed Linux reference results, so you can inspect them before setting up additional tools.

## No-Python fallback for simulation

Run each command separately and stop if compilation reports an error:

```powershell
New-Item -ItemType Directory -Force build
iverilog -g2012 -Wall -s tb_cacheguard -o build/cacheguard.vvp rtl/cacheguard.v rtl/cacheguard_array.v tb/backing_memory.sv tb/tb_cacheguard.sv
vvp build/cacheguard.vvp +seed=1 +random=1000 +metrics=build/metrics.json +vcd=build/cacheguard.vcd
```

This manually runs only the protected main testbench. Use the Python runner for the baseline comparison, limits tests and formatted report. The optional `scripts/run.ps1 sim` wrapper invokes the same runner; using the direct Python commands avoids PowerShell script execution-policy issues.

## Returning after restarting the laptop

Open PowerShell in the extracted `CacheGuard` folder again and run the same simulation command. You do not need to reopen an earlier terminal session. Stop an ongoing simulation with **Ctrl+C**; an interrupted run is not a passing result.
