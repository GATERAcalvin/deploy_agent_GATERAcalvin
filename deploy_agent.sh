#!/usr/bin/env bash
# deploy_agent.sh
#
# Deployment agent for the Student Attendance Tracker.
#
# Features (picked from an interactive menu, or via a flag):
#   1) deploy  - scaffold a new attendance_tracker_{name}/ project
#   2) run     - run an already-deployed project's attendance_checker.py
#   3) archive - archive that project's reports/ logs with a timestamp
#
# Usage:
#   ./deploy_agent.sh            # interactive menu
#   ./deploy_agent.sh deploy     # go straight to the deploy feature
#   ./deploy_agent.sh run        # go straight to the run feature
#   ./deploy_agent.sh archive    # go straight to the archive feature
#
# See README.md for full documentation.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

PROJECT_DIR=""   # set once the user names/picks a project

# ---------------------------------------------------------------------------
# Signal handling (deploy feature only)
# ---------------------------------------------------------------------------
# While feature 1 is creating/populating a project, Ctrl+C (SIGINT) or
# Ctrl+Z (SIGTSTP) must not leave a half-made directory behind with no
# trace. Instead we zip whatever exists so far and exit cleanly.
handle_interrupt() {
	echo
	echo "Deployment interrupted! Archiving whatever was created so far..."
	if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
		local proj_base archive
		proj_base="$(basename "$PROJECT_DIR")"
		archive="${PROJECT_DIR}_archive.zip"
		( cd "$SCRIPT_DIR" && zip -r -q "${proj_base}_archive.zip" "$proj_base" )
		echo "Incomplete project archived to: $archive"
	else
		echo "Nothing had been created yet - nothing to archive."
	fi
	echo "Exiting deploy_agent.sh."
	exit 130
}

arm_deploy_traps() {
	trap handle_interrupt SIGINT SIGTSTP
}

disarm_deploy_traps() {
	trap - SIGINT SIGTSTP
}

# ---------------------------------------------------------------------------
# Feature 1: Deploy
# ---------------------------------------------------------------------------
preflight_checks() {
	local missing=0
	if ! command -v python3 >/dev/null 2>&1; then
		echo "Error: python3 is not installed. Please install it and try again." >&2
		missing=1
	fi
	if ! command -v zip >/dev/null 2>&1; then
		echo "Error: zip is not installed. Please install it and try again." >&2
		missing=1
	fi
	if [ "$missing" -eq 1 ]; then
		exit 1
	fi
	echo "Pre-flight checks passed: python3 and zip are available."
}

build_fresh_roster() {
	# Option B: generate a fresh roster of $1 students, counts starting at 0.
	local count="$1"
	local out="$2"

	local first_names=(Amara Noah Liang Sofia Kwame Mei Diego Priya Omar Yuki Elena Tariq Mariam Lucas Zara)
	local last_names=(Nkosi Johnson Wang Garcia Mensah Chen Rivera Patel Hassan Tanaka Ivanova Farouk Haddad Silva Okafor)

	echo "Email,Names,Attendance Count,Absence Count" > "$out"

	local i=0
	while [ "$i" -lt "$count" ]; do
		local fn="${first_names[$((i % ${#first_names[@]}))]}"
		local ln="${last_names[$((i % ${#last_names[@]}))]}"
		local name="${fn} ${ln}"
		local email
		email="$(echo "${fn}.${ln}${i}" | tr '[:upper:]' '[:lower:]')@example.com"
		echo "${email},${name},0,0" >> "$out"
		i=$((i + 1))
	done
}

set_total_sessions() {
	# Rewrites total_sessions in a config.json file in place, without
	# reformatting the rest of the file.
	local config_file="$1"
	local sessions="$2"
	sed -i.bak -E "s/(\"total_sessions\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${sessions}/" "$config_file"
	rm -f "${config_file}.bak"
}

