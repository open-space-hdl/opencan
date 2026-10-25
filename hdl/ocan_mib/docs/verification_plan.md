# ocan_mib: Verification Plan

## 1. Overview

The testbench `ocan_mib_tb` accesses the registers through the AXI-Lite VVC of UVVM and drives the inputs from the
core (status, events, PDO data, local time) cycle by cycle. A model of the application port of `ocan_od` (OD-AP-01
to OD-AP-03) presents the requests to the mailbox, takes the responses and ends a request with `Err_AppTimeout` after
a time-out that the test sets. A reference model of the register file, written from the specification, predicts in
every clock cycle every output towards the core (`Ctrl_*`, `Cfg_*`, `Tpdo_*`, `App_ReqReady`, `App_Rsp*`,
`Time_Req`, `ErrInj_*`) and the interrupt, and the word and the response of every read; it is independent of the
registers of the architecture. The model takes the timing of the AXI4-Lite slave from the ports: a write acts in the
clock cycle in which `BValid` rises, a read samples the clock cycle after the read address handshake.

Tests observe the ports of `ocan_mib` only. Simulators: GHDL (regression, CI) and QuestaSim (code coverage); VUnit
with UVVM, test end `ocanTestEnd`.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_mib_tb` | `ocan_mib_th` | `ocan_mib`, `Clk` 50 MHz; the AXI-Lite VVC (`ocan_tb_axilite_master`); drivers of every input from the core; the model of the application port; the reference model |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | the defaults | All test cases |
| `errinj` | `ErrInjRegs_g` = true | Error injection (TC-MB-16) |
| `gen_max` | `BusAccess_g` = "Parallel", `MinimalSet_g` = true, `TimePdos_g` = false, `AutoRecover_g` = false, `NumRpdo_g` = 1, `NumTpdo_g` = 3, `FineBits_g` = 0, `SyncStages_g` = 4, `DominantLimit_g` = 1023, `ClkFrequency_g` = 2147483647, `AutoEnable_g` = false, `Prescaler_g` = 1023, `Tseg1_g` = 31, `Tseg2_g` = 15, `Sjw_g` = 4, `ErrInjRegs_g` = true | The other value of every boolean and the upper bound of every numeric generic |
| `gen_min` | `NumRpdo_g` = 3, `NumTpdo_g` = 1, `FineBits_g` = 24, `SyncStages_g` = 2, `DominantLimit_g` = 13, `ClkFrequency_g` = 1000000, `Prescaler_g` = 1, `Tseg1_g` = 2, `Tseg2_g` = 2, `Sjw_g` = 1 | The lower bound of every numeric generic |
| `n00`, `n22` | `NumRpdo_g` and `NumTpdo_g` = 0 and 0, 2 and 2 | With `default`, `gen_max` and `gen_min` every number of PDOs from 0 to 4 |

The test cases of TC-MB-01, TC-MB-02, TC-MB-18 and TC-MB-19 run in every configuration.

Checkers that run in every test:

- every output towards the core and `Irq` equals the reference model in every clock cycle;
- every read word equals the word of the reference model, and every read and write response is OKAY;
- the test end fails on an unexpected alert and on an expected alert that did not occur.

## 3. Test cases

| Test | Description | Requirements |
| --- | --- | --- |
| `test_registers` (TC-MB-01) | ID, GENERICS, DOMINANT_LIMIT and CLK_FREQUENCY read the values of the configuration (the ID also equals `RegMapId_c` of `ocan_regs_pkg`); every address of the 9-bit space is read; address-dependent patterns written to the constant and status registers and to every unused address change nothing; a write with the byte strobes "0000" writes the whole word | MB-IF-01, MB-ID-01, MB-ID-02 |
| `test_reset_values` (TC-MB-02) | After the reset: `Ctrl_Enable` = `AutoEnable_g`, the bit timing of the generics, the application port as with its default values; every register reads its reset value | MB-CT-01, MB-CT-03, MB-AP-04, MB-RS-01 |
| `test_control` (TC-MB-03) | ENABLE and APP_ENABLE read back and drive `Ctrl_Enable`; RECOVER, REENABLE_A and REENABLE_B pulse `Ctrl_Recover`, `Ctrl_Reenable(0)` and `Ctrl_Reenable(1)` for one clock cycle and read zero; the undefined bits read zero | MB-IF-02, MB-CT-01, MB-CT-02 |
| `test_bit_timing` (TC-MB-04) | While disabled: the bounds of Tseg1 (2, 17, 31), Tseg2 (2, 3, 15) and every Sjw up to min(4, Tseg2) with the prescaler 0 and 1023 are taken and read back, the other bits read zero; Tseg1 0 and 1, Tseg2 0 and 1, Sjw 0, 5, 7 and Sjw above Tseg2 leave BIT_TIMING unchanged and set CFG_REFUSED; a valid value while enabled is refused | MB-CT-03, MB-CT-04 |
| `test_status` (TC-MB-05) | NODE, REDUNDANCY, LINK_A, LINK_B, COB_ID_MISMATCH and TPDO_STATUS with random inputs, also inputs that change in every clock cycle during the reads | MB-ST-01, MB-ST-02, MB-ST-03, MB-ST-04 |
| `test_flags` (TC-MB-06) | Every flag of EVENTS, PDO_EVENTS, ERRORS and LINK_ERRORS is set by its input alone, a write of zero leaves it set, a write of one clears it; an event two clock cycles before to two after the clearing write, and in the clock cycle of the write: the flag stays set | MB-FL-01 |
| `test_irq` (TC-MB-07) | For every flag: no interrupt without its enable or with all other enables, an interrupt with its enable, IRQ_STATUS names its register, the clear ends the interrupt; CFG_REFUSED and APP_REQUEST raise it; with several flags the interrupt lasts until the last enabled flag is cleared | MB-IF-03, MB-FL-02, MB-FL-03 |
| `test_counters` (TC-MB-08) | Every error counter of both controllers counts its own events only; a read does not clear; a write clears the counters of its register only, also a write of zero; 300 events in back-to-back clock cycles saturate every counter at 255; an event in the clock cycle of the clearing write counts after the clearing | MB-CN-01 |
| `test_rpdo` (TC-MB-09) | RPDOn_HI and RPDOn_LO with random data, also data that change between the two reads and in every clock cycle: both words come from the clock cycle of the read of HI; a repeated read of LO returns the same word | MB-PD-01 |
| `test_tpdo` (TC-MB-10) | TPDOn_HI and TPDOn_LO read back and do not change `Tpdo_Data`; UPDATE copies both words in one clock cycle without a request; REQUEST copies them and pulses `Tpdo_Req` in the same clock cycle; several PDOs in one write; TPDO_CONTROL reads zero | MB-PD-02 |
| `test_absent_pdos` (TC-MB-11) | In `gen_max`, `gen_min`, `n00` and `n22`: the registers of the PDOs above `NumRpdo_g` and `NumTpdo_g` read zero, writes to them have no effect, UPDATE and REQUEST of an absent PDO change nothing | MB-PD-03 |
| `test_mailbox` (TC-MB-12) | Eight requests (reads and writes, indices, sub-indices, data, lengths): the request is taken at once, APP_REQ, APP_REQ_HI and APP_REQ_LO hold it, PENDING and APP_REQUEST are set and `App_ReqReady` is '0'; SEND answers with APP_RSP_HI, APP_RSP_LO, APP_RSP_LEN and APP_RSP_ABORT (success and abort codes) and clears PENDING; SEND without a request has no effect | MB-AP-01, MB-AP-02 |
| `test_mailbox_timeout` (TC-MB-13) | `Err_AppTimeout` of the port model clears PENDING and sets APP_TIMEOUT, a late SEND has no effect; SEND three clock cycles before to three after the time-out; APP_ENABLE cleared while a request is pending: the port answers 0602 0000h and PENDING is cleared | MB-AP-03, MB-AP-04 |
| `test_mailbox_off` (TC-MB-14) | APP_ENABLE = '0' with all ones in the response registers: every request ends with 0602 0000h, no data, no length; nothing in the mailbox, no APP_REQUEST | MB-AP-04 |
| `test_time` (TC-MB-15) | TIME_COARSE and TIME_FINE with a time that changes between the reads and in every clock cycle: TIME_FINE returns the fine time of the clock cycle of the read of TIME_COARSE; REQUEST pulses `Time_Req` for one clock cycle; a write without bit 0 has no effect | MB-TM-01, MB-TM-02 |
| `test_errinj` (TC-MB-16) | In `errinj` and `gen_max`: both targets with every window 0 to 31 in w0 and another window in w1, address-dependent masks; ERRINJ_SELECT and the masks read back; INJECT drives both masks into their windows with the valid input of the target for one clock cycle (bits beyond the width ignored); a common-mode command on bit 0 of copy A and bit 279 of copy B; the OR of both masks in one window; LINK_TX_DOMINANT as a level, LINK_STOP_FLIP_A and LINK_STOP_FLIP_B for one clock cycle | MB-EI-01, MB-EI-02 |
| `test_errinj_off` (TC-MB-17) | `ErrInjRegs_g` = false: the error injection registers read zero after writes of all ones, and the injection inputs of the core stay '0' | MB-EI-03 |
| `test_reset` (TC-MB-18) | A reset with set flags, enables, counters, snapshots, transmit data, a pending request and an injection level: every register reads its reset value, `Irq`, `Tpdo_Data` and the injection inputs are '0' | MB-RS-01 |
| `test_random` (TC-MB-19) | 600 random reads and writes of every address, random events, status and requests of the application port, SENDs at random times; the reference model checks every clock cycle | MB-IF-01, MB-IF-02, MB-FL-01, MB-CN-01, MB-AP-01, MB-AP-02 |
| TC-MB-20 (`lint/synth_check.py`) | GHDL synthesis of `ocan_mib` in the configurations of section 2 without an inferred latch; `BusAccess_g` other than "Selective" and "Parallel", and `Sjw_g` above `Tseg2_g`, stop the elaboration with the message of the module | MB-IF-01 |
| TC-MB-21 (`tools/regmap.py --check`) | The VHDL package, the register map and the C header match `ocan_regs.yml`; the CI fails on a stale output | MB-RG-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| MB-IF-01 | TC-MB-01, TC-MB-19, TC-MB-20 |
| MB-IF-02 | TC-MB-03, TC-MB-19 |
| MB-IF-03 | TC-MB-07 |
| MB-ID-01 | TC-MB-01 |
| MB-ID-02 | TC-MB-01 |
| MB-CT-01 | TC-MB-02, TC-MB-03 |
| MB-CT-02 | TC-MB-03 |
| MB-CT-03 | TC-MB-02, TC-MB-04 |
| MB-CT-04 | TC-MB-04 |
| MB-ST-01 | TC-MB-05 |
| MB-ST-02 | TC-MB-05 |
| MB-ST-03 | TC-MB-05 |
| MB-ST-04 | TC-MB-05 |
| MB-FL-01 | TC-MB-06, TC-MB-19 |
| MB-FL-02 | TC-MB-07 |
| MB-FL-03 | TC-MB-07 |
| MB-CN-01 | TC-MB-08, TC-MB-19 |
| MB-PD-01 | TC-MB-09 |
| MB-PD-02 | TC-MB-10 |
| MB-PD-03 | TC-MB-11 |
| MB-AP-01 | TC-MB-12, TC-MB-19 |
| MB-AP-02 | TC-MB-12, TC-MB-19 |
| MB-AP-03 | TC-MB-13 |
| MB-AP-04 | TC-MB-02, TC-MB-13, TC-MB-14 |
| MB-TM-01 | TC-MB-15 |
| MB-TM-02 | TC-MB-15 |
| MB-EI-01 | TC-MB-16 |
| MB-EI-02 | TC-MB-16 |
| MB-EI-03 | TC-MB-17 |
| MB-RS-01 | TC-MB-02, TC-MB-18 |
| MB-RG-01 | TC-MB-21 |
