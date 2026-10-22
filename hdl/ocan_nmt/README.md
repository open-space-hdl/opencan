# ocan_nmt

Network management slave of OpenCAN: the NODE-ID check with its protection code (NM-1), the NMT state machine with
the node control services and the service enables (NM-2), and the boot-up message and the heartbeat producer (NM-3).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, state machines |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_nmt*"
```

| File | Content |
| --- | --- |
| `src/ocan_nmt.vhd` | The NMT slave |
| `tb/ocan_nmt_tb.vhd` | Direct testbench: inputs cycle by cycle, a responder like `ocan_dispatch`, a reference model checked in every cycle |
| `tb/ocan_nmt_th.vhd` | Harness of the direct testbench: clock and `ocan_nmt` |
| `tb/ocan_nmt_net_tb.vhd` | Network testbench: boot-up message, heartbeats, NMT messages, node guarding request, missing acknowledge |
| `tb/ocan_nmt_net_th.vhd` | Harness of the network testbench: `ocan_nmt`, `ocan_dispatch`, `ocan_link`, the millisecond tick and the CAN network model |
| `tb/vunit_config.py` | Configuration `minimal` for the minimal set |
