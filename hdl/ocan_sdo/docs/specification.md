# ocan_sdo: Specification

## 1. Overview

`ocan_sdo` is the SDO server of OpenCAN (ECSS-E-ST-50-15C clauses 6.1 and 8.3.1c; D1, D3 and D11 of the
[architecture](../../../docs/architecture.md)). It takes the SDO requests of a client, 600h + NODE-ID, from
`ocan_dispatch`, reads and writes the objects through the access interface of `ocan_od`, and sends the replies,
580h + NODE-ID, through `ocan_dispatch`. It supports the expedited and the segmented transfer of objects of up to 8
bytes, not the block transfer.

| Block | Entity | Function |
| --- | --- | --- |
| SD-1 | `ocan_sdo` | Request decoder and protocol: command specifiers, toggle bit, the open segmented transfer, the aborts |
| SD-2 | `ocan_sdo` | Object access: one read or write through `ocan_od` per transfer, the buffer of 8 bytes |
| SD-3 | `ocan_sdo` | Reply: the frame of the response or of the abort, the transmit handshake with its time-out |

`ocan_sdo` runs in one clock domain. A core with `MinimalSet_g` has no SDO server (D3). The CiA 301 column of the
tables names the section of \[CiA301\] that defines the protocol.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| SD-IF-01 | The SDO server shall take the SDO requests from `ocan_dispatch` as one-cycle events with their DLC and data (DS-IF-04). | 7.2.4.3 | 6.1a |
| SD-IF-02 | The SDO server shall pass its replies to `ocan_dispatch` as transmit requests (DLC and data) with a valid/ready handshake and take their completion (sent, aborted) (DS-IF-06). | 7.2.4.3 | 6.1a |
| SD-IF-03 | The SDO server shall read and write the objects through the access interface of `ocan_od` (OD-IF-01): one access at a time, with the index, the sub-index and, for a write, the data bytes and their number (0 when not indicated), and take its answer. | 7.2.4.3 | 6.8a, 8.3.1c |
| SD-IF-04 | The SDO server shall take the SDO enable and the reset application and reset communication events of `ocan_nmt` (NM-IF-07). | 7.3.2.2 | 6.5.4a |
| SD-IF-05 | The SDO server shall take a one-cycle tick every millisecond, the tick of the other blocks. | none | none |
| SD-IF-06 | The SDO server shall provide events for a request that it does not process (SD-PR-02, SD-PR-09), for an abort frame that it sent, for an abort request of the client that ended an open transfer or the processing of a request, for a reply without completion (SD-TX-02) and for an access of `ocan_od` without an answer (SD-TX-04), and the state "a segmented transfer is open" (SD-RS-03). An abort frame was sent when its reply completed as sent; a rejected, aborted or not completed abort frame gives no event. An abort request that is ignored (SD-PR-07) gives no event. | none | 6.1a |
| SD-IF-07 | The SDO server shall take a request event in every clock cycle, without back pressure (D11). | none | none |

### 2.2 Protocol (SD-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| SD-PR-01 | Requests and replies shall have the layout of \[CiA301\]: the command specifier in bits 7 to 5 of byte 0; in an initiate frame and an abort frame the index in bytes 1 (least significant byte) and 2 and the sub-index in byte 3; the data, the size and the abort code in bytes 4 to 7, least significant byte first; in a segment the data in bytes 1 to 7. | 7.2.4.3.3 to 7.2.4.3.7, 7.2.4.3.17 | 6.1a |
| SD-PR-02 | A request with a DLC below 8 shall not be processed: no reply, the event of SD-IF-06. A DLC of 8 to 15 is a frame of 8 bytes. | Annex A | 6.1a |
| SD-PR-03 | A request with the command specifier 5 or 6 (block transfer) or 7 shall be answered with an abort, code 0504 0001h (command specifier not valid). | 7.2.4.3.13, 7.2.4.3.9, 7.2.4.3.17 | 11.1 |
| SD-PR-04 | A download segment request or an upload segment request without an open segmented transfer of its direction shall be answered with an abort, code 0504 0001h; an open transfer of the other direction ends with it. The abort carries the index and sub-index of the open transfer, or 0 when no transfer is open. | 7.2.4.2.4, 7.2.4.2.7, 7.2.4.3.17 | 6.1a |
| SD-PR-05 | The toggle bit of the first segment after an initiate shall be 0 and alternate from segment to segment; the response carries the toggle bit of the request. A segment request with the wrong toggle bit shall be answered with an abort, code 0503 0000h (toggle bit not alternated), and the transfer ends. | 7.2.4.3.4, 7.2.4.3.7, 7.2.4.3.17 | 6.1a |
| SD-PR-06 | An initiate request shall end an open transfer without an abort and start the new one. | 7.2.4.3.2, 7.2.4.3.5 | 6.1a |
| SD-PR-07 | An abort request of the client shall end an open transfer without a reply. An abort request without an open transfer and without a processed request (SD-PR-09) shall be ignored. | 7.2.4.2.16, 7.2.4.3.17 | 6.1a |
| SD-PR-08 | Bits of a request that \[CiA301\] marks as not used or reserved shall not be checked. | 7.2.4.3.3 to 7.2.4.3.7 | 6.1a |
| SD-PR-09 | The SDO server shall process one request at a time, from the request to the completion of its reply or to the end of its processing without a reply. A further request in this time shall not be processed, with the event of SD-IF-06, except an abort request: it ends the open transfer and the processing without a further reply; the answer of `ocan_od` is not used, and a reply that `ocan_dispatch` has already taken completes. A download whose processing is aborted while its object is written may have written the object. | 7.2.4.2.16 | 6.1a |

