# ocan_od: Specification

## 1. Overview

`ocan_od` is the object dictionary of OpenCAN (ECSS-E-ST-50-15C clauses 6.8, 8.3.1, 9.2 and 9.4.10; D2, D6, D7 and
D8 of the [architecture](../../../docs/architecture.md)). It holds the objects of the communication profile area
that OpenCAN implements and the manufacturer-specific objects 2000h to 2002h, checks every access to them, keeps the
parameters protected against single upsets, supplies them to the other blocks of the core and passes accesses to
the objects of the device to the user logic.

| Block | Entity | Function |
| --- | --- | --- |
| OD-1 | `ocan_od` | Object table and access rules: index and sub-index, data type, access, the abort codes |
| OD-2 | `ocan_od` | Protected parameters: two copies of every writable parameter, the compare and the repair, the COB-ID table |
| OD-3 | `ocan_od` | Parameters to the blocks and updates from them, the error register |
| OD-4 | `ocan_od` | Application port: accesses to the objects of the device |

`ocan_od` runs in one clock domain. The SDO protocol belongs to `ocan_sdo`, which reaches the object dictionary
through the access interface of OD-IF-01. The CiA 301 column of the tables names the section of \[CiA301\] that
defines the object or rule.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-IF-01 | The object dictionary shall take accesses from `ocan_sdo` with a valid/ready handshake, one at a time: read or write, index, sub-index and, for a write, 8 data bytes with the number of the bytes that carry data, 1 to 8, or 0 when the number is not indicated (an expedited download without a size, \[CiA301\] section 7.2.4.3.3). It shall answer each access with the data bytes and their number (read) or with an abort code (0 for a successful write). For an object of table 1 the answer shall come in the clock cycle after the access; for an object of the user logic (OD-AP-01) it shall come in the clock cycle after the response of the user logic, and at the latest 256 ticks and 2 clock cycles after the access (OD-AP-03). | 7.2.4.3 | 6.1a, 8.3.1c |
| OD-IF-02 | The object dictionary shall provide the COB-ID table of `ocan_dispatch` in two copies (DS-IF-03): per entry a valid flag and an 11-bit identifier, for SYNC, the Spacecraft Time PDO, the receive PDOs 1 to 4, the transmit PDOs 1 to 4, the Local Time PDO and the master heartbeat (700h + the NODE-ID of the Redundancy Master). | 7.5.2.5, 7.5.2.19, 7.5.2.35, 7.5.2.37 | 6.10a, 6.10d |
| OD-IF-03 | The object dictionary shall provide the producer heartbeat time to `ocan_nmt`. | 7.5.2.20 | 6.5.2a |
| OD-IF-04 | The object dictionary shall provide to `ocan_redundancy` the consumer heartbeat time of the master, Bdefault, Ttoggle and Ntoggle (RM-IF-02). It shall take the count Ctoggle and the update of Bdefault with its event, and pass a write of Ctoggle as value and event. | 7.5.2.19 | 8.3.1a, 8.3.1c, 8.3.3l |
| OD-IF-05 | The object dictionary shall provide to `ocan_time` the transmission types of the Spacecraft Time PDO and of the Local Time PDO and a write of Local SCET Set as value and event, and take the local time for reads of Local SCET Get (TM-IF-03). | 7.5.2.35, 7.5.2.37 | 7.1.2b, 7.1.2c, 7.1.2d |
| OD-IF-06 | The object dictionary shall provide the transmission types of the receive PDOs 1 to 4 and of the transmit PDOs 1 to 4 to `ocan_pdo`. | 7.5.2.35, 7.5.2.37 | 6.2a, 9.4.2, 9.4.4 |
| OD-IF-07 | The object dictionary shall take from `ocan_nmt` the NMT state, the NODE-ID with its valid flag and the events of the reset application and reset communication sub-states (NM-IF-07). | 7.3.2.2.1 | 6.10a, 6.10f |
| OD-IF-08 | The object dictionary shall take the fault confinement state of the controller of the active bus (error active, error passive, bus off) for the error register. | 7.5.2.2 | 5.6.2a |
| OD-IF-09 | The object dictionary shall have an application port to the user logic (OD-4): a request with a valid/ready handshake (read or write, index, sub-index, 1 to 8 data bytes with their number for a write) and a response with a valid flag (data bytes and their number for a read, abort code). | 7.2.4.3 | 6.8a |
| OD-IF-10 | The object dictionary shall provide the error register as a status output and events for parameter copies that disagree (OD-PR-02) and for a request of the application port without a response (OD-AP-03). | 7.5.2.2 | 6.10d |
| OD-IF-11 | The object dictionary shall take a one-cycle tick every millisecond, the tick of `ocan_nmt`, `ocan_redundancy` and `ocan_time`. | none | none |
| OD-IF-12 | The object dictionary shall have test inputs, inactive by default, that invert selected bits of the copies of its protected parameters in a clock cycle (OD-PR-04). | none | 6.10d |

