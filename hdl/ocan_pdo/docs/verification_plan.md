# ocan_pdo: Verification Plan

## 1. Overview

`ocan_pdo` is verified in two benches:

- `direct`: the bench drives the SYNC and receive PDO events, the transmission types, the NMT inputs, the tick and
  the port of the user logic cycle by cycle, and answers the transmit handshake of every transmit PDO like
  `ocan_dispatch`. A reference model of the PDO block, written from \[CiA301\] and the specification, predicts every
  output in every cycle. It is independent of the registers of the architecture.
- `network`: `ocan_pdo` with `ocan_nmt`, `ocan_od`, `ocan_time`, `ocan_dispatch` and `ocan_link` on the CAN network
  model of `tb/`. A model node is the NMT master, the SYNC producer and the peer of the PDOs. This bench shows the
  PDOs on the bus in the NMT states that the master sets, and their SYNC phase against the Local Time PDO.

Tests observe the ports of `ocan_pdo`, the buses and the model logs only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_pdo_tb` | `ocan_pdo_th` | `ocan_pdo`, `Clk` 40 MHz; drivers of the SYNC and receive PDO events (every DLC, every number), of `Cfg_RpdoType` and `Cfg_TpdoType` (every value 0 to 255), of `Nmt_EnaPdo` and `Nmt_ResetComm`; a tick generator whose period the test sets; a model of the user logic (requests, data that change in every cycle); a responder per transmit PDO like `ocan_dispatch` (delays of `TxTpdo_Ready`, the reject path, `TxTpdo_Done`, `TxTpdo_Aborted` after the take, no completion, completions while no request waits); the reference model |
| `ocan_pdo_net_tb` | `ocan_pdo_net_th` | `ocan_pdo`, `ocan_nmt`, `ocan_od`, `ocan_time`, `ocan_dispatch` and `ocan_link` ("Selective") with `ocan_tb_can_bus` and the model nodes M1 (NMT master, SYNC producer, producer of the receive PDOs, consumer of the transmit PDOs) and M2 on each bus, 1 Mbit/s with the bit timing of the plan of `ocan_link`, `Clk` 40 MHz; the NODE-ID 5, COB-IDs of the pre-defined connection set, the time PDOs with identifiers of the generics; the inputs of `ocan_redundancy` to `ocan_nmt` as constants of the harness; the active bus set by the test; a model of the user logic at the port of `ocan_pdo` |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | `NumRpdo_g` = 4, `NumTpdo_g` = 4 | All test cases of the direct bench |
| `n00`, `n13`, `n22`, `n31` | `NumRpdo_g` and `NumTpdo_g` = 0 and 0, 1 and 3, 2 and 2, 3 and 1 | Every number of PDOs: absent PDOs (TC-PD-18) and the random test (TC-PD-15) |
| `net` | od, nmt: `MinimalSet_g` = false | Network bench, clause 6 slave |
| `net_minimal` | od, nmt: `MinimalSet_g` = true, `TimePdos_g` = false | Network bench, minimal set (TC-PD-17) |

`NumRpdo_g` and `NumTpdo_g` change the structure, so every value 0 to 4 of each is simulated.

Checkers that run in every test of the direct bench:

- every output (`TxTpdo_Valid`, `TxTpdo_Dlc`, `TxTpdo_Data`, `Rpdo_Valid`, `Rpdo_Data`, `Sync_Valid`,
  `Stat_TpdoBusy`, `Stat_PdoEnabled`, `Evt_TpdoSent`, `Evt_TpdoAborted`, `Err_RxLength`, `Err_TxBusy`,
  `Err_TxTimeout`) equals the reference in every cycle;
- `TxTpdo_Valid` and `TxTpdo_Data` of a request stay stable until `TxTpdo_Ready`; never a second request of a PDO
  before the completion or the time-out of the first one.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_rpdo_event` (TC-PD-01) | Receive PDOs 1 to 4 with types 254 and 255 and data that depend on every bit: `Rpdo_Valid` and the data one cycle after the event, data byte k - 1 at sub-index k, the data held until the next PDO of the same number, other PDOs unchanged | PD-RX-01, PD-RX-03, PD-RX-07, PD-IF-01, PD-IF-06 |
