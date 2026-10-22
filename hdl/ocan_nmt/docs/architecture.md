# ocan_nmt: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_nmt: the NODE-ID check with olo_intf_sync (NM-1), the NMT state machine with the service
enables and the reset events (NM-2) and the boot-up and heartbeat producer (NM-3), between the NODE-ID pins,
ocan_dispatch and ocan_redundancy](img/ocan_nmt_arch.drawio.svg)

`ocan_nmt` is one entity with one two-process record. It instantiates `olo_intf_sync` for the NODE-ID pins and runs
in `Clk`. It holds no frame: an NMT message arrives as an event with its command specifier, and an NMT error control
frame is one data byte.

## 2. NODE-ID (NM-1)

The 14 pins `Pin_NodeId` and `Pin_NodeIdCode` pass `olo_intf_sync` (`Width_g` = 14, `SyncStages_g` = 2,
`SyncTmr_g` = true, reset by `Rst`). The state machine samples the synchronised pins in `ResetComm_s` and `WaitId_s`
(section 3). A sample is valid when the code is the bitwise complement of the NODE-ID and the NODE-ID is in the range
1 to 127 (NM-ID-01).

| Register | Width | Content |
| --- | --- | --- |
| `IdCopy` | 7 | NODE-ID of the last valid sample |
| `IdCopyN` | 7 | Bitwise complement of `IdCopy` |

- **Outputs.** `Node_Id` is `IdCopy`. `Node_IdValid` is '1' when `IdCopyN` is the complement of `IdCopy` and the
  state is neither `Init_s` nor `WaitId_s`; no separate register holds the validity. The reset sets both copies to
  0, which are not complementary, so the flag is '0' until the first valid sample. The compare is combinational on
  the registers: an upset of either copy clears `Node_IdValid` in the cycle in which it occurs, so that no frame of
  the node carries a NODE-ID that differs from the sample (NM-ID-02).
- **Copy check.** In `PreOp_s`, `Op_s` and `Stopped_s`, copies that are not complementary give the event
  `Err_NodeId` in the same cycle and the transition to `ResetComm_s`, which samples the pins again (NM-ID-04).
- **Sample.** A valid sample writes both copies. An invalid sample keeps the copies and leads to `WaitId_s`, where
  `Node_IdValid` is '0'. A reset communication with valid pins keeps `Node_IdValid` at '1': `ocan_link` stays
  enabled and does not integrate on the bus again.
- **Test input.** `ErrInj_BitFlip` selects bits of the copies (bits 6 to 0 `IdCopy`, bits 13 to 7 `IdCopyN`); in a
  cycle with `ErrInj_Valid` = '1' the selected bits are inverted in the registers. A system ties both to 0.

## 3. NMT state machine (NM-2)

![NMT state machine of ocan_nmt: Init_s, ResetApp_s, ResetComm_s and WaitId_s of the Initialisation, and PreOp_s,
Op_s and Stopped_s](img/ocan_nmt_fsm.drawio.svg)

| State | `Stat_State` | NMT state | Function |
| --- | --- | --- | --- |
| `Init_s` | "00" | Initialisation | Initialising: waits `SyncStages_c` = 2 cycles after the reset, so that the synchronised pins are valid |
| `ResetApp_s` | "00" | Initialisation | Reset application: one cycle with `Reset_App` = '1' |
| `ResetComm_s` | "00" | Initialisation | Reset communication: one cycle with `Reset_Comm` = '1'; samples the pins |
| `WaitId_s` | "00" | Initialisation | The sample was invalid: samples the pins at every `Tick_Ms` (NM-ID-03) |
| `PreOp_s` | "01" | Pre-operational | - |
| `Op_s` | "10" | Operational | - |
| `Stopped_s` | "11" | Stopped | - |

The encoding of `Stat_State` is defined once, as constants of the package `ocan_pkg`, which `ocan_redundancy` uses
as well. `Reset_App` and `Reset_Comm` are decoded from the state: a reset node gives `Reset_App` and in the next cycle
`Reset_Comm` (NM-SM-06). The `when others` branch leads to `ResetComm_s`, which samples the NODE-ID again and
requests the boot-up message. As in every core of the family, this recovery from an illegal state works only when
the synthesis tool implements the state machines safely: the NODE-ID copies are the only registers that
`ocan_nmt` protects itself, all other registers rely on the TMR and the safe state machines of the synthesis tool
(protection scope of the user guide).

