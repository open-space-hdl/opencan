# ocan_pdo: Specification

## 1. Overview

`ocan_pdo` is the PDO block of OpenCAN (ECSS-E-ST-50-15C clauses 6.2, 6.3, 6.9, 9.3 and 9.4; D1, D7 and D11 of the
[architecture](../../../docs/architecture.md)). It consumes the SYNC object, passes the data of the receive PDOs to
the user logic, at once or at the next SYNC as their transmission type requires, and requests the transmit PDOs from
`ocan_dispatch` at the SYNC or at a request of the user logic. The mapping is static: the eight data bytes of a PDO
are the eight objects of the user logic that the mapping objects of `ocan_od` name.

| Block | Entity | Function |
| --- | --- | --- |
| PD-1 | `ocan_pdo` | SYNC consumer: the check of the SYNC, the SYNC event to the user logic, the NMT state and the resets |
| PD-2 | `ocan_pdo` | Receive PDOs: the length check, the data to the user logic at once or at the next SYNC |
| PD-3 | `ocan_pdo` | Transmit PDOs: the triggers of the transmission types, the sample of the data, the transmit handshake with its time-out |

`ocan_pdo` runs in one clock domain. It serves the receive PDOs 1 to `NumRpdo_g` and the transmit PDOs 1 to
`NumTpdo_g`; the Spacecraft Time PDO and the Local Time PDO belong to `ocan_time`. The CiA 301 column of the tables
names the section of \[CiA301\] that defines the object or protocol.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| PD-IF-01 | The PDO block shall take from `ocan_dispatch` the SYNC with its DLC and the receive PDOs with their number, DLC and data as one-cycle events (DS-IF-04, DS-RX-04), for the receive PDOs 1 to `NumRpdo_g`, 0 to 4. | 7.2.2, 7.2.5 | 6.2a, 6.3b, 9.3a |
| PD-IF-02 | The PDO block shall pass the transmit PDOs 1 to `NumTpdo_g`, 0 to 4, to `ocan_dispatch` as transmit requests (DLC and data) with a valid/ready handshake per PDO and take their completion (sent, aborted) (DS-IF-06). | 7.2.2 | 6.2a, 9.3a |
| PD-IF-03 | The PDO block shall take from `ocan_od` the transmission types of the receive PDOs 1 to 4 and of the transmit PDOs 1 to 4 (OD-IF-06). | 7.5.2.35, 7.5.2.37 | 6.2a, 9.4.2e, 9.4.4d |
| PD-IF-04 | The PDO block shall take the PDO enable and the reset communication event of `ocan_nmt` (NM-IF-03, NM-IF-07). | 7.3.2.2 | 6.5.4a |
| PD-IF-05 | The PDO block shall take a one-cycle tick every millisecond, the tick of the other blocks. | none | none |
| PD-IF-06 | The PDO block shall have a port to the user logic: per receive PDO the 8 data bytes last passed and a one-cycle event when it passes new data; per transmit PDO a one-cycle request and the 8 data bytes to send; a one-cycle event at every SYNC that counts (PD-SY-01). | 7.2.2 | 6.2a, 9.4.3b |
| PD-IF-07 | The PDO block shall provide per receive PDO an event for a PDO that it does not process because of its length (PD-RX-02), and per transmit PDO the state "a request is pending" (PD-TX-07) and events for a completion as sent, for a completion as aborted, for a PDO that falls due while its request is pending (PD-TX-07) and for a request without completion (PD-TX-08). It shall provide the PDO enable as the PDO block uses it in each clock cycle, so that the user logic can tell a request without effect (PD-RS-01) from a lost one. | none | none |
| PD-IF-08 | The PDO block shall take an event in every clock cycle, also the SYNC and a receive PDO in consecutive frames, and complete the processing of each event within the minimum frame time of 46 bit times at 1 Mbit/s (D11). | none | 6.9e |

### 2.2 SYNC (PD-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| PD-SY-01 | A SYNC with DLC 0 or 1 shall count; a SYNC with another DLC shall be ignored. The counter byte of a SYNC with DLC 1 shall not be used. `ocan_time` applies the same rule (TM-SY-02), so that both blocks count the same SYNCs. | 7.2.5.3.1 | 6.3b, 6.9b, 6.9e |
| PD-SY-02 | Every SYNC that counts shall raise the SYNC event to the user logic in the clock cycle after the SYNC event of `ocan_dispatch`, in every NMT state in which `ocan_dispatch` passes the SYNC. | 7.2.5 | 6.9e, 9.4.3b |
| PD-SY-03 | A transmit PDO that falls due at a SYNC shall be requested at that SYNC and sent when `ocan_dispatch` grants it, without a time window: the synchronous window length (1007h) is not used. | 7.5.2.7 | 9.4.7.3d |

