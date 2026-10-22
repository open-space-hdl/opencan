# ocan_dispatch: Specification

## 1. Overview

`ocan_dispatch` sits between `ocan_link` and the protocol blocks of OpenCAN. It classifies every received frame by
its identifier (COB-ID) and passes it with a fixed latency to the block that uses it (D11 of the
[architecture](../../../docs/architecture.md)). Frames of the inactive bus are not passed (architecture section 6.5).
It arbitrates the transmit requests of the protocol blocks, builds their frames with the protected COB-IDs and passes
them to the link.

| Block | Entity | Function |
| --- | --- | --- |
| DS-1 | `ocan_dispatch` | Receive filter: classification by identifier, NMT addressing, service gating |
| DS-2 | `ocan_dispatch` | Bus gate: frames of the active bus to the protocol blocks, NMT messages and master heartbeats of each bus to `ocan_redundancy` |
| DS-3 | `ocan_dispatch` (`olo_base_arb_rr`) | Transmit arbitration, frame build, completion events |
| DS-4 | `ocan_dispatch` | COB-ID protection: two copies of every configured COB-ID |

`ocan_dispatch` runs in one clock domain and has no frame memory.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| DS-IF-01 | The dispatch shall take the received frames of each bus as events from `ocan_link`, and the active bus and the state of the bus selection process from `ocan_redundancy`. | 8.3.3g |
| DS-IF-02 | The dispatch shall take the NODE-ID with its valid flag and an enable per service (SDO, PDO, SYNC) from `ocan_nmt`. | 6.10f |
| DS-IF-03 | The dispatch shall take two copies of each configured COB-ID from `ocan_od`: SYNC, the Spacecraft Time PDO, the receive PDOs 1 to `NumRpdo_g`, the transmit PDOs 1 to `NumTpdo_g` and the Local Time PDO. Each copy is an 11-bit identifier with a valid flag. It shall also take two copies of the NODE-ID of the Redundancy Master. | 6.10a, 6.10d |
| DS-IF-04 | The dispatch shall pass to the protocol blocks, as one-cycle events with their data: the NMT messages to `ocan_nmt`; SYNC with its DLC and data to `ocan_pdo` and `ocan_time`; the receive PDOs with their number, DLC and data to `ocan_pdo`; the Spacecraft Time PDO with its DLC and data to `ocan_time`; the SDO requests with their DLC and data to `ocan_sdo`. | 6.1a, 6.2a, 6.3b, 7.2.2c |
| DS-IF-05 | The dispatch shall pass to `ocan_redundancy`, per bus, the NMT messages and the master heartbeats (with the state byte) as events. | 8.3.3c, 8.3.3g |
| DS-IF-06 | The dispatch shall take transmit requests with a valid/ready handshake: NMT error control (one data byte) from `ocan_nmt`, SDO replies (DLC and data) from `ocan_sdo`, the transmit PDOs (number, DLC and data) from `ocan_pdo` and the Local Time PDO (DLC and data) from `ocan_time`. It shall report the completion of each request (sent or aborted) to its requester. | 6.2a, 6.5.2a, 7.2.2e |
| DS-IF-07 | The dispatch shall send frames to `ocan_link` with a valid/ready handshake and take the completion events of the link. It shall provide error events for discarded frames with a protocol error and for COB-ID copies that disagree, with the object concerned. | 6.10d, 9.4.8a |

### 2.2 Receive filter (DS-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DS-RX-01 | A data frame with an 11-bit identifier shall be classified as follows: 000h is NMT; the SYNC COB-ID is SYNC; 700h + the master NODE-ID is the master heartbeat; 600h + the NODE-ID is an SDO request; the COB-ID of receive PDO n is receive PDO n; the COB-ID of the Spacecraft Time PDO is the Spacecraft Time PDO. A COB-ID whose valid flag is not set matches no frame. | 6.10a, 6.2a, 6.3b, 6.1a, 7.2.2c, 8.3.3c |
| DS-RX-02 | Frames with an extended identifier, remote frames and frames that match no object shall be discarded without an event. | 5.6.1a, 11.1 |
| DS-RX-03 | An NMT frame shall be an NMT message only when its DLC is 2 and its second data byte is the NODE-ID or 0. An NMT frame with another DLC shall be discarded and reported as a protocol error; one addressed to another node shall be discarded without an event. | 9.1b, 9.4.8a |
| DS-RX-04 | SYNC shall be passed to `ocan_pdo` and `ocan_time` in the same clock cycle. | 6.3b, 7.2.3k |
| DS-RX-05 | Every event to a protocol block shall follow the event of the link by the same constant number of clock cycles, for every object and both buses. The NMT message held by DS-BG-03 is the only exception. | 7.2.3k |
| DS-RX-06 | SDO requests shall be passed only while the SDO enable is set, receive PDOs and the Spacecraft Time PDO only while the PDO enable is set, and SYNC only while the SYNC enable is set. NMT messages and master heartbeats shall always be passed. Frames that are not passed shall be discarded without an event. | 8.3.3e |
| DS-RX-07 | While the NODE-ID is not valid, no frame shall be passed and none sent. | 6.10f |
| DS-RX-08 | Without an SDO server (`SdoServer_g` = false) SDO requests shall be discarded without an event. | 9.3a |
| DS-RX-09 | The dispatch shall take a frame event of each bus in every clock cycle, also events of both buses in the same cycle, and classify each without back pressure. | 8.2.2a |
| DS-RX-10 | Two events to the same protocol block shall be at least the minimum frame time apart: 46 bit times. A data frame without data bytes has 44 bits, and the next frame can start in the third bit of the intermission. The per-bus events to `ocan_redundancy` are the exception: one event of each bus can come in the same cycle. | none |

