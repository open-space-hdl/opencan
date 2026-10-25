# ocan_sdo: Verification Plan

## 1. Overview

`ocan_sdo` is verified in two benches:

- `direct`: the bench drives the request events, the NMT inputs and the tick cycle by cycle, answers the transmit
  handshake like `ocan_dispatch` and the access interface like `ocan_od`. The object model of the bench holds
  objects of 1 to 8 bytes, with configurable delays of the answer and configurable abort codes. A reference model of
  the SDO server, written from \[CiA301\] and the specification, predicts every access of the object dictionary and
  every reply frame, and checks the events and `Stat_Open` in every cycle. It is independent of the two state
  variables of the architecture.
- `network`: `ocan_sdo` with `ocan_od`, `ocan_dispatch` and `ocan_link` on the CAN network model of `tb/`. A model node
  is the SDO client. This bench shows the transfers on the bus with the real object dictionary.

Tests observe the ports of `ocan_sdo`, the buses and the model logs only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_sdo_tb` | `ocan_sdo_th` | `ocan_sdo`, `Clk` 40 MHz; drivers of the requests, `Nmt_EnaSdo` and the reset events; a tick generator whose period the test sets; a responder of the transmit handshake like `ocan_dispatch` (delays, `Tx_Done`, `Tx_Aborted`, the reject path, no completion); an object model at the access interface (sizes, delays, abort codes, written values, the behaviour of `ocan_od` at the reset events, an object that never answers); the reference model |
| `ocan_sdo_net_tb` | `ocan_sdo_net_th` | `ocan_sdo`, `ocan_od`, `ocan_dispatch` and `ocan_link` ("Selective") with `ocan_tb_can_bus` and the model nodes M1 (SDO client) and M2 on each bus, 1 Mbit/s with the bit timing of the plan of `ocan_link`, `Clk` 40 MHz; the NODE-ID 5, the NMT state Pre-operational and the service enables as constants of the harness; a register in place of `ocan_time` that takes the writes of 2001h and is the value of 2002h |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | - | All test cases of the direct bench (`ocan_sdo` has no generics) |
| `net` | - | Network bench |

Checkers that run in every test of the direct bench:

- every access of the object dictionary (kind, index, sub-index, data, number of bytes) and every reply frame
  (DLC, data) equal the reference, in the order of the reference;
- never a second reply before the completion of the first one, the frame stable while `Tx_Valid` is '1', one access
  at a time;
- every event (`Err_RxDrop`, `Err_TxTimeout`, `Err_AccTimeout`, `Evt_AbortTx`, `Evt_AbortRx`) and `Stat_Open` are
  expected by the reference in every cycle.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_expedited_download` (TC-SD-01) | Expedited downloads with s = 1 and n = 0 to 3 to objects of 1 to 4 bytes, and with s = 0: the write with 4 - n bytes or with the number 0, the initiate download response with the index and sub-index; every abort code of the object model passed on | SD-DL-01, SD-PR-01, SD-IF-03, SD-TX-01 |
