# ocan_redundancy: Specification

## 1. Overview

`ocan_redundancy` implements the bus monitoring and reconfiguration of a slave node (ECSS-E-ST-50-15C clause 8.3).
It starts the node on the default bus, consumes the heartbeat of the Redundancy Master on the active bus, runs the
bus selection process with the toggling mechanism when that heartbeat is missing, and updates the default bus when an
active bus is found. It drives the requested active bus of `ocan_link`, tells `ocan_dispatch` which bus is active and
whether a bus selection is in progress (architecture section 6.5), and asks `ocan_nmt` to enter Pre-operational before
a bus switch (clause 8.3.3e).

| Block | Entity | Function |
| --- | --- | --- |
| RM-1 | `ocan_redundancy` | Master heartbeat consumer: timer of the active bus, presence per bus |
| RM-2 | `ocan_redundancy` | Bus selection process: start-up on Bdefault, toggling, Ctoggle, end of the process and update of Bdefault |

`ocan_redundancy` runs in one clock domain and is timed by the millisecond tick. The parameters Bdefault, Ttoggle,
Ntoggle and Ctoggle are the object 2000h, the consumer heartbeat time of the master is sub-index 1 of object 1016h
(clause 8.3.1, Table 8-1); they live in `ocan_od`. The CiA 301 column of the tables names the section of \[CiA301\]
that defines the object or protocol.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| RM-IF-01 | The redundancy block shall take from `ocan_dispatch`, per bus, the NMT messages and the master heartbeats with their DLC and state byte as one-cycle events (DS-IF-05). | 7.2.8.3.2.2 | 8.3.3c, 8.3.3g |
| RM-IF-02 | The redundancy block shall take from `ocan_od` the consumer heartbeat time of the master (16 bits, in milliseconds), Bdefault, Ttoggle and Ntoggle. It shall provide Ctoggle and the updated Bdefault with an update event, and take a write of Ctoggle. | 7.5.2.19 | 8.3.1a, 8.3.1c |
| RM-IF-03 | The redundancy block shall drive the requested active bus of `ocan_link` and take the active bus and the busy indication of the link (LK-IF-05, LK-IF-06). | none | 8.2.3a, 8.3.2a |
| RM-IF-04 | The redundancy block shall pass to `ocan_dispatch` the active bus reported by the link and the state of the bus selection process (DS-IF-01). | none | 8.3.3d, 8.3.3g |
| RM-IF-05 | The redundancy block shall take the NMT state of `ocan_nmt`, and pass to it a one-cycle request to enter Pre-operational, a one-cycle event at the end of every bus switch and the state of the bus selection process. | 7.3.2 | 8.3.3e, 8.3.3h |
| RM-IF-06 | The redundancy block shall take a one-cycle tick every millisecond. | 7.5.2.19 | 8.3.3e |
| RM-IF-07 | The redundancy block shall provide as status the state of the bus selection process, Ctoggle, the state byte of the last master heartbeat and, per bus, whether a master heartbeat arrived within the last consumer heartbeat time. It shall provide events for a missing master heartbeat, for the end of the toggling without an active bus, and for a master heartbeat with a DLC other than 1. | 7.2.8.2.2.3 | 8.3.3c, 8.3.3e, 8.3.3j |
| RM-IF-08 | The redundancy block shall take an event of each bus in every clock cycle, also events of both buses in the same cycle, and complete its processing of each event within the minimum frame time of 46 bit times at 1 Mbit/s (D11). | none | 8.3.3g |

### 2.2 Master heartbeat consumer (RM-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| RM-HB-01 | A master heartbeat shall be an event of RM-IF-01 with DLC 1. An event with another DLC is no heartbeat: it shall be ignored and reported as an error event. Every value of the state byte shall be accepted. | 7.2.8.3.2.2 | 6.5.2b |
| RM-HB-02 | Outside the bus selection process the node shall measure the time since the last master heartbeat on the active bus, starting at the end of the bus selection process. When it reaches Ttoggle consumer heartbeat times, the master heartbeat is missing: the redundancy block shall raise the missing heartbeat event and start the bus selection process (RM-SL-02). | 7.5.2.19 | 6.5.2b, 8.3.3c, 8.3.3e |
| RM-HB-03 | With a consumer heartbeat time of 0 the master heartbeat shall not be monitored and no toggling shall take place: the node stays on its bus, and a bus selection process ends only by RM-SL-05 or RM-SL-06. | 7.5.2.19 | 8.3.1a |
| RM-HB-04 | Ttoggle = 0 shall act as Ttoggle = 1. A change of the consumer heartbeat time or of Ttoggle shall restart the running timer. | none | 8.3.1a |
| RM-HB-05 | Per bus, the presence status shall be set by a master heartbeat on that bus and cleared when no master heartbeat arrived on it for one consumer heartbeat time. With a consumer heartbeat time of 0 it shall stay cleared. | 7.2.8.2.2.3 | 8.3.3c |

