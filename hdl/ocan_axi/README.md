# ocan_axi

Top level of OpenCAN for a processor system: the slave node `ocan_core` with the register interface `ocan_mib` on an
AXI4-Lite slave (AX-2) and the reset synchroniser of the register interface (AX-1). The software runs the node through
the registers of [the register map](../ocan_mib/docs/register_map.md); the user guide describes the programming
sequence.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Structure, the two reset synchronisers and why their order does not matter, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_axi*"
```

| File | Content |
| --- | --- |
| `src/ocan_axi.vhd` | The top level: `olo_base_reset_gen`, `ocan_core` and `ocan_mib`, connected port by port |
| `tb/ocan_axi_net_tb.vhd` | Network testbench: the software through the AXI-Lite VVC of UVVM, the CAN network model as master and peers on bus A and bus B |
| `tb/ocan_axi_net_th.vhd` | Harness of the network testbench: `ocan_axi`, the AXI-Lite VVC master, the buses and the model nodes |
| `tb/vunit_config.py` | Configurations of the testbench |