### 2.3 Receive PDOs (PD-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| PD-RX-01 | The data bytes of receive PDO n shall be the objects 2100h + n - 1, sub-indices 01h to 08h, of the mapping of 1600h + n - 1 (table 1 of the specification of `ocan_od`): data byte k - 1 of the frame is sub-index k, data byte 0 is the first on the bus. | 7.4.8, 7.5.2.36 | 6.2a, 9.4.5a |
| PD-RX-02 | A receive PDO with a DLC below 8 shall not be processed and shall raise the event of PD-IF-07. A DLC of 8 to 15 is a PDO of 8 bytes. | 7.5.2.36 | 9.4.1a, 9.4.7.2b, 9.4.8a |
| PD-RX-03 | With an event-driven transmission type (254, 255) the data of a receive PDO shall be passed to the user logic in the clock cycle after its reception event. | 7.2.2.2, 7.5.2.35 | 6.2a, 9.4.2e |
| PD-RX-04 | With a synchronous transmission type (0 to 240) the data of a receive PDO shall be held and passed to the user logic in the clock cycle after the next SYNC that counts. When several receive PDOs of the same number arrive between two SYNCs, the data of the last one shall be passed. Held data shall be passed at that SYNC also when the transmission type has changed since the reception. The data of all held receive PDOs shall be passed in the same clock cycle. | 7.2.2.2, 7.5.2.35 | 6.9a, 6.9b, 6.9e |
| PD-RX-05 | With a transmission type from 241 to 253 a receive PDO shall not be processed. | 7.5.2.35 | 11.1 |
| PD-RX-06 | The transmission type that decides PD-RX-03 to PD-RX-05 shall be the type in the clock cycle of the reception event. A receive PDO event in the clock cycle of a SYNC event shall be held for the next SYNC. | none | 6.9b |
| PD-RX-07 | The data passed to the user logic shall stay at its port until the next data of that receive PDO are passed (last value, D11). | 7.2.2 | 6.2a |

### 2.4 Transmit PDOs (PD-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| PD-TX-01 | Every transmit PDO shall have the DLC 8. Its data bytes shall be the objects 2200h + n - 1, sub-indices 01h to 08h, of the mapping of 1A00h + n - 1: data byte k - 1 of the frame is sub-index k, data byte 0 is the first on the bus. | 7.4.8, 7.5.2.38 | 6.2a, 9.4.1a, 9.4.5a |
| PD-TX-02 | With a transmission type n from 1 to 240 the transmit PDO shall be requested at every n-th SYNC that counts, with the data sampled in the clock cycle of that SYNC event. The count shall start with the first SYNC after the hardware reset, a reset communication event (PD-RS-03) or a change of the transmission type; a SYNC in the clock cycle of one of these events is not counted. The SYNC start value is not used. A request of the user logic has no effect. | 7.2.2.2, 7.5.2.37 | 6.9a, 6.9b, 6.9e |
| PD-TX-03 | With transmission type 0 the transmit PDO shall be requested at the first SYNC that counts after a request of the user logic, with the data sampled in the clock cycle of that SYNC event. A request in the clock cycle of a SYNC event shall apply to the next SYNC. Several requests before a SYNC give one PDO. A change of the transmission type shall discard a request that waits for the SYNC. | 7.2.2.2, 7.5.2.37 | 6.9a, 6.9e |
| PD-TX-04 | With transmission type 254 or 255 the transmit PDO shall be requested at a request of the user logic, with the data sampled in the clock cycle of the request. | 7.2.2.2, 7.2.2.3 | 6.2a, 9.4.3b, 9.4.4d |
| PD-TX-05 | With a transmission type from 241 to 253 no transmit PDO shall be requested. | 7.5.2.37 | 11.1 |
| PD-TX-06 | A transmit PDO shall be requested only by PD-TX-02 to PD-TX-04: there is no inhibit time and no event timer. | 7.5.2.37 | 9.4.1d, 9.4.4b |
| PD-TX-07 | At most one request per transmit PDO shall be pending, from the request to `ocan_dispatch` to its completion or to the end of the wait of PD-TX-08. A transmit PDO that falls due while its request is pending shall not be requested and shall raise the event of PD-IF-07; one that falls due in the clock cycle of the completion of its pending request shall be requested. A request that `ocan_dispatch` has not taken shall not be withdrawn, and its data shall not change. | none | 6.2a |
| PD-TX-08 | When the completion of a transmit PDO that `ocan_dispatch` has taken does not arrive within 256 ticks, the PDO block shall end the wait and raise the event of PD-IF-07. The PDO is not repeated. A completion while no request of that PDO waits for it shall be ignored (DS-TX-03). | none | none |
| PD-TX-09 | The completion of a request, sent or aborted, shall raise the event of PD-IF-07. An aborted transmit PDO shall not be repeated. | 7.2.2 | 8.3.3e |

