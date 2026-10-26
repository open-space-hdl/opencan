# ocan_mib: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_mib*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_mib_tb` | 19 | 43 | 43 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): TC-MB-01, TC-MB-02,
TC-MB-18 and TC-MB-19 in all six configurations, TC-MB-16 in `errinj` and `gen_max`, TC-MB-11 in `gen_max`,
`gen_min`, `n00` and `n22`, the other test cases in `default`. In every clock cycle of every run the reference model
predicted every output towards the core (`Ctrl_*`, `Cfg_*`, `Tpdo_Req`, `Tpdo_Data` of all four PDOs, the application
port, `Time_Req`, the 558 + 14 bits of the error injection and their valid inputs, the link injections) and `Irq`; no
output differed. Every read word equalled the word of the model, and every read and write response was OKAY. The
model keeps the registers as its own variables and takes the timing of the slave from the ports only (the write in the
clock cycle in which `BValid` rises, the read in the clock cycle after the read address handshake); its agreement in
every cycle confirms the timing of section 9 of the architecture.

TC-MB-19 ran 600 random accesses per configuration to every address of the 9-bit space, with random events on every
input (each with a probability of 1 in 6 per clock cycle), random status, PDO data and time, and random requests of
the application port with SENDs at random times; the test requires that the model checked more than 200 read words
of the run. TC-MB-01
read and wrote every address, so every unused address read zero after address-dependent patterns.

QuestaSim: runs with the release (one QuestaSim batch, with and without code coverage).

`python lint/synth_check.py` (TC-MB-20): the six configurations of section 2 synthesise with GHDL without an inferred
latch; `BusAccess_g` = "Dual" and `Sjw_g` = 3 with `Tseg2_g` = 2 stop the elaboration with the message of the module.

`python tools/regmap.py --check` passes (TC-MB-21): the VHDL package, the register map and the C header match
`ocan_regs.yml`; the CI also requires that a stale register map fails the check.

## 2. Deliberate faults

36 faults of the RTL were each simulated with the tests that must detect them: all 36 were detected.

| Area | Faults | Detected by |
| --- | --- | --- |
| Control and bit timing: written while enabled, no range check, Sjw above Tseg2, Tseg1 of 1, Sjw of 5, APP_ENABLE from another bit, a pulse not ended, the reset value of ENABLE, the time request from another bit, CFG_REFUSED not set | 10 | TC-MB-02, TC-MB-03, TC-MB-04, TC-MB-15 |
| Flags and interrupt: the clear wins over the event of its cycle, a flag register not sticky, a clear by a write of zero, two inputs exchanged, the interrupt one clock cycle late, IRQ_STATUS from another register | 6 | TC-MB-06, TC-MB-07 |
| Counters: wrap at 255, the event of the clearing cycle lost, a write that clears the other register | 3 | TC-MB-08 |
| Status and identification: a controller read from the other one, a generic field from another generic | 2 | TC-MB-01, TC-MB-05 |
| PDOs: LO taken at the read of LO, REQUEST without the copy, UPDATE with a request, absent PDOs writable, HI of the next PDO | 5 | TC-MB-09, TC-MB-10, TC-MB-11 |
| Mailbox: a request taken with the mailbox off, SEND without a pending request, the time-out or a cleared APP_ENABLE that does not end the request, abort code 0 with the mailbox off, `App_ReqReady` while pending | 6 | TC-MB-12, TC-MB-13, TC-MB-14 |
| Time: the fine time taken at every read | 1 | TC-MB-15 |
| Error injection: window w1 ignored, the NMT valid for the od target, the registers without `ErrInjRegs_g` | 3 | TC-MB-16, TC-MB-17 |

The fault "the fine time taken at every read" was found undetected in the first run: TC-MB-15 read TIME_FINE only
directly after TIME_COARSE. The test case now reads another register in between and TIME_FINE twice; the fault is
detected.

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `BusAccess_g` | "Selective", "Parallel" | both | both; "Dual" rejected |
| `MinimalSet_g`, `TimePdos_g`, `AutoRecover_g`, `AutoEnable_g`, `ErrInjRegs_g` | true, false | both | both |
| `NumRpdo_g`, `NumTpdo_g` | 0 to 4 | 0, 1, 2, 3, 4 each | 0, 1, 2, 3, 4 each |
| `FineBits_g` | 0 to 24 | 0, 24 | 0, 24 |
| `SyncStages_g` | 2 to 4 | 2, 4 | 2, 4 |
| `DominantLimit_g` | 13 to 1023 | 13, 32, 1023 | 13, 32, 1023 |
| `ClkFrequency_g` | 1000000 to 2147483647 | 1000000, 100000000, 2147483647 | the same |
| `Prescaler_g` | 1 to 1023 | 1, 4, 1023 | the same |
| `Tseg1_g` | 2 to 31 | 2, 18, 31 | the same |
| `Tseg2_g` | 2 to 15 | 2, 6, 15 | the same |
| `Sjw_g` | 1 to min(4, `Tseg2_g`) | 1, 4 | 1, 4; 3 with `Tseg2_g` = 2 rejected |

The generics of `ocan_core` change only the words of GENERICS, DOMINANT_LIMIT and CLK_FREQUENCY in `ocan_mib`;
`NumRpdo_g`, `NumTpdo_g` and `ErrInjRegs_g` change the structure.

## 4. Coverage

Code coverage with QuestaSim follows with the release (one QuestaSim batch); `docs/coverage.md` will list the result.
