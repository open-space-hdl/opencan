# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""ECSS compliance matrix of OpenCAN.

Usage: python tools/compliance.py [--check]
Reads the requirement traceability matrix of docs/architecture.md (section 10), the requirements of every
hdl/<module>/docs/specification.md (ID and ECSS clauses) and the test cases of every verification_plan.md (test and
requirement IDs), and writes docs/compliance.md: for every ECSS clause of the matrix the requirements that trace to it
and the test cases that verify them.

The owner of a clause is a module of OpenCAN (`ocan_<name>` in backticks), "Out of scope, <who>" or "Not implemented
(<reason>)". A clause whose owner module has no testbench yet (hdl/<module>/tb/*_tb.vhd) is listed as planned, with
the test cases of its verification plan marked as planned. With --check the file is not written; the exit code is 1
when a clause of a module with a testbench has no test case, when a requirement of a module with a testbench or a
verification plan has no test case, or when a test case of a module with a testbench is not run by a testbench.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "compliance.md"
CLAUSE_RE = re.compile(r"\d+(?:\.\d+)+")
RANGE_RE = re.compile(r"(\d+(?:\.\d+)+)(?:[a-z]+\d*)?(?:\s+to\s+(\d+(?:\.\d+)+))?")
MODULE_RE = re.compile(r"`(ocan_\w+)`")


def table_rows(text):
    """Rows of markdown tables as lists of cells (header and separator rows included)."""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("|") and line.endswith("|"):
            yield [c.strip() for c in line.strip("|").split("|")]


def clauses(cell):
    """Base clause numbers of a clause cell, ranges expanded: '8.3.3e, 6.10f' -> ['8.3.3', '6.10'],
    '5.1.1 to 5.1.3' -> ['5.1.1', '5.1.2', '5.1.3']."""
    result = []
    for m in RANGE_RE.finditer(cell):
        first, last = m.group(1), m.group(2)
        if last:
            fp, lp = first.split("."), last.split(".")
            if len(fp) == len(lp) and fp[:-1] == lp[:-1] and int(fp[-1]) <= int(lp[-1]):
                result += [".".join(fp[:-1] + [str(n)]) for n in range(int(fp[-1]), int(lp[-1]) + 1)]
            else:
                result += [first, last]
        else:
            result.append(first)
    return result


def expand_ids(cell):
    """Requirement IDs of a test row: 'RM-BS-01, RM-BS-03 to 05, NM-HB-01, 02' -> full list."""
    ids = []
    last = None
    for part in [p.strip() for p in cell.split(",")]:
        m = re.match(r"^([A-Z]+(?:-[A-Z0-9]+)*-)(\d+)(?:\s+to\s+(?:[A-Z]+(?:-[A-Z0-9]+)*-)?(\d+))?", part)
        if m:
            prefix, first = m.group(1), int(m.group(2))
            last_n = int(m.group(3)) if m.group(3) else first
            width = len(m.group(2))
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
            last = (prefix, width)
            continue
        m = re.match(r"^(\d+)(?:\s+to\s+(\d+))?$", part)
        if m and last:
            prefix, width = last
            first = int(m.group(1))
            last_n = int(m.group(2)) if m.group(2) else first
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
    return ids


def has_testbench(module):
    return any((ROOT / "hdl" / module / "tb").glob("*_tb.vhd"))


def load_requirements():
    """Requirements of the module specifications: ID -> (module, ECSS clauses)."""
    reqs = {}
    for spec in sorted(ROOT.glob("hdl/*/docs/specification.md")):
        module = spec.parent.parent.name
        for row in table_rows(spec.read_text(encoding="utf-8")):
            if len(row) >= 3 and re.match(r"^[A-Z]+(-[A-Z0-9]+)*-\d{2}$", row[0]):
                reqs[row[0]] = (module, clauses(row[-1]))
    return reqs


def load_tests():
    """Test cases of the verification plans: test ID -> requirement IDs, for the modules with a testbench
    (verified) and for those without one (planned). Also returns the test names of the plans of modules with a
    testbench that no testbench of the repository runs."""
    verified, planned = {}, {}
    names = set()
    for plan in sorted(ROOT.glob("hdl/*/docs/verification_plan.md")):
        module = plan.parent.parent.name
        target = verified if has_testbench(module) else planned
        for row in table_rows(plan.read_text(encoding="utf-8")):
            if len(row) >= 3 and row[0].startswith("`test_"):
                m = re.search(r"\((TC-[A-Z]+-\d+)\)", row[0])
                tid = m.group(1) if m else row[0]
                target.setdefault(tid, set()).update(expand_ids(row[-1]))
                if target is verified:
                    names.add(row[0].split("`")[1])
    run_names = set()
    for tb in ROOT.glob("hdl/*/tb/*.vhd"):
        run_names.update(re.findall(r'run\("(test_\w+)"\)', tb.read_text(encoding="utf-8")))
    return verified, planned, sorted(names - run_names)