### 2.3 Bus selection process (RM-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| RM-SL-01 | After a hardware reset the requested active bus shall be Bdefault: 0 is bus A (nominal), 1 is bus B (redundant). When `ocan_nmt` enters Pre-operational for the first time after the reset, the bus selection process shall start on this bus without a switch, with Ctoggle = 0. If `ocan_nmt` leaves the Initialisation to Operational or Stopped instead, which happens only after an upset, the master heartbeat monitoring of RM-HB-02 shall start at once. | 7.3.2.2.1 | 8.3.2a, 8.3.2b |
| RM-SL-02 | At a missing master heartbeat the redundancy block shall request Pre-operational from `ocan_nmt`, start the bus selection process with Ctoggle = 0, and switch to the other bus as the first toggle (RM-SL-03) once the NMT state is Pre-operational. | none | 8.3.3e |
| RM-SL-03 | A toggle shall request the other bus from `ocan_link`, increment Ctoggle and restart the toggling timer. The toggle event to `ocan_nmt` shall be issued when the link reports the new active bus, so that the node starts its heartbeat on the new bus (NM-HB-05). A toggle shall be made only while the NMT state is Pre-operational; one that falls due in another state shall wait for Pre-operational. While it waits and the NMT state is Operational or Stopped, the redundancy block shall request Pre-operational again at every expiry of the timer (RM-SL-04). | none | 8.3.3e, 8.3.3h, 8.3.3i |
| RM-SL-04 | During the bus selection process, Ttoggle consumer heartbeat times after the start of the process or after the last toggle, when no message has ended the process (RM-SL-05, RM-SL-06), the redundancy block shall toggle while Ctoggle is less than Ntoggle. When Ctoggle has reached Ntoggle it shall stop toggling, stay on its bus, raise the event for the end of the toggling without an active bus, and keep the process running. With Ntoggle = 0 no toggle takes place, also not the first one of RM-SL-02. | none | 8.3.3h, 8.3.3i, 8.3.3j |
| RM-SL-05 | An NMT message or a master heartbeat on the active bus during the bus selection process shall end it: the active bus is the bus found, Bdefault shall be updated to it, and the master heartbeat monitoring of RM-HB-02 starts. | 7.2.8.3.1, 7.2.8.3.2.2 | 8.3.3g, 8.3.3h, 8.3.3k, 8.3.3l, 9.4.9.1.1a |
| RM-SL-06 | With parallel bus access, an NMT message or a master heartbeat received during the bus selection process on the bus that is not the active one shall make that bus the requested active bus at once, without a change of Ctoggle. When the link reports the new active bus, the redundancy block shall issue the bus switch event to `ocan_nmt`, so that the node starts its heartbeat on that bus (NM-HB-05), end the process and update Bdefault (architecture section 6.5). When messages arrive on both buses in the same clock cycle, the message of the active bus shall be taken (DS-BG-04). | 7.2.8.3.1, 7.2.8.3.2.2 | 8.2.1a, 8.2.2a, 8.3.3g, 8.3.3h, 8.3.3k, 8.3.3l |
| RM-SL-07 | Outside the bus selection process, frames of the inactive bus shall not change the active bus. | none | 8.3.3a, 8.3.3b |
| RM-SL-08 | The NMT services reset node and reset communication shall not change the active bus, Ctoggle or the state of the bus selection process. Only a hardware reset restarts the redundancy block (RM-SL-01). | 7.3.2.2.1 | 8.3.2a, 11.1 |
| RM-SL-09 | The toggling shall not read Bdefault: each toggle switches to the other bus, so that after an even number of toggles the node is on the bus on which the process started. A write of Bdefault shall change neither the active bus nor a running process. The written value is used at the next hardware reset (RM-SL-01), unless the end of a process overwrites it first (RM-SL-05, RM-SL-06). | none | 8.3.2a, 8.3.3j, 8.3.3l |
| RM-SL-10 | A write of Ctoggle shall set Ctoggle. During a bus selection process the toggling shall continue with the written value, without a restart of the toggling timer: a toggle that falls due is made while Ctoggle is less than Ntoggle (RM-SL-04). A write of Ntoggle shall take effect at the next toggle that falls due. A write outside a process has no effect on the next process, which starts with Ctoggle = 0. | none | 8.3.1a, 8.3.1c |

### 2.4 Minimal set

