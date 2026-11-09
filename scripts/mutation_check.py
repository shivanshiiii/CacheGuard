#!/usr/bin/env python3
"""Check that the regression rejects four deliberately broken copies of the RTL."""
import os
import subprocess
import sys

from run import ROOT, dump, provenance, report, run, tool


def run_checks(out,manifest):
    work=ROOT/"build"/"mutations"
    work.mkdir(parents=True,exist_ok=True)
    iv_base=os.environ.get("IVL_BASE")
    iv_flags=["-B",iv_base] if iv_base else []
    vvp_flags=["-M",iv_base] if iv_base else []
    original={n:(ROOT/"rtl"/n).read_text() for n in ("cacheguard.v","cacheguard_array.v")}
    mutations=[
        ("disable_parity", "cacheguard_array.v",
         "assign parity_bad = (^read_data) ^ parity[read_slot];", "assign parity_bad = 1'b0;", "DATA MISMATCH"),
        ("damage_refill", "cacheguard.v", ".refill_data(mem_rsp_data)",
         ".refill_data(mem_rsp_data ^ 32'h1)", "DATA MISMATCH"),
        ("accept_while_busy", "cacheguard.v", "assign cpu_req_ready = !rst && (state == IDLE);",
         "assign cpu_req_ready = !rst;", "More than one outstanding CPU request"),
        ("drop_stalled_response", "cacheguard.v", "if (cpu_rsp_ready)",
         "if (1'b1)", "CPU response changed under backpressure"),
    ]
    results=manifest['mutations']
    for name,filename,old,new,expected in mutations:
        if original[filename].count(old)!=1:
            raise RuntimeError(f"Mutation anchor is not unique: {name}")
        paths=[]
        for fn,text in original.items():
            path=work/f"{name}_{fn}"
            path.write_text(text.replace(old,new) if fn==filename else text)
            paths.append(path)
        binary=work/f"{name}.vvp"
        run([tool("iverilog"),*iv_flags,"-g2012","-s","tb_cacheguard","-o",binary,
             *paths,"tb/backing_memory.sv","tb/tb_cacheguard.sv"],out/f"mutation_{name}_compile.log")
        cmd=[tool("vvp"),*vvp_flags,binary,"+seed=1","+random=10"]
        result=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
        (out/f"mutation_{name}.log").write_text(result.stdout)
        rejected=result.returncode!=0 and expected in result.stdout
        results.append({"mutation":name,"rejected":rejected,"return_code":result.returncode,"expected_failure":expected})
        print(f"{'PASS' if rejected else 'FAIL'} regression rejects {name}")
    return all(r["rejected"] for r in results)


def main():
    out=ROOT/"reports/latest"
    out.mkdir(parents=True,exist_ok=True)
    manifest={"status":"running","provenance":provenance(),"mutations":[]}
    dump(out/"mutations.json",manifest)
    report(out)
    try:
        manifest["status"]="passed" if run_checks(out,manifest) else "failed"
    except (RuntimeError,subprocess.TimeoutExpired,OSError) as exc:
        manifest.update(status="failed",failure=str(exc))
        print(f"FAIL: {exc}",file=sys.stderr)
    finally:
        dump(out/"mutations.json",manifest)
        report(out)
    return 0 if manifest["status"]=="passed" else 1


if __name__=="__main__":
    sys.exit(main())