def load_matrix():
    text = (ROOT / "docs" / "architecture.md").read_text(encoding="utf-8")
    section = text[text.index("## 10 Requirement traceability matrix"):text.index("## 11 ")]
    rows = []
    for row in table_rows(section):
        if len(row) >= 5 and CLAUSE_RE.match(row[0]):
            rows.append(row[:5])
    return rows


def matches(req_clauses, row_clauses):
    for rc in req_clauses:
        for c in row_clauses:
            if rc == c or rc.startswith(c + "."):
                return True
    return False


def test_key(tid):
    parts = tid.split("-")
    return (parts[1], int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0)


def main():
    reqs = load_requirements()
    tests, planned, not_run = load_tests()
    matrix = load_matrix()
    lines = [
        "# OpenCAN: ECSS Compliance Matrix",
        "",
        "Generated by `python tools/compliance.py` from the requirement traceability matrix of the",
        "[architecture](architecture.md) (section 10), the requirements of the module specifications and the test cases",
        "of the module verification plans. `python tools/compliance.py --check` fails when a clause or a requirement",
        "of a module with a testbench has no test case, when a requirement of a module with a verification plan is",
        "missing from the plan, or when a test case of a module with a testbench is not run by a testbench.",
        "",
        "## 1. ECSS clauses",
        "",
        "A clause is listed with every requirement whose ECSS reference lies in the clause, and with the test cases that",
        "verify these requirements. A clause whose owner module has no testbench yet is planned; the test cases of its",
        "verification plan are marked as planned.",
        "",
        "| ECSS clause | Title | Owner | Requirements | Test cases | Status |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    missing = []
    counts = {}
    for clause, title, owner, _, level in matrix:
        cl = clauses(clause)
        req_ids = sorted(r for r, (_, rc) in reqs.items() if matches(rc, cl))
        test_ids = sorted({t for t, ids in tests.items() if ids & set(req_ids)}, key=test_key)
        planned_ids = sorted({t for t, ids in planned.items() if ids & set(req_ids)}, key=test_key)
        modules = MODULE_RE.findall(owner)
        if owner.startswith("Out of scope"):
            status = "Out of scope"
        elif owner.startswith("Not implemented"):
            status = "Not implemented"
        elif test_ids and level == "Board":
            status = "Interface verified; board"
        elif test_ids:
            status = "Verified"
        elif modules and not any(has_testbench(m) for m in modules):
            status = "Planned"
        else:
            status = "Not traced"
            missing.append(clause)
        counts[status] = counts.get(status, 0) + 1
        cases = test_ids + [f"{t} (planned)" for t in planned_ids]
        lines.append(f"| {clause} | {title} | {owner} | {', '.join(req_ids) or '-'} | {', '.join(cases) or '-'} | "
                     f"{status} |")
    summary = "; ".join(f"{k.lower()}: {v}" for k, v in sorted(counts.items()))
    lines += [
        "",
        f"Clauses: {len(matrix)}; {summary}.",
        "",
        "## 2. Requirements",
        "",
        "Requirements of the module specifications and the test cases that verify them (requirements without an ECSS",
        "reference included). A module without a testbench has planned test cases only.",
        "",
        "| Module | Requirements | Verified by a test case | Planned in the verification plan | Without a test case |",
        "| --- | --- | --- | --- | --- |",
    ]
    covered = set().union(*tests.values()) if tests else set()
    planned_cov = set().union(*planned.values()) if planned else set()
    with_plan = {p.parent.parent.name for p in ROOT.glob("hdl/*/docs/verification_plan.md")}
    untested = sorted(r for r, (m, _) in reqs.items()
                      if r not in covered and (has_testbench(m) or (m in with_plan and r not in planned_cov)))
    for module in sorted({m for m, _ in reqs.values()}):
        ids = [r for r, (m, _) in reqs.items() if m == module]
        gaps = [r for r in ids if r not in covered and r not in planned_cov]
        n_ver = len([r for r in ids if r in covered])
        n_plan = len([r for r in ids if r in planned_cov and r not in covered])
        lines.append(f"| `{module}` | {len(ids)} | {n_ver} | {n_plan} | {', '.join(gaps) or '-'} |")
    if not reqs:
        lines.append("| - | 0 | 0 | 0 | - |")
    lines += [
        "",
        f"Requirements: {len(reqs)}; without a test case in a module with a testbench or a verification plan:",
        f"{len(untested)}; test cases of modules with a testbench not run by a testbench: {len(not_run)}.",
        "",
    ]
    if "--check" not in sys.argv:
        OUT.write_text("\n".join(lines), encoding="utf-8", newline="\n")
        print(f"written {OUT.relative_to(ROOT)}")
    for c in missing:
        print(f"clause not traced: {c}")
    for r in untested:
        print(f"requirement without a test case: {r}")
    for n in not_run:
        print(f"test case not run by a testbench: {n}")
    sys.exit(1 if (missing or untested or not_run) else 0)


if __name__ == "__main__":
    main()
