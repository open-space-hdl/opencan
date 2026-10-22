# ocan_pkg: Architecture and Design Description

## 1. Contents

`ocan_pkg` is one VHDL package in `src/ocan_pkg.vhd`, compiled into the library `opencan`. It has no package body.

| Declaration | Kind | Value | Used by |
| --- | --- | --- | --- |
| `NmtState_t` | Subtype | `std_logic_vector(1 downto 0)` | `ocan_nmt` (`Stat_State`), `ocan_redundancy` (`Nmt_State`) |
| `NmtInit_c` | Constant | "00" | Initialisation: `Init_s`, `ResetApp_s`, `ResetComm_s`, `WaitId_s` of `ocan_nmt` |
| `NmtPreOp_c` | Constant | "01" | Pre-operational |
| `NmtOp_c` | Constant | "10" | Operational |
| `NmtStopped_c` | Constant | "11" | Stopped |

## 2. Rules

- The package holds definitions that two or more modules share; a definition used by one module stays in that
  module.
- A change of a value is a change of the interface between the modules that use it: their specifications and
  benches are updated together with the package.
