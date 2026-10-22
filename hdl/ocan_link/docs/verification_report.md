# ocan_link: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_link_tb*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_link_tb` | 18 | 30 | 30 |

The configurations are those of section 2 of the [verification plan](verification_plan.md). The far end of every
test is the CAN network model of `tb/`, whose encoding and receiver are checked against six frames of real buses
(`tb/ocan_tb_can_model_tb.vhd`, 8 tests).

QuestaSim: not run yet.

## 2. Measured values

| Item | Value |
| --- | --- |
| Received frame to `Rx_Valid`, measured from the receiver of the model | 150 ns on bus A and bus B, in both bus access architectures, for every frame of TC-LK-01 (the model samples at 75 % of the bit, the link at 80 %) |
| Bus switch without a pending frame | 2 clock cycles of `Stat_Switching` (TC-LK-06) |
| First bit after a switch | 11.0 bit times after the controller is enabled again (integration, TC-LK-06) |
| Dominant timeout at `DominantLimit_g` = 13 and 32 | 13.025 µs and 32.025 µs at 1 Mbit/s after the transmit bit became dominant (TC-LK-14) |
| Longest dominant sequence of the controller in blind mode, from a transmit count of 0 | 17 bit times (start of frame and 16 restarted active error flags), no dominant timeout (TC-LK-16) |
| Bus-off recovery | after 128 x 11 recessive bits, then the pending frame is sent (TC-LK-11, TC-LK-12) |
| Back-to-back frames | every frame passed; consecutive events exactly the frame length plus 2 bit times apart (TC-LK-17) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `BusAccess_g` | "Selective", "Parallel" | both | both; another value is rejected |
| `SyncStages_g` | 2 to 4 | 2, 3, 4 | 2, 3, 4 |
| `AutoRecover_g` | true, false | both | both |
| `DominantLimit_g` | 13 to 1023 | 13, 32, 1023 | 13, 32, 1023 |

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, twelve deliberate faults
of the RTL were each simulated with the tests that must detect them, and every one made a test fail:

| Fault | Detected by |
| --- | --- |
| The inactive bus is driven | TC-LK-02 and the bus checker of every test |
| The controller of the inactive bus is not in listen-only mode | TC-LK-02 |
| No abort of the pending frame at a disable | TC-LK-09 |
| No abort of the pending frame before a switch | TC-LK-07 |
| The dominant monitor never stops a controller | TC-LK-14 |
| The re-enable request has no effect | TC-LK-14 |
| Frames of bus B are passed as frames of bus A (selective bus access) | TC-LK-01 |
| Frames are taken during a bus switch | TC-LK-07, TC-LK-08, TC-LK-09 |
| A switch keeps the old bus | TC-LK-06 |
| The active bus after the enable ignores the requested bus | TC-LK-06, TC-LK-09 |
| The dominant monitor counts one quantum too many per bit | TC-LK-14 |
| A disable does not clear a stopped controller | TC-LK-14 |

## 5. Summary

All 18 test cases pass in all 30 runs; every requirement of the specification is covered by the verification plan.
VSG reports no errors and no warnings, and the GHDL synthesis of every configuration has no inferred latch.
