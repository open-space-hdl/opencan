# ocan_pdo: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_pdo: SYNC consumer (PD-1), receive PDOs with the held data (PD-2), transmit PDOs with their
triggers and handshakes (PD-3), between ocan_dispatch, ocan_od, ocan_nmt and the user logic](img/ocan_pdo_arch.drawio.svg)

`ocan_pdo` is one entity with a two-process design. The SYNC check is shared; each receive PDO has an output register
and a register for the data held for the next SYNC; each transmit PDO has its own trigger, data register and transmit
state machine. Every event is processed in the clock cycle in which it arrives, so that an event is taken in any
cycle (D11). The vectors of the ports carry PDO n (1 to 4) in bit n - 1 and in bits 64 n - 1 downto 64 (n - 1), as
the ports of `ocan_dispatch`; the bits of the PDOs above `NumRpdo_g` and `NumTpdo_g` are outputs at 0 and inputs
that are not used.

## 2. SYNC (PD-1)

`SyncOk` is `RxSync_Valid` with `RxSync_Dlc` 0 or 1 (PD-SY-01). The register `SyncEvt` is `SyncOk` of the previous
cycle and is the port `Sync_Valid` (PD-SY-02). The counter byte of a SYNC is not an input of `ocan_pdo`.

`Nmt_EnaPdo` and `Nmt_ResetComm` act in the cycle in which they are present. `Stat_PdoEnabled` is `Nmt_EnaPdo`
of the same cycle (a register output of `ocan_nmt`), so that a request of the user logic in a cycle with
`Stat_PdoEnabled` = '0' is one without effect (PD-IF-07, PD-RS-01):

- `Nmt_EnaPdo` = '0': no receive PDO is processed, no transmit PDO requested, the held data and the waiting requests
  of transmission type 0 are cleared in every such cycle (PD-RS-01, PD-RS-02). The SYNC counts continue.
- `Nmt_ResetComm` = '1': the SYNC counts and the type registers restart, the held data and the waiting requests are
  cleared, and a receive PDO event of the cycle is not processed (PD-RS-03).

## 3. Receive PDOs (PD-2)

Registers per receive PDO n: `RxOut` (64 bits, the port `Rpdo_Data`), `RxEvt` (the port `Rpdo_Valid`), `Hold`
(64 bits) and `HoldV` (data held for the next SYNC).

A receive PDO event with the number of PDO n is processed with the transmission type T of `Cfg_RpdoType` in that
cycle (PD-RX-06), when `Nmt_EnaPdo` is '1' and `Nmt_ResetComm` is '0':

| Condition | Action |
| --- | --- |
| `RxRpdo_Dlc` below 8 | `Err_RxLength` of PDO n (PD-RX-02) |
| T = 254 or 255 | `RxOut` := the data, `RxEvt` := '1' (PD-RX-03) |
| T = 0 to 240 | `Hold` := the data, `HoldV` := '1' (PD-RX-04) |
| T = 241 to 253 | None (PD-RX-05) |

At `SyncOk` with `Nmt_EnaPdo` = '1' and `Nmt_ResetComm` = '0', every receive PDO with `HoldV` = '1' takes
`RxOut` := `Hold` and `RxEvt` := '1', and `HoldV` is cleared, whatever its type is now (PD-RX-04). The SYNC acts
before the receive PDO event of the same cycle, so that such an event is held for the next SYNC (PD-RX-06); an
event-driven PDO of that cycle overwrites the data passed at the SYNC. A held PDO that a further PDO of the same
number replaces before the SYNC is lost without an event: the last value is passed.

`RxOut` keeps its value until the next pass of its PDO and at the NMT resets (PD-RX-07, PD-RS-03); the hardware
reset clears it (PD-RS-04).

## 4. Transmit PDOs (PD-3)

### 4.1 Triggers

Registers per transmit PDO n: `SyncCnt` (8 bits), `TypeReg` (8 bits, the type of the previous cycle) and `ReqPend` (a
request of the user logic that waits for the SYNC). T is the transmission type of `Cfg_TpdoType`.

