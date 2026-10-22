# ocan_redundancy: Verification Plan

## 1. Overview

`ocan_redundancy` is verified in two benches:

- `direct`: the bench drives the per-bus events of `ocan_dispatch`, the parameters, the NMT state and the millisecond
  tick cycle by cycle, and models the bus switch of `ocan_link`. A reference model, derived from the requirements of
  the specification and independent of the state machine of the architecture, predicts every output in every cycle:
  it keeps the state in the terms of the specification (not started, master heartbeat monitoring, bus selection
  process waiting for the report of the link or not, the toggle that fell due, the end of the toggling reported, the
  end after the running switch) and the timer as one count of ticks since its last restart. This bench checks the
  exact timing: the timer bounds, same-cycle inputs, the precedence of writes and the recovery cases.
- `network`: `ocan_redundancy` with `ocan_nmt`, `ocan_dispatch`, `ocan_link` and the CAN network model of `tb/` (see
  the [verification plan of ocan_link](../../ocan_link/docs/verification_plan.md)), with selective and with parallel
  bus access. Model nodes on both buses act as the Redundancy Master; faults break a bus. This bench shows the bus
  monitoring protocol of clause 8.3.3 on the buses.

Tests observe the ports of `ocan_redundancy`, the ports of the other blocks, the buses and the model logs only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_redundancy_tb` | `ocan_redundancy_th` | `ocan_redundancy`, `Clk` 40 MHz; drivers of the per-bus events and of the parameters; an NMT model that enters Pre-operational a configurable number of cycles after the first `Nmt_PreopReq` (a running delay is kept, and the test can make it ignore the requests), passes the Initialisation on command and is in the Initialisation during `Rst` and for 4 cycles after it, as `ocan_nmt`; a link model that, like `ocan_link`, answers a change of `Link_Bus` with `Link_Switching` = '1' from the next cycle, changes `Link_ActiveBus` after a configurable number of cycles and clears `Link_Switching` one cycle later, and that is disabled during `Rst` and for 4 cycles after it, with the requested bus as the active bus (LK-BS-01); a tick generator whose period M the test sets (4 cycles unless stated); the reference model |
| `ocan_redundancy_net_tb` | `ocan_redundancy_net_th` | `ocan_redundancy`, `ocan_nmt`, `ocan_dispatch` and `ocan_link` with `ocan_tb_can_bus`; the model nodes M1 (Redundancy Master: heartbeat on a chosen bus, NMT messages) and M2 on each bus, 1 Mbit/s with the bit timing of the plan of `ocan_link`; faults on each bus (stuck dominant, broken); the millisecond tick from `olo_base_strobe_gen`; the parameters as constants of the harness; an injection of an NMT message at the input of `ocan_nmt` (TC-RM-25) |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | `MinimalSet_g` = false | Clause 6 slave |
| `minimal` | `MinimalSet_g` = true | Minimal set (TC-RM-01, TC-RM-15) |
| `net_sel`, `net_par` | `BusAccess_g` of `ocan_link` = "Selective", "Parallel" | Network bench with each bus access architecture |

`MinimalSet_g` is the only generic of `ocan_redundancy`; both values are simulated. The parameter values used by the
tests include the bounds: C (consumer heartbeat time) 0, 1, 2 and 65535; T (Ttoggle) 0, 1 and 255; N (Ntoggle) 0, 1,
2, 3 and 255.

Checkers that run in every test of the direct bench:

- every output equals the reference model in every cycle;
- `Link_Bus` changes only by a toggle, by a message on the inactive bus during a bus selection process or in
  `Idle_s`, and never while the link model reports a switch;
- `Stat_ActiveBus` equals `Link_ActiveBus`.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_startup` (TC-RM-01) | After `Rst` with Bdefault 0 and with 1: `Link_Bus` follows `Cfg_Bdefault` until the NMT model enters Pre-operational; then the start-up process starts on that bus without a switch, with `Ctoggle` 0 (also after a write of Ctoggle before the start) and `Stat_Selecting` '1'. Configuration `minimal`: no bus selection; the monitoring starts when the NMT model leaves the Initialisation, to Operational and, in the second run, to Pre-operational | RM-SL-01, RM-MS-02, RM-SL-10, RM-IF-03, RM-IF-04, RM-IF-05 |
| `test_hb_dlc` (TC-RM-02) | Master heartbeats with DLC 0 and 2 to 15 on each bus: `Err_HbDlc`, no restart of the timer, no presence; with DLC 1 and every state byte 0 to 255: accepted, `Stat_HbState` holds the byte. Wrong DLCs on both buses in one cycle: one `Err_HbDlc` | RM-HB-01, RM-IF-01, RM-IF-07 |
| `test_hb_monitoring` (TC-RM-03) | (C, T) = (1, 1), (5, 3), (2, 255), (65535, 1) and T = 0 (C = 1 is set with the measured heartbeat, so that no expiry comes before it): master heartbeats shortly before the limit keep the monitoring; without them `Err_HbMissing` and `Nmt_PreopReq` come T x C ticks after the last one. Bounds with tick period M: after a heartbeat one cycle after a tick the expiring tick comes T x C x M - 1 cycles later, after one a cycle before a tick (T x C - 1) x M + 1 cycles later; the events follow one cycle after that tick | RM-HB-02, RM-HB-04, RM-IF-06, RM-IF-07 |
| `test_hb_disabled` (TC-RM-04) | C = 0 with T = 1: no `Err_HbMissing` and no toggle in 100000 ticks, longer than a timer that ran with C = 0 would need (65536 ticks), in `Monitor_s` and in a bus selection process; the process ends only by a message; `Stat_HbPresent` stays "00" | RM-HB-03, RM-HB-05 |
| `test_hb_presence` (TC-RM-05) | Master heartbeats on either bus set `Stat_HbPresent` of that bus; it is cleared C ticks after the last one. Heartbeats on the inactive bus outside a bus selection process set its presence but do not restart the timer | RM-HB-05, RM-SL-07, RM-IF-07 |
| `test_param_change` (TC-RM-06) | A change of C or of T in `Monitor_s` and in `Select_s` restarts the timer: the next expiry comes T x C ticks after the change, with the new values | RM-HB-04 |
| `test_first_toggle` (TC-RM-07) | A missing master heartbeat with the NMT model entering Pre-operational after 0, 1 and 50 cycles, and staying in the Initialisation for 10 ticks: the first toggle comes once `Nmt_State` is Pre-operational, `Link_Bus` inverted, `Ctoggle` 1; `Nmt_Switched` one cycle after the link model reports the new bus, for switch times of 1 and 400 cycles | RM-SL-02, RM-SL-03, RM-IF-05 |
| `test_toggling` (TC-RM-08) | N = 0, 1, 2, 3 and 255 without any message: a toggle every T x C ticks, `Ctoggle` counts; after N toggles no further toggle and one `Err_ToggleEnd`; the node is on the start bus after an even N and on the other bus after an odd N, with Bdefault 0 and 1; the process keeps running. N = 0 after a missing heartbeat: no toggle, `Err_ToggleEnd` in the cycle after `Err_HbMissing`, since the first toggle is due at once (RM-SL-02); N = 0 in the start-up process: no toggle, `Err_ToggleEnd` at the first expiry | RM-SL-02, RM-SL-03, RM-SL-04, RM-SL-09, RM-IF-07 |
| `test_select_end_active` (TC-RM-09) | During a bus selection process, after 0, 1 and 2 toggles, an NMT message and, in a second run, a master heartbeat on the active bus: the process ends in the next cycle, `Upd_Valid` with that bus, `Stat_Selecting` '0', and a missing master heartbeat is detected T x C ticks later | RM-SL-05, RM-IF-02 |
| `test_select_end_inactive` (TC-RM-10) | During a bus selection process, a master heartbeat and, in a second run, an NMT message on the inactive bus: while waiting for a toggle, in the cycle after a toggle, during a switch on the bus of `ReqBus` and during a switch on the other bus. The node switches at once without a change of `Ctoggle`, `Nmt_Switched` comes when the link model reports the bus, the process ends with `Upd_Valid` of that bus. Messages on both buses in one cycle: the active bus wins, no switch | RM-SL-06, RM-IF-08 |
| `test_inactive_ignored` (TC-RM-11) | Outside a bus selection process, NMT messages and master heartbeats on the inactive bus in every phase of the timer: no change of `Link_Bus`, no restart of the timer, `Err_HbMissing` at its time | RM-SL-07 |
| `test_writes` (TC-RM-12) | Precedence of writes. Bdefault written during a process: no change of `Link_Bus` or of the toggling, and the end of the process overwrites it (`Upd_Valid`); written outside a process: no change of the active bus, used after the next `Rst`. Ctoggle written during a process: the count is loaded and the toggling continues while it is below N; a value of N or more ends the toggling at the next due toggle with `Err_ToggleEnd`; 0 written after the end lets the toggling resume at the next expiry; a write in the cycle of a toggle wins. Ntoggle written during a process: takes effect at the next due toggle | RM-SL-09, RM-SL-10, RM-IF-02 |
| `test_nmt_resets` (TC-RM-13) | The NMT model passes the Initialisation (reset node, reset communication) during the monitoring and during a bus selection process: no change of `Link_Bus`, `Ctoggle` and `Stat_Selecting`; a toggle that falls due in an Initialisation of 25 ticks (two expiries of T x C = 10 ticks) waits for Pre-operational, and the next toggle follows T x C ticks after it | RM-SL-08, RM-SL-03, RM-SL-04 |
| `test_events_every_cycle` (TC-RM-14) | Configurations `default` and `minimal`: 60 segments of 400 cycles, each with a random tick period (2 to 8 cycles), NMT delay (0 to 20 cycles), switch delay (1 to 50 cycles), C (0 to 4), T (0 to 2), N (0 to 4, 255), Bdefault and NMT state (Initialisation, Pre-operational, Operational, Stopped), random writes of Ctoggle, and random events of both buses in consecutive cycles and in the same cycle at a random density from none to every cycle, checked against the reference model | RM-IF-08, RM-IF-01, RM-SL-03, RM-SL-04, RM-SL-08, RM-SL-10 |
| `test_minimal_set` (TC-RM-15) | Configuration `minimal`: a master heartbeat and an NMT message on the active bus end a bus selection process; on the inactive bus they switch at once (as TC-RM-10) | RM-MS-02, RM-SL-05, RM-SL-06 |
| `test_recovery` (TC-RM-16) | Recovery from every situation reachable at the ports: after the end of the toggling the master heartbeat on the bus of the node ends the process; a Ctoggle write restarts the toggling, and the master is found on the other bus; `Rst` in `Select_s` and in `Switch_s` restarts in `Idle_s` on Bdefault; C changed from 0 to a nonzero value during a process starts the toggling timer | RM-SL-04, RM-SL-05, RM-SL-01, RM-HB-04 |
| `test_net_switch` (TC-RM-17) | Bench `network`, `net_sel` and `net_par`: M1 produces the master heartbeat on bus A and then moves it to bus B (clause 8.3.3b). The node misses it, enters Pre-operational (`Ena_Pdo` '0'), toggles to bus B and sends its heartbeat there at once; M1 sends start remote node on bus B: the node enters Operational, Bdefault is updated to bus B | RM-SL-02, RM-SL-03, RM-SL-05, RM-IF-03 |
| `test_net_master_other_bus` (TC-RM-18) | Bench `network`, `net_par`: during a bus selection process on bus A, M1 starts its master heartbeat on bus B. The node switches to bus B at once, sends its heartbeat there and ends the process; repeated with an NMT message of M1 on bus B | RM-SL-06 |
| `test_preop_again` (TC-RM-20) | Configurations `default` and `minimal`: after the first toggle the node leaves Pre-operational (to Stopped, to Operational; in the minimal set through the Initialisation to Operational, as after a reset communication), and in a third run it enters Operational during the first switch while the link still reports the old bus (an NMT message of the old bus delivered during the switch); the node does not answer the requests: `Nmt_PreopReq` at every expiry, T x C ticks apart, no toggle; when the node answers, the waiting toggle follows | RM-SL-03, RM-SL-08 |
| `test_start_operational` (TC-RM-21) | The NMT model leaves the Initialisation to Operational and to Stopped: no start-up process, the monitoring starts, a missing heartbeat starts a process | RM-SL-01 |
| `test_presence_lower_c` (TC-RM-22) | C lowered from 10 to 3 six ticks after a master heartbeat: the presence is cleared at the next tick | RM-HB-05 |
| `test_second_process` (TC-RM-23) | A first process that toggled twice and ended the toggling, ended by a message; a write of Ctoggle in the monitoring; a second missing heartbeat without a reset: Ctoggle 0, the first toggle due at once (after Pre-operational), two toggles and `Err_ToggleEnd` again | RM-SL-02, RM-SL-04, RM-SL-10 |
| `test_toggle_c0` (TC-RM-24) | C set to 0 while the first toggle waits for Pre-operational: no toggle in Pre-operational; with C /= 0 again the due toggle is made | RM-HB-03, RM-SL-03 |
| `test_net_nmt_race` (TC-RM-25) | Bench `network`, `net_sel`: the master heartbeat is missing, and during the first switch an NMT Start remote node of bus A is delivered to `ocan_nmt`, injected at its input by the harness (on the bus the window is a few clock cycles, since the link aborts a pending frame that is not on the bus at once). The node is Operational on bus B; the master returns to bus A; at the next expiry Pre-operational is requested again, the node toggles back to bus A, and the master heartbeat ends the process | RM-SL-03, RM-SL-05 |
| `test_net_bus_faults` (TC-RM-19) | Bench `network`, `net_sel` and `net_par`: bus A stuck dominant and bus A broken while M1 is on bus B: the node finds bus B by toggling. Both buses broken: N toggles, then `Err_ToggleEnd`, the node stays; bus B repaired with M1 on it: the master heartbeat ends the process | RM-SL-04, RM-IF-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| RM-IF-01 | TC-RM-02, TC-RM-14 |
| RM-IF-02 | TC-RM-09, TC-RM-12 |
| RM-IF-03 | TC-RM-01, TC-RM-17, TC-RM-19 |
| RM-IF-04 | TC-RM-01 |
| RM-IF-05 | TC-RM-01, TC-RM-07 |
| RM-IF-06 | TC-RM-03 |
| RM-IF-07 | TC-RM-02, TC-RM-03, TC-RM-05, TC-RM-08 |
| RM-IF-08 | TC-RM-10, TC-RM-14 |
| RM-HB-01 | TC-RM-02 |
| RM-HB-02 | TC-RM-03 |
| RM-HB-03 | TC-RM-04, TC-RM-24 |
| RM-HB-04 | TC-RM-03, TC-RM-06, TC-RM-16 |
| RM-HB-05 | TC-RM-04, TC-RM-05, TC-RM-22 |
| RM-SL-01 | TC-RM-01, TC-RM-16, TC-RM-21 |
| RM-SL-02 | TC-RM-07, TC-RM-08, TC-RM-17, TC-RM-23 |
| RM-SL-03 | TC-RM-07, TC-RM-08, TC-RM-13, TC-RM-14, TC-RM-17, TC-RM-20, TC-RM-24, TC-RM-25 |
| RM-SL-04 | TC-RM-08, TC-RM-13, TC-RM-14, TC-RM-16, TC-RM-19, TC-RM-23 |
| RM-SL-05 | TC-RM-09, TC-RM-15, TC-RM-16, TC-RM-17 |
| RM-SL-06 | TC-RM-10, TC-RM-15, TC-RM-18 |
| RM-SL-07 | TC-RM-05, TC-RM-11 |
| RM-SL-08 | TC-RM-13, TC-RM-14, TC-RM-20 |
| RM-SL-09 | TC-RM-08, TC-RM-12 |
| RM-SL-10 | TC-RM-01, TC-RM-12, TC-RM-14, TC-RM-23 |
| RM-MS-02 | TC-RM-01, TC-RM-15 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| Master heartbeat with a wrong DLC | TC-RM-02 |
| Missing master heartbeat | TC-RM-03, TC-RM-17 |
| Frames of the inactive bus outside the bus selection process | TC-RM-05, TC-RM-11 |
| End of the toggling without an active bus | TC-RM-08, TC-RM-19 |
| Writes of Bdefault, Ctoggle and Ntoggle during a process | TC-RM-12 |
| Broken and stuck buses | TC-RM-19 |
| A due toggle while the node is Operational or Stopped (race, reset communication, upset) | TC-RM-20, TC-RM-25 |
| The Initialisation ends in Operational or Stopped | TC-RM-21 |
| C lowered below the running presence count | TC-RM-22 |

