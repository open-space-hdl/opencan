# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the ocan_od testbench (verification plan, section 2): every test case runs in the
default configuration; test_read_all and test_resets also with other power-on values; test_absent for every number
of PDOs and without the time PDOs, test_cob_copies and test_param_copies also with absent PDOs; test_app_unconnected with the inputs of the application port at their defaults;
test_minimal in the minimal set without and with the time PDOs."""

VALUES = {
    "DeviceType_g": "x\"80010191\"",
    "VendorId_g": "x\"800004D8\"",
    "ProductCode_g": "x\"0000CA11\"",
    "Revision_g": "x\"00010002\"",
    "SerialNumber_g": "x\"FFFFFFFF\"",
    "ProducerHbTime_g": 0,
    "MasterNodeId_g": 127,
    "MasterHbTime_g": 65535,
    "Bdefault_g": 1,
    "Ttoggle_g": 0,
    "Ntoggle_g": 255,
    "RpdoType_g": 0,
    "TpdoType_g": 240,
    "SctCobId_g": 0x0F0,
    "SctType_g": 255,
    "LtpCobId_g": 0x1F5,
    "LtpType_g": 1,
}

DIRECT = [
    "test_read_all", "test_absent", "test_access_types", "test_lengths", "test_states", "test_cob_id_rules",
    "test_types", "test_redundancy_objects", "test_outputs", "test_scet_objects", "test_same_cycle",
    "test_cob_copies", "test_param_copies", "test_error_register", "test_resets", "test_app_port",
    "test_app_timeout", "test_random",
]


def configure(lib):
    tb = lib.test_bench("ocan_od_tb")
    for test in DIRECT:
        tb.test(test).add_config(name="default", generics={})
    for test in ("test_read_all", "test_resets"):
        tb.test(test).add_config(name="values", generics=VALUES)
    absent = tb.test("test_absent")
    for n in range(0, 4):
        absent.add_config(name=f"rpdo{n}", generics={"NumRpdo_g": n})
        absent.add_config(name=f"tpdo{n}", generics={"NumTpdo_g": n})
    absent.add_config(name="notime", generics={"TimePdos_g": False})
    # Copies of absent objects have no effect (architecture, section 3.3)
    for test in ("test_cob_copies", "test_param_copies"):
        tb.test(test).add_config(name="rpdo1", generics={"NumRpdo_g": 1})
        tb.test(test).add_config(name="notime", generics={"TimePdos_g": False})
    tb.test("test_app_unconnected").add_config(name="unconnected", generics={"AppPort_g": False})
    minimal = tb.test("test_minimal")
    minimal.add_config(name="minimal", generics={"MinimalSet_g": True, "TimePdos_g": False})
    minimal.add_config(name="minimal_time", generics={"MinimalSet_g": True, "TimePdos_g": True, "NumRpdo_g": 3,
                                                      "NumTpdo_g": 3, "SctCobId_g": 0x0F0, "LtpCobId_g": 0x1F5})
