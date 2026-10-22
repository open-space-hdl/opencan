# ocan_time: Verification Plan

## 1. Overview

`ocan_time` is verified in two benches:

- `direct`: the bench drives the SYNC and Spacecraft Time PDO events, the configuration, the Local SCET Set writes,
  the user requests and the reset communication event cycle by cycle, and answers the transmit handshake like
  `ocan_dispatch`. A reference model of the time block, written from the specification, computes the local time of
  every cycle as the last setting plus floor(n * 2^F / f) with exact integer arithmetic, and predicts the samples, the
  frames and the events. This bench checks the exact rate, the settings and the triggers.
- `network`: `ocan_time` with `ocan_dispatch`, `ocan_link` and the CAN network model of `tb/` (see the
  [verification plan of ocan_link](../../ocan_link/docs/verification_plan.md)). A model node acts as SYNC producer and
  time producer. This bench shows the byte order on the bus and the latency of the SYNC sample on both buses.

Tests observe the ports of `ocan_time`, the buses and the model logs only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_time_tb` | `ocan_time_th` | `ocan_time` with `Clk` derived from `ClkFrequency_g`; drivers of the events, the configuration, the writes and the requests; a responder for the transmit handshake with configurable delays and result (`Tx_Done`, `Tx_Aborted`, reject path); the reference model |
| `ocan_time_net_tb` | `ocan_time_net_th` | `ocan_time`, `ocan_dispatch` and `ocan_link` ("Selective") with `ocan_tb_can_bus` and the model nodes M1 (SYNC producer, time producer) and M2 on each bus, 1 Mbit/s with the bit timing of the plan of `ocan_link`, `Clk` 40 MHz; COB-IDs of the pre-defined connection set; service enables and the NODE-ID as constants of the harness; the active bus set by the test |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `default` | `FineBits_g` = 24, `ClkFrequency_g` = 100000000 | All test cases of the direct bench |
| `f40m` | 24, 40000000 | Clock frequency that is not a power of two, long-run rate (TC-TM-02) |
| `f1m` | 24, 1000000 | Lower bound of `ClkFrequency_g`; `Q_c` = 16 |
| `fmax` | 24, 2147483647 | Upper bound of `ClkFrequency_g` |
| `fine0` to `fine23` | 0 to 23, 100000000 | Every other width of the fine time (TC-TM-01, TC-TM-03, TC-TM-07, TC-TM-11) |
| `net` | 24, 40000000 | Network bench |

`FineBits_g` changes the structure, so every value from 0 to 24 is simulated. `ClkFrequency_g` is simulated at both
bounds and at two values between them; the clock period of the bench is derived from the generic, and the reference
model counts cycles, so a period rounded to the time resolution of the simulator does not affect the checks.

Checkers that run in every test of the direct bench:

- `Time_Coarse`, `Time_Fine` and `Stat_Scet` equal the reference in every cycle; the bits of `Time_Fine` below F are 0;
- never a second `Tx_Valid` before the completion of the first request, and the frame stable while `Tx_Valid` is '1';
- every event (`Evt_Set`, `Evt_Sync`, `Err_TxBusy`, `Err_RxDrop`) is expected by the reference.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_counter_rate` (TC-TM-01) | From a setting, the local time equals the set value plus floor(n * 2^F / f) in every one of 100000 cycles, in every configuration of the direct bench | TM-CT-01, TM-CT-02, TM-IF-05 |
| `test_long_run_rate` (TC-TM-02) | Configurations `f40m` and `f1m`: 2^24 + 12345 cycles without a setting, compared with the reference at every 2^20 cycles and at the end, without any deviation | TM-CT-02 |
| `test_coarse_wrap` (TC-TM-03) | Set to coarse time 2^32 - 1 and fine time a few units below its maximum: the time wraps to 0 with the exact advance | TM-CT-03 |
| `test_reset_time` (TC-TM-04) | After `Rst`: local time 0, `Stat_TimeSet` '0', no SYNC sample. `Nmt_ResetComm` after a setting and a sample: local time, `Stat_TimeSet`, the sample and a later high-resolution setting are unchanged | TM-CT-04, TM-IF-07 |
| `test_scet_set` (TC-TM-05) | 1000 writes of Local SCET Set with random values: the value from the next cycle on, the exact advance from there, `Evt_Set` and `Stat_TimeSet`; `Stat_Scet` is the local time. A write in the cycle of a basic setting and in the second cycle of a high-resolution setting: the write wins | TM-CT-05, TM-IF-03, TM-IF-05 |
| `test_sync_sample` (TC-TM-06) | SYNCs with DLC 0 and with DLC 1 and every counter byte: the sample is the local time of the cycle of the event, `Evt_Sync` one cycle later. SYNCs with DLC 2 to 15: no sample, no event, no count | TM-SY-01, TM-SY-02, TM-IF-01 |
| `test_rx_format` (TC-TM-07) | Spacecraft Time PDOs with random SCETs and the example of the specification (section 2.6) in every width of the fine time: coarse and fine time decoded with the bytes least significant first, the fine time cut to F bits. DLC 8: the first seven bytes. DLC 0 to 6: not processed, `Err_RxDrop` | TM-RX-01, TM-RX-02, TM-IF-01 |
| `test_rx_basic` (TC-TM-08) | Types 254 and 255: the local time is the received SCET from the cycle after the event, with the exact advance from there; `Evt_Set` and `Stat_TimeSet` | TM-RX-03 |
| `test_rx_high_res` (TC-TM-09) | Types 0, 1, 120 and 240: a SYNC sample, then the Spacecraft Time PDO 1, 2, 1000, 1000000 and a random number of cycles later. After the two-cycle load the local time equals that of an ideal setting at the SYNC: the received SCET plus floor(n * 2^F / f) for the n cycles since the sample, compared in every cycle after the load. Without a SYNC sample since `Rst`: not processed, `Err_RxDrop`; a sample taken before `Nmt_ResetComm` still counts | TM-RX-04, TM-RX-05, TM-IF-07 |
| `test_rx_types_none` (TC-TM-10) | Types 241 to 253: not processed, `Err_RxDrop`, no change of the local time | TM-RX-06 |
| `test_tx_format` (TC-TM-11) | The Local Time PDO has DLC 7, the bytes of the specification (section 2.6) for the example and random times in every width of the fine time, the bits below F and byte 7 at 0 | TM-TX-01, TM-IF-02 |
| `test_tx_sync_types` (TC-TM-12) | Types 1, 2, 7 and 240: a request at every n-th sampled SYNC with the sample of that SYNC, counted from the first SYNC after `Rst`, after `Nmt_ResetComm` and after a change of the type; SYNCs with a wrong DLC are not counted | TM-TX-02, TM-IF-07 |
| `test_tx_type0` (TC-TM-13) | Type 0: a user request, then the next sampled SYNC gives a request with that sample; several user requests before one SYNC give one frame; `Nmt_ResetComm` between the user request and the SYNC discards it | TM-TX-03, TM-IF-04, TM-IF-07 |
| `test_tx_on_request` (TC-TM-14) | Types 254 and 255: a user request gives a request in the next cycle, with the last sample when the Spacecraft Time PDO has a type 0 to 240 and a sample exists, otherwise with the local time of the cycle of the request | TM-TX-04, TM-IF-04 |
| `test_tx_types_none` (TC-TM-15) | Types 241 to 253: no request at SYNCs or at user requests | TM-TX-05 |
| `test_tx_pending` (TC-TM-16) | The responder holds `Tx_Ready` and the completion: requests that fall due meanwhile are not made and give `Err_TxBusy`. Completion by `Tx_Done`, by `Tx_Aborted` and by the reject path; a request that falls due in the cycle of a completion is made; an aborted frame is not repeated; `Nmt_ResetComm` while a request is pending at the responder leaves it to complete | TM-TX-06, TM-IF-02, TM-IF-05, TM-IF-07 |
| `test_back_to_back` (TC-TM-17) | A SYNC followed by a Spacecraft Time PDO 1, 2 and 3 cycles later, a PDO followed by a SYNC one cycle later, and 2000 random events in consecutive cycles, checked against the reference | TM-IF-06 |
| `test_net_time` (TC-TM-18) | Bench `net`: M1 sends a SYNC and then the Spacecraft Time PDO (type 1) with its time at the SYNC; the local time of the node at the sample equals that time plus the fixed latency stated in the user guide. The Local Time PDO of the node (type 1) on the bus carries its sample in the byte order of the specification. The latency from the end of the SYNC frame to `Evt_Sync` is the same on bus A and on bus B | TM-SY-01, TM-RX-01, TM-RX-04, TM-TX-01, TM-TX-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| TM-IF-01 | TC-TM-06, TC-TM-07 |
| TM-IF-02 | TC-TM-11, TC-TM-16 |
| TM-IF-03 | TC-TM-05 |
| TM-IF-04 | TC-TM-13, TC-TM-14 |
| TM-IF-05 | TC-TM-01, TC-TM-05, TC-TM-16 |
| TM-IF-06 | TC-TM-17 |
| TM-IF-07 | TC-TM-04, TC-TM-09, TC-TM-12, TC-TM-13, TC-TM-16 |
| TM-CT-01 | TC-TM-01 |
| TM-CT-02 | TC-TM-01, TC-TM-02 |
| TM-CT-03 | TC-TM-03 |
| TM-CT-04 | TC-TM-04 |
| TM-CT-05 | TC-TM-05 |
| TM-SY-01 | TC-TM-06, TC-TM-18 |
| TM-SY-02 | TC-TM-06 |
| TM-RX-01 | TC-TM-07, TC-TM-18 |
| TM-RX-02 | TC-TM-07 |
| TM-RX-03 | TC-TM-08 |
| TM-RX-04 | TC-TM-09, TC-TM-18 |
| TM-RX-05 | TC-TM-09 |
| TM-RX-06 | TC-TM-10 |
| TM-TX-01 | TC-TM-11, TC-TM-18 |
| TM-TX-02 | TC-TM-12, TC-TM-18 |
| TM-TX-03 | TC-TM-13 |
| TM-TX-04 | TC-TM-14 |
| TM-TX-05 | TC-TM-15 |
| TM-TX-06 | TC-TM-16 |

