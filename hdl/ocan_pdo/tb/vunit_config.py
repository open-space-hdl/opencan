# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_pdo testbenches (verification plan, section 2): every test case of the direct
bench in default; test_absent and test_random also in n00, n13, n22 and n31, so that every number of receive and
transmit PDOs from 0 to 4 is simulated; the network bench in net and net_minimal."""

CONFIGS = {
    "default": {"NumRpdo_g": 4, "NumTpdo_g": 4},
    "n00": {"NumRpdo_g": 0, "NumTpdo_g": 0},
    "n13": {"NumRpdo_g": 1, "NumTpdo_g": 3},
    "n22": {"NumRpdo_g": 2, "NumTpdo_g": 2},
    "n31": {"NumRpdo_g": 3, "NumTpdo_g": 1},
}

DIRECT = [
    "test_rpdo_event", "test_rpdo_length", "test_rpdo_sync", "test_rpdo_reserved", "test_sync", "test_tpdo_cyclic",
    "test_tpdo_acyclic", "test_tpdo_event", "test_tpdo_busy", "test_tpdo_handshake", "test_nmt", "test_reset_comm",
    "test_reset", "test_back_to_back",
]


def configure(lib):
    tb = lib.test_bench("ocan_pdo_tb")
    for test in DIRECT:
        tb.test(test).add_config(name="default", generics=CONFIGS["default"])
    for test in ("test_random", "test_absent"):
        t = tb.test(test)
        for name, generics in CONFIGS.items():
            t.add_config(name=name, generics=generics)
    net = lib.get_test_benches("*ocan_pdo_net_tb", allow_empty=True)
    for ntb in net:
        ntb.test("test_net_pdo").add_config(name="net", generics={"MinimalSet_g": False})
        ntb.test("test_net_minimal").add_config(name="net_minimal", generics={"MinimalSet_g": True})
