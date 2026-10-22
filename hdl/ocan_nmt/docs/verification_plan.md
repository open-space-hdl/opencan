# ocan_nmt: Verification Plan

## 1. Overview

`ocan_nmt` is verified in two benches:

- `direct`: the bench drives the NMT messages, the redundancy inputs, the NODE-ID pins and the millisecond tick cycle
  by cycle and answers the transmit handshake like `ocan_dispatch`. A reference model of the state machine, written
  from the specification, predicts the state, the service enables, the events and the requests after every input.
  This bench checks the exact timing: the reset sequence, same-cycle inputs, the heartbeat bounds and the NODE-ID
  upsets through `ErrInj_*`.
- `network`: `ocan_nmt` with `ocan_dispatch`, `ocan_link` and the CAN network model of `tb/` (see the
  [verification plan of ocan_link](../../ocan_link/docs/verification_plan.md)). A master model node sends NMT messages
  and a node guarding request, and the boot-up message and the heartbeats are checked on the bus. This bench shows the
  boot-up message as the first frame of the node and a boot-up message that no node acknowledges.

Tests observe the ports of `ocan_nmt`, the buses and the model logs only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_nmt_tb` | `ocan_nmt_th` | `ocan_nmt`, `Clk` 40 MHz; drivers of the NMT messages, the redundancy inputs, the NODE-ID pins and `ErrInj_*`; a tick generator whose period M the test sets (16 cycles unless stated); a responder for the transmit handshake with configurable delays and result (`Tx_Done`, `Tx_Aborted`, reject path); the reference model |
| `ocan_nmt_net_tb` | `ocan_nmt_net_th` | `ocan_nmt`, `ocan_dispatch` and `ocan_link` ("Selective") with `ocan_tb_can_bus` and the model nodes M1 (master) and M2 on bus A, 1 Mbit/s with the bit timing of the plan of `ocan_link`; the millisecond tick from `olo_base_strobe_gen`; COB-IDs of the pre-defined connection set; the redundancy inputs fixed to bus A without a bus selection |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | `MinimalSet_g` = false | Clause 6 slave |
| `minimal` | `MinimalSet_g` = true | Minimal set of clause 9 (TC-NM-13 only) |

`MinimalSet_g` is the only generic; both values are simulated.

Checkers that run in every test of the direct bench:

- never a second `Tx_Valid` before the completion of the first request, and `Tx_Data` stable while `Tx_Valid` is '1';
- `Node_IdValid` is never '1' while `Node_Id` differs from the NODE-ID of the last valid sample of the pins;
- the service enables, `Stat_State` and the events equal the reference model in every cycle.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_reset_sequence` (TC-NM-01) | After `Rst`: `Reset_App` in cycle 2, `Reset_Comm` in cycle 3, the boot-up request (00h) in cycle 4, `Stat_State` "00" until then and "01" from the request. Every service enable stays '0' until the boot-up message completes, then `Ena_Sdo` and `Ena_Sync` are '1' and `Ena_Pdo` '0'. `Node_Id` equals the pins and `Node_IdValid` is '1' from cycle 4. Repeated with the completion by `Tx_Done`, by `Tx_Aborted` and by the reject path | NM-SM-01, NM-SM-04, NM-SM-06, NM-HB-01, NM-IF-01, NM-IF-03, NM-IF-04, NM-IF-07, NM-ID-01 |
| `test_node_id_valid` (TC-NM-02) | Every NODE-ID 1 to 127 with its complement: `Node_Id` correct, `Node_IdValid` '1', boot-up message. The pins change to another valid NODE-ID before a reset communication: the new NODE-ID from the sample on; `Node_IdValid` stays '1' through reset node and reset communication | NM-ID-01, NM-IF-01 |
| `test_node_id_invalid` (TC-NM-03) | NODE-ID 0 with code 7Fh; for NODE-IDs 1, 127 and 14 random ones every single-bit error of the 14 pins; the code equal to the NODE-ID; all pins '0' and all '1'. The node stays in the Initialisation: `Node_IdValid` and the enables '0', no `Tx_Valid`, `Stat_State` "00". The pins are taken at a tick only: a valid code applied between two ticks takes effect at the next tick and starts the node with a boot-up message, without a reset. A reset communication after the pins changed to an invalid code clears `Node_IdValid` from the sample | NM-ID-01, NM-ID-03 |
| `test_node_id_upset` (TC-NM-04) | In `PreOp_s`, `Op_s` and `Stopped_s`, each of the 14 bits of the NODE-ID copies inverted through `ErrInj_BitFlip` and `ErrInj_Valid`: `Node_IdValid` '0' and `Err_NodeId` in the same cycle, `Reset_Comm` in the next cycle, a new sample and a boot-up message, after which the node runs with the NODE-ID of the pins | NM-ID-02, NM-ID-04, NM-IF-07 |
| `test_node_control` (TC-NM-05) | From each of `PreOp_s`, `Op_s` and `Stopped_s` every command specifier 1, 2, 128, 129 and 130, also into the state the node is in: the target state and the service enables of the state table; for 129 `Reset_App` and `Reset_Comm` in consecutive cycles, for 130 `Reset_Comm` alone, each followed by a boot-up message | NM-SM-02, NM-SM-04, NM-SM-06, NM-IF-02, NM-IF-03, NM-IF-07 |
| `test_unknown_cs` (TC-NM-06) | In each of the three states every other command specifier (0, 3 to 127, 131 to 255): no change and one `Err_Cs` per message. NMT messages in the Initialisation (in `WaitId_s` and between `Rst` and the boot-up request): no change and no `Err_Cs` | NM-SM-03, NM-IF-07 |
| `test_nmt_back_to_back` (TC-NM-07) | 2000 NMT messages with random command specifiers, in consecutive cycles and with random gaps, checked against the reference model after every message | NM-SM-07, NM-SM-02, NM-SM-03 |
| `test_preop_request` (TC-NM-08) | `Red_PreopReq` in each state: `Op_s` and `Stopped_s` to `PreOp_s`, no effect in `PreOp_s` and in the Initialisation. In the same cycle as an NMT message with 1, 2, 128, 129, 130 and an unknown command specifier: `PreOp_s` after 1, 2, 128 and the unknown one; the reset sub-states after 129 and 130, without a later change to `PreOp_s` by the request | NM-SM-05, NM-IF-06 |
| `test_heartbeat_period` (TC-NM-09) | P = 1, 2, 7, 1000 and 65535: a heartbeat at every P-th tick after the boot-up request, in each of the three states with its state byte (04h, 05h, 7Fh, bit 7 '0'); P = 0: no heartbeat in 100000 ticks. Bounds of the first interval with tick period M and P = 3: a restart one cycle after a tick gives the first heartbeat P x M - 1 cycles later, a restart one cycle before a tick (P - 1) x M + 1 cycles later, a restart in the cycle of a tick P x M cycles later | NM-HB-02, NM-HB-03, NM-IF-05 |
| `test_heartbeat_restart` (TC-NM-10) | P from 0 to 5: a heartbeat at once, then every 5 ticks; from 5 to 3: the next heartbeat 3 ticks after the change; to 0: no more heartbeats. `Red_Switched`: a heartbeat at once and the cycle restarts; with P = 0 and in the Initialisation no heartbeat. A change of P, `Red_Switched` and a tick in one cycle: one request | NM-HB-04, NM-HB-05, NM-IF-06 |
| `test_request_pending` (TC-NM-11) | The responder holds `Tx_Ready` and the completion for up to 3 P: heartbeats that fall due meanwhile are not requested. A reset communication while a heartbeat is pending: the boot-up request follows in the cycle of the completion, and the enables stay '0' until the boot-up message completes | NM-HB-06, NM-IF-04, NM-SM-04 |
| `test_abort` (TC-NM-12) | A heartbeat aborted through the reject path and after `Tx_Ready`: not repeated, the next one at its time. A boot-up message aborted: the enables of `PreOp_s` return. At the next `Red_Switched` the boot-up message instead of the heartbeat, also with P = 0, with the enables '0' until it completes; the switch after that requests a heartbeat | NM-HB-07, NM-SM-04 |
| `test_minimal_set` (TC-NM-13) | Configuration `minimal`: every command specifier in every state changes nothing and gives no `Err_Cs`. The Initialisation ends in `Op_s` without a boot-up message, with a heartbeat (05h) at once. `Red_PreopReq` leads to `PreOp_s`; `Red_Selecting` from '1' to '0' leads back to `Op_s`; a change from '0' to '1' and a change in `Op_s` do nothing. `Stopped_s` is never reached | NM-MS-01, NM-MS-02, NM-MS-03, NM-IF-06 |
| `test_net_bootup` (TC-NM-14) | Bench `network`: the first frame of the node on the bus after the reset is the boot-up message (identifier 700h + NODE-ID, DLC 1, 00h); then a heartbeat every P ms with the state byte. M1 sends start remote node, enter pre-operational, stop remote node and reset communication; the heartbeats follow the state, and a boot-up message follows the reset communication. M1 sends a node guarding request (remote frame 700h + NODE-ID): the node sends no reply, only its next heartbeat at its time | NM-HB-01, NM-HB-02, NM-SM-02, NM-SM-04, NM-IF-04 |
| `test_net_no_ack` (TC-NM-15) | Bench `network` with the acknowledge of M1 and M2 off: the link repeats the boot-up message, `Stat_State` is "01", the enables stay '0' and no heartbeat is requested for 10 P. M2 turns its acknowledge on: the boot-up message completes, the enables of `PreOp_s` follow, and the heartbeats start | NM-SM-04, NM-HB-06 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| NM-IF-01 | TC-NM-01, TC-NM-02 |
| NM-IF-02 | TC-NM-05 |
| NM-IF-03 | TC-NM-01, TC-NM-05 |
| NM-IF-04 | TC-NM-01, TC-NM-11, TC-NM-14 |
| NM-IF-05 | TC-NM-09 |
| NM-IF-06 | TC-NM-08, TC-NM-10, TC-NM-13 |
| NM-IF-07 | TC-NM-01, TC-NM-04, TC-NM-05, TC-NM-06 |
| NM-ID-01 | TC-NM-01, TC-NM-02, TC-NM-03 |
| NM-ID-02, NM-ID-04 | TC-NM-04 |
| NM-ID-03 | TC-NM-03 |
| NM-SM-01 | TC-NM-01 |
| NM-SM-02 | TC-NM-05, TC-NM-07, TC-NM-14 |
| NM-SM-03 | TC-NM-06, TC-NM-07 |
| NM-SM-04 | TC-NM-01, TC-NM-05, TC-NM-11, TC-NM-12, TC-NM-14, TC-NM-15 |
| NM-SM-05 | TC-NM-08 |
| NM-SM-06 | TC-NM-01, TC-NM-05 |
| NM-SM-07 | TC-NM-07 |
| NM-HB-01 | TC-NM-01, TC-NM-14 |
| NM-HB-02 | TC-NM-09, TC-NM-14 |
| NM-HB-03 | TC-NM-09 |
| NM-HB-04, NM-HB-05 | TC-NM-10 |
| NM-HB-06 | TC-NM-11, TC-NM-15 |
| NM-HB-07 | TC-NM-12 |
| NM-MS-01, NM-MS-02, NM-MS-03 | TC-NM-13 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| NODE-ID check: NODE-ID 0, every single-bit error of the pins, code equal to the NODE-ID | TC-NM-03 |
| Copy check: every single-bit upset of the held copies | TC-NM-04 |
| Unknown command specifiers, NMT messages in the Initialisation | TC-NM-06 |
| Aborted heartbeat and boot-up message | TC-NM-12 |
| Boot-up message that no node acknowledges | TC-NM-15 |
| Node guarding request | TC-NM-14 |

## 6. Functional coverage

| Coverpoint | Requirements | Bins | Goal |
| --- | --- | --- | --- |
| Command specifier x state | NM-SM-02, NM-SM-03 | {1, 2, 128, 129, 130, other} x {`PreOp_s`, `Op_s`, `Stopped_s`, Initialisation} | 100 % |
| Producer heartbeat time P | NM-HB-03 | 0, 1, 2 to 9, 10 to 999, 1000 to 65534, 65535 | 100 % |
| NODE-ID sample | NM-ID-01, NM-ID-03 | valid {1, 2 to 63, 64 to 126, 127}; invalid {NODE-ID 0, error in the code, error in the NODE-ID, code equal to the NODE-ID} | 100 % |
| Same-cycle inputs | NM-SM-05, NM-HB-04, NM-HB-06 | request with each command specifier class; restart with a tick; completion with a due request | 100 % |

## 7. Not verified at the ports

- The `when others` branches of both state machines cannot be reached from the ports; `docs/coverage.md` justifies
  them.
- Two upsets in the same bit position of both NODE-ID copies keep the copies complementary and give another valid
  NODE-ID. This is outside the single-upset protection of D8 and is not tested.
