# ocan_sdo: Verification Report

## 1. Test results

Run with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7 and UVVM 2026.02.14: `python run.py "*ocan_sdo*"`.

| Testbench | Test cases | Runs (test case and configuration) | Passed |
| --- | --- | --- | --- |
| `ocan_sdo_tb` | 16 | 16 | 16 |
| `ocan_sdo_net_tb` | 1 | 1 | 1 |

The configurations are those of section 2 of the [verification plan](verification_plan.md): every test case of the
direct bench in `default`, the network bench in `net`. In every cycle of the direct bench the reference model
predicted `Tx_Valid` with the frame and its DLC, `Acc_Valid` with the kind, index, sub-index, data and number of
bytes of the access, `Stat_Open` and the five events, and no output differed from it. The model is written from
\[CiA301\] section 7.2.4.3 and the specification, with the open transfer and the processing of a request as its own
variables; the tests compare every reply in addition with a frame written from \[CiA301\]. The object model at the
access interface follows OD-IF-01 and OD-WR-02. It answers an object of the user logic after a delay in cycles or
ticks, ends such a request without an answer at a reset event and answers an access in the cycle of a reset event
with 0800 0022h, as `ocan_od` does; one object takes the access and never answers (SD-TX-04).

TC-SD-16 sent 5000 random requests: 3742 replies, 1342 accesses of the object dictionary, 834 requests not processed,
27 replies without completion, 2284 abort frames sent and 205 client aborts that ended a transfer or a processing.

In the network bench (TC-SD-17) the model node M1 of the active bus was the SDO client of the node with NODE-ID 5 on
bus A and on bus B, with the real `ocan_od`, `ocan_dispatch` and `ocan_link`: every reply had the identifier 585h,
the DLC 8 and the bytes of \[CiA301\].

QuestaSim (Questa Pro Microchip Edition 2024.3): the same tests pass in the regression without code coverage
(`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`); the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Measured values

| Item | Value |
| --- | --- |
| Request to `Acc_Valid` | 1 clock cycle (every access of every test) |
| Answer of the object dictionary to `Tx_Valid` | 1 clock cycle, for answers 1 cycle, 100 cycles, 255 ticks and 256 ticks after the access (TC-SD-14) |
| Request without an access to `Tx_Valid` | 1 clock cycle (every such request) |
| Access without an answer | `Err_AccTimeout` at the 512th tick after the decode of the request, the abort 0800 0000h in the next cycle; after a client abort without a reply (TC-SD-14) |
| Taken reply without completion | `Err_TxTimeout` at the 256th tick after the take, no repetition; also for the reply after an access answered after 200 ticks and for the abort after an access without an answer (TC-SD-12) |
| Abandoned transfer | `Stat_Open` set after 2000 ticks without a request; the next initiate ends it (TC-SD-09) |

## 3. Generic ranges

`ocan_sdo` has no generics. `lint/synth_check.py` synthesises it once.

## 4. Negative tests and mutations

Every checker of the plan has a negative test (verification plan, section 5). In addition, 73 deliberate faults of
the RTL were each simulated with the tests that must detect them, and every one made a test fail:

