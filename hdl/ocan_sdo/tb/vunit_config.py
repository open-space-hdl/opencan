# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_sdo testbenches (verification plan, section 2): every test case of the direct
bench in default (ocan_sdo has no generics); the network bench in net."""

DIRECT = [
    "test_expedited_download", "test_segmented_download", "test_download_sizes", "test_expedited_upload",
    "test_segmented_upload", "test_toggle", "test_command_errors", "test_client_abort", "test_new_initiate",
    "test_dlc", "test_busy", "test_reply_handshake", "test_nmt", "test_access_timing", "test_reset", "test_random",
]


def configure(lib):
    tb = lib.test_bench("ocan_sdo_tb")
    for test in DIRECT:
        tb.test(test).add_config(name="default", generics={})
    net = lib.get_test_benches("*ocan_sdo_net_tb", allow_empty=True)
    for ntb in net:
        ntb.test("test_net_sdo").add_config(name="net", generics={})
