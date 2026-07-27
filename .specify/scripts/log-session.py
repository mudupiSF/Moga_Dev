#!/usr/bin/env python3
"""
Log a single work session's token consumption into progress-tracker.json and
recompute every rollup. Call this per prompt / per meaningful turn so the
numbers accumulate accurately instead of being one big round estimate at the end.

Usage (run from your project root):
  # explicit token estimate
  python3 .specify/scripts/log-session.py --epic EPIC-001 --contributor jane \
      --activity "US1 KPI header LWC scaffold" --tokens 4280

  # estimate tokens from the volume produced/read this turn
  python3 .specify/scripts/log-session.py --epic EPIC-001 --contributor jane \
      --activity "pricing service" --from-files force-app/main/default/classes/Pricing.cls

  # attribute to a specific story too
  python3 .specify/scripts/log-session.py --epic EPIC-001 --story PROJ-38 \
      --contributor jane --activity "catalog search" --tokens 3120

Notes:
  - --tokens wins if given. Otherwise tokens are estimated from --chars N or
    --from-files (chars/3.8 * overhead). Default overhead 5.7 (override w/ --overhead).
  - Portable: updates every progress-tracker.json under the project root (CWD,
    or --root). Commit afterwards; the pre-commit hook syncs the dashboards.
"""
import argparse
import datetime
import json
from pathlib import Path

CHARS_PER_TOKEN = 3.8


def estimate_tokens(args, root: Path) -> int:
    if args.tokens is not None:
        return args.tokens
    chars = args.chars or 0
    for f in (args.from_files or []):
        p = Path(f)
        if not p.is_absolute():
            p = root / f
        try:
            chars += len(p.read_text(errors="ignore"))
        except Exception:
            print(f"  (warning: could not read {f})")
    if chars <= 0:
        raise SystemExit("Provide --tokens, --chars, or --from-files to estimate tokens.")
    return round(chars / CHARS_PER_TOKEN * args.overhead)


def recompute(data):
    tc = data["token_consumption"]
    for epic in tc["by_epic"]:
        epic["total_tokens"] = sum(s.get("tokens", 0) for s in epic.get("sessions", []))
    grand = sum(e["total_tokens"] for e in tc["by_epic"])
    contrib_epic = {}
    sess_count = {}
    for epic in tc["by_epic"]:
        for s in epic.get("sessions", []):
            cid = s.get("contributor", "unknown")
            contrib_epic.setdefault(cid, {}).setdefault(epic["epic_id"], 0)
            contrib_epic[cid][epic["epic_id"]] += s.get("tokens", 0)
            sess_count[cid] = sess_count.get(cid, 0) + 1
    for bc in tc.get("by_contributor", []):
        per = contrib_epic.get(bc["contributor_id"], {})
        bc["by_epic"] = [{"epic_id": k, "tokens": v} for k, v in per.items()]
        bc["total_tokens"] = sum(per.values())
    for c in data.get("contributors", []):
        per = contrib_epic.get(c["id"], {})
        c["total_tokens"] = sum(per.values())
        c["sessions_count"] = sess_count.get(c["id"], c.get("sessions_count", 0))
    tc["total_estimated_tokens"] = grand
    data.setdefault("summary", {})["total_tokens"] = grand


def log_one(tracker_path: Path, args, tokens: int) -> bool:
    data = json.loads(tracker_path.read_text())
    tc = data.get("token_consumption", {})
    epic = next((e for e in tc.get("by_epic", []) if e["epic_id"] == args.epic), None)
    if epic is None:
        print(f"  (skip {tracker_path.name}: epic {args.epic} not found)")
        return False
    session = {
        "date": args.date,
        "contributor": args.contributor,
        "activity": args.activity,
        "tokens": tokens,
    }
    if args.story:
        session["story"] = args.story
    epic.setdefault("sessions", []).append(session)
    recompute(data)
    tracker_path.write_text(json.dumps(data, indent=2) + "\n")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--epic", required=True, help="Epic id, e.g. EPIC-001")
    ap.add_argument("--contributor", required=True, help="Contributor id, e.g. jane")
    ap.add_argument("--activity", required=True, help="What was done this session")
    ap.add_argument("--story", help="Optional story key, e.g. PROJ-38")
    ap.add_argument("--tokens", type=int, help="Explicit token estimate")
    ap.add_argument("--chars", type=int, help="Char count to estimate tokens from")
    ap.add_argument("--from-files", nargs="*", help="Files whose size estimates tokens")
    ap.add_argument("--overhead", type=float, default=5.7, help="Overhead factor (default 5.7)")
    ap.add_argument("--root", help="Project root (default: current directory)")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    args = ap.parse_args()

    root = Path(args.root).resolve() if args.root else Path.cwd()
    trackers = [t for t in sorted(root.glob("**/progress-tracker.json"))
                if ".sk-test" not in str(t)]
    if not trackers:
        raise SystemExit(f"No progress-tracker.json found under {root}")

    tokens = estimate_tokens(args, root)
    print(f"Logging {tokens:,} tokens to {args.epic}"
          + (f"/{args.story}" if args.story else "")
          + f" [{args.contributor}] — {args.activity}")
    updated = 0
    for tp in trackers:
        if log_one(tp, args, tokens):
            updated += 1
            print(f"  ✓ {tp}")
    if not updated:
        raise SystemExit("No tracker updated (epic not found?).")
    print("Done. Commit to publish (pre-commit hook syncs the dashboards).")


if __name__ == "__main__":
    main()
