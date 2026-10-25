# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_core network testbench (verification plan, section 2): every test case in the
four configurations, which give BusAccess_g, MinimalSet_g and TimePdos_g each of their values; the configurations
with parallel bus access start on bus B."""

CONFIGS = {
    "sel_full": {"BusAccess_g": "Selective", "MinimalSet_g": False, "TimePdos_g": True},
    "par_full": {"BusAccess_g": "Parallel", "MinimalSet_g": False, "TimePdos_g": False, "Bdefault_g": 1},
    "sel_min": {"BusAccess_g": "Selective", "MinimalSet_g": True, "TimePdos_g": False},
    "par_min_time": {"BusAccess_g": "Parallel", "MinimalSet_g": True, "TimePdos_g": True, "NumRpdo_g": 3,
                     "NumTpdo_g": 3, "Bdefault_g": 1},
}

TESTS = [
    "test_startup", "test_configuration", "test_process_data", "test_time", "test_bus_monitoring",
    "test_nmt_resets", "test_node_id", "test_applicability", "test_connections",
]


def configure(lib):
    tb = lib.test_bench("ocan_core_net_tb")
    for test in TESTS:
        t = tb.test(test)
        for name, generics in CONFIGS.items():
            t.add_config(name=name, generics=generics)
