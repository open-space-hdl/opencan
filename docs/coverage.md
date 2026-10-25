# OpenCAN: Code Coverage

## 1. Method

The code coverage of the OpenCAN sources is measured with QuestaSim (Questa Pro Microchip Edition 2024.3) over the
complete regression of `run.py`, the same test set that GHDL runs, at a time resolution of 1 fs:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches are not instrumented; Open Logic
is verified by its own regression. `run.py` merges the coverage of all tests into `coverage/coverage.ucdb` and writes
the reports `coverage/coverage_report.txt` (details per instance) and `coverage/coverage_byfile.txt`; a design unit
is covered when any of its instances in any test covers it.

Closure rules:

- Statements, branches, state machine states and transitions: every item is covered by a test or listed with its
  justification in section 4.
- Conditions and expressions: reported, not a closure criterion. Focused expression coverage requires every input
  term to change the result while the other terms do not mask it; some combinations cannot occur by construction.
  Every miss was reviewed for untested behaviour (section 3); the remaining ones are listed with their reason in
  section 4.
- `-- coverage off` / `-- coverage on` enclose the `when others` branch of the nine case statements on a state
  register whose enumerated type lists every state (`ocan_dispatch` `r.TxState`, `ocan_link` `r.State`, `ocan_nmt`
  `r.Nmt` and `r.Tx`, `ocan_od` `r.App`, `ocan_pdo` `r.Tx(N)`, `ocan_redundancy` `r.Fsm`, `ocan_sdo` `r.Proc`,
  `ocan_time` `r.Tx`): the branch recovers from an illegal state, which needs an upset of the state register and
  cannot be reached through the ports.
- A generic is constant in an instance, and QuestaSim does not count a term of a condition that is a generic. Every
  value of the structural generics is simulated in its own configuration (verification plans, section 2); such terms
  are listed in section 4.

## 2. Result

Run on 2026-10-25 with Open Logic 4.7.0-ft.9: 356 tests of the 17 testbenches, all passed, 77 minutes in one
simulator process; without code coverage the same 356 tests pass (72 minutes). Numbers are covered/total bins
per file; bold marks a metric with misses.

| File | Statements | Branches | FSM states | FSM transitions | Conditions | Expressions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ocan_core.vhd` | 44 / 44 | 8 / 8 |  |  |  | 2 / 2 |
| `ocan_dispatch.vhd` | 207 / 207 | 94 / 94 |  |  | **56 / 58** | 18 / 18 |
| `ocan_link.vhd` | 127 / 127 | 62 / 62 | 4 / 4 | 7 / 7 | 22 / 22 | 10 / 10 |
| `ocan_nmt.vhd` | 124 / 124 | 97 / 97 | 3 / 3 | 5 / 5 | **62 / 64** | 14 / 14 |
| `ocan_od.vhd` | **373 / 375** | **214 / 216** |  |  | **90 / 92** | **29 / 33** |
| `ocan_pdo.vhd` | 110 / 110 | 52 / 52 |  |  | 17 / 17 | 6 / 6 |
| `ocan_redundancy.vhd` | 131 / 131 | 59 / 59 | 4 / 4 | 10 / 10 | **34 / 35** | 6 / 6 |
| `ocan_sdo.vhd` | **178 / 179** | **94 / 95** |  |  | **21 / 22** | 11 / 11 |
| `ocan_time.vhd` | **135 / 136** | **53 / 54** | 3 / 3 | 5 / 5 | **13 / 14** | 6 / 6 |
| Total | 1429 / 1433 (99.7 %) | 733 / 737 (99.5 %) | 14 / 14 (100.0 %) | 27 / 27 (100.0 %) | 315 / 324 (97.2 %) | 102 / 106 (96.2 %) |

Every item that the ports can reach is covered. The items not covered are listed in section 4 with the reason why no
input sequence reaches them. `ocan_core`, `ocan_link` and `ocan_pdo` are covered completely.

## 3. Gaps found and closed

A QuestaSim run with code coverage before the release showed reachable behaviour that no test exercised. The checks
below close these gaps; they extend existing tests of the direct benches.

| Gap | Test |
| --- | --- |
| SYNC, the Spacecraft Time PDO and the master heartbeat received while their COB-ID entry is not valid | TC-DS-02 |
| A receive PDO at 7DFh and 7EFh, between the free ranges | TC-DS-02 |
| A transmit request rejected in one cycle and allowed from the next | TC-DS-10 |
| An SDO reply withdrawn in `Send_s` when the NODE-ID becomes invalid while the SDO enable is set | TC-DS-10 |
| The dominant monitor with a prescaler of 0, which counts as 1 | TC-LK-14 |
| A disable of the link in `Abort_s` and in `Switch_s` | TC-LK-09 |
| A SYNC COB-ID with bits 28 to 11 not 0 | TC-OD-06 |
| An access to the user logic in the cycle of a reset application or a reset communication | TC-OD-11 |
| A Local Time PDO on request before the first SYNC with the high-resolution protocol | TC-TM-14 |
| A client abort in the cycle of the 512th tick of an access without an answer | TC-SD-14 |

The first QuestaSim run also showed four failures of the SDO testbench that GHDL does not show: when two calls that end
in the same function are actuals of one procedure call, QuestaSim gives one of them the value of the other. The
helper functions of the testbenches return the results of other functions through a local variable since then; the
core was not affected.

## 4. Items not covered

| File | Item | Reason |
| --- | --- | --- |
| `ocan_dispatch.vhd` | Conditions, line 242 `TimePdos_g` = false and line 248 `SdoServer_g` = false | Generic terms (section 1); both values are simulated in the configurations of the core bench |
| `ocan_nmt.vhd` | Conditions, line 263 `MinimalSet_g` = false and line 327 `MinimalSet_g` = true | Generic terms |
| `ocan_redundancy.vhd` | Condition, line 222 `MinimalSet_g` = true | Generic term |
| `ocan_od.vhd` | Branches and statements, lines 1090 and 1146: `when others => null` of the read and the write values | Every readable and every writable object has its own branch; an access to another object is refused before |
| `ocan_od.vhd` | Conditions, line 219 `e` > 9 with `e` >= 6 and line 229 `e` < 2 | `entryExists` is called for the entries 0 to 11, where 10 and 11 are decided before, and `cobBase` for 2 to 9 only |
| `ocan_od.vhd` | Expressions, lines 244 and 246 of `restricted` | The free ranges of clause 9.5a (line 246) lie inside the last range of \[CiA301\] table 40, which line 244 already restricts from 780h on; line 246 states the clause and can never change the result, and in line 244 an identifier at or above 780h is decided by its last term |
| `ocan_sdo.vhd` | Branch and statement, lines 441 and 442 `r.Cnt` >= `r.Size` | After the last segment the transfer closes, so a further segment request is refused before; the guard keeps the remaining count in range after an upset of `Cnt` or `Size` |
| `ocan_sdo.vhd` | Condition, line 454 `Cnt` + `J` < `MaxBytes_c` false | The segment length is at most `Size` - `Cnt` and `Size` at most 8; the term protects the index into the buffer after an upset |
| `ocan_time.vhd` | Branch and statement, lines 84 and 85 | The width function of the counters is evaluated at elaboration and never with 0 |
| `ocan_time.vhd` | Condition, line 345 `Tx_Done` with `Tx_Ready` | `ocan_dispatch` never signals `Tx_Done` together with `Tx_Ready` (DS-TX-03); the term is defensive |
