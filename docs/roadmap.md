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
| a | Architecture: scope, interpretation of ECSS-E-ST-50-15C, traceability matrix | In work |
| b | Data link on the nominal and the redundant bus, bus redundancy management and monitoring | Open |
| c | CANopen services and time distribution | Open |
| d | Hardware test on a redundant CAN network | Open |
