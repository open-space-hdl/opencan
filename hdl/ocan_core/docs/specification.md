# ocan_core: Specification

## 1. Overview

`ocan_core` is the top level of OpenCAN: a slave node of ECSS-E-ST-50-15C on a nominal and a redundant bus, built
from the eight blocks of the [architecture](../../../docs/architecture.md) (section 6). It adds the reset
synchroniser, the millisecond tick and the selection of the fault confinement state for the object dictionary, and
connects the blocks; every protocol function is the function of a block and is specified there. It owns clause 11.1,
the applicability of \[CiA301\] (section 2.3).

| Block | Entity | Function |
| --- | --- | --- |
| CO-1 | `olo_base_reset_gen` | Synchronises the release of the asynchronous reset input (triplicated synchroniser) |
| CO-2 | `olo_base_strobe_gen` | Millisecond tick of all blocks |
| CO-3 | `ocan_link`, `ocan_dispatch`, `ocan_nmt`, `ocan_redundancy`, `ocan_od`, `ocan_sdo`, `ocan_pdo`, `ocan_time` | The blocks of the node and their connections |

`ocan_core` runs in one clock domain. The CiA 301 column of the tables names the section of \[CiA301\] that defines
the object or protocol.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| CO-IF-01 | The core shall run in one clock domain. The reset input shall be asynchronous and high-active; the core shall synchronise its release with a triplicated synchroniser, and the synchronised reset shall be the hardware reset of every block. | none | 8.3.2a |
| CO-IF-02 | The core shall have per bus a transmit output, a transmit enable and a receive input of the transceiver, bus A in index 0 and bus B in index 1 (LK-IF). | none | 5.3, 8.2 |
| CO-IF-03 | The core shall take the NODE-ID pins and their complement (NM-ID) and provide the protected NODE-ID with its valid flag. | 7.3.2.2.1 | 6.10d, 6.10f, 6.10k |
| CO-IF-04 | The core shall take the bit timing (prescaler, phase segments, synchronisation jump width) at its ports, used by the controllers while they are enabled, and an enable input; the controllers shall be enabled while the enable input is '1' and the NODE-ID is valid. The bit timing shall change only while the enable input is '0'. The core shall take the recovery inputs of the controllers (LK-IF). | none | 5.4, 6.10d |
| CO-IF-05 | The core shall have the port of the PDO block to the user logic: the SYNC event, the receive PDOs, the transmit PDOs with their requests, status and events (PD-IF-06, PD-IF-07). | 7.2.2 | 6.2a, 9.4.3b |
| CO-IF-06 | The core shall have the application port of the object dictionary to the user logic (OD-AP). | 7.4 | 6.8a |
| CO-IF-07 | The core shall provide the local time (coarse and fine) with its set flag and events, and take the request of the Local Time PDO (TM-IF-04, TM-IF-05). | 7.2.2 | 7.2.2f |
| CO-IF-08 | The core shall provide the status and the events of every block: the NMT state and the reset events, the active bus and the bus selection, the master heartbeat, the error register, the COB-ID compare, the SDO transfer, and per controller the error state, the error counters and the error events. | 7.5.2.2 | 5.6.2, 6.5.1a, 8.3.3 |
| CO-IF-09 | The core shall have the test inputs of the blocks (`ErrInj` of `ocan_od`, `ocan_nmt` and `ocan_link`), without effect while they are 0. | none | 6.10d |

