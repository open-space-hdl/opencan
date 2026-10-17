# OpenCAN Architecture

## 1 Purpose, scope and references

OpenCAN connects a spacecraft unit to a CAN network as specified by ECSS-E-ST-50-15C, the CANbus extension protocol.
The network has a nominal and a redundant bus; one node, the Redundancy Master, defines the active bus with its
heartbeat, and all other nodes follow it. OpenCAN implements the node side of this protocol in hardware: the access
to the two buses, the bus monitoring and reconfiguration of clause 8, the CANopen services of clause 6 that a node
needs (network management, heartbeat, process data, configuration access) and the time distribution of clause 7. A
unit without a processor can join a network of the standard with OpenCAN alone; a unit with a processor uses it to
offload the time-critical parts of the protocol.

The CAN protocol itself (frames, bit stuffing, CRC, arbitration, error signalling, fault confinement, bit timing) is
the CAN 2.0B controller `olo_intf_can` of Open Logic, used once or twice depending on the bus access architecture.

### In scope

The scope below is the proposal of this document. Section 6.1 lists the interpretation questions whose answers fix
it; the traceability matrix (section 10) assigns every clause of the standard to a module or marks it out of scope.

- Data link layer on the nominal and the redundant bus (clauses 5.4 and 5.6) with `olo_intf_can`.
- Both node-internal bus redundancy architectures of clause 8.2 (selective and parallel bus access), selected by a
  generic.
- Bus monitoring and reconfiguration of clause 8.3 for a slave node: start-up on the default bus, heartbeat
  consumption of the Redundancy Master, bus toggling and the update of the default bus.
- CANopen services of clause 6 for a slave node: NMT state machine and module control, boot-up, heartbeat, SYNC
  consumption, process data objects, an SDO server and the object dictionary entries of the communication profile and
  of clause 8.
- Node and COB identifier handling of clause 6.10, including the protection against single point failures.
- The minimal protocol set of clause 9 as a configuration of the same modules.
- Spacecraft elapsed time (SCET) and the time distribution protocols of clause 7 for a time consumer.

### Out of scope

- The physical layer of clauses 5.1 to 5.3 and 5.5 and the connectors of clause 10 (cabling, termination, ISO 11898-2
  or RS-485 transceivers, EMC): they belong to the board. OpenCAN drives a transmit enable per transceiver for the
  RS-485 variant and for the selective bus access architecture.
- Electronic data sheets and device configuration files (clause 6.6) and device profiles (clause 6.7): they describe a
  particular device. The documentation provides the object dictionary of OpenCAN as the basis of a device's EDS.
- Hot and warm bus redundancy and node redundancy, which the standard leaves to the application (clause 4.8.1).
- The Redundancy Master, NMT master, SYNC producer and time producer roles, unless question Q1 decides otherwise.

### Target technology

Vendor-independent VHDL-2008, synthesisable for FPGAs of all vendors. The core runs in one clock domain; the bus
inputs pass the synchronisers of `olo_intf_can`. The bit rates of clause 5.4 (1 Mbit/s and 500, 250, 125 kbit/s) are
set at runtime from the system clock.

### Project

OpenCAN belongs to the Open Space HDL family (`ocan_` prefix, VHDL library `opencan`). It builds on Open Logic
4.7.0-ft.7 (fork open-space-hdl/open-logic-ft, `fault-tolerant` branch) for the CAN controller, FIFOs, RAMs and
synchronisers.

### References

| Ref | Document |
| --- | --- |
| \[ECSS\] | ECSS-E-ST-50-15C, Space engineering, CANbus extension protocol, 1 May 2015 |
| \[CiA301\] | CiA 301 V4.2.0, CANopen application layer and communication profile, CAN in Automation, 2011 |
| \[ISO11898\] | ISO 11898-1:2003, Road vehicles, Controller area network (CAN), Part 1: Data link layer and physical signalling |
| \[Bosch\] | CAN Specification 2.0, Robert Bosch GmbH, 1991 |
| \[CCSDS301\] | CCSDS 301.0-B-4, Time code formats |
| \[OLO\] | Open Logic VHDL library, fork open-space-hdl/open-logic-ft, tag 4.7.0-ft.7 |

