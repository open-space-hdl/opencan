# ocan_link

Access of OpenCAN to the nominal and the redundant bus (ECSS-E-ST-50-15C clauses 5.4, 5.6 and 8.2): one or two
`olo_intf_can` (LK-1), the bus selector (LK-2), the bus switch sequencer (LK-3), the received frames as events
(LK-4), the transmit path (LK-5) and a dominant monitor per controller (LK-6).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Blocks, ports, state machine |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_link_tb*"
```

| File | Content |
| --- | --- |
| `tb/ocan_link_tb.vhd` | Testbench: one run block per test case of the verification plan |
| `tb/ocan_link_th.vhd` | Harness: clock, `ocan_link` and the CAN network model with two model nodes on each bus |
| `tb/vunit_config.py` | Configurations: every test runs in the configurations of the verification plan |

The CAN network model (`tb/ocan_tb_can_*`, `tb/ocan_tb_net*_pkg`) is shared by all OpenCAN testbenches; its
self-test is `tb/ocan_tb_can_model_tb.vhd`.
