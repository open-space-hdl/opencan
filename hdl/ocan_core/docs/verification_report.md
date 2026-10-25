# ocan_core: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_core*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_core_net_tb` | 9 | 36 | 36 |

Every test case runs in the four configurations of section 2 of the [verification plan](verification_plan.md):
`sel_full`, `par_full`, `sel_min` and `par_min_time`. The node is the whole core with its eight blocks, the model node
M1 of the active bus acts as Redundancy Master, NMT master, SYNC and time producer, SDO client and peer of the PDOs.
In every test three checkers watched the logs of M1 on both buses: every frame of the node was a data frame with an
11-bit identifier, no frame of the node appeared on the inactive bus later than 500 us after a change of the active
bus, and no frame of the node appeared while its NODE-ID was not valid.

- Start-up (TC-CO-01): after `Rst`, also released in the middle of a clock period, the node integrated on Bdefault
  (bus A in `sel_full` and `sel_min`, bus B in `par_full` and `par_min_time`), sent its boot-up message 705h and then
  its heartbeat every 5 ms; in the minimal set it was Operational by local control and sent no boot-up message.
- Configuration (TC-CO-02): in Pre-operational the COB-ID of transmit PDO 1 was invalidated, changed to 195h and made
  valid again, its transmission type set to 1, 1017h set to 8 ms, Ttoggle, Ctoggle and 1016h written; after the start
  the transmit PDO came on 195h at the SYNC with the data of the user logic, the heartbeat every 8 ms, Ttoggle and
  Ctoggle read back and Ctoggle at the redundancy block. A transmission type written in Operational was refused with
  0800 0022h. The identity object returned the vendor ID and the product code of the generics; the application object
  2100h went through the application port. In the minimal set no SDO request was answered.
- Process data (TC-CO-03): every receive PDO reached the user port with its data; transmit PDOs of the types 254, 1 and
  0 were on the bus with the data of the user logic and DLC 8; `Sync_Valid` marked every SYNC; in Pre-operational and
  Stopped no PDO was passed or sent; a hardware reset through `Rst` cleared the data at the user port.
- Time (TC-CO-04): after a Spacecraft Time PDO of a synchronous type, the local time equalled the SCET of M1 at the
  SYNC plus the time since then within 6 units of 2^-24 s; the Local Time PDO carried the local time of its SYNC
  within the same bound, and was sent on `Time_Req` with type 254; Local SCET Set and Get worked by SDO; with the
  Local Time PDO of type 254, the Spacecraft Time PDO kept its type 1; without the time PDOs no time PDO was used
  or sent, and without a time block the local time stayed 0.
- Bus monitoring (TC-CO-05): with the master heartbeat missing, the node entered Pre-operational, stopped its PDOs and
  toggled to the other bus at once, with its heartbeat there within 1 ms; the master heartbeat on the other bus ended
  the bus selection and Bdefault followed (read back by SDO). An NMT message ended a second bus selection: with
  selective bus access on the bus that the node had toggled to, with parallel bus access from the inactive bus, to
  which the node switched at once. After Ntoggle toggles without success the toggling ended on the default bus. Bit 4
  of the error register followed the error passive state of the controller of the active bus, with parallel bus
  access on both buses.
- NMT resets (TC-CO-06): reset node and reset communication from M1 in Operational raised `Evt_ResetApp` (reset node
  only) and `Evt_ResetComm`, the boot-up message followed, 1017h returned to its power-on value, 2000h, the data at the
  PDO port, the local time and the active bus were kept; a reset communication in Stopped and a reset node in
  Pre-operational were each followed by a boot-up message; stop, enter pre-operational and start changed the state in
  the heartbeat; in the minimal set no NMT command had an effect.
- NODE-ID (TC-CO-07): with an invalid code at the pins the node stayed silent and did not acknowledge; a valid code
  started it; a disable and enable with another bit timing between (the same bit rate with another sample point)
  restarted the node.