### 2.2 Integration (CO-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| CO-CN-01 | The core shall provide every block with the same one-cycle tick every millisecond, derived from the clock frequency of `ClkFrequency_g`. | none | 6.5.2a, 8.3.3 |
| CO-CN-02 | The core shall connect the blocks as their interface requirements specify (LK-IF, DS-IF, NM-IF, RM-IF, OD-IF, SD-IF, PD-IF, TM-IF), with the active bus of `ocan_redundancy` as the requested bus of `ocan_link` and as the active bus of `ocan_dispatch`. | none | 8.2, 8.3.3d |
| CO-CN-03 | The object dictionary shall take the fault confinement state of the controller of the active bus: with selective bus access the controller, with parallel bus access the controller of the active bus of `ocan_link`. | 7.5.2.2 | 5.6.2, 6.10d |
| CO-CN-04 | With `MinimalSet_g` the core shall have no SDO server (D3). Without the minimal set and without `TimePdos_g` the time block shall serve the local time and its objects without the time PDOs. With `MinimalSet_g` and without `TimePdos_g` the core shall have no time block, and the local time outputs shall be 0. | 7.2.4 | 7.1.2, 9.4.10f |
| CO-CN-05 | Every frame that the core sends shall be a data frame with an 11-bit identifier. | 7.2.2.4.3 | 5.6.1, 11.1 |

### 2.3 Applicability of \[CiA301\] (clause 11.1)