| T | The PDO falls due | Data sampled |
| --- | --- | --- |
| 1 to 240 | At `SyncOk` with `SyncCnt` >= T - 1, which also clears `SyncCnt`; any other `SyncOk` increments `SyncCnt` (PD-TX-02) | `Tpdo_Data` in the cycle of the SYNC event |
| 0 | At `SyncOk` with `ReqPend` = '1' (PD-TX-03) | `Tpdo_Data` in the cycle of the SYNC event |
| 254, 255 | At `Tpdo_Req` = '1' (PD-TX-04) | `Tpdo_Data` in the cycle of the request |
| 241 to 253 | Never (PD-TX-05) | - |

- `SyncCnt` and `ReqPend` are cleared after the hardware reset, at `Nmt_ResetComm` and when T differs from
  `TypeReg`; a SYNC in the cycle of one of these events is not counted and makes no PDO due (PD-TX-02). The compare
  with >= ends a count above T - 1 after an upset at the next SYNC.
- `ReqPend` is set by `Tpdo_Req` with T = 0 and `Nmt_EnaPdo` = '1'. In the cycle of a `SyncOk` the PDO falls due
  with the `ReqPend` of the previous cycles, and a `Tpdo_Req` of that cycle sets `ReqPend` for the next SYNC
  (PD-TX-03). `ReqPend` is cleared when the PDO falls due, when T is not 0 and while `Nmt_EnaPdo` is '0'.
- A PDO that falls due while `Nmt_EnaPdo` is '0' is not requested and raises no event (PD-RS-01).

### 4.2 Request and handshake

Registers per transmit PDO n: the state `TxSt`, the frame data `TxData` (64 bits, the port `TxTpdo_Data`) and the
tick count `TxTmo` (8 bits). `TxTpdo_Dlc` is 8 (PD-TX-01).

| `TxSt` | `TxTpdo_Valid` | Exit |
| --- | --- | --- |
| `TIdle_s` | '0' | The PDO falls due: `TxData` := the sampled data, to `TReq_s` |
| `TReq_s` | '1' | `TxTpdo_Ready` with `TxTpdo_Aborted` (reject path of `ocan_dispatch`): `Evt_TpdoAborted`, to `TIdle_s`. `TxTpdo_Ready` alone: `TxTmo` := 0, to `TWait_s` |
| `TWait_s` | '0' | `TxTpdo_Done`: `Evt_TpdoSent`, to `TIdle_s`. `TxTpdo_Aborted`: `Evt_TpdoAborted`, to `TIdle_s`. At a tick with `TxTmo` >= 255: `Err_TxTimeout`, to `TIdle_s` (PD-TX-08); at another tick `TxTmo` is incremented |

- A request is pending from `TReq_s` until the completion or the time-out; `Stat_TpdoBusy` is '1' outside
  `TIdle_s`. A PDO that falls due while its request is pending is not requested and pulses `Err_TxBusy`; one that
  falls due in the cycle of the completion (the reject path included) goes to `TReq_s` with the new data
  (PD-TX-07).
- In `TReq_s` neither `TxTpdo_Valid` nor `TxData` change until `TxTpdo_Ready` (PD-TX-07). The wait is bounded by
  `ocan_dispatch`: a pending request is granted after at most one frame of each other source (DS-TX-06), and is
  completed as aborted when the PDO enable clears (DS-TX-04) or the controller of the active bus stops (DS-TX-08).
- `ocan_dispatch` does not grant a source in the cycle of its own completion (DS-TX-03): the late completion of a
  timed-out frame arrives in `TIdle_s`, or in `TReq_s` without `TxTpdo_Ready`, and is ignored. An aborted PDO and a
  PDO after the time-out are not repeated (PD-TX-08, PD-TX-09).
- The `when others` branch of `TxSt` leads to `TIdle_s`.

Each transmit PDO has its own `TxTmo`, so that a lost completion of one PDO does not affect another one, whatever
`ocan_dispatch` holds.

## 5. Protection