### 2.3 Bus gate (DS-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DS-BG-01 | Only frames of the active bus shall be passed to the protocol blocks; frames of the inactive bus shall be discarded, except as in DS-BG-03. | 8.3.3d |
| DS-BG-02 | The NMT messages and the master heartbeats of both buses shall be passed to `ocan_redundancy` as events of their bus. | 8.3.3c, 8.3.3g |
| DS-BG-03 | During the bus selection process, an NMT message on the inactive bus shall be held. From that clock cycle on, the frames of the former active bus shall be discarded. The held message shall be passed to `ocan_nmt` when the active bus has changed to its bus, and discarded when the bus selection process ends without that change. | 8.3.3g, 8.3.3k |
| DS-BG-04 | When NMT messages arrive on both buses in the same clock cycle, the message of the active bus shall be taken and the other discarded. | 8.3.3g |

### 2.4 Transmit (DS-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DS-TX-01 | Pending transmit requests shall be served one frame at a time. The sources are ordered by the default identifiers of the pre-defined connection set: transmit PDOs 1 to 4, the Local Time PDO, the SDO reply, NMT error control. After a frame of a source, the next frame shall be that of the first pending source after it in this order, wrapping around to the first source. The next frame is passed to the link after the completion of the previous one. | none |
| DS-TX-06 | A pending request shall be passed to the link after at most one frame of each other source, also when transmit PDOs are pending all the time. | 6.5.2a, 8.3.3d |
| DS-TX-02 | The frames shall be data frames with an 11-bit identifier: 700h + NODE-ID for NMT error control, 580h + NODE-ID for the SDO reply, the COB-ID of transmit PDO n and of the Local Time PDO; the DLC and the data are those of the request. | 6.10a, 9.1b |
| DS-TX-03 | The completion of a frame (sent, aborted) shall be reported to the requester of that frame. | 6.2a |
| DS-TX-04 | A request of a service whose enable is not set, or of an object without a valid COB-ID, shall complete as aborted without a frame. When the enable of the service of the pending frame is cleared, the dispatch shall request the abort of that frame from the link. | 8.3.3e |
| DS-TX-05 | No frame shall be sent with an identifier from 781h to 7DEh or from 7F0h to 7FFh; an object configured with such a COB-ID is not used for transmission or reception. | 9.5a |

### 2.5 COB-ID protection (DS-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| DS-CP-01 | An object with a configured COB-ID shall be used for reception and transmission only while both copies of its COB-ID, valid flag included, are equal. The same holds for the master heartbeat and both copies of the master NODE-ID. | 6.10d |
| DS-CP-02 | Copies that disagree shall make the object unused and shall be reported, once per change, with the object concerned. | 6.10d |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| NMT frame with a DLC other than 2 | DS-1 | Discarded, protocol error event |
| Extended identifier, remote frame, no matching object | DS-1 | Discarded without an event |
| Frame of a disabled service or before a valid NODE-ID | DS-1 | Discarded without an event |
| Frame of the inactive bus | DS-2 | Discarded; NMT messages and master heartbeats are passed to `ocan_redundancy` |
| COB-ID copies disagree | DS-4 | Object unused; event with the object |
| Request of a disabled service or an invalid COB-ID | DS-3 | Completed as aborted, no frame |
| Service enable cleared while its frame is pending | DS-3 | Abort requested from the link |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `NumRpdo_g` | 4 | 0 to 4 | Number of receive PDOs (D7) |
| `NumTpdo_g` | 4 | 0 to 4 | Number of transmit PDOs (D7) |
| `TimePdos_g` | true | true, false | Spacecraft Time PDO and Local Time PDO present (D5) |
| `SdoServer_g` | true | true, false | SDO server present; false with the minimal set (D3) |

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.6.1a | The network may carry frames with 29-bit identifiers (note 2). The CANopen objects of OpenCAN use 11-bit identifiers; the node receives extended frames and ignores them |
| 8.3.3g | The NMT message is a frame of the NMT module control service (architecture section 6.5). Its addressing (second byte: the NODE-ID or 0 for all nodes) is checked here, so that `ocan_nmt` and `ocan_redundancy` see the same messages |
| 9.4.8a | A protocol error of a received frame means that the frame is not processed. The dispatch checks the format of the NMT message; the receiving blocks check the format of their objects (DLC of SYNC, heartbeat, SDO and PDOs) against \[CiA301\] |
| 9.5a | The free COB-IDs are kept unused at both levels, the clause 6 slave and the minimal set |
| 6.10b | Restricted COB-IDs are checked by `ocan_od` when a COB-ID is written; the dispatch uses the configured values as they are, apart from DS-TX-05 |
| 11.1 | Remote frames are not used: the applicability matrix lists remotely requested and read PDOs and node guarding as not applicable |
| Priority | When all sources are pending, the transmit order equals the order of the bus arbitration for the default COB-IDs. The round robin (DS-TX-01) bounds the wait of every source: the own heartbeat (700h + NODE-ID, the lowest bus priority) waits for at most one frame of each of the six other sources, a bound that the integrator checks against the consumer heartbeat time of the master |
