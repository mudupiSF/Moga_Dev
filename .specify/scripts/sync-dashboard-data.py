#!/usr/bin/env python3
"""
Sync the dashboard's embedded fallback data from its progress-tracker.json.

The dashboard (progress-dashboard.html) renders 100% dynamically:
  - Primary source: live fetch of ./progress-tracker.json (GitHub Pages / any http server)
  - Fallback source: an embedded <script id="embedded-data"> JSON island (for file:// viewing)

progress-tracker.json is the single source of truth. This script copies it into the
embedded island so the offline fallback never goes stale. Run it after editing the JSON:

    python3 scripts/sync-dashboard-data.py

It updates every <docs>/progress-dashboard.html that has a sibling progress-tracker.json.
"""
import json
import re
import sys
from pathlib import Path

# Search root: first CLI arg, else the current working directory (the project root).
# This keeps the script portable — it works whether it lives in <repo>/scripts/
# or is shipped inside a project's .specify/scripts/ folder.
ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
ISLAND_RE = re.compile(
    r'(<script type="application/json" id="embedded-data">)(.*?)(</script>)',
    re.S,
)


def sync(html_path: Path) -> bool:
    tracker = html_path.parent / "progress-tracker.json"
    if not tracker.exists():
        print(f"  skip {html_path} (no sibling progress-tracker.json)")
        return False
    data = json.loads(tracker.read_text())
    mini = json.dumps(data, separators=(",", ":"))
    html = html_path.read_text()
    if not ISLAND_RE.search(html):
        print(f"  warn {html_path} has no embedded-data island")
        return False
    new_html = ISLAND_RE.sub(lambda m: m.group(1) + "\n" + mini + "\n    " + m.group(3), html)
    if new_html != html:
        html_path.write_text(new_html)
        print(f"  synced {html_path}  (epics={data['summary']['total_epics']}, tokens={data['summary']['total_tokens']})")
        return True
    print(f"  ok {html_path} (already up to date)")
    return False


def main() -> int:
    dashboards = sorted(ROOT.glob("**/progress-dashboard.html"))
    dashboards = [d for d in dashboards if ".sk-test" not in str(d)]
    if not dashboards:
        print("No progress-dashboard.html files found.")
        return 1
    print(f"Syncing {len(dashboards)} dashboard(s):")
    for d in dashboards:
        sync(d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
