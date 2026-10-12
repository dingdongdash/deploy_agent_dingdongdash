#!/usr/bin/env bash
#
# deploy_agent.sh - bootstraps, runs, and archives the Student Attendance
# Tracker application. Interactive menu with three features:
#   1) Deploy   2) Run   3) Archive logs
#
# SIGINT/SIGTSTP are trapped only while Feature 1 (deploy) is in progress.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

TEMPLATES_DIR="$SCRIPT_DIR/templates"
PROJECT_DIR=""   # set once the user names a project; used by the trap

# ---------------------------------------------------------------------------
# Signal handling (armed only during Feature 1)
# ---------------------------------------------------------------------------
interrupt_handler() {
    echo ""
    echo "!! Deployment interrupted - archiving whatever was created so far..."
    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        if zip -r "${PROJECT_DIR}_archive.zip" "$PROJECT_DIR" >/dev/null 2>&1; then
            rm -rf "$PROJECT_DIR"
            echo "   Archived to: ${PROJECT_DIR}_archive.zip"
            echo "   Removed incomplete directory: $PROJECT_DIR"
        else
            echo "   ERROR: failed to create ${PROJECT_DIR}_archive.zip (directory left in place)"
        fi
    else
        echo "   Nothing to archive yet - no partial project directory existed."
    fi
    echo "Exiting cleanly."
    trap - SIGINT SIGTSTP
    exit 130
}

arm_deploy_trap() {
    trap interrupt_handler SIGINT SIGTSTP
}

disarm_deploy_trap() {
    trap - SIGINT SIGTSTP
}

# ---------------------------------------------------------------------------
# Feature 1: Deploy
# ---------------------------------------------------------------------------
preflight_check() {
    local missing=0
    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is not installed or not on PATH." >&2
        missing=1
    fi
    if ! command -v zip >/dev/null 2>&1; then
        echo "ERROR: zip is not installed or not on PATH." >&2
        missing=1
    fi
    if [ "$missing" -eq 1 ]; then
        echo "Pre-flight check failed. Install the missing tool(s) and re-run." >&2
        return 1
    fi
    echo "Pre-flight check OK: $(python3 --version 2>&1), $(zip -v 2>&1 | head -n1)"
    return 0
}

# Build Helpers/assets.csv via Option A (copy N rows from templates/assets.csv)
build_roster_option_a() {
    local dest="$1" count="$2"
    local header total
    header=$(head -n 1 "$TEMPLATES_DIR/assets.csv")
    # awk's NR (unlike wc -l) counts a final line even without a trailing newline.
    total=$(( $(awk 'END{print NR}' "$TEMPLATES_DIR/assets.csv") - 1 ))
    if [ "$count" -gt "$total" ]; then
        echo "   Note: only $total template rows available; using $total instead of $count."
        count=$total
    fi
    {
        echo "$header"
        tail -n +2 "$TEMPLATES_DIR/assets.csv" | head -n "$count"
    } > "$dest"
}

# Build Helpers/assets.csv via Option B (fresh roster, counts start at 0)
build_roster_option_b() {
    local dest="$1" count="$2"
    local names=(
        "Grace Uwimana" "Kevin Mugisha" "Linda Mutesi" "Marcus Habimana"
        "Nadia Keza" "Oscar Niyonzima" "Priya Ingabire" "Quentin Bizimana"
        "Rita Umutoni" "Samuel Twagirayezu" "Teresa Mukamana" "Victor Nshimiyimana"
    )
    local emails=(
        "grace.uwimana@example.com" "kevin.mugisha@example.com" "linda.mutesi@example.com"
        "marcus.habimana@example.com" "nadia.keza@example.com" "oscar.niyonzima@example.com"
        "priya.ingabire@example.com" "quentin.bizimana@example.com" "rita.umutoni@example.com"
        "samuel.twagirayezu@example.com" "teresa.mukamana@example.com" "victor.nshimiyimana@example.com"
    )
    local n=${#names[@]}
    {
        echo "Email,Names,Attendance Count,Absence Count"
        local i idx suffix name email
        for (( i=0; i<count; i++ )); do
            idx=$(( i % n ))
            suffix=$(( i / n ))
            name="${names[$idx]}"
            email="${emails[$idx]}"
            if [ "$suffix" -gt 0 ]; then
                name="${name} ${suffix}"
                email="${email/@/+${suffix}@}"
            fi
            echo "${email},${name},0,0"
        done
    } > "$dest"
}

# Prompt until a positive integer is entered
read_positive_int() {
    local prompt="$1" default="${2:-}" value
    while true; do
        if [ -n "$default" ]; then
            read -r -p "$prompt [$default]: " value
            value="${value:-$default}"
        else
            read -r -p "$prompt: " value
        fi
        if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -gt 0 ]; then
            echo "$value"
            return 0
        fi
        echo "  Please enter a positive whole number." >&2
    done
}