deploy_feature() {
	preflight_checks

	read -r -p "Name for the project directory (attendance_tracker_<name>): " proj_name
	if [ -z "$proj_name" ]; then
		echo "Error: a project name is required." >&2
		exit 1
	fi

	PROJECT_DIR="$SCRIPT_DIR/attendance_tracker_${proj_name}"

	if [ -d "$PROJECT_DIR" ]; then
		read -r -p "Directory '$PROJECT_DIR' already exists. Overwrite? (y/n): " overwrite
		case "$overwrite" in
			y|Y|yes|YES)
				rm -rf "$PROJECT_DIR"
				;;
			*)
				echo "Aborting: '$PROJECT_DIR' already exists and was not overwritten." >&2
				exit 1
				;;
		esac
	fi

	# Everything from here on can be interrupted mid-way, so arm the traps.
	arm_deploy_traps

	mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports"

	cp "$TEMPLATES_DIR/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py"
	cp "$TEMPLATES_DIR/config.json" "$PROJECT_DIR/Helpers/config.json"

	echo
	echo "How should the roster (Helpers/assets.csv) be built?"
	echo "  A) Copy students from the template roster"
	echo "  B) Generate a fresh roster (all counts start at 0)"
	read -r -p "Choice (A/B): " roster_choice

	case "$roster_choice" in
		A|a)
			local max_students
			max_students=$(($(wc -l < "$TEMPLATES_DIR/assets.csv") - 1))
			read -r -p "How many students to copy (1-${max_students}): " n
			if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "$max_students" ]; then
				echo "Invalid number, defaulting to ${max_students}."
				n="$max_students"
			fi
			{ head -n 1 "$TEMPLATES_DIR/assets.csv"; tail -n +2 "$TEMPLATES_DIR/assets.csv" | head -n "$n"; } > "$PROJECT_DIR/Helpers/assets.csv"
			# Template rows carry 4 prior sessions each, so today is session 5.
			set_total_sessions "$PROJECT_DIR/Helpers/config.json" 5
			;;
		B|b)
			read -r -p "How many students to generate: " n
			if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ]; then
				echo "Invalid number, defaulting to 10."
				n=10
			fi
			build_fresh_roster "$n" "$PROJECT_DIR/Helpers/assets.csv"
			# A fresh roster has no prior sessions, so today is session 1.
			set_total_sessions "$PROJECT_DIR/Helpers/config.json" 1
			;;
		*)
			echo "Invalid choice. Aborting deployment." >&2
			disarm_deploy_traps
			rm -rf "$PROJECT_DIR"
			exit 1
			;;
	esac

	chmod +x "$PROJECT_DIR/attendance_checker.py"
	chmod 600 "$PROJECT_DIR/Helpers/config.json"
	echo
	echo "Permissions set:"
	echo "  attendance_checker.py -> $(stat -c '%A' "$PROJECT_DIR/attendance_checker.py" 2>/dev/null || stat -f '%Sp' "$PROJECT_DIR/attendance_checker.py") (executable)"
	echo "  Helpers/config.json   -> $(stat -c '%A' "$PROJECT_DIR/Helpers/config.json" 2>/dev/null || stat -f '%Sp' "$PROJECT_DIR/Helpers/config.json") (owner read/write only)"

	echo
	read -r -p "Update the attendance alert thresholds now? (y/n): " update_thresholds
	if [[ "$update_thresholds" =~ ^[yY] ]]; then
		read -r -p "Warning threshold %% [default 75]: " warning_val
		read -r -p "Failure threshold %% [default 50]: " failure_val
		warning_val="${warning_val:-75}"
		failure_val="${failure_val:-50}"
		sed -i.bak -E "s/(\"warning\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${warning_val}/" "$PROJECT_DIR/Helpers/config.json"
		sed -i.bak -E "s/(\"failure\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${failure_val}/" "$PROJECT_DIR/Helpers/config.json"
		rm -f "$PROJECT_DIR/Helpers/config.json.bak"
		echo "Thresholds updated: warning=${warning_val}, failure=${failure_val}"
	fi

	disarm_deploy_traps

	echo
	echo "Deployment structure created at: $PROJECT_DIR"
	echo
	echo "Verifying the deployment by running the application now..."
	echo "-----------------------------------------------------------"
	run_feature "$proj_name"
}

# ---------------------------------------------------------------------------
# Feature 2: Run
# ---------------------------------------------------------------------------
run_feature() {
	local proj_name="$1"
	if [ -z "$proj_name" ]; then
		read -r -p "Name of the deployed project (attendance_tracker_<name>): " proj_name
	fi

	local target="$SCRIPT_DIR/attendance_tracker_${proj_name}"
	if [ ! -d "$target" ]; then
		echo "Error: '$target' does not exist. Deploy it first." >&2
		return 1
	fi
	if [ ! -f "$target/attendance_checker.py" ]; then
		echo "Error: '$target/attendance_checker.py' not found." >&2
		return 1
	fi

	# The application is interactive; without a terminal, input() hits EOF.
	if [ ! -t 0 ]; then
		echo "Error: the attendance checker is interactive and needs a terminal (stdin is not a TTY)." >&2
		return 1
	fi

	if ! validate_project "$target"; then
		echo "Not running the application: fix the problem above and try again." >&2
		return 1
	fi

	local status=0
	(cd "$target" && python3 attendance_checker.py) || status=$?
	if [ "$status" -eq 130 ]; then
		echo "Session interrupted. Roster was not changed."
	elif [ "$status" -ne 0 ]; then
		echo "Error: the attendance checker exited with status $status." >&2
		return "$status"
	fi
}

# Validates Helpers/config.json and Helpers/assets.csv so the application
# never starts with input it cannot handle.
validate_project() {
	local target="$1"
	python3 -I - "$target" <<'PY'
import csv, json, os, sys

target = sys.argv[1]
cfg_path = os.path.join(target, "Helpers", "config.json")
csv_path = os.path.join(target, "Helpers", "assets.csv")
errors = []

def num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)

