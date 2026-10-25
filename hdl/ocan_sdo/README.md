# ocan_sdo

SDO server of OpenCAN: the request decoder and the protocol of the expedited and the segmented transfer (SD-1),
the access of the object dictionary with a buffer of 8 bytes (SD-2), and the reply with its transmit handshake
(SD-3).

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |
| [architecture.md](docs/architecture.md) | Open transfer, processing of a request, decoder, ports |
| [verification_plan.md](docs/verification_plan.md) | Test cases |
| [verification_report.md](docs/verification_report.md) | Results |

## Tests

```shell
python run.py "*ocan_sdo*"
```

| File | Content |
| --- | --- |
| `src/ocan_sdo.vhd` | The SDO server: decoder and protocol checks, the open transfer with its buffer, the access of `ocan_od`, the reply |
| `tb/ocan_sdo_tb.vhd` | Direct testbench: requests cycle by cycle, a responder of the transmit handshake, an object model at the access interface, a reference model of the server written from \[CiA301\] and the specification, checked in every cycle |
| `tb/ocan_sdo_th.vhd` | Harness of the direct testbench: the clock and `ocan_sdo` |
| `tb/ocan_sdo_net_tb.vhd` | Network testbench: a model node as the SDO client on bus A and on bus B |
| `tb/ocan_sdo_net_th.vhd` | Harness of the network testbench: `ocan_sdo` with `ocan_od`, `ocan_dispatch`, `ocan_link` and the CAN network model |
| `tb/vunit_config.py` | Configurations of both testbenches |