| `test_segmented_download` (TC-SD-02) | Segmented downloads of 1 to 8 bytes in segments with every n: the responses with the toggle bit, one write at the last segment with all bytes, an abort code of the object model at the last segment | SD-DL-02, SD-DL-03, SD-DL-04, SD-PR-05, SD-RS-03 |
| `test_download_sizes` (TC-SD-03) | Indicated size 9 and FFFF FFFFh: 0607 0012h; indicated size 0 and no indicated size: 0607 0010h; segments that end short of or beyond the indicated size: 0607 0010h; more than 8 bytes: 0504 0005h | SD-DL-02, SD-DL-03, SD-DL-04 |
| `test_expedited_upload` (TC-SD-04) | Uploads of objects of 1 to 4 bytes: e = 1, s = 1, n = 4 - size, the data; an abort code of the object model; answers of the object model with 0 and with 9 data bytes: 0800 0000h | SD-UL-01, SD-PR-01 |
| `test_segmented_upload` (TC-SD-05) | Uploads of objects of 5 to 8 bytes: the initiate response with the size, the segments with the data, n, c and the toggle bit | SD-UL-01, SD-UL-02, SD-PR-05, SD-RS-03 |
| `test_toggle` (TC-SD-06) | A wrong toggle bit in the first and in a later segment of a download and of an upload: 0503 0000h, the transfer ends | SD-PR-05 |
| `test_command_errors` (TC-SD-07) | Command specifiers 5, 6 and 7: 0504 0001h with the index and sub-index of the request; a download and an upload segment without a transfer and during a transfer of the other direction: 0504 0001h, the transfer ends; requests with every reserved bit set: processed as without them | SD-PR-03, SD-PR-04, SD-PR-08 |
| `test_client_abort` (TC-SD-08) | A client abort during an open download and upload: the transfer ends, no reply, `Evt_AbortRx`; while idle: ignored, without `Evt_AbortRx`; during the access of an expedited download, of the last segment and of an upload: no reply, and the written object of the object model shows that the write took effect; cycle by cycle from the take of the access to the take of the reply, the cycle of the answer included; during an offered and during a taken reply | SD-PR-07, SD-PR-09, SD-IF-06 |
| `test_new_initiate` (TC-SD-09) | A new initiate during an open download and upload: the old transfer ends without an abort, the new one is correct. An abandoned transfer, the client silent after the initiate response for 2000 ticks: `Stat_Open` stays set, and the next initiate ends it and runs correctly | SD-PR-06, SD-RS-03 |
| `test_dlc` (TC-SD-10) | Requests with DLC 0 to 7: not processed, `Err_RxDrop`, no reply, an open transfer unchanged; DLC 8 to 15: processed | SD-PR-02, SD-IF-06 |
| `test_busy` (TC-SD-11) | Requests while an access is outstanding and while a reply is offered and taken: not processed, `Err_RxDrop`; requests in consecutive cycles | SD-PR-09, SD-IF-07, SD-IF-06 |
| `test_reply_handshake` (TC-SD-12) | Delays of `Tx_Ready`, the reject path, `Tx_Aborted` after the take (the transfer ends), no completion: `Err_TxTimeout` 256 ticks after the take, also for the reply after an access answered after 200 ticks and for the abort after an access without an answer, no repetition, the next request served; `Evt_AbortTx` for an abort frame completed as sent, none for one completed as aborted; completions while no reply is outstanding (idle, during an access of the user logic, during an offered reply): ignored | SD-TX-01, SD-TX-02, SD-TX-03, SD-IF-02, SD-IF-05, SD-IF-06 |
| `test_nmt` (TC-SD-13) | `Nmt_EnaSdo` cleared and each reset event during an open transfer, an access not yet taken, an outstanding access of the user logic, an offered and a taken reply: the transfer and the processing end without a reply and without an abort; `Stat_Open` cleared. The event in the cycle in which `ocan_od` takes the access (an own object, and an object of the user logic answered with 0800 0022h), in the cycle of the answer and in the cycle of a request: no reply; after a reset event in the cycle of the take, a request in the cycle of the discarded answer is not processed. A request right after the event during a taken reply is processed | SD-RS-01, SD-RS-02, SD-RS-03, SD-IF-04 |
| `test_access_timing` (TC-SD-14) | Answers of the object model after 1 cycle, 100 cycles and 255 ticks, and 0800 0000h after 256 ticks: the reply follows the answer by one cycle. An object that takes the access and never answers: `Err_AccTimeout` at the 512th tick and the abort 0800 0000h, the next request served; the same during a client abort: `Err_AccTimeout` without a reply; a client abort in each cycle from 6 before to 2 after `Err_AccTimeout`, the cycle of the 512th tick among them, checked against the reference model in every cycle | SD-IF-03, SD-DL-01, SD-UL-01, SD-TX-04, SD-IF-06 |
| `test_reset` (TC-SD-15) | `Rst` during an open transfer and during a reply: idle afterwards, no reply | SD-RS-04 |
| `test_random` (TC-SD-16) | 5000 random requests (every command specifier, sizes, toggle bits, DLC) with random object sizes, delays, abort codes, handshake results, aborts and NMT events, compared with the reference | SD-PR-01 to SD-PR-09, SD-DL-01 to SD-DL-04, SD-UL-01, SD-UL-02 |
| `test_net_sdo` (TC-SD-17) | Bench `network`, on bus A and on bus B: M1 reads 1018h sub-index 01h (expedited), writes and reads 1017h (expedited), writes 2000h sub-index 02h with s = 0, writes 2001h and reads 2002h as segmented transfers of 7 bytes, and reads an absent object (abort 0602 0000h): every reply on the bus with the identifier 580h + NODE-ID, DLC 8 and the byte order of \[CiA301\] | SD-IF-01, SD-IF-02, SD-IF-03, SD-PR-01, SD-TX-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| SD-IF-01 | TC-SD-17 |
| SD-IF-02 | TC-SD-12, TC-SD-17 |
| SD-IF-03 | TC-SD-01, TC-SD-14, TC-SD-17 |
| SD-IF-04 | TC-SD-13 |
| SD-IF-05 | TC-SD-12 |
| SD-IF-06 | TC-SD-08, TC-SD-10, TC-SD-11, TC-SD-12, TC-SD-14 |
| SD-IF-07 | TC-SD-11 |
| SD-PR-01 | TC-SD-01, TC-SD-04, TC-SD-16, TC-SD-17 |
| SD-PR-02 | TC-SD-10, TC-SD-16 |
| SD-PR-03 | TC-SD-07, TC-SD-16 |
| SD-PR-04 | TC-SD-07, TC-SD-16 |
| SD-PR-05 | TC-SD-02, TC-SD-05, TC-SD-06, TC-SD-16 |
| SD-PR-06 | TC-SD-09, TC-SD-16 |
| SD-PR-07 | TC-SD-08, TC-SD-16 |
| SD-PR-08 | TC-SD-07, TC-SD-16 |
| SD-PR-09 | TC-SD-08, TC-SD-11, TC-SD-16 |
| SD-DL-01 | TC-SD-01, TC-SD-14, TC-SD-16 |
| SD-DL-02 | TC-SD-02, TC-SD-03, TC-SD-16 |
| SD-DL-03 | TC-SD-02, TC-SD-03, TC-SD-16 |
| SD-DL-04 | TC-SD-02, TC-SD-03, TC-SD-16 |
| SD-UL-01 | TC-SD-04, TC-SD-05, TC-SD-14, TC-SD-16 |
| SD-UL-02 | TC-SD-05, TC-SD-16 |
| SD-TX-01 | TC-SD-01, TC-SD-12, TC-SD-17 |
| SD-TX-02 | TC-SD-12 |
| SD-TX-03 | TC-SD-12 |
| SD-TX-04 | TC-SD-14 |
| SD-RS-01 | TC-SD-13 |
| SD-RS-02 | TC-SD-13 |
| SD-RS-03 | TC-SD-02, TC-SD-05, TC-SD-09, TC-SD-13 |
| SD-RS-04 | TC-SD-15 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| Every abort of the protocol and of the sizes | TC-SD-03, TC-SD-06, TC-SD-07 |
| Requests that are not processed (DLC, busy) | TC-SD-10, TC-SD-11 |
| Client aborts in every state | TC-SD-08 |
| Missing and stray completions of the reply | TC-SD-12 |
| Access without an answer | TC-SD-14 |
| Abandoned transfer | TC-SD-09 |

