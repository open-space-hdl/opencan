# ocan_sdo: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_sdo: request decoder and protocol (SD-1), object access with the buffer (SD-2), reply with
the transmit handshake (SD-3), between ocan_dispatch, ocan_od and ocan_nmt](img/ocan_sdo_arch.drawio.svg)

`ocan_sdo` is one entity with a two-process design and two state variables: `Xfer`, the open transfer, and `Proc`,
the processing of one request. A request is decoded in the cycle after its event; the object access and the reply
follow in `Proc`. Between requests `Proc` is idle, so that a new request is taken in any cycle (D11).

## 2. Open transfer (SD-1)

| `Xfer` | Meaning | Set by | Ended by |
| --- | --- | --- | --- |
| `XNone_s` | No transfer open | - | - |
| `XDown_s` | Segmented download open: the next request is a download segment | The initiate download response of a segmented download | The last segment, an abort, a new initiate, SD-RS-01, SD-RS-02 |
| `XUp_s` | Segmented upload open: the next request is an upload segment | The initiate upload response of a segmented upload | The last segment, an abort, a new initiate, SD-RS-01, SD-RS-02 |

Registers of the open transfer: the index and sub-index (`Mux`, 24 bits), the expected toggle bit `Tgl`, the
indicated size `Size` (download), the number of bytes `Cnt` (bytes received in a download, bytes sent in an upload)
and the buffer `Buf` of 8 bytes. `Stat_Open` is '1' while `Xfer` is not `XNone_s` (SD-RS-03).

## 3. Processing of a request

| `Proc` | Meaning | Exit |
| --- | --- | --- |
| `PIdle_s` | Ready for a request | A request with DLC 8 or more: decoded (section 4); to `PAcc_s` for an object access, to `PTx_s` for a reply without an access, back to `PIdle_s` for an abort request |
| `PAcc_s` | Access of `ocan_od` outstanding (`Acc_Valid` until `Acc_Ready`, then the answer) | `Rsp_Valid` after the take: the reply is built from the answer, to `PTx_s`; with `Aborted` set, or with an abort request, a cleared SDO enable or a reset event in the cycle of the answer: no reply, to `PIdle_s`; at a tick with `TxTmo` >= 511: `Err_AccTimeout`, the abort 0800 0000h to `PTx_s`, or no reply and to `PIdle_s` in the cases without a reply |
| `PTx_s` | Reply offered to `ocan_dispatch` (`TxSdo_Valid`) | `TxSdo_Ready`: to `PWait_s`, or to `PIdle_s` when `TxSdo_Aborted` comes with it (reject path) |
| `PWait_s` | Reply taken, its completion awaited | `TxSdo_Done` or `TxSdo_Aborted`: to `PIdle_s`; at a tick with `TxTmo` >= 255: `Err_TxTimeout`, to `PIdle_s` |

- A request event outside `PIdle_s` is not processed and pulses `Err_RxDrop` (SD-PR-09). An abort request ends
  the open transfer in every state: in `PAcc_s` it sets `Aborted`; the access is held until `ocan_od` takes it, so
  that a valid access is never withdrawn, and its answer is discarded without a reply. In `PTx_s` it withdraws the
  offered reply; in `PWait_s` the taken reply completes.
- Every state of `Proc` ends. `ocan_od` answers every access it takes within 256 ticks (OD-IF-01, OD-AP-03), and
  `TxTmo` bounds the wait in `PAcc_s` at 512 ticks (SD-TX-04): this bound also ends the wait after an upset of
  `AccTaken` or of `Proc`, when `ocan_od` has no access to answer. `TxTmo` bounds the wait for the completion of the
  reply (SD-TX-02).
- The SDO enable cleared or a reset event: `Xfer` to `XNone_s`, without a reply. In `PTx_s` and `PWait_s`, `Proc`
  goes to `PIdle_s`: an offered reply is withdrawn, a taken reply is aborted by `ocan_dispatch` (DS-TX-04) or
  completes. In `PAcc_s`:
  - the SDO enable cleared: as an abort request; `ocan_od` answers every access it takes (OD-IF-01);
  - a reset event: an access taken in an earlier cycle and not answered in the cycle of the event ends at `ocan_od`
    without an answer (an outstanding request of the application port, architecture of `ocan_od`, section 6), and
    `Proc` goes to `PIdle_s`; an access not yet taken is withdrawn; an access taken in the cycle of the event has no
    effect on the objects (OD-WR-10) and is answered in the next cycle, with 0800 0022h for an object of the user
    logic; `Aborted` is set and that answer is discarded.

  A request in the cycle of these events is not processed. `TxSdo_Done` and `TxSdo_Aborted` outside `PWait_s` are
  ignored.
- The `when others` branches lead to `PIdle_s` and `XNone_s`.

## 4. Decoder

The command specifier is bits 7 to 5 of byte 0 (`ocan_dispatch` passes byte 0 in bits 63 to 56 of the data).

