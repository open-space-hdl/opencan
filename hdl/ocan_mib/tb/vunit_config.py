# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_mib testbench (verification plan, section 2): the register tests, the reset and
the random test in every configuration; the test cases of the control, the flags, the PDOs, the mailbox and the time
in default; the error injection in errinj and gen_max; the absent PDOs in the configurations with fewer than four
PDOs. The configurations simulate every number of PDOs from 0 to 4 and both ends of every numeric generic."""

CONFIGS = {
    "default": {},
    "errinj": {"ErrInjRegs_g": True},
    "gen_max": {
        "BusAccess_g": "Parallel", "MinimalSet_g": True, "TimePdos_g": False, "AutoRecover_g": False,
        "NumRpdo_g": 1, "NumTpdo_g": 3, "FineBits_g": 0, "SyncStages_g": 4, "DominantLimit_g": 1023,
        "ClkFrequency_g": 2147483647, "AutoEnable_g": False, "Prescaler_g": 1023, "Tseg1_g": 31, "Tseg2_g": 15,
        "Sjw_g": 4, "ErrInjRegs_g": True, "Seed_g": 11,
    },
    "gen_min": {
        "NumRpdo_g": 3, "NumTpdo_g": 1, "FineBits_g": 24, "SyncStages_g": 2, "DominantLimit_g": 13,
        "ClkFrequency_g": 1000000, "Prescaler_g": 1, "Tseg1_g": 2, "Tseg2_g": 2, "Sjw_g": 1, "Seed_g": 13,
    },
    "n00": {"NumRpdo_g": 0, "NumTpdo_g": 0, "Seed_g": 17},
    "n22": {"NumRpdo_g": 2, "NumTpdo_g": 2, "Seed_g": 19},
}

ALL = ["test_registers", "test_reset_values", "test_reset", "test_random"]

DEFAULT = [
    "test_control", "test_bit_timing", "test_status", "test_flags", "test_irq", "test_counters", "test_rpdo",
    "test_tpdo", "test_mailbox", "test_mailbox_timeout", "test_mailbox_off", "test_time", "test_errinj_off",
]


def configure(lib):
    tb = lib.test_bench("ocan_mib_tb")
    for test in ALL:
        for name, generics in CONFIGS.items():
            tb.test(test).add_config(name=name, generics=generics)
    for test in DEFAULT:
        tb.test(test).add_config(name="default", generics=CONFIGS["default"])
    for name in ("errinj", "gen_max"):
        tb.test("test_errinj").add_config(name=name, generics=CONFIGS[name])
    for name in ("gen_max", "gen_min", "n00", "n22"):
        tb.test("test_absent_pdos").add_config(name=name, generics=CONFIGS[name])
