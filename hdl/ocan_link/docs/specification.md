# ocan_link: Specification

## 1. Overview

`ocan_link` connects OpenCAN to the two buses of a redundant CAN network (ECSS-E-ST-50-15C clauses 5.4, 5.6 and 8.2).
It contains the CAN 2.0B controller `olo_intf_can` of Open Logic once or twice, depending on the bus access
architecture (D4 of the [architecture](../../../docs/architecture.md)). It switches the active bus on request, passes
the received frames of each bus with a fixed latency and sends the frames of `ocan_dispatch` on the active bus. It
also reports the error state and the error counters of every controller.

| Block | Entity | Function |
| --- | --- | --- |
| LK-1 | `ocan_link` (`olo_intf_can`, one or two) | CAN protocol, bit timing, fault confinement |
| LK-2 | `ocan_link` | Bus selector of the selective bus access: connects the controller to transceiver A or B |
| LK-3 | `ocan_link` | Bus switch sequencer: abort of a pending frame, disable, selection or mode change, enable |
| LK-4 | `ocan_link` | Receive path: frames of each bus as events with a fixed latency |
| LK-5 | `ocan_link` | Transmit path: one frame at a time to the controller of the active bus |

`ocan_link` runs in one clock domain; the bus inputs pass the synchronisers of `olo_intf_can` (`SyncTmr_g` = true).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| LK-IF-01 | The link shall connect to bus A and bus B, each with a transmit output, a receive input and a transmit enable output for its transceiver; '1' on the transmit output and the receive input is the recessive level. | 8.2.1a, 8.2.3a |
| LK-IF-02 | The link shall take frames to send (identifier, IDE, RTR, DLC, eight data bytes) with a valid/ready handshake, take an abort request, and report the completion of each frame (sent or aborted) and every lost arbitration as events. | 5.6.1a |
| LK-IF-03 | The link shall pass every frame received on a bus (identifier, IDE, RTR, DLC, eight data bytes) as a one-cycle event of that bus, without back pressure. | 5.6.1a, 8.2.2a |
| LK-IF-04 | The link shall take the bit timing configuration (prescaler, PROP_SEG + PHASE_SEG1, PHASE_SEG2, SJW) as inputs common to all controllers. The configuration is applied while the link is disabled and is static while it is enabled. | 5.4.3a, 5.4.3d |
| LK-IF-05 | The link shall take an enable input, the requested active bus and a bus-off recovery request. | 6.10f, 8.2.3a |
| LK-IF-06 | The link shall provide the active bus and a busy indication while a bus switch is in progress. Per controller it shall provide the transmit and receive error counts, the fault confinement state (error active, error passive, bus off), the bus idle state and the error events (bit, stuff, CRC, form, acknowledgement). | 5.6.2a, 5.6.2b, 5.6.2c |

### 2.2 Bus access (LK-1, LK-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LK-BA-01 | With selective bus access (`BusAccess_g` = "Selective") the link shall have one `olo_intf_can`. The bus selector connects its transmit output and receive input to the active bus. The transmit output of the other bus shall be recessive and its transmit enable inactive. | 8.2.1a, 8.2.3a |
| LK-BA-02 | With parallel bus access (`BusAccess_g` = "Parallel") the link shall have one `olo_intf_can` per bus. The controller of the active bus runs in normal mode. The controller of the inactive bus runs in listen-only mode and the transmit enable of its bus is inactive. | 8.2.1a, 8.2.2a |
| LK-BA-03 | The transmit enable of the active bus shall be active while its controller is enabled in normal mode, and inactive otherwise. | 8.2.3a |
| LK-BA-04 | While the enable input is inactive, every controller shall be disabled, both transmit outputs recessive and both transmit enables inactive; no frame is passed or taken. | 6.10f |

