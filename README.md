# deploy_agent

A shell-scripted deployment agent for the Student Attendance Tracker (a
Python application). `deploy_agent.sh` deploys the app, runs it, and
archives its logs, with clean handling of Ctrl+C / Ctrl+Z while deploying.

## Layout

```
.
├── deploy_agent.sh
├── templates/
│   ├── attendance_checker.py   # unmodified, deployed as-is
│   ├── assets.csv              # sample roster, 10 students, 4 prior sessions each
│   └── config.json             # default thresholds/config
└── attendance_tracker_<name>/  # created by the deploy feature, one per project
    ├── attendance_checker.py
    ├── Helpers/
    │   ├── assets.csv
    │   └── config.json
    ├── reports/                # attendance.log / absent.log land here after a run
    └── archives/                # created by the archive feature
        ├── attendance/
        └── absent/
```

## Running the script and picking a feature

`deploy_agent.sh` offers its three features two ways:

- **No arguments** — shows an interactive numbered menu:
  ```
  ./deploy_agent.sh
  ```
- **A flag** — jumps straight to a feature, useful for scripting or demos:
  ```
  ./deploy_agent.sh deploy
  ./deploy_agent.sh run [project_name]
  ./deploy_agent.sh archive [project_name]
  ```
  If `project_name` is omitted for `run`/`archive`, the script asks for it
  with `read`.

Project names are passed without the `attendance_tracker_` prefix — e.g.
entering `v1` deploys/targets `attendance_tracker_v1/`.

## Feature 1: Deploy

1. Checks that `python3` and `zip` are installed; exits with a clear error
   if either is missing.
2. Asks for a project name and creates `attendance_tracker_<name>/`. If
   that directory already exists, it asks whether to overwrite it; "no"
   aborts with an error instead of touching anything.
3. Copies `templates/attendance_checker.py` and `templates/config.json`
   into the new project unmodified.
4. Asks how to build `Helpers/assets.csv`:
   - **A** — copies the first *N* students from `templates/assets.csv`
     (prompts for *N*). Those sample rows carry 4 prior sessions each, so
     `total_sessions` is set to **5** (4 prior + today).
   - **B** — generates *N* fresh students from built-in name arrays, all
     counts starting at 0. Since there are no prior sessions,
     `total_sessions` is set to **1** (today is session one).
5. Sets permissions: `attendance_checker.py` is made executable
   (`chmod +x`), and `Helpers/config.json` is restricted to the owner
   (`chmod 600`), since it holds grading-sensitive thresholds. The script
   prints the resulting mode for both.
6. Asks whether to update the alert thresholds. If yes, it reads new
   `warning` (default 75) and `failure` (default 50) values and edits
   `Helpers/config.json` in place with `sed`, targeting only the
   `"warning": <number>` and `"failure": <number>` lines so the rest of
   the file's formatting is untouched.
7. Verifies the deployment by immediately invoking **Feature 2** on the
   new project — if the app starts and prompts for the first student, the
   structure, roster and config all work together.

## Feature 2: Run

Runs an already-deployed project:

```bash
cd attendance_tracker_<name>
python3 attendance_checker.py
```

The app is interactive — it hands the terminal to the instructor to mark
each student present/absent, updates `Helpers/assets.csv`, and writes
`reports/attendance.log` / `reports/absent.log`.

### Crash protection

Before starting the app, Feature 2 checks that:

- stdin is a real terminal (the app is interactive);
- `Helpers/config.json` is valid JSON with numeric thresholds and
  `total_sessions` >= 1;
- `Helpers/assets.csv` has the `Email,Names,Attendance Count,Absence Count`
  header, at least one student, and whole-number counts;
- the roster and `reports/` are writable.

If any check fails, it prints what is wrong and exits with status 1 instead
of letting Python print a traceback. A non-zero exit from the app is also
reported, and Ctrl+C during a session prints a short message.

## Feature 3: Archive the logs

After a run, this feature copies whatever logs exist into timestamped,
per-type archive directories:

```
attendance_tracker_<name>/archives/attendance/attendance_YYYYMMDD_HHMMSS.log
attendance_tracker_<name>/archives/absent/absent_YYYYMMDD_HHMMSS.log
```

- Each log type gets its own subdirectory under `archives/`.
- The timestamp in the filename (`date +%Y%m%d_%H%M%S`) means every
  archived copy is unique, so running archive multiple times never
  overwrites an earlier one.
- If `reports/attendance.log` or `reports/absent.log` doesn't exist (for
  example nobody was marked absent, so no `absent.log` was ever created),
  the script reports that plainly and continues instead of crashing.
- The script prints each archived file's final path as confirmation.

## Signal handling: Ctrl+C and Ctrl+Z during deploy

`trap` is armed on `SIGINT` and `SIGTSTP` for the whole duration of
Feature 1 (from the moment the project directory is created, through
roster/config population), and disarmed again right before Feature 1
hands off to Feature 2 for verification.

On either signal, the handler:

1. Prints a message explaining the deployment was interrupted.
2. Zips whatever currently exists of `attendance_tracker_<name>/` into
   `attendance_tracker_<name>_archive.zip` (using `zip`, from the
   script's own directory, so the archive contains clean relative paths
   rather than absolute ones).
3. Exits the script cleanly (status 130) instead of leaving a half-made
   directory with no trace of what happened.

**To test it yourself:** run `./deploy_agent.sh deploy`, answer the
project-name prompt, and while it's sitting at the next prompt (roster
choice, or any later prompt), press **Ctrl+C** (or **Ctrl+Z**). You'll see
the interrupt message and find `attendance_tracker_<name>_archive.zip`
next to `deploy_agent.sh` — `unzip -l` it to see exactly what had been
created before the interrupt. The original partial directory is left in
place as well (the trap only archives; it doesn't delete anything), so
you can inspect both side by side.

## How I tested the deployed application structure

Besides the interactive run-throughs described above, I verified:

- **Option A deploy** (copy N students) end-to-end: correct row count
  copied, `total_sessions` set to 5, permissions `755`/`600`, a full
  marking session, roster counts updated correctly, and both
  `attendance.log`/`absent.log` written with the right present/absent
  split.
- **Option B deploy** (fresh roster): generated rows start at `0,0`,
  `total_sessions` set to 1.
- **Overwrite prompt**: declining leaves the existing directory
  untouched and aborts; accepting removes and recreates it.
- **Standalone run** (`./deploy_agent.sh run <name>`) on an
  already-deployed project.
- **Archive**, run twice in a row — confirmed two distinct timestamped
  files are kept rather than one overwriting the other, and that a
  missing `absent.log` is reported gracefully rather than erroring.
- **`shellcheck deploy_agent.sh`** — no warnings.
- **SIGINT and SIGTSTP** sent mid-deploy (via a FIFO feeding the name
  prompt, then a signal sent to the backgrounded process) — both produced
  the interrupt message, exit status 130, and a valid zip archive with
  clean relative paths, leaving the partial directory intact for
  inspection.

## Notes

- `attendance_checker.py` is never modified by this project — it's copied
  verbatim from `templates/` into every deployed project.
- The script works from wherever it's invoked via `./deploy_agent.sh`,
  because it resolves its own directory (`$BASH_SOURCE[0]`) and always
  creates/targets `attendance_tracker_<name>/` next to itself, not in the
  caller's current working directory.
