# OpenCAN Conventions

OpenCAN follows the coding conventions of Open Logic and the module development process of the architecture
document. This page lists the rules and the few OpenCAN-specific additions.

## VHDL coding

- The [Open Logic coding conventions](../open-logic/doc/Conventions.md) apply in full: port names
  `<Interface>_<Signal>`, generics `_g`, constants `_c`, variables `_v`, types `_t`, FSM types `<Name>Fsm_t` with
  states `_s`, functions in `lowerCamelCase`, four spaces of indentation, no tabs, no trailing whitespace.
- Entities are named `ocan_<function>` (for example `ocan_bus_monitor`). All OpenCAN sources are compiled into the VHDL
  library `opencan`; Open Logic is compiled into the library `olo`.
- Language: VHDL-2008.
- A record field that is an array uses a fully constrained array type (`type T is array (0 to N - 1) of E`), not an
  index constraint on an unconstrained array type (`U : T(0 to N - 1)`). The AMD Vivado simulator 2025.2 gives the
  elements of such a field the constraint of another field when the record is accessed through an alias of an array
  element, and stops at time 0 with an index error; GHDL and QuestaSim are correct. Vectors of scalars
  (`std_logic_vector`, `unsigned`, `signed`) have no element constraint and are not affected.
- Entities with non-trivial state use the two-process pattern of Open Logic: all registers in one `TwoProcess_r`
  record, signals `r` and `r_next`, a combinational process starting with `v := r;` and ending with
  `r_next <= v;`, a sequential process with `r <= r_next;` and the reset override at its end.
- Resets are synchronous and high-active. Only state registers are reset. The core has one clock domain `Clk`.
- Every data path between blocks is a valid / ready stream (AXI4-Stream handshake semantics) or a valid-only stream
  of one-cycle events where the receiver is never slower than the source.
- Standard functions (FIFOs, RAMs, crossings, synchronisers, arbiters, pipeline stages) are instantiated from Open
  Logic, never rewritten. FIFOs and crossings use the fault-tolerant `olo_ft_*` entities.
- State machines have a `when others` branch that returns to a defined recovery state; the reset leads to that state
  from any state.
- Every line that implements an ECSS requirement is traceable through the module specification; comments name the
  clause where it helps the reader (for example `-- ECSS 8.3.3a`).
- File header: copyright line and authors, then a 1 to 2 sentence description that links to the module
  documentation. Never write "all rights reserved".
- Never use em-dashes in code, comments or documentation. Use UTF-8 only.
- VSG 3.27 with the Open Logic configuration in `lint/config` must report no errors and no warnings:
  `vsg -c lint/config/vsg_config.yml -f <file>`. Safe automatic fixes:
  `vsg -c lint/config/vsg_config.yml --fix --fix_only lint/config/fix_only_config.yml -f <file>`.
- The design must be synthesizable in a technology-independent way: `python lint/synth_check.py` elaborates
  `ocan_core` with the synthesis of GHDL (after `python run.py --compile`) at the generic values of the verification
  report of `ocan_core` and fails on errors and inferred latches; inconsistent configurations must stop with the
  message of the core. It runs in CI after the regression.
- Generic ranges are verified: every value of a generic that changes the structure is simulated, the ends of every
  numeric range are at least synthesised, other values are excluded by an assertion or listed as unverified; the
  verification report of `ocan_core` has the table.
  `to_01` and other simulation-only functions are not used in RTL.
- The synthesis sources analyse with `ghdl -a --std=08` without `-frelaxed` and without warnings. Attribute
  specifications use literals, because the expression of an attribute specification must be locally static. Only
  Open Logic and UVVM need `-frelaxed`.
- `compile_order.txt` lists the synthesis sources of the library `opencan` in compile order. After adding, removing
  or renaming a source file, regenerate it with `python run.py --compile-order`; the CI fails when it is out of date.
- Traceability: every requirement of a specification is verified by at least one test case of the verification plan,
  every ECSS clause of the traceability matrix (architecture section 10) by the test cases of its requirements, and
  every test case of a plan is run by a testbench. `python tools/compliance.py` writes the
  compliance matrix `docs/compliance.md`; `python tools/compliance.py --check` fails on a gap.

## Module development process

Every module goes through the seven phases of the architecture document (section 9):

