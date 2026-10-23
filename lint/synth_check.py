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
    for minimal in ("false", "true"):
        cfg.append(("ocan_nmt", {"MinimalSet_g": minimal}, None))
        cfg.append(("ocan_redundancy", {"MinimalSet_g": minimal}, None))
    for fine in (0, 1, 23, 24):
        cfg.append(("ocan_time", {"FineBits_g": str(fine)}, None))
    for freq in (1000000, 2147483647):
        cfg.append(("ocan_time", {"ClkFrequency_g": str(freq)}, None))
    cfg.append(("ocan_time", {"FineBits_g": "0", "ClkFrequency_g": "2147483647"}, None))
    cfg.append(("ocan_time", {"FineBits_g": "0", "ClkFrequency_g": "1000000"}, None))
    # ocan_od: every value of the structural generics, the bounds of the numeric ones; TC-OD-21 the rejections
    for minimal in ("false", "true"):
        for time in ("false", "true"):
            gen = {"MinimalSet_g": minimal, "TimePdos_g": time, "NumRpdo_g": "4", "NumTpdo_g": "4"}
            if minimal == "true" and time == "true":
                gen.update({"NumRpdo_g": "3", "NumTpdo_g": "3", "SctCobId_g": "240", "LtpCobId_g": "501"})
            cfg.append(("ocan_od", gen, None))
    for n in (0, 1, 2, 3):
        cfg.append(("ocan_od", {"NumRpdo_g": str(n), "NumTpdo_g": str(3 - n)}, None))
    cfg.append(("ocan_od", {"ProducerHbTime_g": "65535", "MasterNodeId_g": "127", "MasterHbTime_g": "0",
                            "Bdefault_g": "1", "Ttoggle_g": "255", "Ntoggle_g": "0", "RpdoType_g": "255",
                            "TpdoType_g": "0", "SctCobId_g": "1279", "LtpCobId_g": "1280"}, None))
    time = {"MinimalSet_g": "true", "TimePdos_g": "true", "SctCobId_g": "240", "LtpCobId_g": "501"}
    cfg.append(("ocan_od", {**time, "NumRpdo_g": "4", "NumTpdo_g": "3"}, "OD-MS-05"))
    cfg.append(("ocan_od", {**time, "NumRpdo_g": "3", "NumTpdo_g": "4"}, "OD-MS-05"))
    # The time COB-IDs of the minimal set with the time PDOs are not 0 (OD-MS-03)
    cfg.append(("ocan_od", {**time, "NumRpdo_g": "3", "NumTpdo_g": "3", "SctCobId_g": "0"}, "OD-MS-03"))
    cfg.append(("ocan_od", {**time, "NumRpdo_g": "3", "NumTpdo_g": "3", "LtpCobId_g": "0"}, "OD-MS-03"))
    cfg.append(("ocan_od", {"SctCobId_g": "1409"}, "SctCobId_g is a restricted or free identifier"))
    cfg.append(("ocan_od", {"LtpCobId_g": "2047"}, "LtpCobId_g is a restricted or free identifier"))
    cfg.append(("ocan_od", {"SctCobId_g": "1000", "LtpCobId_g": "1000"}, "SctCobId_g and LtpCobId_g are equal"))
    # Transmission types: the bounds of 0 to 240, 254, 255 accepted, 241, 253 and 256 refused
    types = ("RpdoType_g", "TpdoType_g", "SctType_g", "LtpType_g")
    cfg.append(("ocan_od", {name: "240" for name in types}, None))
    for name in types:
        for value in ("241", "253"):
            cfg.append(("ocan_od", {name: value}, f"{name} is not a transmission type"))
        cfg.append(("ocan_od", {name: "256"}, f'override for generic "{name}" is out of bounds'))
    # ocan_sdo has no generics
    cfg.append(("ocan_sdo", {}, None))
    # ocan_pdo: every number of receive and of transmit PDOs from 0 to 4
    for n in range(0, 5):
        cfg.append(("ocan_pdo", {"NumRpdo_g": str(n), "NumTpdo_g": str(4 - n)}, None))
    cfg.append(("ocan_pdo", {"NumRpdo_g": "0", "NumTpdo_g": "0"}, None))
    cfg.append(("ocan_pdo", {}, None))
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