### 2.2 Objects (OD-1)

Table 1 lists the objects of the clause 6 slave (`MinimalSet_g` = false). The column "Power-on value" is the value
after a hardware reset and after the resets of OD-RS-02 and OD-RS-03; NODE-ID is the NODE-ID sampled by `ocan_nmt`.
The receive PDOs n = 1 to `NumRpdo_g` use the indices 1400h + n - 1 and 1600h + n - 1, the transmit PDOs n = 1 to
`NumTpdo_g` the indices 1800h + n - 1 and 1A00h + n - 1. The rows of 1404h, 1604h, 1804h and 1A04h exist with
`TimePdos_g` = true.

| Index | Sub | Object | Data type | Access | Power-on value |
| --- | --- | --- | --- | --- | --- |
| 1000h | 00h | Device type | UNSIGNED32 | ro | `DeviceType_g` |
| 1001h | 00h | Error register | UNSIGNED8 | ro | OD-ER-01 |
| 1005h | 00h | COB-ID SYNC | UNSIGNED32 | rw | 0000 0080h |
| 1016h | 00h | Consumer heartbeat time, highest sub-index | UNSIGNED8 | const | 01h |
| 1016h | 01h | Consumer heartbeat time of the Redundancy Master: NODE-ID in bits 23 to 16, time in ms in bits 15 to 0 | UNSIGNED32 | rw | `MasterNodeId_g`, `MasterHbTime_g` |
| 1017h | 00h | Producer heartbeat time in ms | UNSIGNED16 | rw | `ProducerHbTime_g` |
| 1018h | 00h | Identity, highest sub-index | UNSIGNED8 | const | 04h |
| 1018h | 01h to 04h | Vendor-ID, product code, revision number, serial number | UNSIGNED32 | ro | `VendorId_g`, `ProductCode_g`, `Revision_g`, `SerialNumber_g` |
| 1400h to 1403h | 00h | Receive PDO communication, highest sub-index | UNSIGNED8 | const | 02h |
| 1400h to 1403h | 01h | COB-ID of receive PDO n | UNSIGNED32 | rw | 100h x (n + 1) + NODE-ID |
| 1400h to 1403h | 02h | Transmission type | UNSIGNED8 | rw | `RpdoType_g` |
| 1404h | 00h to 02h | Spacecraft Time PDO communication, as 1400h | UNSIGNED8, UNSIGNED32, UNSIGNED8 | const, rw, rw | 02h, `SctCobId_g`, `SctType_g` |
| 1600h to 1603h | 00h | Receive PDO mapping, number of mapped objects | UNSIGNED8 | const | 08h |
| 1600h to 1603h | 01h to 08h | Mapped object k: 2100h + n - 1, sub-index k, 8 bits | UNSIGNED32 | const | (2100h + n - 1) x 10000h + k x 100h + 08h |
| 1604h | 00h, 01h | Spacecraft Time PDO mapping: one object, 2001h, sub-index 00h, 56 bits | UNSIGNED8, UNSIGNED32 | const | 01h, 2001 0038h |
| 1800h to 1803h | 00h to 02h | Transmit PDO communication, as 1400h | UNSIGNED8, UNSIGNED32, UNSIGNED8 | const, rw, rw | 02h, 100h x n + 80h + NODE-ID, `TpdoType_g` |
| 1804h | 00h to 02h | Local Time PDO communication, as 1400h | UNSIGNED8, UNSIGNED32, UNSIGNED8 | const, rw, rw | 02h, `LtpCobId_g`, `LtpType_g` |
| 1A00h to 1A03h | 00h to 08h | Transmit PDO mapping: 2200h + n - 1, sub-indices 1 to 8, 8 bits each | UNSIGNED8, UNSIGNED32 | const | 08h, (2200h + n - 1) x 10000h + k x 100h + 08h |
| 1A04h | 00h, 01h | Local Time PDO mapping: one object, 2002h, sub-index 00h, 56 bits | UNSIGNED8, UNSIGNED32 | const | 01h, 2002 0038h |
| 2000h | 00h | Bus redundancy, highest sub-index | UNSIGNED8 | const | 04h |
| 2000h | 01h | Bdefault: 0 bus A, 1 bus B | UNSIGNED8 | rw | `Bdefault_g` |
| 2000h | 02h | Ttoggle | UNSIGNED8 | rw | `Ttoggle_g` |
| 2000h | 03h | Ntoggle | UNSIGNED8 | rw | `Ntoggle_g` |
| 2000h | 04h | Ctoggle | UNSIGNED8 | rw | Count of `ocan_redundancy` |
| 2001h | 00h | Local SCET Set: fine time in bytes 1 to 3, coarse time in bytes 4 to 7 | UNSIGNED56 | wo | - |
| 2002h | 00h | Local SCET Get, as 2001h | UNSIGNED56 | ro | Local time of `ocan_time` |

