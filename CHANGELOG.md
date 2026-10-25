# Changelog

The notable changes of OpenCAN. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, generics or the object dictionary, a minor version for a feature and a
patch version for a fix.

## [Unreleased]

- **Added:** the register interface `ocan_mib`: an AXI4-Lite slave with the control and the bit timing (written only
  while disabled and in range), the status of the node and of both controllers, sticky event and error flags with an
  interrupt, 8-bit error counters, the PDO data, a mailbox for the objects of the user logic, the local time and the
  error injection (`ErrInjRegs_g`). Register map version 1 (ID 0x4F434101), generated with the C header `sw/ocan_regs.h`
  by `tools/regmap.py`.
- **Added:** the top level `ocan_axi` (`ocan_core` with `ocan_mib`) for a processor system; `ocan_core` keeps its
  ports.
- **Changed:** Open Logic 4.7.0-ft.11 (from 4.7.0-ft.9). No Open Logic file that OpenCAN uses changes; no port,
  generic or object of OpenCAN changes.

## [0.1.0] - 2026-10-25

First release: the slave node of ECSS-E-ST-50-15C on a nominal and a redundant CAN bus, with the data link
`ocan_link` (selective or parallel bus access, bus switch, dominant monitor), the frame dispatcher `ocan_dispatch`,
the network management `ocan_nmt` (NMT state machine, boot-up, heartbeat, NODE-ID check), the bus redundancy
management `ocan_redundancy` (bus selection at start-up, master heartbeat consumer, bus toggling, update of
Bdefault), the time distribution `ocan_time` (local SCET, Spacecraft Time PDO, Local Time PDO, sample at the SYNC),
the object dictionary `ocan_od`, the SDO server `ocan_sdo`, the PDOs `ocan_pdo` and the top level `ocan_core`. The
CAN protocol comes from the controller `olo_intf_can` of Open Logic 4.7.0-ft.9. TRL 3 for phases a to c: verified
by simulation (GHDL and QuestaSim, code coverage). The AXI4-Lite register wrapper and the hardware test follow in
phase d.