| Phase | Output |
| --- | --- |
| A Requirements | `hdl/<module>/docs/specification.md`: requirements with IDs, each tracing to ECSS clauses |
| B Architecture | `hdl/<module>/docs/architecture.md`: blocks, ports, state machines, data formats |
| C Verification plan | `hdl/<module>/docs/verification_plan.md`: test cases with IDs, requirement coverage |
| D RTL | `hdl/<module>/src/*.vhd` |
| E Testbenches | `hdl/<module>/tb/<entity>_th.vhd` (harness) and `<entity>_tb.vhd` (VUnit runner) |
| F Verification | Regression green, `hdl/<module>/docs/verification_report.md` |
| G Integration | Tests at the next level that cross every seam the module touches |

A module is one layer or one group of blocks of the architecture (section 7). Every block keeps its own entity and
its own unit testbench. `hdl/<module>/README.md` links the four documents and explains how to run the tests.

## Diagrams

- Every architecture document has a block diagram; state machines and data formats have one where text alone is
  hard to follow.
- Diagrams are draw.io drawings stored as editable SVG with the drawing embedded (`<name>.drawio.svg`) in the `img/`
  folder next to the document. The SVG is the source: open it in draw.io to change it. It is exported with the light
  theme on an opaque white background, so that it reads in both colour schemes of the documentation site.
- Blocks: light blue for OpenCAN logic, white with a blue outline for an OpenCAN entity instantiated as a whole,
  light grey for an Open Logic entity, drawn inside the block that instantiates it. A dashed outline groups the
  blocks of one entity instance. The title carries the building block ID of the architecture (`TG-3 Command
  controller`), the entity follows in grey.
- Connections: thick lines for streams and buses, thin lines for single signals. Every line is horizontal or
  vertical; a dot marks a branch or the junction of lines that share a segment. Ports cross the frame of the
  entity, inputs on the left, outputs on the right where the layout allows.
- State machines: states as rounded boxes, the reset entry as a filled dot, every transition labelled with its
  condition.
- A diagram is at most about 1000 px wide, so that its text stays readable in the content column, and its alt text
  names the blocks it shows.

## Verification

- VUnit runs every test (`run.py`); UVVM supplies VVCs, BFMs, checks, randomisation and functional coverage.
- The harness (`_th`) contains clocks, reset, the DUT and the VVCs, the testbench (`_tb`) contains one
  `if run("<test id>") then` block per test case of the verification plan. The test IDs of the plan and the names
  in `run(...)` are identical.
- A test passes only when UVVM reports no unexpected alerts and every expected alert occurred
  (`ocan_tb_pkg.ocanTestEnd`).
- Tests observe ports and management interfaces only, never internal signals.
- GHDL is the default simulator and the evidence of every pull request. QuestaSim (`python run.py --questa`) runs the
  full regression of a release, with and without code coverage (`docs/coverage.md`), at a time resolution of 1 fs as
  GHDL (`run.py` passes `-t fs`). Every test passes in both simulators.
- `run.py` gives every GHDL simulation its own copy of the option `ghdl.sim_flags` and stops when a simulation command
  does not carry exactly the generics of its configuration (VUnit 5.0.0.dev7 shares that list between configurations).
- A side effect is never obtained by calling an impure function and discarding its result: QuestaSim may remove such
  a call. Protected types offer a procedure for it.
- The far end of every bus is the CAN network model of `tb/` (own implementation of the CAN frames, of the CANopen
  services and of the redundancy master or slave nodes of the standard); tests never use the RTL of the core to build
  or check frames.
- Negative tests inject the fault from the bench (a missing heartbeat, a broken or stuck bus, corrupted frames,
  wrong CANopen requests, double errors through the `ErrInj` ports, ...) and expect the reaction on the buses and in
  the status of the core.

## Git

- `develop` holds the integrated state and `main` the released state; both change only through pull requests.
- Every module or change is developed on a branch `feature/<module>` or `bugfix/<topic>` from `develop` and merged
  into `develop` through a pull request once its GHDL regression and the other checks of the CI are green.
- A release is a branch `release/x.y.z` from `develop`. The full QuestaSim regression, with and without code coverage,
  runs on its head; afterwards only `docs/coverage.md`, the run records of the verification reports, the version and
  the change log change, no HDL. The branch merges into `main` through a pull request, the merge is tagged `vX.Y.Z`,
  and `main` is merged back into `develop`. A fix of a release is a branch `hotfix/x.y.z` from `main` with the same
  evidence.
- Versions follow semantic versioning: 0.y.z while the core is at TRL 3, 1.0.0 with TRL 4 (hardware test). The major
  version changes with an incompatible change of ports, generics, stream formats or register map, the minor version
  with a new feature, the patch version with a fix.
- Commit messages: imperative subject line, body explains what and why.