The objects 2100h to 2103h and 2200h to 2203h that the mapping objects name hold the data bytes of the receive and
transmit PDOs; they belong to the user logic (D7) and are reached through the application port (OD-AP-01).

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-OB-01 | The object dictionary shall implement the objects of table 1 with their data types, access types and power-on values, for the generics `NumRpdo_g`, `NumTpdo_g` and `TimePdos_g`. | 7.4.3, 7.4.5, 7.5.2 | 6.8a, 7.1.2b, 8.3.1a |
| OD-OB-02 | An access to an index from 1000h to 1FFFh or from 2000h to 2002h that is not in table 1 shall end with abort code 0602 0000h (object does not exist); an access to an existing index with a sub-index that is not in table 1 with 0609 0011h (sub-index does not exist). An access to an index from 0000h to 0FFFh or from A000h to FFFFh shall end with 0602 0000h. | 7.2.4.3.17 | 6.8a, 11.1 |
| OD-OB-03 | A read shall return the value with the number of bytes of the data type of the object (UNSIGNED8 1, UNSIGNED16 2, UNSIGNED32 4, UNSIGNED56 7), least significant byte first. | 7.1.6, 7.4.7 | 7.1.2e, 7.1.2f |
| OD-OB-04 | A read of 2002h shall return the local time of `ocan_time` in the clock cycle of the access, a read of 2000h sub-index 04h the count Ctoggle of `ocan_redundancy`, a read of 1001h the error register of OD-ER-01. | 7.5.2.2 | 7.1.2d, 8.3.1a |

