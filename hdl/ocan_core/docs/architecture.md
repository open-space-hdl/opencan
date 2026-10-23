# ocan_core: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_core: the reset synchroniser and the tick, ocan_link with one or two olo_intf_can, ocan_dispatch,
ocan_nmt, ocan_redundancy, ocan_od, ocan_sdo, ocan_pdo and ocan_time, with the ports of the core](img/ocan_core_arch.drawio.svg)

`ocan_core` is a structural entity: the eight blocks of the architecture of OpenCAN, connected as their interface
requirements specify, and three pieces of logic of its own (CO-1, CO-2 and the selection of section 5). It has no
state machine and no register of its own besides those of `olo_base_reset_gen` and `olo_base_strobe_gen`.

## 2. Reset and tick (CO-1, CO-2)

`Rst` is asynchronous and high-active. `olo_base_reset_gen` (`SyncTmr_g` = true, `SyncStages_g` of the core,
`RstPulseCycles_g` 3) asserts its output at once and releases it synchronously; the output is `Rst` of all eight blocks
and of the tick. It is the hardware reset of clause 8.3.2a: the node restarts on Bdefault (RM-SL-01).

`olo_base_strobe_gen` makes the tick `Tick_Ms` from `ClkFrequency_g`: one cycle every round(`ClkFrequency_g` /
1000) cycles. The same tick drives `ocan_nmt`, `ocan_redundancy`, `ocan_od`, `ocan_sdo`, `ocan_pdo` and `ocan_time`,
so that all time-outs and heartbeat times count the same milliseconds. The local time of `ocan_time` is not derived
from the tick: it advances with the clock by `ClkFrequency_g` (TM-CT-02).

## 3. Connections (CO-3)

| From | To | Signals |
| --- | --- | --- |
| `ocan_link` | `ocan_dispatch` | The received frames of each bus (`Rx_*` to `LinkRx_*`); the handshake and the completion of the frame to send (`Tx_Ready`, `Tx_Done`, `Tx_Aborted`, `Tx_Stopped` to `LinkTx_*`) |
| `ocan_dispatch` | `ocan_link` | The frame to send (`LinkTx_Valid`, `_Id`, `_Dlc`, `_Data`, `_Abort` to `Tx_*`); `Tx_Ide` and `Tx_Rtr` are '0' (CO-CN-05) |
| `ocan_link` | `ocan_redundancy` | `Stat_ActiveBus`, `Stat_Switching` to `Link_ActiveBus`, `Link_Switching` |
| `ocan_redundancy` | `ocan_link` | `Link_Bus` to `Ctrl_Bus` (the requested active bus) |
| Core, `ocan_nmt` | `ocan_link` | `Ctrl_Enable` of the core and `Node_IdValid` to `Ctrl_Enable` |
| `ocan_link` | `ocan_od` | `Stat_State` of the controller of the active bus to `Link_State` (section 5) |
| `ocan_redundancy` | `ocan_dispatch` | `Stat_ActiveBus`, `Stat_Selecting` to `Red_ActiveBus`, `Red_Selecting` |
| `ocan_redundancy` | `ocan_nmt` | `Nmt_PreopReq`, `Nmt_Switched`, `Stat_Selecting` to `Red_PreopReq`, `Red_Switched`, `Red_Selecting` |
| `ocan_dispatch` | `ocan_redundancy` | `RxRed_NmtValid`, `RxRed_HbValid`, `RxRed_HbDlc`, `RxRed_HbState` to `Rx_*` |
| `ocan_nmt` | `ocan_dispatch` | `Node_Id`, `Node_IdValid`, `Ena_Sdo`, `Ena_Pdo`, `Ena_Sync` |
| `ocan_nmt` | `ocan_redundancy` | `Stat_State` to `Nmt_State` |
| `ocan_nmt` | `ocan_od` | `Stat_State`, `Node_Id`, `Reset_App`, `Reset_Comm` |
| `ocan_nmt` | `ocan_sdo` | `Ena_Sdo`, `Reset_App`, `Reset_Comm` |
| `ocan_nmt` | `ocan_pdo`, `ocan_time` | `Ena_Pdo` and `Reset_Comm` (pdo), `Reset_Comm` (time) |
| `ocan_dispatch` | protocol blocks | `RxNmt_*` (nmt), `RxSync_*` (pdo and time), `RxRpdo_*` (pdo), `RxTime_*` (time), `RxSdo_*` (sdo) |
| protocol blocks | `ocan_dispatch` | `TxNmt_*` (nmt), `TxTpdo_*` (pdo), `TxTime_*` (time), `TxSdo_*` (sdo), each with its completion |
| `ocan_od` | `ocan_dispatch` | `Cfg_CobId`, `Cfg_CobIdCopy` |
| `ocan_od` | `ocan_nmt` | `Cfg_HbTime` |
| `ocan_od` | `ocan_redundancy` | `Cfg_MasterHbTime`, `Cfg_Bdefault`, `Cfg_Ttoggle`, `Cfg_Ntoggle`, `Cfg_Ctoggle`, `Cfg_CtoggleValid` (to `Cfg_HbTime`, `Cfg_Bdefault`, `Cfg_Ttoggle`, `Cfg_Ntoggle`, `Cfg_Ctoggle`, `Cfg_CtoggleWr`) |
| `ocan_redundancy` | `ocan_od` | `Stat_Ctoggle`, `Upd_Valid`, `Upd_Bdefault` |
| `ocan_od` | `ocan_time` | `Cfg_SctType`, `Cfg_LtpType`, `Cfg_SetValid`, `Cfg_SetScet` (to `Cfg_RxType`, `Cfg_TxType`, `Cfg_SetValid`, `Cfg_SetScet`) |
| `ocan_time` | `ocan_od` | `Stat_Scet` |
| `ocan_od` | `ocan_pdo` | `Cfg_RpdoType`, `Cfg_TpdoType` |
| `ocan_sdo` | `ocan_od` | The access interface (`Acc_*` from `ocan_sdo`, `Acc_Ready` and `Rsp_*` back) |