| `test_rpdo_length` (TC-PD-02) | Receive PDOs with DLC 0 to 7: not processed, `Err_RxLength` of that PDO, the data at the port and the held data unchanged; DLC 8 to 15: processed with 8 bytes | PD-RX-02, PD-IF-07 |
| `test_rpdo_sync` (TC-PD-03) | Types 0, 1 and 240: no pass at the reception, the data passed one cycle after the next SYNC with DLC 0 and with DLC 1, all held PDOs in the same cycle; several PDOs between two SYNCs: the last one; a type changed to 254 between the reception and the SYNC: still passed at the SYNC; a SYNC with DLC 2 to 15 passes nothing; a SYNC without held data passes nothing | PD-RX-04, PD-RX-06, PD-SY-01 |
| `test_rpdo_reserved` (TC-PD-04) | Every type from 241 to 253: no pass, no event | PD-RX-05, PD-IF-03 |
| `test_sync` (TC-PD-05) | SYNCs with DLC 0 to 15 and every counter byte: `Sync_Valid` one cycle after the SYNCs with DLC 0 and 1 only, also with `Nmt_EnaPdo` = '0' | PD-SY-01, PD-SY-02 |
| `test_tpdo_cyclic` (TC-PD-06) | Types 1, 2, 3, 17 and 240: a request at every n-th SYNC, counted from the first SYNC after the hardware reset, a reset communication and a change of the type; a SYNC in the cycle of each of these events not counted; the data of the cycle of the SYNC event with data that change in every cycle; DLC 8, data byte k - 1 at sub-index k; the requests of the user logic without effect; the request held while `TxTpdo_Ready` is late (no window) | PD-TX-01, PD-TX-02, PD-SY-03, PD-IF-02, PD-IF-06 |
| `test_tpdo_acyclic` (TC-PD-07) | Type 0: a request of the user logic, then a SYNC: one PDO with the data of the SYNC cycle; several requests: one PDO; a request in the cycle of a SYNC: the PDO at the next SYNC; no request: no PDO; a change of the type while a request waits: discarded | PD-TX-03 |
| `test_tpdo_event` (TC-PD-08) | Types 254 and 255: a PDO one cycle after each request with the data of the request cycle; SYNCs without effect; every type from 241 to 253: no PDO at requests and SYNCs; no PDO without a trigger over 2000 ticks (no event timer) | PD-TX-04, PD-TX-05, PD-TX-06, PD-IF-03 |
| `test_tpdo_busy` (TC-PD-09) | Requests and due SYNCs while a request is offered and while it is taken: not requested, `Err_TxBusy`; a request and a due SYNC in the cycle of `TxTpdo_Done`, of `TxTpdo_Aborted` and of the reject path: requested with the new data; `TxTpdo_Valid` and the data unchanged while `TxTpdo_Ready` is held off for 1000 cycles | PD-TX-07, PD-IF-07 |
| `test_tpdo_handshake` (TC-PD-10) | Delays of `TxTpdo_Ready`, the reject path, `TxTpdo_Aborted` after the take, `TxTpdo_Done`: `Evt_TpdoSent` and `Evt_TpdoAborted`, no repetition; no completion: `Err_TxTimeout` 256 ticks after the take, no repetition, the next request served, the other PDOs unaffected; completions while no request waits (idle, offered without `TxTpdo_Ready`, late after the time-out): ignored | PD-TX-08, PD-TX-09, PD-IF-05, PD-IF-07 |
| `test_nmt` (TC-PD-11) | `Stat_PdoEnabled` equal to `Nmt_EnaPdo` in every cycle; `Nmt_EnaPdo` = '0': receive PDOs not processed, due PDOs not requested without an event, requests without effect, the SYNC counts continue (the phase after `Nmt_EnaPdo` = '1' again); the exit from Operational with held synchronous data of every PDO: not passed at the next SYNC, also when the SYNC comes in the cycle of the exit; with a request of type 0 waiting: no PDO at the next SYNC and none after the return to Operational; a request offered and taken at the exit: completes as the responder reports it | PD-RS-01, PD-RS-02, PD-IF-04, PD-IF-07 |
| `test_reset_comm` (TC-PD-12) | `Nmt_ResetComm` with held data, a waiting request of type 0 and counts in progress: the counts restart, the held data and the request discarded; a receive PDO and a SYNC in the cycle of the event: not processed, not counted; the data at the port kept; an offered and a taken request complete as the responder reports it | PD-RS-03, PD-IF-04 |
| `test_reset` (TC-PD-13) | `Rst` with held data, pending requests and counts in progress: no request pending, the data at the port 0, the counts from the start | PD-RS-04 |
| `test_back_to_back` (TC-PD-14) | SYNC and receive PDO events 46 bit times apart at 1 Mbit/s and in consecutive cycles; all four transmit PDOs due at the same SYNC: four requests in the same cycle; all four held receive PDOs passed in the same cycle | PD-IF-08, PD-RX-04, PD-TX-02 |
| `test_random` (TC-PD-15) | 20000 cycles of random SYNCs (every DLC), receive PDOs (every number and DLC), requests, types (all 256 values, changed only between events), handshake results, ticks and NMT events, compared with the reference in every cycle | PD-RX-02 to PD-RX-06, PD-TX-02 to PD-TX-09, PD-RS-01 to PD-RS-03, PD-SY-01 |
| `test_net_pdo` (TC-PD-16) | Bench `network`, on bus A and on bus B: M1 starts the node; RPDOs 1 to 4 with type 254 and with type 1 (passed at the next SYNC); TPDOs 1 to 4 with types 254, 1, 3 and 0 on the bus with the identifiers 180h + NODE-ID to 480h + NODE-ID, DLC 8 and the bytes of the user logic; the TPDO of type 3 at the same SYNCs as the Local Time PDO of type 3, and at a SYNC where all are due the TPDOs before the Local Time PDO; M1 sets Pre-operational after an RPDO of type 1 and after a request of type 0, before the SYNC: no data passed, no TPDO, also after the next start; in Pre-operational no PDO | PD-IF-01, PD-IF-02, PD-RX-01, PD-TX-01, PD-TX-02, PD-SY-01, PD-RS-01, PD-RS-02 |
| `test_net_minimal` (TC-PD-17) | Bench `net_minimal`, on bus A: the node in Operational by local control; an RPDO of M1 (telemetry request) passed at once and the TPDO that the model of the user logic requests in reply on the bus; a TPDO that the model requests at every `Sync_Valid` on the bus after every SYNC (clause 9.4.3b) | PD-SY-02, PD-RX-03, PD-TX-04 |
| `test_absent` (TC-PD-18) | Configurations `default`, `n00`, `n13`, `n22` and `n31`: receive PDO events with the numbers of absent PDOs not processed, the outputs of absent PDOs 0, their requests and `TxTpdo_Ready`, `TxTpdo_Done` and `TxTpdo_Aborted` inputs without effect | PD-IF-01, PD-IF-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PD-IF-01 | TC-PD-01, TC-PD-16, TC-PD-18 |
| PD-IF-02 | TC-PD-06, TC-PD-16, TC-PD-18 |
| PD-IF-03 | TC-PD-04, TC-PD-08 |
| PD-IF-04 | TC-PD-11, TC-PD-12 |
| PD-IF-05 | TC-PD-10 |
| PD-IF-06 | TC-PD-01, TC-PD-06 |
| PD-IF-07 | TC-PD-02, TC-PD-09, TC-PD-10, TC-PD-11 |
| PD-IF-08 | TC-PD-14 |
| PD-SY-01 | TC-PD-03, TC-PD-05, TC-PD-15, TC-PD-16 |
| PD-SY-02 | TC-PD-05, TC-PD-17 |
| PD-SY-03 | TC-PD-06 |
| PD-RX-01 | TC-PD-01, TC-PD-16 |
| PD-RX-02 | TC-PD-02, TC-PD-15 |
| PD-RX-03 | TC-PD-01, TC-PD-15, TC-PD-17 |
| PD-RX-04 | TC-PD-03, TC-PD-14, TC-PD-15 |
| PD-RX-05 | TC-PD-04, TC-PD-15 |
| PD-RX-06 | TC-PD-03, TC-PD-15 |
| PD-RX-07 | TC-PD-01 |
| PD-TX-01 | TC-PD-06, TC-PD-16 |
| PD-TX-02 | TC-PD-06, TC-PD-14, TC-PD-15, TC-PD-16 |
| PD-TX-03 | TC-PD-07, TC-PD-15 |
| PD-TX-04 | TC-PD-08, TC-PD-15, TC-PD-17 |
| PD-TX-05 | TC-PD-08, TC-PD-15 |
| PD-TX-06 | TC-PD-08, TC-PD-15 |
| PD-TX-07 | TC-PD-09, TC-PD-15 |
| PD-TX-08 | TC-PD-10, TC-PD-15 |
| PD-TX-09 | TC-PD-10, TC-PD-15 |
| PD-RS-01 | TC-PD-11, TC-PD-15, TC-PD-16 |
| PD-RS-02 | TC-PD-11, TC-PD-15, TC-PD-16 |
| PD-RS-03 | TC-PD-12, TC-PD-15 |
| PD-RS-04 | TC-PD-13 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| SYNC with another DLC | TC-PD-03, TC-PD-05 |
| Receive PDO with a DLC below 8 | TC-PD-02 |
| Reserved transmission types 241 to 253 | TC-PD-04, TC-PD-08 |
| PDO due while its request is pending | TC-PD-09 |
| Rejected, aborted, missing and stray completions | TC-PD-10 |
| PDO enable cleared, exit from Operational with held data and a waiting request | TC-PD-11, TC-PD-16 |
| Reset communication with held data and a waiting request | TC-PD-12 |
| Events of absent PDOs | TC-PD-18 |

