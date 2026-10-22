# ocan_nmt: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_nmt*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_nmt_tb` | 13 | 13 | 13 |
| `ocan_nmt_net_tb` | 2 | 2 | 2 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): TC-NM-13 runs in the
configuration `minimal`, every other test case in `default`. In every cycle of the direct testbench the reference
model predicted `Stat_State`, the service enables, `Node_IdValid`, `Node_Id`, the reset and error events, `Tx_Valid`
and `Tx_Data`, and no output differed from it. The network testbench runs `ocan_nmt` with `ocan_dispatch` and
`ocan_link` on the CAN network model of `tb/`.

QuestaSim: not run yet; it runs with the first release of OpenCAN.

## 2. Measured values

| Item | Value |
| --- | --- |
| Reset to `Reset_App`, `Reset_Comm` and the boot-up request | Cycles 2, 3 and 4 after the release of `Rst` (TC-NM-01) |
| NMT message to the new state and the service enables | 1 clock cycle (every check of the direct testbench) |
| Heartbeat period | P ticks exactly for P = 1, 2, 7, 1000 and 65535 (TC-NM-09) |
| First heartbeat after a restart, P = 3, tick every 16 cycles | 47 cycles after a restart one cycle after a tick, 33 cycles one cycle before a tick, 48 cycles in the cycle of a tick: between P - 1 and P ticks (TC-NM-09) |
| Upset of a NODE-ID copy to `Node_IdValid` = '0' and `Err_NodeId` | Same cycle; `Reset_Comm` in the next cycle (TC-NM-04, all 14 bits in all three states) |
| Heartbeats on the bus at P = 2 ms | 2 ms apart within the bus timing of the frames (TC-NM-14) |
| Boot-up message without an acknowledge | Repeated by the link for 10 ms, one request only, no heartbeat, the enables cleared; completed when a node acknowledged (TC-NM-15) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `MinimalSet_g` | true, false | both | both |

The producer heartbeat time is an input; its bounds 0, 1 and 65535 are simulated (TC-NM-09, TC-NM-10). Every
NODE-ID 1 to 127 is simulated (TC-NM-02).

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, sixteen deliberate faults
of the RTL were each simulated with the tests that must detect them, and every one made a test fail:

| Fault | Detected by |
| --- | --- |
| No complement check of the NODE-ID code | TC-NM-03 |
| NODE-ID 0 accepted | TC-NM-03 |
| `Node_IdValid` without the compare of the copies | TC-NM-04 |
| No reset communication at unequal copies | TC-NM-04 |
| Service enables not blocked by the boot-up message | TC-NM-01 |
| PDO enable in Pre-operational | TC-NM-01, TC-NM-05 |
| Reset node without the reset application sub-state | TC-NM-05 |
| No error event for an unknown command specifier | TC-NM-06 |
| Request of `ocan_redundancy` evaluated before the command | TC-NM-08 |
| Heartbeat period P + 1 ticks | TC-NM-09 |
| No heartbeat at once after P changes from 0 | TC-NM-10 |
| No heartbeat at a bus switch | TC-NM-10 |
| Heartbeat requested while a request is pending | TC-NM-11 |
| Aborted boot-up message not repeated | TC-NM-12 |
| Minimal set: no return to Operational at the end of the bus selection | TC-NM-13 |
| NODE-ID sampled in every cycle of `WaitId_s` instead of at the tick | TC-NM-03 |

The fault "heartbeat requested while a request is pending" was first not detected: TC-NM-11 held `Tx_Ready`, so
the repeated request carried the same byte in `TxReq_s`. TC-NM-11 now also holds the completion after `Tx_Ready`
for 3 P, where a repeated request is a second `Tx_Valid`, and detects the fault.

## 5. Summary

All 15 test cases pass in all 15 runs; every requirement of the specification is covered by the verification plan.
VSG reports no errors and no warnings, and the GHDL synthesis of both configurations has no inferred latch.
