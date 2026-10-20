# ocan_time: Specification

## 1. Overview

`ocan_time` is the time consumer of OpenCAN (ECSS-E-ST-50-15C clause 7, D5 of the
[architecture](../../../docs/architecture.md)). It keeps the local spacecraft elapsed time (SCET) of the node, sets it
from the Spacecraft Time PDO of the time producer and from the Local SCET Set object, and returns it in the Local
Time PDO. For the high-resolution time distribution protocol (clause 7.2.3) it samples the local time at every SYNC
and relates both PDOs to that sample.

| Block | Entity | Function |
| --- | --- | --- |
| TM-1 | `ocan_time` | Local SCET counter: 32 bits of seconds, `FineBits_g` bits of sub-seconds, advanced from the system clock |
| TM-2 | `ocan_time` | SYNC sample: the local time at the reception of every SYNC |
| TM-3 | `ocan_time` | Spacecraft Time PDO consumer: setting of the local time, basic or high-resolution protocol |
| TM-4 | `ocan_time` | Local Time PDO producer: transmission by SYNC count or on request, frame build |

`ocan_time` runs in one clock domain. The CiA 301 column of the tables names the section of \[CiA301\] that defines
the object or protocol.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| TM-IF-01 | The time block shall take from `ocan_dispatch` the SYNC with its DLC and the Spacecraft Time PDO with its DLC and data as one-cycle events (DS-IF-04, DS-RX-04). | 7.2.5, 7.2.2.5.1 | 6.3b, 7.2.2c |
| TM-IF-02 | The time block shall pass the Local Time PDO to `ocan_dispatch` as a transmit request (DLC and data) with a valid/ready handshake and take its completion (sent, aborted). | 7.2.2.5.1 | 7.2.2e, 7.2.3h |
| TM-IF-03 | The time block shall take from `ocan_od` the transmission type of the Spacecraft Time PDO (RPDO) and of the Local Time PDO (TPDO), and a write of the Local SCET Set object (value and event). It shall provide the current local time for reads of the Local SCET Get object. | 7.5.2.35, 7.5.2.37 | 7.1.2b, 7.1.2c, 7.1.2d |
| TM-IF-04 | The time block shall take a one-cycle request from the user logic to send the Local Time PDO. | 7.2.2.3 | 7.2.2f |
| TM-IF-05 | The time block shall provide the local time (coarse and fine) to the user logic in every clock cycle, a flag that is set once the local time has been set since the reset, and events for a setting of the local time, for a SYNC sample, for a Local Time PDO that could not be requested because the previous one was pending, and for a Spacecraft Time PDO that was not processed. | none | 7.1.1a, 7.2.3k |
| TM-IF-06 | The time block shall take an event in every clock cycle, also the SYNC and the Spacecraft Time PDO in consecutive frames, and complete the processing of each event within the minimum frame time of 46 bit times at 1 Mbit/s (D11). | none | 7.2.3k |

### 2.2 Local SCET (TM-1)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| TM-CT-01 | The local time shall be an unsegmented time code of 32 bits of seconds (coarse time) and `FineBits_g` bits of sub-seconds (fine time), from 0 to 24. The fine time unit is 2^-`FineBits_g` s. | none | 7.1.1a, 7.1.2e |
| TM-CT-02 | The local time shall advance with the system clock of frequency `ClkFrequency_g`: n clock cycles after a setting it shall be the set value plus floor(n * 2^`FineBits_g` / `ClkFrequency_g`) fine time units, without a cumulative rounding error. | none | 7.1.1a |
| TM-CT-03 | The coarse time shall wrap from 2^32 - 1 to 0. | none | 7.1.1a |
| TM-CT-04 | After a hardware reset the local time shall be 0 and the set flag cleared. The NMT services reset node and reset communication shall not change the local time. | 7.3.2.2.1 | 7.1.2a |
| TM-CT-05 | A write of the Local SCET Set object shall set the local time to the written value in the clock cycle of the write event. | none | 7.1.2c |

### 2.3 SYNC sample (TM-2)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| TM-SY-01 | At every SYNC with DLC 0 or 1 the time block shall sample the local time. The sample is taken a fixed number of clock cycles after the reception of the SYNC by `olo_intf_can`, the same for both buses. | 7.2.5.3.1 | 7.2.3k |
| TM-SY-02 | A SYNC with another DLC shall not be sampled and shall be ignored. | 7.2.5.3.1 | 9.4.8a |