### 2.5 NMT state and resets (PD-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| PD-RS-01 | While the PDO enable is cleared, no transmit PDO shall be requested and no receive PDO processed: a transmit PDO that falls due is not requested, without an event, and a request of the user logic has no effect. The SYNC counts of PD-TX-02 shall continue. The status of the PDO enable (PD-IF-07) shows this condition. | 7.3.2.2.2, 7.3.2.2.5 | 6.5.4a, 8.3.3e |
| PD-RS-02 | While the PDO enable is cleared, no data shall be held for the next SYNC (PD-RX-04) and no request of the user logic shall wait for it (PD-TX-03): held data and a waiting request are discarded when the node leaves Operational. A request that `ocan_dispatch` has taken completes as the dispatch reports it (DS-TX-04). | 7.3.2.2.3 | 6.5.4a, 8.3.3e |
| PD-RS-03 | The reset communication event shall restart the SYNC counts of PD-TX-02 and discard held receive data and a request that waits for the SYNC. A receive PDO event in the clock cycle of the event shall not be processed. A request that `ocan_dispatch` has taken completes as the dispatch reports it. The data last passed to the user logic shall be kept. | 7.3.2.2.1 | 6.5.4a, 11.1 |
| PD-RS-04 | After a hardware reset no request shall be pending, the SYNC counts shall be cleared, no data held, and the data at the port of every receive PDO shall be 0. | 7.3.2.2.1 | 8.3.2a |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| SYNC with a DLC other than 0 or 1 | PD-1 | Ignored: not counted, no SYNC event |
| Receive PDO with a DLC below 8 | PD-2 | Not processed; event |
| Receive PDO with a transmission type 241 to 253 | PD-2 | Not processed |
| Transmit PDO due while its request is pending | PD-3 | Not requested; event |
| Transmit PDO taken without completion within 256 ticks (lost completion, upset) | PD-3 | Wait ended; event; not repeated |
| Transmit PDO completed as aborted by the dispatch | PD-3 | Event; not repeated |
| Transmission type 241 to 253 of a transmit PDO | PD-3 | No transmit PDO |
| PDO enable cleared, reset communication | PD-1 | No requests; held data and waiting requests discarded |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `NumRpdo_g` | 4 | 0 to 4 | Receive PDOs 1 to `NumRpdo_g` (D7); the limit of the minimal set with the time PDOs is OD-MS-05 |
| `NumTpdo_g` | 4 | 0 to 4 | Transmit PDOs 1 to `NumTpdo_g` (D7) |

