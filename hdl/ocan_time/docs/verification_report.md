# ocan_time: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_time*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_time_tb` | 19 | 121 | 121 |
| `ocan_time_net_tb` | 1 | 1 | 1 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): TC-TM-01 runs in every
configuration of the direct bench (`default`, `f40m`, `f1m`, `fmax`, `fine0` to `fine23`), TC-TM-02 in `f40m` and
`f1m`, TC-TM-06 and TC-TM-14 in `default` and `f1m`, TC-TM-03, TC-TM-07 and TC-TM-11 in `default` and `fine0` to
`fine23`, every other direct test case in `default`. In every cycle of the direct testbench the reference model
predicted `Time_Coarse`, `Time_Fine`, `Stat_Scet`, `Stat_TimeSet`, the events, `Tx_Valid` and, while it is '1',
`Tx_Dlc` and `Tx_Data`, and no output differed from it. The model computes the local time in closed form from the
specification, the last setting plus floor(n * 2^F / f), and is independent of the accumulator of the architecture.
The network testbench runs `ocan_time` with `ocan_dispatch` and `ocan_link` on the CAN network model of `tb/`.

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Measured values

| Item | Value |
| --- | --- |
| Advance of the local time | Equal to floor(n x 2^F / f) in every cycle of every run, for f = 1 MHz, 40 MHz, 100 MHz and 2^31 - 1 Hz and every F from 0 to 24 (TC-TM-01); over 2^24 + 12345 cycles at 40 MHz and 1 MHz without a deviation (TC-TM-02) |
| `Rx_SyncValid` to the sample and `Evt_Sync` | The local time of the cycle of the event, on every phase of the accumulator at 100 MHz and 1 MHz: in the Local Time PDO of type 1 for 66 SYNCs (TC-TM-06) and as the last sample of types 254 and 255 for 66 SYNCs, also with the request in the cycle of the SYNC (TC-TM-14); `Evt_Sync` 1 clock cycle later (TC-TM-06) |
| `Rx_TimeValid` (basic protocol) and `Cfg_SetValid` to the setting | The set value 1 clock cycle later (TC-TM-05, TC-TM-08) |
| `Rx_TimeValid` (high-resolution protocol) to the setting | 2 clock cycles; from then on the local time is the SCET at the sample plus floor(n x 2^F / f), for 0 to 10^6 cycles between the sample and the PDO (TC-TM-09, TC-TM-20) |
| Sampled SYNC or `Req_Valid` to `Tx_Valid` | 1 clock cycle (every check of the direct testbench) |
| Taken Local Time PDO without completion to `Err_TxTimeout` | At the 256th tick after the frame was taken, in the cycle that the reference model predicts; no repetition (TC-TM-19) |
| Last bit of the SYNC frame, as the transmitter M1 logs it, to `Evt_Sync`, 40 MHz, 1 Mbit/s | -837.5 ns on bus A and on bus B. Negative, since a receiver takes a frame at the last but one bit of the end of frame, one bit time before the transmitter logs it (TC-TM-18) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `ClkFrequency_g` | 1000000 to 2^31 - 1 | 1000000, 40000000, 100000000, 2147483647 | 1000000, 100000000, 2147483647 |
| `FineBits_g` | 0 to 24 | every value from 0 to 24 | 0, 1, 23, 24; 0 at 1000000 and at 2147483647 |

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, 33 deliberate faults of
the RTL were each simulated with the tests that must detect them. In the first run 30 made a test fail. Two were not
detected, by gaps of the bench described below; TC-TM-05 and TC-TM-14 were extended, and both faults, simulated again
with the extended bench, make a test fail. The extension adds stimuli and checks to these two test cases only and
the RTL is unchanged, so the 30 detections of the first run stand. One fault changes the behaviour only after an
upset that the ports cannot inject and is covered by design review:

| Fault | Detected by |
| --- | --- |
| Advance by `Q_c` + 2 at a carry | TC-TM-01 |
| Carry only above f | TC-TM-01 |
| `Acc` not cleared at a basic setting | TC-TM-08 |
| `Acc` not cleared at a write | TC-TM-05 |
| `Elap` not one cycle ahead | TC-TM-09 |
| `Elap` not restarted at a SYNC | TC-TM-09 |
| High-resolution load without the accumulator | TC-TM-09 |
| No `Evt_Set` at the high-resolution load | TC-TM-09 |
| SYNC with DLC 2 sampled | TC-TM-06 |
| Sample one cycle late | TC-TM-14 |
| No check of a sample since the reset (TM-RX-05) | TC-TM-04 |
| A SYNC in the cycle of the PDO not taken first | TC-TM-20 |
| Fine bytes of the PDO in the wrong order | TC-TM-07 |
| Fine time cut to its lower bits | TC-TM-07 |
| PDO with DLC 6 processed | TC-TM-07 |
| Types 241 to 253 processed | TC-TM-10 |
| A high-resolution load in the cycle of a write not cancelled | TC-TM-05 |
| Frame bytes in the wrong order | TC-TM-11 |
| Frame with DLC 8 | TC-TM-11 |
| SYNC count one too high | TC-TM-12 |
| No restart of the count at a type change | TC-TM-12, TC-TM-20 |
| No restart of the count at a reset communication | TC-TM-12, TC-TM-13 |
| Type 0: a request in the cycle of a SYNC taken at once | TC-TM-20 |
| Type 254: the time of the request instead of the sample | TC-TM-14 |
| A second request while one is pending | TC-TM-16 |
| No `Err_TxBusy` | TC-TM-16 |
| Reject path not taken as a completion | TC-TM-16 |
| A request in the cycle of a completion not made | TC-TM-16 |
| No completion time-out | TC-TM-19 |
| Time-out after 255 ticks | TC-TM-19 |
| No `Err_TxTimeout` | TC-TM-19 |
| No set flag at a write | TC-TM-05 |
| SYNC count compared with = | Not detected; covered by design review |

`SyncCnt` exceeds T - 1 only after an upset, since a change of the type and a reset communication restart the count
(verification plan, section 7).

The two faults that the first run did not detect were gaps of the bench, not of the RTL. "Sample one cycle late":
the sample is sent only in a Local Time PDO of type 254 or 255 in the high-resolution protocol (TM-TX-04); a frame
of types 0 to 240 carries the local time of the cycle of its SYNC directly. TC-TM-14 checked one such sample for
each type, and at 100 MHz with 24 fine bits the local time advances in about one cycle of six, so both samples fell
on cycles without an advance. TC-TM-14 now checks 64 more samples at random distances and also runs in `f1m`, where
the local time advances in every cycle; TC-TM-06 was extended in the same way for the frames of type 1. "A
high-resolution load in the cycle of a write not cancelled": the tests wrote in the second cycle of a
high-resolution setting, not in the cycle of its PDO; TC-TM-05 now does.

## 5. Summary

All 20 test cases pass in all 122 runs; every requirement of the specification is covered by the verification plan.
VSG reports no errors and no warnings, and the GHDL synthesis of the eight configurations of `lint/synth_check.py`
has no inferred latch.