### Conventions

Clauses of \[ECSS\] are cited by number and requirement letter (8.3.3e). CANopen objects are cited by their
object dictionary index in hexadecimal (1017h). The rules of the repository are in [conventions](conventions.md).

## 2 ECSS-E-ST-50-15C functional overview

**Communication model (clause 4.5).** A network has one master and up to 126 slave nodes in a strict master/slave
relationship. The master is the CANopen NMT master and the Redundancy Master (clause 8.1).

**Layers.** The physical and data link layers follow ISO 11898 (clause 5) with spacecraft-specific restrictions: the
bit rates, the bit timing (configurable time quanta, sample point and a resynchronization jump width of 1 to min(4,
phase segment 1), synchronisation on recessive-to-dominant edges only) and the indication of the error state and the
error counters to the application (clause 5.6.2). The higher layer is CANopen \[CiA301\] with the applicability of
clause 11: process data objects, the SYNC object, an optional SDO service, network management with the heartbeat
protocol (node guarding is not used), the boot-up service and the NMT state machine. The CANopen TIME object is
replaced by the time distribution of clause 7.

**Redundancy (clause 8).** A node accesses the two buses either through one controller and a selector between two
transceivers (selective bus access, one bus at a time) or through one controller per bus (parallel bus access,
clause 8.2). The Redundancy Master sends its heartbeat on the active bus and switches the bus by moving its heartbeat
to the other one (clause 8.3.3a, b). A slave node starts on the default bus, consumes the master heartbeat and sends
its own heartbeat on the bus it considers active. When the master heartbeat is missing for Ttoggle consumer heartbeat
times, the slave enters Pre-operational, switches to the other bus and looks for an NMT message there; after Ntoggle
switches without success it stays on the default bus. When an NMT message arrives on a bus, that bus is the active one
and becomes the new default (clause 8.3.3e to l). The parameters Bdefault, Ttoggle, Ntoggle and Ctoggle are the object
2000h; the heartbeat times are 1016h and 1017h (clause 8.3.1).

**Time (clause 7).** A device that keeps time uses SCET, an unsegmented CCSDS time code of 32 bits of seconds and up
to 24 bits of sub-seconds, optionally a spacecraft UTC in the CCSDS day segmented code. The time producer sends its
time in the Spacecraft Time PDO; every time consumer sets its local time from it and returns its local time in a
Local Time PDO. The high-resolution protocol couples both values to the last SYNC object, so that the sample is taken
at the SYNC frame (clause 7.2.3).

**Minimal protocol set (clause 9).** For very simple slaves the standard defines a fixed subset: four transmit and
four receive PDOs of the pre-defined connection set with transmission type 254, a hard-coded object dictionary, no
NMT module control, no boot-up message, no emergency object and no time stamp object. The master is the only
initiator of exchanges (unconfirmed commands and telemetry requests).

## 3 Design drivers

- **A complete node without a processor.** Many units on a spacecraft CAN network are simple (sensors, actuators,
  power switches). The protocol of the standard must run in hardware, with a simple data interface to the user logic.
- **Autonomous redundancy management.** The bus selection of clause 8.3 decides within heartbeat times; it must not
  depend on software reaction times.
- **Deterministic time sampling.** The high-resolution time protocol needs the local time sampled at the SYNC frame;
  hardware does this to the resolution of the clock.
- **Integration flexibility.** Clause 6.10 requires that COB-IDs and NODE-IDs can be changed until the end of system
  testing without requalifying the device; clause 8.3.1c requires the redundancy parameters to be programmable through
  SDO.
- **Single point failures.** Clause 6.10d and 6.10k require that no single point failure makes a node accept a false
  COB-ID or NODE-ID.
- **Radiation.** Frame buffers are SECDED protected, synchronisers triplicated, state machines recover from any state.

## 4 Design goals