The generics of the core pass to the blocks with their names (specification, section 4); `SdoServer_g` of
`ocan_dispatch` is `not MinimalSet_g`.

## 4. Configurations (CO-CN-04)

| Configuration | `ocan_sdo` | `ocan_time` |
| --- | --- | --- |
| Clause 6 slave with the time PDOs | Present | Present |
| Clause 6 slave without the time PDOs | Present | Present for Local SCET Set and Get (2001h, 2002h): `Rx_TimeValid` '0', `Req_Valid` '0' |
| Minimal set with the time PDOs | Absent: the access interface of `ocan_od` is idle, `TxSdo_Valid` '0' | Present |
| Minimal set without the time PDOs | Absent | Absent: `Time_*`, `Stat_TimeSet` and the time events are 0, `Stat_Scet` of `ocan_od` is 0, `TxTime_Valid` '0' |

An absent block is a generate branch that is not elaborated; its outputs to the other blocks are constants.

## 5. Fault confinement state of the active bus (CO-CN-03)

`Link_State` of `ocan_od` is bits 1 and 0 of `Stat_State` of `ocan_link` with selective bus access (controller 0).
With parallel bus access it is the state of the controller of the active bus: bits 2 b + 1 downto 2 b with b =
`Stat_ActiveBus` of `ocan_link`, so that the error register follows the bus that the node uses. The selection is
combinational.

## 6. Protection

The core adds the triplicated synchroniser of the reset release and the counter of the tick. An upset of the counter
moves one tick by at most one tick period; every time-out and heartbeat time of the blocks is counted in ticks and
tolerates this. The selection of section 5 has no state. All other state is in the blocks; the user guide lists their
protection (section "Protection scope").

## 7. Ports of ocan_core

