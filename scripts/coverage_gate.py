#!/usr/bin/env python3
"""Validate measured SB-COVER line coverage, fail closed, emit badge JSON."""
import argparse
import json
import sys
from pathlib import Path

# Pure declarations: package definitions and API package marker only.
EXCLUDED = {
    "packages.lisp": "UIOP package declarations; no runtime implementation",
    "api.lisp": "re-export package marker; no runtime implementation",
}


def analyze(lcov, source):
    source = source.resolve()
    expected = {p.name for p in source.glob("*.lisp")} - EXCLUDED.keys()
    if not expected:
        raise ValueError("No eligible source files")
    records = {}
    for record in lcov.read_text(encoding="utf-8").split("end_of_record"):
        lines = record.splitlines()
        fields = [s[3:] for s in lines if s.startswith("SF:")]
        if not fields:
            continue
        if len(fields) != 1:
            raise ValueError("Bad SF record")
        path = Path(fields[0]).resolve()
        if path.parent != source or path.name in EXCLUDED:
            continue
        if path.name in records:
            raise ValueError("Duplicate source: " + path.name)
        hits = {}
        for line in lines:
            if line.startswith("DA:"):
                columns = line[3:].split(",")
                number, count = int(columns[0]), int(columns[1])
                if number < 1 or count < 0 or number in hits:
                    raise ValueError("Invalid DA for " + path.name)
                hits[number] = count
        if not hits:
            raise ValueError("No executable DA lines for " + path.name)
        records[path.name] = {"covered": sum(v > 0 for v in hits.values()), "total": len(hits)}
    if set(records) != expected:
        raise ValueError(f"Coverage modules differ from runtime sources: "
                         f"missing={sorted(expected - set(records))}, "
                         f"unexpected={sorted(set(records) - expected)}")
    covered = sum(row["covered"] for row in records.values())
    total = sum(row["total"] for row in records.values())
    if total < 1:
        raise ValueError("Zero denominator")
    return covered, total, dict(sorted(records.items()))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--lcov", type=Path, default=Path("coverage/coverage.lcov"))
    p.add_argument("--source", type=Path, default=Path("src/events"))
    p.add_argument("--out", type=Path, default=Path("coverage"))
    p.add_argument("--threshold", type=int, default=85)
    args = p.parse_args()
    try:
        if not 0 <= args.threshold <= 100:
            raise ValueError("Invalid threshold")
        covered, total, files = analyze(args.lcov, args.source)
    except (OSError, ValueError, IndexError) as exc:
        print(f"Coverage invalid: {exc}", file=sys.stderr)
        return 2
    percent = covered * 100 / total
    passed = 100 * covered >= args.threshold * total
    summary = {"method": "SBCL SB-COVER executable LCOV lines",
               "covered": covered, "denominator": total, "percent": round(percent, 3),
               "threshold": args.threshold, "passed": passed,
               "excluded_declaration_only": EXCLUDED, "files": files}
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if passed:
        endpoint = {"schemaVersion": 1, "label": "coverage",
                    "message": f"{percent:.1f}%", "color": "brightgreen" if percent >= 90 else "green"}
        (args.out / "endpoint.json").write_text(json.dumps(endpoint) + "\n", encoding="utf-8")
    for name, stats in files.items():
        print(f"{name}: {stats['covered']}/{stats['total']}")
    print(f"SB-COVER {covered}/{total} = {percent:.2f}% (threshold {args.threshold}%): "
          + ("PASS" if passed else "FAIL"))
    print("Excluded package declarations:", ", ".join(EXCLUDED))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
