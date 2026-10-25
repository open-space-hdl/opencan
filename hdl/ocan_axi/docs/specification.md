# ocan_axi: Specification

## 1. Overview

`ocan_axi` is the top level of OpenCAN for a processor system (decision D6 of the
[architecture](../../../docs/architecture.md)): the slave node `ocan_core` with the register interface `ocan_mib` on an
AXI4-Lite slave. The PDOs, the objects of the user logic, the local time, the status and the events of the node are
reached through the registers of `ocan_mib`; a system without a processor, or one that needs the native ports, uses
`ocan_core` directly. Every protocol function is the function of `ocan_core` and its blocks, every register function
the function of `ocan_mib`; `ocan_axi` adds the reset synchroniser of the register interface and connects the two.

| Block | Entity | Function |
| --- | --- | --- |
| AX-1 | `olo_base_reset_gen` | Synchronises the release of the asynchronous reset input for the register interface (triplicated synchroniser) |
| AX-2 | `ocan_core`, `ocan_mib` | The node and its register interface, connected port by port |

`ocan_axi` runs in one clock domain.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | ECSS |
| --- | --- | --- |
| AX-IF-01 | `ocan_axi` shall run in one clock domain. The reset input shall be asynchronous and high-active and the hardware reset of the node (CO-IF-01) and of the register interface; the release for the register interface shall be synchronised with a triplicated synchroniser. | 8.3.2a |
| AX-IF-02 | `ocan_axi` shall provide the AXI4-Lite slave of `ocan_mib` (MB-IF-01) and its interrupt output (MB-IF-03). | none |
| AX-IF-03 | `ocan_axi` shall have the transceiver ports of both buses and the NODE-ID pins with their complement of `ocan_core` (CO-IF-02, CO-IF-03). | 5.3, 6.10e, 8.2 |

### 2.2 Integration (AX-2)

| ID | Requirement | ECSS |
| --- | --- | --- |
| AX-CN-01 | Every port of `ocan_core` other than the clock, the reset, the transceiver ports and the NODE-ID pins shall be connected to the port of the same name of `ocan_mib`. | 5.6.2c, 6.2a, 6.8a, 7.2.2f |
| AX-CN-02 | The generics of `ocan_core` that `ocan_mib` reports (MB-ID-02) shall be those of `ocan_axi`, so that GENERICS, DOMINANT_LIMIT and CLK_FREQUENCY describe the instantiated node. | none |
| AX-CN-03 | With `AutoEnable_g` = true and the bit timing of the generics, the node shall start without any register access, as `ocan_core` with `Ctrl_Enable` at its default value; with `AutoEnable_g` = false the node shall stay off the bus until the software sets CONTROL.ENABLE. | 6.10f, 8.3.2a |
| AX-RS-01 | The register accesses and the operation of the node shall not depend on the order in which the reset synchroniser of `ocan_core` and that of the register interface release: an access in the first clock cycles after the release shall complete with its effect, and a frame on the bus at the release shall not be disturbed. | 8.3.2a |

## 3. Error conditions

| Condition | Response |
| --- | --- |
| Register access during the reset | Not answered until the release (the slave is in reset); then executed |
| Frame on the bus at the release | The controllers join the bus only after 11 recessive bits (`olo_intf_can`); the frame is not disturbed |
| Software enables the node without a valid bit timing | Refused writes of BIT_TIMING set CFG_REFUSED (MB-CT-04); the reset values of the generics stay |

## 4. Configuration parameters

The generics of `ocan_core` with its names, defaults and ranges (user guide, section 2), and of `ocan_mib`:

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `AutoEnable_g` | true | true, false | Reset value of CONTROL.ENABLE |
| `Prescaler_g`, `Tseg1_g`, `Tseg2_g`, `Sjw_g` | 4, 18, 6, 4 | as `ocan_mib` | Reset value of BIT_TIMING |
| `ErrInjRegs_g` | false | true, false | The error injection registers |

## 5. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| 8.3.2a | `Rst` of `ocan_axi` is the hardware reset of the node. `ocan_core` synchronises its release itself (CO-1); `ocan_axi` synchronises it a second time for the register interface (AX-1), with the same number of stages. The two releases can differ by one clock cycle (each synchroniser resolves the asynchronous edge on its own); the architecture shows why the order does not matter, TC-AX-02 checks it at the ports. |