Transitions of the Initialisation:

| From | Condition | To |
| --- | --- | --- |
| `Init_s` | `SyncStages_c` cycles after the reset | `ResetApp_s` |
| `ResetApp_s` | always | `ResetComm_s` |
| `ResetComm_s` | valid sample | `PreOp_s` with the boot-up request (NM-SM-01, NM-HB-01); `Op_s` with `MinimalSet_g` = true |
| `ResetComm_s` | invalid sample | `WaitId_s` |
| `WaitId_s` | `Tick_Ms` and a valid sample | as `ResetComm_s` with a valid sample |

In `PreOp_s`, `Op_s` and `Stopped_s` the state of the next cycle is formed in four steps:

1. NMT message (`Rx_Valid`) with command specifier 129 (reset node): `ResetApp_s`.
2. NMT message with 130 (reset communication), or copies that are not complementary: `ResetComm_s`.
3. NMT message with 1 (start remote node), 2 (stop remote node) or 128 (enter pre-operational): `Op_s`,
   `Stopped_s` or `PreOp_s`, also from the same state (NM-SM-02). Another command specifier changes nothing and gives
   the event `Err_Cs` (NM-SM-03).
4. `Red_PreopReq` changes the result of step 3 from `Op_s` or `Stopped_s` to `PreOp_s`; after step 1 or 2 it is
   discarded (NM-SM-05).

The states of the Initialisation take no NMT message and no request (NM-SM-03, NM-SM-05). `Red_Selecting` is used with
`MinimalSet_g` = true only (section 5).

Service enables, decoded from the state and the boot-up block of section 4.2 (NM-SM-04):

| State | `Ena_Sdo` | `Ena_Sync` | `Ena_Pdo` |
| --- | --- | --- | --- |
| `PreOp_s` | '1' | '1' | '0' |
| `Op_s` | '1' | '1' | '1' |
| Every other state | '0' | '0' | '0' |
| Boot-up block set | '0' | '0' | '0' |

## 4. Boot-up and heartbeat (NM-3)

### 4.1 Heartbeat timer

P is `Cfg_HbTime`. The register `HbTime` holds the value of the previous cycle, so that `Cfg_HbTime` /= `HbTime`
marks a change. The counter `HbCnt` (16 bits) counts `Tick_Ms`. In every cycle:

| Condition | `HbCnt` | Heartbeat due |
| --- | --- | --- |
| The next state is a state of the Initialisation, or the cycle is the transition from it to `PreOp_s` (the boot-up message is the first heartbeat) | 0 | no |
| Restart: the transition from the Initialisation to `Op_s` (`MinimalSet_g` = true), a change of P, or `Red_Switched` | 0 | yes for the transition and for `Red_Switched` when P /= 0; yes for a change from 0 to a value /= 0 (NM-HB-04, NM-HB-05, NM-MS-02) |
| `Tick_Ms` and P /= 0, `HbCnt` >= P - 1 | 0 | yes (NM-HB-03) |
| `Tick_Ms` and P /= 0, `HbCnt` < P - 1 | `HbCnt` + 1 | no |
| Otherwise | kept | no |

The first row that holds applies. Several restart conditions in one cycle restart the counter once; the heartbeat is
due when one of them makes it due. With P = 0 no heartbeat falls due (NM-HB-03). The compare with >= makes a
counter above P - 1, after an upset, give a heartbeat at the next tick instead of after 2^16 ticks.

### 4.2 Requests

A request is the boot-up message (00h) or a heartbeat (the state byte of the NMT state of the next cycle: 04h
Stopped, 05h Operational, 7Fh Pre-operational; NM-HB-02). One request is pending from its registration until its
completion (NM-HB-06).

