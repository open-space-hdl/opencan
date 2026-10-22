# OpenCAN Roadmap

This page tracks the development phases and the state of every module. A module is done when its verification report
is written and its regression is green.

## Technology readiness

The core is in development and has no technology readiness level yet. The
[TRL page](https://openspacehdl.org/trl/) explains what the levels mean for an IP core.

| Next level | What is needed | State |
| --- | --- | --- |
| TRL 3 | Every module of the phases below implemented and fully verified by simulation (GHDL and QuestaSim, code coverage closed), traceability matrix complete | Open |
| TRL 4 | Synthesis and timing closure on a target FPGA; hardware test on a redundant CAN network with transceivers; hardware test plan and test report | Open |

## Development phases

| Phase | Content | State |
| --- | --- | --- |
| a | Architecture: scope, architecture decisions, traceability matrix | Done |
| b | Data link on the nominal and the redundant bus, bus redundancy management and monitoring | Done |
| c | CANopen services and time distribution | In work |
| d | AXI4-Lite register wrapper; hardware test on a redundant CAN network | Open |

## Modules

Every module has a specification, an architecture, a verification plan and a verification report in
`hdl/<module>/docs/`. The figures come from the verification reports: the GHDL regression of the module, and the
deliberate faults of the RTL that were each simulated with the tests that must detect them. A fault that changes the
behaviour only after an upset, which the ports cannot inject, is covered by design review. QuestaSim runs once over
all modules, with and without code coverage, for the first release.

| Module | Phase | Function | GHDL regression | Deliberate faults |
| --- | --- | --- | --- | --- |
| `ocan_pkg` | b | Definitions that several modules share | 1 of 1 runs pass | - |
| `ocan_link` | b | Access to the nominal and the redundant bus, bus switch, dominant monitor | 32 of 32 runs pass | 18, all detected |
| `ocan_dispatch` | b | Receive filter by COB-ID, bus gate, transmit arbitration | 27 of 27 runs pass | 23, all detected |
| `ocan_nmt` | b | NMT slave state machine, boot-up, heartbeat producer, NODE-ID check | 21 of 21 runs pass | 32: 31 detected, 1 by design review |
| `ocan_redundancy` | b | Bus selection at start-up, master heartbeat consumer, bus toggling, update of Bdefault | 30 of 30 runs pass | 40: 37 detected, 3 by design review |
| `ocan_time` | c | Local SCET, Spacecraft Time PDO consumer, Local Time PDO producer, sample at SYNC | 122 of 122 runs pass | 33: 32 detected, 1 by design review |
| `ocan_od` | c | Object dictionary of the communication profile and of clause 8, object access port | 36 of 36 runs pass | 51, all detected |
| `ocan_sdo` | c | SDO server | Open | Open |
| `ocan_pdo` | c | Receive and transmit PDOs, transmission types, SYNC consumer | Open | Open |
| `ocan_core` | c | Top level, generics and ports | Open | Open |
