#!/usr/bin/env python3
"""
Portable test-case metrics sync for SpecKit installs.

Derives the dashboard's `test_cases` block live from the project (nothing
hardcoded) and writes it into every progress-tracker.json found under the
project root:

  Per epic (from each epic's test-cases.md, located via its spec_path):
    - manual    : unique TC-… ids   (manual / UAT cases)
    - automated : unique AT-… ids   (planned automated cases)
    - tokens    : sum of test-tagged token sessions for that epic
  Repo-wide automated suite (actually emitted code, discovered anywhere under root):
    - apex_test_classes / apex_test_methods / jest_specs / jest_tests

Usage (run from the project root, or pass --root):
    python3 .specify/scripts/sync-testcases-data.py
    python3 .specify/scripts/sync-testcases-data.py --root /path/to/project

Then run sync-dashboard-data.py (or just commit; the pre-commit hook does both).
"""
import argparse
import datetime
import json
import re
from pathlib import Path

CHARS = None
TC_RE = re.compile(r"\bTC-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\b")
AT_RE = re.compile(r"\bAT-[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\b")
APEX_METHOD_RE = re.compile(r"\bstatic\s+void\s+\w+\s*\(")
JEST_TEST_RE = re.compile(r"\b(?:it|test)\s*\(")
TEST_ACTIVITY_RE = re.compile(
    r"test case|testcase|test cases|jest|apex test|traceability|test class|\.test\.js|"
    r"speckit-testcases|unit test",
    re.I,
)
SKIP_DIRS = {".git", "node_modules", ".sk-test", "__pycache__"}


def under_skipped(path: Path) -> bool:
    return any(part in SKIP_DIRS for part in path.parts)


def is_test_session(s):
    if (s.get("category") or "").lower() == "testcases":
        return True
    if "TEST" in (s.get("story") or "").upper():
        return True
    return bool(TEST_ACTIVITY_RE.search(s.get("activity") or ""))


def count_doc_cases(testcases_md: Path):
    if not testcases_md or not testcases_md.exists():
        return 0, 0, False
    text = testcases_md.read_text(encoding="utf-8", errors="ignore")
    return len(set(TC_RE.findall(text))), len(set(AT_RE.findall(text))), True


def resolve_testcases_md(root: Path, spec_path: str):
    if not spec_path:
        return None
    candidates = [root / spec_path]
    # also try one directory level up/down (package-relative vs repo-relative)
    for sub in root.glob("*/" + spec_path):
        candidates.append(sub)
    for c in candidates:
        tc = c.parent / "test-cases.md"
        if tc.exists():
            return tc
    return (root / spec_path).parent / "test-cases.md"


def automated_suite(root: Path):
    apex_classes = [p for p in root.rglob("*Test.cls") if not under_skipped(p)]
    apex_methods = sum(
        len(APEX_METHOD_RE.findall(p.read_text(encoding="utf-8", errors="ignore")))
        for p in apex_classes
    )
    jest_specs = [p for p in root.rglob("__tests__/*.test.js") if not under_skipped(p)]
    jest_tests = sum(
        len(JEST_TEST_RE.findall(p.read_text(encoding="utf-8", errors="ignore")))
        for p in jest_specs
    )
    return {
        "apex_test_classes": len(apex_classes),
        "apex_test_methods": apex_methods,
        "jest_specs": len(jest_specs),
        "jest_tests": jest_tests,
    }


def test_tokens_by_epic(data):
    out = {}
    for e in data.get("token_consumption", {}).get("by_epic", []):
        out[e.get("epic_id")] = sum(
            (s.get("tokens") or 0) for s in e.get("sessions", []) if is_test_session(s)
        )
    return out


def build_block(root: Path, data, suite):
    tok_map = test_tokens_by_epic(data)
    by_epic = []
    for ep in data.get("epics", []):
        manual, automated, doc = count_doc_cases(resolve_testcases_md(root, ep.get("spec_path")))
        by_epic.append({
            "epic_id": ep.get("id"),
            "epic_name": ep.get("name"),
            "manual": manual,
            "automated": automated,
            "total": manual + automated,
            "tokens": tok_map.get(ep.get("id"), 0),
            "doc": doc,
        })
    total_manual = sum(e["manual"] for e in by_epic)
    total_automated = sum(e["automated"] for e in by_epic)
    return {
        "generated": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "note": "Counts derived live from test-cases.md and emitted Apex/Jest files; tokens from test-tagged sessions. Not hardcoded.",
        "totals": {
            "manual": total_manual,
            "automated": total_automated,
            "total": total_manual + total_automated,
            "tokens": sum(tok_map.values()),
            "epics_covered": sum(1 for e in by_epic if e["doc"] and e["total"] > 0),
            "epics_total": len(by_epic),
        },
        "automated_suite": suite,
        "by_epic": by_epic,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="Project root (default: cwd)")
    args = ap.parse_args()
    root = Path(args.root).resolve()
    suite = automated_suite(root)
    trackers = [p for p in root.rglob("progress-tracker.json") if not under_skipped(p)]
    if not trackers:
        print("No progress-tracker.json found.")
        return 1
    for tracker in trackers:
        data = json.loads(tracker.read_text())
        block = build_block(root, data, suite)
        old = data.get("test_cases") or {}
        if {k: v for k, v in old.items() if k != "generated"} == {
            k: v for k, v in block.items() if k != "generated"
        } and data.get("summary", {}).get("total_test_cases") == block["totals"]["total"]:
            print(f"  ok {tracker} (test_cases unchanged)")
            continue
        data["test_cases"] = block
        data.setdefault("summary", {})["total_test_cases"] = block["totals"]["total"]
        tracker.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        t = block["totals"]
        print(f"  updated {tracker}  (total={t['total']}, tokens={t['tokens']}, "
              f"epics_covered={t['epics_covered']}/{t['epics_total']})")
    print(f"Done. {len(trackers)} tracker(s) updated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
