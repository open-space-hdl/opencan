"""Synthesis check of OpenCAN with GHDL: elaborates and synthesises the modules at the values of their generics that
the verification reports list (every value of a structure generic, the ends of the numeric ranges), and checks that
inconsistent configurations stop with the message of the module.

Usage: python lint/synth_check.py [-j N]
Uses the libraries compiled by the regression runner (run `python run.py --compile` first); the netlists are written
to vunit_out/synth_check. Exit code 0 when every configuration synthesises without error and without inferred latch,
and every inconsistent configuration fails with its message. This is a technology-independent check of
synthesizability; resources and timing need the FPGA tools.
"""

import argparse
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"
OUT = ROOT / "vunit_out" / "synth_check"


def configs():
    """(top, generics, None) for valid configurations, (top, generics, expected message) for inconsistent ones."""
    cfg = []
    for access in ("Selective", "Parallel"):
        for recover in ("true", "false"):
            cfg.append(("ocan_link", {"BusAccess_g": access, "AutoRecover_g": recover}, None))
        for stages in (2, 3, 4):
            cfg.append(("ocan_link", {"BusAccess_g": access, "SyncStages_g": str(stages)}, None))
        for limit in (13, 32, 1023):
            cfg.append(("ocan_link", {"BusAccess_g": access, "DominantLimit_g": str(limit)}, None))
    cfg.append(("ocan_link", {"BusAccess_g": "Dual"}, "BusAccess_g must be"))
    for n in range(0, 5):
        cfg.append(("ocan_dispatch", {"NumRpdo_g": str(n)}, None))
        cfg.append(("ocan_dispatch", {"NumTpdo_g": str(n)}, None))
    for flag in ("TimePdos_g", "SdoServer_g"):
        cfg.append(("ocan_dispatch", {flag: "false"}, None))
    return cfg


def synth(top, generics, expected):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=opencan",
           f"--workdir={LIBS / 'opencan'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append(top)
    name = top + "".join(f"_{k[:-2]}{v}" for k, v in generics.items())
    with open(OUT / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    log = res.stderr
    if expected is not None:
        ok = res.returncode != 0 and expected in log
        return ok, f"{name}: {'rejected' if ok else 'NOT REJECTED as expected'}", []
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = res.returncode == 0 and not latches and not errors
    return ok, f"{name}: {'OK' if ok else 'FAILED'}", (errors + latches)[:20]


def main():
    parser = argparse.ArgumentParser(description="GHDL synthesis check of the OpenCAN modules")
    parser.add_argument("-j", type=int, default=1, help="parallel GHDL processes")
    args = parser.parse_args()
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        results = list(pool.map(lambda c: synth(*c), configs()))
    for ok, line, details in results:
        print(line)
        for detail in details:
            print("  " + detail)
    failed = sum(not ok for ok, _, _ in results)
    print(f"{len(results)} configurations, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
