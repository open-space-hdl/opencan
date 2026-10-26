# ocan_mib: Specification

## 1. Overview

`ocan_mib` is the register interface of OpenCAN for a processor system (decision D6 of the
[architecture](../../../docs/architecture.md)): an AXI4-Lite slave with the identification and the generics of the
node, the control and the bit timing of the controllers, the status of the network management, the redundancy and
both controllers, sticky event and error flags with an interrupt, the data of the PDOs, a mailbox for the objects of
the user logic, the local time and, for test systems, the error injection. The top level `ocan_axi` connects
`ocan_mib` to the native ports of `ocan_core`; `ocan_core` keeps its ports, and a system without a processor uses them
directly. The register map is described once in `hdl/ocan_mib/regs/ocan_regs.yml`; `tools/regmap.py` generates the
VHDL package `ocan_regs_pkg`, the register map and the C header `sw/ocan_regs.h` from it.

| Block | Entity | Function |
| --- | --- | --- |
| MB-1 | `ocan_mib` | AXI4-Lite slave (`olo_axi_lite_slave`) and register file |
| MB-2 | `ocan_mib` | Event and error flags, interrupt |
| MB-3 | `ocan_mib` | PDO data, application object mailbox, local time |
| MB-4 | `ocan_mib` | Error injection |

`ocan_mib` runs in the clock domain of `ocan_core` (`Clk`): the AXI4-Lite port is synchronous to `Clk`, so there is
no clock crossing in the register path.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| MB-IF-01 | The MIB shall provide an AXI4-Lite slave in `Clk` with 9-bit byte addresses and 32-bit data; every access shall complete with the response OKAY, reads of unused addresses and bits shall return zero, writes to read-only registers and unused addresses shall have no effect, and the byte strobes shall be ignored (registers are written as 32-bit words). | none |
| MB-IF-02 | The MIB shall drive the control, bit timing, PDO, application port, time request and error injection inputs of `ocan_core` and take its status, event and error outputs, without changing a port of `ocan_core`. | none |
| MB-IF-03 | The MIB shall provide a level-sensitive interrupt output in `Clk` (MB-FL-03). | none |

### 2.2 Identification and control (MB-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MB-ID-01 | The register ID shall read 0x4F434101: the letters OCA and the version 1 of the register map. | none |
| MB-ID-02 | The registers GENERICS and CLK_FREQUENCY shall read the generics of the core as listed in the register map. | none |
| MB-CT-01 | CONTROL.ENABLE shall drive `Ctrl_Enable`; its reset value shall be the generic `AutoEnable_g`, so that a node without software joins the network with the bit timing of the generics. | none |
| MB-CT-02 | A write of '1' to CONTROL.RECOVER shall pulse `Ctrl_Recover` for one clock cycle, and a write of '1' to CONTROL.REENABLE_A or CONTROL.REENABLE_B shall pulse `Ctrl_Reenable(0)` or `Ctrl_Reenable(1)`. | 5.6.2a |
| MB-CT-03 | BIT_TIMING shall drive `Cfg_Prescaler`, `Cfg_Tseg1`, `Cfg_Tseg2` and `Cfg_Sjw`; its reset values shall be the generics `Prescaler_g`, `Tseg1_g`, `Tseg2_g` and `Sjw_g`. | 5.4.3 |
| MB-CT-04 | A write to BIT_TIMING shall take effect only while CONTROL.ENABLE is '0' and only with values in the ranges of `olo_intf_can` (Tseg1 2 to 31, Tseg2 2 to 15, Sjw 1 to min(4, Tseg2)); any other write to BIT_TIMING shall leave it unchanged and set ERRORS.CFG_REFUSED. | 5.4.3 |