A deliberate fault of the RTL for every abort code, the toggle check, the size checks, the busy rule, the client
abort, the time-out of the reply and the end of a transfer by the NMT events is simulated with the tests that must
detect it (verification report, section 4).

## 6. Input space covered by the directed tests

| Input | Requirements | Classes and test cases |
| --- | --- | --- |
| Command specifier | SD-PR-03, SD-PR-04 | Every value 0 to 7, in every state of the transfer (TC-SD-07, TC-SD-16) |
| Size of the object | SD-DL-01 to SD-UL-02 | 1 to 8 bytes (TC-SD-01, TC-SD-02, TC-SD-04, TC-SD-05) |
| n of the segments | SD-DL-03, SD-UL-02 | 0 to 7 (TC-SD-02, TC-SD-05) |
| DLC | SD-PR-02 | 0 to 15 (TC-SD-10) |
| Delay of the answer of the object dictionary | SD-IF-03, SD-TX-04 | 1 cycle to 256 ticks, and no answer (TC-SD-14) |
| Events of the client and of `ocan_nmt` in each state of `Proc` | SD-PR-09, SD-RS-01, SD-RS-02 | TC-SD-08, TC-SD-11, TC-SD-13 |

## 7. Not verified at the ports

- The `when others` branches of `Xfer` and `Proc` cannot be reached from the ports; they recover only when the
  synthesis tool implements the state machines safely (protection scope of the user guide) and are covered by
  design review.
- The compares `Cnt` >= 8, `TxTmo` >= 255 and `TxTmo` >= 511 differ from compares with = only after an upset of
  the counts, which the ports cannot inject; covered by design review.
- The bound of SD-TX-04 also ends the wait for an answer after an upset of `AccTaken` or of `Proc`, when
  `ocan_od` has no access to answer. The ports cannot inject the upset; the bound itself is tested with an object
  that never answers (TC-SD-14).
