# ocan_core

Top level of OpenCAN: the slave node of ECSS-E-ST-50-15C with the eight blocks of the architecture, the reset
synchroniser and the millisecond tick (CO-1 to CO-3), and the applicability of \[CiA301\] of clause 11.1.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Reset and tick, connections of the blocks, configurations, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

The [user guide](../../docs/user_guide.md) describes the integration of the core.

## Tests

```shell
python run.py "*ocan_core*"
python lint/synth_check.py
```

| File | Content |
| --- | --- |
| `src/ocan_core.vhd` | The top level: the reset synchroniser, the millisecond tick, the eight blocks and their connections, the generic checks |
| `tb/ocan_core_net_tb.vhd` | Network testbench: the model node M1 of the active bus as Redundancy Master, NMT master, SYNC and time producer, SDO client and peer of the PDOs, M2 for acknowledges and disturbing frames, models of the user logic at the PDO port and at the application port, checkers of the frames of the node in every test |
| `tb/ocan_core_net_th.vhd` | Harness of the network testbench: the clock and `ocan_core` with the parameters of the verification plan on the CAN network model with two model nodes on each bus |
| `tb/vunit_config.py` | The four configurations of the network testbench |
