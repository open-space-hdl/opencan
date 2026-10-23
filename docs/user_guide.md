# OpenCAN User Guide

OpenCAN is a slave node of ECSS-E-ST-50-15C (CANbus extension protocol) on a nominal and a redundant bus, in
technology-independent VHDL-2008. This guide is for the integrator of the top level `ocan_core`: the sources, the
generics, the clock and reset, the interfaces, the protection scope, the integration constraints and the conformance
to the standard. The [architecture](architecture.md) describes the design, the module documents under `hdl/` the
requirements and their verification.

## 1. Sources

| Library | Sources | Order |
| --- | --- | --- |
| `olo` | Open Logic, fork open-space-hdl/open-logic-ft, tag 4.7.0-ft.9 (submodule `open-logic`): the areas `base` and `intf` | `open-logic/compile_order.txt` |
| `opencan` | `hdl/<module>/src/*.vhd` of the nine modules | `compile_order.txt` |

The top level is `ocan_core` in the library `opencan`. It uses `olo_intf_can` (the CAN controller),
`olo_base_reset_gen`, `olo_base_strobe_gen` and `olo_base_arb_rr` of Open Logic, and no vendor primitive.

## 2. Generics

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `BusAccess_g` | "Selective" | "Selective", "Parallel" | Bus access architecture of clause 8.2: one controller with a bus selector, or one controller per bus (the controller of the inactive bus listens only) |
| `SyncStages_g` | 2 | 2 to 4 | Synchroniser stages of the bus inputs and of the reset release |
| `AutoRecover_g` | true | true, false | Recovery from bus off after 128 occurrences of 11 recessive bits; false: on `Ctrl_Recover` |
| `DominantLimit_g` | 32 | 13 to 1023 | Bit times of a dominant transmit output after which a controller stops (dominant timeout) |
| `MinimalSet_g` | false | true, false | Minimal protocol set of clause 9 instead of the clause 6 slave: no node control, no boot-up message, no SDO server, a fixed object dictionary |
| `NumRpdo_g`, `NumTpdo_g` | 4 | 0 to 4; at most 3 with `MinimalSet_g` and `TimePdos_g` | Receive and transmit PDOs with the COB-IDs of the pre-defined connection set |
| `TimePdos_g` | true | true, false | Spacecraft Time PDO and Local Time PDO of clause 7 |
| `ClkFrequency_g` | 100000000 | 1000000 to 2147483647 | Frequency of `Clk` in Hz: the millisecond tick and the local time |
| `FineBits_g` | 24 | 0 to 24 | Bits of sub-seconds of the local time |
| `DeviceType_g`, `VendorId_g`, `ProductCode_g`, `Revision_g`, `SerialNumber_g` | 0 | 32 bits | Objects 1000h and 1018h |
| `ProducerHbTime_g` | 1000 | 0 to 65535 | Power-on value of the producer heartbeat time 1017h in ms |
| `MasterNodeId_g`, `MasterHbTime_g` | 1, 1500 | 0 to 127, 0 to 65535 | Power-on value of the consumer heartbeat time of the Redundancy Master, 1016h sub-index 01h |
| `Bdefault_g`, `Ttoggle_g`, `Ntoggle_g` | 0, 1, 3 | 0 to 1, 0 to 255, 0 to 255 | Power-on values of Bdefault (0 bus A, 1 bus B), Ttoggle and Ntoggle (2000h) |
| `RpdoType_g`, `TpdoType_g` | 254 | 0 to 240, 254, 255 | Power-on transmission types of the receive and transmit PDOs |
| `SctCobId_g`, `SctType_g`, `LtpCobId_g`, `LtpType_g` | 0, 254, 0, 254 | 0 to 2047; 0 to 240, 254, 255 | COB-IDs (0: not valid) and transmission types of the Spacecraft Time PDO and of the Local Time PDO; with `MinimalSet_g` and `TimePdos_g` the COB-IDs must not be 0 |

Inconsistent values stop the elaboration with a message: `BusAccess_g`, more than 3 PDOs or a time COB-ID of 0 in the
minimal set with the time PDOs, a restricted or free COB-ID, two equal time COB-IDs, and a transmission type from 241 to
253.

## 3. Clock, reset and tick

`Clk` is the only clock; every port is synchronous to it except `Rst`, `Can_Rx` and the NODE-ID pins. `Rst` is an
asynchronous high-active reset; the core synchronises its release with triplicated synchronisers. It is the hardware
reset of clause 8.3.2a: the node restarts on Bdefault with the power-on values of the generics. The core makes its
millisecond tick from `ClkFrequency_g`, which must be the frequency of `Clk`.

