# ocan_mib: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_mib: the AXI4-Lite slave olo_axi_lite_slave with its register bus, the register file with
control and bit timing, the flags with the interrupt, the error counters, the PDO registers, the mailbox, the local
time and the error injection, and the ports towards ocan_core](img/ocan_mib_arch.drawio.svg)

`olo_axi_lite_slave` turns the AXI4-Lite accesses into a register bus (`Rb_*`): one access at a time, a write as a
one-cycle `Rb_Wr` with the address and the data, a read as a one-cycle `Rb_Rd` answered with `Rb_RdValid` in the next
clock cycle, so that the read time-out of the slave never expires. The register file is one two-process record in
`Clk`; every output towards the core is a register or a function of registers only, so no path leads from an input of
the core to an output. The byte strobes are not used (MB-IF-01). The register map is in
[register_map.md](register_map.md); the RTL takes every address and field position from `ocan_regs_pkg`.

| Access of the slave | Clock cycle of the effect |
| --- | --- |
| Write | The cycle in which `BValid` rises: the register takes the value at the end of that cycle |
| Read | The cycle after the read address handshake: the inputs of that cycle form the word, `RValid` follows two cycles later |

## 2. Control and bit timing (MB-1)

CONTROL.ENABLE and APP_ENABLE are registers; RECOVER, REENABLE_A and REENABLE_B set one-cycle pulses that drive
`Ctrl_Recover` and `Ctrl_Reenable` in the clock cycle after the write. BIT_TIMING drives `Cfg_*`. A write to
BIT_TIMING is taken only while ENABLE is '0' and its fields are in the ranges of `olo_intf_can` (`timingOk`: Tseg1 2
to 31, Tseg2 2 to 15, Sjw 1 to min(4, Tseg2)); otherwise the event CFG_REFUSED sets its flag (MB-CT-04). The
prescaler has no forbidden value: `olo_intf_can` counts 0 as 1. The reset values come from `AutoEnable_g`,
`Prescaler_g`, `Tseg1_g`, `Tseg2_g` and `Sjw_g`.

## 3. Flags, interrupt and counters (MB-2)

| Register | Bits | Events |
| --- | --- | --- |
| EVENTS | 9:0 | `Sync_Valid`, `Evt_ResetApp`, `Evt_ResetComm`, `Evt_BdefaultUpdate`, `Evt_TimeSet`, `Evt_TimeSync`, `Evt_SdoAbortTx`, `Evt_SdoAbortRx`, `Evt_LinkArbLost`, a request taken into the mailbox |
| PDO_EVENTS | 23:0 | `Rpdo_Valid`, `Evt_TpdoSent`, `Evt_TpdoAborted`, `Err_RpdoLength`, `Err_TpdoBusy`, `Err_TpdoTimeout`, four bits each |
| ERRORS | 16:0 | The 16 `Err_*` outputs of the NMT, the redundancy, the object dictionary, the dispatch, the SDO server and the time, and CFG_REFUSED |
| LINK_ERRORS | 13:8, 5:0 | `Err_LinkBit`, `Err_LinkStuff`, `Err_LinkCrc`, `Err_LinkForm`, `Err_LinkAck`, `Err_LinkDomTimeout` of controller B and A |

Each flag register is updated in one statement: next = (flags and not the written ones) or the events of the cycle,
so an event in the clock cycle of the clearing write keeps its flag (MB-FL-01). The interrupt register takes the OR of
all flags and their enables of the next state, so `Irq` rises in the clock cycle after the event and falls in the
clock cycle after the clearing write. IRQ_STATUS reads the same OR per flag register.

The error counters are twelve 8-bit registers (six per controller). A write to LINK_A_COUNTS0 or LINK_B_COUNTS0
clears the bit, stuff, CRC and form counters of its controller, a write to LINK_A_COUNTS1 or LINK_B_COUNTS1 the
acknowledgement and dominant timeout counters; the next value is then the event of the cycle (0 or 1), otherwise the
counter adds the event below 255. A read has no effect on the counters (MB-CN-01).

## 4. PDOs, mailbox and time (MB-3)

**Receive PDOs.** RPDOn_HI reads bits 63 to 32 of the PDO at `Rpdo_Data` in the read cycle and takes bits 31 to 0
into the register `RpdoLo(n)`, which RPDOn_LO reads; both words therefore come from one clock cycle (MB-PD-01).

**Transmit PDOs.** `TpdoNext(n)` holds the words that software writes; `TpdoData(n)` drives `Tpdo_Data`. UPDATE copies
`TpdoNext(n)` into `TpdoData(n)`; REQUEST copies it and sets the one-cycle `Tpdo_Req(n - 1)` in the same clock edge,
so the core never samples half of an old and half of a new PDO (MB-PD-02). The registers of the absent PDOs are not
generated (loops to `NumRpdo_g` - 1 and `NumTpdo_g` - 1) and read zero.

**Mailbox.** With APP_ENABLE = '1' the port answers `App_ReqReady` = not PENDING. A request is taken in the clock
cycle in which `App_ReqValid` is '1' while PENDING is '0'; its fields are stored and PENDING and the event
APP_REQUEST are set. A write of SEND while PENDING is '1' sets the one-cycle `App_RspValid` with the response registers
and clears PENDING. `Err_AppTimeout` and APP_ENABLE = '0' clear PENDING: `ocan_od` has then ended the access, and a
later SEND finds no pending request. With APP_ENABLE = '0' the outputs are the default values of the port
(`App_ReqReady` = '1', `App_RspValid` = '1', `App_RspAbort` = 0602 0000h, data and length 0), so the core answers every
request in the clock cycle after it (OD-AP-04); clearing APP_ENABLE while a request is pending ends it the same way.