### 2.3 Status (MB-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MB-ST-01 | The register NODE shall read the NMT state, the NODE-ID and its validity, the error register 1001h and the PDO, SDO and time status of the core (`Stat_NmtState`, `Node_Id`, `Node_IdValid`, `Stat_ErrReg`, `Stat_PdoEnabled`, `Stat_SdoOpen`, `Stat_TimeSet`). | 6.5.4a |
| MB-ST-02 | The register REDUNDANCY shall read the active bus, the bus selection process, the bus switch, Ctoggle and the state and presence of the master heartbeat (`Stat_ActiveBus`, `Stat_Selecting`, `Stat_LinkSwitching`, `Stat_Ctoggle`, `Stat_MasterHbState`, `Stat_MasterHbPresent`). | 8.3.3 |
| MB-ST-03 | The registers LINK_A and LINK_B shall read, per controller, the transmit and the receive error counter, the fault confinement state (error active, error passive, bus off), the bus idle state and the dominant timeout (`Stat_LinkTec`, `Stat_LinkRec`, `Stat_LinkState`, `Stat_LinkBusIdle`, `Stat_LinkDomTimeout`); a read shall not change a state of the controllers. | 5.6.2b, 5.6.2c |
| MB-ST-04 | The register COB_ID_MISMATCH shall read `Stat_CobIdMismatch`, and TPDO_STATUS the busy flags of the transmit PDOs (`Stat_TpdoBusy`). | 6.10d |

### 2.4 Flags and interrupt (MB-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MB-FL-01 | Every event and error output of the core (`Evt_*`, `Err_*`), `Sync_Valid`, `Rpdo_Valid`, a request of the application port and a refused write to BIT_TIMING shall set its sticky flag in EVENTS, PDO_EVENTS, ERRORS or LINK_ERRORS; a write of '1' to a flag shall clear it; an event in the clock cycle of the clear shall leave the flag set. | none |
| MB-FL-02 | Every flag register shall have an interrupt enable register with one enable per flag; the enables shall reset to '0'. | none |
| MB-FL-03 | The interrupt output shall be '1' while at least one flag is set whose enable is '1'; IRQ_STATUS shall show for every flag register whether it has such a flag. | none |
| MB-CN-01 | The registers LINK_A_COUNTS0, LINK_A_COUNTS1, LINK_B_COUNTS0 and LINK_B_COUNTS1 shall count, per controller, the bit, stuff, CRC, form and acknowledgement errors and the dominant timeouts in 8-bit counters that saturate at 255; a write to a counter register shall clear its counters, and an event in the clock cycle of the write shall be counted after the clearing. | 5.6.2c |

### 2.5 PDOs, application objects and time (MB-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MB-PD-01 | For every receive PDO n, RPDOn_HI shall read bits 63 to 32 of its data at `Rpdo_Data` (data bytes 0 to 3) and RPDOn_LO bits 31 to 0 (bytes 4 to 7); a read of RPDOn_HI shall take bits 31 to 0 into the value that the next read of RPDOn_LO returns, so that both reads return the data of one PDO. | 6.2a |
| MB-PD-02 | For every transmit PDO n, TPDOn_HI and TPDOn_LO shall hold the next data, written and read back by software; a write of '1' to bit n - 1 of TPDO_CONTROL.UPDATE shall copy both to the data of the PDO at `Tpdo_Data` in one clock cycle, and a write of '1' to bit n - 1 of TPDO_CONTROL.REQUEST shall copy them and pulse `Tpdo_Req(n - 1)` in the same clock cycle, so that a SYNC or a request takes either the complete previous or the complete new data. | 6.2a, 6.3b |
| MB-PD-03 | The registers of the PDOs above `NumRpdo_g` and `NumTpdo_g` shall read zero and ignore writes. | none |
| MB-AP-01 | With CONTROL.APP_ENABLE = '1' the MIB shall take one request of the application port at a time: it shall hold `App_ReqReady` at '1' while no request is pending, store the request (read or write, index, sub-index, data, number of bytes) in APP_REQ, APP_REQ_HI and APP_REQ_LO, set APP_REQ.PENDING and the flag EVENTS.APP_REQUEST. | 6.8a |
| MB-AP-02 | A write of '1' to APP_RSP_CONTROL.SEND while a request is pending shall pulse `App_RspValid` for one clock cycle with the data, the number of bytes and the abort code of APP_RSP_HI, APP_RSP_LO, APP_RSP_LEN and APP_RSP_ABORT, and clear APP_REQ.PENDING; SEND without a pending request shall have no effect. | 6.8a |
| MB-AP-03 | `Err_AppTimeout` shall clear APP_REQ.PENDING, so that a late SEND has no effect (OD-AP-03). | none |
| MB-AP-04 | With CONTROL.APP_ENABLE = '0' (the reset value) the MIB shall drive the application port as its default values do (OD-AP-04): every request ends with 0602 0000h; a pending request ends the same way when APP_ENABLE is cleared. | 6.8a |
| MB-TM-01 | TIME_COARSE shall read `Time_Coarse`; a read of TIME_COARSE shall take `Time_Fine` into the value that the next read of TIME_FINE returns, so that both reads return one instant of the local time. | 7.1.2d |
| MB-TM-02 | A write of '1' to TIME_CONTROL.REQUEST shall pulse `Time_Req` for one clock cycle. | 7.2.2f, 7.2.3k |