1. Conformance to every clause of \[ECSS\] in scope, traced to requirements and test cases (section 10).
2. One core for both bus access architectures and for both the full slave and the minimal set, selected by generics.
3. Operation without a processor; an optional processor interface for configuration and status.
4. Bus switching and heartbeat timing exact to one millisecond tick, independent of the load of the user logic.
5. Moderate resource use: one or two CAN controllers, small frame buffers, the object dictionary of the
   communication profile in registers.

## 5 Design principles

- The CAN protocol is `olo_intf_can`; OpenCAN never reimplements a part of it. A change that OpenCAN needs in the
  controller goes into Open Logic first.
- Every block is a two-process state machine with registered outputs; every data path between blocks is a valid/ready
  stream.
- The protocol logic of clauses 6 to 9 is independent of the bus access architecture: the link layer offers one
  frame interface per bus and the active bus as a status.
- Objects of the communication profile live in the core; application objects reach the user logic through one
  object access port, so that the core needs no knowledge of the device.

## 6 Architecture overview

```text
                 +------------------------------------------------------------------+
  Node-ID  ----->| ocan_nmt        NMT state machine, boot-up, heartbeat producer   |
  (protected)    |                 module control, NODE-ID check                    |
                 +---------------------------^--------------------------------------+
                                             |
                 +------------------+  +-----+-----------+  +----------------------+
  PDO data <---->| ocan_pdo         |  | ocan_dispatch   |  | ocan_redundancy      |
  (streams)      | RPDO, TPDO, SYNC |<>| COB-ID filter,  |<>| bus selection,       |
                 +------------------+  | TX arbitration  |  | master heartbeat     |
                 +------------------+  +-----+-----------+  | consumer, toggling   |
  Object   <---->| ocan_od, ocan_sdo|<>------|              +----------+-----------+
  access port    | object dictionary|        |                         | active bus
                 +------------------+  +-----v-------------------------v-----------+
  Time     <---->| ocan_time        |  | ocan_link   selective: 1 x olo_intf_can   |
  (SCET)         | SCET, time PDOs  |  |             + bus selector               |
                 +------------------+  |             parallel: 2 x olo_intf_can   |
                                       +------------+--------------+--------------+
                                                    | bus A        | bus B
                                               transceiver A   transceiver B
```

The block diagram is drawn in draw.io once the interpretation questions are answered.

| Block | Function | Clauses |
| --- | --- | --- |
| `ocan_link` | Access to the nominal and the redundant bus: one controller and a bus selector or two controllers; frame buffers; error state and counters per controller | 5.4, 5.6, 8.2 |
| `ocan_dispatch` | Receive filter by COB-ID to the protocol blocks; transmit arbitration between heartbeat, boot-up, PDOs and SDO replies | 6.10, 11 |
| `ocan_nmt` | NMT slave state machine, module control services, boot-up, heartbeat producer, NODE-ID check | 6.5, 6.10, 9.4.6, 9.4.9 |
| `ocan_redundancy` | Start-up on Bdefault, master heartbeat consumer, bus toggling, Ctoggle, update of Bdefault | 8.3 |
| `ocan_pdo` | Receive and transmit PDOs, transmission types, SYNC consumer | 6.2, 6.3, 6.9, 9.3, 9.4 |
| `ocan_od` | Object dictionary of the communication profile and of clause 8; object access port to the user logic | 6.8, 8.3.1, 9.2, 9.4.10 |
| `ocan_sdo` | SDO server | 6.1, 9.4.8 |
| `ocan_time` | Local SCET, Spacecraft Time PDO consumer, Local Time PDO producer, sample at SYNC | 7 |
| `ocan_core` | Top level, generics and ports | all |

### 6.1 Interpretation questions

Each question names the options, the clauses involved and a recommendation. The answers become the architecture
decisions of this section and fix the scope of section 1.

