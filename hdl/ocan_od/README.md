# ocan_od

Object dictionary of OpenCAN: the object table and its access rules (OD-1), the protected parameters (OD-2), the
parameters to the blocks and the error register (OD-3), and the application port to the objects of the device
(OD-4).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Access path, protected parameters, application port, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_od*"
```

| File | Content |
| --- | --- |
| `src/ocan_od.vhd` | The object dictionary: decoder and rule check, two copies of the parameters, outputs, application port |
| `tb/ocan_od_tb.vhd` | Direct testbench: accesses cycle by cycle, a responder of the application port, a reference model of the object dictionary written from the specification, checked in every cycle |
| `tb/ocan_od_th.vhd` | Harness: the clock and `ocan_od`, with the application port connected or at its default inputs |
| `tb/vunit_config.py` | Configurations of the generics, the minimal set and the unconnected application port |