### 2.6 Error injection (MB-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| MB-EI-01 | With the generic `ErrInjRegs_g` = true, ERRINJ_SELECT shall select a target (0 the parameters of `ocan_od`, 1 the state of `ocan_nmt`) and two windows of 32 bits, w0 and w1 (bits 32 w to 32 w + 31 of `ErrInj_OdBitFlip` or `ErrInj_NmtBitFlip`), and a write of '1' to ERRINJ_CONTROL.INJECT shall drive the bits of ERRINJ_MASK0 into window w0 and those of ERRINJ_MASK1 into window w1 (their OR when w0 = w1) with the valid input of the target for one clock cycle; mask bits above the width of the target shall be ignored. | none |
| MB-EI-02 | With `ErrInjRegs_g` = true, ERRINJ_CONTROL.LINK_TX_DOMINANT shall drive `ErrInj_LinkTxDominant` as a level, and a write of '1' to ERRINJ_CONTROL.LINK_STOP_FLIP_A or LINK_STOP_FLIP_B shall pulse `ErrInj_LinkStopFlip(0)` or `(1)` for one clock cycle. | none |
| MB-EI-03 | With `ErrInjRegs_g` = false (the default) the error injection registers shall read zero, writes to them shall have no effect and the error injection inputs of the core shall be '0'. | none |

The windows of the error injection address the bits of the test inputs of `ocan_core` (layouts: section 3.3 of the
architecture of `ocan_od` and section 2 of the architecture of `ocan_nmt`). A window covers 32 bits; bit i of
ERRINJ_MASK0 inverts bit 32 w0 + i and bit i of ERRINJ_MASK1 bit 32 w1 + i of the target selected by ERRINJ_SELECT:

| TARGET | WINDOW | Bits of the target | Content |
| --- | --- | --- | --- |
| 0 (`ErrInj_OdBitFlip`) | 0 to 4 | 0 to 159 | Copy A: COB-ID entries 0 to 10 (bits 0 to 142), 1016h sub-index 01h from bit 143 |
| 0 | 5 | 160 to 191 | Copy A: 1016h sub-index 01h to bit 165, 1017h (bits 166 to 181), transmission types from bit 182 |
| 0 | 6 to 8 | 192 to 287 | Copy A: transmission types to bit 261, Bdefault (262), Ttoggle and Ntoggle (263 to 278); copy B: COB-ID entries from bit 279 |
| 0 | 9 to 13 | 288 to 447 | Copy B: COB-ID entries to bit 421, 1016h sub-index 01h (422 to 444), 1017h from bit 445 |
| 0 | 14 to 16 | 448 to 543 | Copy B: 1017h to bit 460, transmission types (461 to 540), Bdefault (541), Ttoggle from bit 542 |
| 0 | 17 | 544 to 557 | Copy B: Ttoggle and Ntoggle to bit 557; mask bits 14 to 31 are ignored |
| 0 | 18 to 31 | none | No effect |
| 1 (`ErrInj_NmtBitFlip`) | 0 | 0 to 13 | `IdCopy` (bits 0 to 6) and `IdCopyN` (bits 7 to 13); mask bits 14 to 31 are ignored |
| 1 | 1 to 31 | none | No effect |

