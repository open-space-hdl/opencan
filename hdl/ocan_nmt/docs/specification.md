# ocan_nmt: Specification

## 1. Overview

`ocan_nmt` is the network management (NMT) slave of OpenCAN (ECSS-E-ST-50-15C clauses 6.5 and 6.10, for the minimal
set clauses 9.4.6 and 9.4.9). It checks and holds the NODE-ID of the node, runs the NMT state machine of \[CiA301\]
section 7.3.2 with the node control services, sends the boot-up message and produces the heartbeat. From its state it
derives the service enables that `ocan_dispatch` applies to the received and the sent frames. It takes the request of
`ocan_redundancy` to enter Pre-operational when the master heartbeat is missing (clause 8.3.3e).

| Block | Entity | Function |
| --- | --- | --- |
| NM-1 | `ocan_nmt` (`olo_intf_sync`) | NODE-ID check: pins with a protection code, sampled in the reset communication sub-state, held in two copies |
| NM-2 | `ocan_nmt` | NMT state machine: Initialisation with its sub-states, Pre-operational, Operational, Stopped; node control services; service enables; reset events |
| NM-3 | `ocan_nmt` | Boot-up and heartbeat producer: NMT error control frames, timed by the millisecond tick |

`ocan_nmt` runs in one clock domain; the NODE-ID pins pass `olo_intf_sync` (`SyncTmr_g` = true). The CiA 301 column
of the tables names the section of \[CiA301\] that defines the service or protocol.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-IF-01 | The NMT block shall take the NODE-ID from seven pins and its protection code from seven further pins. | 7.2.8.1 | 6.10e, 6.10k, 9.1b |
| NM-IF-02 | The NMT block shall take the NMT messages of `ocan_dispatch` as one-cycle events with their command specifier. The dispatch has checked the DLC and the addressing (DS-RX-03). | 7.2.8.3.1 | 6.5.1a |
| NM-IF-03 | The NMT block shall pass to `ocan_dispatch` the NODE-ID with its valid flag and one enable per service: SDO, PDO and SYNC. | 7.3.2.2.5 | 6.10f |
| NM-IF-04 | The NMT block shall pass the NMT error control frames (boot-up, heartbeat) to `ocan_dispatch` as transmit requests of one data byte with a valid/ready handshake, and take their completion (sent, aborted). | 7.2.8.3.2.2, 7.2.8.3.3 | 6.5.2a, 6.5.3a |
| NM-IF-05 | The NMT block shall take the producer heartbeat time (object 1017h, 16 bits, in milliseconds) and a one-cycle tick every millisecond. | 7.5.2.20 | 8.3.1a |
| NM-IF-06 | The NMT block shall take from `ocan_redundancy` a one-cycle request to enter Pre-operational, a one-cycle event at every bus switch and the state of the bus selection process, and pass the NMT state to `ocan_redundancy`. | none | 8.3.3e, 8.3.3h, 8.3.3k |
| NM-IF-07 | The NMT block shall provide the NMT state as a status output, a one-cycle event at the start of the reset application sub-state and one at the start of the reset communication sub-state, and error events for an NMT message with an unknown command specifier, for NODE-ID copies that disagree and for a request without completion (NM-HB-08). | 7.3.2.2.1 | 6.5.1a, 11.1 |

### 2.2 NODE-ID (NM-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-ID-01 | The NODE-ID pins and the code pins shall be sampled in the reset communication sub-state, that is after a hardware reset, a reset node and a reset communication. The sample is valid when the code is the bitwise complement of the NODE-ID and the NODE-ID is in the range 1 to 127. | 7.2.8.1, 7.3.2.2.1 | 6.10e, 6.10g, 6.10j, 6.10k |
| NM-ID-02 | The sampled NODE-ID shall be held in two copies, the NODE-ID and its complement. The NODE-ID is valid only while the two copies are complementary and the node is neither in the initialising sub-state nor waiting for a valid sample (NM-ID-03); no separate register holds the validity. | none | 6.10k |
| NM-ID-03 | While the sample is not valid, the node shall stay in the Initialisation state: no boot-up message and no heartbeat, every service enable and the valid flag to `ocan_dispatch` cleared, so that the node neither receives nor sends (DS-RX-07). The pins shall be sampled again at every millisecond tick; the first valid sample ends the reset communication sub-state. | 7.3.2.2.1 | 6.10f |
| NM-ID-04 | When the two copies of a valid NODE-ID disagree, the NMT block shall report an error event and enter the reset communication sub-state. | 7.3.2.2.1 | 6.10f, 6.10k |

