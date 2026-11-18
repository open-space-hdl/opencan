# Changelog

The notable changes of OpenCAN. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, generics or the object dictionary, a minor version for a feature and a
patch version for a fix.

## [0.2.1] - 2026-11-18

Open Logic FT 4.8.0-ft.2. No port, generic, object or register of OpenCAN changes. No source or testbench of
OpenCAN changed since 0.2.0, and the Open Logic files that OpenCAN uses are identical at both tags, so the QuestaSim
runs and the code coverage of 0.2.0 apply to this release.

- **Changed:** Open Logic 4.8.0-ft.2 (1f4a6c3), based on Open Logic 4.8.0 (from 4.7.0-ft.11). The 13 Open Logic files
  that the sources and the testbenches of OpenCAN use, `olo_intf_can` among them, are identical in both tags.
- **Changed:** the documentation names the path to TRL 4: the hardware test on a redundant CAN network as part of a
  reference system of the family (README, roadmap, architecture, conventions).
- **Fixed:** the documentation site builds with Python-Markdown 3.11.3 (heading hook of `tools/docs`).

## [0.2.0] - 2026-10-26

The register interface of phase d: `ocan_mib` and the top level `ocan_axi` connect the node to a processor system
over AXI4-Lite. TRL 3 for phases a to c and for the register interface of phase d: verified by simulation (GHDL and
QuestaSim, code coverage). The hardware test on a redundant CAN network follows in phase d.

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
