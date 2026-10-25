# ocan_pdo: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_pdo*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_pdo_tb` | 16 | 24 | 24 |
| `ocan_pdo_net_tb` | 2 | 2 | 2 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): every test case of the
direct bench in `default`, TC-PD-15 and TC-PD-18 also in `n00`, `n13`, `n22` and `n31`, the network bench in `net`
and `net_minimal`. In every cycle of the direct bench the reference model predicted `Sync_Valid`, `Rpdo_Valid` with
the data of every receive PDO, `TxTpdo_Valid` with the data and the DLC of every transmit PDO, `Stat_TpdoBusy` and
the five events of every PDO, and `Stat_PdoEnabled` was compared with `Nmt_EnaPdo` of the same cycle; no output
differed. The model is written from \[CiA301\] section 7.2.2 and the specification: it counts the SYNCs of a
transmit PDO up to its type and keeps the request, its handshake phase and the ticks of its wait as its own
variables, not as the registers of the architecture. A second checker required in every cycle that an offered
request and its data stay until `TxTpdo_Ready` and that no PDO is requested again before the completion or the
time-out of its previous request. The data of the user logic changed in every cycle, so a sample in another cycle
than the one of the specification would have changed the data.

TC-PD-15 ran 20000 cycles with every transmission type of 0 to 255 applied to the receive and to the transmit PDOs,
also in the cycle of an event, and the responder of every transmit PDO went through every completion class in turn.
In `default`: 320 transmit PDOs requested, 182 completed as sent, 124 as aborted (after the take or on the reject
path), 14 time-outs and 600 PDOs that fell due while their request was pending; 893 passes of receive data and 328
receive PDOs with a DLC below 8. The test requires every completion and error event of every present PDO; the other
configurations ran the same stimuli with fewer PDOs.

In the network bench (TC-PD-16) the model node M1 of the active bus started the node with NODE-ID 5 on bus A and on
bus B, with the real `ocan_nmt`, `ocan_od`, `ocan_time`, `ocan_dispatch` and `ocan_link`. The receive PDOs 205h to
505h of type 254 reached the user logic with the bytes of the frame, those of type 1 at the next SYNC, all four in
the cycle of `Sync_Valid`. The transmit PDOs 185h to 485h had DLC 8 and the bytes of the user logic: type 254 at the
request, type 1 at every SYNC, type 3 at the same SYNCs as the Local Time PDO of type 3, type 0 at the SYNC after the
request. At the SYNCs where the transmit PDOs and the Local Time PDO were due, the frames followed the round-robin
order of DS-TX-01 from the source of the last frame: the Local Time PDO came before transmit PDO 2, which had been the
last frame. In Pre-operational no PDO was passed or sent, and the data held and the request waiting at the exit from
Operational were discarded, also after the next start. In the minimal set (TC-PD-17) the node was in Operational by
local control, the reply to a receive PDO and the transmit PDO requested at every `Sync_Valid` were on the bus.

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Measured values

| Item | Value |
| --- | --- |
| Receive PDO event (types 254, 255) to `Rpdo_Valid` | 1 clock cycle (every receive PDO of every test) |
| SYNC event to `Sync_Valid` and to `Rpdo_Valid` of the held data | 1 clock cycle, all held PDOs in the same cycle (TC-PD-03, TC-PD-14, TC-PD-16) |
| SYNC event (types 0 to 240) and `Tpdo_Req` (types 254, 255) to `TxTpdo_Valid` | 1 clock cycle, with the data of the cycle of the SYNC or of the request (every check of the direct bench) |
| Taken transmit PDO without completion | `Err_TxTimeout` at the 256th tick after the take, twice in TC-PD-10; no repetition |
| Offered request without `TxTpdo_Ready` | Held with its data for 1000 cycles (TC-PD-09) and for 400 cycles of a late `TxTpdo_Ready` (TC-PD-06) |

## 3. Generic ranges

| Generic | Declared range | Simulated | Synthesised (`lint/synth_check.py`) |
| --- | --- | --- | --- |
| `NumRpdo_g` | 0 to 4 | 0, 1, 2, 3, 4 | 0, 1, 2, 3, 4 |
| `NumTpdo_g` | 0 to 4 | 0, 1, 2, 3, 4 | 0, 1, 2, 3, 4 |

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, 57 deliberate faults of
the RTL were each simulated with the tests that must detect them, and every one made a test fail:

| Fault | Detected by |
| --- | --- |
| SYNC with DLC 1 ignored | TC-PD-05, TC-PD-03 |
| SYNC with DLC 2 counted | TC-PD-05, TC-PD-03 |
| Sync_Valid for every DLC | TC-PD-05 |
| DLC 7 processed | TC-PD-02 |
| DLC 8 refused | TC-PD-02 |
| Receive type 253 event-driven | TC-PD-04 |
| Receive type 255 not event-driven | TC-PD-01 |
| Receive type 241 synchronous | TC-PD-04 |
| Receive type 240 not synchronous | TC-PD-03 |
| Receive type of PDO 1 for every PDO | TC-PD-02 |
| A synchronous PDO in the SYNC cycle passed at that SYNC | TC-PD-03 |
| The first held value wins | TC-PD-03 |
| The SYNC after the receive PDO of the same cycle | TC-PD-03 |
| Held data not discarded | TC-PD-11 |
| Held data passed while the PDO enable is cleared | TC-PD-11 |
| Receive PDOs processed in the cycle of a reset communication | TC-PD-12 |
| Receive PDOs processed while the PDO enable is cleared | TC-PD-11 |
| Receive data not cleared by Rst | TC-PD-13 |
| Held data not cleared by Rst | TC-PD-13 |
| Cyclic one SYNC late | TC-PD-06 |
| Count not cleared at the due SYNC | TC-PD-06 |
| SYNC of the restart cycle counted | TC-PD-06, TC-PD-12 |
| Count paused while the PDO enable is cleared | TC-PD-11 |
| No restart at a type change | TC-PD-06, TC-PD-07 |
| No restart at a reset communication | TC-PD-06, TC-PD-12 |
| Transmit type of PDO 1 for every PDO | TC-PD-06 |
| Type 1 not cyclic | TC-PD-06 |
| Type 241 cyclic | TC-PD-08 |
| Type 0: a request in the SYNC cycle served at that SYNC | TC-PD-07 |
| Type 0: the request kept at the due SYNC | TC-PD-07 |
| Type 0: the request of the restart cycle discarded (rule B) | TC-PD-07, TC-PD-12 |
| Type 0: the waiting request kept while the PDO enable is cleared | TC-PD-11 |
| Type 253 event-driven | TC-PD-08 |
| Type 255 not event-driven | TC-PD-08 |
| Event request of the restart cycle ignored (rule B) | TC-PD-07, TC-PD-12 |
| Count not cleared by Rst | TC-PD-13 |
| Waiting request not cleared by Rst | TC-PD-13 |
| Requested while the PDO enable is cleared | TC-PD-11 |
| No busy rule | TC-PD-09 |
| Busy in the cycle of the completion | TC-PD-09 |
| No Err_TxBusy | TC-PD-09 |
| Reject path taken as a take | TC-PD-10 |
| No Evt_TpdoAborted on the reject path | TC-PD-10 |
| TxTpdo_Done ignored | TC-PD-10 |
| TxTpdo_Aborted after the take ignored | TC-PD-10 |
| No Evt_TpdoSent | TC-PD-10 |
| Time-out after 255 ticks | TC-PD-10 |
| No time-out | TC-PD-10 |
| Time-out count not cleared at the take | TC-PD-10 |
| Time-out counts cycles | TC-PD-10 |
| Pending request withdrawn when the PDO enable clears | TC-PD-11 |
| Data of an offered request follow the user logic | TC-PD-09 |
| DLC 7 of a transmit PDO | TC-PD-06 |
| TxTpdo_Valid while taken | TC-PD-10 |
| Stat_TpdoBusy only while offered | TC-PD-09 |
| Stat_PdoEnabled constant | TC-PD-11 |
| Request state not cleared by Rst | TC-PD-13 |

In the first complete run 56 faults made a test fail. The fault "data of an offered request follow the user logic"
was not detected because the fault itself was wrong: the mutation inserted the assignment into the branch of the
take, where it changes the data only after `TxTpdo_Ready`, when they are no longer used. With the assignment in
every cycle of the offer, as intended, the fault ran again and was detected; the RTL and the benches are unchanged.

The compares `SyncCnt` >= T - 1 and `TxTmo` >= 255 differ from compares with = only after an upset of the counts,
and the `when others` branch of `TxSt` cannot be reached from the ports; both are covered by design review (plan,
section 7). Faults that change only absent PDOs are not visible at the ports: the outputs of absent PDOs are
constant 0 (TC-PD-18).

## 5. Summary

All 16 test cases of the direct bench in all 24 runs and TC-PD-16 and TC-PD-17 of the network bench pass; every
requirement of the specification is covered by the verification plan. VSG reports no errors and no warnings, and the
GHDL synthesis of `ocan_pdo` in `lint/synth_check.py` has no inferred latch for every number of PDOs.