### 2.3 Write rules (OD-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-WR-01 | A write of an object with the access type ro or const shall end with 0601 0002h (attempt to write a read-only object), a read of 2001h with 0601 0001h (attempt to read a write-only object). | 7.2.4.3.17, 7.4.5 | 6.8a |
| OD-WR-02 | A write with more data bytes than the data type of the object shall end with 0607 0012h, one with fewer bytes with 0607 0013h. A write whose number of bytes is not indicated (0) shall take as many bytes as the data type of the object has, without this check. | 7.2.4.3.3, 7.2.4.3.17 | 6.8a |
| OD-WR-03 | The COB-IDs (1005h, sub-index 01h of 1400h to 1404h and 1800h to 1804h) and the transmission types (sub-index 02h of the same objects) shall be writable in Pre-operational only; a write in another NMT state shall end with 0800 0022h (data cannot be stored because of the device state). 1016h sub-index 01h, 1017h, 2000h sub-indices 01h to 04h and 2001h shall be writable in Pre-operational and Operational. | 7.3.2.2.2, 7.3.2.2.3 | 6.10c, 8.3.1c |
| OD-WR-04 | Bits 0 to 29 of the COB-ID of a PDO shall change only while bit 31 of the stored COB-ID is 1 (the PDO is not valid); a write that changes them while bit 31 is 0 shall end with 0609 0030h (invalid value). A write in which bit 30 of the COB-ID of a transmit PDO is 0 (remote frames allowed), bit 29 of any COB-ID is 1 (29-bit identifier) or bit 30 of 1005h is 1 (SYNC producer) shall end with 0609 0030h. Bits 28 to 11 shall be 0. | 7.5.2.5, 7.5.2.35, 7.5.2.37 | 5.6.1a, 11.1 |
| OD-WR-05 | A write that leaves a COB-ID valid with a restricted identifier (\[CiA301\] section 7.3.5, table 40) or with an identifier of the free ranges of clause 9.5a shall end with 0609 0030h. A write that leaves a COB-ID valid with the identifier of another valid COB-ID of the node (OD-IF-02 entries 0 to 10) shall end with 0604 0043h (general parameter incompatibility). | 7.3.5 | 6.10b, 6.10l, 9.5a |
| OD-WR-06 | A transmission type other than 0 to 240, 254 and 255 shall be refused with 0609 0030h. | 7.5.2.35, 7.5.2.37 | 9.4.2, 9.4.4, 11.1 |
| OD-WR-07 | A write of 1016h sub-index 01h with bits 31 to 24 not 0 or with a NODE-ID above 127 shall end with 0609 0030h. A NODE-ID of 0 or a time of 0 is taken and disables the master heartbeat consumer: the entry of the master heartbeat in the COB-ID table is not valid while the NODE-ID is 0. | 7.5.2.19 | 6.5.2b, 8.3.1a |
| OD-WR-08 | A write of 2000h sub-index 01h with a value above 1 shall end with 0609 0030h. | none | 8.3.1a |
| OD-WR-09 | A write that ends with an abort code shall not change any object. A write that is accepted shall change the object from the clock cycle after the access. | 7.2.4.3.17 | 6.8a |
| OD-WR-10 | When a write of the access interface and an update by a block (Bdefault by `ocan_redundancy`, OD-IF-04) change the same object in the same clock cycle, the write shall take effect. A reset application or reset communication event in the cycle of an access shall take effect, and the access shall have no effect on the objects. | none | 8.3.3l |

### 2.4 Protected parameters (OD-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-PR-01 | Every writable parameter of table 1 except 2001h and Ctoggle shall be held in two copies. An accepted write and a repair shall write both copies. | none | 6.10d |
| OD-PR-02 | COB-IDs: the two copies of each entry shall be the two copies of the COB-ID table (OD-IF-02), so that `ocan_dispatch` uses the object only while they agree (DS-CP-01). Copies that disagree shall stay as they are until the next accepted write of that object or the next reset communication; a read returns the first copy. For the write rule of OD-WR-04 the PDO is valid only while bit 31 is 0 in both copies. | 7.5.2.35, 7.5.2.37 | 6.10d, 6.10l |
| OD-PR-03 | Other parameters (1016h sub-index 01h, 1017h, the transmission types, 2000h sub-indices 01h to 03h): while the copies of a parameter disagree, the parameter shall have its power-on value at the outputs to the blocks and for a read. Copies that disagree shall raise the copy event (OD-IF-10) and be set to the power-on value in the next clock cycle. | none | 6.10d |
| OD-PR-04 | The test inputs (OD-IF-12) shall select bits of both copies of every protected parameter and invert the selected bits in the registers in a cycle in which they are active. A system ties them inactive. | none | 6.10d |

