# ocan_redundancy: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_redundancy*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_redundancy_tb` | 21 | 24 | 24 |
| `ocan_redundancy_net_tb` | 4 | 6 | 6 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): TC-RM-01, TC-RM-14 and
TC-RM-20 run in the configurations `default` and `minimal`, TC-RM-15 in `minimal`, every other direct test case in
`default`; TC-RM-17 and TC-RM-19 run with selective and with parallel bus access, TC-RM-18 with parallel and TC-RM-25
with selective bus access. In every cycle of the direct testbench the reference model predicted `Link_Bus`,
`Stat_Selecting`, `Stat_Ctoggle`, `Stat_HbState`, `Stat_HbPresent`, `Nmt_PreopReq`, `Nmt_Switched`, `Upd_Valid` with
`Upd_Bdefault` and the three error events, and no output differed from it. The reference model is derived from the
requirements of the specification and is independent of the state machine of the architecture (verification plan,
section 1). Run against the RTL of the reviewed state before the corrections of RM-SL-01 and RM-SL-03 and of the
compares, the same benches fail in 9 of 30 runs, among them by the comparison with the reference model in the random
test TC-RM-14 and in TC-RM-20. The network testbench runs `ocan_redundancy` with `ocan_nmt`, `ocan_dispatch` and
`ocan_link` on the CAN network model of `tb/`; TC-RM-25 injects one NMT message at the receive input of `ocan_nmt`
(`Rx_Valid`, `Rx_Cs`) in the network harness, while `ocan_link` reports the switch; the modules stay the real ones.

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Measured values

| Item | Value |
| --- | --- |
| Last master heartbeat to `Err_HbMissing`, T x C = 3 ticks of 16 cycles | 48 cycles after a heartbeat one cycle after a tick, 34 cycles after a heartbeat one cycle before a tick (TC-RM-03) |
| Last master heartbeat to `Err_HbMissing` for (C, T) = (1, 1), (5, 3), (2, 255), (65535, 1) and T = 0 | T x C ticks exactly, for a heartbeat one cycle after a tick (TC-RM-03) |
| Pre-operational to the first toggle after a missing heartbeat | 1 clock cycle, for the NMT state reached after 0, 1 and 50 cycles and after 10 ticks of Initialisation (TC-RM-07) |
| End of the switch by the link to `Nmt_Switched` | 1 clock cycle, for switch times of 1 and 400 cycles (TC-RM-07) |
| A toggle due while the node is Operational or Stopped | `Nmt_PreopReq` at every expiry, T x C = 40 cycles apart; the toggle in the cycle after Pre-operational (TC-RM-20, also from Operational entered during the switch and in the minimal set) |
| C lowered from 10 to 3 six ticks after a master heartbeat | The presence cleared at the next tick (TC-RM-22) |
| `Err_HbMissing` to `Err_ToggleEnd` with N = 0 | 1 clock cycle (TC-RM-08) |
| Toggle that waited for Pre-operational to the next toggle, T x C = 10 ticks of 4 cycles | Between 38 and 41 cycles, (T x C - 1) x M + 2 to T x C x M + 1 (TC-RM-13) |
| Master heartbeat moved to bus B, T x C = 6 ms | Bus selection process started by the missing heartbeat, bus B found with the next master heartbeat on it, `Bdefault` updated to bus B; the first heartbeat of the node on bus B less than 500 µs after the switch event (TC-RM-17, selective and parallel bus access) |
| Master on bus B during the start-up process, parallel bus access | Process ended on bus B in less than 2 ms, before the first toggle, by a master heartbeat and by an NMT message (TC-RM-18) |
| Bus A stuck dominant or broken, master on bus B | Bus B found and `Bdefault` updated (TC-RM-19) |
| An NMT Start of bus A delivered during the first switch (selective bus access) | The node Operational on bus B; at the next expiry Pre-operational again, the toggle back to bus A, the process ended by the master heartbeat (TC-RM-25) |
| Both buses broken, Ntoggle = 3 | Three toggles, one `Err_ToggleEnd`, the node on bus B; the repaired bus B with the master on it ends the process (TC-RM-19) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `MinimalSet_g` | true, false | both | both |