The NODE-ID pins and their complement are sampled in the reset communication sub-state and, while the code is not
valid, at every tick. Keep them stable during these samples; they need no synchroniser of the integrator.

## 4. Interfaces

### 4.1 Transceivers

| Signal | Selective bus access | Parallel bus access |
| --- | --- | --- |
| `Can_Tx(b)`, `Can_Rx(b)` | Bus b of the selector: only the active bus carries frames of the node | The controller of bus b |
| `Can_TxEn(b)` | '1' for the active bus, '0' for the other one | '1' for the active bus; '0' for the inactive bus, whose controller listens only |

Bus A has index 0, bus B index 1. A transceiver without an enable (ISO 11898-2) takes `Can_Tx` only; with selective
bus access `Can_Tx` of the inactive bus is recessive. An RS-485 transceiver takes `Can_TxEn` as its driver enable.

### 4.2 Bit timing

`Cfg_Prescaler`, `Cfg_Tseg1`, `Cfg_Tseg2` and `Cfg_Sjw` set the bit timing of both controllers: bit rate = clock
frequency / (`Cfg_Prescaler` x (1 + `Cfg_Tseg1` + `Cfg_Tseg2`)), sample point = (1 + `Cfg_Tseg1`) / (1 + `Cfg_Tseg1` +
`Cfg_Tseg2`). They are taken while the controllers are enabled; change them only while `Ctrl_Enable` = '0'. Clause
5.4.3 requires the bit timing and the sample point of a system to be calculated by the method of iCC 2012 for the
propagation delay and the oscillator tolerance of that system; the core accepts every configuration of 8 to 25 time
quanta per bit. The function `canBitTiming` of `olo_intf_pkg_can` gives a configuration for a clock, a bit rate and a
sample point. With a sample point of 75 %:

| `Clk` | 1 Mbit/s | 500 kbit/s | 250 kbit/s | 125 kbit/s |
| --- | --- | --- | --- | --- |
| 40 MHz | 2, 14, 5, 4 | 4, 14, 5, 4 | 8, 14, 5, 4 | 16, 14, 5, 4 |
| 50 MHz | 2, 18, 6, 4 | 4, 18, 6, 4 | 8, 18, 6, 4 | 16, 18, 6, 4 |
| 100 MHz | 4, 18, 6, 4 | 8, 18, 6, 4 | 16, 18, 6, 4 | 32, 18, 6, 4 |

The values are `Cfg_Prescaler`, `Cfg_Tseg1`, `Cfg_Tseg2`, `Cfg_Sjw`. The clock needs at least 8 cycles per bit.

### 4.3 PDO port

The user logic receives the data of receive PDO n at `Rpdo_Data(64 n - 1 downto 64 (n - 1))` with the event
`Rpdo_Valid(n - 1)`; the data stay until the next PDO of that number. It sends transmit PDO n with `Tpdo_Data` and a
one-cycle `Tpdo_Req(n - 1)`. Data byte 0, the first on the bus, is in bits 63 to 56 of the 64 bits of a PDO; data
byte k - 1 is sub-index k of the mapped object 2100h + n - 1 (receive) or 2200h + n - 1 (transmit). The transmission
type decides when a PDO is passed or requested:

| Type | Receive PDO | Transmit PDO |
| --- | --- | --- |
| 0 | At the next SYNC | At the SYNC after a request, with the data of the cycle of the SYNC |
| 1 to 240 | At the next SYNC | At every n-th SYNC, with the data of the cycle of the SYNC; requests have no effect |
| 254, 255 | At once | At a request, with the data of the cycle of the request |

- A request while the request of that PDO is pending (`Stat_TpdoBusy`) has no effect and raises `Err_TpdoBusy`; the
  completion raises `Evt_TpdoSent` or `Evt_TpdoAborted`. A request in the cycle of a change of the transmission type
  acts with the new type.
- PDOs exist in Operational only (`Stat_PdoEnabled`). A request while `Stat_PdoEnabled` = '0' has no effect.
- `Sync_Valid` marks every SYNC. In the minimal set, where every transmission type is 254, the user logic sends a
  PDO triggered by the SYNC (clause 9.4.3b) by a request at `Sync_Valid`, and answers a telemetry request after the
  receive PDO of the request. The rule of clause 9.4.3c, no spontaneous message, is a duty of the user logic.
- The frames due at the same SYNC are sent in the round-robin order of the sources, which starts after the source of
  the last frame: the Local Time PDO can come before or after a transmit PDO. Each frame waits for at most one frame
  of every other source; the Local Time PDO carries the sample of the SYNC, so its value does not depend on its place.