## 5. Negative tests

| Checker or protection | Test |
| --- | --- |
| SYNC with a wrong DLC | TC-TM-06 |
| Spacecraft Time PDO with fewer than seven bytes | TC-TM-07 |
| High-resolution PDO without a SYNC sample | TC-TM-09 |
| Transmission types 241 to 253 | TC-TM-10, TC-TM-15 |
| Local Time PDO due while one is pending; aborted frames | TC-TM-16 |

## 6. Functional coverage

| Coverpoint | Requirements | Bins | Goal |
| --- | --- | --- | --- |
| Transmission type of the Spacecraft Time PDO | TM-RX-03 to TM-RX-06 | 0, 1 to 239, 240, 241 to 253, 254, 255 | 100 % |
| Transmission type of the Local Time PDO | TM-TX-02 to TM-TX-05 | 0, 1, 2 to 239, 240, 241 to 253, 254, 255 | 100 % |
| Cycles from the sample to the high-resolution PDO | TM-RX-04 | 1, 2, 3 to 999, 1000 to 999999, 1000000 and more | 100 % |
| DLC of the received frames | TM-SY-02, TM-RX-02 | SYNC {0, 1, 2 to 15}; Spacecraft Time PDO {0 to 6, 7, 8} | 100 % |
| Same-cycle inputs | TM-CT-05, TM-TX-06 | write with a basic setting; write with the second cycle of a high-resolution setting; due request with a completion | 100 % |

## 7. Not verified at the ports

The `when others` branch of the transmit handshake cannot be reached from the ports; `docs/coverage.md` justifies it.
