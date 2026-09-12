#!/usr/bin/env python3
"""Memory staleness report — auto-memory files not accessed in N days.

Reads the `last_accessed` / `access_count` frontmatter that hooks/memory-access-tracker.sh
maintains and reports, per memory directory:
- Stale files (older than --days since last access)
- Never-accessed files (no last_accessed field)
- Active files (recently accessed)
- MEMORY.md index size against its 200-line budget

By default it scans every Claude Code project memory dir, ~/.claude/projects/*/memory.
Pass --dir (repeatable) to scan specific ones. --archive moves stale files into a stale/
subdirectory of their own memory dir.

Usage:
    python3 ~/Repositories/dotfiles/claude/scripts/memory-cleanup.py [--days 90] [--dir PATH]... [--archive]

Moved from fredabood/homelab internal/scripts/memory-cleanup.py (LAB-93, homelab#1861).
"""
import argparse
import sys
from datetime import datetime, timedelta
from pathlib import Path


PROJECTS_DIR = Path.home() / ".claude" / "projects"
STALE_THRESHOLD_DAYS = 90


def parse_frontmatter(path: Path) -> dict:
    """Extract YAML frontmatter fields from a markdown file."""
    text = path.read_text()
    lines = text.split("\n")
    if not lines or lines[0] != "---":
        return {}

    end = -1
    for i in range(1, len(lines)):
        if lines[i] == "---":
            end = i
            break
    if end < 0:
        return {}

    fm = {}
    for line in lines[1:end]:
        if ":" in line:
            key, _, val = line.partition(":")
            fm[key.strip()] = val.strip()
    return fm


def analyze_memory(memory_dir: Path, stale_days: int) -> dict:
    """Analyze all memory files for staleness."""
    today = datetime.now()
    cutoff = today - timedelta(days=stale_days)

    stale = []
    active = []
    never_accessed = []

    for f in sorted(memory_dir.glob("*.md")):
        if f.name == "MEMORY.md":
            continue

        fm = parse_frontmatter(f)
        name = fm.get("name", f.stem)
        mem_type = fm.get("type", "unknown")
        description = fm.get("description", "")
        last_accessed = fm.get("last_accessed", "")
        access_count = fm.get("access_count", "0")

        entry = {
            "file": f.name,
            "name": name,
            "type": mem_type,
            "description": description[:80],
            "last_accessed": last_accessed,
            "access_count": int(access_count) if access_count.isdigit() else 0,
        }

        if not last_accessed:
            never_accessed.append(entry)
        else:
            try:
                last_dt = datetime.strptime(last_accessed, "%Y-%m-%d")
                days_ago = (today - last_dt).days
                entry["days_ago"] = days_ago
                if last_dt < cutoff:
                    stale.append(entry)
                else:
                    active.append(entry)
            except ValueError:
                never_accessed.append(entry)

    # Count MEMORY.md lines
    memory_index = memory_dir / "MEMORY.md"
    index_lines = 0
    if memory_index.exists():
        index_lines = len(memory_index.read_text().strip().split("\n"))

    return {
        "stale": sorted(stale, key=lambda x: x.get("days_ago", 999), reverse=True),
        "active": sorted(active, key=lambda x: x.get("days_ago", 0)),
        "never_accessed": never_accessed,
        "index_lines": index_lines,
        "total_files": len(stale) + len(active) + len(never_accessed),
    }


def print_report(analysis: dict, stale_days: int) -> None:
    """Print the staleness report."""
    print("=" * 70)
    print(f"Memory Staleness Report — threshold: {stale_days} days")
    print("=" * 70)
    print()

    # Summary
    print(f"Total memory files: {analysis['total_files']}")
    print(f"MEMORY.md lines: {analysis['index_lines']}/200")
    print(f"Active: {len(analysis['active'])}")
    print(f"Stale (>{stale_days}d): {len(analysis['stale'])}")
    print(f"Never accessed: {len(analysis['never_accessed'])}")
    print()

    # Stale files
    if analysis["stale"]:
        print(f"--- STALE ({len(analysis['stale'])} files) ---")
        for e in analysis["stale"]:
            print(f"  {e['file']:<45} {e['days_ago']:>4}d ago  [{e['type']}]")
        print()

    # Never accessed
    if analysis["never_accessed"]:
        print(f"--- NEVER ACCESSED ({len(analysis['never_accessed'])} files) ---")
        for e in analysis["never_accessed"]:
            print(f"  {e['file']:<45} [{e['type']}]  {e['description']}")
        print()

    # Active files
    if analysis["active"]:
        print(f"--- ACTIVE ({len(analysis['active'])} files) ---")
        for e in analysis["active"]:
            days = e.get("days_ago", "?")
            count = e.get("access_count", 0)
            print(f"  {e['file']:<45} {days:>4}d ago  x{count}  [{e['type']}]")
        print()

    # Recommendations
    total_stale = len(analysis["stale"]) + len(analysis["never_accessed"])
    if total_stale > 0:
        print("--- RECOMMENDATIONS ---")
        if analysis["stale"]:
            print(f"  Review {len(analysis['stale'])} stale files for archival or consolidation")
        if analysis["never_accessed"]:
            print(f"  Add last_accessed to {len(analysis['never_accessed'])} files (run memory-access-tracker hook)")
        if analysis["index_lines"] > 180:
            print(f"  MEMORY.md is at {analysis['index_lines']}/200 lines — consolidate entries")


def memory_dirs(explicit: list[str]) -> list[Path]:
    """The dirs to scan: --dir values, else every ~/.claude/projects/*/memory."""
    if explicit:
        return [Path(d).expanduser() for d in explicit]
    return sorted(p for p in PROJECTS_DIR.glob("*/memory") if p.is_dir())


def main():
    parser = argparse.ArgumentParser(description="Memory staleness report")
    parser.add_argument("--days", type=int, default=STALE_THRESHOLD_DAYS, help="Staleness threshold in days")
    parser.add_argument("--dir", action="append", default=[], help="Memory directory to scan (repeatable)")
    parser.add_argument("--archive", action="store_true", help="Archive stale files (moves to stale/ subdirectory)")
    args = parser.parse_args()

    dirs = memory_dirs(args.dir)
    missing = [d for d in dirs if not d.is_dir()]
    if missing:
        for d in missing:
            print(f"Memory directory not found: {d}")
        sys.exit(1)
    if not dirs:
        print(f"No memory directories under {PROJECTS_DIR}")
        sys.exit(2)

    for memory_dir in dirs:
        print(f"\n### {memory_dir}")
        analysis = analyze_memory(memory_dir, args.days)
        print_report(analysis, args.days)

        if args.archive and analysis["stale"]:
            archive_dir = memory_dir / "stale"
            archive_dir.mkdir(exist_ok=True)
            for entry in analysis["stale"]:
                (memory_dir / entry["file"]).rename(archive_dir / entry["file"])
                print(f"  Archived: {entry['file']} -> stale/")
            print(f"Archived {len(analysis['stale'])} stale files")


if __name__ == "__main__":
    main()
