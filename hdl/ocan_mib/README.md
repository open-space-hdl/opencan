# ocan_mib

Register interface of OpenCAN for a processor system: the AXI4-Lite slave and the register file (MB-1), the event and
error flags with the interrupt (MB-2), the PDO data, the mailbox of the application objects and the local time (MB-3),
and the error injection (MB-4). The top level `ocan_axi` connects it to the native ports of `ocan_core`.

| Document | Content |
| --- | --- |
| [specification.md](docs/specification.md) | Requirements |

| File | Content |
| --- | --- |
| `regs/ocan_regs.yml` | Register map: the one description from which `tools/regmap.py` generates the VHDL package, the register map documentation and the C header |