`ocan_pdo` holds no parameter of its own: the transmission types are protected in `ocan_od` (two copies, OD-PR-03)
and the COB-IDs in `ocan_dispatch` (DS-CP-01). It has therefore no test inputs. Its registers are covered by the
protection scope of the user guide (TMR of the synthesis tool). Without that TMR an upset of a register gives at
most:

- `TxSt` to `TWait_s`: the time-out of PD-TX-08 ends the wait; to `TReq_s`: one frame with the content of `TxData`;
  to an unused code: `TIdle_s` (`when others`);
- `SyncCnt` above T - 1: the PDO falls due at the next SYNC (>=);
- `HoldV`, `ReqPend`: one pass of `Hold` or one PDO at the next SYNC;
- `TxTmo`: an earlier end of the wait.

No upset of a single register silences `ocan_pdo`: every state ends by itself or at the next event.

## 6. Ports of ocan_pdo

| Signal | Direction | Width | Default | Description |
| --- | --- | --- | --- | --- |
| `Clk`, `Rst` | In | 1 | - | Clock and synchronous high-active reset |
| `Tick_Ms` | In | 1 | - | Tick every millisecond |
| `RxSync_Valid`, `RxSync_Dlc` | In | 1, 4 | - | SYNC of `ocan_dispatch` |
| `RxRpdo_Valid`, `RxRpdo_Num`, `RxRpdo_Dlc`, `RxRpdo_Data` | In | 1, 2, 4, 64 | - | Receive PDO of `ocan_dispatch` (number n - 1) |
| `TxTpdo_Valid`, `TxTpdo_Ready`, `TxTpdo_Dlc`, `TxTpdo_Data`, `TxTpdo_Done`, `TxTpdo_Aborted` | Out, In, Out, Out, In, In | 4, 4, 16, 256, 4, 4 | - | Transmit PDOs to `ocan_dispatch` |
| `Cfg_RpdoType`, `Cfg_TpdoType` | In | 32, 32 | - | Transmission types of `ocan_od`, PDO n in bits 8 n - 1 downto 8 (n - 1) |
| `Nmt_EnaPdo`, `Nmt_ResetComm` | In | 1 | - | From `ocan_nmt` |
| `Sync_Valid` | Out | 1 | - | SYNC event to the user logic (PD-SY-02) |
| `Rpdo_Valid`, `Rpdo_Data` | Out | 4, 256 | - | Receive PDOs to the user logic: the event and the data last passed |
| `Tpdo_Req`, `Tpdo_Data` | In | 4, 256 | 0 | Transmit PDOs of the user logic: the request and the data |
| `Stat_TpdoBusy` | Out | 4 | - | A request of the transmit PDO is pending (PD-TX-07) |
| `Stat_PdoEnabled` | Out | 1 | - | The PDO enable as `ocan_pdo` uses it (PD-IF-07) |
| `Evt_TpdoSent`, `Evt_TpdoAborted` | Out | 4 | - | Completion of a transmit PDO (PD-TX-09) |
| `Err_RxLength`, `Err_TxBusy`, `Err_TxTimeout` | Out | 4 | - | Events of PD-RX-02, PD-TX-07 and PD-TX-08 |

## 7. Timing and behaviour

| Operation | Duration |
| --- | --- |
| Receive PDO event (types 254, 255) to `Rpdo_Valid` | 1 clock cycle |
| SYNC event to `Rpdo_Valid` of the held data, to `Sync_Valid` | 1 clock cycle |
| SYNC event to `TxTpdo_Valid` (types 0 to 240) | 1 clock cycle |
| `Tpdo_Req` to `TxTpdo_Valid` (types 254, 255) | 1 clock cycle |
| Taken transmit PDO without completion | 256 ticks to `Err_TxTimeout` |

With the fixed latency of `ocan_link` and `ocan_dispatch` (DS-RX-05) the data of the synchronous receive PDOs reach
the user logic, and the data of the synchronous transmit PDOs are sampled, a fixed time after the end of the SYNC
frame, the same on both buses.
