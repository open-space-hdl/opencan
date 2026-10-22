# ocan_od: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_od: access decoder and rule check (OD-1), protected parameters with the compare and the
repair (OD-2), outputs to the blocks and the error register (OD-3), application port (OD-4)](img/ocan_od_arch.drawio.svg)

`ocan_od` is one entity with a two-process design. An access of `ocan_sdo` is decoded and checked in one clock cycle
and answered in the next; an access to an object of the user logic passes the application port. Every writable
parameter is held in two copies; the outputs to the blocks are derived from the copies in every cycle.

## 2. Access path (OD-1)

### 2.1 Access interface

`ocan_sdo` presents an access with `Acc_Valid`; `Acc_Ready` is '1' while no access of the application port is
outstanding. The data bytes are a value: byte k of the transfer (byte 0 first on the bus) is in bits 8k + 7 to 8k
of `Acc_Data` and `Rsp_Data`, so that an UNSIGNED32 written as 78h, 56h, 34h, 12h is the value 12345678h.

| Signal | Content |
| --- | --- |
| `Acc_Write` | '1' write, '0' read |
| `Acc_Index`, `Acc_Sub` | Index (16 bits) and sub-index (8 bits) |
| `Acc_Data`, `Acc_Len` | Data bytes of a write (64 bits) and their number (1 to 8; 0 not indicated: the size of the data type is taken) |
| `Rsp_Valid` | One-cycle answer |
| `Rsp_Data`, `Rsp_Len` | Data bytes of a read and their number |
| `Rsp_Abort` | Abort code; 0 for a successful access |

### 2.2 Decoder

A combinational function maps index and sub-index to an object of table 1 of the specification, with its data
type, access type and the NMT states in which a write is allowed, for the generics. Indices from 2003h to 9FFFh go
to the application port. An index of table 1 is decoded only when its object exists for `NumRpdo_g`, `NumTpdo_g` and
`TimePdos_g`.

### 2.3 Rule check and the order of the abort codes

The checks of a write run in this order; the first failing check gives the abort code:

| Order | Check | Abort code |
| --- | --- | --- |
| 1 | Object exists | 0602 0000h |
| 2 | Sub-index exists | 0609 0011h |
| 3 | Access type (write of ro or const, read of wo) | 0601 0002h, 0601 0001h |
| 4 | Number of data bytes, when indicated (`Acc_Len` 1 to 8) | 0607 0012h, 0607 0013h |
| 5 | NMT state (OD-WR-03) | 0800 0022h |
| 6 | Value: unsupported COB-ID bits, change while valid, restricted or free identifier, transmission type, 1016h, Bdefault | 0609 0030h |
| 7 | Duplicate identifier | 0604 0043h |

Checks 6 and 7 compare the written COB-ID with the stored one and with the effective identifiers of the other
entries (section 3.1). The restricted identifiers are those of \[CiA301\] section 7.3.5, table 40, and the free
ranges of clause 9.5a, as constants of the entity. A read runs checks 1 to 3.

### 2.4 Answer

The answer of an access to an own object is registered: `Rsp_Valid`, data and abort code in the clock cycle after
`Acc_Valid` and `Acc_Ready`. An accepted write updates both copies at the same clock edge (OD-WR-09). A reset
application or reset communication event in the cycle of an access sets the objects to their power-on values; the
write has no effect, and the access is answered with the abort code 0800 0022h, which `ocan_sdo` does not send
because the reset ends its transfer.

## 3. Protected parameters (OD-2)

### 3.1 COB-IDs

Each of the entries 0 to 10 of the COB-ID table is held in two copies `CobA(e)` and `CobB(e)` of 13 bits:

| Field | Bits | Meaning |
| --- | --- | --- |
| `NotValid` | 1 | Bit 31 of the COB-ID |
| `Rel` | 1 | '1': the identifier is the base of the pre-defined connection set plus the NODE-ID |
| `Id` | 11 | Identifier when `Rel` is '0' |