deploy_feature() {
    preflight_check || return 1

    local suffix
    read -r -p "Enter a project name suffix (directory will be attendance_tracker_<name>): " suffix
    if [ -z "$suffix" ]; then
        echo "ERROR: project name suffix cannot be empty." >&2
        return 1
    fi

    PROJECT_DIR="attendance_tracker_${suffix}"

    if [ -d "$PROJECT_DIR" ]; then
        local answer
        read -r -p "Directory '$PROJECT_DIR' already exists. Overwrite? [y/N]: " answer
        case "$answer" in
            y|Y|yes|YES)
                rm -rf "$PROJECT_DIR"
                echo "Existing directory removed; proceeding with fresh deploy."
                ;;
            *)
                echo "Aborting deploy - existing directory left untouched."
                PROJECT_DIR=""
                return 1
                ;;
        esac
    fi

    arm_deploy_trap

    if ! mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports"; then
        echo "ERROR: could not create $PROJECT_DIR structure (permission denied?)." >&2
        disarm_deploy_trap
        return 1
    fi

    if ! cp "$TEMPLATES_DIR/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py"; then
        echo "ERROR: could not copy attendance_checker.py into $PROJECT_DIR (permission denied?)." >&2
        disarm_deploy_trap
        return 1
    fi
    if ! cp "$TEMPLATES_DIR/config.json" "$PROJECT_DIR/Helpers/config.json"; then
        echo "ERROR: could not copy config.json into $PROJECT_DIR/Helpers (permission denied?)." >&2
        disarm_deploy_trap
        return 1
    fi

    echo ""
    echo "How should the roster (Helpers/assets.csv) be built?"
    echo "  A) Copy rows from templates/assets.csv (sample students, 4 prior sessions each)"
    echo "  B) Generate a fresh roster (new students, 0 prior sessions)"
    local roster_choice
    read -r -p "Choose A or B: " roster_choice

    local student_count
    case "$roster_choice" in
        [Aa])
            student_count=$(read_positive_int "How many students to copy")
            build_roster_option_a "$PROJECT_DIR/Helpers/assets.csv" "$student_count"
            echo "Roster built via Option A ($student_count students, total_sessions stays 5)."
            ;;
        [Bb])
            student_count=$(read_positive_int "How many students to generate")
            build_roster_option_b "$PROJECT_DIR/Helpers/assets.csv" "$student_count"
            # Fresh roster = session one; keep config.total_sessions consistent.
            sed -i.bak -E 's/("total_sessions"[[:space:]]*:[[:space:]]*)[0-9]+/\11/' "$PROJECT_DIR/Helpers/config.json"
            rm -f "$PROJECT_DIR/Helpers/config.json.bak"
            echo "Roster built via Option B ($student_count students, total_sessions set to 1)."
            ;;
        *)
            echo "ERROR: invalid choice '$roster_choice'. Aborting deploy." >&2
            disarm_deploy_trap
            return 1
            ;;
    esac

    if ! chmod +x "$PROJECT_DIR/attendance_checker.py"; then
        echo "ERROR: could not chmod +x attendance_checker.py (permission denied?)." >&2
        disarm_deploy_trap
        return 1
    fi
    if ! chmod 600 "$PROJECT_DIR/Helpers/config.json"; then
        echo "ERROR: could not chmod 600 Helpers/config.json (permission denied?)." >&2
        disarm_deploy_trap
        return 1
    fi
    echo ""
    echo "Permissions set:"
    ls -l "$PROJECT_DIR/attendance_checker.py"
    ls -l "$PROJECT_DIR/Helpers/config.json"

    echo ""
    local update_thresholds
    read -r -p "Update attendance alert thresholds now? [y/N]: " update_thresholds
    case "$update_thresholds" in
        y|Y|yes|YES)
            local warning failure
            while true; do
                read -r -p "  New 'warning' threshold [75]: " warning
                warning="${warning:-75}"
                [[ "$warning" =~ ^[0-9]+$ ]] && break
                echo "    Please enter a whole number." >&2
            done
            while true; do
                read -r -p "  New 'failure' threshold [50]: " failure
                failure="${failure:-50}"
                [[ "$failure" =~ ^[0-9]+$ ]] && break
                echo "    Please enter a whole number." >&2
            done
            sed -i.bak -E "s/(\"warning\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${warning}/" "$PROJECT_DIR/Helpers/config.json"
            sed -i.bak -E "s/(\"failure\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${failure}/" "$PROJECT_DIR/Helpers/config.json"
            rm -f "$PROJECT_DIR/Helpers/config.json.bak"
            echo "  Thresholds updated: warning=$warning, failure=$failure"
            ;;
        *)
            echo "  Keeping default thresholds."
            ;;
    esac

    disarm_deploy_trap

    echo ""
    echo "Deploy complete: $PROJECT_DIR"
    echo "Verifying deployment by launching the application (Feature 2)..."
    echo ""
    run_feature "$suffix"
}