The consumer heartbeat time, Ttoggle and Ntoggle are inputs. Their bounds are simulated: C = 0, 1 and 65535 (TC-RM-03,
TC-RM-04), T = 0, 1 and 255 (TC-RM-03), N = 0 and 255 (TC-RM-08).

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, 40 deliberate faults of
the RTL were each simulated with the tests that must detect them, one of them also in the network bench alone. 37 made
a test fail; three change the behaviour only after an upset that the ports cannot inject and are covered by design
review:

| Fault | Detected by |
| --- | --- |
| DLC of the master heartbeat not checked | TC-RM-02 |
| No `Err_HbDlc` | TC-RM-02 |
| State byte taken from the inactive bus | TC-RM-02 |
| Ttoggle = 0 not taken as 1 | TC-RM-03 |
| Presence not cleared after C | TC-RM-05 |
| Presence set with C = 0 | TC-RM-04 |
| Monitoring with C = 0 | TC-RM-04 |
| No restart of the timer at a parameter change | TC-RM-06 |
| A heartbeat on the inactive bus restarts the timer | TC-RM-05, TC-RM-11 |
| A tick in the cycle of a heartbeat counted | TC-RM-03, TC-RM-14 |
| No `Err_HbMissing` | TC-RM-03 |
| No Pre-operational request at a missing heartbeat | TC-RM-07 |
| First toggle not due at once after a missing heartbeat | TC-RM-07 |
| Toggle outside Pre-operational | TC-RM-07, TC-RM-13 |
| `Ctoggle` not counted | TC-RM-08 |
| No restart of the timer at a toggle | TC-RM-13 |
| No end of the toggling | TC-RM-08 |
| `Err_ToggleEnd` at every due toggle | TC-RM-08 |
| End of the process on the active bus without the update of Bdefault | TC-RM-09 |
| Message on the inactive bus: no switch | TC-RM-10 |
| Switch event before the link reports the new bus | TC-RM-07 |
| No `Nmt_Switched` | TC-RM-07 |
| End of the process after a switch by a message without the update of Bdefault | TC-RM-10 |
| Message on the requested bus during a switch ignored | TC-RM-10 |
| Message on the bus left during a switch taken | TC-RM-10 |
| A message of the inactive bus taken before one of the active bus in the same cycle | TC-RM-10 |
| Bdefault not read in `Idle_s` | TC-RM-01 |
| Start-up process with a toggle due | TC-RM-01, TC-RM-08 |
| Minimal set: start-up bus selection | TC-RM-01 |
| Write of `Ctoggle` ignored | TC-RM-12 |
| No repeated Pre-operational request for a due toggle (RM-SL-03) | TC-RM-20; TC-RM-25 alone |
| `Idle_s` waits in Operational or Stopped (RM-SL-01) | TC-RM-21 |
| `PresMs` compared with = | TC-RM-22 |
| Toggle with C = 0 | TC-RM-24 |
| `Ctoggle` not cleared at a missing heartbeat | TC-RM-23 |
| `Exhausted` not cleared at a missing heartbeat | TC-RM-23 |
| `Ctoggle` not cleared at the start-up process | TC-RM-01 |
| `TmrMs` compared with = | Not detected; covered by design review |
| `EndAfter` not cleared at the start-up process | Not detected; covered by design review |
| `EndAfter` not cleared at a missing heartbeat | Not detected; covered by design review |

`TmrMs` exceeds C - 1 only after an upset, since a change of C restarts the timer, and `EndAfter` is '1' at the start
of a process only after an upset: every path that sets it ends at the end of the switch, which clears it (verification
plan, section 7).

Four faults were first not detected, each by a gap of the bench, not of the RTL: "monitoring with C = 0" (TC-RM-04 ran
with T = 2, where a timer that ran with C = 0 expires only after 131072 ticks; it now runs with T = 1), "no restart of
the timer at a toggle" (the restart matters only for a toggle that waited for Pre-operational; TC-RM-13 now measures
the next toggle after such a toggle), "minimal set: start-up bus selection" (no test let the node leave the
Initialisation to Pre-operational in the minimal set; TC-RM-01 now does) and "`Exhausted` not cleared at a missing
heartbeat" (a toggle also clears it; TC-RM-23 now runs processes with Ntoggle = 0). After these changes all four are
detected.

## 5. Summary

All 25 test cases pass in all 30 runs; every requirement of the specification is covered by the verification plan.
VSG reports no errors and no warnings, and the GHDL synthesis of both configurations has no inferred latch.