### 2.3 NMT state machine (NM-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-SM-01 | After a hardware reset the node shall pass the sub-states initialising, reset application and reset communication of the Initialisation state and then enter Pre-operational. The transition to Pre-operational is the request of the boot-up message (NM-HB-01). | 7.3.2.1, 7.3.2.2.1 | 6.5.4a, 8.3.2a |
| NM-SM-02 | In the states Pre-operational, Operational and Stopped the node control services shall change the state as follows, also when the node is already in the target state: command specifier 1 (start remote node) to Operational, 2 (stop remote node) to Stopped, 128 (enter pre-operational) to Pre-operational, 129 (reset node) to the reset application sub-state, 130 (reset communication) to the reset communication sub-state. | 7.2.8.2.1, 7.2.8.3.1, 7.3.2.1 | 6.5.1a, 6.5.4a |
| NM-SM-03 | An NMT message with another command specifier shall not change the state and shall be reported as an error event. An NMT message in the Initialisation state shall not change the state. | 7.3.2.3 | none |
| NM-SM-04 | The service enables shall follow the state: SDO and SYNC in Pre-operational and Operational, PDO in Operational only, none in Stopped and in Initialisation. From the request of the boot-up message until its completion (sent or aborted) every enable shall stay cleared, so that the boot-up message is the first frame of the node. | 7.3.2.2.2 to 7.3.2.2.5 | 6.5.4a, 8.3.3e |
| NM-SM-05 | A request of `ocan_redundancy` to enter Pre-operational shall change Operational and Stopped to Pre-operational; it shall have no effect in Pre-operational and in Initialisation. When the request and an NMT message come in the same clock cycle, a start, stop or enter pre-operational command shall be executed first and the request after it; a reset command shall be executed and the request discarded. | 7.3.2.3 | 8.3.3e |
| NM-SM-06 | The NMT block shall issue the reset application event at the start of the reset application sub-state and the reset communication event at the start of the reset communication sub-state. A reset node and a hardware reset pass both sub-states and issue both events, a reset communication issues the second only. The blocks of the core respond to the events and to the hardware reset as section 2.6 states. | 7.2.8.2.1.5, 7.2.8.2.1.6, 7.3.2.2.1 | 6.5.1a, 11.1 |
| NM-SM-07 | The NMT block shall take an NMT message in every clock cycle, also in consecutive cycles, and complete the change of state, of the service enables and of the transmit request of each message within the minimum frame time of 46 bit times at 1 Mbit/s (D11). | none | 6.5.1a |

### 2.4 Boot-up and heartbeat (NM-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-HB-01 | At the transition from Initialisation to Pre-operational the node shall request the boot-up message: one data byte 00h. | 7.2.8.2.3, 7.2.8.3.3 | 6.5.3a, 8.3.2a |
| NM-HB-02 | A heartbeat shall be one data byte with the NMT state at the time of the request: 04h Stopped, 05h Operational, 7Fh Pre-operational. The reserved bit 7 is 0. | 7.2.8.3.2.2 | 6.5.2a, 8.3.3d |
| NM-HB-03 | With a producer heartbeat time P from 1 to 65535 ms, a heartbeat shall fall due at every P-th millisecond tick, counted from the request of the boot-up message or from a restart of the cycle (NM-HB-04, NM-HB-05); the boot-up message counts as the first heartbeat. A heartbeat that falls due in Pre-operational, Operational or Stopped shall be requested. With P = 0 no heartbeat shall fall due. As a restart is not aligned with the tick, the first heartbeat after a restart falls due between P - 1 and P milliseconds after it; the later ones follow every P milliseconds. | 7.2.8.3.2.2, 7.5.2.20 | 6.5.2a, 8.3.3d |
| NM-HB-04 | When P changes, the heartbeat cycle shall restart: from 0 to a nonzero value with a heartbeat request at once, otherwise with the next heartbeat at the P-th tick after the change. | 7.2.8.3.2.2 | 6.5.2a |
| NM-HB-05 | After a bus switch of `ocan_redundancy` the node shall request a heartbeat at once and restart the cycle (P not 0, node not in Initialisation). | none | 8.3.3h |
| NM-HB-06 | At most one NMT error control request shall be pending. A heartbeat that falls due while a request is pending shall not be requested. A boot-up message that falls due while a heartbeat is pending shall be requested after the completion of that heartbeat, unless a reset node or a reset communication comes in that cycle; the boot-up message of the new Initialisation follows then. A reset communication ends the wait for the completion of a request that `ocan_dispatch` has taken; a request that it has not taken stays until `Tx_Ready`. | none | 6.5.2a, 6.5.3a |
| NM-HB-07 | An aborted heartbeat shall not be repeated. An aborted boot-up message shall be requested again after the next bus switch, in place of the heartbeat of NM-HB-05 and also when P = 0. Until the repeated boot-up message completes, every service enable shall stay cleared, as for the first one (NM-SM-04). Every request of a boot-up message ends a pending repetition, and an abort in the cycle of a bus switch counts for that switch. | 7.2.8.3.3 | 8.3.2a, 8.3.3h |
| NM-HB-08 | When the completion of a request that `ocan_dispatch` has taken does not arrive within 256 millisecond ticks, the NMT block shall end the wait and report an error event. A heartbeat is not repeated. A boot-up message is requested again at once, so that the service enables stay cleared until a boot-up message completes; the boot-up message can then be sent twice. The late completion of the old frame is not taken for the new request (DS-TX-03). | none | 6.5.2a, 6.5.3a |

