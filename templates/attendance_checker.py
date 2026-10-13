#!/usr/bin/env python3
"""
attendance_checker.py

Interactive classroom attendance marking tool.

Expected layout (relative to the directory this script is run from):
    ./Helpers/assets.csv   - the class roster
    ./Helpers/config.json  - alert thresholds and session settings
    ./reports/             - created if missing; attendance.log / absent.log
                              are written here after a marking session.

Do not modify this file - it is deployed unmodified by deploy_agent.sh.
"""

import csv
import json
import os
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS_PATH = os.path.join(ROOT, "Helpers", "assets.csv")
CONFIG_PATH = os.path.join(ROOT, "Helpers", "config.json")
REPORTS_DIR = os.path.join(ROOT, "reports")
ATTENDANCE_LOG = os.path.join(REPORTS_DIR, "attendance.log")
ABSENT_LOG = os.path.join(REPORTS_DIR, "absent.log")


def load_config():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def load_roster():
    with open(ASSETS_PATH, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = reader.fieldnames
        rows = list(reader)
    return fieldnames, rows


def save_roster(fieldnames, rows):
    with open(ASSETS_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def ask_present(name):
    while True:
        answer = input(f"Was {name} present today? (y/n): ").strip().lower()
        if answer in ("y", "yes"):
            return True
        if answer in ("n", "no"):
            return False
        print("Please answer y or n.")


def main():
    try:
        config = load_config()
    except FileNotFoundError:
        print(f"Error: config file not found at {CONFIG_PATH}", file=sys.stderr)
        sys.exit(1)

    try:
        fieldnames, rows = load_roster()
    except FileNotFoundError:
        print(f"Error: roster file not found at {ASSETS_PATH}", file=sys.stderr)
        sys.exit(1)

    thresholds = config.get("thresholds", {})
    warning = thresholds.get("warning", 75)
    failure = thresholds.get("failure", 50)
    total_sessions = config.get("total_sessions", 1)
    run_mode = config.get("run_mode", "live")

    print(f"=== Attendance Checker ({run_mode} mode) ===")
    print(f"Total sessions (including today): {total_sessions}")
    print(f"Thresholds: warning < {warning}%, failure < {failure}%\n")

    present_entries = []
    absent_entries = []
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    for row in rows:
        name = row.get("Names", "Unknown")
        email = row.get("Email", "")
        present = ask_present(name)

        att = int(row.get("Attendance Count", 0) or 0)
        absn = int(row.get("Absence Count", 0) or 0)

        if present:
            att += 1
            present_entries.append(f"{timestamp} - {name} ({email}) - Present")
        else:
            absn += 1
            absent_entries.append(f"{timestamp} - {name} ({email}) - Absent")

        row["Attendance Count"] = str(att)
        row["Absence Count"] = str(absn)

        pct = (att / total_sessions) * 100 if total_sessions else 0
        if pct < failure:
            print(f"  ALERT: {name} is at {pct:.1f}% attendance (below failure threshold)")
        elif pct < warning:
            print(f"  WARNING: {name} is at {pct:.1f}% attendance (below warning threshold)")

    save_roster(fieldnames, rows)

    os.makedirs(REPORTS_DIR, exist_ok=True)

    if present_entries:
        with open(ATTENDANCE_LOG, "a", encoding="utf-8") as f:
            f.write("\n".join(present_entries) + "\n")

    if absent_entries:
        with open(ABSENT_LOG, "a", encoding="utf-8") as f:
            f.write("\n".join(absent_entries) + "\n")

    print("\nSession complete.")
    print(f"  Present: {len(present_entries)}")
    print(f"  Absent:  {len(absent_entries)}")
    print(f"Roster updated: {ASSETS_PATH}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nSession interrupted.")
        sys.exit(130)