### 2.3 Protocol and bit timing (LK-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LK-PR-01 | The CAN protocol shall be that of `olo_intf_can`: data and remote frames with standard (11-bit) and extended (29-bit) identifiers, bit stuffing, CRC, acknowledgement, error detection and signalling, and fault confinement. | 5.6.1a, 5.6.2a |
| LK-PR-02 | The bit rates 1 Mbit/s, 500 kbit/s, 250 kbit/s and 125 kbit/s shall be reachable through the bit timing configuration for every clock frequency f with f = r x P x Q for the bit rate r, a prescaler P of 1 to 1023 and Q of 8 to 25 time quanta per bit. | 5.4.1a, 5.4.2a |
| LK-PR-03 | The time quantum, the sample point and the resynchronization jump width (1 to min(4, PROP_SEG + PHASE_SEG1, PHASE_SEG2) time quanta) shall be configurable. | 5.4.3a, 5.4.3d |
| LK-PR-04 | The controllers shall synchronise on recessive-to-dominant edges only, and shall receive and send correctly with a far end whose bit time differs by the oscillator tolerance of the configured bit timing. | 5.4.3e |

### 2.4 Bus switch (LK-3)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LK-BS-01 | After the reset, and whenever the link is enabled, the active bus shall be the requested active bus. | 8.3.2a |
| LK-BS-02 | When the requested active bus differs from the active bus, the link shall switch the bus in this order. It requests the abort of a pending frame and waits until no frame is pending. It disables the controllers and changes the bus selector (selective) or exchanges the modes of the two controllers (parallel). It then enables the controllers and reports the new active bus. | 8.2.3a |
| LK-BS-03 | During a bus switch the link shall take no frame to send. After the switch a controller shall integrate on its bus (11 recessive bits) before it receives or sends. | 8.2.3a |
| LK-BS-04 | A frame pending at the start of a bus switch shall never be sent on the new bus. A frame that is on the bus when the abort is requested completes on the old bus as sent or aborted. | 8.3.3e |
| LK-BS-05 | A request that changes during a bus switch shall be taken when the switch has ended: the active bus then follows the latest request. | 8.2.3a |
| LK-BS-06 | The error counts and the fault confinement state of a controller shall be kept across a bus switch and while the controller is disabled. | 5.6.2a, 5.6.2c |

### 2.5 Receive path (LK-4)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LK-RX-01 | Every frame that a controller receives shall be passed as an event of the bus that the controller is connected to. The event follows the reception by `olo_intf_can` by a constant number of clock cycles, the same for both buses and both bus access architectures. | 5.6.1a, 7.2.3k |
| LK-RX-02 | With parallel bus access, frames received on both buses in the same clock cycle shall be passed in the same clock cycle, each as an event of its bus. | 8.2.2a |
| LK-RX-03 | A frame received on the inactive bus (parallel bus access, listen-only controller) shall be passed like a frame of the active bus. | 8.2.2a |

### 2.6 Transmit path (LK-5)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LK-TX-01 | A frame shall be taken only while the link is enabled, no bus switch is in progress and no frame is pending. The controller of the active bus sends it and retransmits it after an error or a lost arbitration until it is sent or aborted. | 5.6.1a |
| LK-TX-02 | An abort request shall drop a pending frame that is not on the bus at once. A frame that is on the bus shall complete: it is reported as sent after a successful attempt and dropped after a failed one. | 5.6.1a |
| LK-TX-03 | A bus-off controller shall keep its pending frame and send it after the bus-off recovery unless it is aborted. | 5.6.2a |

### 2.7 Fault confinement and status (LK-1)

| ID | Requirement | ECSS |
| --- | --- | --- |
| LK-FC-01 | The link shall provide, per controller, the transmit error count, the receive error count and the fault confinement state (error active, error passive, bus off). The application can read them at any time without affecting the protocol. | 5.6.2a, 5.6.2b, 5.6.2c |
| LK-FC-02 | The link shall pass, per controller, the bit, stuff, CRC, form and acknowledgement error events. | 5.6.2a |
| LK-FC-03 | With `AutoRecover_g` = true a bus-off controller shall recover after 128 occurrences of 11 consecutive recessive bits; with `AutoRecover_g` = false this recovery shall start only after a recovery request. | 5.6.2a |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| Bit, stuff, CRC, form or acknowledgement error | LK-1 | Error frame and error counts per the protocol; event per controller |
| Error passive, bus off | LK-1 | State per controller; a bus-off controller keeps its transmit output recessive until it has recovered |
| Bus stuck dominant or broken | LK-1 (no bus idle, errors) | A pending frame that never started is dropped at once on an abort; a bus switch completes |
| Request for the other bus during a bus switch | LK-3 | Taken after the running switch |
| Enable removed during a bus switch | LK-3 | Controllers disabled; the switch ends; on the next enable the active bus is the requested bus |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `BusAccess_g` | "Selective" | "Selective", "Parallel" | Bus access architecture of clause 8.2 (D4) |
| `SyncStages_g` | 2 | 2 to 4 | Synchroniser stages of the bus inputs (`olo_intf_can`) |
| `AutoRecover_g` | true | true, false | Automatic bus-off recovery, or recovery on request (`olo_intf_can`) |

