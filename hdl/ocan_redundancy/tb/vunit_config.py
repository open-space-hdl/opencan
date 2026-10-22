# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_redundancy testbenches (verification plan, section 2): test_startup runs in the
default configuration and in minimal, test_minimal_set in minimal only, every other direct test in the default
configuration; the network testbench runs with selective (net_sel) and parallel (net_par) bus access, the master on
the other bus during a bus selection with parallel bus access only, the NMT race with selective bus access only;
test_preop_again and test_events_every_cycle also run in minimal."""


def configure(lib):
    tb = lib.test_bench("ocan_redundancy_tb")
    start = tb.test("test_startup")
    start.add_config(name="default", generics={})
    start.add_config(name="minimal", generics={"MinimalSet_g": True})
    tb.test("test_minimal_set").add_config(name="minimal", generics={"MinimalSet_g": True})
    for test in ("test_preop_again", "test_events_every_cycle"):
        tb.test(test).add_config(name="default", generics={})
        tb.test(test).add_config(name="minimal", generics={"MinimalSet_g": True})
    net = lib.get_test_benches("*ocan_redundancy_net_tb", allow_empty=True)
    for ntb in net:
        for test in ("test_net_switch", "test_net_bus_faults"):
            t = ntb.test(test)
            t.add_config(name="net_sel", generics={"Parallel_g": False})
            t.add_config(name="net_par", generics={"Parallel_g": True})
        ntb.test("test_net_master_other_bus").add_config(name="net_par", generics={"Parallel_g": True})
        ntb.test("test_net_nmt_race").add_config(name="net_sel", generics={"Parallel_g": False})
