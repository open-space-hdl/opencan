# ocan_time: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_time: the local SCET counter (TM-1), the SYNC sample with the elapsed counter (TM-2), the
Spacecraft Time PDO consumer (TM-3) and the Local Time PDO producer (TM-4), between ocan_dispatch, ocan_od, ocan_nmt
and the user logic](img/ocan_time_arch.drawio.svg)

`ocan_time` is one entity with one two-process record. It instantiates no other entity and runs in `Clk`. Every
SCET at its ports is a 56-bit unsigned value: bits 55 to 24 the coarse time, bits 23 to 0 the fine time aligned to
its most significant bit (specification, section 2.6). Inside, the local time has 32 + F bits, F = `FineBits_g`.

## 2. Local SCET counter (TM-1)

The counter advances by exactly floor(n * 2^F / f) fine time units in n clock cycles, f = `ClkFrequency_g`, without a
divider (TM-CT-02). Two constants are computed from the generics:

| Constant | Value | Example: f = 100 MHz, F = 24 | Example: f = 1 MHz, F = 24 |
| --- | --- | --- | --- |
| `Q_c` | floor(2^F / f) | 0 | 16 |
| `R_c` | 2^F mod f | 16777216 | 777216 |

| Register | Width | Content |
| --- | --- | --- |
| `Time` | 32 + F | Local time: coarse time in the upper 32 bits, fine time in the lower F bits |
| `Acc` | ceil(log2(f)) | Fractional accumulator, 0 to f - 1 |
| `TimeSet` | 1 | The local time has been set since the hardware reset (`Stat_TimeSet`) |

In every cycle `Acc` + `R_c` is formed. When it is f or more, `Acc` := `Acc` + `R_c` - f and `Time` advances by
`Q_c` + 1; otherwise `Acc` := `Acc` + `R_c` and `Time` advances by `Q_c`. After n cycles from `Acc` = 0 the time has
advanced by `n * Q_c + floor(n * R_c / f)` = `floor(n * 2^F / f)` units. The coarse time wraps with the counter
(TM-CT-03). A setting loads `Time` and clears `Acc` (TM-RX-03, TM-CT-05), except the high-resolution setting of
section 4, which loads both from the elapsed counter.

Every cycle adds 2^F to f * `Time` + `Acc`, also when `Acc` is f or more after an upset. The compare with >= then
takes f off `Acc` in every cycle until it is below f again; the upset shifts the local time by less than two fine time
units, until the next setting.

`Time_Coarse` and `Time_Fine` are `Time` with the fine time aligned to bit 23 of `Time_Fine`; the bits below it are
0. With F = 0 `Time_Fine` is 0. `Stat_Scet` is the same value as one 56-bit vector for reads of Local SCET Get.

## 3. SYNC sample and elapsed counter (TM-2)

| Register | Width | Content |
| --- | --- | --- |
| `Sample` | 32 + F | Local time at the last sampled SYNC |
| `SampleValid` | 1 | A SYNC has been sampled since the hardware reset (TM-RX-05) |
| `Elap`, `ElapAcc` | 32 + F, ceil(log2(f)) | Time elapsed since the last sample, one cycle ahead, advanced like `Time` and `Acc` |

A SYNC event (`Rx_SyncValid`) with `Rx_SyncDlc` 0 or 1 is sampled (TM-SY-01): `Sample` takes `Time` of the cycle of
the event, `SampleValid` := '1', `Elap` and `ElapAcc` start in that cycle, and `Evt_Sync` pulses. The sample
therefore lies zero cycles after the event at the port; the latency from the end of the SYNC frame is that of
`ocan_link` and `ocan_dispatch` (DS-RX-05). The data byte of a SYNC with DLC 1 (the SYNC counter) is not used. A SYNC
with another DLC changes nothing (TM-SY-02).

n cycles after the sample `Elap` holds floor((n + 1) * 2^F / f): the advance of TM-CT-02 for the next cycle, so
that the high-resolution setting of section 4 loads it with one addition of two registers.

## 4. Spacecraft Time PDO (TM-3)

The received frame (`Rx_TimeValid`, `Rx_TimeDlc`, `Rx_TimeData`) is decoded as follows: bytes 0 to 2 the fine time
least significant byte first, bytes 3 to 6 the coarse time least significant byte first, byte 0 in bits 63 to 56 of
`Rx_TimeData`. The fine time is cut to its upper F bits (TM-RX-01).

