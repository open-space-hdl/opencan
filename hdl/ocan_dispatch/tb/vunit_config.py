# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_dispatch testbenches (verification plan, section 2): the direct testbench runs
test_generics for every number of PDOs and without the time PDOs, and test_sdo_absent without the SDO server; all
other tests run in the default configuration."""


def configure(lib):
    tb = lib.test_bench("ocan_dispatch_tb")
    gen = tb.test("test_generics")
    for n in range(0, 4):
        gen.add_config(name=f"rpdo{n}", generics={"NumRpdo_g": n})
        gen.add_config(name=f"tpdo{n}", generics={"NumTpdo_g": n})
    gen.add_config(name="no_time", generics={"TimePdos_g": False})
    gen.add_config(name="default", generics={})
    tb.test("test_sdo_absent").add_config(name="no_sdo", generics={"SdoServer_g": False})
