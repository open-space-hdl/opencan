# ocan_od: Verification Plan

## 1. Overview

`ocan_od` is verified in one bench, `direct`. The bench drives the access interface as `ocan_sdo` does, the NMT
state, the NODE-ID and the reset events as `ocan_nmt` does, the updates of `ocan_redundancy`, the local time of
`ocan_time`, the fault confinement state of the link and the test inputs, cycle by cycle. A responder plays the user
logic at the application port with configurable delays, results, missing and stray responses.

A reference model of the object dictionary, written from the specification, holds table 1 with its data types,
access types, NMT state rules and power-on values, applies the write rules of section 2.3 of the specification in
the order of section 2.3 of the architecture, and predicts in every cycle the answer of an access, every output to
the blocks, the error register and the events. It is independent of the copies and the decoder of the architecture:
it keeps one value per object and derives the protected behaviour (power-on value at a disagreement, the latch) from
the injected bits.

The integration with `ocan_sdo`, `ocan_dispatch` and the other blocks on the bus is tested in the network bench of
`ocan_core`. Tests observe the ports of `ocan_od` only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_od_tb` | `ocan_od_th` | `ocan_od`, `Clk` 40 MHz; drivers of the access interface, the NMT inputs, the block updates, `Stat_Scet`, `Stat_Ctoggle`, `Link_State` and the test inputs; a tick generator whose period the test sets; a responder of the application port; the reference model |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | `NumRpdo_g` = 4, `NumTpdo_g` = 4, `TimePdos_g` = true, `MinimalSet_g` = false, the defaults of the specification | All test cases |
| `values` | As `default`, with other power-on values: identity and device type with bit 31 set, `ProducerHbTime_g` 0, `MasterNodeId_g` 127, `MasterHbTime_g` 65535, `Bdefault_g` 1, `Ttoggle_g` 0, `Ntoggle_g` 255, transmission types 0, 240, 255, `SctCobId_g` 0F0h, `LtpCobId_g` 1F5h | Power-on values reach the objects and the outputs (TC-OD-01, TC-OD-15) |
| `rpdo0` to `rpdo3`, `tpdo0` to `tpdo3` | `NumRpdo_g`, `NumTpdo_g` = 0 to 3 | Every number of PDOs: absent objects (TC-OD-02) |
| `notime` | `TimePdos_g` = false | Without the time PDOs (TC-OD-02) |
| `minimal` | `MinimalSet_g` = true, `TimePdos_g` = false | Minimal set (TC-OD-19) |
| `minimal_time` | `MinimalSet_g` = true, `TimePdos_g` = true, `NumRpdo_g` = 3, `NumTpdo_g` = 3 | Minimal set of a node that keeps time (TC-OD-19) |

`NumRpdo_g`, `NumTpdo_g`, `TimePdos_g` and `MinimalSet_g` change the structure, so every value is simulated. The
negative elaboration of the PDO limit of the minimal set with the time PDOs (TC-OD-21: `MinimalSet_g` and
`TimePdos_g` with 4 PDOs) and of the generic checks of architecture section 9 runs in `lint/synth_check.py`.

Checkers that run in every test:

- `Rsp_Valid`, `Rsp_Data`, `Rsp_Len` and `Rsp_Abort` equal the reference in every cycle, and every access is answered
  within the bound of OD-IF-01;
- `Cfg_*`, `Stat_ErrReg`, `Err_ParamCopy` and `Err_AppTimeout` equal the reference in every cycle;
- the application port has at most one outstanding request, and `App_Req*` is stable while `App_ReqValid` is '1'.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_read_all` (TC-OD-01) | Configurations `default` and `values`: every object and sub-index of table 1 read, with its value, number of bytes and abort code 0; 1016h, 1017h, 2000h and the transmission types after writes | OD-OB-01, OD-OB-03, OD-OB-04, OD-IF-01 |
| `test_absent` (TC-OD-02) | Accesses to absent indices of 0000h to 0FFFh, 1000h to 1FFFh, 2000h to 2002h and A000h to FFFFh, to absent sub-indices of every object, and to the objects of absent PDOs in `rpdo0` to `rpdo3`, `tpdo0` to `tpdo3` and `notime` | OD-OB-02, OD-OB-01 |
| `test_access_types` (TC-OD-03) | A write of every ro and const object, a read of 2001h | OD-WR-01 |
| `test_lengths` (TC-OD-04) | A write of every writable object with 1 to 8 data bytes, and with the number not indicated (0): the size of the data type is taken, the bytes above it are ignored | OD-WR-02, OD-WR-09 |
| `test_states` (TC-OD-05) | Writes of every writable object in Initialisation, Pre-operational, Operational and Stopped | OD-WR-03, OD-IF-07 |
| `test_cob_id_rules` (TC-OD-06) | Every COB-ID: change while valid and while not valid; bits 29 and 30 of the PDOs and bit 30 of 1005h; bits 28 to 11; every restricted range of \[CiA301\] table 40 and the free ranges of clause 9.5a at both ends and inside; a duplicate of every other valid entry, also through the NODE-ID dependent identifiers; the abort order of architecture section 2.3 with several failing checks | OD-WR-04, OD-WR-05, OD-WR-09 |
| `test_types` (TC-OD-07) | Every value 0 to 255 written to every transmission type | OD-WR-06 |
| `test_redundancy_objects` (TC-OD-08) | 1016h sub-index 01h with reserved bits, NODE-ID 0, 1, 127, 128 and time 0; 2000h sub-index 01h with every value 0 to 255; Ttoggle and Ntoggle with 0 and 255; a write of Ctoggle: value and event; a read of Ctoggle from `Stat_Ctoggle` | OD-WR-07, OD-WR-08, OD-IF-04, OD-OB-04 |
| `test_outputs` (TC-OD-09) | Every accepted write at its output in the next cycle and never before; the COB-ID table in both copies, the master heartbeat entry, the identifiers that follow the NODE-ID, SYNC always valid | OD-IF-02, OD-IF-03, OD-IF-04, OD-IF-05, OD-IF-06, OD-WR-09 |
| `test_scet_objects` (TC-OD-10) | Writes of 2001h with random values: `Cfg_SetValid` and `Cfg_SetScet` one cycle later; reads of 2002h return `Stat_Scet` of the cycle of the access, byte order of OD-OB-03 | OD-IF-05, OD-OB-04, OD-OB-03 |
| `test_same_cycle` (TC-OD-11) | A write of Bdefault in the cycle of `Upd_Valid`; a reset application and a reset communication in the cycle of an access; a write of a parameter in the cycle of an injected disagreement of its copies | OD-WR-10, OD-PR-03 |
| `test_cob_copies` (TC-OD-12) | Every bit of every COB-ID copy inverted through the test inputs: the copies at `Cfg_CobId` and `Cfg_CobIdCopy` differ until a write or a reset communication; a read returns the first copy; the lock rule with bit 31 disagreeing; bit 0 of 1001h while a disagreement persists. Configurations `rpdo1` and `notime` in addition: a flip of an entry of an absent object has no effect, both copies stay 0, no event | OD-PR-01, OD-PR-02, OD-PR-04, OD-ER-01, OD-IF-12 |
| `test_param_copies` (TC-OD-13) | Every bit of every other protected parameter inverted in copy A and in copy B: the power-on value at the output in the same cycle, `Err_ParamCopy`, bit 7 and bit 0 of 1001h until the next reset communication, both copies repaired in the next cycle; Bdefault after an update by `ocan_redundancy`. Configurations `rpdo1` and `notime` in addition: a flip of the transmission type of an absent PDO has no effect, no `Err_ParamCopy` | OD-PR-01, OD-PR-03, OD-PR-04, OD-ER-01, OD-IF-10, OD-IF-12 |
| `test_error_register` (TC-OD-14) | `Link_State` error active, error passive and bus off, with and without a COB-ID disagreement and the latch | OD-ER-01, OD-IF-08 |
| `test_resets` (TC-OD-15) | Configurations `default` and `values`: after writes of every writable object, `Rst`, a reset application (2000h kept) and a reset communication (the communication profile area to its power-on values with the NODE-ID of the new sample, bit 7 cleared, an outstanding request of the application port ended without an answer, also when the response of the user logic comes in the cycle of the reset) | OD-RS-01, OD-RS-02, OD-RS-03, OD-IF-07 |
| `test_app_port` (TC-OD-16) | Accesses to 2002h, 2003h, 9FFFh and A000h; reads and writes passed to the user logic with their data; responses with data, number of bytes and abort codes after 0 to 1000 cycles; no access taken while a request is outstanding; stray responses before, during and after a request ignored | OD-AP-01, OD-AP-02, OD-IF-09, OD-IF-01 |
| `test_app_timeout` (TC-OD-17) | No `App_ReqReady`, and no response after a taken request: 0800 0000h and `Err_AppTimeout` 256 ticks after the access, the request withdrawn; a late response ignored; the next access is served | OD-AP-03, OD-IF-10, OD-IF-11 |
| `test_app_unconnected` (TC-OD-18) | The inputs of the application port at their default values: every access to 2003h to 9FFFh ends with 0602 0000h three cycles after the access | OD-AP-04 |
| `test_minimal` (TC-OD-19) | Configurations `minimal` and `minimal_time`: no access taken, no request of the application port; the COB-ID table, the transmission types and the other outputs of OD-MS-02 and OD-MS-03; Bdefault with its update and an injected disagreement; the error register | OD-MS-01, OD-MS-02, OD-MS-03, OD-MS-04 |
| `test_random` (TC-OD-20) | 20000 random accesses (existing and absent objects, valid and invalid values, every length, every NMT state) with random block updates, NODE-ID changes, resets and injected disagreements, compared with the reference in every cycle | OD-IF-01, OD-OB-01, OD-WR-01 to OD-WR-10, OD-PR-03 |
| TC-OD-21 (`lint/synth_check.py`) | Negative elaboration: `MinimalSet_g` and `TimePdos_g` with `NumRpdo_g` = 4 and with `NumTpdo_g` = 4 are refused, with 3 and 3 accepted; `SctCobId_g` and `LtpCobId_g` restricted, free or equal are refused (architecture section 9) | OD-MS-05 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| OD-IF-01 | TC-OD-01, TC-OD-16, TC-OD-20 |
| OD-IF-02 | TC-OD-09 |
| OD-IF-03 | TC-OD-09 |
| OD-IF-04 | TC-OD-08, TC-OD-09 |
| OD-IF-05 | TC-OD-09, TC-OD-10 |
| OD-IF-06 | TC-OD-09 |
| OD-IF-07 | TC-OD-05, TC-OD-15 |
| OD-IF-08 | TC-OD-14 |
| OD-IF-09 | TC-OD-16 |
| OD-IF-10 | TC-OD-13, TC-OD-17 |
| OD-IF-11 | TC-OD-17 |
| OD-IF-12 | TC-OD-12, TC-OD-13 |
| OD-OB-01 | TC-OD-01, TC-OD-02, TC-OD-20 |
| OD-OB-02 | TC-OD-02 |
| OD-OB-03 | TC-OD-01, TC-OD-10 |
| OD-OB-04 | TC-OD-01, TC-OD-08, TC-OD-10 |
| OD-WR-01 | TC-OD-03, TC-OD-20 |
| OD-WR-02 | TC-OD-04, TC-OD-20 |
| OD-WR-03 | TC-OD-05, TC-OD-20 |
| OD-WR-04 | TC-OD-06, TC-OD-20 |
| OD-WR-05 | TC-OD-06, TC-OD-20 |
| OD-WR-06 | TC-OD-07, TC-OD-20 |
| OD-WR-07 | TC-OD-08, TC-OD-20 |
| OD-WR-08 | TC-OD-08, TC-OD-20 |
| OD-WR-09 | TC-OD-04, TC-OD-06, TC-OD-09, TC-OD-20 |
| OD-WR-10 | TC-OD-11, TC-OD-20 |
| OD-PR-01 | TC-OD-12, TC-OD-13 |
| OD-PR-02 | TC-OD-12 |
| OD-PR-03 | TC-OD-11, TC-OD-13, TC-OD-20 |
| OD-PR-04 | TC-OD-12, TC-OD-13 |
| OD-ER-01 | TC-OD-12, TC-OD-13, TC-OD-14 |
| OD-RS-01 | TC-OD-15 |
| OD-RS-02 | TC-OD-15 |
| OD-RS-03 | TC-OD-15 |
| OD-AP-01 | TC-OD-16 |
| OD-AP-02 | TC-OD-16 |
| OD-AP-03 | TC-OD-17 |
| OD-AP-04 | TC-OD-18 |
| OD-MS-01 | TC-OD-19 |
| OD-MS-02 | TC-OD-19 |
| OD-MS-03 | TC-OD-19 |
| OD-MS-04 | TC-OD-19 |
| OD-MS-05 | TC-OD-21 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| Absent objects and sub-indices | TC-OD-02 |
| Every abort code of the write rules, and their order | TC-OD-03 to TC-OD-08 |
| COB-ID copies that disagree | TC-OD-12 |
| Other parameter copies that disagree | TC-OD-13 |
| Missing, late and stray responses of the user logic | TC-OD-16, TC-OD-17 |
| Generics outside the rules of architecture section 9 and the PDO limit of the minimal set | TC-OD-21 |