Clause 11.1 states for each section of \[CiA301\] whether it applies. Each requirement below covers the sections with
the same function and the same answer; the CiA 301 column lists every section it covers, and section 5 names the
sections that are for reference only or carry no answer.

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| CO-AP-01 | The core shall have no physical medium attachment: it drives and reads the transceivers through the signals of CO-IF-02. | 5.3 | 5.3, 11.1 |
| CO-AP-02 | The core shall implement the physical signalling and the data link layer of the CAN protocol with `olo_intf_can` in `ocan_link` (LK-PR-01 to LK-PR-04). | 5.4, 6 | 5.4, 5.6.1, 11.1 |
| CO-AP-03 | The values of the objects and of the SDO and PDO frames shall follow the bit sequences, the transfer syntax and the data types of \[CiA301\], with the bytes of a value least significant first, as the blocks specify (SD-PR-01, OD-OB-03, TM-RX-01, TM-TX-01). The general description of the data types is not used. | 7.1.1, 7.1.3.1, 7.1.3.2, 7.1.4, 7.1.5, 7.1.6 | 11.1 |
| CO-AP-04 | The node shall receive and send its PDOs with the write PDO protocol, in the synchronous and event-driven transmission modes of `ocan_pdo` (PD-RX-03, PD-RX-04, PD-TX-02 to PD-TX-04). The event timer is not implemented (PD-TX-06). | 7.2.2, 7.2.2.2, 7.2.2.3 (event or timer), 7.2.2.3 (synchronous), 7.2.2.4.2, 7.2.2.5.1 | 6.2a, 6.9, 11.1 |
| CO-AP-05 | The node shall send no PDO on a remote request and shall read no PDO: remote frames are discarded (DS-RX-02), and every frame sent is a data frame (CO-CN-05). | 7.2.2.3 (remote), 7.2.2.4.3, 7.2.2.5.2 | 11.1 |
| CO-AP-06 | The node shall have no multiplexed PDO: every PDO has the static mapping of D7 (PD-RX-01, PD-TX-01). | 7.2.3 | 11.1 |
| CO-AP-07 | The clause 6 slave shall have one SDO server, without an SDO server parameter object; with `MinimalSet_g` the core shall have no SDO server (CO-CN-04, DS-RX-08). | 7.2.4, 7.2.4.1, 7.2.4.2 | 6.1, 9.4.10f, 11.1 |
| CO-AP-08 | The SDO server shall implement the expedited and the segmented download and upload, with the size indicated in its responses, and the abort transfer (SD-PR-01 to SD-PR-09, SD-DL-01 to SD-DL-04, SD-UL-01, SD-UL-02). | 7.2.4.2.2, 7.2.4.2.3, 7.2.4.2.4, 7.2.4.2.5, 7.2.4.2.6, 7.2.4.2.7, 7.2.4.3, 7.2.4.3.2, 7.2.4.3.3, 7.2.4.3.4, 7.2.4.3.5, 7.2.4.3.6, 7.2.4.3.7, 7.2.4.3.17 | 6.1, 11.1 |
| CO-AP-09 | The SDO server shall implement no block transfer and no block transfer CRC: a request of the block transfer is answered with an abort (SD-PR-03, D3). | 7.2.4.2.8, 7.2.4.2.9, 7.2.4.2.10, 7.2.4.2.11, 7.2.4.2.12, 7.2.4.2.13, 7.2.4.2.14, 7.2.4.2.15, 7.2.4.3.8, 7.2.4.3.9, 7.2.4.3.10, 7.2.4.3.11, 7.2.4.3.12, 7.2.4.3.13, 7.2.4.3.14, 7.2.4.3.15, 7.2.4.3.16 | 6.1, 11.1 |
| CO-AP-10 | The node shall consume the SYNC object (PD-SY-01, PD-SY-02, TM-SY-01, TM-SY-02) and shall not produce it (D1). | 7.2.5, 7.2.5.2, 7.2.5.3 | 6.3, 11.1 |
| CO-AP-11 | The node shall have no time stamp object: the time is the SCET of clause 7 (`ocan_time`). | 7.2.6, 7.2.6.2, 7.2.6.3 | 7.1, 11.1 |
| CO-AP-12 | The node shall send no emergency object (D9). | 7.2.7 | 6.4, 11.1 |
| CO-AP-13 | The clause 6 slave shall execute the node control services start remote node, stop remote node, enter pre-operational, reset node and reset communication with their protocols (NM-SM-02, NM-SM-03); at reset node the core passes the reset application event to the user logic for the reset of the device (NM-SM-06, CO-IF-08). With `MinimalSet_g` no node control service shall be executed (NM-MS-01). | 7.2.8, 7.2.8.2, 7.2.8.2.1.2, 7.2.8.2.1.3, 7.2.8.2.1.4, 7.2.8.2.1.5, 7.2.8.2.1.6, 7.2.8.3, 7.2.8.3.1, 7.2.8.3.1.1, 7.2.8.3.1.2, 7.2.8.3.1.3, 7.2.8.3.1.4, 7.2.8.3.1.5 | 6.5.1, 9.4.6, 11.1 |
| CO-AP-14 | The error control of the node shall be the heartbeat protocol: the node produces its heartbeat (NM-HB-02 to NM-HB-08) and consumes the heartbeat of the master (RM-HB-01 to RM-HB-05). | 7.2.8.2.2, 7.2.8.2.2.3, 7.2.8.3.2, 7.2.8.3.2.2 | 6.5.2, 11.1 |
| CO-AP-15 | The node shall support neither node guarding nor life guarding: a guarding request is a remote frame and is discarded (DS-RX-02). | 7.2.8.2.2.1, 7.2.8.2.2.2, 7.2.8.3.2.1 | 6.5.2, 11.1 |
| CO-AP-16 | The clause 6 slave shall send the boot-up message with its protocol (NM-HB-01); with `MinimalSet_g` no boot-up message shall be sent (NM-MS-02). | 7.2.8.2.3, 7.2.8.3.3 | 6.5.3, 9.4.9.2a, 11.1 |
| CO-AP-17 | The node shall follow the NMT state machine with the states Initialisation (with its sub-states initialising, reset application and reset communication), Pre-operational, Operational and Stopped and their transitions (NM-SM-01 to NM-SM-07); the clause 6 slave enters Pre-operational after the boot-up and Operational at the start command of the master, the minimal set enters Operational by local control (NM-MS-02). The simplified start-up of \[CiA301\] section 7.3.1 is not used. | 7.3, 7.3.1, 7.3.2, 7.3.2.1, 7.3.2.2.1, 7.3.2.2.1 (initialising), 7.3.2.2.1 (reset application), 7.3.2.2.1 (reset communication), 7.3.2.2.2, 7.3.2.2.3, 7.3.2.2.4, 7.3.2.3 | 6.5.4, 9.4.6, 11.1 |
| CO-AP-18 | The services of the node shall be enabled in the NMT states as NM-SM-04 states; the time stamp object and the emergency object do not exist (CO-AP-11, CO-AP-12). | 7.3.2.2.5 | 6.5.4, 11.1 |
| CO-AP-19 | The power-on COB-IDs of the receive and transmit PDOs, SYNC, the SDO and NMT error control shall be those of the generic pre-defined connection set (OD-OB-01, DS-TX-02); the time PDOs are further PDOs with the COB-IDs of the generics (D5). | 7.3.3 | 6.10, 9.3, 11.1 |
| CO-AP-20 | The object dictionary shall hold the objects of the communication profile of the specification of `ocan_od` (table 1), with the records of the PDO communication and mapping parameters and of the identity object as \[CiA301\] specifies them (OD-OB-01 to OD-OB-04). The SDO parameter record is not used, since the node has no SDO server parameter object (CO-AP-07). | 7.4, 7.4.8, 7.4.8.1, 7.4.8.2, 7.4.8.3, 7.4.8.4, 7.5, 7.5.1 | 6.8, 11.1 |