### 2.5 Error register (OD-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-ER-01 | Bit 4 (communication error) of 1001h shall be 1 while the controller of the active bus is error passive or bus off. Bit 7 (manufacturer-specific) shall be set by a copy event of OD-PR-03 and held until the next reset communication. Bit 0 (generic error) shall be 1 while bit 4 or bit 7 is 1 or the copies of a COB-ID entry disagree. Bits 1, 2, 3, 5 and 6 shall be 0. | 7.5.2.2 | 5.6.2a, 6.10d |

### 2.6 Resets (OD-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-RS-01 | After a hardware reset every object shall have its power-on value. | 7.3.2.2.1 | 8.3.2a |
| OD-RS-02 | The reset application event shall set the objects of 1000h to 1FFFh to their power-on values. Object 2000h shall keep its values: reset node and reset communication keep the active bus and Ctoggle (RM-SL-08; section 2.6 of the specification of `ocan_nmt`). | 7.3.2.2.1 | 8.3.2a, 11.1 |
| OD-RS-03 | The reset communication event shall set the objects of 1000h to 1FFFh to their power-on values and clear bit 7 of 1001h. The COB-IDs of table 1 that depend on the NODE-ID shall use the NODE-ID of the sample of that reset communication (NM-ID-01). | 7.3.2.2.1 | 6.10a, 6.10j |

### 2.7 Application port (OD-4)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-AP-01 | An access to an index from 2003h to 9FFFh shall be passed to the user logic as a request of the application port; its response (data bytes and their number, or the abort code) is the answer of the access. | 7.4.2 | 6.8a |
| OD-AP-02 | At most one request of the application port shall be outstanding. A response of the user logic while no request is outstanding shall be ignored. | none | none |
| OD-AP-03 | A request without a response within 256 ticks shall end the access with 0800 0000h (general error) and raise the event of OD-IF-10. A later response to it shall be ignored. | 7.2.4.3.17 | none |
| OD-AP-04 | With the inputs of the application port at their default values the access shall end with 0602 0000h in the clock cycle after the request, so that a system without objects of the device leaves the port unconnected. | 7.2.4.3.17 | 6.8a |