| ID | Question | Options | Recommendation |
| --- | --- | --- | --- |
| Q1 | Node role | Slave node only; Redundancy Master (NMT master, SYNC and time producer) only; both, selected by a generic | Slave node in phases b and c. The master is usually the platform computer and needs a scheduler for SYNC, time and NMT commands; a master role can follow in a later phase on the same blocks (heartbeat producer on the active bus, bus switch command, clause 8.3.3a, b, f). |
| Q2 | CANopen level | Clause 6 only; clause 9 minimal set only; both, selected by a generic | Both: the minimal set is a strict subset of the clause 6 slave (module control, boot-up and emergency disabled, fixed PDO parameters), so a generic `MinimalSet_g` costs little and covers the simplest units. |
| Q3 | SDO server (clause 6.1, 8.3.1c) | None; expedited only; expedited and segmented; with block transfer | Expedited and segmented, no block transfer. Clause 8.3.1c requires the redundancy parameters to be programmable through SDO for a clause 6 node; all of them fit an expedited transfer, but the SCET objects of clause 7.1.2 have 7 bytes and need the segmented protocol. The SDO server is absent in the minimal set. |
| Q4 | Bus access architecture (clause 8.2) | Selective; parallel; both, selected by a generic | Both. Selective bus access as the default (one controller, the toggling protocol of clause 8.3.3 is made for it); parallel bus access with the controller of the inactive bus in listen-only mode, which also allows a later master role to listen passively on the redundant bus (clause 8.2.2, note 3). |
| Q5 | Time distribution (clause 7) | None; SCET with the time distribution protocol; plus the high-resolution protocol; plus UTC | SCET with both protocols of clause 7.2 for a time consumer: the local SCET counter (32-bit coarse time, fine time width by generic, 0 to 24 bits), the Spacecraft Time PDO sets it, the Local Time PDO returns it, both sampled at the SYNC for the high-resolution protocol. UTC (optional, clause 7.1.1b) in a later phase. |
| Q6 | Application interface | Native ports (PDO data streams, object access port, status); a register interface (AXI4-Lite) for a processor; both | Native ports as the base, so that a unit without a processor works; an AXI4-Lite register bank for configuration and status as an optional wrapper in a later phase. |
| Q7 | PDOs | Number per direction; static or configurable mapping | Up to four receive and four transmit PDOs by generic, with the COB-IDs of the pre-defined connection set as defaults (\[CiA301\] 7.3.3, clause 9.3). Static mapping: the eight data bytes of a PDO pass to and from the user logic, the mapping objects (1600h, 1A00h) are read-only and describe the static mapping (allowed by clause 9.4.10e note and 9.4.5). |
| Q8 | NODE-ID and COB-ID protection (clause 6.10d to k) | NODE-ID from pins without check; from pins with a protection code; from a register | NODE-ID from pins with a protection code (the identifier and its complement), sampled at reset; the node does not communicate until the code is valid (6.10f). COB-IDs default to the pre-defined connection set, change only through SDO in Pre-operational and are held in registers whose single upset the core detects (duplicated with a compare). |
| Q9 | Emergency object (clause 6.4, optional) | Not implemented; implemented with all error codes | Not implemented: the object is optional, clause 11 lists the EMCY service as not required, and if implemented clause 6.4b requires all CANopen error codes. The optional EMCY before a bus switch (clause 8.3.3, note 2) is therefore not sent. |
| Q10 | Source of \[CiA301\] | The detailed protocols (NMT, heartbeat, SDO, PDO, SYNC) are specified in CiA 301 V4.2.0 | The specifications of phase b and c cite \[CiA301\] by section; the document is needed in the work directory before phase b starts. |

### 6.2 Clock and reset

One clock domain. The bus inputs pass the synchronisers of `olo_intf_can` (`SyncTmr_g`). A synchronous reset
corresponds to the power-on or hardware reset of clause 8.3.2a: the node restarts on Bdefault. The NMT services Reset
Node and Reset Communication reset the protocol state as defined by \[CiA301\], not the whole core.

### 6.3 Internal interfaces

- Link to dispatch: one frame stream per direction and per bus (identifier, IDE, RTR, DLC, eight data bytes), the
  active bus, the error state and counters of each controller.
