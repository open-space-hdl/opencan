# ocan_od: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_od*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_od_tb` | 20 | 36 | 36 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): every test case runs in
`default`; TC-OD-01 and TC-OD-15 also in `values`; TC-OD-02 in `rpdo0` to `rpdo3`, `tpdo0` to `tpdo3` and
`notime`; TC-OD-12 and TC-OD-13 also in `rpdo1` and `notime`; TC-OD-18 in `unconnected`; TC-OD-19 in `minimal` and
`minimal_time`. In every cycle the reference model predicted the answer of the access interface (`Rsp_Valid`,
`Rsp_Data`, `Rsp_Len`, `Rsp_Abort`), `Acc_Ready`, every output to the blocks (both copies of the COB-ID table,
the heartbeat times, Bdefault, Ttoggle, Ntoggle, the transmission types, the Ctoggle and Local SCET Set events), the
error register, both events and the request of the application port, and no output differed from it. The model
holds table 1 of the specification and the write rules, and keeps the two copies of the protected parameters as the
specification defines them (OD-PR-01 to OD-PR-03).

TC-OD-21, the negative elaboration of OD-MS-03, OD-MS-05 and of the generic checks, runs in `lint/synth_check.py`
(section 3).

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Measured values

| Item | Value |
| --- | --- |
| Access to an object of table 1 to the answer | 1 clock cycle (every access of every test) |
| Accepted write to the new value at the outputs | 1 clock cycle (TC-OD-09) |
| Access to an object of the user logic to `App_ReqValid` | 1 clock cycle (TC-OD-16) |
| Response of the user logic to the answer | 1 clock cycle, for responses 0 to 1000 cycles after the request (TC-OD-16) |
| Unconnected application port: access to the answer 0602 0000h | 3 clock cycles (TC-OD-18) |
| No response of the user logic | 0800 0000h and `Err_AppTimeout` at the 256th tick after the access; a request without `App_ReqReady` withdrawn; a late response ignored (TC-OD-17) |
| Copies of a parameter that disagree | The power-on value at the output and `Err_ParamCopy` in the cycle of the disagreement, both copies repaired in the next cycle, bit 7 of 1001h until the next reset communication, for every bit of both copies (TC-OD-13) |
| Copies of a COB-ID entry that disagree | Both copies at `Cfg_CobId` and `Cfg_CobIdCopy` until a write or a reset communication, bit 0 of 1001h meanwhile, for every bit of both copies (TC-OD-12) |
| Bits of absent PDOs | No effect: no event, the entries of the COB-ID table constant 0 (TC-OD-12, TC-OD-13 in `rpdo1` and `notime`) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `MinimalSet_g` | true, false | both | both |
| `NumRpdo_g`, `NumTpdo_g` | 0 to 4; at most 3 with `MinimalSet_g` and `TimePdos_g` | 0 to 4; 3 in `minimal_time` | 0 to 4; 4 with `MinimalSet_g` and `TimePdos_g` rejected (TC-OD-21) |
| `TimePdos_g` | true, false | both | both |
| 32-bit values (`DeviceType_g`, identity) | 32 bits | 0 and values with bit 31 set (`values`) | 0 |
| `ProducerHbTime_g`, `MasterHbTime_g` | 0 to 65535 | 1000, 1500, 0, 65535 | the defaults, 65535 and 0 |
| `MasterNodeId_g` | 0 to 127 | 1, 127 | 1, 127 |
| `Bdefault_g` | 0, 1 | both | both |
| `Ttoggle_g`, `Ntoggle_g` | 0 to 255 | 1, 3, 0, 255 | the defaults, 255 and 0 |
| `RpdoType_g`, `TpdoType_g`, `SctType_g`, `LtpType_g` | 0 to 240, 254, 255 | 254, 0, 240, 255, 1 | 254, 255, 0, 240; 241, 253 and 256 rejected (TC-OD-21) |
| `SctCobId_g`, `LtpCobId_g` | 0 to 2047, not restricted, not free, not equal; not 0 with `MinimalSet_g` and `TimePdos_g` | 0, 0F0h, 1F5h | 0, 0F0h, 1F5h, 4FFh, 500h; 581h, 7FFh, two equal values and 0 with `MinimalSet_g` and `TimePdos_g` rejected (TC-OD-21) |

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, 52 deliberate faults of
the RTL were each simulated with the tests that must detect them, and every one made a test fail:

