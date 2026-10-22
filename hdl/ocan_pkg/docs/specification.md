# ocan_pkg: Specification

## 1. Overview

`ocan_pkg` is the VHDL package with the definitions that several OpenCAN modules share. It holds no logic. A
definition enters the package when a second module needs it, so that both use one source.

| Block | Entity | Function |
| --- | --- | --- |
| PK-1 | `ocan_pkg` (package) | Encoding of the NMT state between `ocan_nmt` and `ocan_redundancy` |

The CiA 301 column names the section of \[CiA301\] that defines the states.

## 2. Requirements

| ID | Requirement | CiA 301 | ECSS |
| --- | --- | --- | --- |
| PKG-01 | The package shall define the encoding of the NMT state that `ocan_nmt` provides as status and passes to `ocan_redundancy`, two bits: "00" Initialisation, "01" Pre-operational, "10" Operational, "11" Stopped. | 7.3.2.1 | none |

## 3. Error conditions

None: the package defines constants only.

## 4. Configuration parameters

None.