The effective identifier of an entry is base(e) + `Nmt_NodeId` while `Rel` is '1' and `Id` otherwise; base(e) is
200h, 300h, 400h, 500h for the receive PDOs and 180h, 280h, 380h, 480h for the transmit PDOs. A reset
communication sets `Rel` of these entries, so the identifiers follow the NODE-ID of the new sample (OD-RS-03); an
accepted write stores the written identifier with `Rel` = '0'. The time PDOs and SYNC have `Rel` = '0' with the
power-on values of the generics and 080h. `Cfg_CobId` is built from `CobA`, `Cfg_CobIdCopy` from `CobB`, with the
same `Nmt_NodeId`: the valid flag of entry e is not `NotValid`. Entry 0 (SYNC) is always valid, since bit 31 of 1005h
has no meaning for a consumer; entry 11 (master heartbeat) is 700h + the NODE-ID of 1016h sub-index 01h of the
same copy, valid while that NODE-ID is not 0.

No repair: copies that disagree stay until a write or a reset communication (OD-PR-02). A read returns `CobA`:
bit 31 is `NotValid`, bit 30 is '1' for a transmit PDO (no remote frames) and '0' for a receive PDO, whose reserved
bit 30 is not stored at a write, bits 29 to 11 are 0 and bits 10 to 0 are the effective identifier. For 1005h bit 31
is stored as written and read back. `Rel` has an effect for the entries 2 to 9 only.

### 3.2 Other parameters

| Parameter | Width per copy | Power-on value |
| --- | --- | --- |
| 1016h sub-index 01h: NODE-ID, time | 7 + 16 | `MasterNodeId_g`, `MasterHbTime_g` |
| 1017h | 16 | `ProducerHbTime_g` |
| Transmission types of the receive and transmit PDOs 1 to 4 and of the time PDOs | 8 each | `RpdoType_g`, `TpdoType_g`, `SctType_g`, `LtpType_g` |
| Bdefault | 1 | `Bdefault_g` |
| Ttoggle, Ntoggle | 8 each | `Ttoggle_g`, `Ntoggle_g` |

For each parameter `Ok` is the combinational equality of its copies. The output to the blocks and the value of a
read is copy A while `Ok` is '1' and the power-on value otherwise (OD-PR-03). While `Ok` is '0' the next value of
both copies is the power-on value, `Err_ParamCopy` pulses in that cycle and the latch `ErLatch` (bit 7 of 1001h) is
set. An accepted write of the parameter in the same cycle takes precedence over the repair; the event and the latch
are set all the same.

### 3.3 Test input

`ErrInj_BitFlip` has one bit per protected register bit of both copies; in a cycle with `ErrInj_Valid` = '1' the
selected bits are inverted in the registers, after every other assignment of that cycle. The layout, from bit 0:

| Bits | Copy A | Bits | Copy B |
| --- | --- | --- | --- |
| 0 to 142 | `CobA(0)` to `CobA(10)`, 13 bits each (`Id` in bits 10 to 0, `Rel` bit 11, `NotValid` bit 12) | 279 to 421 | `CobB(0)` to `CobB(10)` |
| 143 to 165 | 1016h sub-index 01h (time in bits 15 to 0, NODE-ID in bits 22 to 16) | 422 to 444 | as copy A |
| 166 to 181 | 1017h | 445 to 460 | as copy A |
| 182 to 261 | Transmission types: receive PDOs 1 to 4, transmit PDOs 1 to 4, Spacecraft Time PDO, Local Time PDO | 461 to 540 | as copy A |
| 262 | Bdefault | 541 | as copy A |
| 263 to 278 | Ttoggle (bits 263 to 270), Ntoggle (bits 271 to 278) | 542 to 557 | as copy A |

The layout is the same for every value of the generics; bits of absent objects have no effect: the entries of
absent objects in the COB-ID table are constant 0 in both copies, and the copies of the transmission types of absent
PDOs are not compared, so that a flip there raises neither `Err_ParamCopy` nor, in `ocan_dispatch`, `Err_CobId`.

## 4. Outputs and updates (OD-3)

