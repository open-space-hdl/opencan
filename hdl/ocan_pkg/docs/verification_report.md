# ocan_pkg: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_pkg*"`.

| Testbench | Test cases | Runs | Passed |
| --- | --- | --- | --- |
| `ocan_pkg_tb` | 1 | 1 | 1 |

QuestaSim: not run yet; it runs with the first release of OpenCAN.

## 2. Summary

The constants of `ocan_pkg` equal the values of the specification (TC-PKG-01). The direct testbench of `ocan_nmt`
compares `Stat_State` with these constants in every cycle. VSG reports no errors and no warnings.