- Dispatch to the protocol blocks: frames filtered by COB-ID (NMT, SYNC, master heartbeat, RPDOs, SDO requests,
  Spacecraft Time PDO) and transmit requests with a fixed priority (heartbeat and boot-up, SDO replies, TPDOs).
- A millisecond tick (`olo_base_strobe_gen`) for the heartbeat producer, the heartbeat consumer and the toggling
  timer.

### 6.4 Bus switching with one controller

With selective bus access the selector moves the controller from one transceiver to the other. The controller is
disabled before the switch and enabled after it (`Cfg_Enable` of `olo_intf_can`): it then integrates on the new bus
after eleven recessive bits and never sees a bus change inside a frame. The error counters are kept, as the
controller keeps them while disabled; clause 5.6.2 only requires them to be readable.

## 7 Building block specifications

The module specifications (`hdl/<module>/docs/specification.md`) hold the requirements with their clause references.
They are written in dependency order once section 6.1 is decided: `ocan_link`, `ocan_dispatch`, `ocan_nmt`,
`ocan_redundancy` (phase b), then `ocan_od`, `ocan_sdo`, `ocan_pdo`, `ocan_time` (phase c) and `ocan_core`.

## 8 Open Logic usage

| Function | Open Logic entity |
| --- | --- |
| CAN 2.0B protocol, bit timing, error confinement | `olo_intf_can` |
| Bit timing constants from a clock frequency and a bit rate | `canBitTiming` of `olo_intf_pkg_can` |
| Frame buffers | `olo_ft_fifo_sync` (SECDED) |
| Millisecond tick | `olo_base_strobe_gen` |
| Transmit arbitration | `olo_base_arb_prio` |

`olo_intf_can` has no acceptance filter by design; the filter by COB-ID is `ocan_dispatch`. No gap in Open Logic is
known at this stage; one found later goes to the fork first.

## 9 Verification architecture

### Framework

VUnit runs the tests, UVVM supplies BFMs, checks and randomisation. GHDL is the default simulator, QuestaSim collects
the code coverage; every test passes in both.

### Rules

- The far end is the CAN network model of `tb/`: a wired-AND model of two buses with independent node models (a
  Redundancy Master with heartbeat, NMT commands, SYNC, Spacecraft Time PDO and an SDO client, and further slave
  nodes). It builds and checks frames at bit level independently of the RTL, so that a protocol error of the core is
  seen on the bus.
- Faults are injected on the buses: a broken or stuck bus, a missing master heartbeat, a master that switches the bus,
  corrupted frames, wrong CANopen requests, invalid NODE-ID codes, upsets through the `ErrInj` ports.
- Every test observes ports and buses only.

## 10 Requirement traceability matrix

Every clause of \[ECSS\] has one owner: a module of OpenCAN, the board ("Out of scope, board"), the device supplier
("Out of scope, device") or "Not implemented" with the reason in section 6.1. "First verified at" names the lowest
verification level at which the clause can be fully checked. The compliance matrix `docs/compliance.md`, generated
from this table, the module specifications and the verification plans by `tools/compliance.py`, lists the
requirements and test cases of every clause; a clause whose owner module has no testbench yet is listed as planned.