| Output | Source |
| --- | --- |
| `Cfg_CobId`, `Cfg_CobIdCopy` | Section 3.1 |
| `Cfg_HbTime` to `ocan_nmt` | 1017h |
| `Cfg_MasterHbTime`, `Cfg_Bdefault`, `Cfg_Ttoggle`, `Cfg_Ntoggle` to `ocan_redundancy` | 1016h sub-index 01h bits 15 to 0, 2000h sub-indices 01h to 03h |
| `Cfg_Ctoggle`, `Cfg_CtoggleValid` to `ocan_redundancy` | Value and one-cycle event of an accepted write of 2000h sub-index 04h |
| `Cfg_SctType`, `Cfg_LtpType`, `Cfg_SetValid`, `Cfg_SetScet` to `ocan_time` | 1404h and 1804h sub-index 02h; value and one-cycle event of an accepted write of 2001h |
| `Cfg_RpdoType`, `Cfg_TpdoType` to `ocan_pdo` | Sub-index 02h of 1400h to 1403h and 1800h to 1803h |
| `Stat_ErrReg` | 1001h |

The update of Bdefault by `ocan_redundancy` (`Upd_Valid`, `Upd_Bdefault`) writes both copies, unless an accepted
write of 2000h sub-index 01h comes in the same cycle (OD-WR-10). The local time (`Stat_Scet`) and Ctoggle
(`Stat_Ctoggle`) of the blocks are read in the cycle of the access.

**Error register.** Bit 4 is '1' while `Link_State` (the fault confinement state of the controller of the active
bus, as at `olo_intf_can`) is error passive or bus off; `ocan_core` selects the controller. Bit 7 is `ErLatch`.
Bit 0 is bit 4 or bit 7 or a COB-ID entry whose copies disagree.

## 5. Application port (OD-4)

| State | `App_ReqValid` | Exit |
| --- | --- | --- |
| `AppIdle_s` | '0' | Access to an index from 2003h to 9FFFh: request registered, to `AppReq_s` |
| `AppReq_s` | '1' | `App_ReqReady` = '1': to `AppWait_s` |
| `AppWait_s` | '0' | `App_RspValid` = '1': answer with `App_RspData`, `App_RspLen`, `App_RspAbort`, to `AppIdle_s` |

`Acc_Ready` is '0' outside `AppIdle_s` (OD-AP-02). `App_RspValid` is taken only in `AppWait_s`; a response in
another state is ignored. `TmoCnt` counts the ticks in `AppReq_s` and `AppWait_s`; at a tick with `TmoCnt` >= 255 the
access ends with 0800 0000h and the event `Err_AppTimeout`, and the port returns to `AppIdle_s`: a request that the
user logic has not taken is withdrawn, a late response is ignored (OD-AP-03). The `when others` branch leads to
`AppIdle_s`.

The default values of the inputs are `App_ReqReady` = '1', `App_RspValid` = '1', `App_RspAbort` = 0602 0000h: a
port left unconnected answers every request with 0602 0000h two cycles after the request (OD-AP-04).

## 6. Resets

| Event | Effect |
| --- | --- |
| `Rst` | Every register to its power-on value, `Rel` set, `ErLatch` cleared, the port in `AppIdle_s` |
| Reset application (`Nmt_ResetApp`) | As reset communication; 2000h sub-indices 01h to 03h kept (OD-RS-02) |
| Reset communication (`Nmt_ResetComm`) | Every parameter of 1000h to 1FFFh to its power-on value, `Rel` set, `ErLatch` cleared; an outstanding request of the application port ends without an answer |

## 7. Minimal set

With `MinimalSet_g` = true, `Acc_Ready` is '0' and `App_ReqValid` is '0'. The parameters are constants of the
generics, except Bdefault, which keeps its two copies and the update of OD-IF-04. The COB-IDs of the receive and
transmit PDOs 1 to 4 have `Rel` = '1' and are valid; the transmission types are 254 (OD-MS-02). An assertion refuses
`TimePdos_g` = true with `NumRpdo_g` or `NumTpdo_g` above 3 (OD-MS-05).

## 8. Ports of ocan_od

