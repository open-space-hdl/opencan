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
| NM-IF-07 | The NMT block shall provide the NMT state as a status output, a one-cycle event at the start of the reset application sub-state and one at the start of the reset communication sub-state, and error events for an NMT message with an unknown command specifier and for NODE-ID copies that disagree. | 7.3.2.2.1 | 6.5.1a, 11.1 |

### 2.2 NODE-ID (NM-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-ID-01 | The NODE-ID pins and the code pins shall be sampled in the reset communication sub-state, that is after a hardware reset, a reset node and a reset communication. The sample is valid when the code is the bitwise complement of the NODE-ID and the NODE-ID is in the range 1 to 127. | 7.2.8.1, 7.3.2.2.1 | 6.10e, 6.10g, 6.10j, 6.10k |
| NM-ID-02 | The sampled NODE-ID shall be held in two copies, the NODE-ID and its complement. The NODE-ID is valid only while the two copies are complementary. | none | 6.10k |
| NM-ID-03 | While the sample is not valid, the node shall stay in the Initialisation state: no boot-up message and no heartbeat, every service enable and the valid flag to `ocan_dispatch` cleared, so that the node neither receives nor sends (DS-RX-07). The pins shall be sampled again at every millisecond tick; the first valid sample ends the reset communication sub-state. | 7.3.2.2.1 | 6.10f |
| NM-ID-04 | When the two copies of a valid NODE-ID disagree, the NMT block shall report an error event and enter the reset communication sub-state. | 7.3.2.2.1 | 6.10f, 6.10k |

### 2.3 NMT state machine (NM-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-SM-01 | After a hardware reset the node shall pass the sub-states initialising, reset application and reset communication of the Initialisation state and then enter Pre-operational. The transition to Pre-operational is the request of the boot-up message (NM-HB-01). | 7.3.2.1, 7.3.2.2.1 | 6.5.4a, 8.3.2a |
| NM-SM-02 | In the states Pre-operational, Operational and Stopped the node control services shall change the state as follows, also when the node is already in the target state: command specifier 1 (start remote node) to Operational, 2 (stop remote node) to Stopped, 128 (enter pre-operational) to Pre-operational, 129 (reset node) to the reset application sub-state, 130 (reset communication) to the reset communication sub-state. | 7.2.8.2.1, 7.2.8.3.1, 7.3.2.1 | 6.5.1a, 6.5.4a |
| NM-SM-03 | An NMT message with another command specifier shall not change the state and shall be reported as an error event. An NMT message in the Initialisation state shall not change the state. | 7.3.2.3 | 9.4.8a |
| NM-SM-04 | The service enables shall follow the state: SDO and SYNC in Pre-operational and Operational, PDO in Operational only, none in Stopped and in Initialisation. From the request of the boot-up message until its completion (sent or aborted) every enable shall stay cleared, so that the boot-up message is the first frame of the node. | 7.3.2.2.2 to 7.3.2.2.5 | 6.5.4a, 8.3.3e |
| NM-SM-05 | A request of `ocan_redundancy` to enter Pre-operational shall change Operational and Stopped to Pre-operational; it shall have no effect in Pre-operational and in Initialisation. When the request and an NMT message come in the same clock cycle, a start, stop or enter pre-operational command shall be executed first and the request after it; a reset command shall be executed and the request discarded. | 7.3.2.3 | 8.3.3e |
| NM-SM-06 | The reset application event shall be issued at the start of the reset application sub-state: the user logic resets the application of the device, `ocan_od` sets the manufacturer-specific and the device profile area to their power-on values. The reset communication event shall be issued at the start of the reset communication sub-state: the protocol blocks reset their state, `ocan_od` sets the communication profile area to its power-on values. A reset node passes both sub-states and issues both events. | 7.2.8.2.1.5, 7.2.8.2.1.6, 7.3.2.2.1 | 6.5.1a, 11.1 |
| NM-SM-07 | The NMT block shall take an NMT message in every clock cycle, also in consecutive cycles, and complete the change of state, of the service enables and of the transmit request of each message within the minimum frame time of 46 bit times at 1 Mbit/s (D11). | none | 6.5.1a |

