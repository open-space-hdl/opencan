# ocan_link: Verification Plan

## 1. Overview

`ocan_link` is verified at its ports against the CAN network model of `tb/`: two buses with independent model nodes
that build, send, receive and check frames at bit level. The model is written from the Bosch CAN Specification 2.0
part B and shares no code with `olo_intf_can`. A protocol error of the link is therefore seen on the bus and in the
model logs, not only at the ports of the link. Tests observe the ports of `ocan_link`, the buses and the model logs
only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_link_tb` | `ocan_link_th` | `ocan_link`, `Clk` 40 MHz; `ocan_tb_can_bus` with bus A and bus B; two model nodes `ocan_tb_can_node` per bus (M1, M2); procedures for the transmit stream of the link and a monitor of its receive events with the cycle of each event |

CAN network model (`tb/`):

- **Bus (`ocan_tb_can_bus`).** Wired-AND per bus of the transmit bit of the link when its transmit enable is '1'
  (transceiver model), of the model nodes and of a fault input. The fault input can hold a bus dominant or
  recessive. A blind mode feeds the receive input of the link with recessive while the bus follows the nodes, so that
  the dominant bits of the link do not reach its own receive input.
- **Nodes (`ocan_tb_can_node`).** Each node has its own bit clock (bit rate, offset in ppm, phase), a transmit queue
  and a log of every frame on its bus (fields, acknowledge, errors, time of the end of frame). It sends and receives
  data and remote frames with 11-bit and 29-bit identifiers and generates the acknowledge (on or off).
- **Contention.** A node arbitrates and retransmits after a lost arbitration. Two nodes, or a node and the link, can
  start in the same bit, and a node can start a frame in the third bit of the intermission (back-to-back frames).
- **Error injection.** A node can corrupt a bit of its own frame, send an active error flag at a chosen bit of
  another frame, send overload flags, and change the time of dominant-to-recessive edges independently of
  recessive-to-dominant edges. So the error counts of the link are driven by real error frames of another node.

Simulators: GHDL and QuestaSim. Bit timing unless stated: 1 Mbit/s with `Cfg_Prescaler` 2, `Cfg_Tseg1` 15,
`Cfg_Tseg2` 4, `Cfg_Sjw` 4 (20 quanta, sample point 80 %).

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `sel` | `BusAccess_g` = "Selective" | Selective bus access, defaults |
| `par` | `BusAccess_g` = "Parallel" | Parallel bus access |
| `sel_norec` | "Selective", `AutoRecover_g` = false | Bus-off recovery on request |
| `sync3`, `sync4` | `SyncStages_g` = 3, 4 | Every synchroniser length (2 in `sel` and `par`) |
| `domlim13`, `domlim1023` | `DominantLimit_g` = 13, 1023 | Both bounds of the dominant monitor (32 in `sel` and `par`) |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_frames` (TC-LK-01) | Frames between the link and M1 in both directions on bus A, then on bus B: standard and extended identifiers, data and remote frames, DLC 0 to 8 and 9 to 15; every frame in the log of M1 and M2 equals the frame sent; every received frame at `Rx_*` of its bus; both architectures | LK-IF-01 to LK-IF-03, LK-BA-01, LK-BA-02, LK-PR-01, LK-RX-01, LK-TX-01 |
| `test_listen_only` (TC-LK-02) | Parallel: frames of M1 on the inactive bus are passed with the index of that bus. The link does not acknowledge them: M1, alone on that bus, sees acknowledge errors, and the link sends no error flag after a frame corrupted by M2. `Can_Tx` of the inactive bus stays '1' and `Can_TxEn` '0' throughout | LK-BA-02, LK-RX-03, LK-IF-01 |
| `test_same_cycle` (TC-LK-03) | Parallel: M1 on bus A and M1 on bus B end frames in the same clock cycle; both events in the same cycle, each on its bus, one cycle after the controllers | LK-RX-01, LK-RX-02 |
| `test_bit_rates` (TC-LK-04) | 1 Mbit/s, 500 kbit/s, 250 kbit/s and 125 kbit/s, set while the link is disabled; frames in both directions at each rate | LK-PR-02, LK-IF-04 |
| `test_bit_timing` (TC-LK-05) | Sample points 62.5 % to 87.5 %, SJW 1 to 4. M1 with bit times 0.5 % longer and shorter and with delayed dominant-to-recessive edges: no error and no lost frame (synchronisation on recessive-to-dominant edges only) | LK-PR-03, LK-PR-04 |
| `test_switch_idle` (TC-LK-06) | After the reset the active bus is the requested bus. A switch without a pending frame: `Stat_Switching` for 2 cycles; the transmit bit and enable of each bus in both architectures; the first frame after the switch on the new bus only after 11 recessive bits | LK-BS-01 to LK-BS-03, LK-BA-03, LK-IF-05, LK-IF-06 |
| `test_switch_pending` (TC-LK-07) | Switch with a pending frame that has not started (bus busy with M1 frames of higher priority): aborted, never on the new bus. Switch with a frame on the bus: it completes on the old bus as sent, or after an error frame of M2 as aborted | LK-BS-04, LK-TX-02 |
| `test_switch_request_change` (TC-LK-08) | Requested bus toggled during `Abort_s` and during `Switch_s`: the active bus ends at the latest request | LK-BS-05 |
| `test_disable` (TC-LK-09) | `Ctrl_Enable` = '0' with a pending frame: the frame is reported as aborted, both buses recessive, no events; enable with the other bus requested: that bus is active | LK-BA-04, LK-BS-01 |
| `test_arbitration` (TC-LK-10) | The link and M1 start in the same bit: M1 with a lower identifier wins, `Tx_ArbLost`, the link sends after M1; M1 with a higher identifier loses and retransmits after the link. Repeated contention with M1 and M2 queuing frames continuously; every frame of the link arrives once and in order | LK-TX-01, LK-IF-02 |
| `test_error_frames` (TC-LK-11) | M2 destroys frames of the link with error flags: retransmission, transmit error count +8 per error, error passive at 128, bus off at 256. Bus off keeps the frame pending; after 128 x 11 recessive bits the link recovers and sends it. M2 destroys frames of M1 during the reception of the link: receive error count; all error events per controller | LK-FC-01 to LK-FC-03, LK-TX-03, LK-IF-06 |
| `test_recover_request` (TC-LK-12) | Configuration `sel_norec`: a bus-off controller stays off until `Ctrl_Recover`, then recovers after 128 x 11 recessive bits | LK-FC-03, LK-IF-05 |
| `test_counts_kept` (TC-LK-13) | Errors raise the counts on bus A; a switch to bus B and back, and a disable and enable, keep both counts and the state | LK-BS-06 |
| `test_dominant_timeout` (TC-LK-14) | `ErrInj_TxDominant` on the active controller: after `DominantLimit_g` bit times (+0 to 1 bit time) `Can_Tx` is recessive, `Can_TxEn` '0', `Err_DomTimeout` pulses, `Stat_DomTimeout` is '1' and the pending frame is aborted. `Tx_Ready` is '0' until `Ctrl_Reenable`; a second timeout ends with a disable and enable. In `domlim13` and `domlim1023` the timeout comes at the bound | LK-DT-01, LK-DT-02, LK-IF-05, LK-IF-07 |
| `test_dominant_inactive` (TC-LK-15) | Parallel: `ErrInj_TxDominant` on the controller of the inactive bus never reaches its bus; its monitor stops it after the limit. A dominant timeout of the active controller, then a bus switch: the stopped controller does not take part until it is re-enabled | LK-DT-01, LK-DT-03, LK-BA-02 |
| `test_dominant_margin` (TC-LK-16) | No dominant timeout at the default limit in the longest sequences of the controller: superposed error flags of M1 and the link, and blind mode on the active bus (the controller restarts its active error flags until it is error passive) | LK-DT-04 |
| `test_back_to_back` (TC-LK-17) | M1 sends frames without data back to back (start in the third bit of the intermission, 46 bit times apart) on bus A and, in parallel, on bus B: every frame is passed, each event one cycle after its controller | LK-RX-01, LK-RX-02 |
| `test_sync_stages` (TC-LK-18) | Configurations `sync3` and `sync4`: frames in both directions | LK-PR-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| LK-IF-01 | TC-LK-01, TC-LK-02 |
| LK-IF-02 | TC-LK-01, TC-LK-10 |
| LK-IF-03 | TC-LK-01 |
| LK-IF-04 | TC-LK-04 |
| LK-IF-05 | TC-LK-06, TC-LK-12, TC-LK-14 |
| LK-IF-06 | TC-LK-06, TC-LK-11 |
| LK-IF-07 | TC-LK-14 |
| LK-BA-01 | TC-LK-01 |
| LK-BA-02 | TC-LK-01, TC-LK-02, TC-LK-15 |
| LK-BA-03 | TC-LK-06 |
| LK-BA-04 | TC-LK-09 |
| LK-PR-01 | TC-LK-01, TC-LK-18 |
| LK-PR-02 | TC-LK-04 |
| LK-PR-03, LK-PR-04 | TC-LK-05 |
| LK-BS-01 | TC-LK-06, TC-LK-09 |
| LK-BS-02, LK-BS-03 | TC-LK-06 |
| LK-BS-04 | TC-LK-07 |
| LK-BS-05 | TC-LK-08 |
| LK-BS-06 | TC-LK-13 |
| LK-RX-01 | TC-LK-01, TC-LK-03, TC-LK-17 |
| LK-RX-02 | TC-LK-03, TC-LK-17 |
| LK-RX-03 | TC-LK-02 |
| LK-TX-01 | TC-LK-01, TC-LK-10 |
| LK-TX-02 | TC-LK-07 |
| LK-TX-03 | TC-LK-11 |
| LK-FC-01, LK-FC-02 | TC-LK-11 |
| LK-FC-03 | TC-LK-11, TC-LK-12 |
| LK-DT-01 | TC-LK-14, TC-LK-15 |
| LK-DT-02 | TC-LK-14 |
| LK-DT-03 | TC-LK-15 |
| LK-DT-04 | TC-LK-16 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| Inactive bus never driven, also under fault injection | TC-LK-02, TC-LK-15 |
| Pending frame never sent on the new bus | TC-LK-07 |
| Pending frame dropped at a disable | TC-LK-09 |
| Lost arbitration and retransmission | TC-LK-10 |
| Error frames of another node, error passive, bus off, recovery | TC-LK-11, TC-LK-12 |
| Dominant monitor: stuck transmit bit, both bounds of the limit | TC-LK-14 |
| Dominant monitor: no timeout in legal and fault-reaction sequences | TC-LK-16 |