| Signal | Direction | Width | Default | Description |
| --- | --- | --- | --- | --- |
| `Clk`, `Rst` | In | 1 | - | Clock and synchronous high-active reset |
| `Tick_Ms` | In | 1 | - | Tick every millisecond |
| `Acc_Valid`, `Acc_Ready`, `Acc_Write`, `Acc_Index`, `Acc_Sub`, `Acc_Data`, `Acc_Len` | In, Out, In, In, In, In, In | 1, 1, 1, 16, 8, 64, 4 | '0' for `Acc_Valid` | Access of `ocan_sdo` |
| `Rsp_Valid`, `Rsp_Data`, `Rsp_Len`, `Rsp_Abort` | Out | 1, 64, 4, 32 | - | Answer |
| `Nmt_State`, `Nmt_NodeId`, `Nmt_ResetApp`, `Nmt_ResetComm` | In | 2, 7, 1, 1 | - | From `ocan_nmt` |
| `Cfg_CobId`, `Cfg_CobIdCopy` | Out | 144 | - | COB-ID table of `ocan_dispatch` |
| `Cfg_HbTime` | Out | 16 | - | Producer heartbeat time |
| `Cfg_MasterHbTime`, `Cfg_Bdefault`, `Cfg_Ttoggle`, `Cfg_Ntoggle` | Out | 16, 1, 8, 8 | - | To `ocan_redundancy` |
| `Cfg_Ctoggle`, `Cfg_CtoggleValid`, `Stat_Ctoggle`, `Upd_Valid`, `Upd_Bdefault` | Out, Out, In, In, In | 8, 1, 8, 1, 1 | - | Ctoggle and the update of Bdefault |
| `Cfg_SctType`, `Cfg_LtpType`, `Cfg_SetValid`, `Cfg_SetScet`, `Stat_Scet` | Out, Out, Out, Out, In | 8, 8, 1, 56, 56 | "0" for `Stat_Scet` | To and from `ocan_time` |
| `Cfg_RpdoType`, `Cfg_TpdoType` | Out | 32, 32 | - | Transmission types of the PDOs 1 to 4, 8 bits each |
| `Link_State` | In | 2 | "00" | Fault confinement state of the controller of the active bus |
| `App_ReqValid`, `App_ReqReady`, `App_ReqWrite`, `App_ReqIndex`, `App_ReqSub`, `App_ReqData`, `App_ReqLen` | Out, In, Out, Out, Out, Out, Out | 1, 1, 1, 16, 8, 64, 4 | '1' for `App_ReqReady` | Request of the application port |
| `App_RspValid`, `App_RspData`, `App_RspLen`, `App_RspAbort` | In | 1, 64, 4, 32 | '1', 0, 0, 0602 0000h | Response of the user logic |
| `Stat_ErrReg` | Out | 8 | - | Error register (1001h) |
| `Err_ParamCopy`, `Err_AppTimeout` | Out | 1 | - | Events |
| `ErrInj_BitFlip`, `ErrInj_Valid` | In | 558, 1 | 0, '0' | **Test inputs** (section 3.3). A system ties them to 0 |

## 9. Configuration parameters

The generics of section 4 of the [specification](specification.md); the 32-bit values (`DeviceType_g`,
`VendorId_g`, `ProductCode_g`, `Revision_g`, `SerialNumber_g`) are `std_logic_vector(31 downto 0)`, the others
`natural` with the ranges of the specification. Assertions refuse at elaboration: `SctCobId_g` or `LtpCobId_g`
that is not 0 and restricted or free, two equal non-zero identifiers among them, and `NumRpdo_g` or `NumTpdo_g`
above 3 with `MinimalSet_g` and `TimePdos_g`.

## 10. Timing and behaviour

| Operation | Duration |
| --- | --- |
| Access to an object of table 1 to `Rsp_Valid` | 1 clock cycle |
| Accepted write to the new value at the outputs | 1 clock cycle |
| Access to an object of the user logic to `App_ReqValid` | 1 clock cycle |
| `App_RspValid` in `AppWait_s` to `Rsp_Valid` | 1 clock cycle |
| Unconnected application port: access to `Rsp_Valid` (0602 0000h) | 3 clock cycles |
| No response of the user logic | 256 ticks to `Rsp_Valid` (0800 0000h) and `Err_AppTimeout` |
| Copies that disagree to the power-on value at the outputs | 0 clock cycles (combinational); repaired copies in the next cycle |
| Reset communication to the power-on values | 1 clock cycle |