| Event in a clock cycle | PENDING next |
| --- | --- |
| Request taken | '1' |
| SEND while PENDING | '0' |
| `Err_AppTimeout` or APP_ENABLE = '0' | '0' (also over a request taken in the same cycle) |
| Otherwise | unchanged |

**Time.** A read of TIME_COARSE returns `Time_Coarse` and takes `Time_Fine` into `FineSnap`, which TIME_FINE reads
(MB-TM-01). REQUEST of TIME_CONTROL sets the one-cycle `Time_Req`.

## 5. Error injection (MB-4)

With `ErrInjRegs_g` = true, ERRINJ_SELECT (target, windows w0 and w1), ERRINJ_MASK0, ERRINJ_MASK1 and the level
LINK_TX_DOMINANT are registers; INJECT sets the one-cycle `InjPulse` and LINK_STOP_FLIP_A and B the one-cycle
`StopFlip`. During `InjPulse` the outputs are, for bit i of the selected target:

```text
ErrInj_<target>BitFlip(i) = (Mask0(i mod 32) and w0 = i / 32) or (Mask1(i mod 32) and w1 = i / 32)
ErrInj_<target>Valid      = '1'
```

The decode is a function of registers only, so the 558 bits of `ErrInj_OdBitFlip` need no register of their own.
Bits beyond the width of a target (window 17 above bit 557, windows 1 to 31 of the NMT target) have no output and
are ignored. With `ErrInjRegs_g` = false the registers are not written, read zero and the outputs are constant '0',
which synthesis removes (MB-EI-03).

## 6. Protection

`ocan_mib` holds no parameter of the standard: the protected parameters stay in `ocan_od` and `ocan_dispatch`, the
NODE-ID in `ocan_nmt`. Its registers are covered by the protection scope of the user guide (TMR of the synthesis
tool). Without that TMR an upset of a register gives at most:

- CONTROL.ENABLE: the controllers stop or start until software writes it again;
- BIT_TIMING: a wrong bit timing until software writes it again (a value outside the ranges of `olo_intf_can` only
  through the upset);
- a flag, an enable, a counter: a wrong interrupt or count until software clears it;
- PENDING: a request without its port state (cleared by `Err_AppTimeout` of the core after 256 ticks) or a lost
  response (the core times out and answers 0800 0000h);
- a pulse register: one pulse more or less (a recovery, a request, an injection only with `ErrInjRegs_g`).

No upset of a single register stops the register access: `olo_axi_lite_slave` recovers its FSM in `when others`, and
every read is answered in the next clock cycle.

## 7. Ports of ocan_mib

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | In | 1 | Clock and synchronous high-active reset |
| `S_AxiLite_*` | | | AXI4-Lite slave: `ArAddr`, `AwAddr` 9 bits, `WData`, `RData` 32 bits, `WStrb` 4 bits (not used), `BResp`, `RResp` 2 bits, handshakes |
| `Irq` | Out | 1 | Interrupt, '1' while an enabled flag is set |
| `Ctrl_*`, `Cfg_*` | Out | as `ocan_core` | Control and bit timing of `ocan_core` |
| `Tpdo_Req`, `Tpdo_Data` | Out | 4, 256 | Transmit PDOs of `ocan_core` |
| `App_ReqReady`, `App_RspValid`, `App_RspData`, `App_RspLen`, `App_RspAbort` | Out | 1, 1, 64, 4, 32 | Application port of `ocan_core` |
| `Time_Req` | Out | 1 | Request of the Local Time PDO |
| `ErrInj_*` | Out | as `ocan_core` | Error injection inputs of `ocan_core` |
| `Node_*`, `Sync_Valid`, `Rpdo_*`, `Stat_*`, `Evt_*`, `Err_*`, `App_Req*` (in), `Time_Coarse`, `Time_Fine` | In | as `ocan_core` | Outputs of `ocan_core` |

The ports towards the core have the names, widths and layouts of the ports of `ocan_core`, so that `ocan_axi`
connects them by name.

## 8. Configuration parameters

The generics of the specification (section 4) and those of `ocan_core` that GENERICS, DOMINANT_LIMIT and
CLK_FREQUENCY report, with the names, defaults and ranges of `ocan_core`. Elaboration stops with a message for a
`BusAccess_g` other than "Selective" and "Parallel" and for `Sjw_g` above `Tseg2_g`.

## 9. Timing and behaviour

| Operation | Duration |
| --- | --- |
| Write: write data handshake to the write | The next clock cycle, in which `BValid` rises; the register takes the value at its end |
| Read: read address handshake to `RValid` | 3 clock cycles; the word is formed from the inputs of the clock cycle after the handshake |
| Event to its flag; flag to `Irq` | 1 clock cycle; together (the interrupt register takes the next state) |
| Write of a command bit to its pulse | 1 clock cycle after the cycle of the write, for one clock cycle |
| Request of the application port to APP_REQ.PENDING | 1 clock cycle |
| SEND to `App_RspValid` | 1 clock cycle after the cycle of the write |
