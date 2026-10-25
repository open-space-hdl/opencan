# ocan_pkg

Definitions shared by the OpenCAN modules: the encoding of the NMT state between `ocan_nmt` and `ocan_redundancy`
(PK-1).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Declarations |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_pkg*"
```

| File | Content |
| --- | --- |
| `src/ocan_pkg.vhd` | The package |
| `tb/ocan_pkg_tb.vhd` | Testbench: the constants against the values of the specification |
