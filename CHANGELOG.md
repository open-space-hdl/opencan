# Changelog

The notable changes of OpenCAN. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, generics or the object dictionary, a minor version for a feature and a
patch version for a fix.

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