An injection inverts the selected bits in one clock cycle, after every other assignment of that cycle (the rule of
the test inputs of `ocan_od` and `ocan_nmt`). The two copies of a parameter of `ocan_od` lie 279 bits apart, in
different windows: one command with a window in each copy gives a common-mode upset of both copies in one clock cycle,
one with both masks in one copy the upset that the copy check repairs or reports.

### 2.7 Reset and register map

| ID | Requirement | ECSS |
| --- | --- | --- |
| MB-RS-01 | `Rst` shall set every register to its reset value, clear every flag, counter, snapshot and pending request, and end every pulse. | 8.3.2a |
| MB-RG-01 | The VHDL package, the register map documentation and the C header shall be generated from `ocan_regs.yml`; `python tools/regmap.py --check` shall fail when one of them differs from the description. | none |

## 3. Error conditions

| Condition | Response |
| --- | --- |
| Read of an unused address or bit | Zero, response OKAY |
| Write to a read-only register or an unused address | No effect, response OKAY |
| Write to BIT_TIMING while CONTROL.ENABLE = '1', or with a value out of range | BIT_TIMING unchanged, ERRORS.CFG_REFUSED set, response OKAY |
| Event in the clock cycle of the clear of its flag | The flag stays set |
| Counter at 255 | Stays at 255 until it is cleared |
| SEND without a pending request, or after the time-out of the request | No effect |
| Request of the application port while APP_ENABLE = '0' | Answered with 0602 0000h, as with the default values of the port |
| REQUEST of a transmit PDO while it is busy | The data are copied as with UPDATE; the request has no effect in the core, `Err_TpdoBusy` sets PDO_EVENTS.TPDO_BUSY |
| Injection with `ErrInjRegs_g` = false | No effect |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `AutoEnable_g` | true | true, false | Reset value of CONTROL.ENABLE |
| `Prescaler_g`, `Tseg1_g`, `Tseg2_g`, `Sjw_g` | 4, 18, 6, 4 | 1 to 1023, 2 to 31, 2 to 15, 1 to min(4, `Tseg2_g`) | Reset value of BIT_TIMING; the defaults give 1 Mbit/s with the sample point at 75 % at 100 MHz (user guide, section 4.2) |
| `ErrInjRegs_g` | false | true, false | The error injection registers (MB-4) |

The generics of `ocan_core` that GENERICS and CLK_FREQUENCY report are passed to `ocan_mib` by `ocan_axi`:
`BusAccess_g`, `MinimalSet_g`, `TimePdos_g`, `AutoRecover_g`, `NumRpdo_g`, `NumTpdo_g`, `FineBits_g`,
`SyncStages_g`, `DominantLimit_g` and `ClkFrequency_g`.

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.6.2b, 5.6.2c | The error state of both controllers and their error counters are registers that the software reads without an effect on the controllers (MB-ST-03): the non-intrusive read access of clause 5.6.2c. The counters of MB-CN-01 count the error events of the controllers in addition; they serve the assessment of the bus quality and are not the error counters of the fault confinement. |
| 6.10e, 6.10f | The NODE-ID stays a hardware input of `ocan_core` with its complement (clause 6.10e); the MIB only reads it. CONTROL.ENABLE gates the controllers in addition to the NODE-ID check: with `AutoEnable_g` = true the node behaves as `ocan_core` with `Ctrl_Enable` at its default value. |
| 8.3.2a | `Rst` of `ocan_axi` is the hardware reset of the node: it resets `ocan_core` and the MIB. The reset application and the reset communication of the NMT services do not reset the MIB; they set the flags RESET_APP and RESET_COMM for the software. |