In both sets an NMT message or a master heartbeat ends the bus selection process (RM-SL-05,
RM-SL-06); the minimal set has no NMT messages (clause 9.4.6.1a), so the master heartbeat ends it there.

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| RM-MS-02 | With `MinimalSet_g` = true there is no start-up bus selection process: the master heartbeat monitoring of RM-HB-02 starts when `ocan_nmt` leaves the Initialisation (NM-MS-02). | none | 8.3.2b, 9.4.9.2a |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Master heartbeat missing for Ttoggle consumer heartbeat times | RM-1 | Missing heartbeat event; Pre-operational request; bus selection process |
| Master heartbeat with a DLC other than 1 | RM-1 | Ignored; error event |
| No NMT message and no master heartbeat after Ntoggle toggles | RM-2 | Event; the node stays on its bus and keeps listening |
| Write of Bdefault during a bus selection process | RM-2 | No effect on the process; the end of the process overwrites the value when a bus is found |
| Write of Ctoggle or Ntoggle during a bus selection process | RM-2 | The toggling continues with the written values (RM-SL-10) |
| Consumer heartbeat time 0 | RM-1 | No monitoring and no toggling |
| Toggle due outside Pre-operational | RM-2 | Waits for Pre-operational |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `MinimalSet_g` | false | true, false | Minimal protocol set of clause 9 (D2): no start-up bus selection (RM-MS-02) |

The parameters of clause 8.3.1 are inputs from `ocan_od`; their default values are parameters of the object
dictionary.

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 8.3.1a | The standard gives no encoding of Bdefault. OpenCAN uses 0 for bus A, the nominal bus, and 1 for bus B, the redundant bus; `ocan_od` accepts no other value |
| 8.3.1a | Ctoggle counts the toggles of the current bus selection process: it is cleared at the start of a process and kept after its end, so that the application can read how many toggles the last process needed. A write sets the count; during a process the toggling continues from the written value (RM-SL-10) |
| 8.3.3e | The node misses the master heartbeat when none has arrived for Ttoggle consumer heartbeat times (architecture section 2). The monitoring starts at the end of the bus selection process, not at the first master heartbeat as for an ordinary heartbeat consumer: a Redundancy Master that has ended the bus selection with an NMT message produces its heartbeat on that bus (clause 8.3.3a) |
| 8.3.3e, 8.3.3i, 8.3.3j | The switch at a missing master heartbeat is the first toggle. The toggling is relative to the bus on which the process started and never reads Bdefault (RM-SL-09). That bus is Bdefault after a hardware reset and after every process that found a bus (clause 8.3.3l), so after an even number of toggles the node is on Bdefault, as clause 8.3.3j requires. A write of Bdefault during a process (SDO, clause 8.3.1c) therefore cannot move the node to a third bus or break the parity; it takes effect at the next hardware reset. The NMT resets change neither the bus nor the process (RM-SL-08) |
| 8.3.3e (Figure 8-2) | Bus switching is enabled when Ntoggle is not 0 |
| 8.3.3g, 8.3.3h, Table 8-1, A.4.1 | Clauses 8.3.3g and 8.3.3h name the NMT message as the message that identifies the active bus. Table 8-1 describes Ttoggle as the time during which the node listens for the heartbeat message on a bus, and Annex A.4.1 describes the toggling as the search for the heartbeat of the Redundancy Master. An NMT message or a master heartbeat on the selected bus therefore ends the bus selection process (RM-SL-05). The node also finds a Redundancy Master that only produces its heartbeat on the new bus after a switch (clause 8.3.3b) |
| 8.3.3g | The clause applies during the bus selection process. Outside it, a frame of the inactive bus does not change the active bus (RM-SL-07), so that a faulty node on the inactive bus cannot move the node away from a Redundancy Master that operates on the active bus |
| 8.3.2b | The toggling in Pre-operational belongs to the start-up procedure, whose Figure 8-1 ends with the bus selection process, and to the bus monitoring of clause 8.3.3e. An enter pre-operational command of the master (command specifier 128) starts no toggling: the node keeps its bus and its master heartbeat monitoring |
| 9.4.9.1.1a | The heartbeat may be used for the autonomous bus selection. The minimal set has no NMT messages (clause 9.4.6.1a), so the master heartbeat is the message that ends the bus selection process there; the rule of RM-SL-05 is the same for both sets |
| 8.3.1a, 11.1 | Object 2000h lies in the manufacturer-specific area, which the reset application restores (\[CiA301\] section 7.3.2.2.1). OpenCAN keeps 2000h at reset node and at reset communication; only a hardware reset restores its power-on value. Otherwise a reset node would lose the bus that the last bus selection found (clause 8.3.3l) and the count Ctoggle (specification of `ocan_nmt`, section 2.6) |
| 8.3.2a, 11.1 | A hardware reset is the reset of the core. Reset node and reset communication are commands of the Redundancy Master on the active bus; the node keeps that bus. The reset of the whole device that the applicability matrix names for reset node concerns the application (NM-SM-06) |
| 8.3.3l | The updated Bdefault is held in `ocan_od`. A power-on or hardware reset restores the configured value; storing the update in non-volatile memory is a task of the integrator |