- The node has no inhibit time: the rate of the event-driven transmit PDOs is the rate of the requests. The integrator
  bounds the request rate. A user logic that requests without pause fills the bus with PDOs of high priority and
  starves the master heartbeat; the nodes then enter Pre-operational (clause 8.3.3e) and the network falls back
  instead of locking up.

### 4.4 Application objects

The objects 2003h to 9FFFh, the mapped PDO objects 2100h to 2103h and 2200h to 2203h among them, reach the user
logic through the application port: a request (`App_ReqValid`, `App_ReqReady`, read or write, index, sub-index, data
and number of bytes) and its response (`App_RspValid` with the data, the number of bytes and an abort code, 0 for
success). A response must come within 256 ticks, otherwise the access ends with 0800 0000h (`Err_AppTimeout`). With
the inputs at their defaults every access ends with 0602 0000h (object does not exist).

The user logic answers the mapped objects consistently with the PDO port: the objects of the receive PDOs (2100h to
2103h) as rw or wo and those of the transmit PDOs (2200h to 2203h) as ro or rw, since \[CiA301\] (Corrigendum 3)
allows no read-only object in a receive PDO and no write-only object in a transmit PDO. Example: 2100h sub-index 01h
(data byte 0 of receive PDO 1) as rw, a read returning the byte last passed at `Rpdo_Data(63 downto 56)`; 2200h
sub-index 01h as ro, a read returning the byte that the user logic sends at `Tpdo_Data(63 downto 56)`, a write
refused with 0601 0002h.

### 4.5 Local time

`Time_Coarse` (seconds) and `Time_Fine` (2^-`FineBits_g` s, aligned to bit 23) are the local SCET in every cycle,
`Stat_TimeSet` is '1' once it has been set. The Spacecraft Time PDO sets it (basic protocol with types 254 and 255,
high-resolution protocol with types 0 to 240, relative to the SYNC); Local SCET Set (2001h) sets it by SDO. The
Local Time PDO is sent at its SYNCs or, with types 0, 254 and 255, on `Time_Req`.

### 4.6 Status and events

| Group | Ports |
| --- | --- |
| NMT | `Stat_NmtState` ("00" Initialisation, "01" Pre-operational, "10" Operational, "11" Stopped), `Node_Id`, `Node_IdValid`; `Evt_ResetApp` (reset the application of the device, clause 11.1), `Evt_ResetComm`; `Err_NmtCs`, `Err_NodeId`, `Err_NmtTxTimeout` |
| Redundancy | `Stat_ActiveBus`, `Stat_Selecting` (bus selection process), `Stat_Ctoggle`, `Stat_MasterHbState`, `Stat_MasterHbPresent`; `Evt_BdefaultUpdate`, `Err_MasterHbMissing`, `Err_ToggleEnd`, `Err_MasterHbDlc` |
| Link, per controller (clause 5.6.2) | `Stat_LinkTec`, `Stat_LinkRec`, `Stat_LinkState` ("00" error active, "01" error passive, "11" bus off), `Stat_LinkBusIdle`, `Stat_LinkDomTimeout`, `Stat_LinkSwitching`; `Evt_LinkArbLost`, `Err_LinkBit`, `Err_LinkStuff`, `Err_LinkCrc`, `Err_LinkForm`, `Err_LinkAck`, `Err_LinkDomTimeout` |
| Object dictionary, dispatch | `Stat_ErrReg` (1001h: bit 0 generic error, bit 4 communication error), `Err_ParamCopy`, `Err_AppTimeout`, `Stat_CobIdMismatch`, `Err_Protocol`, `Err_CobId` |
| SDO server | `Stat_SdoOpen`, `Evt_SdoAbortTx`, `Evt_SdoAbortRx`, `Err_SdoRxDrop`, `Err_SdoTxTimeout`, `Err_SdoAccTimeout` |
| Time | `Evt_TimeSet`, `Evt_TimeSync`, `Err_TimeTxBusy`, `Err_TimeRxDrop`, `Err_TimeTxTimeout` |

`Stat_LinkDomTimeout` is a level: a controller stopped by a dominant timeout stays stopped until `Ctrl_Reenable`.
Events are one-cycle pulses.

## 5. Object dictionary

The objects, their access types and power-on values are table 1 of the [specification of
`ocan_od`](../hdl/ocan_od/docs/specification.md). COB-IDs and transmission types are writable in Pre-operational only;
the mapping objects are read-only and describe the static mapping of section 4.3. With `MinimalSet_g` the object
dictionary is fixed and not reachable. The object dictionary of the node is the basis of the electronic data sheet
of a device (clause 6.6).

