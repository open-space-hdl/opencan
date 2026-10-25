# ocan_dispatch: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_dispatch*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_dispatch_tb` | 16 | 25 | 25 |
| `ocan_dispatch_net_tb` | 2 | 2 | 2 |

The configurations are those of section 2 of the [verification plan](verification_plan.md). In the direct testbench
the transmit side of the link is a model of the specification of `ocan_link` and of the completion invariant of
the architecture (section 5.1): `LinkTx_Ready` is '1' while no frame is pending and the link neither switches nor
is stopped, and '0' from the cycle after the take to the cycle of the completion event; a checker confirms in every
test that every completion event of a source belongs to a taken request of that source. The network testbench runs
`ocan_dispatch` with `ocan_link` on the CAN network model of `tb/`.

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Measured values

| Item | Value |
| --- | --- |
| Link event to a protocol output or a per-bus event | 1 clock cycle (every check of the direct testbench) |
| Held NMT message to `RxNmt_Valid` | 1 clock cycle after the active bus changed to its bus (TC-DS-05) |
| Completion event of a source to the next grant of the same source | 1 clock cycle; no `Ready` in the cycle of `Done` or `Aborted` (TC-DS-15, sources 0, 5 and 6) |
| Smallest distance of two events to one block, back-to-back frames at 1 Mbit/s | NMT 175 µs, PDO block 49 µs, time block 50 µs, SDO 196 µs; none below 46 bit times (TC-DS-06) |
| Cyclic transmit order with all seven sources pending | TPDO1, TPDO2, TPDO3, TPDO4, Local Time PDO, SDO reply, NMT error control (TC-DS-09) |
| Transmit wait, random requests | 300 frames, no request waited for more than one frame of each other source (TC-DS-09) |
| Lost completion: `LinkTx_Ready` again without a completion event, to `Aborted` of the owner | 1 clock cycle; the requests of three sources are sent afterwards (TC-DS-16) |
| Frames back to back, completion 1, 2 and 3 cycles after the take | No `Aborted`, every frame `Done` once, one frame on the link per `Done`, for all seven sources (TC-DS-17) |
| Stop of the controller of the active bus between the grant and the take, to `Aborted` of the owner | 1 clock cycle; no grant while stopped; the waiting request is sent after the re-enable, the withdrawn frame never (TC-DS-18) |
| Bus switch of 20 cycles from a grant on | The frame waits in `Send_s` and is sent, no abort (TC-DS-18) |
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
matches for every receive rule. In addition, 23 deliberate faults of the RTL were each simulated with the tests that
must detect them, and every one made a test fail (the guard of DS-TX-03 also in the network bench of
`ocan_nmt`, TC-NM-21):

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
| No completion as aborted at `LinkTx_Ready` in `Wait_s` (DS-TX-07) | TC-DS-16 |
| Completion as aborted at `LinkTx_Ready` also in the cycle of a completion event | TC-DS-17, TC-DS-08 |
| A grant while the link cannot take a frame (DS-TX-08) | TC-DS-18 |
| `Ready` to a source without the link ready | TC-DS-18 |
| No withdraw in `Send_s` when the link is stopped | TC-DS-18 |
| Withdraw in `Send_s` also during a bus switch | TC-DS-18, TC-DS-10 |

The fault of the SDO identifier was a real error of the first version of the RTL, found by TC-DS-01 before the mutation
check. All 23 faults ran on the RTL of the bounded transmit waits; the change moved the text of two faults of the first
check (the fixed priority, now at `Out_Ready` of the arbiter, and the withdraw in `Send_s`), which were simulated again
as the same faults at their new places.

## 5. Summary

All 18 test cases pass in all 27 runs; every requirement of the specification is covered by the verification plan.
VSG reports no errors and no warnings, and the GHDL synthesis of every configuration has no inferred latch.