try:
    with open(cfg_path, encoding="utf-8") as f:
        cfg = json.load(f)
    if not isinstance(cfg, dict):
        errors.append("config.json must contain a JSON object")
    else:
        th = cfg.get("thresholds", {})
        if not isinstance(th, dict):
            errors.append("config.json: 'thresholds' must be an object")
        else:
            for k in ("warning", "failure"):
                if k in th and not num(th[k]):
                    errors.append(f"config.json: thresholds.{k} must be a number")
        ts = cfg.get("total_sessions", 1)
        if not isinstance(ts, int) or isinstance(ts, bool) or ts < 1:
            errors.append("config.json: total_sessions must be a whole number >= 1")
except FileNotFoundError:
    errors.append(f"missing {cfg_path}")
except (json.JSONDecodeError, UnicodeDecodeError) as e:
    errors.append(f"config.json is not valid JSON ({e})")
except OSError as e:
    errors.append(f"cannot read config.json ({e.strerror})")

try:
    with open(csv_path, encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        need = ["Email", "Names", "Attendance Count", "Absence Count"]
        if reader.fieldnames is None or any(c not in reader.fieldnames for c in need):
            errors.append("assets.csv header must contain: " + ", ".join(need))
        else:
            rows = list(reader)
            if not rows:
                errors.append("assets.csv has no students")
            for i, r in enumerate(rows, start=2):
                for c in ("Attendance Count", "Absence Count"):
                    v = (r.get(c) or "0").strip()
                    if not v.isdigit():
                        errors.append(f"assets.csv line {i}: '{c}' must be a whole number, got '{v}'")
except FileNotFoundError:
    errors.append(f"missing {csv_path}")
except (csv.Error, UnicodeDecodeError) as e:
    errors.append(f"assets.csv is not valid CSV ({e})")
except OSError as e:
    errors.append(f"cannot read assets.csv ({e.strerror})")

for p in (csv_path, os.path.join(target, "reports")):
    if os.path.exists(p) and not os.access(p, os.W_OK):
        errors.append(f"{p} is not writable")
os.makedirs(os.path.join(target, "reports"), exist_ok=True) if not errors else None

if errors:
    for e in errors[:10]:
        print("Error: " + e, file=sys.stderr)
    sys.exit(1)
PY
}

# ---------------------------------------------------------------------------
# Feature 3: Archive
# ---------------------------------------------------------------------------
archive_feature() {
	local proj_name="${1:-}"
	if [ -z "$proj_name" ]; then
		read -r -p "Name of the project to archive logs for (attendance_tracker_<name>): " proj_name
	fi

	local target="$SCRIPT_DIR/attendance_tracker_${proj_name}"
	if [ ! -d "$target" ]; then
		echo "Error: '$target' does not exist." >&2
		return 1
	fi

	local ts
	ts="$(date +%Y%m%d_%H%M%S)"
	local archived_any=0

	if [ -f "$target/reports/attendance.log" ]; then
		mkdir -p "$target/archives/attendance"
		local dest="$target/archives/attendance/attendance_${ts}.log"
		cp "$target/reports/attendance.log" "$dest"
		echo "Archived attendance log -> $dest"
		archived_any=1
	else
		echo "No reports/attendance.log found - nothing to archive for attendance."
	fi

	if [ -f "$target/reports/absent.log" ]; then
		mkdir -p "$target/archives/absent"
		local dest="$target/archives/absent/absent_${ts}.log"
		cp "$target/reports/absent.log" "$dest"
		echo "Archived absent log -> $dest"
		archived_any=1
	else
		echo "No reports/absent.log found - nothing to archive for absences (e.g. nobody was absent)."
	fi

	if [ "$archived_any" -eq 0 ]; then
		echo "Nothing was archived; no logs existed yet. Run the application first."
	fi
}

# ---------------------------------------------------------------------------
# Menu / entry point
# ---------------------------------------------------------------------------
show_menu() {
	echo "=================================="
	echo " Attendance Tracker Deploy Agent"
	echo "=================================="
	echo "1) Deploy a new project"
	echo "2) Run a deployed project"
	echo "3) Archive a project's logs"
	echo "4) Exit"
	read -r -p "Choose an option (1-4): " choice
	case "$choice" in
		1) deploy_feature ;;
		2) run_feature "" ;;
		3) archive_feature "" ;;
		4) exit 0 ;;
		*) echo "Invalid choice." ;;
	esac
}

main() {
	local mode="${1:-}"
	case "$mode" in
		deploy)
			deploy_feature
			;;
		run)
			run_feature "${2:-}"
			;;
		archive)
			archive_feature "${2:-}"
			;;
		"")
			show_menu
			;;
		*)
			echo "Usage: $0 [deploy|run|archive]" >&2
			exit 1
			;;
	esac
}

main "$@"
