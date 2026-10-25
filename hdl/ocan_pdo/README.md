# ocan_pdo

PDO block of OpenCAN: the SYNC consumer (PD-1), the receive PDOs with their data to the user logic at once or at the
next SYNC (PD-2), and the transmit PDOs with their triggers, the sample of the data and the transmit handshake
(PD-3).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | SYNC, receive PDOs, triggers and handshake of the transmit PDOs, protection, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_pdo*"
```

| File | Content |
| --- | --- |
| `src/ocan_pdo.vhd` | The PDO block: the SYNC check, the receive PDOs with the data held for the next SYNC, the triggers and the transmit handshake of every transmit PDO |
| `tb/ocan_pdo_tb.vhd` | Direct testbench: events, types and NMT inputs cycle by cycle, a responder of the transmit handshake per transmit PDO, data of the user logic that change in every cycle, a reference model of the PDO block written from \[CiA301\] and the specification, checked in every cycle |
| `tb/ocan_pdo_th.vhd` | Harness of the direct testbench: the clock and `ocan_pdo` |
| `tb/ocan_pdo_net_tb.vhd` | Network testbench: a model node as NMT master, SYNC producer and peer of the PDOs on bus A and on bus B, the clause 6 slave and the minimal set |
| `tb/ocan_pdo_net_th.vhd` | Harness of the network testbench: `ocan_pdo` with `ocan_nmt`, `ocan_od`, `ocan_time`, `ocan_dispatch`, `ocan_link` and the CAN network model |
| `tb/vunit_config.py` | Configurations of both testbenches |