| Condition (first match) | Action |
| --- | --- |
| `Rx_TimeDlc` < 7 | Not processed; `Err_RxDrop` (TM-RX-02) |
| `Cfg_RxType` 241 to 253 | Not processed; `Err_RxDrop` (TM-RX-06) |
| `Cfg_RxType` 254 or 255 | Basic protocol: `Time` := the SCET and `Acc` := 0 in the cycle of the event (TM-RX-03) |
| `Cfg_RxType` 0 to 240 and `SampleValid` = '0' | Not processed; `Err_RxDrop` (TM-RX-05) |
| `Cfg_RxType` 0 to 240 | High-resolution protocol (TM-RX-04): the SCET is registered, and in the next cycle `Time` := SCET + `Elap` and `Acc` := `ElapAcc`, both one cycle ahead (section 3) |

The high-resolution setting takes two cycles, so that the addition of the SCET and `Elap` has registers at both
inputs and is not in series with the advance of `Elap`. The result does not depend on that latency: from then on
`Time` equals the SCET plus floor(n * 2^F / f) for the n cycles since the sample, so the local time at the SYNC is the
received SCET.

Every setting sets `TimeSet` and gives `Evt_Set`. A write of Local SCET Set (`Cfg_SetValid`, TM-CT-05) loads
`Time` := `Cfg_SetScet` and `Acc` := 0 in the cycle of the write. When a write and a setting by a PDO come in the same
cycle, or the write comes in the second cycle of a high-resolution setting, the write wins.

Same-cycle inputs (TM-IF-06):

- A SYNC in the cycle of a Spacecraft Time PDO is the SYNC that the PDO relates to: the SYNC is taken first, so the
  check of TM-RX-05 and the load use its sample.
- A SYNC in the cycle after the PDO, before the load, does not change the load: it uses `Elap` of the SYNC before the
  PDO.
- The settings of one cycle take precedence in this order: the write of Local SCET Set, the basic setting of a PDO of
  that cycle, the load of a high-resolution setting.

## 5. Local Time PDO (TM-4)

### 5.1 Triggers

T is `Cfg_TxType`. The protocol is high-resolution when `Cfg_RxType` is 0 to 240 (specification, section 5).

| T | Request falls due | SCET of the frame |
| --- | --- | --- |
| 1 to 240 | At every T-th sampled SYNC: `SyncCnt` counts the sampled SYNCs; a SYNC with `SyncCnt` >= T - 1 makes the request due and clears it (TM-TX-02) | `Sample` of that SYNC |
| 0 | At the first sampled SYNC after `Req_Valid` (flag `ReqPend`, TM-TX-03) | `Sample` of that SYNC |
| 254, 255 | At `Req_Valid` (TM-TX-04) | High-resolution protocol with `SampleValid` = '1': `Sample`; otherwise `Time` of the cycle of the request |
| 241 to 253 | Never (TM-TX-05) | - |

`SyncCnt` (8 bits) is cleared after the hardware reset, at `Nmt_ResetComm` and when `Cfg_TxType` changes (register
`TxTypeReg`), so that the count starts at the next SYNC: a SYNC in the cycle of one of these events is not counted
and makes no request. The compare with >= ends a count above T - 1 after an upset at the next SYNC. `ReqPend` is
cleared at the same events and when T is not 0; with T = 0, `Req_Valid` in the cycle of a sampled SYNC applies to the
next sampled SYNC. A request that falls due while one is pending is not made and gives `Err_TxBusy` (TM-TX-06).

### 5.2 Frame and handshake

The frame has DLC 7. `Tx_Data` holds the SCET in the byte order of section 4, the fine time aligned to its most
significant bit with the bits below F at 0, and byte 7 at 0 (TM-TX-01).

| State | `Tx_Valid` | Exit |
| --- | --- | --- |
| `TxIdle_s` | '0' | Request: the frame is registered; to `TxReq_s` |
| `TxReq_s` | '1' | `Tx_Ready` = '1' with `Tx_Done` or `Tx_Aborted` in the same cycle (reject path of `ocan_dispatch`): to `TxIdle_s`. `Tx_Ready` = '1' alone: to `TxWait_s` |
| `TxWait_s` | '0' | `Tx_Done` or `Tx_Aborted`: to `TxIdle_s`. Otherwise at the 256th tick (`TxTmo` >= 255): `Err_TxTimeout`, to `TxIdle_s` (TM-TX-07) |

`TxTmo` (8 bits) counts the ticks in `TxWait_s` from 0 at `Tx_Ready`. A request is pending from `TxReq_s` until
the completion or the time-out. A request that falls due in the cycle of a completion is made. An aborted Local Time
PDO is not repeated, and neither is one after the time-out. `ocan_dispatch` owns one frame at a time and does not
grant a source in the cycle of its own completion event (DS-TX-03): the late completion of a timed-out frame arrives
while `ocan_time` is in `TxIdle_s`, or in `TxReq_s` without `Tx_Ready`, and is ignored. A request that
`ocan_dispatch` has not taken (`TxReq_s`) is never withdrawn, so that the valid/ready rule holds.

