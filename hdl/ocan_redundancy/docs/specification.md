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
| RM-IF-07 | The redundancy block shall provide as status the state of the bus selection process, Ctoggle, the state byte of the last master heartbeat and, per bus, whether a master heartbeat arrived within the last consumer heartbeat time. It shall provide events for a missing master heartbeat, for the end of the toggling without an active bus, and for a master heartbeat with a DLC other than 1. | 7.2.8.2.2.3 | 5.6.2a, 8.3.3e, 8.3.3j |
| RM-IF-08 | The redundancy block shall take an event of each bus in every clock cycle, also events of both buses in the same cycle, and complete its processing of each event within the minimum frame time of 46 bit times at 1 Mbit/s (D11). | none | 8.3.3g |

### 2.2 Master heartbeat consumer (RM-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| RM-HB-01 | A master heartbeat shall be an event of RM-IF-01 with DLC 1. An event with another DLC is no heartbeat: it shall be ignored and reported as an error event. Every value of the state byte shall be accepted. | 7.2.8.3.2.2 | 6.5.2b, 9.4.8a |
| RM-HB-02 | Outside the bus selection process the node shall measure the time since the last master heartbeat on the active bus, starting at the end of the bus selection process. When it reaches Ttoggle consumer heartbeat times, the master heartbeat is missing: the redundancy block shall raise the missing heartbeat event and start the bus selection process (RM-SL-02). | 7.5.2.19 | 6.5.2b, 8.3.3c, 8.3.3e |
| RM-HB-03 | With a consumer heartbeat time of 0 the master heartbeat shall not be monitored and no toggling shall take place: the node stays on its bus, and a bus selection process ends only by RM-SL-05 or RM-SL-06. | 7.5.2.19 | 8.3.1a |
| RM-HB-04 | Ttoggle = 0 shall act as Ttoggle = 1. A change of the consumer heartbeat time or of Ttoggle shall restart the running timer. | none | 8.3.1a |
| RM-HB-05 | Per bus, the presence status shall be set by a master heartbeat on that bus and cleared when no master heartbeat arrived on it for one consumer heartbeat time. With a consumer heartbeat time of 0 it shall stay cleared. | 7.2.8.2.2.3 | 5.6.2a |

### 2.3 Bus selection process (RM-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| RM-SL-01 | After a hardware reset the requested active bus shall be Bdefault: 0 is bus A (nominal), 1 is bus B (redundant). When `ocan_nmt` enters Pre-operational for the first time after the reset, the bus selection process shall start on this bus without a switch, with Ctoggle = 0. | 7.3.2.2.1 | 8.3.2a, 8.3.2b |
| RM-SL-02 | At a missing master heartbeat the redundancy block shall request Pre-operational from `ocan_nmt`, start the bus selection process with Ctoggle = 0, and switch to the other bus as the first toggle (RM-SL-03) once the NMT state is Pre-operational. | none | 8.3.3e |
| RM-SL-03 | A toggle shall request the other bus from `ocan_link`, increment Ctoggle and restart the toggling timer. The toggle event to `ocan_nmt` shall be issued when the link reports the new active bus, so that the node starts its heartbeat on the new bus (NM-HB-05). A toggle shall be made only while the NMT state is Pre-operational; one that falls due in another state shall wait for Pre-operational. | none | 8.3.3e, 8.3.3h, 8.3.3i |
| RM-SL-04 | During the bus selection process, when no NMT message has arrived on the active bus for Ttoggle consumer heartbeat times since the start of the process or the last toggle, the redundancy block shall toggle while Ctoggle is less than Ntoggle. When Ctoggle has reached Ntoggle it shall stop toggling, stay on its bus, raise the event for the end of the toggling without an active bus, and keep the process running. With Ntoggle = 0 no toggle takes place, also not the first one of RM-SL-02. | none | 8.3.3h, 8.3.3i, 8.3.3j |
| RM-SL-05 | An NMT message on the active bus during the bus selection process shall end it: the active bus is the bus found, Bdefault shall be updated to it, and the master heartbeat monitoring of RM-HB-02 starts. | 7.2.8.3.1 | 8.3.3g, 8.3.3k, 8.3.3l |
| RM-SL-06 | An NMT message on the inactive bus during the bus selection process (parallel bus access) shall make that bus the requested active bus at once, without a change of Ctoggle, and end the process when the link reports the new active bus, with the update of Bdefault (architecture section 6.5). When NMT messages arrive on both buses in the same clock cycle, the message of the active bus shall be taken (DS-BG-04). | 7.2.8.3.1 | 8.3.3g, 8.3.3k, 8.3.3l |
| RM-SL-07 | Outside the bus selection process, frames of the inactive bus shall not change the active bus. | none | 8.1a, 8.3.3a, 8.3.3b |
| RM-SL-08 | The NMT services reset node and reset communication shall not change the active bus, Ctoggle or the state of the bus selection process. Only a hardware reset restarts the redundancy block (RM-SL-01). | 7.3.2.2.1 | 8.3.2a, 11.1 |