## 3. Error conditions

`ocan_core` detects no error of its own; the blocks report theirs at the ports of CO-IF-08.

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `BusAccess_g` | "Selective" | "Selective", "Parallel" | Bus access architecture of clause 8.2 (D4, `ocan_link`) |
| `SyncStages_g` | 2 | 2 to 4 | Synchroniser stages of the bus inputs and of the reset release |
| `AutoRecover_g` | true | true, false | Recovery from bus off (`ocan_link`) |
| `DominantLimit_g` | 32 | 13 to 1023 | Bit times of a dominant bus until the controller stops sending (`ocan_link`) |
| `MinimalSet_g` | false | true, false | Minimal protocol set of clause 9 (D2) |
| `NumRpdo_g`, `NumTpdo_g` | 4 | 0 to 4; at most 3 with `MinimalSet_g` and `TimePdos_g` (OD-MS-05) | Receive and transmit PDOs (D7) |
| `TimePdos_g` | true | true, false | Spacecraft Time PDO and Local Time PDO (D5) |
| `ClkFrequency_g` | 100000000 | 1000000 to 2147483647 | Clock frequency in Hz: the tick and the local time |
| `FineBits_g` | 24 | 0 to 24 | Bits of sub-seconds of the local time (`ocan_time`) |
| `DeviceType_g` to `SerialNumber_g` | 0 | 32 bits | Device type and identity object (`ocan_od`) |
| `ProducerHbTime_g`, `MasterNodeId_g`, `MasterHbTime_g`, `Bdefault_g`, `Ttoggle_g`, `Ntoggle_g` | as `ocan_od` | as `ocan_od` | Power-on values of the heartbeat and redundancy parameters |
| `RpdoType_g`, `TpdoType_g`, `SctCobId_g`, `SctType_g`, `LtpCobId_g`, `LtpType_g` | as `ocan_od` | as `ocan_od` | Power-on values of the PDO and time PDO parameters |

The generic checks of the blocks apply to the core (`ocan_link`: `BusAccess_g`; `ocan_od`: OD-MS-03, OD-MS-05, the
COB-IDs and the transmission types).

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 11.1 | Each requirement of section 2.3 covers the sections of \[CiA301\] with the same function and the same answer of the clause, with the block that implements them or the reason why they are absent. Sections that are applicable, optional or not applicable are each covered by one requirement. For reference only: 3, 4, 7.1.2, 7.3.4, 7.3.5, 7.4.1, 7.4.7, 7.4.7.2, 7.5.2. Without an answer (headings of their subsections, or sections without a letter): 5, 7, 7.1, 7.1.3, 7.2, 7.2.2.3 (heading), 7.2.2.4, 7.2.2.5, 7.2.8.3.2 (heading), 7.3.2.2, 7.4.2, 7.4.3, 7.4.4, 7.4.5, 7.4.6, 7.4.8.5, 7.4.8.6. None of these requires a function |
| 11.1 (numbering) | The clause cites section 7.2.1 for the PDO; in \[CiA301\] V4.2.0 the PDO is section 7.2.2, which the requirements cite. The subsections of the PDO have the same numbers in both |
| 5.6.2 | The error state and the error counters of each controller are status outputs of the core; the error register of the object dictionary shows the state of the controller of the active bus (CO-CN-03) |
| 8.1 | The core is a slave node: it follows the Redundancy Master and is not one (D1). Clause 8.1 is verified at the core from the side of the slave |