The transmission types are objects of `ocan_od` (OD-IF-06); with `MinimalSet_g` they are 254 (OD-MS-02), and only the
event-driven paths of PD-RX-03 and PD-TX-04 are used. `ocan_pdo` has no generic for the minimal set.

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 9.4.1d, 9.4.4b, 11.1 (7.2.2.3) | The minimal set forbids the inhibit time and the event timer; the applicability matrix makes the event- and timer-driven triggering applicable to the clause 6 slave, and \[CiA301\] sections 7.5.2.35 and 7.5.2.37 make both parameters optional (sub-indices 03h and 05h). OpenCAN implements neither, at both levels (PD-TX-06): a PDO without them behaves as with an inhibit time and an event timer of 0, a conforming configuration. Without a processor the user logic makes the events: a periodic event-driven PDO is a strobe of the user logic or a synchronous type, a deadline monitor of a receive PDO is a counter on its event. The conformance section of the user guide lists both parameters as not implemented (optional) |
| 9.4.1d, 9.4.4b (bus load) | Without an inhibit time the rate of the event-driven transmit PDOs is the rate of the requests of the user logic, bounded by one pending request per PDO (PD-TX-07). The integrator bounds the request rate. A user logic that requests without pause fills the bus with frames of 181h to 4FFh and starves the frames of lower priority, the master heartbeat among them: the nodes then enter Pre-operational (clause 8.3.3e), which stops the PDOs of this node as well, and the network falls back to Pre-operational instead of locking up |
| 9.4.8a, \[CiA301\] 7.5.2.36 | The mapping of every PDO has 8 bytes (D7). A receive PDO with fewer bytes is a protocol error and is not processed; the error is a local event, no emergency message (D9, clause 9.4.7.2b). A DLC of 9 to 15 is a frame of 8 data bytes (ISO 11898-1), so no PDO is longer than its mapping |
| 9.4.3b, 9.4.3c, 9.4.2b, 9.4.2e, 9.4.4d | The minimal set fixes the transmission type 254 (OD-MS-02). A data transmission triggered by a SYNC (clause 9.4.3b.2) is a transmit PDO that the user logic requests at the SYNC event (PD-SY-02); one triggered by a telemetry request (9.4.3b.1) is a request of the user logic after the receive PDO of the request. Only the data content tells a telemetry request from a command (clause 9.4.2b), so the rule of clause 9.4.3c, no spontaneous message, is a duty of the user logic. The user guide describes this use |
| 9.4.7.3d, \[CiA301\] 7.5.2.7 | The synchronous window length is not used, in the minimal set and in the clause 6 slave (PD-SY-03) |
| Table 9-12, \[CiA301\] 7.2.5, 7.5.2.22, 7.5.2.37 | Table 9-12 lists 1019h as reserved. The SYNC counter and the SYNC start value of the transmit PDOs (sub-index 06h) are not implemented: a SYNC with DLC 1 counts as one with DLC 0, and the transmit PDOs count every SYNC from the first one after a reset or a change of their type, as the Local Time PDO does (TM-TX-02). A transmit PDO and the Local Time PDO with the same type are therefore sent at the same SYNCs |
| \[CiA301\] 7.3.2.2.2, 7.3.2.2.3, 7.3.2.2.5 | PDOs exist in Operational only. \[CiA301\] states nothing about held synchronous data and about a request waiting for the SYNC when the node leaves Operational. OpenCAN discards both (PD-RS-02), so that no data received in Operational are passed to the user logic at a SYNC in Pre-operational or Stopped, outside Operational. The SYNC counts continue, so that the phase of the synchronous transmit PDOs stays that of the Local Time PDO. A transmit PDO that falls due outside Operational is not requested, instead of being aborted by `ocan_dispatch` at every due SYNC |
| \[CiA301\] 7.2.2.2 | For a receive PDO every synchronous type has the same meaning: the data are passed at the next SYNC. \[CiA301\] states nothing about several receive PDOs between two SYNCs: the last value is passed (PD-RX-04) |
| 11.1 (7.2.2.4.2, 7.2.2.4.3, 7.2.3) | Remote frames are not used: the remote transmission types 252 and 253 request no PDO and are refused by `ocan_od` (OD-WR-06), and no PDO is read by a remote request. Multiplexed PDOs are not applicable |
| \[CiA301\] 7.4.8, 7.5.1 | The mapped objects 2100h to 2103h and 2200h to 2203h belong to the user logic and are reached through the application port of `ocan_od` (OD-AP-01). Corrigendum 3 allows no read-only object in a receive PDO and no write-only object in a transmit PDO: the user logic answers the objects of the receive PDOs as rw or wo and those of the transmit PDOs as ro or rw, consistently with the data at the port of `ocan_pdo` (user guide) |
| 6.2a, 9.3a | The core has up to four receive and four transmit PDOs (D7), the PDOs of the pre-defined connection set. The time PDOs are additional PDOs of `ocan_time`; with the minimal set OD-MS-05 keeps the total at four of each |
| 7.2.3 | `ocan_pdo` gives the data of the user logic no time stamp: the user logic takes the SYNC sample of `ocan_time`. When the transmit PDOs and the Local Time PDO fall due at the same SYNC, `ocan_dispatch` sends the transmit PDOs first (DS-TX-01); the Local Time PDO carries the sample of the SYNC, so its value does not depend on the wait |