### 2.4 Minimal set

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| RM-MS-01 | With `MinimalSet_g` = true a master heartbeat shall end the bus selection process as an NMT message does: one on the active bus by RM-SL-05, one on the inactive bus by RM-SL-06. | 7.2.8.3.2.2 | 9.4.9.1a, 8.3.3g, 8.3.3k |
| RM-MS-02 | With `MinimalSet_g` = true there is no start-up bus selection process: the master heartbeat monitoring of RM-HB-02 starts when `ocan_nmt` leaves the Initialisation (NM-MS-02). | none | 8.3.2b, 9.4.9.2a |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Master heartbeat missing for Ttoggle consumer heartbeat times | RM-1 | Missing heartbeat event; Pre-operational request; bus selection process |
| Master heartbeat with a DLC other than 1 | RM-1 | Ignored; error event |
| No NMT message after Ntoggle toggles | RM-2 | Event; the node stays on its bus and keeps listening |
| Consumer heartbeat time 0 | RM-1 | No monitoring and no toggling |
| Toggle due outside Pre-operational | RM-2 | Waits for Pre-operational |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `MinimalSet_g` | false | true, false | Minimal protocol set of clause 9 (D2): the master heartbeat identifies the active bus |

The parameters of clause 8.3.1 are inputs from `ocan_od`; their default values are parameters of the object
dictionary.

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 8.3.1a | The standard gives no encoding of Bdefault. OpenCAN uses 0 for bus A, the nominal bus, and 1 for bus B, the redundant bus; `ocan_od` accepts no other value |
| 8.3.1a | Ctoggle counts the toggles of the current bus selection process: it is cleared at the start of a process and kept after its end, so that the application can read how many toggles the last process needed |
| 8.3.3e | The node misses the master heartbeat when none has arrived for Ttoggle consumer heartbeat times (architecture section 2). The monitoring starts at the end of the bus selection process, not at the first master heartbeat as for an ordinary heartbeat consumer: a Redundancy Master that has ended the bus selection with an NMT message produces its heartbeat on that bus (clause 8.3.3a) |
| 8.3.3e, 8.3.3i, 8.3.3j | The switch at a missing master heartbeat is the first toggle. Bdefault is updated at the end of every bus selection process (clause 8.3.3l), so a process starts on Bdefault; after an even number of toggles the node is back on it, as clause 8.3.3j requires |
| 8.3.3e (Figure 8-2) | Bus switching is enabled when Ntoggle is not 0 |
| 8.3.3g, 8.3.3h | In the clause 6 slave only an NMT message identifies the active bus. A master heartbeat on the selected bus does not stop the toggling; the integrator chooses Ttoggle so that the Redundancy Master commands the node within Ttoggle consumer heartbeat times |
| 9.4.9.1a | The minimal set has no NMT messages (clause 9.4.6.1a). The master heartbeat takes their place for the bus selection |
| 8.3.2a, 11.1 | A hardware reset is the reset of the core. Reset node and reset communication are commands of the Redundancy Master on the active bus; the node keeps that bus. The reset of the whole device that the applicability matrix names for reset node concerns the application (NM-SM-06) |
| 8.3.3l | The updated Bdefault is held in `ocan_od`. A power-on or hardware reset restores the configured value; storing the update in non-volatile memory is a task of the integrator |