| Fault | Detected by |
| --- | --- |
| No toggle check of download segments | TC-SD-06 |
| No toggle check of upload segments | TC-SD-06 |
| More than 8 bytes taken | TC-SD-03 |
| 8 bytes refused | TC-SD-02 |
| No size check at the last segment | TC-SD-03 |
| Size above 8 taken | TC-SD-03 |
| Size 0 taken | TC-SD-03 |
| Segmented download without a size taken | TC-SD-03 |
| Abort code of the toggle error | TC-SD-06 |
| Abort code of a command specifier | TC-SD-07 |
| Abort code of more than 8 bytes | TC-SD-03 |
| Abort code of a size mismatch | TC-SD-03 |
| Abort code of a size above 8 | TC-SD-03 |
| Abort code of a bad answer length | TC-SD-04 |
| Command specifiers 5 to 7 aborted without the multiplexer | TC-SD-07 |
| Download segment without a transfer: old multiplexer | TC-SD-07 |
| Upload segment without a transfer: old multiplexer | TC-SD-07 |
| Download segment during an upload keeps the upload | TC-SD-07 |
| Upload segment during a download keeps the download | TC-SD-07 |
| N of an expedited download from bits 2 to 1 | TC-SD-01 |
| S = 0 written with 4 bytes | TC-SD-01 |
| N of an expedited upload | TC-SD-04 |
| An object of 4 bytes uploaded segmented | TC-SD-04 |
| An answer with 0 bytes taken | TC-SD-04 |
| An answer with 9 bytes taken | TC-SD-04 |
| Data of an expedited download in the wrong byte order | TC-SD-01 |
| C of the last upload segment for 7 bytes | TC-SD-05 |
| N of an upload segment | TC-SD-05 |
| Toggle bit of an upload segment response | TC-SD-05 |
| Toggle bit of a download segment response | TC-SD-02 |
| Toggle bit of the response to the last download segment | TC-SD-02 |
| Data of a download segment from the wrong bytes | TC-SD-02 |
| Last byte of an upload segment missing | TC-SD-05 |
| Toggle bit not reset at a segmented initiate download | TC-SD-09 |
| Toggle bit not reset at a segmented initiate upload | TC-SD-05 |
| Count not reset at a segmented initiate upload | TC-SD-05 |
| Count not reset at a segmented initiate download | TC-SD-02 |
| Buffer not cleared at a segmented initiate download | TC-SD-02 |
| Initiate download keeps the open transfer | TC-SD-09 |
| Initiate upload keeps the open transfer | TC-SD-09 |
| No busy rule | TC-SD-11 |
| DLC below 8 processed | TC-SD-10 |
| DLC 8 not processed | TC-SD-10 |
| Client abort keeps the open transfer | TC-SD-08 |
| Client abort does not end the processing | TC-SD-08 |
| Evt_AbortRx for an ignored abort | TC-SD-08 |
| No Evt_AbortRx | TC-SD-08 |
| Answer of an abandoned access used | TC-SD-08, TC-SD-13 |
| Answer in the cycle of an abort used | TC-SD-08 |
| Offered reply kept at a client abort | TC-SD-08 |
| Abandoned access withdrawn | TC-SD-13 |
| Access not taken withdrawn at a cleared enable | TC-SD-13 |
| Answer awaited after a reset event | TC-SD-13 |
| Answer of an access taken in the cycle of a reset event not awaited | TC-SD-13 |
| Cleared enable keeps the open transfer | TC-SD-13 |
| Reset events keep the open transfer | TC-SD-13 |
| Taken reply awaited after an NMT event | TC-SD-13 |
| Request in the cycle of an NMT event processed | TC-SD-13 |
| No time-out of the access | TC-SD-14 |
| Time-out of the access after 511 ticks | TC-SD-14 |
| No completion time-out | TC-SD-12 |
| Completion time-out after 255 ticks | TC-SD-12 |
| Time-out count not cleared at the take | TC-SD-12 |
| Rejected reply keeps the transfer | TC-SD-12 |
| Aborted reply keeps the transfer | TC-SD-12 |
| Evt_AbortTx at every completion | TC-SD-12 |
| No Evt_AbortTx | TC-SD-12 |
| Tx_Done taken as Tx_Ready | TC-SD-12 |
| DLC 7 of the reply | TC-SD-01 |
| Index bytes of a reply swapped | TC-SD-01 |
| Index bytes of a request swapped | TC-SD-01 |
| Transfer not reset by Rst | TC-SD-15 |
| Processing not reset by Rst | TC-SD-15 |

The first mutation run detected 72 of the faults. "Time-out count not cleared at the take" was a gap of the bench,
not of the RTL: TC-SD-12 withheld the completion only of replies to requests that took no tick before the take,
where the count is 0 with or without the clear. TC-SD-12 now also withholds the completion of the reply to an access
answered after 200 ticks and of the abort after an access without an answer, and the fault is detected. The eight
faults that TC-SD-12 must detect ran again on the extended bench and were all detected. The RTL is unchanged since
the first run, and the other test cases are unchanged, so the other detections of that run stand.

## 5. Summary

All 16 test cases of the direct bench and TC-SD-17 of the network bench pass in all 17 runs; every requirement of
the specification is covered by the verification plan. VSG reports no errors and no warnings, and the GHDL synthesis
of `ocan_sdo` in `lint/synth_check.py` has no inferred latch.