| Signal | Direction | Width | Default | Description |
| --- | --- | --- | --- | --- |
| `Clk` | In | 1 | - | Clock |
| `Rst` | In | 1 | - | Asynchronous high-active reset (CO-IF-01) |
| `Ctrl_Enable` | In | 1 | '1' | The controllers take part in the buses while '1' and the NODE-ID is valid (CO-IF-04) |
| `Ctrl_Recover`, `Ctrl_Reenable` | In | 1, 2 | '0', "00" | Bus-off recovery and re-enable after a dominant timeout (`ocan_link`) |
| `Cfg_Prescaler`, `Cfg_Tseg1`, `Cfg_Tseg2`, `Cfg_Sjw` | In | 10, 5, 4, 3 | - | Bit timing; static while `Ctrl_Enable` = '1' |
| `Pin_NodeId`, `Pin_NodeIdCode` | In | 7, 7 | - | NODE-ID pins and their complement (asynchronous) |
| `Node_Id`, `Node_IdValid` | Out | 7, 1 | - | Protected NODE-ID and its valid flag |
| `Can_Tx`, `Can_TxEn`, `Can_Rx` | Out, Out, In | 2, 2, 2 | -, -, "11" | Transceivers, bus A in index 0 |
| `Sync_Valid` | Out | 1 | - | SYNC event to the user logic |
| `Rpdo_Valid`, `Rpdo_Data` | Out | 4, 256 | - | Receive PDOs: event and the data last passed |
| `Tpdo_Req`, `Tpdo_Data` | In | 4, 256 | 0 | Transmit PDOs: request and data |
| `Stat_TpdoBusy`, `Stat_PdoEnabled` | Out | 4, 1 | - | A request of the transmit PDO is pending; the PDO enable |
| `Evt_TpdoSent`, `Evt_TpdoAborted` | Out | 4, 4 | - | Completion of a transmit PDO |
| `Err_RpdoLength`, `Err_TpdoBusy`, `Err_TpdoTimeout` | Out | 4, 4, 4 | - | `Err_RxLength`, `Err_TxBusy`, `Err_TxTimeout` of `ocan_pdo` |
| `App_ReqValid`, `App_ReqReady`, `App_ReqWrite`, `App_ReqIndex`, `App_ReqSub`, `App_ReqData`, `App_ReqLen` | Out, In, Out, Out, Out, Out, Out | 1, 1, 1, 16, 8, 64, 4 | -, '1', - | Request of the application port of `ocan_od` |
| `App_RspValid`, `App_RspData`, `App_RspLen`, `App_RspAbort` | In | 1, 64, 4, 32 | '1', 0, 0, 0602 0000h | Response of the user logic |
| `Time_Coarse`, `Time_Fine` | Out | 32, 24 | - | Local time |
| `Time_Req` | In | 1 | '0' | Request of the Local Time PDO (types 0, 254, 255) |
| `Stat_TimeSet`, `Evt_TimeSet`, `Evt_TimeSync` | Out | 1 | - | `Stat_TimeSet`, `Evt_Set`, `Evt_Sync` of `ocan_time` |
| `Err_TimeTxBusy`, `Err_TimeRxDrop`, `Err_TimeTxTimeout` | Out | 1 | - | Events of `ocan_time` |
| `Stat_NmtState` | Out | 2 | - | NMT state |
| `Evt_ResetApp`, `Evt_ResetComm` | Out | 1 | - | Reset application and reset communication events (to reset the device, CO-AP-13) |
| `Err_NmtCs`, `Err_NodeId`, `Err_NmtTxTimeout` | Out | 1 | - | Events of `ocan_nmt` |
| `Stat_ActiveBus`, `Stat_Selecting`, `Stat_Ctoggle` | Out | 1, 1, 8 | - | Active bus, bus selection process, Ctoggle |
| `Stat_MasterHbState`, `Stat_MasterHbPresent` | Out | 8, 2 | - | State in the last master heartbeat; presence per bus |
| `Evt_BdefaultUpdate`, `Err_MasterHbMissing`, `Err_ToggleEnd`, `Err_MasterHbDlc` | Out | 1 | - | Events of `ocan_redundancy` |
| `Stat_ErrReg`, `Err_ParamCopy`, `Err_AppTimeout` | Out | 8, 1, 1 | - | Error register and events of `ocan_od` |
| `Stat_CobIdMismatch`, `Err_Protocol`, `Err_CobId` | Out | 12, 1, 1 | - | COB-ID compare and events of `ocan_dispatch` |
| `Stat_SdoOpen`, `Evt_SdoAbortTx`, `Evt_SdoAbortRx`, `Err_SdoRxDrop`, `Err_SdoTxTimeout`, `Err_SdoAccTimeout` | Out | 1 | - | Status and events of `ocan_sdo` (0 with `MinimalSet_g`) |
| `Stat_LinkTec`, `Stat_LinkRec`, `Stat_LinkState`, `Stat_LinkBusIdle`, `Stat_LinkDomTimeout` | Out | 18, 16, 4, 2, 2 | - | Per controller (controller 0 in the low bits): error counters, fault confinement state, bus idle, dominant timeout |
| `Stat_LinkSwitching`, `Evt_LinkArbLost` | Out | 1 | - | Bus switch in progress; arbitration lost |
| `Err_LinkBit`, `Err_LinkStuff`, `Err_LinkCrc`, `Err_LinkForm`, `Err_LinkAck`, `Err_LinkDomTimeout` | Out | 2 | - | Error events per controller |
| `ErrInj_OdBitFlip`, `ErrInj_OdValid` | In | 558, 1 | 0 | Test inputs of `ocan_od` (tie to 0 in a system) |
| `ErrInj_NmtBitFlip`, `ErrInj_NmtValid` | In | 14, 1 | 0 | Test inputs of `ocan_nmt` |
| `ErrInj_LinkTxDominant`, `ErrInj_LinkStopFlip` | In | 2, 2 | "00" | Test inputs of `ocan_link` |

## 8. Timing

Every received frame reaches the user logic and the blocks a constant number of clock cycles after its reception by
`olo_intf_can`, the same on both buses and in both bus access architectures (LK-RX-01, DS-RX-05): the core adds no
stage. The verification report states the measured values from the end of a frame on the bus to `Rpdo_Valid`,
`Sync_Valid` and the SYNC sample of the local time, and from a request at the ports to the start of the frame.