### 2.8 Minimal set (OD-MS)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| OD-MS-01 | With `MinimalSet_g` = true the object dictionary shall take no access and make no request of the application port: the node has no SDO server (D3), and its object dictionary is fixed. | none | 6.8a, 9.2a, 9.4.10e, 9.4.10f |
| OD-MS-02 | With `MinimalSet_g` = true the parameters shall have these values: the COB-IDs of the receive and transmit PDOs 1 to 4 those of table 1, valid, with the transmission type 254 (Tables 9-3 to 9-6); the COB-ID of SYNC 0000 0080h (Tables 9-7 and 9-8); the producer heartbeat time, the consumer heartbeat time of the master, Bdefault, Ttoggle and Ntoggle the power-on values of the generics; Ctoggle and the update of Bdefault as in OD-IF-04. | 7.5.2.35, 7.5.2.37 | 8.3.2a, 8.3.3l, 9.3a, 9.4.2, 9.4.4, 9.4.7.3 |
| OD-MS-03 | With `MinimalSet_g` = true and `TimePdos_g` = true the COB-IDs and the transmission types of the Spacecraft Time PDO and of the Local Time PDO shall be the values of the generics. No object 1404h, 1604h, 1804h, 1A04h or 2000h exists. | none | 7.1.2a, 9.2a, 9.4.10b, 9.4.10c |
| OD-MS-04 | With `MinimalSet_g` = true the error register (OD-ER-01) shall be the status output; Bdefault shall be held in two copies (OD-PR-03). | 7.5.2.2 | 6.10d |
| OD-MS-05 | With `MinimalSet_g` = true and `TimePdos_g` = true, `NumRpdo_g` and `NumTpdo_g` shall be at most 3, refused otherwise at elaboration, so that the node has at most four receive and four transmit PDOs (note to clause 9.3a; interpretation of the specification of `ocan_time`). | none | 9.3a |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Object or sub-index that does not exist | OD-1 | 0602 0000h or 0609 0011h |
| Write of a read-only object, read of 2001h | OD-1 | 0601 0002h, 0601 0001h |
| Data bytes do not match the data type | OD-1 | 0607 0012h or 0607 0013h |
| COB-ID or transmission type written outside Pre-operational | OD-1 | 0800 0022h |
| COB-ID change while the PDO is valid, unsupported bits, restricted or free identifier, invalid value | OD-1 | 0609 0030h |
| Valid COB-ID equal to another valid COB-ID of the node | OD-1 | 0604 0043h |
| Copies of a COB-ID disagree (upset) | OD-2 | Object unused by `ocan_dispatch` until the next write or reset communication; bit 0 of 1001h |
| Copies of another parameter disagree (upset) | OD-2 | Power-on value, event, bit 7 and bit 0 of 1001h until the next reset communication |
| Controller of the active bus error passive or bus off | OD-3 | Bits 4 and 0 of 1001h |
| No response of the user logic within 256 ticks | OD-4 | 0800 0000h, event; a later response is ignored |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `MinimalSet_g` | false | true, false | Minimal set of clause 9 (D2) |
| `NumRpdo_g`, `NumTpdo_g` | 4 | 0 to 4; at most 3 with `MinimalSet_g` and `TimePdos_g` (OD-MS-05) | Receive and transmit PDOs (D7) |
| `TimePdos_g` | true | true, false | Spacecraft Time PDO and Local Time PDO (D5) |
| `DeviceType_g` | 0 | 32 bits | Value of 1000h |
| `VendorId_g`, `ProductCode_g`, `Revision_g`, `SerialNumber_g` | 0 | 32 bits | Values of 1018h |
| `ProducerHbTime_g` | 1000 | 0 to 65535 | Producer heartbeat time in ms |
| `MasterNodeId_g` | 1 | 0 to 127 | NODE-ID of the Redundancy Master |
| `MasterHbTime_g` | 1500 | 0 to 65535 | Consumer heartbeat time of the master in ms |
| `Bdefault_g` | 0 | 0, 1 | Bdefault |
| `Ttoggle_g`, `Ntoggle_g` | 1, 3 | 0 to 255 | Ttoggle and Ntoggle (clause 8.3.1) |
| `RpdoType_g`, `TpdoType_g` | 254 | 0 to 240, 254, 255; other values refused at elaboration | Transmission types of the receive and transmit PDOs 1 to 4 |
| `SctCobId_g`, `LtpCobId_g` | 0 | 0 to 2047 | Identifiers of the Spacecraft Time PDO and of the Local Time PDO; 0 means not valid |
| `SctType_g`, `LtpType_g` | 254 | 0 to 240, 254, 255; other values refused at elaboration | Transmission types of the Spacecraft Time PDO and of the Local Time PDO |

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 6.8a, 11.1 | The applicability matrix makes the detailed object definitions of \[CiA301\] section 7.5.2 a reference and the object dictionary mission dependent: OpenCAN implements the objects that its services use (table 1) and passes the objects of the device to the user logic |
| 6.10b, 6.10l, 9.5a | The standard names no abort code for a restricted, free or duplicate identifier. OpenCAN answers 0609 0030h (invalid value) for a restricted or free identifier and 0604 0043h (general parameter incompatibility) for a duplicate |
| 6.10c, 6.10n | The delivery defaults of the COB-IDs of the receive and transmit PDOs 1 to 4 are those of the pre-defined connection set; other values are written through SDO in Pre-operational. The time PDOs have no identifier in the pre-defined connection set; their defaults are generics |
| 6.10d, 6.10k | The standard leaves the protection mechanism open. OpenCAN holds every writable parameter in two copies: a COB-ID whose copies disagree is not used (DS-CP-01), any other parameter falls back to its power-on value, and the error register records the fall-back until the next reset communication, so that the master can configure the node again |
| 6.10g | The maintenance mode of the NODE-ID is the protected NODE-ID pins of `ocan_nmt` (D8); the NODE-ID is not an object of `ocan_od` |
| 7.1.2b | The standard assigns no index to Local SCET Set and Local SCET Get: 2001h and 2002h, next to the redundancy object 2000h (TM-IF-03). Local SCET Set is write-only; its value is the local time of `ocan_time` from the next cycle on |
| 8.3.1, Table 8-1 | The table lists the consumer heartbeat time as two 16-bit values. OpenCAN uses the layout of \[CiA301\] section 7.5.2.19: NODE-ID in bits 23 to 16, time in bits 15 to 0, bits 31 to 24 reserved |
| 8.3.1a | The standard gives no encoding of Bdefault: 0 is bus A, 1 is bus B (ocan_redundancy, section 5). Ttoggle = 0 counts as 1 and Ntoggle = 0 gives no toggle, as the specification of `ocan_redundancy` states |
| 8.3.3l, 7.3.2.2.1 of \[CiA301\] | Object 2000h lies in the manufacturer-specific area but keeps its values over the NMT resets (OD-RS-02); a hardware reset restores the configured Bdefault. Storing an updated Bdefault in non-volatile memory is a task of the integrator |
| 9.4.7.3, \[CiA301\] 7.5.2.5 | OpenCAN is a SYNC consumer (D1): bit 30 of 1005h is 0 and a write with bit 30 = 1 is refused; bit 31 has no meaning for a consumer and is stored as written |
| 9.4.2, 9.4.4, Tables 9-3 to 9-6 | Table 9-5 numbers the transmit PDO communication objects from 1801h while its defaults and Table 9-12 use 1800h to 1803h: OpenCAN uses 1800h to 1803h. The highest sub-index range 2 to 5 of Tables 9-4 and 9-6 is implemented as 2, since the inhibit time and the event timer are not used (9.4.1d, 9.4.4b) |
| 11.1 | Remote frames are not used: the remote transmission types 252 and 253 and bit 30 = 0 of a transmit PDO COB-ID are refused (OD-WR-04, OD-WR-06) |
| \[CiA301\] 7.4.8, 7.5.2.36, 7.5.2.38 | The mapping is static (D7): the mapping objects are const and describe the eight data bytes of a PDO as eight UNSIGNED8 objects of the user logic |
| \[CiA301\] 7.5.2.2 | Without the emergency object (D9) the error register is read through SDO only. Bit 7 is manufacturer-specific and records a parameter fall-back of OD-PR-03 |
| \[CiA301\] 7.5.2.10, 7.5.2.11 | Storing and restoring parameters (1010h, 1011h) is not implemented; the power-on values are generics |
| 9.3a, 7.1.1a, 7.1.2a, 7.2.1a | A minimal-set node that keeps time includes both time PDOs (interpretation of the specification of `ocan_time`). Their parameters are generics, not objects, so Table 9-12 and clause 9.4.10c hold: no object outside the authorised indices exists. OD-MS-05 keeps the node within the four receive and four transmit PDOs of the note to clause 9.3a |
| 9.2a (note), 9.4.10e | The object dictionary of the minimal set is fixed: the values of OD-MS-02 and OD-MS-03 are set by the generics and by the NODE-ID, and no object is reachable without an SDO server |
