# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_time testbenches (verification plan, section 2): test_counter_rate runs in every
configuration of the direct bench, test_long_run_rate in f40m and f1m, test_sync_sample and test_tx_on_request in
default and f1m (where the local time advances in every cycle), the format and wrap tests in default and in every
width of the fine time (fine0 to fine23 at the lower bound of the clock frequency, so that a fine time unit is at most
10^6 cycles), every other direct test in default; the network bench in net."""

CONFIGS = {
    "default": {"FineBits_g": 24, "ClkFrequency_g": 100000000},
    "f40m": {"FineBits_g": 24, "ClkFrequency_g": 40000000},
    "f1m": {"FineBits_g": 24, "ClkFrequency_g": 1000000},
    "fmax": {"FineBits_g": 24, "ClkFrequency_g": 2147483647},
}
FINE = {f"fine{n}": {"FineBits_g": n, "ClkFrequency_g": 1000000} for n in range(0, 24)}


def configure(lib):
    tb = lib.test_bench("ocan_time_tb")
    rate = tb.test("test_counter_rate")
    for name, generics in {**CONFIGS, **FINE}.items():
        rate.add_config(name=name, generics=generics)
    long_run = tb.test("test_long_run_rate")
    for name in ("f40m", "f1m"):
        long_run.add_config(name=name, generics=CONFIGS[name])
    for test in ("test_sync_sample", "test_tx_on_request"):
        t = tb.test(test)
        for name in ("default", "f1m"):
            t.add_config(name=name, generics=CONFIGS[name])
    for test in ("test_coarse_wrap", "test_rx_format", "test_tx_format"):
        t = tb.test(test)
        t.add_config(name="default", generics=CONFIGS["default"])
        for name, generics in FINE.items():
            t.add_config(name=name, generics=generics)
    net = lib.get_test_benches("*ocan_time_net_tb", allow_empty=True)
    for ntb in net:
        ntb.test("test_net_time").add_config(name="net", generics={})
