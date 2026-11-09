#!/usr/bin/env python3
"""Reproducible Icarus simulation, Verilator RTL lint and Yosys synthesis (stdlib only)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ["rtl/cacheguard.v", "rtl/cacheguard_array.v"]


def tool(name):
    value = os.environ.get(name.upper(), name)
    found = shutil.which(value)
    if not found:
        raise RuntimeError(f"{name} not found. Put it on PATH or set {name.upper()} to its executable path.")
    return found


def run(cmd, log, timeout=180):
    result = subprocess.run([str(x) for x in cmd], cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text("COMMAND: " + subprocess.list2cmdline([str(x) for x in cmd]) +
                   "\n\n" + result.stdout, encoding="utf-8")
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}); see {log.relative_to(ROOT)}\n{result.stdout[-3500:]}")
    return result.stdout


def dump(path, obj):
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def provenance():
    files = sorted(list((ROOT/"rtl").glob("*.v")) + list((ROOT/"tb").glob("*.sv")) +
                   list((ROOT/"scripts").glob("*.py")) + list((ROOT/"synth").glob("*.in")))
    return {"platform": platform.platform(), "python": platform.python_version(),
            "sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}


def simulation(args, out):
    iv, vvp = tool("iverilog"), tool("vvp")
    iv_base = os.environ.get("IVL_BASE")
    iv_flags = ["-B", iv_base] if iv_base else []
    vvp_flags = ["-M", iv_base] if iv_base else []
    version = run([iv, *iv_flags, "-V"], out/"iverilog_version.log").splitlines()[0]
    manifest = {"status": "running", "tool": version, "provenance": provenance(), "runs": []}
    dump(out/"simulation.json", manifest)
    try:
        for parity in (0, 1):
            name = "protected" if parity else "baseline"
            binary = ROOT/"build"/f"{name}.vvp"
            run([iv, *iv_flags, "-g2012", "-Wall", "-s", "tb_cacheguard",
                 f"-Ptb_cacheguard.ENABLE_PARITY={parity}", "-o", binary, *RTL,
                 "tb/backing_memory.sv", "tb/tb_cacheguard.sv"], out/f"compile_{name}.log")
            for seed in args.seeds:
                prefix = f"{name}_seed_{seed}"
                metrics = out/f"{prefix}.json"
                metrics.unlink(missing_ok=True)
                cmd = [vvp, *vvp_flags, binary, f"+seed={seed}", f"+random={args.random}",
                       f"+metrics={metrics.relative_to(ROOT).as_posix()}"]
                if args.vcd and parity == 1 and seed == args.seeds[0]:
                    cmd.append("+vcd=build/cacheguard.vcd")
                result = run(cmd, out/f"{prefix}.log")
                data = json.loads(metrics.read_text())
                if not data["pass"] or "PASS parity=" not in result:
                    raise RuntimeError(f"Missing simulation PASS marker for {prefix}")
                manifest["runs"].append(data)
                print(f"PASS {prefix}: {data['completed']} completed, {data['parity_detections']} detections")
        binary = ROOT/"build"/"protection_limits.vvp"
        run([iv, *iv_flags, "-g2012", "-Wall", "-s", "tb_protection_limits", "-o", binary,
             *RTL, "tb/backing_memory.sv", "tb/tb_protection_limits.sv"], out/"compile_limits.log")
        result = run([vvp, *vvp_flags, binary], out/"protection_limits.log")
        if "PASS protection limits (3 scenarios)" not in result:
            raise RuntimeError("Missing limitation-test PASS marker")
        # Compare identical benchmark traces, including exact hit/miss and cycle totals.
        for seed in args.seeds:
            pair = [r for r in manifest["runs"] if r["seed"] == seed]
            if pair[0]["benchmark"] != pair[1]["benchmark"]:
                raise RuntimeError(f"Baseline/protected benchmark mismatch seed={seed}")
        manifest.update(status="passed", limitation_scenarios=3,
                        baseline_protected_benchmarks_equal=True)
    except Exception:
        manifest["status"] = "failed"
        raise
    finally:
        dump(out/"simulation.json", manifest)


def synthesis(out):
    yosys = tool("yosys")
    version = run([yosys, "-V"], out/"yosys_version.log").strip()
    manifest = {"status": "running", "tool": version, "provenance": provenance(), "variants": {}}
    dump(out/"synthesis.json", manifest)
    try:
        for parity in (0, 1):
            name = "protected" if parity else "baseline"
            stats = (out/f"synth_{name}_stats.json").relative_to(ROOT).as_posix()
            netlist = f"build/{name}_netlist.v"
            script = (ROOT/"synth"/"generic.ys.in").read_text()
            script = script.replace("@PARITY@", str(parity)).replace("@STATS@", stats).replace("@NETLIST@", netlist)
            script_path = ROOT/"build"/f"{name}.ys"
            script_path.write_text(script, encoding="utf-8")
            run([yosys, "-s", script_path], out/f"synth_{name}.log")
            raw = json.loads((ROOT/stats).read_text())
            module = raw["modules"]["\\cacheguard"]
            types = module["num_cells_by_type"]
            manifest["variants"][name] = {
                "generic_cells": module["num_cells"],
                "flip_flop_cells": sum(v for k,v in types.items() if "DFF" in k),
                "cell_types": types,
            }
            print(f"PASS Yosys {name}: {module['num_cells']} generic cells")
        base = manifest["variants"]["baseline"]["generic_cells"]
        protected = manifest["variants"]["protected"]["generic_cells"]
        manifest["generic_cell_overhead_percent"] = (protected-base)*100/base
        manifest["status"] = "passed"
    except Exception:
        manifest["status"] = "failed"
        raise
    finally:
        dump(out/"synthesis.json", manifest)


def lint(out):
    verilator = tool("verilator")
    version = run([verilator, "--version"], out/"verilator_version.log").strip()
    manifest = {"status": "running", "tool": version, "provenance": provenance()}
    dump(out/"lint.json", manifest)
    try:
        for parity in (0, 1):
            run([verilator, "--lint-only", "-Wall", "--top-module", "cacheguard",
                 f"-GENABLE_PARITY={parity}", *RTL], out/f"lint_parity_{parity}.log")
        manifest["status"] = "passed"
        print("PASS Verilator RTL lint: baseline and protected")
    except Exception:
        manifest["status"] = "failed"
        raise
    finally:
        dump(out/"lint.json", manifest)


def report(out):
    def load_stage(path):
        data=json.loads(path.read_text())
        saved=data.get("provenance",{}).get("sha256")
        if data["status"]=="passed" and saved!=provenance()["sha256"]:
            data["status"]="stale: source files changed; rerun this stage"
        return data

    lines = ["# CacheGuard measured results", "", "Generated from executed tool runs. Raw logs and JSON are in this directory.", ""]
    sim_path = out/"simulation.json"
    if sim_path.exists():
        sim = load_stage(sim_path)
        lines += [f"Simulation: **{sim['status']}** — {sim['tool']}", ""]
        if sim["status"] == "passed":
            runs = sim["runs"]
            lines += [f"{len(runs)} regression runs; {sum(r['completed'] for r in runs):,} completed reads; "
                      f"{sum(r['aborted'] for r in runs)} deliberately reset-aborted requests.", "",
                      "| Variant | Seed | Completed | Detected/injected data faults | Reset scenarios |",
                      "|---|---:|---:|---:|---:|"]
            for r in runs:
                lines.append(f"| {'Protected' if r['parity'] else 'Baseline'} | {r['seed']} | {r['completed']} | "
                             f"{r['parity_detections']}/{r['faults_injected']} | {r['reset_scenarios']} |")
            lines += ["", "Three additional protection-limit scenarios passed: baseline single-bit corruption, "
                      "protected parity-bit recovery, and expected undetected two-bit corruption.", "",
                      "## Fault-free benchmark", "", "1,000 accepted reads per seed and variant; 80% of generated addresses "
                      "come from a 128-byte hot region. The remaining 20% come from a 4-KiB region. "
                      "Backing-memory response scheduling delay is 3 cycles plus deterministic 0–2-cycle jitter "
                      "(response transfer is sampled on the following edge); "
                      "request-ready stalls every fourth memory-model tick. CPU response ready is asserted at first availability.", "",
                      "| Seed | Hits | Misses | Hit rate | Miss rate | First-response average (cycles) | Memory word reads |",
                      "|---|---:|---:|---:|---:|---:|---:|"]
            for r in runs:
                if not r["parity"]: continue
                b=r["benchmark"]
                lines.append(f"| {r['seed']} | {b['hits']} | {b['misses']} | {b['hits']/b['reads']:.1%} | "
                             f"{b['misses']/b['reads']:.1%} | {b['first_response_cycles_sum']/b['reads']:.3f} | {b['memory_word_reads']} |")
            lines += ["", "Baseline and protected benchmark results are exactly equal for each seed. "
                      "This is a cycle-count comparison at the RTL level, not proof of equal maximum clock frequency.", "",
                      "## Fault recovery", ""]
            for r in runs:
                if r["parity"]:
                    lines.append(f"- Seed {r['seed']}: {r['recovery_count']} recovered data faults; "
                                 f"mean {r['recovery_cycles_sum']/r['recovery_count']:.3f} cycles, "
                                 f"maximum {r['recovery_cycles_max']} cycles.")
            lines += ["", "Recovery is measured from the clock edge sampling the parity-error event "
                      "to the edge sampling the first valid correct response. It excludes time from injection "
                      "until the affected word is read. This campaign varies memory latency and stalls; "
                      "its maximum is not a universal bound.", "",
                      "Each protected run covers all 1,024 data-bit positions once, all 32 word slots, "
                      "all six FSM states, and eight reset-abort scenarios. These are explicit testbench bins, "
                      "not simulator code/toggle coverage or formal proof.", ""]
    syn_path=out/"synthesis.json"
    if syn_path.exists():
        syn=load_stage(syn_path)
        lines += ["## Generic synthesis", "", f"Status: **{syn['status']}** — {syn['tool']}", ""]
        if syn["status"]=="passed":
            lines += ["| Variant | Generic cells | Flip-flop cells |", "|---|---:|---:|"]
            for name,r in syn["variants"].items():
                lines.append(f"| {name.capitalize()} | {r['generic_cells']} | {r['flip_flop_cells']} |")
            lines += ["", f"Generic cell-count overhead: **{syn['generic_cell_overhead_percent']:.2f}%**. "
                      "Both variants use the same flattened Yosys/ABC flow and interfaces. "
                      "Parity stores 32 additional bits (3.125% of the 1,024 data bits). "
                      "Generic gates/flip-flops are not FPGA LUTs, SRAM macros, silicon area, timing, power, or signoff evidence. "
                      "No target technology or clock constraint is applied.", ""]
    lint_path=out/"lint.json"
    if lint_path.exists():
        data=load_stage(lint_path)
        lines += ["## RTL lint", "", f"Status: **{data['status']}** — {data['tool']}", ""]
        if data["status"]=="passed":
            lines += ["Both parity configurations checked with `--lint-only -Wall`; warnings are fatal. "
                      "Verilator was used for lint, not functional simulation.", ""]
    mutation_path=out/"mutations.json"
    if mutation_path.exists():
        data=load_stage(mutation_path)
        lines += ["## Checker validation", "", f"Mutation-check status: **{data['status']}**.", ""]
        if data["status"]=="passed":
            lines += ["The regression rejected all four deliberately broken RTL copies with the expected "
                      "data/protocol failures. See `mutations.json` and the four failure logs. "
                      "These expected failures are separate from the passing production-RTL regressions.", ""]
    lines += ["## Reproduction and scope", "", "Run `python scripts/run.py all --seeds 1 17 2026 --random 1000`. "
              "Results from a new run go to `reports/latest/`. Tool versions and SHA-256 source hashes are recorded "
              "in each stage manifest. Reference reports were run on Linux; Windows scripts are supplied but "
              "have not been executed on Windows. Simulation uses a synthetic immutable backing-memory model.", ""]
    (out/"RESULTS.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["sim", "synth", "lint", "all", "report"])
    parser.add_argument("--seeds", nargs="+", type=int, default=[1,17,2026])
    parser.add_argument("--random", type=int, default=1000)
    parser.add_argument("--vcd", action="store_true", help="Dump first protected run to build/cacheguard.vcd")
    args=parser.parse_args()
    if len(set(args.seeds))!=len(args.seeds) or args.random<0:
        parser.error("Seeds must be unique and random count nonnegative")
    out=ROOT/"reports"/"latest"
    out.mkdir(parents=True, exist_ok=True); (ROOT/"build").mkdir(exist_ok=True)
    stages=(["sim","lint","synth"] if args.stage=="all" else [args.stage])
    filenames={"sim":"simulation.json","lint":"lint.json","synth":"synthesis.json"}
    for stage in stages:
        if stage in filenames:
            dump(out/filenames[stage],{"status":"not_run","tool":"not checked"})
    current_stage=None
    try:
        for stage in stages:
            current_stage=stage
            if stage=="sim": simulation(args,out)
            if stage=="lint": lint(out)
            if stage=="synth": synthesis(out)
        report(out)
    except (RuntimeError, subprocess.TimeoutExpired) as exc:
        if current_stage in filenames:
            path=out/filenames[current_stage]
            data=json.loads(path.read_text())
            data.update(status="failed",failure=str(exc))
            dump(path,data)
        report(out)
        print(f"FAIL: {exc}",file=sys.stderr)
        return 1
    print("Report: reports/latest/RESULTS.md")
    return 0


if __name__=="__main__":
    sys.exit(main())