### 2.5 Minimal set

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-MS-01 | With `MinimalSet_g` = true the node shall not execute node control services: NMT messages shall not change the state and shall not be reported as errors. | 7.2.8.2.1 | 6.5.1a, 9.4.6.1a |
| NM-MS-02 | With `MinimalSet_g` = true the node shall send no boot-up message. At the end of the Initialisation it shall enter Operational by local control and request a heartbeat at once; further heartbeats follow NM-HB-03. | 7.3.2.2.2, 7.2.8.3.2.2 | 9.4.9.2a, 6.5.2a |
| NM-MS-03 | With `MinimalSet_g` = true a request of `ocan_redundancy` shall change Operational to Pre-operational (NM-SM-05), and the end of the bus selection process with an active bus shall return the node to Operational by local control. | 7.3.2.2.2 | 8.3.3e, 8.3.3k, 9.4.6.1a |

### 2.6 Effect of the resets

What the hardware reset (`Rst` of the core) and the two NMT resets change in each block. Reset node passes the reset
application and the reset communication sub-state; the entries of reset communication apply to it as well. The
entries of blocks that are specified later (`ocan_od`, `ocan_sdo`, `ocan_pdo`) are the intended effects, which their
specifications take over.

| Block | Hardware reset | Reset node | Reset communication |
| --- | --- | --- | --- |
| `ocan_link` | Both controllers restart, error counters 0, on the bus that `ocan_redundancy` requests | No change: with valid NODE-ID pins the valid flag stays set, so the link stays enabled and does not integrate again | As reset node |
| `ocan_dispatch` | No held NMT message, no pending frame | No change; the COB-IDs follow `ocan_od` | No change; the COB-IDs follow `ocan_od` |
| `ocan_nmt` | Initialisation from the initialising sub-state (NM-SM-01) | Reset application and reset communication sub-states: new NODE-ID sample, boot-up message, new heartbeat cycle; with a valid sample the NODE-ID valid flag stays set | Reset communication sub-state: as reset node without the reset application event |
| `ocan_redundancy` | Requested bus Bdefault, start-up bus selection (RM-SL-01) | No change of the active bus, Ctoggle and the bus selection process (RM-SL-08) | As reset node |
| `ocan_od` | Every object to its power-on value | Manufacturer-specific and device profile areas, then the communication profile area, to their power-on values; object 2000h is kept | Communication profile area (1000h to 1FFFh) to its power-on values |
| `ocan_sdo` | No transfer in progress | A transfer in progress ends without a reply | As reset node |
| `ocan_pdo` | No pending request, SYNC counts cleared, the data of the receive PDOs 0 (PD-RS-04) | The SYNC counts restart; synchronous receive data not yet passed and requests of transmission type 0 that wait for the SYNC are discarded; a request that `ocan_dispatch` has taken completes. The data last passed to the user logic are kept (PD-RS-03) | As reset node |
| `ocan_time` | Local time 0, set flag cleared, no SYNC sample (TM-CT-04) | The SYNC count of the Local Time PDO restarts and a request that waits for the next SYNC is discarded; a request that `ocan_dispatch` has taken completes. The local time, the set flag and the SYNC sample are kept (TM-CT-04, TM-IF-07) | As reset node |

