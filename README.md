# deploy_agent_dingdongdash

Shell-scripted deploy/run/archive automation for the Student Attendance
Tracker Python app. `attendance_checker.py` itself is never modified -
everything here is scripting around it.

YT Video at https://github.com/dingdongdash/deploy_agent_dingdongdash

## Feature selection

`./deploy_agent.sh` always shows an interactive menu:

```
1) Deploy a new attendance tracker project
2) Run an existing deployed project
3) Archive logs from a deployed project
4) Exit
```

Pick a number and answer the prompts that follow. Feature 1 (Deploy) ends
by automatically invoking Feature 2 (Run) as a verification step, so a
fresh deploy immediately proves the structure/roster/config actually work
together.

## Deploy (Feature 1)

1. Pre-flight check: verifies `python3` and `zip` are on `PATH`, prints
   `python3 --version` and the `zip` version. Aborts with a clear error if
   either is missing.
2. Asks for a project name suffix and creates `attendance_tracker_<name>/`
   with `Helpers/` and an empty `reports/` inside the same directory as
   `deploy_agent.sh`. If that directory already exists you're asked to
   overwrite (deletes and recreates) or abort (existing directory is left
   untouched, nothing is clobbered).
3. Copies `templates/attendance_checker.py` and `templates/config.json`
   into place unmodified.
4. Asks how to build `Helpers/assets.csv`:
   - **Option A** - copy N rows (plus header) from `templates/assets.csv`
     (the sample roster, each row already carries 4 prior sessions).
     `config.json`'s `total_sessions` is left at its shipped value of `5`
     (4 prior + today's session).
   - **Option B** - generate N fresh rows from a built-in name/email pool,
     each starting at `0,0` (no prior sessions). Because there is no
     attendance history yet, this path uses `sed` to rewrite
     `"total_sessions"` down to `1` in the deployed `config.json` (today
     is session one). If you ask for more students than the name pool
     holds, names are reused with a numeric suffix to stay unique.
5. Sets permissions and prints confirmation:
   - `chmod +x attendance_checker.py`
   - `chmod 600 Helpers/config.json` (it holds grading-sensitive
     thresholds, so it's locked to owner read/write only)
6. Offers to update the alert thresholds. If you say yes, it reads new
   `warning` (default 75) and `failure` (default 50) values - each is
   validated as a whole number before use - and rewrites just those two
   lines in `Helpers/config.json` with `sed -E`, matching on
   `"warning": <number>` / `"failure": <number>` specifically. No
   reformatting, no reordering, no touching any other key.
7. Hands off to Feature 2 to prove the deployed project actually launches.

## Run (Feature 2)

```
cd attendance_tracker_<name>
python3 attendance_checker.py
```

This is interactive - it hands the terminal to you to mark each student
present/absent. That's expected; it updates `Helpers/assets.csv` and
writes `reports/attendance.log` / `reports/absent.log`.

## Archive (Feature 3)

After a run, pick option 3 and give the same project suffix. For each log
that exists it is copied (not moved) into its own timestamped directory
inside the project:

```
attendance_tracker_<name>/
└── archives/
    ├── attendance/attendance_YYYYMMDD_HHMMSS.log
    └── absent/absent_YYYYMMDD_HHMMSS.log
```

The timestamp (`date +%Y%m%d_%H%M%S`) is taken at archive time, so
re-running archive after another session produces new, non-colliding
files. If one of the two logs doesn't exist (e.g. nobody was marked
absent, so `absent.log` was never created), the script prints a clear
"nothing to archive" message for that log and continues - it does not
error out or crash.

## Ctrl+C / Ctrl+Z during deploy

The `SIGINT`/`SIGTSTP` trap is armed only while Feature 1 is building the
project directory (from right after the overwrite check, until right
before the verification run). It is deliberately **not** active once
`python3 attendance_checker.py` takes over, since `attendance_checker.py`
already handles its own `KeyboardInterrupt` during a live marking
session.

If either signal fires mid-deploy:

1. A clear interruption message is printed.
2. Whatever exists so far of `attendance_tracker_<name>/` is zipped into
   `attendance_tracker_<name>_archive.zip` next to the script (via
   `zip -r`).
3. The incomplete `attendance_tracker_<name>/` directory is then deleted,
   so no half-made project is left cluttering the workspace.
4. The script exits cleanly (exit code 130) instead of dumping a stack
   trace.

### How this was tested

Start a deploy, answer the project name, then press Ctrl+C or Ctrl+Z at
the roster-option prompt. Both signals were confirmed to: print the
interruption message, produce `attendance_tracker_<name>_archive.zip`
containing the partial directory tree, and remove
`attendance_tracker_<name>/` from disk.

## How the deployed app structure was verified

Beyond Feature 1 auto-invoking Feature 2, deployments were tested end to
end:

- Option A deploy with a handful of students, Option B deploy (confirming
  `total_sessions` became `1` via `grep` on the deployed `config.json`).
- Re-running deploy against an existing directory, once declining the
  overwrite (directory untouched) and once accepting it (directory
  recreated).
- `ls -l` on the deployed `attendance_checker.py` (executable bit set)
  and `Helpers/config.json` (mode `600`).
- Threshold update, diffing the deployed `config.json` against the
  template to confirm only the `warning`/`failure` lines changed.
- A full mock marking session via piped stdin (`p`/`a` answers) against
  the deployed `attendance_checker.py`, confirming `reports/attendance.log`
  and `reports/absent.log` were created with the expected per-student
  lines and percentage calculations.
- Feature 3 after that session, confirming both logs landed in their
  timestamped archive paths, and a second scenario where everyone was
  marked present (no `absent.log`) to confirm the graceful no-crash path.