### 2.3 Download (SD-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| SD-DL-01 | An expedited initiate download request (e = 1) shall write the object with 4 - n data bytes when the size is indicated (s = 1), and with the number of bytes not indicated (s = 0). The reply is the initiate download response with the index and sub-index of the request, or an abort with the abort code of `ocan_od`. | 7.2.4.3.3 | 6.1a, 8.3.1c |
| SD-DL-02 | A segmented initiate download request (e = 0) with an indicated size (s = 1) of 1 to 8 bytes shall open a segmented download, answered with the initiate download response. A size above 8 shall be answered with an abort, code 0607 0012h; a size of 0 and a request without an indicated size (s = 0) with an abort, code 0607 0010h (Table 11-1). | 7.2.4.3.3, 7.2.4.3.17 | 11.1 |
| SD-DL-03 | Each download segment request of an open segmented download shall add its 7 - n data bytes to the transfer and be answered with the download segment response; more than 8 bytes in total shall be answered with an abort, code 0504 0005h (out of memory), and end the transfer. | 7.2.4.3.4 | 6.1a |
| SD-DL-04 | The last segment (c = 1) shall end the segmented download: when the number of bytes differs from the indicated size, with an abort, code 0607 0010h; otherwise with a write of the object with that number of bytes, answered with the download segment response or with an abort with the abort code of `ocan_od`. | 7.2.4.3.4, 7.2.4.3.17 | 6.1a, 8.3.1c |

### 2.4 Upload (SD-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| SD-UL-01 | An initiate upload request shall read the object. An abort code of `ocan_od` shall be answered with an abort with that code. An object of 1 to 4 bytes shall be answered with the expedited initiate upload response (e = 1, s = 1, n = 4 - the number of bytes) and its data. An object of 5 to 8 bytes shall open a segmented upload, answered with the initiate upload response with the indicated size (e = 0, s = 1, the size in bytes 4 to 7). An answer of `ocan_od` with 0 or more than 8 data bytes shall be answered with an abort, code 0800 0000h (general error). | 7.2.4.3.6 | 6.1a, 11.1 |
| SD-UL-02 | Each upload segment request of an open segmented upload shall be answered with the upload segment response with the next up to 7 data bytes, n = the number of bytes without data and c = 1 on the last segment, which ends the transfer. | 7.2.4.3.7 | 6.1a |

### 2.5 Reply (SD-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| SD-TX-01 | Every reply shall have the DLC 8; bytes without content are 0. An abort shall have the command specifier 4, the index and sub-index of SD-PR-01 and the abort code. | 7.2.4.3.17 | 6.1a |
| SD-TX-02 | At most one reply shall be outstanding. A reply that `ocan_dispatch` has taken and that does not complete within 256 ticks shall end the wait with the event of SD-IF-06, without a repetition. A completion while no reply is outstanding shall be ignored. | none | none |
| SD-TX-03 | A reply that completes as aborted shall end the transfer. | 7.2.4.2.16 | 8.3.3e |
| SD-TX-04 | An access of `ocan_od` without an answer within 512 ticks shall end the processing with an abort, code 0800 0000h (general error), the code of the time-out of the application port (OD-AP-03), and with the event of SD-IF-06; after an abort request, a cleared SDO enable or a reset event during the access (SD-PR-09, SD-RS-01, SD-RS-02) without a reply. The bound lies above the answer time of `ocan_od` (OD-IF-01, OD-AP-03). | none | none |

