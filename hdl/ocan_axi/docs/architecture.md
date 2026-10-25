# ocan_axi: Architecture and Design Description

## 1. Block diagram

![Block diagram of ocan_axi: the reset generator olo_base_reset_gen for the register interface, ocan_core with the
transceiver ports and the NODE-ID pins, and ocan_mib with the AXI4-Lite slave and the interrupt, connected port by
port](img/ocan_axi_arch.drawio.svg)

`ocan_axi` instantiates `ocan_core`, `ocan_mib` and `olo_base_reset_gen`. Every port of `ocan_core` other than `Clk`,
`Rst`, `Can_*` and `Pin_*` connects to the port of the same name of `ocan_mib` (AX-CN-01): the outputs of the core to
the inputs of the register interface and the control, bit timing, PDO, application port, time request and error
injection outputs of the register interface to the inputs of the core. The generics of the core go to both
instances, so the identification registers describe the instantiated node (AX-CN-02).

## 2. Reset

`Rst` is asynchronous and high-active. `ocan_core` synchronises its release with its own `olo_base_reset_gen`
(CO-1); `ocan_axi` synchronises it a second time for `ocan_mib` and `olo_axi_lite_slave`, with the same generics
(`RstPulseCycles_g` = 3, `SyncStages_g` of the core, `SyncTmr_g` = true). Both outputs assert while `Rst` is '1' and
release after the three stages of the reset chain and the `SyncStages_g` stages of the synchroniser; because each
synchroniser resolves the asynchronous edge of `Rst` on its own, the two releases can differ by one clock cycle. The
order does not matter at the ports:

| Released first | In the cycle of the difference | Why nothing is lost |
| --- | --- | --- |
| `ocan_core` | `ocan_mib` drives its reset values: `Ctrl_Enable` = `AutoEnable_g`, the bit timing of the generics, no request, the application port at its default values, no injection | These are the values that `ocan_mib` drives after its release, so the core sees the same inputs. No event of the core occurs in that cycle: `ocan_nmt` waits two clock cycles in `Init_s` before its first event, and the controllers integrate for 11 recessive bits before they take part in the bus. |
| `ocan_mib` | The register interface answers accesses while the core is still in reset | An AXI4-Lite write takes effect at the earliest in the third clock cycle after the write address (address, data, write), so no register write and no command pulse reaches the core before its release; levels such as CONTROL.ENABLE are held and seen by the core when it starts. A read samples the status in the clock cycle after its read address, when the core runs. |

TC-AX-02 releases the reset with a read and a write queued for the first cycles and with a frame of a model node on
the bus at four positions of the frame; the accesses complete with their effect, the frame ends without an error and
the node joins the bus after it.

## 3. Ports of ocan_axi

| Signal | Direction | Width | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | In | 1 | Clock; asynchronous high-active reset, the hardware reset of the node |
| `S_AxiLite_*` | | | AXI4-Lite slave of `ocan_mib`: `ArAddr`, `AwAddr` 9 bits, `WData`, `RData` 32 bits, `WStrb` 4 bits (not used), `BResp`, `RResp` 2 bits, handshakes |
| `Irq` | Out | 1 | Interrupt of `ocan_mib` |
| `Pin_NodeId`, `Pin_NodeIdCode` | In | 7, 7 | NODE-ID pins and their complement (CO-IF-03) |
| `Can_Tx`, `Can_TxEn`, `Can_Rx` | Out, Out, In | 2, 2, 2 | Transceivers of bus A (index 0) and bus B (index 1); `Can_Rx` defaults to "11" |

## 4. Configuration parameters

The generics of `ocan_core` (user guide, section 2) and `AutoEnable_g`, `Prescaler_g`, `Tseg1_g`, `Tseg2_g`, `Sjw_g`
and `ErrInjRegs_g` of `ocan_mib`, with their names, defaults and ranges. The generic checks of both instances apply.

## 5. Protection

`ocan_axi` adds the reset synchroniser of the register interface: three synchroniser chains and a majority voter
(`SyncTmr_g` = true), as every crossing of the family. All other protection is that of `ocan_core` and `ocan_mib`
(user guide, section "Protection scope").