# ---------------------------------------------------------------------------
# Feature 2: Run
# ---------------------------------------------------------------------------
run_feature() {
    local suffix="$1"
    if [ -z "$suffix" ]; then
        read -r -p "Enter the project name suffix to run (attendance_tracker_<name>): " suffix
    fi
    local dir="attendance_tracker_${suffix}"
    if [ ! -d "$dir" ]; then
        echo "ERROR: $dir does not exist. Deploy it first." >&2
        return 1
    fi
    ( cd "$dir" && python3 attendance_checker.py )
}

# ---------------------------------------------------------------------------
# Feature 3: Archive
# ---------------------------------------------------------------------------
archive_feature() {
    local suffix="$1"
    if [ -z "$suffix" ]; then
        read -r -p "Enter the project name suffix to archive (attendance_tracker_<name>): " suffix
    fi
    local dir="attendance_tracker_${suffix}"
    if [ ! -d "$dir" ]; then
        echo "ERROR: $dir does not exist." >&2
        return 1
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local attendance_log="$dir/reports/attendance.log"
    local absent_log="$dir/reports/absent.log"

    if [ -f "$attendance_log" ]; then
        mkdir -p "$dir/archives/attendance"
        local dest="$dir/archives/attendance/attendance_${timestamp}.log"
        cp "$attendance_log" "$dest"
        echo "Archived attendance log -> $dest"
    else
        echo "No attendance.log found - nothing to archive for attendance."
    fi

    if [ -f "$absent_log" ]; then
        mkdir -p "$dir/archives/absent"
        local dest="$dir/archives/absent/absent_${timestamp}.log"
        cp "$absent_log" "$dest"
        echo "Archived absent log -> $dest"
    else
        echo "No absent.log found (e.g. nobody was absent) - nothing to archive for absences."
    fi
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
main_menu() {
    echo "=============================================="
    echo " Attendance Tracker Deploy Agent"
    echo "=============================================="
    echo "1) Deploy a new attendance tracker project"
    echo "2) Run an existing deployed project"
    echo "3) Archive logs from a deployed project"
    echo "4) Exit"
    read -r -p "Choose an option [1-4]: " choice
    case "$choice" in
        1) deploy_feature ;;
        2) run_feature "" ;;
        3) archive_feature "" ;;
        4) echo "Bye."; exit 0 ;;
        *) echo "Invalid choice." >&2; exit 1 ;;
    esac
}

main_menu
