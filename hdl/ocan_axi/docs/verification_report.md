# ocan_axi: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_axi*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_axi_net_tb` | 7 | 19 | 19 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): TC-AX-01 and TC-AX-02 in
all five, TC-AX-03 in `sel`, `par` and `min`, TC-AX-04 and TC-AX-06 in `sel` and `par`, TC-AX-05 in `sel`, TC-AX-07
in `errinj`. Every action of the software went through the AXI4-Lite port, every check of the node through a register,
the interrupt, the buses or the log of a model node.

- Start-up (TC-AX-01): without `AutoEnable_g` the node sent nothing and disturbed nothing for 5 ms (no error at the
  model nodes, a transmit error counter of 0) and read the bit timing of 500 kbit/s of the generics; after the software
  wrote the bit timing of 1 Mbit/s and ENABLE, the boot-up message followed and NODE read 0000 8501h (NODE-ID 5 valid,
  Pre-operational); the NMT start of M1 took it to Operational. With `AutoEnable_g` the node started without a register
  access. GENERICS, CLK_FREQUENCY and DOMINANT_LIMIT read the generics of the harness in every configuration.
- Reset release (TC-AX-02): in all five configurations and at four positions of the frame of M2 (0, 7, 14 and 21 bit
  times after its start of frame) the read of ID and the write of EVENTS_IRQ_EN queued for the first cycles after the
  release completed with their effect, the frame ended without an error, and the node joined the bus after it.
- In the mailbox test (TC-AX-04) the data of a write of one byte read 0000 0000 0000 00ABh in APP_REQ_HI and APP_REQ_LO:
  the least significant byte of the value in bits 7 to 0, as the user guide states.

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

`python lint/synth_check.py`: `ocan_axi` synthesises with GHDL without an inferred latch in the four configurations of
the check (the default, the parallel bus access, the minimal set with the error injection registers, no PDOs), and
`BusAccess_g` = "Dual" stops the elaboration with the message of the core.

## 2. Deliberate faults

40 faults of the connections were each simulated with the tests that must detect them (`_ocan_work/axi_mut.py` in
the work directory of the project, not part of the repository): a port of `ocan_core` or of `ocan_mib` with its
actual replaced by a constant, `open` or a fixed generic.

| Result | Faults |
| --- | --- |
| Detected | 38: the control and the bit timing, the re-enable, the transmit PDO requests and data, the receive PDO data and events, the SYNC, the completions of the transmit PDOs, the application port in both directions (valid, data, index, abort code), the time request, the coarse time and the time set event, the NMT state, the NODE-ID, the reset communication event, the master heartbeat presence, the active bus, the missing master heartbeat, Ctoggle, the CRC errors, the dominant timeout events and state, the parameter copy and NODE-ID errors, the three injection inputs, the interrupt, and the reported bus access, minimal set and time PDOs |
| Not detectable at the ports | 2, see below |

- `App_ReqReady` of the core constant '1': `ocan_od` holds one request at a time and waits in `AppWait_s` for its
  response (OD-AP-02); the mailbox is pending only during that wait, so `App_ReqReady` = '0' never meets
  `App_ReqValid` = '1' with `ocan_od` as the partner. The ready of the mailbox is verified in the bench of
  `ocan_mib` (TC-MB-12), whose model of the port presents requests against it.
- The reset of the register interface without its synchroniser (`Rst` directly): the release of `Rst` is asynchronous to
  `Clk`, and only the metastability of the release differs, which a simulation cannot show; covered by design review
  (architecture, section 2).

The fault "Ctrl_Enable of the core constant '1'" was found undetected in the first run: TC-AX-01 checked only that the
node sent no frame before the enable. With the fault the node ran at the bit timing of the generics; the test now also
requires that the model nodes see no error and that the transmit error counter stays 0, and the fault is detected.

## 3. Generic ranges

The generics of `ocan_core` and `ocan_mib` are verified by their benches and in `lint/synth_check.py` (verification
reports of `ocan_core` and `ocan_mib`, section 3). `ocan_axi` passes them unchanged; the network bench simulates both
bus access architectures, the clause 6 slave and the minimal set, with and without the time PDOs, both values of
`AutoEnable_g` and of `ErrInjRegs_g`.

## 4. Coverage

`ocan_axi.vhd` connects `ocan_core`, `ocan_mib` and `olo_base_reset_gen` and has no statement, branch or condition
of its own, so QuestaSim counts no item in it. The coverage of the instances, merged over all benches including
this one, is in [docs/coverage.md](../../../docs/coverage.md); the connections are verified by the deliberate
faults of section 2.