The bit timing has no generic: it is set at runtime (LK-IF-04). `SyncTmr_g` of `olo_intf_can` is always true (family
rule for synchronisers).

## 5. Partner behaviour: olo_intf_can

From the source and the documentation of `olo_intf_can` in \[OLO\] 4.7.0-ft.7:

- **Transmit.** A frame is taken with `Tx_Valid` while `Tx_Ready` is '1' and stays pending until `Tx_Done` or
  `Tx_Aborted`. The controller retransmits it after an error or a lost arbitration (`Tx_ArbLost`); it has no transmit
  queue.
- **Abort.** `Tx_Abort` drops a pending frame that is not on the bus at once (`Tx_Aborted`). A frame on the bus
  completes: `Tx_Done` on success, otherwise it is dropped instead of retransmitted.
- **Disable.** `Cfg_Enable` = '0' keeps the transmit output recessive and stops the bit processing. A frame on the bus
  is cut, but **a pending frame stays pending** and is sent after the next enable, so the bus switch has to abort it
  first (LK-BS-02, LK-BS-04). After the enable the controller integrates (11 recessive bits). The error counts and the
  bus-off state are kept; disabling does not bypass the bus-off recovery.
- **Listen-only.** No acknowledge, no error or overload flags, no transmission; a pending frame is not started; the
  error counts do not change; errors are pulsed. `Cfg_ListenOnly` is static while `Cfg_Enable` is '1'.
- **Receive.** `Rx_Valid` is a one-cycle pulse after the last but one bit of the end of frame field, with no back
  pressure. Remote frames and frames with a data length code above 8 are output, the bytes beyond the data length are
  0, and the controller does not output its own frames (except in loopback mode).
- **Bit timing.** `Cfg_Tseg1` is PROP_SEG + PHASE_SEG1; SJW is limited to min(4, `Cfg_Tseg1`, `Cfg_Tseg2`).
  Hard synchronisation at a recessive-to-dominant edge in bus idle, resynchronisation on recessive-to-dominant edges
  within a frame only.

## 6. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 5.4.1a, 5.4.2a | The supported bit rates are those of the transceivers and of the device. The link reaches all four rates of the standard (LK-PR-02); which of them a device supports is set by its bit timing configuration |
| 5.4.3b, 5.4.3c | The calculation method and the choice of the bit timing are a system task: the integrator computes the values for the network, and the link accepts any valid setting. `canBitTiming` of Open Logic is an aid with its own criterion (smallest rate error); the user guide gives the formulas |
| 5.4.3d | `olo_intf_can` limits SJW also to PHASE_SEG2. Bosch 2.0 makes PHASE_SEG2 at least PHASE_SEG1, so every value that the clause allows is accepted |
| 5.3.6a, 5.3.6b | The inversion of the transmit bit for the RS-485 driver and its fail-safe mechanism belong to the board. The link keeps the transmit output of a disabled or inactive bus recessive and its transmit enable inactive |
| 5.6.2b | The error active and error passive states are indicated together with bus off (LK-FC-01) |
| 8.2.2a | Read with the expanded information of Annex A.4.2: a node with parallel bus access accesses each bus through its own controller |
| 8.2.3a | The selection mechanism of the link is the requested active bus input. `ocan_redundancy` drives it; how the application selects the bus is specified there |