A deliberate fault of the RTL for every write rule, every abort code, the compare and the repair of the copies, the
latch, the precedence rules and the time-out of the application port is simulated with the tests that must detect
it (verification report, section 4).

## 6. Input space covered by the directed tests

| Input | Requirements | Classes and test cases |
| --- | --- | --- |
| Index | OD-OB-02, OD-AP-01 | Every object of table 1; the borders 0FFFh, 1000h, 1FFFh, 2000h, 2002h, 2003h, 9FFFh, A000h, FFFFh (TC-OD-02, TC-OD-16) |
| Number of data bytes | OD-WR-02 | 1 to 8 for every writable object (TC-OD-04) |
| NMT state | OD-WR-03 | Initialisation, Pre-operational, Operational, Stopped (TC-OD-05) |
| COB-ID | OD-WR-04, OD-WR-05 | Each restricted and free range at both ends and inside, neighbours outside, duplicates of every entry (TC-OD-06) |
| Transmission type | OD-WR-06 | Every value 0 to 255 (TC-OD-07) |
| Protected bits | OD-PR-02, OD-PR-03 | Every bit of both copies (TC-OD-12, TC-OD-13) |
| Response delay of the user logic | OD-AP-01, OD-AP-03 | 0, 1, random up to 1000 cycles, 255 and 256 ticks, none (TC-OD-16, TC-OD-17) |

## 7. Not verified at the ports

- The `when others` branch of the application port cannot be reached from the ports; it recovers only when the
  synthesis tool implements the state machine safely (protection scope of the user guide) and is covered by design
  review.
- The compare `TmoCnt` >= 255 differs from a compare with = only after an upset of the count, which the ports cannot
  inject; covered by design review.
- An upset of the same bit in both copies of a parameter is a double fault and changes the parameter without an
  event; the protection of OD-2 is designed against single upsets (clause 6.10d).
