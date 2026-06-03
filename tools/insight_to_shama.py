#!/usr/bin/env python3
"""Convert an Insight Timer export (logs CSV + journal TXT) into ShamaTimer's
session JSON, joining each session's journal note onto its log entry.

Insight Timer's "Export Data" produces two files:
  * InsightTimerLogs.csv   — one row per session: Started At, Duration, Preset, Activity
  * InsightTimerJournal.txt — blocks of `Timer Start` / `Timer Duration` / note text

The two are joined on (start time to the minute, duration in seconds), which is
reliable because the log keeps seconds in the start time while the journal only
keeps minutes, and durations match exactly.

Output is a JSON array of ShamaTimer session objects. It is faithful — ALL
activities and ALL durations are emitted; filtering (e.g. meditation-only,
skip < 1 min) happens in the app's Import dialog.

Usage:
    python3 insight_to_shama.py [LOGS_CSV] [JOURNAL_TXT] [-o OUT.json]

Defaults:
    LOGS_CSV    ~/Downloads/InsightTimerLogs.csv
    JOURNAL_TXT ~/Downloads/InsightTimerJournal.txt
    -o          stdout
"""
import argparse
import csv
import json
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path


def parse_log_duration(text):
    """'H:MM:SS' (parts may be unpadded) -> seconds."""
    parts = [int(p) for p in text.strip().split(":")]
    while len(parts) < 3:
        parts.insert(0, 0)
    h, m, s = parts[-3:]
    return h * 3600 + m * 60 + s


def parse_journal_duration(text):
    """'2 hrs 13 mins 5 secs' (any subset) -> seconds."""
    sec = 0
    for val, unit in re.findall(r"(\d+)\s*(hrs?|mins?|secs?)", text):
        val = int(val)
        if unit.startswith("hr"):
            sec += val * 3600
        elif unit.startswith("min"):
            sec += val * 60
        else:
            sec += val
    return sec


def clean_note(text):
    """Drop U+FFFD replacement chars (lost emoji from the export) and tidy space."""
    text = text.replace("�", "")
    text = re.sub(r"[ \t]+", " ", text)
    return text.strip()


def load_journal(path):
    """Return {(YYYY-MM-DD HH:MM, durationSec): note}."""
    raw = Path(path).read_bytes().decode("utf-8", "replace")
    notes = {}
    for block in raw.split("================================"):
        block = block.strip()
        if not block:
            continue
        start = dur = None
        note_lines = []
        for line in block.splitlines():
            if line.startswith("Timer Start:"):
                start = line.split(":", 1)[1].strip()
            elif line.startswith("Timer Duration:"):
                dur = line.split(":", 1)[1].strip()
            elif line.strip():
                note_lines.append(line.strip())
        if not start or not dur:
            continue
        dt = datetime.strptime(start, "%b %d,%Y %I:%M %p")
        key = (dt.strftime("%Y-%m-%d %H:%M"), parse_journal_duration(dur))
        note = clean_note(" ".join(note_lines))
        if note:
            notes[key] = note
    return notes


def iso_z(dt_utc):
    """Match JS toISOString(): YYYY-MM-DDTHH:MM:SS.000Z."""
    return dt_utc.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def build_sessions(logs_path, journal_path):
    notes = load_journal(journal_path) if Path(journal_path).exists() else {}
    sessions = []
    matched = 0
    activities = Counter()
    with open(logs_path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            started = row.get("Started At", "").strip()
            duration = row.get("Duration", "").strip()
            activity = (row.get("Activity", "") or "").strip() or "Meditation"
            if not started or not duration:
                continue
            # CSV wall-clock is local time -> aware-local -> UTC (so it renders
            # back to the same wall-clock on this machine).
            local = datetime.strptime(started, "%m/%d/%Y %H:%M:%S").astimezone()
            start_utc = local.astimezone(timezone.utc)
            dsec = parse_log_duration(duration)
            end_utc = start_utc + timedelta(seconds=dsec)
            key = (local.strftime("%Y-%m-%d %H:%M"), dsec)
            note = notes.get(key, "")
            if note:
                matched += 1
            activities[activity] += 1
            sessions.append({
                "id": int(local.timestamp() * 1000),
                "date": iso_z(start_utc),
                "endDate": iso_z(end_utc),
                "durationSec": dsec,
                "plannedSec": None,
                "complete": True,
                "mode": "imported",
                "source": "insight-timer",
                "activity": activity.lower(),
                "note": note,
            })
    return sessions, matched, activities


def main():
    home = Path.home()
    ap = argparse.ArgumentParser(description="Insight Timer export -> ShamaTimer JSON")
    ap.add_argument("logs", nargs="?", default=str(home / "Downloads/InsightTimerLogs.csv"))
    ap.add_argument("journal", nargs="?", default=str(home / "Downloads/InsightTimerJournal.txt"))
    ap.add_argument("-o", "--out", default=None, help="output file (default: stdout)")
    args = ap.parse_args()

    sessions, matched, activities = build_sessions(args.logs, args.journal)
    # de-dup by id (same start second) keeping the one that has a note
    by_id = {}
    for s in sessions:
        prev = by_id.get(s["id"])
        if prev is None or (not prev["note"] and s["note"]):
            by_id[s["id"]] = s
    sessions = sorted(by_id.values(), key=lambda s: s["date"], reverse=True)

    payload = json.dumps(sessions, ensure_ascii=False, indent=0)
    if args.out:
        Path(args.out).write_text(payload, encoding="utf-8")

    dates = [s["date"][:10] for s in sessions]
    print(
        f"sessions: {len(sessions)} | with note: {sum(1 for s in sessions if s['note'])} "
        f"(journal matched {matched}) | range: {min(dates)} .. {max(dates)}",
        file=sys.stderr,
    )
    print("by activity: " + ", ".join(f"{k}={v}" for k, v in activities.most_common()), file=sys.stderr)
    if args.out:
        print(f"written: {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(payload)


if __name__ == "__main__":
    main()