### 2.4 Spacecraft Time PDO (TM-3)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| TM-RX-01 | The SCET of a PDO shall be read from the first seven data bytes: bytes 0 to 2 the fine time, bytes 3 to 6 the coarse time, each field with its least significant byte first. The fine time is aligned to its most significant bit, 2^-1 s; bits below the resolution of the local time shall be ignored. | 7.1.3.2, 7.1.4.5 | 7.1.2e, 7.1.2f, 7.1.2h |
| TM-RX-02 | A Spacecraft Time PDO with more than seven data bytes shall be processed with its first seven bytes. One with fewer than seven shall not be processed and shall raise the event of TM-IF-05. | 7.5.2.36 | 9.4.8a |
| TM-RX-03 | With an event-driven transmission type of the Spacecraft Time PDO (254, 255), the basic protocol: the local time shall be set to the received SCET in the clock cycle of the reception event. | 7.2.2.2 | 7.2.2c |
| TM-RX-04 | With a synchronous transmission type of the Spacecraft Time PDO (0 to 240), the high-resolution protocol: the received SCET is the time of the producer at the last preceding SYNC. The local time shall be set to the received SCET plus the local time elapsed since the last SYNC sample, so that the local time at that SYNC is the received SCET. | 7.2.2.2 | 7.2.3c, 7.2.3g |
| TM-RX-05 | In the high-resolution protocol a Spacecraft Time PDO without a SYNC sample since the hardware reset shall not be processed and shall raise the event of TM-IF-05. | none | 7.2.3c |
| TM-RX-06 | With a transmission type from 241 to 253 the Spacecraft Time PDO shall not be processed. | 7.5.2.35 | 11.1 |

### 2.5 Local Time PDO (TM-4)

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| TM-TX-01 | The Local Time PDO shall have DLC 7: bytes 0 to 2 the fine time, bytes 3 to 6 the coarse time, each field with its least significant byte first. The fine time is aligned to its most significant bit; the bits below `FineBits_g` shall be 0. | 7.1.3.2, 7.1.4.5 | 7.1.2f, 7.1.2g, 7.2.2e |
| TM-TX-02 | With a transmission type n from 1 to 240 the Local Time PDO shall be requested at every n-th SYNC, counted from the first SYNC after the time block was reset or the transmission type changed, with the SYNC sample of that SYNC. | 7.2.2.2 | 7.2.3h, 7.2.3k |
| TM-TX-03 | With transmission type 0 the Local Time PDO shall be requested at the first SYNC after a request of the user logic, with the SYNC sample of that SYNC. | 7.2.2.2 | 7.2.3k |
| TM-TX-04 | With transmission type 254 or 255 the Local Time PDO shall be requested on a request of the user logic: in the high-resolution protocol (TM-RX-04) with the last SYNC sample, otherwise with the local time at the request. | 7.2.2.2, 7.2.2.3 | 7.2.2f, 7.2.3k |
| TM-TX-05 | Transmission types 241 to 253 shall request no Local Time PDO. | 7.5.2.37 | 11.1 |
| TM-TX-06 | At most one Local Time PDO request shall be pending. One that falls due while a request is pending shall not be requested and shall raise the event of TM-IF-05. | none | 7.2.2g |

## 3. Error conditions

| Condition | Detection | Response |
| --- | --- | --- |
| SYNC with a DLC other than 0 or 1 | TM-2 | Ignored, no sample |
| Spacecraft Time PDO with fewer than seven bytes | TM-3 | Not processed; event |
| High-resolution Spacecraft Time PDO before the first SYNC sample | TM-3 | Not processed; event |
| Local Time PDO due while the previous one is pending | TM-4 | Not requested; event |
| Transmission type 241 to 253 | TM-4 | No Local Time PDO |

## 4. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `ClkFrequency_g` | 100000000 | 1000000 to 2^31 - 1 | Frequency of the system clock in Hz |
| `FineBits_g` | 24 | 0 to 24 | Width of the fine time (D5) |

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 7.1.2e, 7.1.2f | The structure lists the coarse time first, while Figure 7-1 places the fine time in octets 1 to 3 and the coarse time in octets 4 to 7. Clause 7.1.2f makes the figure the frame format. Within each field the octets follow the transfer syntax of \[CiA301\] (least significant octet first). This equals the encoding of one 56-bit unsigned value with the fine time in its lower 24 bits, which is the data type proposed for the Local SCET objects in `ocan_od` |
| 7.1.2b | The standard assigns no object dictionary index to the Local SCET Set and Local SCET Get objects. OpenCAN places them in the manufacturer-specific area next to the redundancy object 2000h (`ocan_od`) |
| 7.2.1a, 7.2.3 | The transmission type of the Spacecraft Time PDO selects the protocol: a synchronous type relates the time to the SYNC (clause 7.2.3e makes the producer send it with type 1 to 240), an event-driven type sets the time at the reception. The setting takes effect at the reception, corrected by the time since the SYNC; it is not deferred to the next SYNC as for other synchronous receive PDOs, because the correction already relates the value to the SYNC |
| 7.2.3k | The SYNC sample is taken a fixed time after the end of the SYNC frame. The latency from the bus to the sample is the same for every node with OpenCAN and is stated in the user guide, so that a system can compensate it |
| 7.2.2 (note), 7.2.3 (note 1) | The transmission of the Local Time PDO is left to the implementer. OpenCAN sends it by SYNC count (types 1 to 240), at the SYNC after a request (type 0) or on request (types 254, 255). Remote transmission types are not used (clause 11.1); the inhibit time and the event timer of the Local Time PDO are not supported |
| 7.1.2a, 7.3.2.2.1 of \[CiA301\] | The local time is a process value of the device, not a parameter: the NMT resets do not change it |
| 9.3a | The minimal set has no time PDOs; a core with `MinimalSet_g` may still include `ocan_time` as an additional object (clause 9.4.10a) |