## 6. Protection scope

The core is designed for radiation environments together with the triple modular redundancy (TMR) of the synthesis
tool, like the Open Logic ft entities it is built on. It protects the parts in the first rows itself and relies on
TMR for all other logic:

| Part | Protection | Indication and test |
| --- | --- | --- |
| Memories and FIFO buffers | None: the core has no memory and no FIFO; received frames are not buffered, each object holds its last frame in a register | - |
| COB-ID table and the master NODE-ID, the transmission types, the heartbeat times, Bdefault, Ttoggle and Ntoggle | Two copies with a compare: an object whose COB-ID copies disagree is not used, a parameter whose copies disagree takes its power-on value | `Stat_CobIdMismatch`, `Err_CobId`, `Err_ParamCopy`; `ErrInj_OdBitFlip`, `ErrInj_OdValid` |
| NODE-ID | Pins with their complement; two copies, the NODE-ID and its complement | `Err_NodeId`, `Node_IdValid`; `ErrInj_NmtBitFlip`, `ErrInj_NmtValid` |
| Stop state of a controller after a dominant timeout | The state and its complement | `Stat_LinkDomTimeout`; `ErrInj_LinkStopFlip` |
| Clock domain crossings and reset synchronisers | Triplicated synchronisers (`SyncTmr_g` = true) of the bus inputs in `olo_intf_can` and of the reset release: three synchroniser chains and a majority voter. Their registers carry the Synplify attribute `syn_radhardlevel` = `none`, so the TMR of the synthesis tool adds no voters between the stages | none |
| State machines | Recovery state through the `when others` branch and the reset | none |
| All other logic: registers of the control and data paths, counters, pointers, pipeline registers | TMR of the synthesis tool (for example `syn_radhardlevel` = `tmr` with Synplify, or the equivalent setting of the tool chain). The core adds no protection of its own for this logic; without TMR, an upset in it is not covered | synthesis report |

Every transmit source of the core ends the wait for the completion of a frame after 256 ticks and every access of
the application port after 256 ticks, so that a lost completion does not silence the node.

The integrator:

- enables the TMR of the synthesis tool for the core and the logic around it,
- checks in the synthesis report that TMR was applied, that the synchroniser chains of the crossings were not
  triplicated a second time, and that no register-based storage meant to be protected by TMR was inferred as a RAM
  primitive,
- requests safe state machines, so that synthesis keeps the `when others` branches (AMD Vivado: property
  `FSM_SAFE_STATE` = `default_state` on the state registers; Synplify: attribute `syn_encoding` = `safe`),
- protects the configuration memory of SRAM-based FPGAs by scrubbing; this is part of the FPGA design, not of the
  core.

Whether the protection as a whole meets the requirements of a mission is shown by a radiation test with the core in
operation (TRL 5).

## 7. Integration constraints

| Constraint | Reason |
| --- | --- |
| TMR of the synthesis tool enabled for the core | The core protects its parameters, its NODE-ID and its synchronisers itself and relies on TMR for all other logic (section 6) |
| `ClkFrequency_g` equal to the frequency of `Clk` | Millisecond tick and local time |
| Bit timing calculated for the system (clause 5.4.3), changed only while `Ctrl_Enable` = '0' | Section 4.2 |
| NODE-ID pins and their complement stable while they are sampled | Section 3 |
| Request rate of the event-driven transmit PDOs bounded by the user logic | No inhibit time (section 4.3) |
| A response of the application port within 256 ticks | Otherwise the access ends with 0800 0000h |
| `ErrInj_*` tied to 0 | Test inputs |

## 8. Latency

The figures come from the network testbench at 40 MHz and 1 Mbit/s with a sample point of 80 % (verification report
of `ocan_core`, section 2):

| Path | Latency |
| --- | --- |
| Receive PDO of type 254 or 255 to `Rpdo_Valid` | The controller takes a frame in the last but one bit of the end of frame (CAN 2.0B); `Rpdo_Valid` follows 0.925 us after the start of that bit, 1.075 us before the end of the frame: the sample point, the input synchroniser and the pipeline of the link, the dispatcher and the PDO block |
| SYNC to `Sync_Valid` and to `Rpdo_Valid` of the synchronous receive PDOs | As for a receive PDO, in the same clock cycle (`ocan_pdo`) |
| `Tpdo_Req` (types 254, 255) to the start of frame on an idle bus | The controller takes a pending frame at the sample point of a bit of the idle bus and starts it with the next bit: at most about 1.2 bit times plus the pipeline of the PDO block, the dispatcher and the link; measured: 1.075 us |
| `Tpdo_Req` to the start of frame while a frame is on the bus | The end of that frame and the intermission of 3 bit times (CAN 2.0B), then as on an idle bus |