| Event | No request pending, or the pending one completes in this cycle | A request pending |
| --- | --- | --- |
| Boot-up due: transition from the Initialisation to `PreOp_s` | Boot-up request | `BootDue` := '1'; the boot-up request follows at the completion |
| Heartbeat due (section 4.1) | Heartbeat request | Dropped |
| `Red_Switched` with `BootRetry` = '1' | Boot-up request in place of the heartbeat, `BootRetry` := '0' (NM-HB-07) | `BootDue` := '1', `BootRetry` := '0' |
| Time-out of a boot-up message (section 4.3) | Boot-up request again (NM-HB-08) | - |

Every boot-up request clears `BootRetry` (NM-HB-07). The completion of the handshake (section 4.3) is evaluated
before the requests, so that an abort in the cycle of `Red_Switched` counts for that switch. A deferred boot-up
request (`BootDue`) is not made in the cycle of a reset command; the boot-up message of the new Initialisation
follows (NM-HB-06).

| Register | Content |
| --- | --- |
| `TxData` | Data byte of the pending request |
| `TxBoot` | The pending request is the boot-up message |
| `TxTmo` | Ticks in `TxWait_s`, 0 to 255 |
| `BootDue` | A boot-up message waits for the completion of a heartbeat |
| `BootRetry` | The last boot-up message was aborted; it is requested again at the next bus switch, also when P = 0 |

`BootDue` and `BootRetry` are cleared in the states of the Initialisation. The boot-up block of the service enables
(section 3) is `BootDue` or a pending request with `TxBoot` = '1' (NM-SM-04).

### 4.3 Transmit handshake

| State | `Tx_Valid` | Exit |
| --- | --- | --- |
| `TxIdle_s` | '0' | Request: `TxData` and `TxBoot` registered; to `TxReq_s` |
| `TxReq_s` | '1' | `Tx_Ready` = '1' with `Tx_Done` or `Tx_Aborted` in the same cycle (reject path of `ocan_dispatch`): completion, to `TxIdle_s`. `Tx_Ready` = '1' alone: to `TxWait_s` |
| `TxWait_s` | '0' | `Tx_Done` or `Tx_Aborted`: completion, to `TxIdle_s`. Otherwise in `ResetComm_s`: the wait ends, to `TxIdle_s`. Otherwise at the 256th tick (`TxTmo` = 255): `Err_TxTimeout`, to `TxIdle_s` (NM-HB-08) |

A completion with `Tx_Aborted` of the boot-up message sets `BootRetry`. An aborted heartbeat is not repeated
(NM-HB-07). At a completion with `BootDue` = '1' the boot-up request is registered in the same cycle (`TxReq_s`
again). `Tx_Data` is `TxData`. The `when others` branch leads to `TxIdle_s`.

The wait ends without a completion in two cases: at a reset communication, and after 256 ticks without a completion.
`ocan_dispatch` owns one frame at a time and does not grant a source in the cycle of its own completion event
(DS-TX-03). The late completion of the old frame therefore arrives while `ocan_nmt` is in `TxIdle_s`, or in
`TxReq_s` without `Tx_Ready`, and is ignored. A request that `ocan_dispatch` has not taken (`TxReq_s`) is never
withdrawn, so that the valid/ready rule holds.

## 5. Minimal set

With `MinimalSet_g` = true:

- `Rx_Valid` is ignored: no change of state and no `Err_Cs` (NM-MS-01). `Stopped_s` is not reachable.
- The Initialisation ends in `Op_s` without a boot-up message, with a heartbeat due at once (NM-MS-02). `BootDue` and
  `BootRetry` stay '0'.
- `Red_PreopReq` changes `Op_s` to `PreOp_s`. The register `Selecting` holds `Red_Selecting` of the previous cycle;
  a change of `Red_Selecting` from '1' to '0' in `PreOp_s` is the end of the bus selection with an active bus and
  leads to `Op_s` (NM-MS-03).

## 6. Ports of ocan_nmt