| Fault | Detected by |
| --- | --- |
| No object check | TC-OD-02 |
| No sub-index check | TC-OD-02 |
| Write of a read-only object taken | TC-OD-03 |
| Read of a write-only object taken | TC-OD-03 |
| Too many bytes taken | TC-OD-04 |
| Too few bytes taken | TC-OD-04 |
| Number of bytes 0 refused | TC-OD-04 |
| COB-IDs written outside Pre-operational | TC-OD-05 |
| Parameters written in Stopped and Initialisation | TC-OD-05 |
| No lock of a valid COB-ID | TC-OD-06 |
| Lock rule from copy A only | TC-OD-12 |
| Remote frames allowed | TC-OD-06 |
| 29-bit identifiers allowed | TC-OD-06 |
| Bits 28 to 11 not checked | TC-OD-06 |
| Restricted identifiers of PDOs allowed | TC-OD-06 |
| Restricted range 6E0h to 6FFh from 6E1h | TC-OD-06 |
| Restricted range up to 07Eh | TC-OD-06 |
| Restricted range 701h to 77Fh from 702h | TC-OD-06 |
| No duplicate check | TC-OD-06 |
| SYNC producer allowed | TC-OD-06 |
| Transmission type 241 taken | TC-OD-07 |
| Transmission type 253 taken | TC-OD-07 |
| Reserved bits of 1016h taken | TC-OD-08 |
| NODE-ID 128 in 1016h taken | TC-OD-08 |
| Bdefault 2 taken | TC-OD-08 |
| An access in the cycle of a reset takes effect | TC-OD-11 |
| The update of Bdefault wins over a write | TC-OD-11 |
| No repair of 1017h | TC-OD-13 |
| Copy A at the output while the copies disagree | TC-OD-13 |
| No compare of the transmission types | TC-OD-13 |
| Copies of absent transmission types compared | TC-OD-13 |
| Latch not set | TC-OD-13 |
| Latch not cleared by a reset communication | TC-OD-13 |
| One copy at both COB-ID outputs | TC-OD-12 |
| Absent COB-ID entries not constant | TC-OD-02 |
| Error register bit 0 without the COB-ID disagreement | TC-OD-12, TC-OD-14 |
| Error register bit 4 only at bus off | TC-OD-14 |
| Bdefault not kept at a reset | TC-OD-15 |
| No reset of the communication profile area | TC-OD-15 |
| Identifiers without the NODE-ID | TC-OD-09 |
| Master heartbeat entry valid with NODE-ID 0 | TC-OD-08 |
| Time-out after 255 ticks | TC-OD-17 |
| No time-out of the application port | TC-OD-17 |
| A response taken while the request waits for ready | TC-OD-16 |
| A second access taken while a request is outstanding | TC-OD-16 |
| An outstanding request answered at a reset | TC-OD-15 |
| Accesses taken in the minimal set | TC-OD-19 |
| Test input without effect | TC-OD-12 |
| 2002h returns the last Set value | TC-OD-10 |
| No `Cfg_SetValid` | TC-OD-10 |
| No `Cfg_CtoggleValid` | TC-OD-08 |
| Mapping of the Spacecraft Time PDO with 8 bits | TC-OD-01 |

The first mutation run detected 50 of the faults. "An outstanding request answered at a reset" was a gap of the
bench, not of the RTL: TC-OD-15 reset while no response was pending, where the fault has no effect. TC-OD-15 now
also resets in the cycle of the response of the user logic, and the fault is detected. The RTL is unchanged since the
first run, and the bench gained stimuli and checks only, so the 50 detections of that run stand.

The write whose number of bytes is not indicated (OD-IF-01, OD-WR-02) later changed the two length checks of the RTL
and of the reference model and extended TC-OD-04, the only test that writes with the number 0. The three faults of
the length checks, among them "Number of bytes 0 refused", ran again on the changed RTL and bench and were all
detected. TC-OD-04 detects no other fault, and the other tests write with 1 to 8 bytes only, where both checks are
unchanged, so the other detections stand.

The first regression run had five failures, all errors of the bench: an invalidation of a PDO that changed its
identifier, which OD-WR-04 refuses, a leftover abort code of the responder and a race in reading an event counter.
The RTL answered as the specification requires in each case.

## 5. Summary

All 20 test cases pass in all 36 runs, and TC-OD-21 passes in `lint/synth_check.py`; every requirement of the
specification is covered by the verification plan. VSG reports no errors and no warnings, and the GHDL synthesis of
the ten valid configurations of `lint/synth_check.py` has no inferred latch; the nineteen inconsistent ones are
rejected with their messages.