### 2.6 NMT state and status (SD-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| SD-RS-01 | When the SDO enable is cleared, an open transfer and the processing of a request shall end without a reply and without an abort. | 7.3.2.2.4, 7.3.2.2.5 | 6.5.4a |
| SD-RS-02 | The reset application and the reset communication events shall end an open transfer and the processing of a request without a reply. | 7.3.2.2.1 | 6.5.4a |
| SD-RS-03 | The state "a segmented transfer is open" shall be set by the initiate response of a segmented download or upload and cleared by its last segment, by an abort sent or received, by a new initiate request, by the clearing of the SDO enable and by the resets of SD-RS-02 and of the hardware. A client that stops in the middle of a transfer leaves the state set until one of these events. | 7.2.4.3.2 | 6.1a |
| SD-RS-04 | After a hardware reset no transfer shall be open and no request in processing. | 7.3.2.2.1 | 8.3.2a |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Request with a DLC below 8 | SD-1 | Not processed; event |
| Block transfer or command specifier 7 | SD-1 | Abort 0504 0001h |
| Segment without an open transfer of its direction | SD-1 | Abort 0504 0001h; a transfer of the other direction ends |
| Toggle bit not alternated | SD-1 | Abort 0503 0000h; the transfer ends |
| Request during the processing of another one | SD-1 | Not processed; event; an abort request ends the processing |
| Segmented download larger than 8 bytes, with a size of 0 or without a size, or with a size that the segments do not match | SD-2 | Abort 0607 0012h, 0607 0010h, 0504 0005h |
| Abort code of `ocan_od` | SD-2 | Abort with that code |
| Answer of `ocan_od` to a read with 0 or more than 8 data bytes | SD-2 | Abort 0800 0000h |
| Access of `ocan_od` without an answer within 512 ticks | SD-2 | Abort 0800 0000h; event |
| Reply without completion within 256 ticks | SD-3 | Wait ended; event; not repeated |
| Reply aborted by the dispatch | SD-3 | The transfer ends |
| SDO enable cleared, reset application, reset communication | SD-1 | Transfer and processing end without a reply |

## 4. Configuration parameters

`ocan_sdo` has no generics. The default COB-IDs are those of `ocan_dispatch` (DS-RX-01, DS-TX-02).

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 6.1a, 11.1 (7.2.4.1) | One SDO server per node; its communication parameter (1200h) is omitted, as the applicability matrix states, and `ocan_od` answers 0602 0000h for it |
| 11.1 (7.2.4.3) | The applicability matrix makes the expedited transfer mandatory and the other transfers mission dependent. OpenCAN implements the expedited and the segmented transfer (D3); the block transfer is refused with 0504 0001h, the only code of \[CiA301\] table 22 that fits, without the fall-back of the protocol switch threshold of section 7.2.4.3.13 |
| 11.1 (7.2.4.2.2 to 7.2.4.2.7) | The applicability matrix makes the size field mandatory with the segmented transfer. The server refuses a segmented download without an indicated size with 0607 0010h and indicates the size in every initiate upload response |
| \[CiA301\] 7.2.4.3.3 | An expedited download without an indicated size writes as many bytes as the data type of the object has (OD-IF-01, OD-WR-02) |
| \[CiA301\] 7.2.4.3.4, 7.2.4.3.7 | A segment with the wrong toggle bit is to be ignored, and the server may abort. OpenCAN aborts with 0503 0000h, the code defined for this case: a silent ignore leaves both sides waiting for the time-out of the client |
| \[CiA301\] Annex A | The protocol time-out is implementation specific and belongs to the client. The server has none: a transfer that waits for the next segment blocks nothing, and every initiate request, a stop and a reset end it (SD-PR-06, SD-RS-01, SD-RS-02). The state of SD-RS-03 shows such a transfer |
| \[CiA301\] Annex A, 9.4.8a | A frame with a DLC below 8 is not an SDO request and is handled locally, without an abort. Clause 9.4.8a states the same rule for the minimal set, which has no SDO server (D3) |
| D11 | The server takes every request event without back pressure. SDO is a confirmed service: a client sends its next request after the reply, so a request during the processing of another one is a fault of the client and is not processed (SD-PR-09) |
| \[CiA301\] 7.2.4.2.16 | `ocan_od` has no cancel input: an abort request during the write of an expedited download or of the last segment of a segmented download ends the processing without a reply, but the object may have been written. The user guide states this |
| \[CiA301\] 7.3.2.2.4 (corrigendum 3) | A device that enters Stopped sends no SDO abort; the transfer ends silently (SD-RS-01) |
| 8.3.3e | During a bus selection process the node is in Pre-operational and the SDO server stays available. `ocan_dispatch` passes the requests of the active bus only, and a reply waits during a bus switch (DS-TX-08); a transfer continues on the new active bus when the client follows it |
