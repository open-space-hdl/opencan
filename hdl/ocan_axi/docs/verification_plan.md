# ocan_axi: Verification Plan

## 1. Overview

`ocan_axi` is verified in a network testbench. The test plays the software of the processor system through the
AXI-Lite VVC of UVVM: it writes the bit timing and the control, reads the status, waits for the interrupt, reads and
writes the PDO registers and answers the mailbox. The CAN network model of `tb/` plays, with model node M1 of the
active bus, the NMT master, the Redundancy Master (its heartbeat every 4 ms), the SYNC and time producer and the peer
of the PDOs and SDOs; M2 of each bus acknowledges and produces the frames of the error tests. The functions of the
node are verified by the benches of `ocan_core` and its blocks, those of the registers by the bench of `ocan_mib`;
this bench shows that every connection between them works and that the software can run the node through the
registers alone.

Tests observe the AXI4-Lite port, the interrupt, the buses and the model logs only.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `ocan_axi_net_tb` | `ocan_axi_net_th` | `ocan_axi` with `Clk` 50 MHz (`ClkFrequency_g` = 50000000), NODE-ID 5, producer heartbeat time 5 ms, consumer heartbeat time of the master 10 ms, Ttoggle 1, Ntoggle 2, the Spacecraft Time PDO 0F0h and the Local Time PDO 1F5h of type 254; the AXI-Lite VVC master (`ocan_tb_axilite_master`); `ocan_tb_can_bus` with the model nodes M1 and M2 on each bus, 1 Mbit/s |

| VUnit configuration | Generics | Purpose |
| --- | --- | --- |
| `sel` | `BusAccess_g` = "Selective", `AutoEnable_g` = false | All test cases except the error injection |
| `par` | `BusAccess_g` = "Parallel", `TimePdos_g` = false, `AutoEnable_g` = false | Parallel bus access |
| `min` | `MinimalSet_g` = true, `TimePdos_g` = false, `AutoEnable_g` = false | Minimal set |
| `errinj` | `ErrInjRegs_g` = true, `AutoEnable_g` = false | Error injection through the registers |
| `auto` | `AutoEnable_g` = true | The node without software |

With `AutoEnable_g` = false the reset value of BIT_TIMING is 500 kbit/s (prescaler 4), so the node works only after
the software has written the bit timing of 1 Mbit/s (prescaler 2); with `AutoEnable_g` = true the reset value is
1 Mbit/s.

## 3. Test cases

| Test | Description | Requirements |
| --- | --- | --- |
| `test_startup` (TC-AX-01) | ID, GENERICS, CLK_FREQUENCY and DOMINANT_LIMIT describe the node of the harness. With `AutoEnable_g` = false: for 5 ms after the reset no frame of the node, no error on the bus and a transmit error counter of 0; CONTROL and BIT_TIMING read their reset values; after the software wrote the bit timing and ENABLE, the boot-up message (DLC 1, 00h), NODE reads Pre-operational with the valid NODE-ID 5, NMT start of M1 to Operational, RESET_COMM set, active bus A, master heartbeat present. With `AutoEnable_g` = true: the node starts without a register access | AX-IF-01, AX-IF-02, AX-IF-03, AX-CN-01, AX-CN-02, AX-CN-03 |
| `test_reset_release` (TC-AX-02) | Four resets, each released while a frame of M2 is on bus A, 0, 7, 14 and 21 bit times after its start of frame; a read of ID and a write of EVENTS_IRQ_EN queued for the first cycles after the release complete with their effect; the frame of M2 ends without an error; the node joins the bus after it (with `AutoEnable_g` = false after the software enabled it) | AX-IF-01, AX-RS-01 |
| `test_pdo` (TC-AX-03) | Every receive PDO from M1 raises the interrupt and RPDO_RECEIVED, RPDOn_HI and RPDOn_LO read its bytes; the clear ends the interrupt; every transmit PDO written to TPDOn_HI and TPDOn_LO and requested by REQUEST is on the bus with these bytes and DLC 8 and sets TPDO_SENT; a SYNC of M1 sets the SYNC flag | AX-CN-01 |
| `test_sdo_mailbox` (TC-AX-04) | SDO accesses of M1 to the objects of the user logic, answered by the software through the mailbox after the interrupt APP_REQUEST: a download of one byte to 2100h sub-index 1 (APP_REQ, the byte in bits 7 to 0 of APP_REQ_LO, download response), an upload of it (expedited upload response with the byte of the software), a download refused by the software with 0601 0002h (SDO abort with this code) | AX-CN-01 |
| `test_time` (TC-AX-05) | A Spacecraft Time PDO of M1 sets TIME_SET, TIME_COARSE reads its coarse time and TIME_FINE its fine time plus the time since; TIME_CONTROL.REQUEST sends the Local Time PDO (DLC 7, the coarse time in bytes 3 to 6) | AX-CN-01 |
| `test_monitoring` (TC-AX-06) | A CRC error at the receiver of controller A: the CRC flag of LINK_ERRORS, the CRC counter of LINK_A_COUNTS0, LINK_A error active; the master heartbeat stops: MASTER_HB_MISSING raises the interrupt, REDUNDANCY reads the active bus B and a Ctoggle of at least 1 | AX-CN-01 |
| `test_errinj` (TC-AX-07) | Through the error injection registers: one bit of copy A of 1017h (PARAM_COPY, the heartbeat period stays 5 ms), one bit of `IdCopy` (NODE_ID, a new boot-up), the transmit bit of controller A forced dominant (the dominant timeout flag and LINK_A.DOM_TIMEOUT) and CONTROL.REENABLE_A after the release of the injection (LINK_A.DOM_TIMEOUT cleared) | AX-CN-01 |

The deliberate faults of `ocan_axi` replace the actual of one port in the port map of `ocan_core` or `ocan_mib`
(a connection open, a constant, the reported generics constant); every fault is simulated with the test cases of the
table that must detect it.

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| AX-IF-01 | TC-AX-01, TC-AX-02 |
| AX-IF-02 | TC-AX-01 |
| AX-IF-03 | TC-AX-01 |
| AX-CN-01 | TC-AX-01, TC-AX-03, TC-AX-04, TC-AX-05, TC-AX-06, TC-AX-07 |
| AX-CN-02 | TC-AX-01 |
| AX-CN-03 | TC-AX-01 |
| AX-RS-01 | TC-AX-02 |