A deliberate fault of the RTL for every compare (DLC, transmission type ranges, `SyncCnt`, `TxTmo`), every same-cycle
rule of PD-RX-06, PD-TX-02, PD-TX-03 and PD-TX-07, the busy rule, the handshake, the time-out and the discard at the
exit from Operational and at the reset communication is simulated with the tests that must detect it (verification
report, section 4).

## 6. Input space covered by the directed tests

| Input | Requirements | Classes and test cases |
| --- | --- | --- |
| DLC of the SYNC | PD-SY-01 | 0 to 15 (TC-PD-05) |
| DLC of a receive PDO | PD-RX-02 | 0 to 15 (TC-PD-02) |
| Transmission type of a receive PDO | PD-RX-03 to PD-RX-05 | 0, 1, 240, 241 to 253, 254, 255 (TC-PD-01, TC-PD-03, TC-PD-04); all values (TC-PD-15) |
| Transmission type of a transmit PDO | PD-TX-02 to PD-TX-05 | 0, 1, 2, 3, 17, 240, 241 to 253, 254, 255 (TC-PD-06 to TC-PD-08); all values (TC-PD-15) |
| Completion of a request | PD-TX-07 to PD-TX-09 | Sent, aborted after the take, reject path, none, stray (TC-PD-09, TC-PD-10) |
| Events of `ocan_nmt` in each state of a transmit PDO and with held data | PD-RS-01 to PD-RS-03 | TC-PD-11, TC-PD-12 |
| Number of PDOs | PD-IF-01, PD-IF-02 | 0 to 4 receive and transmit PDOs (TC-PD-18) |

## 7. Not verified at the ports

- The `when others` branch of `TxSt` cannot be reached from the ports; it recovers only when the synthesis tool
  implements the state machine safely (protection scope of the user guide) and is covered by design review.
- The compares `SyncCnt` >= T - 1 and `TxTmo` >= 255 differ from compares with = only after an upset of the counts,
  which the ports cannot inject; covered by design review.
- The effects of upsets of the registers listed in section 5 of the architecture are covered by design review.