| ECSS clause | Title | Owner | Also involved | First verified at |
| --- | --- | --- | --- | --- |
| 5.1.1 to 5.1.3 | Topology, bus length, number of devices | Out of scope, board | - | - |
| 5.2.1, 5.2.2 | Cable, connectors | Out of scope, board | - | - |
| 5.3.1 to 5.3.6 | Transceiver characteristics | Out of scope, board | `ocan_link` | Board |
| 5.4.1, 5.4.2 | Bit rates | `ocan_link` | - | Unit |
| 5.4.3 | Bit timing | `ocan_link` | - | Unit |
| 5.5 | Electromagnetic compatibility | Out of scope, board | - | - |
| 5.6.1 | ISO 11898 compliance of the data link layer | `ocan_link` | - | Unit |
| 5.6.2 | Fault confinement, error state and counters | `ocan_link` | `ocan_core` | Unit |
| 6.1 | Service data objects | `ocan_sdo` | `ocan_od` | Unit |
| 6.2 | Process data objects | `ocan_pdo` | `ocan_dispatch` | Unit |
| 6.3 | Synchronisation object | `ocan_pdo` | `ocan_time` | Unit |
| 6.4 | Emergency object | Not implemented (Q9) | - | - |
| 6.5.1 | Module control services | `ocan_nmt` | - | Unit |
| 6.5.2 | Error control services, heartbeat | `ocan_nmt` | `ocan_redundancy` | Unit |
| 6.5.3 | Bootup service | `ocan_nmt` | - | Unit |
| 6.5.4 | Node state diagram | `ocan_nmt` | - | Unit |
| 6.6 | Electronic data sheets | Out of scope, device | `ocan_od` | - |
| 6.7 | Device and application profiles | Out of scope, device | `ocan_od` | - |
| 6.8 | Object dictionary | `ocan_od` | `ocan_sdo` | Unit |
| 6.9 | Synchronous communications | `ocan_pdo` | - | Unit |
| 6.10 | COB-ID and NODE-ID assignment | `ocan_nmt` | `ocan_od`, `ocan_dispatch` | Unit |
| 7.1.1 | Time code formats | `ocan_time` | - | Unit |
| 7.1.2 | Spacecraft elapsed time objects | `ocan_time` | `ocan_od` | Unit |
| 7.1.3 | Spacecraft UTC objects | Not implemented (Q5) | - | - |
| 7.2.1 | Time distribution, general | `ocan_time` | - | Unit |
| 7.2.2 | Time distribution protocol | `ocan_time` | `ocan_pdo` | Unit |
| 7.2.3 | High-resolution time distribution protocol | `ocan_time` | `ocan_pdo` | Core |
| 8.1 | Redundancy master | Out of scope, master (Q1) | `ocan_redundancy` | Core |
| 8.2.1 to 8.2.3 | Bus redundancy architectures | `ocan_link` | - | Unit |
| 8.3.1 | Bus redundancy management parameters | `ocan_od` | `ocan_redundancy` | Unit |
| 8.3.2 | Start-up procedure | `ocan_redundancy` | `ocan_nmt` | Unit |
| 8.3.3 | Bus monitoring protocol | `ocan_redundancy` | `ocan_nmt`, `ocan_link` | Core |
| 9.1 | COB-ID assignment, minimal set | `ocan_nmt` | `ocan_dispatch` | Unit |
| 9.2 | Object dictionary, minimal set | `ocan_od` | - | Unit |
| 9.3 | Minimal set CANopen objects | `ocan_pdo` | `ocan_od` | Unit |
| 9.4.1 to 9.4.5 | Minimal set protocol, data transmission, PDO mapping | `ocan_pdo` | - | Unit |
| 9.4.6, 9.4.9 | Minimal set network management, heartbeat, no boot-up | `ocan_nmt` | `ocan_redundancy` | Unit |
| 9.4.7 | Minimal set special function objects | `ocan_pdo` | `ocan_nmt` | Unit |
| 9.4.8 | Minimal set communication error object | `ocan_sdo` | - | Unit |
| 9.4.10 | Minimal set authorized objects | `ocan_od` | - | Unit |
| 9.5 | Free COB-ID | `ocan_dispatch` | - | Unit |
| 10.1 to 10.5 | Connectors and pin assignments | Out of scope, board | - | - |
| 11.1 | CANopen applicability matrix | `ocan_core` | all | Core |

## 11 Development plan

| Phase | Content | Exit criterion |
| --- | --- | --- |
| a | This architecture; answers to section 6.1; compliance matrix | Review passed |
| b | `ocan_link`, `ocan_dispatch`, `ocan_nmt`, `ocan_redundancy`: a slave node that joins the network, follows the Redundancy Master and switches the bus | Phase b modules verified, GHDL and QuestaSim |
| c | `ocan_od`, `ocan_sdo`, `ocan_pdo`, `ocan_time`, `ocan_core`: process data, configuration access and time | All modules verified, coverage closed, TRL 3 |
| d | Hardware test on a redundant CAN network with transceivers | TRL 4 |
