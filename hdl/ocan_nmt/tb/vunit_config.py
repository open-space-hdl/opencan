# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_nmt testbenches (verification plan, section 2): test_minimal_set runs in the
configuration minimal, all other tests in the default configuration (clause 6 slave)."""


def configure(lib):
    tb = lib.test_bench("ocan_nmt_tb")
    tb.test("test_minimal_set").add_config(name="minimal", generics={"MinimalSet_g": True})