## 6. Input space covered by the directed tests

The bench collects no functional coverage. The directed tests cover these classes of the input space, each in a
named test case:

| Input | Requirements | Classes and test cases |
| --- | --- | --- |
| State x event | RM-IF-08, RM-SL-05, RM-SL-06, RM-SL-07 | Heartbeats with every DLC on either bus and on both in one cycle in `Monitor_s` (TC-RM-02); NMT messages and heartbeats on the inactive bus in `Monitor_s` (TC-RM-05, TC-RM-11); on the active bus in `Select_s` (TC-RM-09); on the inactive bus in `Select_s`, on the requested bus and on the bus left in `Switch_s`, on both buses in one cycle (TC-RM-10); random events of both buses in every cycle in all three states (TC-RM-14) |
| Consumer heartbeat time C | RM-HB-02, RM-HB-03 | 0 (TC-RM-04, TC-RM-16), 1, 2, 3, 5 and 65535 (TC-RM-03), 10 (TC-RM-05); changes 5 to 7 (TC-RM-06) and 0 to 3 (TC-RM-16) |
| Ttoggle T | RM-HB-04 | 0, 1, 3 and 255 (TC-RM-03), 2 (the default, TC-RM-09 to TC-RM-13); change 2 to 4 during a process (TC-RM-06) |
| Ntoggle N and the end bus | RM-SL-04, RM-SL-09 | N = 0, 1, 2, 3 and 255 with Bdefault 0 and 1, the end on the start bus and on the other bus (TC-RM-08); Ntoggle and Ctoggle written during a process (TC-RM-12) |
| NMT state during a process | RM-SL-03, RM-SL-08 | Pre-operational, the Initialisation (TC-RM-13), Operational and Stopped (TC-RM-20, TC-RM-25), random (TC-RM-14) |
| Delays of the environment | RM-IF-08 | tick period, NMT delay and switch delay random per segment (TC-RM-14); NMT delays 0, 1, 20 and 50, switch delays 1, 3, 20 and 400 cycles (TC-RM-07 to TC-RM-10) |
| Same-cycle inputs | RM-SL-10, RM-HB-04 | a write of Ctoggle in the cycle of a toggle (TC-RM-12); a heartbeat one cycle before and one cycle after a tick (TC-RM-03); messages on both buses in one cycle (TC-RM-02, TC-RM-10) |

## 7. Not verified at the ports

- The `when others` branch of the state machine cannot be reached from the ports. It recovers only when the
  synthesis tool implements the state machine safely (architecture, section 3; protection scope of the user
  guide); it is covered by design review.
- `EndAfter` is cleared at the start of every process; it can be '1' there only after an upset, and `TmrMs` exceeds
  C - 1 only after an upset (a change of C restarts the timer). The ports cannot inject these upsets; the clears and
  the compare with >= of `TmrMs` are covered by design review. The compare of `PresMs` is tested by TC-RM-22.
