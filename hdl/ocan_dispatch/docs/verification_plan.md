# ocan_dispatch: Verification Plan

## 1. Overview

`ocan_dispatch` is verified in two benches:

- `direct`: the bench drives the link events of both buses cycle by cycle and answers the transmit stream like
  `ocan_link`. A reference classifier of the bench, written from the specification, predicts every output event and
  its cycle. This bench checks the exact timing: same-cycle events, the held NMT message and the reject path.
- `network`: `ocan_dispatch` with `ocan_link` and the CAN network model of `tb/` (see the
  [verification plan of ocan_link](../../ocan_link/docs/verification_plan.md)). Model nodes contend for the bus,
  lose and win arbitrations and send error frames. This bench shows the round robin, the heartbeat bound and the
  frame spacing under real bus conditions.

Tests observe the ports of `ocan_dispatch`, the buses and the model logs only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_dispatch_tb` | `ocan_dispatch_th` | `ocan_dispatch`, `Clk` 40 MHz; drivers of the link events and of the requests of the protocol blocks, a model of the transmit side of `ocan_link` (LK-TX-01, LK-TX-02, LK-DT-01, LK-DT-03 and the completion invariant of the architecture, section 5.1): `LinkTx_Ready` is '1' while no frame is pending and the link neither switches nor is stopped, '0' from the cycle after the take, and '1' again in the cycle of the completion event; configurable completion time and result, a lost completion event, a bus switch and a stop from a grant on; a checker that every completion event belongs to a taken request of its source and that a source has at most one taken request without its completion; the reference classifier |
| `ocan_dispatch_net_tb` | `ocan_dispatch_net_th` | `ocan_dispatch`, `ocan_link` ("Selective") and `ocan_tb_can_bus` with two model nodes on each bus, 1 Mbit/s as in the plan of `ocan_link` |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | `NumRpdo_g` = 4, `NumTpdo_g` = 4, `TimePdos_g` = true, `SdoServer_g` = true | All objects |
| `rpdo0` to `rpdo3`, `tpdo0` to `tpdo3` | `NumRpdo_g`, `NumTpdo_g` = 0 to 3 | Every number of PDOs (4 in `default`) |
| `no_time` | `TimePdos_g` = false | Without the time PDOs |
| `no_sdo` | `SdoServer_g` = false | Without the SDO server (minimal set) |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_rx_classes` (TC-DS-01) | Every class on the active bus, bus A and bus B: NMT (to the node and to all nodes), SYNC (DLC 0 and 1), master heartbeat, SDO request, receive PDO 1 to 4, Spacecraft Time PDO. Each output event with its data one cycle after the link event | DS-RX-01, DS-RX-04, DS-RX-05, DS-IF-01, DS-IF-03, DS-IF-04 |
| `test_rx_near_miss` (TC-DS-02) | For every rule a frame that nearly matches is not delivered: NMT with DLC 1 and 3 (protocol error event); NMT to NODE-ID + 1; SYNC, master heartbeat, receive PDOs and Spacecraft Time PDO with the configured identifier + 1 and - 1; SDO at 600h + NODE-ID + 1 and at 580h + NODE-ID; each object with the right 11 bits in an extended frame; each object as a remote frame; a receive PDO configured to 781h, 7DEh, 7F0h and 7FFh, and received at 7DFh and 7EFh (between the free ranges); SYNC, the Spacecraft Time PDO, the master heartbeat and a receive PDO with the valid flag clear; a receive PDO whose copies differ in one bit | DS-RX-02, DS-RX-03, DS-TX-05, DS-CP-01, DS-IF-07 |
| `test_rx_enables` (TC-DS-03) | Each service enable cleared: its frames are discarded, NMT messages and master heartbeats still pass; NODE-ID invalid: nothing is passed or sent | DS-RX-06, DS-RX-07, DS-IF-02 |
| `test_rx_both_buses` (TC-DS-04) | Events on both buses in the same cycle, in every combination of classes. Only frames of the active bus reach the protocol outputs; the NMT messages and master heartbeats of both buses reach `RxRed_*` in the same cycle | DS-RX-09, DS-BG-01, DS-BG-02, DS-IF-05 |
| `test_held_nmt` (TC-DS-05) | During the bus selection an NMT message on the inactive bus is held, and frames of both buses are no longer delivered. It is delivered one cycle after the active bus changes to its bus. When the selection ends without that change it is discarded. NMT messages on both buses in the same cycle: the active bus wins and nothing is held | DS-BG-03, DS-BG-04, DS-RX-05 |
| `test_rx_spacing` (TC-DS-06) | Bench `network`: M1 sends frames without data back to back, every class in turn. Every frame is delivered, events to one block are at least 46 bit times apart, and the per-bus events to `ocan_redundancy` follow every frame | DS-RX-10, DS-RX-09 |
| `test_sdo_absent` (TC-DS-07) | Configuration `no_sdo`: SDO requests are discarded without an event; SDO replies complete as aborted without a frame | DS-RX-08, DS-TX-04 |
| `test_tx_frames` (TC-DS-08) | Each source in turn: identifier, DLC and data on `LinkTx_*`; `Done` and `Aborted` of the link reach the owner only | DS-TX-02, DS-TX-03, DS-IF-06, DS-IF-07 |
| `test_tx_round_robin` (TC-DS-09) | All seven sources request continuously with an immediate link: frames in the cyclic order TPDO1 to NMT error control. Random requests: no pending request waits for more than one frame of each other source | DS-TX-01, DS-TX-06 |
| `test_tx_reject` (TC-DS-10) | Requests with a disabled service, an unusable entry and an invalid NODE-ID: `Ready` and `Aborted` one cycle later, no frame. Enable cleared in `Send_s`, while the link switches the bus from the grant on: the frame is withdrawn and the owner gets `Aborted`. Enable cleared in `Wait_s`: one `LinkTx_Abort`, completion as reported by the link. A request rejected in one cycle and allowed from the next: aborted, never granted. An SDO reply in `Send_s` while the NODE-ID becomes invalid with the SDO enable set: withdrawn and aborted | DS-TX-04 |
| `test_tx_free_range` (TC-DS-11) | Transmit PDOs and the Local Time PDO configured in the free ranges: rejected. A checker on `LinkTx_*` in every test: no identifier in the free ranges, never two frames without a completion between them | DS-TX-05 |
| `test_heartbeat_load` (TC-DS-12) | Bench `network`: all transmit PDOs, the Local Time PDO and the SDO reply pending continuously while M1 and M2 contend with frames of higher and lower priority and M2 sends error frames. NMT error control requested every 1 ms (shortest heartbeat period): each heartbeat is on the bus after at most one frame of each other source | DS-TX-06, DS-TX-01 |
| `test_cob_id_copies` (TC-DS-13) | One bit of each entry flipped in one copy at runtime: the object is unused from the next cycle, `Err_CobId` pulses once and `Stat_CobIdMismatch` shows the entry; restoring the copy makes it usable again | DS-CP-01, DS-CP-02 |
| `test_generics` (TC-DS-14) | Configurations `rpdo0` to `rpdo3`, `tpdo0` to `tpdo3` and `no_time`: frames of absent receive objects are not delivered, requests of absent transmit objects complete as aborted | DS-RX-01, DS-TX-04 |
| `test_tx_completion_grant` (TC-DS-15) | A source requests again while its frame is awaited; the completion event (`Done`, then `Aborted`) comes in a cycle in which the arbiter is free: no `Ready` in the cycle of the completion event, the grant one cycle later, and the new frame is sent | DS-TX-03 |
| `test_tx_lost_completion` (TC-DS-16) | The link takes a frame and becomes ready again without a completion event: the owner gets `Aborted` one cycle after `LinkTx_Ready`, no `Done`; the next requests of three sources are sent | DS-TX-07 |
| `test_tx_earliest_completion` (TC-DS-17) | All seven sources request back to back while the link completes every frame 1, 2 and 3 cycles after the take: no `Aborted`, every frame `Done` once, one frame on the link per `Done` | DS-TX-07, DS-TX-03 |
| `test_tx_link_stopped` (TC-DS-18) | The controller of the active bus stops from a grant on, before the take: the owner gets `Aborted` one cycle later and the frame is never sent; no grant while the link is stopped; after the re-enable the request that waited is sent. A bus switch from a grant on: the frame waits and is sent without an abort | DS-TX-08, DS-IF-07 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| DS-IF-01, DS-IF-03, DS-IF-04 | TC-DS-01 |
| DS-IF-02 | TC-DS-03 |
| DS-IF-05 | TC-DS-04 |
| DS-IF-06 | TC-DS-08 |
| DS-IF-07 | TC-DS-02, TC-DS-08, TC-DS-18 |
| DS-RX-01 | TC-DS-01, TC-DS-14 |
| DS-RX-02, DS-RX-03 | TC-DS-02 |
| DS-RX-04 | TC-DS-01 |
| DS-RX-05 | TC-DS-01, TC-DS-05 |
| DS-RX-06, DS-RX-07 | TC-DS-03 |
| DS-RX-08 | TC-DS-07 |
| DS-RX-09 | TC-DS-04, TC-DS-06 |
| DS-RX-10 | TC-DS-06 |
| DS-BG-01, DS-BG-02 | TC-DS-04 |
| DS-BG-03, DS-BG-04 | TC-DS-05 |
| DS-TX-01 | TC-DS-09, TC-DS-12 |
| DS-TX-02 | TC-DS-08 |
| DS-TX-03 | TC-DS-08, TC-DS-15 |
| DS-TX-04 | TC-DS-07, TC-DS-10, TC-DS-14 |
| DS-TX-05 | TC-DS-02, TC-DS-11 |
| DS-TX-06 | TC-DS-09, TC-DS-12 |
| DS-TX-07 | TC-DS-16, TC-DS-17 |
| DS-TX-08 | TC-DS-10, TC-DS-18 |
| DS-CP-01 | TC-DS-02, TC-DS-13 |
| DS-CP-02 | TC-DS-13 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| Near-miss frames of every receive rule (DLC, neighbouring identifier, extended and remote frames, free range, valid flag, unequal copies) | TC-DS-02 |
| Frames of the inactive bus and the held NMT message | TC-DS-04, TC-DS-05 |
| Disabled services and an invalid NODE-ID | TC-DS-03, TC-DS-10 |
| Rejected and withdrawn transmit requests | TC-DS-10, TC-DS-11 |
| Starvation of the heartbeat under contention and error frames | TC-DS-12 |
| COB-ID copy mismatch | TC-DS-13 |
| Completion of a frame that the link does not report | TC-DS-16 |
| A completion as aborted that the link did not report, at the earliest completion | TC-DS-17 |
| Granted frame while the controller of the active bus stops | TC-DS-18 |