A transmit PDO waits in addition for the frames of higher priority on the bus and, at the arbitration of the node,
for at most one frame of every other transmit source of the node (section 4.3).

## 9. Conformance

OpenCAN implements a slave node of ECSS-E-ST-50-15C with the application layer of \[CiA301\] V4.2.0 as clause 11
applies it. The [compliance matrix](compliance.md) lists the requirements and the test cases of every clause; the
section "Interpretation of the standard" of the module specifications states the behaviour where the standard leaves
a choice.

| Status | Clauses | Scope |
| --- | --- | --- |
| Implemented | 5.4.1, 5.4.2, 5.6.1, 5.6.2, 6.1, 6.2, 6.3, 6.5.1 to 6.5.4, 6.8, 6.9, 6.10, 7.1.2, 7.2.1 to 7.2.3, 8.2.1 to 8.2.3, 8.3.1 to 8.3.3, 9.1 to 9.5, 11.1 | The data link layer on both buses, NMT slave with heartbeat and boot-up, SYNC consumer, PDOs, SDO server with expedited and segmented transfer, object dictionary, NODE-ID and COB-ID protection, the time consumer with both time distribution protocols, both bus access architectures, the bus monitoring and reconfiguration of a slave, the minimal protocol set |
| Partially implemented | 5.3, 5.4.3, 7.1.1, 8.1 | 5.3: the transmit enables of the transceivers; their electrical characteristics belong to the board. 5.4.3: the bit timing is configurable; its calculation for a system is the integrator's (section 4.2). 7.1.1: SCET; the spacecraft UTC is not implemented (D5). 8.1: the slave side of the redundancy management; the Redundancy Master is not part of the core (D1) |
| Not implemented, optional | 6.4, 7.1.3 | The emergency object (D9) and the spacecraft UTC objects (D5) |
| Out of scope | 5.1, 5.2, 5.5, 6.6, 6.7, 10 | Topology, cables, EMC and connectors belong to the board; electronic data sheets and device profiles to the device |

Optional parameters of \[CiA301\] that the node does not implement: the inhibit time and the event timer of the PDOs,
the SYNC counter (1019h) and the SYNC start value, the synchronous window length (1007h), the SDO block transfer, the
dynamic PDO mapping and the SDO server parameter object. The roles of the NMT master, the SYNC producer and the time
producer are not part of the core (D1).

## 10. Verification

Every module is verified by its own testbench with a reference model and by deliberate faults of its RTL; the core by
a network testbench of the whole node in four configurations (both bus access architectures, the clause 6 slave and
the minimal set, with and without the time PDOs). The verification reports of the modules state the results. GHDL
synthesises the core with every combination of `BusAccess_g`, `MinimalSet_g` and `TimePdos_g` without an inferred
latch (`lint/synth_check.py`).

## 11. Resources

Resources and clock frequency with Libero SoC 2025.2 (Synplify Pro W-2025.03M-SP1-1 and SmartTime) for a PolarFire
MPF100T (FCG484, STD speed grade, industrial range), without the TMR of the synthesis tool, with `ErrInj_*` tied to 0
and the other generics at their defaults. The PDO buses need more pins than the device has, so the core is
synthesised, placed and routed as a block without I/O buffers. The clock frequencies are the place and route results
for a 100 MHz constraint at the slow corner. The configurations are those of the network testbench:

| Configuration | Generics | LUT | Flip-flops | RAM | Clock frequency |
| --- | --- | --- | --- | --- | --- |
| Clause 6 slave with the time PDOs | `BusAccess_g` "Selective", `MinimalSet_g` false, `TimePdos_g` true | 7636 | 3410 | 0 | 104 MHz |
| Clause 6 slave, parallel bus access | "Parallel", false, false | 8197 | 3242 | 0 | 108 MHz |
| Minimal set | "Selective", true, false | 2515 | 1543 | 0 | 124 MHz |
| Minimal set with the time PDOs, parallel bus access | "Parallel", true, true, 3 receive and 3 transmit PDOs, time COB-IDs 0F0h and 1F5h | 4058 | 1946 | 0 | 111 MHz |

The longest paths lie in the bit timing logic of the CAN controller and, in the clause 6 slave with the time PDOs, in
the decode of an object access of the SDO server in the object dictionary.