The `when others` branch leads to `TxIdle_s`. As in every core of the family, this recovery from an illegal state
works only when the synthesis tool implements the state machine safely: `ocan_time` protects none of its registers
itself, they rely on the TMR and the safe state machines of the synthesis tool (protection scope of the user guide).
Without an upset of the state machine, every register recovers by itself: `Acc` and `SyncCnt` by the compares with
>=, `SampleValid` at the next SYNC, `ReqPend` and the high-resolution load at the next SYNC or PDO, the transmit
handshake by the time-out.

## 6. Reset communication

`Nmt_ResetComm` clears `SyncCnt` and `ReqPend` (TM-IF-07). It does not change `Time`, `Acc`, `TimeSet`, `Sample`,
`SampleValid`, `Elap` and the transmit handshake: a request that `ocan_dispatch` has taken completes as the dispatch
reports it, or ends at the time-out of TM-TX-07. `ocan_time` does not take the reset application event.

## 7. Ports of ocan_time

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | In | 1 | Clock and synchronous high-active reset |
| `Tick_Ms` | In | 1 | Millisecond tick (TM-IF-08) |
| `Rx_SyncValid`, `Rx_SyncDlc` | In | 1, 4 | SYNC (`RxSync_Valid`, `RxSync_Dlc` of `ocan_dispatch`) |
| `Rx_TimeValid`, `Rx_TimeDlc`, `Rx_TimeData` | In | 1, 4, 64 | Spacecraft Time PDO (`RxTime_*` of `ocan_dispatch`) |
| `Tx_Valid`, `Tx_Ready` | Out, In | 1 | Handshake of the Local Time PDO (`TxTime_*` of `ocan_dispatch`) |
| `Tx_Dlc`, `Tx_Data` | Out | 4, 64 | DLC 7 and the frame data |
| `Tx_Done`, `Tx_Aborted` | In | 1 | Completion events of the frame |
| `Cfg_RxType`, `Cfg_TxType` | In | 8, 8 | Transmission types of the Spacecraft Time PDO and of the Local Time PDO (`ocan_od`) |
| `Cfg_SetValid`, `Cfg_SetScet` | In | 1, 56 | Write of Local SCET Set: pulse and value (`ocan_od`) |
| `Stat_Scet` | Out | 56 | Local time for reads of Local SCET Get (`ocan_od`) |
| `Nmt_ResetComm` | In | 1 | Reset communication event (`Reset_Comm` of `ocan_nmt`) |
| `Req_Valid` | In | 1 | Pulse from the user logic: send the Local Time PDO |
| `Time_Coarse`, `Time_Fine` | Out | 32, 24 | Local time to the user logic in every cycle; fine time aligned to bit 23 |
| `Stat_TimeSet` | Out | 1 | The local time has been set since the hardware reset |
| `Evt_Set`, `Evt_Sync` | Out | 1 | Events: a setting of the local time; a SYNC sample |
| `Err_TxBusy` | Out | 1 | Event: a Local Time PDO fell due while one was pending |
| `Err_RxDrop` | Out | 1 | Event: a Spacecraft Time PDO was not processed |
| `Err_TxTimeout` | Out | 1 | Event: no completion of a taken Local Time PDO within 256 ticks |

## 8. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ClkFrequency_g` | 100000000 | 1000000 to 2^31 - 1 | Frequency of `Clk` in Hz; an integer, so that simulators can set it |
| `FineBits_g` | 24 | 0 to 24 | Width of the fine time |

## 9. Timing and behaviour

| Operation | Duration |
| --- | --- |
| `Rx_SyncValid` to the sample | The sample is `Time` of the cycle of the event; `Evt_Sync` 1 clock cycle later |
| `Rx_TimeValid` to the basic setting, `Cfg_SetValid` to the setting | `Time` holds the set value 1 clock cycle later |
| `Rx_TimeValid` to the high-resolution setting | `Time` holds the corrected value 2 clock cycles later |
| Sampled SYNC or `Req_Valid` to `Tx_Valid` | 1 clock cycle |
| Taken Local Time PDO without completion to `Err_TxTimeout` | Between 255 and 256 ms |
| Advance of the local time | floor(n * 2^F / f) fine time units in n cycles, exact over any n |

Every event is processed within two clock cycles, also the SYNC and the Spacecraft Time PDO in consecutive frames
(TM-IF-06).