| Request (ccs) | Condition | Action |
| --- | --- | --- |
| Initiate download (1), e = 1 | - | `Xfer` := `XNone_s`; write of 4 - n bytes (s = 1) or with the number 0 (s = 0); reply: initiate download response or the abort of the answer |
| Initiate download (1), e = 0 | s = 1, size 1 to 8 | `Xfer` := `XDown_s`, `Tgl` := 0, `Cnt` := 0, `Size` := size; reply: initiate download response |
| | s = 1, size above 8; s = 1, size 0, or s = 0 | Abort 0607 0012h; 0607 0010h |
| Download segment (0) | `Xfer` = `XDown_s`, t = `Tgl` | 7 - n bytes to `Buf`; more than 8 in total: abort 0504 0005h; c = 0: response, `Tgl` inverted; c = 1: `Cnt` /= `Size`: abort 0607 0010h, otherwise write of `Cnt` bytes, reply: response or the abort of the answer |
| | t /= `Tgl` | Abort 0503 0000h, `Xfer` := `XNone_s` |
| Initiate upload (2) | - | `Xfer` := `XNone_s`; read; reply from the answer: abort, expedited response (1 to 4 bytes), or initiate response with the size, `Xfer` := `XUp_s`, `Tgl` := 0, `Cnt` := 0 (5 to 8 bytes); an answer with 0 or more than 8 bytes: abort 0800 0000h |
| Upload segment (3) | `Xfer` = `XUp_s`, t = `Tgl` | Response with the next 7 or fewer bytes of `Buf`, c = 1 on the last; `Tgl` inverted; `Xfer` := `XNone_s` after the last |
| | t /= `Tgl` | Abort 0503 0000h, `Xfer` := `XNone_s` |
| Segment (0, 3) | No open transfer of its direction | Abort 0504 0001h with `Mux` (0 without a transfer); `Xfer` := `XNone_s` |
| Abort (4) | - | `Xfer` := `XNone_s`; no reply; `Evt_AbortRx` when a transfer was open or a request in processing, otherwise ignored without the event (SD-PR-07) |
| 5, 6, 7 | - | Abort 0504 0001h with the index and sub-index of the request; `Xfer` := `XNone_s` |

`Evt_AbortTx` pulses at the completion (`TxSdo_Done`) of a reply with the command specifier 4; an abort frame that is
rejected, aborted or not completed gives no event. The byte count `Cnt` is compared with >= against the limit of 8,
so that a count above the limit after an upset ends the transfer (SD-DL-03).

## 5. Reply (SD-3)

The reply register holds the 8 data bytes; `TxSdo_Dlc` is 8. `TxSdo_Valid` is '1' in `PTx_s`. `TxTmo` (9 bits)
counts the ticks in `PAcc_s` from the decode of the request and in `PWait_s` from the take of the reply. At a tick
with `TxTmo` >= 511 in `PAcc_s` the wait for the answer ends (512 ticks, SD-TX-04); at a tick with `TxTmo` >= 255 in
`PWait_s` the wait for the completion ends (256 ticks, SD-TX-02).

## 6. Ports of ocan_sdo

| Signal | Direction | Width | Default | Description |
| --- | --- | --- | --- | --- |
| `Clk`, `Rst` | In | 1 | - | Clock and synchronous high-active reset |
| `Tick_Ms` | In | 1 | - | Tick every millisecond |
| `Rx_Valid`, `Rx_Dlc`, `Rx_Data` | In | 1, 4, 64 | - | SDO request of `ocan_dispatch` (`RxSdo_*`) |
| `Tx_Valid`, `Tx_Ready`, `Tx_Dlc`, `Tx_Data`, `Tx_Done`, `Tx_Aborted` | Out, In, Out, Out, In, In | 1, 1, 4, 64, 1, 1 | - | SDO reply to `ocan_dispatch` (`TxSdo_*`) |
| `Acc_Valid`, `Acc_Ready`, `Acc_Write`, `Acc_Index`, `Acc_Sub`, `Acc_Data`, `Acc_Len` | Out, In, Out, Out, Out, Out, Out | 1, 1, 1, 16, 8, 64, 4 | - | Access of `ocan_od` |
| `Rsp_Valid`, `Rsp_Data`, `Rsp_Len`, `Rsp_Abort` | In | 1, 64, 4, 32 | - | Answer of `ocan_od` |
| `Nmt_EnaSdo`, `Nmt_ResetApp`, `Nmt_ResetComm` | In | 1 | - | From `ocan_nmt` |
| `Stat_Open` | Out | 1 | - | A segmented transfer is open (SD-RS-03) |
| `Err_RxDrop`, `Err_TxTimeout`, `Err_AccTimeout`, `Evt_AbortTx`, `Evt_AbortRx` | Out | 1 | - | Events (SD-IF-06) |

## 7. Timing and behaviour

| Operation | Duration |
| --- | --- |
| Request to `Acc_Valid` | 1 clock cycle |
| Answer of `ocan_od` to `Tx_Valid` | 1 clock cycle |
| Request of an object of `ocan_od` to `Tx_Valid` | 3 clock cycles (the answer 1 cycle after the access) |
| Request without an access (segment of a download that is not the last, upload segment, protocol abort) to `Tx_Valid` | 1 clock cycle |
| Taken reply without completion | 256 ticks to `Err_TxTimeout` |
| Access of `ocan_od` without an answer | 512 ticks from the decode of the request to `Err_AccTimeout`, the abort 0800 0000h 1 clock cycle later |