| Signal | Direction | Width | Default | Description |
| --- | --- | --- | --- | --- |
| `Clk`, `Rst` | In | 1 | - | Clock and synchronous high-active reset |
| `Pin_NodeId`, `Pin_NodeIdCode` | In | 7, 7 | - | NODE-ID pins and their protection code (the bitwise complement), asynchronous |
| `Tick_Ms` | In | 1 | - | Pulse every millisecond (`olo_base_strobe_gen` of `ocan_core`) |
| `Cfg_HbTime` | In | 16 | - | Producer heartbeat time P in milliseconds (object 1017h of `ocan_od`) |
| `Rx_Valid`, `Rx_Cs` | In | 1, 8 | - | NMT message and its command specifier (`RxNmt_*` of `ocan_dispatch`) |
| `Tx_Valid`, `Tx_Ready` | Out, In | 1 | - | Handshake of the NMT error control frame (`TxNmt_*` of `ocan_dispatch`) |
| `Tx_Data` | Out | 8 | - | Data byte of the frame (DLC 1) |
| `Tx_Done`, `Tx_Aborted` | In | 1 | - | Completion events of the frame |
| `Node_Id`, `Node_IdValid` | Out | 7, 1 | - | Protected NODE-ID and its valid flag (`Nmt_NodeId` and `Nmt_NodeIdValid` of `ocan_dispatch`, `Ctrl_Enable` of `ocan_link`) |
| `Ena_Sdo`, `Ena_Pdo`, `Ena_Sync` | Out | 1 | - | Service enables (`Nmt_Ena*` of `ocan_dispatch`) |
| `Red_PreopReq` | In | 1 | - | Pulse from `ocan_redundancy`: enter Pre-operational |
| `Red_Switched` | In | 1 | - | Pulse from `ocan_redundancy`: a bus switch has ended |
| `Red_Selecting` | In | 1 | - | '1' during the bus selection process |
| `Stat_State` | Out | 2 | - | NMT state (section 3), to `ocan_redundancy` and as status |
| `Reset_App`, `Reset_Comm` | Out | 1 | - | Events: start of the reset application and of the reset communication sub-state |
| `Err_Cs` | Out | 1 | - | Event: NMT message with an unknown command specifier |
| `Err_NodeId` | Out | 1 | - | Event: the NODE-ID copies are not complementary |
| `Err_TxTimeout` | Out | 1 | - | Event: no completion of a taken request within 256 ticks |
| `ErrInj_BitFlip`, `ErrInj_Valid` | In | 14, 1 | 0, '0' | **Test input.** Inverts the selected bits of the NODE-ID copies (section 2). A system ties both to 0 |

## 7. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `MinimalSet_g` | false | true, false | Minimal protocol set of clause 9 (section 5) |

`SyncStages_c` = 2 is a constant: the stages of `olo_intf_sync` and the length of `Init_s`.

## 8. Timing and behaviour

Cycle 0 is the first cycle with `Rst` = '0'.

| Operation | Duration |
| --- | --- |
| Reset to `Reset_App` | Cycle 2; `Reset_Comm` and the sample in cycle 3; `Tx_Valid` of the boot-up message in cycle 4 |
| `Rx_Valid` to the new state, `Stat_State` and the service enables | 1 clock cycle |
| `Rx_Valid` with reset node to `Reset_App` | 1 clock cycle; `Reset_Comm` 1 cycle later, `Tx_Valid` of the boot-up message 1 cycle after that |
| `Rx_Valid` with reset communication to `Reset_Comm` | 1 clock cycle; `Tx_Valid` of the boot-up message 1 cycle later |
| `Tick_Ms`, `Red_Switched` or a change of P to `Tx_Valid` of a heartbeat | 1 clock cycle |
| Completion of the boot-up message to the service enables | 1 clock cycle |
| Upset of a NODE-ID copy to `Node_IdValid` = '0' and `Err_NodeId` | Same cycle; `Reset_Comm` in the next cycle |
| Taken request without completion to `Err_TxTimeout` | Between 255 and 256 ms |
| Heartbeat period | P ticks of `Tick_Ms`; the first interval after a restart is between P - 1 and P milliseconds, as a restart is not aligned with the tick |

Every NMT message is processed in the cycle after `Rx_Valid`, also in consecutive cycles, well within the minimum frame
time of 46 bit times (NM-SM-07).
