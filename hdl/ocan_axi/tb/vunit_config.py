# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_axi network testbench (verification plan, section 2): the start-up and the reset
release in every configuration, the PDOs, the mailbox, the time, the bus monitoring and the error injection in the
configurations whose functions they need."""

CONFIGS = {
    "sel": {"BusAccess_g": "Selective"},
    "par": {"BusAccess_g": "Parallel", "TimePdos_g": False},
    "min": {"MinimalSet_g": True, "TimePdos_g": False},
    "errinj": {"ErrInjRegs_g": True},
    "auto": {"AutoEnable_g": True},
}

TESTS = {
    "test_startup": ["sel", "par", "min", "errinj", "auto"],
    "test_reset_release": ["sel", "par", "min", "errinj", "auto"],
    "test_pdo": ["sel", "par", "min"],
    "test_sdo_mailbox": ["sel", "par"],
    "test_time": ["sel"],
    "test_monitoring": ["sel", "par"],
    "test_errinj": ["errinj"],
}


def configure(lib):
    tb = lib.test_bench("ocan_axi_net_tb")
    for test, names in TESTS.items():
        for name in names:
            tb.test(test).add_config(name=name, generics=CONFIGS[name])
