# ocan_time

Time consumer of OpenCAN: the local spacecraft elapsed time (TM-1), its sample at every SYNC (TM-2), the setting from
the Spacecraft Time PDO with the basic or the high-resolution protocol (TM-3) and the Local Time PDO (TM-4).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, counter, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_time*"
```

| File | Content |
| --- | --- |
| `src/ocan_time.vhd` | The time consumer: local SCET, SYNC sample, Spacecraft Time PDO, Local Time PDO |
| `tb/ocan_time_tb.vhd` | Direct testbench: events cycle by cycle, a responder like `ocan_dispatch`, a reference model of the local time in closed form, checked in every cycle |
| `tb/ocan_time_th.vhd` | Harness of the direct testbench: the clock of `ClkFrequency_g` and `ocan_time` |
| `tb/ocan_time_net_tb.vhd` | Network testbench: byte order on the bus, the high-resolution setting, the latency of the SYNC sample on both buses |
| `tb/ocan_time_net_th.vhd` | Harness of the network testbench: `ocan_time`, `ocan_dispatch`, `ocan_link`, the millisecond tick and the CAN network model |
| `tb/vunit_config.py` | Configurations of the clock frequency and of the width of the fine time |
