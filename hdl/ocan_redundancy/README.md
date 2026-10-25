# ocan_redundancy

Bus monitoring and reconfiguration of OpenCAN for a slave node: the consumer of the master heartbeat (RM-1) and the
bus selection process with the start-up on Bdefault, the toggling mechanism, Ctoggle and the update of Bdefault (RM-2).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, state machine |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_redundancy*"
```

| File | Content |
| --- | --- |
| `src/ocan_redundancy.vhd` | The bus monitoring and the bus selection process |
| `tb/ocan_redundancy_tb.vhd` | Direct testbench: per-bus events and parameters cycle by cycle, models of `ocan_nmt` and `ocan_link`, a reference model checked in every cycle |
| `tb/ocan_redundancy_th.vhd` | Harness of the direct testbench: clock and `ocan_redundancy` |
| `tb/ocan_redundancy_net_tb.vhd` | Network testbench: the master moves to the other bus, the master on the other bus during a bus selection, broken and stuck buses |
| `tb/ocan_redundancy_net_th.vhd` | Harness of the network testbench: `ocan_redundancy`, `ocan_nmt`, `ocan_dispatch`, `ocan_link`, the millisecond tick and the CAN network model with faults |
| `tb/vunit_config.py` | Configuration `minimal` for the minimal set; selective and parallel bus access of the network testbench |