### 2.4 Boot-up and heartbeat (NM-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-HB-01 | At the transition from Initialisation to Pre-operational the node shall request the boot-up message: one data byte 00h. | 7.2.8.2.3, 7.2.8.3.3 | 6.5.3a, 8.3.2a |
| NM-HB-02 | A heartbeat shall be one data byte with the NMT state at the time of the request: 04h Stopped, 05h Operational, 7Fh Pre-operational. The reserved bit 7 is 0. | 7.2.8.3.2.2 | 6.5.2a, 8.3.3d |
| NM-HB-03 | With a producer heartbeat time P from 1 to 65535 ms, a heartbeat shall fall due at every P-th millisecond tick, counted from the request of the boot-up message or from a restart of the cycle (NM-HB-04, NM-HB-05); the boot-up message counts as the first heartbeat. A heartbeat that falls due in Pre-operational, Operational or Stopped shall be requested. With P = 0 no heartbeat shall fall due. | 7.2.8.3.2.2, 7.5.2.20 | 6.5.2a, 8.3.3d |
| NM-HB-04 | When P changes, the heartbeat cycle shall restart: from 0 to a nonzero value with a heartbeat request at once, otherwise with the next heartbeat at the P-th tick after the change. | 7.2.8.3.2.2 | 6.5.2a |
| NM-HB-05 | After a bus switch of `ocan_redundancy` the node shall request a heartbeat at once and restart the cycle (P not 0, node not in Initialisation). | none | 8.3.3h |
| NM-HB-06 | At most one NMT error control request shall be pending. A heartbeat that falls due while a request is pending shall not be requested. A boot-up message that falls due while a heartbeat is pending shall be requested after the completion of that heartbeat. | none | 6.5.2a, 6.5.3a |
| NM-HB-07 | An aborted heartbeat shall not be repeated. An aborted boot-up message shall be requested again after the next bus switch, in place of the heartbeat of NM-HB-05. | 7.2.8.3.3 | 8.3.2a, 8.3.3h |

### 2.5 Minimal set

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| NM-MS-01 | With `MinimalSet_g` = true the node shall not execute node control services: NMT messages shall not change the state and shall not be reported as errors. | 7.2.8.2.1 | 6.5.1a, 9.4.6.1a |
| NM-MS-02 | With `MinimalSet_g` = true the node shall send no boot-up message. At the end of the Initialisation it shall enter Operational by local control and request a heartbeat at once; further heartbeats follow NM-HB-03. | 7.3.2.2.2, 7.2.8.3.2.2 | 9.4.9.2a, 6.5.2a |
| NM-MS-03 | With `MinimalSet_g` = true a request of `ocan_redundancy` shall change Operational to Pre-operational (NM-SM-05), and the end of the bus selection process with an active bus shall return the node to Operational by local control. | 7.3.2.2.2 | 8.3.3e, 8.3.3k, 9.4.6.1a |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Invalid NODE-ID sample (code not the complement, NODE-ID 0) | NM-1 | Node stays in Initialisation and does not communicate; pins sampled again every millisecond |
| NODE-ID copies disagree | NM-1 | Error event; reset communication sub-state, new sample, boot-up message |
| NMT message with an unknown command specifier | NM-2 | No state change; error event |
| Request of `ocan_redundancy` together with an NMT message | NM-2 | NMT command first, then the request; a reset command discards the request |
| Boot-up message aborted | NM-3 | Requested again after the next bus switch |
| Heartbeat aborted | NM-3 | Not repeated; the cycle continues |
| Producer heartbeat time 0 | NM-3 | No heartbeat; the integrator configures a nonzero value (clause 6.5.2a) |

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
| 6.5.1a, 11.1 | The applicability matrix states that a reset node resets the whole device connected with the CAN controller. The reset application event passes this reset to the user logic |
| 6.5.3a, 8.3.2a | The boot-up message is the first frame of the node after the Initialisation (NM-SM-04). It is sent on the default bus; when the bus is not usable and the transmission is aborted at the bus switch, it is sent on the next bus, so that the master learns of the restart on the bus it uses |
| 8.3.3h | The heartbeat production on the new bus starts with a heartbeat at once after the switch, so that the Redundancy Master sees the node on the new bus without waiting for a heartbeat period |
| 8.3.3e, 8.3.3f | In the clause 6 slave the node stays in Pre-operational after a bus switch until the Redundancy Master sends start remote node (clause 8.3.3f) |
| 9.4.6.1a, 9.4.9.2a | The minimal set has no node control services and no boot-up message. The node enters Operational by local control (\[CiA301\] section 7.3.2.2.2). The bus monitoring of clause 8.3.3e still stops the PDOs during a bus selection; as no master command can end it, the node returns to Operational by local control when the bus selection process has found the active bus |
| 11.1 | The note of the applicability matrix on the NMT startup, a transition to Operational directly after the reset communication, concerns the master, which may start a node right after its boot-up message without configuration (NM-SM-02). The clause 6 slave never enters Operational on its own |
| \[CiA301\] 7.2.8.3.2.2 | The heartbeat protocol starts as soon as the producer heartbeat time is configured: a change from 0 starts the cycle with a heartbeat at once (NM-HB-04) |
