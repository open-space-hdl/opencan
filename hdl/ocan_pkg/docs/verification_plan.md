# ocan_pkg: Verification Plan

## 1. Overview

The testbench compares every constant of `ocan_pkg` with the value of the specification, written in the testbench as
a literal. A changed constant therefore fails the test, while a comparison of the package with itself could not.

## 2. Test configuration

| Testbench | Harness | Content |
| --- | --- | --- |
| `ocan_pkg_tb` | none (no entity) | VUnit runner with the UVVM checks |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_nmt_state_encoding` (TC-PKG-01) | `NmtState_t` has two bits; `NmtInit_c`, `NmtPreOp_c`, `NmtOp_c` and `NmtStopped_c` equal "00", "01", "10" and "11" | PKG-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PKG-01 | TC-PKG-01 |

The use of the encoding by `ocan_nmt` is verified by its testbench, which checks `Stat_State` against these values in
every cycle.
