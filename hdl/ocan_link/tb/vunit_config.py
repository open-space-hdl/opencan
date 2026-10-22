# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_link testbench (verification plan, section 2): every test runs in the
configurations of the plan."""

CONFIGS = {
    "sel": {"BusAccess_g": "Selective"},
    "par": {"BusAccess_g": "Parallel"},
    "sel_norec": {"BusAccess_g": "Selective", "AutoRecover_g": False},
    "sync3": {"BusAccess_g": "Selective", "SyncStages_g": 3},
    "sync4": {"BusAccess_g": "Selective", "SyncStages_g": 4},
    "domlim13": {"BusAccess_g": "Selective", "DominantLimit_g": 13},
    "domlim1023": {"BusAccess_g": "Selective", "DominantLimit_g": 1023},
}

TESTS = {
    "test_frames": ["sel", "par"],
    "test_listen_only": ["par"],
    "test_same_cycle": ["par"],
    "test_bit_rates": ["sel", "par"],
    "test_bit_timing": ["sel"],
    "test_switch_idle": ["sel", "par"],
    "test_switch_pending": ["sel", "par"],
    "test_switch_request_change": ["sel", "par"],
    "test_disable": ["sel", "par"],
    "test_arbitration": ["sel"],
    "test_error_frames": ["sel", "par"],
    "test_recover_request": ["sel_norec"],
    "test_counts_kept": ["sel"],
    "test_dominant_timeout": ["sel", "par", "domlim13", "domlim1023"],
    "test_dominant_inactive": ["par"],
    "test_dominant_margin": ["sel"],
    "test_stop_upset": ["sel", "par"],
    "test_back_to_back": ["sel", "par"],
    "test_sync_stages": ["sync3", "sync4"],
}


def configure(lib):
    tb = lib.test_bench("ocan_link_tb")
    for test, names in TESTS.items():
        for name in names:
            tb.test(test).add_config(name=name, generics=CONFIGS[name])
