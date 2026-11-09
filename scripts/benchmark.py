#!/usr/bin/env python3
"""Sweep four address patterns and three memory delays for both cache variants."""
import json
import os
import subprocess
import sys
from run import ROOT, RTL, dump, provenance, run, tool

PATTERNS=["Repeated word", "Sequential stream", "Alternating conflicts", "Uniform 4-KiB random"]


def expected_hits(pattern):
    """Independent integer-address cache model; no DUT/internal signal reads."""
    tags=[None]*8
    hits=0
    rng=2026
    for n in range(256):
        if pattern==0: address=0
        elif pattern==1: address=n*4
        elif pattern==2: address=(n%2)*128
        else:
            rng^=(rng<<13)&0xffffffff
            rng^=rng>>17
            rng^=(rng<<5)&0xffffffff
            address=rng&0xffc
        block=address//16
        index=block%8
        tag=block//8
        hits+=tags[index]==tag
        tags[index]=tag
    return hits


def write_report(out,manifest):
    lines=["# Workload and latency sweep", "", f"Status: **{manifest['status']}**.", ""]
    if manifest['status']=="passed":
        lines += ["24 executed simulations: four patterns × three response scheduling delays × two variants, "
                  "256 reads per run, **6,144 additional scoreboard-checked reads**. These counts are separate "
                  "from the 21,996-read main regression. Both variants match each other and a Python tag model; "
                  "each transaction also passes golden-data, traffic and analytic latency checks in SystemVerilog.", "",
                  "| Pattern | Hits / 256 | Misses / 256 | Hit rate | Mean cycles, L=1 | L=3 | L=7 |",
                  "|---|---:|---:|---:|---:|---:|---:|"]
        for pattern,name in enumerate(PATTERNS):
            rows=[r for r in manifest['runs'] if r['parity']==1 and r['pattern']==pattern]
            row=rows[0]
            means=" | ".join(f"{r['cycle_sum']/r['reads']:.3f}" for r in rows)
            lines.append(f"| {name} | {row['hits']} | {row['misses']} | {row['hits']/row['reads']:.2%} | {means} |")
        lines += ["", "Every run starts with an empty cache. No jitter, request stalls or CPU response stalls "
                  "are enabled here; those are covered by the main regression. L means the memory model's "
                  "delay to asserting response-valid; the transfer is sampled on the following edge. "
                  "For this controller, a hit takes two sampled cycles and a miss takes 4×(L+2)+3. "
                  "Reported averages exclude gaps between CPU requests and are latency, not throughput.", "",
                  "## Engineering conclusions", "",
                  "- Repeated-word reads show the cost of one cold fill followed by temporal reuse.",
                  "- A sequential stream reuses three of the four words fetched per line.",
                  "- Alternating addresses 0 and 128 collide at index zero and miss on every read.",
                  "- Uniform 4-KiB random accesses have little locality in a 128-byte cache.",
                  "- Longer memory delays penalize misses. A single hit-rate number cannot describe every workload.",
                  "- Protected and baseline cycle counts match; generic synthesis shows hardware overhead. "
                  "There is no claim that their maximum clock frequencies are equal.", "",
                  "This sweep is synthetic. It does not compare against an uncached CPU path, use real software "
                  "traces, or establish application speedup.", ""]
    lines += ["Reproduce with `python scripts/benchmark.py`. Raw metrics, logs, source hashes and tool version "
              "are alongside this report. Windows execution and hosted CI remain unverified.", ""]
    (out/"WORKLOADS.md").write_text("\n".join(lines),encoding="utf-8")


def main():
    out=ROOT/"reports/latest"
    out.mkdir(parents=True,exist_ok=True)
    (ROOT/"build").mkdir(exist_ok=True)
    manifest={"status":"running","provenance":provenance(),"runs":[]}
    dump(out/"workloads.json",manifest)
    write_report(out,manifest)
    try:
        iv,vvp=tool("iverilog"),tool("vvp")
        iv_base=os.environ.get("IVL_BASE")
        iv_flags=["-B",iv_base] if iv_base else []
        vvp_flags=["-M",iv_base] if iv_base else []
        manifest["tool"]=run([iv,*iv_flags,"-V"],out/"workload_tool.log").splitlines()[0]
        for parity in (0,1):
            binary=ROOT/"build"/f"workloads_{parity}.vvp"
            run([iv,*iv_flags,"-g2012","-Wall","-s","tb_workloads",
                 f"-Ptb_workloads.ENABLE_PARITY={parity}","-o",binary,*RTL,
                 "tb/backing_memory.sv","tb/tb_workloads.sv"],out/f"workload_compile_{parity}.log")
            for pattern in range(4):
                for delay in (1,3,7):
                    prefix=f"workload_p{parity}_a{pattern}_l{delay}"
                    metrics=out/f"{prefix}.json"
                    metrics.unlink(missing_ok=True)
                    result=run([vvp,*vvp_flags,binary,f"+pattern={pattern}",f"+latency={delay}",
                                f"+metrics={metrics.relative_to(ROOT).as_posix()}"],out/f"{prefix}.log")
                    row=json.loads(metrics.read_text())
                    h=expected_hits(pattern)
                    expected={"pass":True,"parity":parity,"pattern":pattern,"memory_delay":delay,
                              "reads":256,"hits":h,"misses":256-h,
                              "cycle_sum":h*2+(256-h)*(4*(delay+2)+3),"memory_reads":4*(256-h)}
                    if row!=expected or "PASS workload" not in result:
                        raise RuntimeError(f"Workload differs from independent expected metrics: {prefix}")
                    manifest["runs"].append(row)
        manifest["status"]="passed"
        print("PASS workload sweep: 24 runs, 6144 checked reads, independent model matches")
    except (RuntimeError,subprocess.TimeoutExpired,OSError,ValueError) as exc:
        manifest.update(status="failed",failure=str(exc))
        print(f"FAIL: {exc}",file=sys.stderr)
    finally:
        dump(out/"workloads.json",manifest)
        write_report(out,manifest)
    return 0 if manifest["status"]=="passed" else 1


if __name__=="__main__":
    sys.exit(main())
