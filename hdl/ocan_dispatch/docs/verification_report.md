# ocan_dispatch: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.03.20: `python run.py "*ocan_dispatch*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_dispatch_tb` | 13 | 22 | 22 |
| `ocan_dispatch_net_tb` | 2 | 2 | 2 |

The configurations are those of section 2 of the [verification plan](verification_plan.md). The network testbench
runs `ocan_dispatch` with `ocan_link` on the CAN network model of `tb/`.

QuestaSim: not run yet.

## 2. Measured values

| Item | Value |
| --- | --- |
| Link event to a protocol output or a per-bus event | 1 clock cycle (every check of the direct testbench) |
| Held NMT message to `RxNmt_Valid` | 1 clock cycle after the active bus changed to its bus (TC-DS-05) |
| Completion event of a source to the next grant of the same source | 1 clock cycle; no `Ready` in the cycle of `Done` or `Aborted` (TC-DS-15, sources 0, 5 and 6) |
| Smallest distance of two events to one block, back-to-back frames at 1 Mbit/s | NMT 175 µs, PDO block 49 µs, time block 50 µs, SDO 196 µs; none below 46 bit times (TC-DS-06) |
| Cyclic transmit order with all seven sources pending | TPDO1, TPDO2, TPDO3, TPDO4, Local Time PDO, SDO reply, NMT error control (TC-DS-09) |
| Transmit wait, random requests | 300 frames, no request waited for more than one frame of each other source (TC-DS-09) |
| Transmit wait under load, heartbeat every 1 ms, contention and error frames on the bus | 42 frames passed to the link, the bound held for every frame; the longest wait of a heartbeat for the link was 2.48 ms, caused by lost arbitrations against model nodes, not by other sources of the dispatch (TC-DS-12) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `NumRpdo_g` | 0 to 4 | 0, 1, 2, 3, 4 | 0, 1, 2, 3, 4 |
| `NumTpdo_g` | 0 to 4 | 0, 1, 2, 3, 4 | 0, 1, 2, 3, 4 |
| `TimePdos_g` | true, false | both | both |
| `SdoServer_g` | true, false | both | both |

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5); TC-DS-02 sends a frame that nearly
matches for every receive rule. In addition, seventeen deliberate faults of the RTL were each simulated with the tests
that must detect them, and every one made a test fail (the seventeenth, the guard of DS-TX-03, also in the network
bench of `ocan_nmt`, TC-NM-21):

| Fault | Detected by |
| --- | --- |
| No DLC check of the NMT message | TC-DS-02 |
| No addressing check of the NMT message | TC-DS-02 |
| Extended frames accepted | TC-DS-02 |
| Remote frames accepted | TC-DS-02 |
| Free COB-IDs usable | TC-DS-02, TC-DS-11 |
| COB-ID copies not compared | TC-DS-02, TC-DS-13 |
| COB-ID mismatch event in every cycle of a mismatch | TC-DS-13 |
| Bus A always taken as the active bus | TC-DS-01, TC-DS-04 |
| NMT message of the inactive bus not held | TC-DS-05 |
| Held NMT message never passed | TC-DS-05 |
| SDO requests passed without the SDO enable | TC-DS-03 |
| Fixed priority instead of the round robin | TC-DS-09 |
| No reject path | TC-DS-10 |
| No withdraw in `Send_s` | TC-DS-10 |
| No abort request in `Wait_s` | TC-DS-10 |
| SDO identifier computed with 7 bits | TC-DS-01 |
| Grant in the cycle of the own completion event | TC-DS-15 |

The sixteenth fault was a real error of the first version of the RTL, found by TC-DS-01 before the mutation check.

## 5. Summary

All 15 test cases pass in all 24 runs; every requirement of the specification is covered by the verification plan.
VSG reports no errors and no warnings, and the GHDL synthesis of every configuration has no inferred latch.
