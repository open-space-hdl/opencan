# ocan_core: Verification Plan

## 1. Overview

`ocan_core` is verified on the CAN network model of `tb/`: the whole node against model nodes on both buses. The
core is a structural entity, and every block has its own direct bench with a reference model; this bench shows that
the blocks work together as the node of the standard, that every connection carries its signal, and it verifies the
clauses that can only be checked at the level of the node (architecture of OpenCAN, section 10: 7.2.3, 8.1, 8.3.3,
11.1). There is no direct bench of the core.

Tests observe the ports of the core, the buses and the logs of the model nodes only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_core_net_tb` | `ocan_core_net_th` | `ocan_core`, `Clk` 40 MHz, 1 Mbit/s with the bit timing of the plan of `ocan_link`, NODE-ID 5 at the pins; `ocan_tb_can_bus` with the model nodes M1 and M2 on each bus. M1 of the active bus is the Redundancy Master and NMT master, the SYNC and time producer, the SDO client and the peer of the PDOs; M2 acknowledges and can send disturbing frames. A model of the user logic at the PDO port, a model of the application objects 2100h to 2203h at the application port (delays, aborts), and the reset and enable inputs driven by the test |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `sel_full` | `BusAccess_g` "Selective", `MinimalSet_g` false, `TimePdos_g` true | Clause 6 slave with the time PDOs |
| `par_full` | "Parallel", false, false | Clause 6 slave without the time PDOs, both controllers |
| `sel_min` | "Selective", true, false | Minimal set |
| `par_min_time` | "Parallel", true, true, `NumRpdo_g` = `NumTpdo_g` = 3, time COB-IDs 0F0h and 1F5h | Minimal set of a node that keeps time |

The four configurations give `BusAccess_g`, `MinimalSet_g` and `TimePdos_g` each of their values, and the selection of
the fault confinement state (architecture, section 5) both bus access architectures. The other generics change the
structure of single blocks and are simulated in their benches; `lint/synth_check.py` synthesises the core at their
bounds (TC-CO-10).

Checkers that run in every test: no frame of the node on the inactive bus; every frame of the node is a data frame with
an 11-bit identifier; no frame of the node while the NODE-ID is not valid.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_startup` (TC-CO-01) | Hardware reset through `Rst` (asynchronous, also released in the middle of a clock period): integration on Bdefault, boot-up message 705h, heartbeats with the producer heartbeat time; in the minimal set Operational by local control without a boot-up message; Bdefault = B: start on bus B | CO-IF-01, CO-IF-02, CO-CN-01, CO-CN-02, CO-AP-01, CO-AP-02, CO-AP-16, CO-AP-17 |
| `test_configuration` (TC-CO-02) | SDO in Pre-operational: the COB-ID of a transmit PDO invalidated, changed and made valid again, transmission types, 1017h, 1016h, 2000h; the effect of each write on the bus; a write in Operational refused; the application objects 2100h to 2203h through the application port; in the minimal set no SDO answer | CO-IF-06, CO-CN-04, CO-AP-03, CO-AP-07, CO-AP-08, CO-AP-09, CO-AP-19, CO-AP-20 |
| `test_process_data` (TC-CO-03) | Operational: receive PDOs to the user port, transmit PDOs with the types 254, 1 and 0 on the bus, `Sync_Valid` at every SYNC; no PDO in Pre-operational and in Stopped; `Stat_PdoEnabled` with the NMT state | CO-IF-05, CO-AP-04, CO-AP-06, CO-AP-10, CO-AP-18 |
| `test_time` (TC-CO-04) | The Spacecraft Time PDO of M1 with a synchronous type after a SYNC: the local time against the SCET of M1 at the SYNC (clause 7.2.3), the Local Time PDO at its SYNCs and on `Time_Req`; Local SCET Set and Get by SDO; on both buses; without the time PDOs no time PDO; in the minimal set without the time PDOs the local time 0 | CO-IF-07, CO-CN-04, CO-AP-11 |
| `test_bus_monitoring` (TC-CO-05) | The master heartbeat stops on the active bus: Pre-operational after Ttoggle heartbeat times, the PDOs stop, toggling; the master heartbeat on the other bus ends the bus selection, Bdefault updated and read back by SDO; an NMT message on the other bus ends it as well; Ntoggle toggles without success end on the default bus; the error register bit 4 with the state of the controller of the active bus | CO-IF-08, CO-CN-02, CO-CN-03, CO-AP-14 |
| `test_nmt_resets` (TC-CO-06) | Reset node and reset communication from M1 in each NMT state: `Evt_ResetApp`, `Evt_ResetComm`, boot-up again, the objects restored as the reset table of `ocan_nmt` states (read by SDO), 2000h kept, the data at the PDO port and the local time kept, the active bus kept; start, stop and enter pre-operational | CO-IF-08, CO-AP-13, CO-AP-17 |
| `test_node_id` (TC-CO-07) | NODE-ID pins with an invalid code: the node silent, no acknowledge on the bus, `Node_IdValid` '0'; a valid code: the node starts; `Ctrl_Enable` '0' and '1' with a change of the bit timing between | CO-IF-03, CO-IF-04 |
| `test_applicability` (TC-CO-08) | Frames that the node must not answer: remote frames on the identifiers of every PDO, node guarding requests, a block transfer request (answered with an abort), frames of the EMCY and TIME identifiers; no frame of the node other than boot-up, heartbeat, transmit PDOs, the Local Time PDO and SDO replies in the whole test | CO-CN-05, CO-AP-05, CO-AP-09, CO-AP-12, CO-AP-15 |
| `test_connections` (TC-CO-09) | Every status and event port active at least once: errors of each controller on corrupted frames of M2, the counters, the COB-ID compare and the parameter copies through `ErrInj_Od*`, the NODE-ID copies through `ErrInj_Nmt*`, the dominant timeout through `ErrInj_LinkTxDominant`, the application port with a delay and an abort | CO-IF-08, CO-IF-09, CO-CN-02, CO-AP-02 |
| TC-CO-10 (`lint/synth_check.py`) | The core synthesised for every combination of `BusAccess_g`, `MinimalSet_g` and `TimePdos_g`, at the bounds of `NumRpdo_g`, `NumTpdo_g`, `FineBits_g` and `ClkFrequency_g`; the generic checks of the blocks refuse inconsistent configurations through the core | CO-CN-04 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CO-IF-01 | TC-CO-01 |
| CO-IF-02 | TC-CO-01 |
| CO-IF-03 | TC-CO-07 |
| CO-IF-04 | TC-CO-07 |
| CO-IF-05 | TC-CO-03 |
| CO-IF-06 | TC-CO-02 |
| CO-IF-07 | TC-CO-04 |
| CO-IF-08 | TC-CO-05, TC-CO-06, TC-CO-09 |
| CO-IF-09 | TC-CO-09 |
| CO-CN-01 | TC-CO-01 |
| CO-CN-02 | TC-CO-01, TC-CO-05, TC-CO-09 |
| CO-CN-03 | TC-CO-05 |
| CO-CN-04 | TC-CO-02, TC-CO-04, TC-CO-10 |
| CO-CN-05 | TC-CO-08 |
| CO-AP-01 | TC-CO-01 |
| CO-AP-02 | TC-CO-01, TC-CO-09 |
| CO-AP-03 | TC-CO-02 |
| CO-AP-04 | TC-CO-03 |
| CO-AP-05 | TC-CO-08 |
| CO-AP-06 | TC-CO-03 |
| CO-AP-07 | TC-CO-02 |
| CO-AP-08 | TC-CO-02 |
| CO-AP-09 | TC-CO-02, TC-CO-08 |
| CO-AP-10 | TC-CO-03 |
| CO-AP-11 | TC-CO-04 |
| CO-AP-12 | TC-CO-08 |
| CO-AP-13 | TC-CO-06 |
| CO-AP-14 | TC-CO-05 |
| CO-AP-15 | TC-CO-08 |
| CO-AP-16 | TC-CO-01 |
| CO-AP-17 | TC-CO-01, TC-CO-06 |
| CO-AP-18 | TC-CO-03 |
| CO-AP-19 | TC-CO-02 |
| CO-AP-20 | TC-CO-02 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| Invalid NODE-ID code | TC-CO-07 |
| Remote frames, guarding requests, block transfer, EMCY and TIME identifiers | TC-CO-08 |
| Missing master heartbeat, toggling without success | TC-CO-05 |
| Upsets of the COB-ID table, the parameters and the NODE-ID copies | TC-CO-09 |
| Corrupted frames and a dominant transmit output | TC-CO-09 |
| Inconsistent generics | TC-CO-10 |

A deliberate fault of every connection of the core (a signal tied to its idle value, two signals exchanged, the wrong
controller selected for the fault confinement state, the tick or the reset not connected) is simulated with the
tests that must detect it (verification report, section 4).

## 6. Not verified at the ports

- The triplicated synchroniser of the reset release and the counter of the tick under an upset (architecture,
  section 6): design review.
- The functions of the blocks beyond the scenarios of this plan: their own benches.
