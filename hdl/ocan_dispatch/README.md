# ocan_dispatch

Classification of the received frames of OpenCAN by COB-ID (DS-1), the bus gate with the NMT message of the inactive
bus (DS-2), the transmit arbitration of the protocol blocks with `olo_base_arb_rr` (DS-3) and the protection of the
COB-IDs by two copies (DS-4).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, state machine |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_dispatch*"
```

| File | Content |
| --- | --- |
| `tb/ocan_dispatch_tb.vhd` | Direct testbench: link events cycle by cycle, a link responder, one request process per source |
| `tb/ocan_dispatch_th.vhd` | Harness of the direct testbench: clock and `ocan_dispatch` |
| `tb/ocan_dispatch_net_tb.vhd` | Network testbench: back-to-back frames and the transmit wait under load |
| `tb/ocan_dispatch_net_th.vhd` | Harness of the network testbench: `ocan_dispatch`, `ocan_link` and the CAN network model |
| `tb/vunit_config.py` | Configurations: every number of PDOs, without time PDOs, without SDO server |
