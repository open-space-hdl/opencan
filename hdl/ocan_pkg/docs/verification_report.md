# ocan_pkg: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_pkg*"`.

| Testbench | Test cases | Runs | Passed |
| --- | --- | --- | --- |
| `ocan_pkg_tb` | 1 | 1 | 1 |

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

The constants of `ocan_pkg` equal the values of the specification (TC-PKG-01). The direct testbench of `ocan_nmt`
compares `Stat_State` with these constants in every cycle. VSG reports no errors and no warnings.