- Applicability (TC-CO-08): remote frames on the identifiers of transmit PDO 1 and receive PDO 1, a node guarding
  request and frames on the identifiers of EMCY and TIME caused no transmit PDO, no receive PDO, no answer to node
  guarding and no SDO reply; a block download and a block upload request were answered with an abort (0504 0001h for
  the download); in the minimal set no SDO request was answered. Over the whole test every frame of the node was its
  boot-up message, a heartbeat, a transmit PDO, a Local Time PDO or an SDO reply.
- Connections (TC-CO-09): every status and event port group of the configuration was active at least once. A CRC
  error that only the node detected came from a disturbance of its receive input alone (the input `DutRec` of the bus
  model); with parallel bus access also the controller of the inactive bus reported it.

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Measured values

| Item | Value |
| --- | --- |
| Last bit of a receive PDO frame, as the transmitter M1 logs it (sample point of the last bit of the end of frame), to `Rpdo_Valid`, 40 MHz, 1 Mbit/s | -825 ns in all four configurations: `Rpdo_Valid` comes in the last but one bit of the end of frame, 0.925 us after its start, where the controller takes the frame |
| `Tpdo_Req` (from the clock edge after which it is '1') to the start of the transmit PDO frame on an idle bus, 1 Mbit/s | 1.075 us in all four configurations (frame of 111 bits on the bus) |
| Master heartbeat missing to the heartbeat of the node on the other bus | within 1 ms (TC-CO-05) |
| Local time after the Spacecraft Time PDO, and in the Local Time PDO, against the SCET of M1 at the SYNC | within 6 units of 2^-24 s (TC-CO-04) |

## 3. Generic ranges

| Generic | Declared range | Simulated (network bench) | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `BusAccess_g` | "Selective", "Parallel" | both | both; "Dual" refused |
| `SyncStages_g` | 2 to 4 | 2 | 2, 4 |
| `AutoRecover_g` | true, false | true | true, false |
| `DominantLimit_g` | 13 to 1023 | 32 | 13, 32, 1023 |
| `MinimalSet_g` | true, false | both | both |
| `NumRpdo_g`, `NumTpdo_g` | 0 to 4; at most 3 in the minimal set with the time PDOs | 4, 3 | 0, 3, 4; 4 refused in the minimal set with the time PDOs |
| `TimePdos_g` | true, false | both | both |
| `ClkFrequency_g` | 1000000 to 2147483647 | 40000000 | 1000000, 100000000, 2147483647 |
| `FineBits_g` | 0 to 24 | 24 | 0, 24 |
| `DeviceType_g` to `SerialNumber_g` | 32 bits | defaults, `VendorId_g` 800004D8h, `ProductCode_g` 0000C0DEh | defaults |
| `ProducerHbTime_g` | 0 to 65535 | 5 | 0, 1000, 65535 |
| `MasterNodeId_g` | 0 to 127 | 1 | 0, 1, 127 |
| `MasterHbTime_g` | 0 to 65535 | 10 | 0, 1500, 65535 |
| `Bdefault_g` | 0, 1 | 0, 1 | 0, 1 |
| `Ttoggle_g` | 0 to 255 | 1 | 0, 1, 255 |
| `Ntoggle_g` | 0 to 255 | 2 | 0, 3, 255 |
| `RpdoType_g`, `TpdoType_g` | 0 to 240, 254, 255 | 254 | 0, 240, 254, 255 |
| `SctCobId_g`, `LtpCobId_g` | 0 to 2047, not restricted or free | 0F0h, 1F5h | 0, 0F0h and 1F5h, 4FFh and 500h; 0 refused in the minimal set with the time PDOs |
| `SctType_g`, `LtpType_g` | 0 to 240, 254, 255 | 1 | 0, 240, 254, 255 |

The benches of the blocks simulate the further values of the generics that the core passes to them (for example
`SyncStages_g`, `DominantLimit_g` and `AutoRecover_g` in the bench of `ocan_link`).

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, 39 deliberate faults of
the connections of the core were each simulated with the tests that must detect them; 38 were detected, and one
cannot be shown at the ports of the core:

| Fault | Test | Result |
| --- | --- | --- |
| Link enable without the NODE-ID | `sel_full.test_node_id` | detected |
| Link enable without `Ctrl_Enable` | `sel_full.test_node_id` | detected |
| Fault confinement state of controller 0 with parallel access | `par_full.test_bus_monitoring` | detected |
| Fault confinement state of the inactive controller | `par_full.test_bus_monitoring` | detected |
| Fault confinement state not connected | `sel_full.test_bus_monitoring` | detected |
| Requested bus not from the redundancy block | `sel_full.test_bus_monitoring` | detected |
| Active bus of the dispatch not from the redundancy block | `sel_full.test_bus_monitoring` | detected |
| Bus selection not passed to the dispatch | `par_full.test_bus_monitoring` | detected |
| Bus switch not passed to the NMT block | `sel_full.test_bus_monitoring` | detected |
| Pre-operational request not passed to the NMT block | `sel_full.test_bus_monitoring` | detected |
| Link stop not passed to the dispatch | `sel_full.test_connections` | not detected: a window of one clock cycle (below); TC-DS-18 of `ocan_dispatch` |
| Producer heartbeat time not connected | `sel_full.test_startup` | detected |
| Consumer heartbeat time of the master not connected | `sel_full.test_bus_monitoring` | detected |
| Bdefault update not passed to the object dictionary | `sel_full.test_bus_monitoring` | detected |
| Bdefault of the update not passed | `sel_full.test_bus_monitoring` | detected |
| Ctoggle write not passed to the redundancy block | `sel_full.test_configuration` | detected |
| Ctoggle of the redundancy block not read | `sel_full.test_configuration` | detected |
| Transmission types of the PDOs exchanged | `sel_full.test_process_data` | detected |
| Transmission types of the time PDOs exchanged | `sel_full.test_time` | detected |
| Local time not read by the object dictionary | `sel_full.test_time` | detected |
| Local SCET Set not passed to the time block | `sel_full.test_time` | detected |
| SYNC not passed to the time block | `sel_full.test_time` | detected |
| Spacecraft Time PDO tied off with the time PDOs | `sel_full.test_time` | detected |
| Request of the Local Time PDO tied off | `sel_full.test_time` | detected |
| Completions of the transmit PDOs exchanged | `sel_full.test_process_data` | detected |
| Reset application event from the reset communication | `sel_full.test_nmt_resets` | detected |
| SDO server in the minimal set | `sel_min.test_applicability` | detected |
| No time block in the minimal set with the time PDOs | `par_min_time.test_time` | detected |
| Time block in the minimal set without the time PDOs | `sel_min.test_time` | detected |
| Tick of the NMT block not connected | `sel_full.test_startup` | detected |
| Tick of the redundancy block not connected | `sel_full.test_bus_monitoring` | detected |
| PDO block not reset | `sel_full.test_process_data` | detected |
| Test inputs of the object dictionary not connected | `sel_full.test_connections` | detected |
| Test inputs of the NMT block not connected | `sel_full.test_connections` | detected |
| CRC errors of the link not at the port | `sel_full.test_connections` | detected |
| COB-ID mismatch not at the port | `sel_full.test_connections` | detected |
| Parameter copy error not at the port | `sel_full.test_connections` | detected |
| SDO transfer state not at the port | `sel_full.test_connections` | detected |
| SYNC event of the time block not at the port | `sel_full.test_connections` | detected |

The link stop at the dispatch (`LinkTx_Stopped`) withdraws a granted request when the controller of the active bus
stops between the grant and the take. The dispatch grants only while the link can take a frame, so this is a window of
one clock cycle, which the stimuli at the ports of the core cannot hit; TC-DS-18 of `ocan_dispatch` verifies it with a
model of the link that stops in that cycle (verification plan, section 6).

The time-outs of the blocks and the tick at the object dictionary, the SDO server, the PDO block and the time block
are not verified at the core (verification plan, section 6).

## 5. Summary

All 9 test cases pass in all four configurations; every requirement of the specification is covered by the
verification plan. Of the 39 deliberate faults of the connections, 38 are detected at the ports of the core and
the remaining one by TC-DS-18 of `ocan_dispatch`. VSG reports no errors and no warnings, and the GHDL synthesis
of `ocan_core` in `lint/synth_check.py` has no inferred latch for every combination of `BusAccess_g`,
`MinimalSet_g` and `TimePdos_g` and at the bounds of the numeric generics.