NOTE: The applicability matrix of clause 11 states for reset node that the whole device connected with the CAN
controller is reset. The core passes this reset to the user logic as the reset application event; the user logic
resets the application of the device. `ocan_od` takes both events and restores the areas of the table (\[CiA301\]
section 7.3.2.2.1). Object 2000h (Bdefault, Ttoggle, Ntoggle, Ctoggle) lies in the manufacturer-specific area but
keeps its value at both NMT resets, so that the node keeps its bus and its toggle count (specification of
`ocan_redundancy`, section 5).

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Invalid NODE-ID sample (code not the complement, NODE-ID 0) | NM-1 | Node stays in Initialisation and does not communicate; pins sampled again every millisecond |
| NODE-ID copies disagree | NM-1 | Error event; reset communication sub-state, new sample, boot-up message |
| NMT message with an unknown command specifier | NM-2 | No state change; error event |
| Request of `ocan_redundancy` together with an NMT message | NM-2 | NMT command first, then the request; a reset command discards the request |
| Boot-up message aborted | NM-3 | Requested again after the next bus switch |
| Boot-up message not acknowledged (no other node on the bus, broken bus) | NM-3 | The link repeats the frame; the request stays pending, the service enables stay cleared and no heartbeat is requested. With the master heartbeat monitoring and the toggling enabled, the bus switch aborts the request and the boot-up message is sent on the other bus (NM-HB-07). With a consumer heartbeat time of 0 or Ntoggle = 0 there is no bus switch: the request completes when a node acknowledges the frame |
| Heartbeat aborted | NM-3 | Not repeated; the cycle continues |
| No completion of a taken request within 256 ms (lost completion, upset) | NM-3 | Error event; the heartbeat is not repeated, the boot-up message is requested again (it may appear twice on the bus) |
| Producer heartbeat time 0 | NM-3 | No heartbeat; the integrator configures a nonzero value (clause 6.5.2a) |
| Node guarding request (remote frame with the identifier 700h + NODE-ID) | `ocan_dispatch` (DS-RX-02) | Discarded, no reply: node guarding is not supported (section 5) |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `MinimalSet_g` | false | true, false | Minimal protocol set of clause 9 (D2): no node control services, no boot-up message |

The producer heartbeat time is an input (object 1017h of `ocan_od`); its default value is a parameter of the object
dictionary.

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 6.10e, 6.10g, 6.10j | The NODE-ID is hard-coded by pins, for example straps in a connector (note of clause 6.10j). The maintenance mode of clause 6.10g is a change of the straps followed by a reset: the pins are read only in the reset communication sub-state, so a valid NODE-ID cannot change in operation |
| 6.10f, 6.10k | The protection code is the complement of the NODE-ID (D8). A single faulty pin or a single upset of the held copies gives an invalid NODE-ID, never a different valid one. An invalid sample keeps the node silent; the node joins the network once the pins carry a valid code, without a reset |
| 6.5.1a, 11.1 | The applicability matrix states that a reset node resets the whole device connected with the CAN controller. The reset application event passes this reset to the user logic (section 2.6) |
| 6.5.2 note, 11.1 | Clause 6.5.2 makes the heartbeat the only error control protocol, and the applicability matrix marks the node guarding protocol (\[CiA301\] section 7.2.8.3.2.1) and the life guarding event as not applicable. Node guarding and life guarding are not supported: a guarding request is a remote frame, which `ocan_dispatch` discards (DS-RX-02) |
| 9.4.8a | The clause defines the handling of a protocol error for the minimal set. The clause 6 slave has no corresponding clause; NM-SM-03 follows \[CiA301\] and traces to no ECSS clause |
| 6.5.3a, 8.3.2a | The boot-up message is the first frame of the node after the Initialisation (NM-SM-04). It is sent on the default bus; when the bus is not usable and the transmission is aborted at the bus switch, it is sent on the next bus, so that the master learns of the restart on the bus it uses |
| 8.3.3h | The heartbeat production on the new bus starts with a heartbeat at once after the switch, so that the Redundancy Master sees the node on the new bus without waiting for a heartbeat period |
| 8.3.3e, 8.3.3f | In the clause 6 slave the node stays in Pre-operational after a bus switch until the Redundancy Master sends start remote node (clause 8.3.3f) |
| 9.4.6.1a, 9.4.9.2a | The minimal set has no node control services and no boot-up message. The node enters Operational by local control (\[CiA301\] section 7.3.2.2.2). The bus monitoring of clause 8.3.3e still stops the PDOs during a bus selection; as no master command can end it, the node returns to Operational by local control when the bus selection process has found the active bus |
| 11.1 | The note of the applicability matrix on the NMT startup requires the possibility to go to Operational directly after the reset communication. The note stands next to the start-up sequence of the network (heartbeat, bus monitoring, configuration, SYNC), which is a procedure of the master, and \[CiA301\] section 7.3.2.2.1 lets the slave enter Pre-operational after the reset communication. The note therefore concerns the master, which may start a node with start remote node right after its boot-up message, without the configuration step (NM-SM-02). A slave that entered Operational on its own would send PDOs before the start-up bus selection of clause 8.3.2b has found the bus of the master and without the start command of clause 8.3.3f. The clause 6 slave never enters Operational on its own, and the core has no option for it |
| \[CiA301\] 7.2.8.3.2.2 | The heartbeat protocol starts as soon as the producer heartbeat time is configured: a change from 0 starts the cycle with a heartbeat at once (NM-HB-04) |
