#!/usr/bin/env bash
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  New Storage Setup
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Central visual theme for the full script.
YW="$(printf '\033[33m')"
BL="$(printf '\033[36m')"
RD="$(printf '\033[01;31m')"
BGN="$(printf '\033[4;92m')"
GN="$(printf '\033[1;92m')"
DGN="$(printf '\033[32m')"
CL="$(printf '\033[m')"
CLF="$(printf '\033[5m')"
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
WARN="${YW}!${CL}"
CROSS="${RD}✗${CL}"
BORDER="${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"

SCRIPT_SOURCE="2-newStorageSetup.sh"
SCRIPT_VERSION="v1.2.0"
SCRIPT_UPDATED="2026-05-22"
SCRIPT_BUILD="audit-untimed-inputs-crea-vm-storage"

# --- 2. GLOBAL VARIABLES ---
# Stores timer values, logs, selected disk state, LVM/Proxmox storage values and tuning state.
T=15
LOG_FILE="/var/log/new-storage-setup.log"
VERIFY_FILE="/var/log/new-storage-setup-verify.log"
COMPLETED_MARKER="/root/.new-storage-setup-completed"

SELECTED_DISK=""
SELECTED_DISK_NAME=""
DISK_TYPE="unknown"
DISK_BUS="unknown"
DISK_MODEL="unknown"
DISK_SIZE_BYTES="0"
DISK_SIZE_GB="0"
HAS_DATA="no"
DATA_RISK_REPORT=""

VG_NAME_DEFAULT="vg_crea_vm"
THINPOOL_NAME_DEFAULT="crea_vm_thin"
STORAGE_ID_DEFAULT="crea-vm"

VG_NAME=""
THINPOOL_NAME=""
STORAGE_ID=""
CONTENT_TYPES="images,rootdir"
THIN_PERCENT="95"

IS_SSD="no"
IS_NVME="no"
IO_SCHEDULER="skip"
IO_SCHEDULER_SERVICE=""

ROOT_PARENT_DISKS=""
MOUNTED_PARENT_DISKS=""
PV_PARENT_DISKS=""
BLOCKED_PARENT_DISKS=""
SAFE_DISKS=()
BLOCKED_DISKS=()

PV_CREATED="no"
VG_CREATED="no"
THINPOOL_CREATED="no"
STORAGE_REGISTERED="no"

TEMP_FILES=()

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
# Displays the New Storage Setup ASCII banner.
function header_info {
echo -e "${BL}
███╗   ██╗███████╗██╗    ██╗    ███████╗████████╗ ██████╗ ██████╗  █████╗  ██████╗ ███████╗
████╗  ██║██╔════╝██║    ██║    ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝ ██╔════╝
██╔██╗ ██║█████╗  ██║ █╗ ██║    ███████╗   ██║   ██║   ██║██████╔╝███████║██║  ███╗█████╗  
██║╚██╗██║██╔══╝  ██║███╗██║    ╚════██║   ██║   ██║   ██║██╔══██╗██╔══██║██║   ██║██╔══╝  
██║ ╚████║███████╗╚███╔███╔╝    ███████║   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╔╝███████╗
╚═╝  ╚═══╝╚══════╝ ╚══╝╚══╝     ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
${CL}"
}


# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent status messages for display -> apply -> success flow.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- SCRIPT VERSION DISPLAY ---
# Prints the currently running script version immediately under the ASCII banner.
function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

# --- 5. SECTION HEADER HELPER ---
# Keeps output clean and avoids repeated overwritten status messages.
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

# --- FLASHING SUCCESS SECTION HEADER HELPER ---
# Uses the standard final success layout with bold flashing green text.
function section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

# --- DETAIL LINE HELPER ---
# Prints clean script 1-style detail lines for summaries and audit output.
function detail_line() {
    local label="$1"
    local value="$2"
    echo -e " ${BL}━━━━━▶${CL} ${label}: ${GN}${value}${CL}"
}

# --- 6. TTY PRINT HELPER ---
# Prints directly to terminal even when functions return values through stdout.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 7. TTY PRINTLN HELPER ---
# Prints directly to terminal with newline.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# =========================================================
#  CLEANUP / ERROR HANDLING
# =========================================================

# --- 8. CLEANUP FUNCTION ---
# Removes temporary files created by run_cmd error capture.
function cleanup() {
    local exit_code="$?"

    for file in "${TEMP_FILES[@]:-}"; do
        [ -n "$file" ] && [ -f "$file" ] && rm -f "$file" 2>/dev/null || true
    done

    exit "$exit_code"
}

# --- 9. FAILURE HELP FUNCTION ---
# Prints useful recovery commands when the script fails after destructive storage actions.
function print_failure_recovery_hint() {
    echo ""
    echo -e "${RD}New Storage Setup did not complete successfully.${CL}"
    echo -e "${YW}Current state:${CL}"
    echo "  SELECTED_DISK: ${SELECTED_DISK:-unknown}"
    echo "  PV_CREATED: ${PV_CREATED}"
    echo "  VG_CREATED: ${VG_CREATED}"
    echo "  THINPOOL_CREATED: ${THINPOOL_CREATED}"
    echo "  STORAGE_REGISTERED: ${STORAGE_REGISTERED}"
    echo ""
    echo -e "${YW}Useful inspection commands:${CL}"
    echo "  pvs"
    echo "  vgs"
    echo "  lvs -a"
    echo "  pvesm status"
    echo "  wipefs -n ${SELECTED_DISK:-/dev/<disk>}"
    echo "  lsblk -f"
    echo ""
    echo -e "${YW}Do not rerun blindly if a PV/VG/thinpool was already created. Inspect first.${CL}"
    echo ""
}

# --- 10. ERROR TRAP HELPER ---
# Shows the failing line number and, when relevant, storage recovery hints.
function on_error() {
    local line_no="$1"

    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"

    if [ "$PV_CREATED" == "yes" ] || [ "$VG_CREATED" == "yes" ] || [ "$THINPOOL_CREATED" == "yes" ] || [ "$STORAGE_REGISTERED" == "yes" ]; then
        print_failure_recovery_hint
    fi
}

# --- 11. COMMAND RUNNER ---
# Runs critical commands quietly, but shows real stderr if they fail.
function run_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    if ! "$@" > /dev/null 2> "$err_file"; then
        echo ""
        echo -e "${RD}Command failed during:${CL} ${description}"
        echo -e "${YW}Command:${CL} $*"
        echo ""
        echo -e "${RD}Real error:${CL}"
        cat "$err_file"
        rm -f "$err_file"
        exit 1
    fi

    rm -f "$err_file"
}

# --- 12. OPTIONAL COMMAND RUNNER ---
# Runs non-critical commands quietly and never stops the script.
function run_optional() {
    "$@" > /dev/null 2>&1 || true
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 13. YES/NO LABEL HELPER ---
# Converts Y/N input into readable yes/no output.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 14. BLOCKING YES/NO HELPER ---
# Used when SPACE pauses a countdown and waits for Y/N/ENTER.
function tty_read_yes_no_blocking() {
    local prompt="$1"
    local default="$2"
    local default_label="Y/n"
    local key=""

    if [[ "$default" =~ ^[Nn]$ ]]; then
        default_label="y/N"
    fi

    while true; do
        tty_print "${BFR}${YW}${prompt} (${default_label}): ${CL}"

        if [ -r /dev/tty ]; then
            IFS= read -rsn1 key < /dev/tty || true
        else
            IFS= read -rsn1 key || true
        fi

        if [[ -z "$key" ]]; then
            tty_print "${BFR}"
            echo "$default"
            return 0
        elif [[ "$key" =~ ^[YyNn]$ ]]; then
            tty_print "${BFR}"
            echo "$key"
            return 0
        fi
    done
}

# --- 15. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown.
# SPACE pauses and waits.
# ENTER accepts default.
# Timeout accepts default.
# Final answer stays visible.
function timed_yes_no() {
    local prompt="$1"
    local default="$2"
    local answer=""
    local key=""
    local default_label="Y/n"
    local final_label=""
    local deadline=""
    local now=""
    local remaining=""

    if [[ "$default" =~ ^[Nn]$ ]]; then
        default_label="y/N"
    fi

    deadline=$(( $(date +%s) + T ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            answer="$default"
            break
        fi

        tty_print "${BFR}${YW}${prompt} (${default_label}) [${remaining}s]${CL} "

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                if [[ "$key" == " " ]]; then
                    answer="$(tty_read_yes_no_blocking "$prompt" "$default")"
                    break
                elif [[ "$key" =~ ^[YyNn]$ ]]; then
                    answer="$key"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(tty_read_yes_no_blocking "$prompt" "$default")"
                    break
                elif [[ "$key" =~ ^[YyNn]$ ]]; then
                    answer="$key"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                fi
            fi
        fi
    done

    [ -z "$answer" ] && answer="$default"
    final_label="$(yes_no_label "$answer")"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${final_label}${CL}"

    echo "$answer"
}

# --- 16. NUMERIC VALIDATION HELPER ---
# Validates numeric input against optional minimum and maximum values.
function validate_number() {
    local value="$1"
    local min_value="${2:-1}"
    local max_value="${3:-}"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$value" -lt "$min_value" ]; then
        return 1
    fi

    if [ -n "$max_value" ] && [ "$value" -gt "$max_value" ]; then
        return 1
    fi

    return 0
}

# --- 17. NUMERIC ERROR HELPER ---
# Shows a clear numeric validation error.
function print_number_error() {
    local min_value="${1:-1}"
    local max_value="${2:-}"

    if [ -n "$max_value" ]; then
        tty_println "${RD}Invalid input. Enter numbers only between ${min_value} and ${max_value}.${CL}"
    else
        tty_println "${RD}Invalid input. Enter numbers only. Minimum value is ${min_value}.${CL}"
    fi
}

# --- 18. EDITABLE INPUT LOOP HELPER ---
# Shared editable input system for text and numeric prompts.
# The initial key is passed into the same editable buffer, so Backspace/Delete can delete it.
function editable_input_loop() {
    local prompt="$1"
    local default="$2"
    local numeric_only="${3:-no}"
    local min_value="${4:-1}"
    local max_value="${5:-}"
    local initial_value="${6:-}"
    local answer="$initial_value"
    local key=""

    while true; do
        tty_print "${BFR}${YW}${prompt} [default: ${default}]: ${CL}${answer}"

        if [ -r /dev/tty ]; then
            IFS= read -rsn1 key < /dev/tty || true
        else
            IFS= read -rsn1 key || true
        fi

        case "$key" in
            "")
                [ -z "$answer" ] && answer="$default"

                if [ "$numeric_only" == "yes" ]; then
                    if validate_number "$answer" "$min_value" "$max_value"; then
                        tty_print "${BFR}"
                        echo "$answer"
                        return 0
                    fi

                    tty_print "${BFR}"
                    print_number_error "$min_value" "$max_value"
                    answer=""
                else
                    tty_print "${BFR}"
                    echo "$answer"
                    return 0
                fi
                ;;
            $'\177'|$'\b')
                answer="${answer%?}"
                ;;
            *)
                if [ "$numeric_only" == "yes" ]; then
                    if [[ "$key" =~ ^[0-9]$ ]]; then
                        answer+="$key"
                    else
                        tty_print "${BFR}"
                        print_number_error "$min_value" "$max_value"
                        answer=""
                    fi
                else
                    answer+="$key"
                fi
                ;;
        esac
    done
}

# --- 19. TIMED TEXT INPUT HELPER ---
# Shows wall-clock countdown.
# SPACE pauses with empty editable buffer.
# Any typed character pauses with that character already inside the editable buffer.
# Backspace/Delete can delete every typed character, including the first.
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""

    # Text/path/name inputs are deliberately NOT timed.
    # Countdown prompts are reserved only for simple Y/n decisions.
    # This prevents defaults being accepted while the user is away and gives enough time to type/paste.
    answer="$(editable_input_loop "$prompt" "$default" "no" "1" "" "")"
    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"

    echo "$answer"
}

# --- 20. TIMED NUMERIC INPUT HELPER ---
# Shows wall-clock countdown and validates numeric input.
# SPACE pauses with empty editable numeric buffer.
# Any typed digit pauses with that digit already inside the editable buffer.
# Timeout accepts default.
function timed_number_input() {
    local prompt="$1"
    local default="$2"
    local min_value="${3:-1}"
    local max_value="${4:-}"
    local answer=""

    # Numeric inputs are deliberately NOT timed.
    # Countdown prompts are reserved only for simple Y/n decisions.
    while true; do
        answer="$(editable_input_loop "$prompt" "$default" "yes" "$min_value" "$max_value" "")"
        [ -z "$answer" ] && answer="$default"

        if validate_number "$answer" "$min_value" "$max_value"; then
            tty_print "${BFR}"
            tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
            echo "$answer"
            return 0
        fi

        tty_print "${BFR}"
        print_number_error "$min_value" "$max_value"
    done
}

# =========================================================
#  VALIDATION HELPERS
# =========================================================

# --- 21. NAME VALIDATION HELPER ---
# Validates LVM and Proxmox storage names before destructive actions begin.
function validate_name_or_error() {
    local label="$1"
    local value="$2"
    local pattern="$3"

    if ! [[ "$value" =~ $pattern ]]; then
        msg_error "${label} contains invalid characters: ${value}"
    fi
}

# --- 22. RESERVED NAME VALIDATION HELPER ---
# Blocks names that are confusing or dangerous for this setup.
function reject_reserved_name_or_error() {
    local label="$1"
    local value="$2"

    case "$value" in
        local|local-lvm|pve|root|data|backup|iso|snippets)
            msg_error "${label} uses a reserved or confusing name: ${value}"
            ;;
    esac
}

# --- 23. CONTENT TYPE VALIDATION HELPER ---
# Validates Proxmox storage content type list.
function validate_content_types_or_error() {
    local value="$1"
    local item=""

    if [ -z "$value" ]; then
        msg_error "Content types cannot be empty."
    fi

    IFS=',' read -ra content_array <<< "$value"

    for item in "${content_array[@]}"; do
        item="$(echo "$item" | xargs)"

        case "$item" in
            images|rootdir|backup|iso|vztmpl|snippets|import)
                ;;
            *)
                msg_error "Invalid Proxmox content type: ${item}"
                ;;
        esac
    done
}

# =========================================================
#  DISK SAFETY HELPERS
# =========================================================

# --- 24. PARENT DISK HELPER ---
# Returns the parent disk name for a block path.
# Examples:
# /dev/sda2 -> sda
# /dev/nvme0n1p2 -> nvme0n1
# /dev/sdb -> sdb
function get_parent_disk_name() {
    local path="$1"
    local pkname=""
    local name=""

    [ -b "$path" ] || return 1

    pkname="$(lsblk -no PKNAME "$path" 2>/dev/null | head -n1 | xargs || true)"

    if [ -n "$pkname" ]; then
        echo "$pkname"
        return 0
    fi

    name="$(lsblk -no NAME "$path" 2>/dev/null | head -n1 | xargs || true)"

    if [ -n "$name" ]; then
        echo "$name"
        return 0
    fi

    basename "$path"
}

# --- 25. ADD UNIQUE WORD HELPER ---
# Maintains space-separated unique disk-name lists.
function add_unique_word() {
    local list="$1"
    local word="$2"

    [ -z "$word" ] && {
        echo "$list"
        return 0
    }

    if [[ " ${list} " == *" ${word} "* ]]; then
        echo "$list"
    else
        echo "${list} ${word}" | xargs
    fi
}

# --- 26. BUILD BLOCKED DISK LISTS ---
# Blocks OS/root/boot/EFI disks, mounted disks and existing PV-backed disks from being selectable.
function build_blocked_disk_lists() {
    local target=""
    local source=""
    local disk=""
    local pv=""
    local mounted_dev=""
    local type=""

    ROOT_PARENT_DISKS=""
    MOUNTED_PARENT_DISKS=""
    PV_PARENT_DISKS=""
    BLOCKED_PARENT_DISKS=""

    for target in / /boot /boot/efi /var/lib/vz; do
        source="$(findmnt -n -o SOURCE "$target" 2>/dev/null || true)"

        if [ -n "$source" ] && [ -b "$source" ]; then
            disk="$(get_parent_disk_name "$source" || true)"
            ROOT_PARENT_DISKS="$(add_unique_word "$ROOT_PARENT_DISKS" "$disk")"
        fi
    done

    while read -r mounted_dev type; do
        [ -z "$mounted_dev" ] && continue
        [ "$type" != "part" ] && [ "$type" != "disk" ] && continue

        if [ -b "$mounted_dev" ]; then
            disk="$(get_parent_disk_name "$mounted_dev" || true)"
            MOUNTED_PARENT_DISKS="$(add_unique_word "$MOUNTED_PARENT_DISKS" "$disk")"
        fi
    done < <(lsblk -rnpo NAME,TYPE,MOUNTPOINTS | awk '$3 != "" {print $1, $2}')

    while read -r pv; do
        [ -z "$pv" ] && continue

        if [ -b "$pv" ]; then
            disk="$(get_parent_disk_name "$pv" || true)"
            PV_PARENT_DISKS="$(add_unique_word "$PV_PARENT_DISKS" "$disk")"
        fi
    done < <(pvs --noheadings -o pv_name 2>/dev/null | xargs -n1 || true)

    for disk in $ROOT_PARENT_DISKS $MOUNTED_PARENT_DISKS $PV_PARENT_DISKS; do
        BLOCKED_PARENT_DISKS="$(add_unique_word "$BLOCKED_PARENT_DISKS" "$disk")"
    done
}

# --- 27. DISK BLOCK REASON HELPER ---
# Explains why a disk was blocked from selection.
function get_disk_block_reason() {
    local disk="$1"
    local reason=""

    if [[ " ${ROOT_PARENT_DISKS} " == *" ${disk} "* ]]; then
        reason+="root/boot/proxmox-storage "
    fi

    if [[ " ${MOUNTED_PARENT_DISKS} " == *" ${disk} "* ]]; then
        reason+="mounted-child "
    fi

    if [[ " ${PV_PARENT_DISKS} " == *" ${disk} "* ]]; then
        reason+="existing-LVM-PV "
    fi

    echo "${reason:-unknown}" | xargs
}

# --- 28. DISK DATA RISK REPORT HELPER ---
# Builds a detailed risk report for existing signatures, partitions, PVs, mdraid and ZFS labels.
function build_data_risk_report() {
    local disk="$1"
    local report=""
    local child_count="0"

    if wipefs -n "$disk" 2>/dev/null | grep -q .; then
        report+="filesystem/partition signatures detected"$'\n'
    fi

    child_count="$(lsblk -nr "$disk" | awk 'NR>1 {count++} END {print count+0}')"

    if [ "$child_count" -gt 0 ]; then
        report+="child partitions/devices detected (${child_count})"$'\n'
    fi

    if pvs "$disk" >/dev/null 2>&1; then
        report+="selected disk is an existing LVM PV"$'\n'
    fi

    if command -v mdadm >/dev/null 2>&1 && mdadm --examine "$disk" >/dev/null 2>&1; then
        report+="mdraid metadata detected"$'\n'
    fi

    if command -v zdb >/dev/null 2>&1 && zdb -l "$disk" >/dev/null 2>&1; then
        report+="possible ZFS label detected"$'\n'
    fi

    echo "$report"
}

# =========================================================
#  INITIALIZATION / ENVIRONMENT VALIDATION
# =========================================================

# --- 29. DEPENDENCY CHECK ---
# Ensures disk, LVM, Proxmox, systemd and tuning tools are available before any changes.
function validate_dependencies() {
    local required_commands=(
        awk
        basename
        blockdev
        cat
        chmod
        command
        cut
        date
        env
        findmnt
        grep
        head
        lsblk
        lvchange
        lvcreate
        lvs
        mkdir
        mktemp
        pvesm
        pvcreate
        pvs
        rm
        sed
        sgdisk
        sleep
        sort
        sysctl
        systemctl
        tee
        touch
        vgcfgbackup
        vgcreate
        vgs
        wipefs
        xargs
    )

    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Missing required command: $cmd"
    done
}


# --- 30. PROXMOX VALIDATION ---
# Confirms this is Proxmox VE 9+ before touching storage.
function validate_proxmox() {
    local pve_major=""

    if ! command -v pveversion >/dev/null 2>&1; then
        msg_error "This system is not Proxmox VE. Script cancelled."
    fi

    pve_major="$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)"

    if ! [[ "$pve_major" =~ ^[0-9]+$ ]] || [ "$pve_major" -lt 9 ]; then
        msg_error "Requires Proxmox VE 9+."
    fi
}

# --- 31. SCRIPT INITIALIZATION ---
# Starts logging, installs traps, validates root/proxmox/dependencies and shows banner.
function init_script() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RD}Please run as root.${CL}"
        exit 1
    fi

    exec > >(tee -a "$LOG_FILE") 2>&1

    trap 'on_error "$LINENO"' ERR
    trap cleanup EXIT

    clear
    header_info
    show_script_version

    validate_proxmox
    validate_dependencies
}

# --- 32. PREVIOUS RUN MARKER CHECK ---
# Warns if this setup was already completed before.
function check_previous_marker() {
    local continue_yn=""

    if [ -f "$COMPLETED_MARKER" ]; then
        section "PREVIOUS SETUP MARKER DETECTED"

        echo -e "${YW}A previous New Storage Setup marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        cat "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi
}

# =========================================================
#  DISK AUDIT / SELECTION
# =========================================================

# --- 33. DISK AUDIT BUILDER ---
# Builds safe and blocked disk lists.
# Root, mounted and existing PV-backed disks are blocked from selection.
function audit_disks() {
    local name=""
    local size=""
    local type=""
    local tran=""
    local rota=""
    local model=""
    local line=""
    local reason=""

    section "DISK AUDIT"

    msg_info "Building blocked disk safety list"
    build_blocked_disk_lists
    msg_ok "BLOCKED DISK SAFETY LIST BUILT"

    msg_info "Auditing available physical disks"

    SAFE_DISKS=()
    BLOCKED_DISKS=()

    while read -r line; do
        [ -z "$line" ] && continue

        name="$(echo "$line" | awk '{print $1}')"
        size="$(echo "$line" | awk '{print $2}')"
        type="$(echo "$line" | awk '{print $3}')"
        tran="$(echo "$line" | awk '{print $4}')"
        rota="$(echo "$line" | awk '{print $5}')"
        model="$(echo "$line" | cut -d' ' -f6- | xargs)"

        [ "$type" != "disk" ] && continue

        if [[ " ${BLOCKED_PARENT_DISKS} " == *" ${name} "* ]]; then
            reason="$(get_disk_block_reason "$name")"
            BLOCKED_DISKS+=("${name}|${size}|${tran:-unknown}|${rota}|${model:-unknown}|${reason}")
        else
            SAFE_DISKS+=("${name}|${size}|${tran:-unknown}|${rota}|${model:-unknown}")
        fi
    done < <(lsblk -dn -o NAME,SIZE,TYPE,TRAN,ROTA,MODEL)

    if [ "${#SAFE_DISKS[@]}" -eq 0 ]; then
        echo ""
        echo -e "${RD}No safe unused physical disks were found.${CL}"
        echo -e "${YW}Blocked disks:${CL}"

        for line in "${BLOCKED_DISKS[@]}"; do
            IFS='|' read -r name size tran rota model reason <<< "$line"
            echo "  /dev/${name} | ${size} | ${model} | reason=${reason}"
        done

        msg_error "No safe disk candidates available."
    fi

    msg_ok "DISK AUDIT COMPLETE"
}

# --- 34. DISK LIST DISPLAY ---
# Displays safe selectable disks and blocked disks separately.
function show_disk_lists() {
    local name=""
    local size=""
    local tran=""
    local rota=""
    local model=""
    local reason=""
    local dtype=""

    echo ""
    echo -e "${BL}SAFE SELECTABLE DISKS:${CL}"

    for i in "${!SAFE_DISKS[@]}"; do
        IFS='|' read -r name size tran rota model <<< "${SAFE_DISKS[$i]}"

        if [ "$rota" == "0" ]; then
            dtype="SSD"
        else
            dtype="HDD"
        fi

        printf " %b %2d) %-12s %-8s %-4s BUS=%-8s %s\n" \
            "${BL}━━━━━▶${CL}" \
            "$((i+1))" \
            "/dev/${name}" \
            "${size}" \
            "${dtype}" \
            "${tran:-unknown}" \
            "${model:-unknown}"
    done

    if [ "${#BLOCKED_DISKS[@]}" -gt 0 ]; then
        echo ""
        echo -e "${YW}BLOCKED DISKS:${CL}"

        for line in "${BLOCKED_DISKS[@]}"; do
            IFS='|' read -r name size tran rota model reason <<< "$line"
            printf " %b %-12s %-8s %s | reason=%s\n" \
                "${YW}━━━━━▶${CL}" \
                "/dev/${name}" \
                "${size}" \
                "${model:-unknown}" \
                "${reason}"
        done
    fi
}


# --- 35. DISK SELECTION ---
# Selects a safe disk using numeric validation.
function select_disk() {
    local disk_idx=""

    show_disk_lists

    disk_idx="$(timed_number_input "Select disk number to format" "1" "1" "${#SAFE_DISKS[@]}")"

    SELECTED_DISK_NAME="$(echo "${SAFE_DISKS[$((disk_idx-1))]}" | cut -d'|' -f1)"
    SELECTED_DISK="/dev/${SELECTED_DISK_NAME}"

    if [ ! -b "$SELECTED_DISK" ]; then
        msg_error "Selected disk is not a block device."
    fi
}

# --- 36. SELECTED DISK SMART DETECTION ---
# Detects SSD/HDD, NVMe/SATA/USB, disk size and existing signatures.
function inspect_selected_disk() {
    local rota=""
    local tran=""

    section "SELECTED DISK INSPECTION"

    msg_info "Inspecting selected disk"

    rota="$(lsblk -dn -o ROTA "$SELECTED_DISK" | xargs)"
    tran="$(lsblk -dn -o TRAN "$SELECTED_DISK" | xargs || true)"
    DISK_MODEL="$(lsblk -dn -o MODEL "$SELECTED_DISK" | xargs || true)"
    DISK_SIZE_BYTES="$(blockdev --getsize64 "$SELECTED_DISK")"
    DISK_SIZE_GB="$(( DISK_SIZE_BYTES / 1024 / 1024 / 1024 ))"

    if [ "$rota" == "0" ]; then
        IS_SSD="yes"
        DISK_TYPE="SSD"
    else
        IS_SSD="no"
        DISK_TYPE="HDD"
    fi

    if [[ "$(basename "$SELECTED_DISK")" =~ ^nvme ]]; then
        IS_NVME="yes"
        DISK_BUS="NVME"
    elif [ -n "$tran" ]; then
        DISK_BUS="${tran^^}"
    else
        DISK_BUS="UNKNOWN"
    fi

    DATA_RISK_REPORT="$(build_data_risk_report "$SELECTED_DISK")"

    if [ -n "$DATA_RISK_REPORT" ]; then
        HAS_DATA="yes"
    else
        HAS_DATA="no"
    fi

    msg_ok "SELECTED DISK INSPECTED"
}

# --- 37. SELECTED DISK SUMMARY ---
# Shows disk details and warns if data/signatures already exist.
function show_selected_disk_summary() {
    echo ""
    echo -e "${BL}SELECTED DISK:${CL}"
    echo -e " ${BL}━━━━━▶${CL} DISK: ${GN}${SELECTED_DISK}${CL}"
    echo -e " ${BL}━━━━━▶${CL} MODEL: ${GN}${DISK_MODEL:-unknown}${CL}"
    echo -e " ${BL}━━━━━▶${CL} TYPE/BUS: ${GN}${DISK_TYPE} / ${DISK_BUS}${CL}"
    echo -e " ${BL}━━━━━▶${CL} SIZE: ${GN}${DISK_SIZE_GB}GB${CL}"
    echo -e " ${BL}━━━━━▶${CL} EXISTING DATA/SIGNATURES: ${GN}${HAS_DATA}${CL}"

    if [ "$HAS_DATA" == "yes" ]; then
        echo ""
        echo -e "${RD}DATA RISK REPORT:${CL}"
        while read -r line; do
            [ -z "$line" ] && continue
            echo -e "  ${YW}!${CL} ${line}"
        done <<< "$DATA_RISK_REPORT"
    fi
}


# --- 38. FIRST DESTRUCTIVE CONFIRMATION ---
# If disk has data, default is NO. If disk looks empty, default is YES.
function first_destructive_confirmation() {
    local proceed_yn=""

    if [ "$HAS_DATA" == "yes" ]; then
        echo ""
        echo -e "${RD}WARNING: Existing data, partitions, or signatures were detected on ${SELECTED_DISK}.${CL}"
        proceed_yn="$(timed_yes_no "Destroy all data on ${SELECTED_DISK} and create Proxmox storage?" "n")"
    else
        proceed_yn="$(timed_yes_no "Create Proxmox storage on empty disk ${SELECTED_DISK}?" "y")"
    fi

    if [[ "$proceed_yn" =~ ^[Nn] ]]; then
        msg_error "Aborted by user."
    fi

    return 0

    return 0
}

# =========================================================
#  STORAGE CONFIGURATION INPUTS
# =========================================================

# --- 39. ADAPTIVE STORAGE NAMING ---
# Generates defaults based on SSD/HDD/NVMe/SATA/USB.
function set_adaptive_storage_defaults() {
    if [ "$IS_SSD" == "yes" ]; then
        STORAGE_ID_DEFAULT="data-ssd"
        VG_NAME_DEFAULT="vg_data_ssd"
        THINPOOL_NAME_DEFAULT="data_ssd_thin"
    else
        STORAGE_ID_DEFAULT="data-hdd"
        VG_NAME_DEFAULT="vg_data_hdd"
        THINPOOL_NAME_DEFAULT="data_hdd_thin"
    fi

    if [ "$IS_NVME" == "yes" ]; then
        STORAGE_ID_DEFAULT="data-nvme"
        VG_NAME_DEFAULT="vg_data_nvme"
        THINPOOL_NAME_DEFAULT="data_nvme_thin"
    fi
}

# --- 40. STORAGE NAME INPUTS ---
# Collects VG, thinpool and Proxmox storage ID with validation.
function collect_storage_names() {
    local valid_names="no"

    section "STORAGE CONFIGURATION"

    set_adaptive_storage_defaults

    while [ "$valid_names" != "yes" ]; do
        VG_NAME="$(timed_text_input "Enter VG name" "$VG_NAME_DEFAULT")"
        THINPOOL_NAME="$(timed_text_input "Enter thinpool name" "$THINPOOL_NAME_DEFAULT")"
        STORAGE_ID="$(timed_text_input "Enter Proxmox storage ID" "$STORAGE_ID_DEFAULT")"

        validate_name_or_error "VG name" "$VG_NAME" '^[a-zA-Z0-9_+.-]+$'
        validate_name_or_error "Thinpool name" "$THINPOOL_NAME" '^[a-zA-Z0-9_+.-]+$'
        validate_name_or_error "Storage ID" "$STORAGE_ID" '^[a-zA-Z0-9][a-zA-Z0-9_-]*$'

        reject_reserved_name_or_error "VG name" "$VG_NAME"
        reject_reserved_name_or_error "Thinpool name" "$THINPOOL_NAME"
        reject_reserved_name_or_error "Storage ID" "$STORAGE_ID"

        valid_names="yes"
    done
}

# --- 41. STORAGE CONFLICT CHECK ---
# Prevents naming collisions with existing Proxmox storage, VGs or LVs.
function check_storage_conflicts() {
    section "CONFLICT CHECK"

    msg_info "Checking for storage conflicts"

    if pvesm config "$STORAGE_ID" >/dev/null 2>&1; then
        msg_error "Proxmox storage ID ${STORAGE_ID} already exists."
    fi

    if vgs "$VG_NAME" >/dev/null 2>&1; then
        msg_error "Volume group ${VG_NAME} already exists."
    fi

    if lvs "${VG_NAME}/${THINPOOL_NAME}" >/dev/null 2>&1; then
        msg_error "Logical volume ${VG_NAME}/${THINPOOL_NAME} already exists."
    fi

    msg_ok "NO STORAGE CONFLICTS FOUND"
}


# --- 42. THINPOOL ALLOCATION LOGIC ---
# Uses adaptive allocation to leave free VG space for metadata growth and repair.
# Validates the final value to avoid failure after disk wipe.
function collect_thinpool_allocation() {
    if [ "$DISK_SIZE_GB" -lt 256 ]; then
        THIN_PERCENT="95"
    elif [ "$DISK_SIZE_GB" -lt 1024 ]; then
        THIN_PERCENT="92"
    else
        THIN_PERCENT="90"
    fi

    THIN_PERCENT="$(timed_number_input "Enter thinpool allocation percent" "$THIN_PERCENT" "50" "98")"
}

# --- 43. CONTENT TYPE SELECTION ---
# Sets storage content types. Defaults support VM images, containers and backups.
function collect_content_types() {
    CONTENT_TYPES="$(timed_text_input "Enter Proxmox content types" "$CONTENT_TYPES")"
    CONTENT_TYPES="$(echo "$CONTENT_TYPES" | tr -d ' ' | sed 's/,,*/,/g; s/^,//; s/,$//')"

    validate_content_types_or_error "$CONTENT_TYPES"
}

# --- 44. FINAL DESTRUCTIVE CONFIRMATION ---
# Final destructive confirmation before wiping disk.
function final_destructive_confirmation() {
    local final_yn=""

    section "READY TO CREATE STORAGE"

    echo -e "${RD}FINAL WARNING: ALL DATA ON ${SELECTED_DISK} WILL BE DESTROYED.${CL}"
    echo ""
    echo -e "${BL}DISK SAFETY CONTEXT:${CL}"
    echo -e " ${BL}━━━━━▶${CL} ROOT / BOOT / PVE DISKS: ${GN}${ROOT_PARENT_DISKS:-none}${CL}"
    echo -e " ${BL}━━━━━▶${CL} MOUNTED DISKS: ${GN}${MOUNTED_PARENT_DISKS:-none}${CL}"
    echo -e " ${BL}━━━━━▶${CL} EXISTING LVM PV DISKS: ${GN}${PV_PARENT_DISKS:-none}${CL}"
    echo ""
    echo -e "${BL}SELECTED STORAGE TARGET:${CL}"
    echo -e " ${BL}━━━━━▶${CL} DISK: ${GN}${SELECTED_DISK}${CL}"
    echo -e " ${BL}━━━━━▶${CL} MODEL: ${GN}${DISK_MODEL:-unknown}${CL}"
    echo -e " ${BL}━━━━━▶${CL} SIZE: ${GN}${DISK_SIZE_GB}GB${CL}"
    echo -e " ${BL}━━━━━▶${CL} STORAGE ID: ${GN}${STORAGE_ID}${CL}"
    echo -e " ${BL}━━━━━▶${CL} VG / THINPOOL: ${GN}${VG_NAME} / ${THINPOOL_NAME}${CL}"
    echo -e " ${BL}━━━━━▶${CL} THIN ALLOCATION: ${GN}${THIN_PERCENT}%FREE${CL}"
    echo -e " ${BL}━━━━━▶${CL} CONTENT: ${GN}${CONTENT_TYPES}${CL}"
    echo ""

    final_yn="$(timed_yes_no "Proceed with disk wipe and storage creation?" "n")"
    if [[ "$final_yn" =~ ^[Nn] ]]; then
        msg_error "Aborted by user."
    fi

    return 0

    return 0
}


# --- 45. DISK WIPE ---
# Clears old filesystem, partition and LVM signatures.
# Failures are critical and stop the script.
function wipe_selected_disk() {
    section "DISK WIPE"

    msg_info "Wiping filesystem signatures"
    run_cmd "wiping filesystem signatures on ${SELECTED_DISK}" wipefs -a "$SELECTED_DISK"
    msg_ok "FILESYSTEM SIGNATURES WIPED"

    msg_info "Zapping partition table"
    run_cmd "zapping partition table on ${SELECTED_DISK}" sgdisk --zap-all "$SELECTED_DISK"
    msg_ok "PARTITION TABLE ZAPPED"

    msg_info "Requesting kernel partition table reread"
    run_optional blockdev --rereadpt "$SELECTED_DISK"

    if command -v partprobe >/dev/null 2>&1; then
        run_optional partprobe "$SELECTED_DISK"
    fi

    if command -v udevadm >/dev/null 2>&1; then
        run_optional udevadm settle
    fi

    if command -v pvscan >/dev/null 2>&1; then
        run_optional pvscan --cache
    fi

    sleep 2
    msg_ok "DISK PREPARED"
}


# --- 46. LVM PHYSICAL VOLUME ---
# Creates an aligned LVM physical volume on the whole disk.
function create_lvm_physical_volume() {
    section "LVM PHYSICAL VOLUME"

    msg_info "Creating LVM physical volume"
    run_cmd "creating LVM physical volume on ${SELECTED_DISK}" pvcreate -y --force "$SELECTED_DISK"
    PV_CREATED="yes"
    msg_ok "PHYSICAL VOLUME CREATED"
}

# --- 47. LVM VOLUME GROUP ---
# Creates dedicated VG for this secondary storage device.
function create_lvm_volume_group() {
    section "LVM VOLUME GROUP"

    msg_info "Creating LVM volume group"
    run_cmd "creating LVM volume group ${VG_NAME}" vgcreate -y "$VG_NAME" "$SELECTED_DISK"
    VG_CREATED="yes"
    msg_ok "VOLUME GROUP CREATED"
}

# --- 48. LVM THINPOOL CREATION ---
# Creates thinpool with adaptive free-space reserve and automatic metadata sizing.
function create_lvm_thinpool() {
    section "LVM THINPOOL"

    msg_info "Creating LVM thinpool"
    run_cmd "creating LVM thinpool ${VG_NAME}/${THINPOOL_NAME}" lvcreate -y -l "${THIN_PERCENT}%FREE" --thinpool "$THINPOOL_NAME" "$VG_NAME"
    THINPOOL_CREATED="yes"
    msg_ok "LVM THINPOOL CREATED"

    msg_info "Enabling LVM thinpool monitoring"
    run_optional lvchange --monitor y "${VG_NAME}/${THINPOOL_NAME}"
    msg_ok "LVM THINPOOL MONITORING ENABLED"

    msg_info "Backing up LVM metadata"
    run_cmd "backing up LVM metadata for ${VG_NAME}" vgcfgbackup "$VG_NAME"
    msg_ok "LVM METADATA BACKED UP"
}


# --- 49. PROXMOX STORAGE REGISTRATION ---
# Registers the thinpool in Proxmox with selected content types and saferemove enabled.
function register_proxmox_storage() {
    section "PROXMOX STORAGE REGISTRATION"

    msg_info "Registering storage in Proxmox"

    run_cmd "registering Proxmox storage ${STORAGE_ID}" \
        pvesm add lvmthin "$STORAGE_ID" \
        --vgname "$VG_NAME" \
        --thinpool "$THINPOOL_NAME" \
        --content "$CONTENT_TYPES" \
        --saferemove 1

    STORAGE_REGISTERED="yes"

    msg_ok "STORAGE REGISTERED"
}

# --- 50. SSD TRIM LOGIC ---
# Enables fstrim timer only for SSD/NVMe devices.
function apply_trim_logic() {
    section "SSD TRIM"

    if [ "$IS_SSD" == "yes" ]; then
        msg_info "Enabling SSD TRIM"
        run_cmd "enabling fstrim.timer" systemctl enable --now fstrim.timer
        msg_ok "SSD TRIM ENABLED"
    else
        msg_ok "SSD TRIM NOT REQUIRED FOR HDD"
    fi
}

# --- 51. IO SCHEDULER SELECTOR ---
# Chooses a supported scheduler only when available.
function select_io_scheduler() {
    local dev_name="$1"
    local scheduler_file="/sys/block/${dev_name}/queue/scheduler"
    local supported=""

    IO_SCHEDULER="skip"

    if [ ! -e "$scheduler_file" ]; then
        return 0
    fi

    supported="$(cat "$scheduler_file" 2>/dev/null || true)"

    if [ "$IS_NVME" == "yes" ]; then
        if echo "$supported" | grep -qw "none"; then
            IO_SCHEDULER="none"
        elif echo "$supported" | grep -qw "mq-deadline"; then
            IO_SCHEDULER="mq-deadline"
        fi
    elif [ "$IS_SSD" == "yes" ]; then
        if echo "$supported" | grep -qw "mq-deadline"; then
            IO_SCHEDULER="mq-deadline"
        elif echo "$supported" | grep -qw "none"; then
            IO_SCHEDULER="none"
        fi
    else
        if echo "$supported" | grep -qw "mq-deadline"; then
            IO_SCHEDULER="mq-deadline"
        elif echo "$supported" | grep -qw "bfq"; then
            IO_SCHEDULER="bfq"
        fi
    fi
}

# --- 52. IO SCHEDULER LOGIC ---
# Applies and persists scheduler tuning only when the chosen scheduler is actually supported.
function apply_io_scheduler_tuning() {
    local dev_name=""
    local scheduler_file=""

    section "IO SCHEDULER TUNING"

    dev_name="$(basename "$SELECTED_DISK")"
    scheduler_file="/sys/block/${dev_name}/queue/scheduler"

    select_io_scheduler "$dev_name"

    if [ "$IO_SCHEDULER" == "skip" ]; then
        if [ -e "$scheduler_file" ]; then
            msg_warn "IO scheduler tuning skipped. Supported schedulers: $(cat "$scheduler_file" 2>/dev/null || echo unknown)"
        else
            msg_warn "IO scheduler tuning skipped. Scheduler file not present for ${dev_name}."
        fi
        return 0
    fi

    msg_info "Applying IO scheduler ${IO_SCHEDULER}"
    echo "$IO_SCHEDULER" > "$scheduler_file" 2>/dev/null || true
    msg_ok "IO SCHEDULER APPLIED (${IO_SCHEDULER})"

    IO_SCHEDULER_SERVICE="storage-${STORAGE_ID}-scheduler.service"

    msg_info "Writing IO scheduler systemd service"
    cat <<EOF > "/etc/systemd/system/${IO_SCHEDULER_SERVICE}"
[Unit]
Description=Apply IO Scheduler for ${STORAGE_ID}
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '[ -e /sys/block/${dev_name}/queue/scheduler ] && grep -qw "${IO_SCHEDULER}" /sys/block/${dev_name}/queue/scheduler && echo "${IO_SCHEDULER}" > /sys/block/${dev_name}/queue/scheduler || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    msg_ok "IO SCHEDULER SYSTEMD SERVICE WRITTEN"

    run_cmd "reloading systemd daemon" systemctl daemon-reload
    run_cmd "enabling ${IO_SCHEDULER_SERVICE}" systemctl enable "$IO_SCHEDULER_SERVICE"

    msg_ok "IO SCHEDULER TUNED (${IO_SCHEDULER})"
}

# --- 53. SWAPPINESS AND ZFS ARC TUNING ---
# Adds safe host-level memory defaults useful for VM/database workloads.
function apply_memory_tuning() {
    local total_mem_bytes=""
    local arc_max=""

    section "MEMORY TUNING"

    msg_info "Writing storage memory tuning sysctl file"
    cat <<EOF > /etc/sysctl.d/98-storage-memory-tuning.conf
vm.swappiness = 10
vm.vfs_cache_pressure = 100
EOF
    msg_ok "STORAGE MEMORY SYSCTL FILE WRITTEN"

    if [ -f /sys/module/zfs/parameters/zfs_arc_max ]; then
        msg_info "Writing ZFS ARC cap"
        total_mem_bytes="$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)"
        arc_max="$(( total_mem_bytes / 4 ))"

        cat <<EOF > /etc/modprobe.d/zfs-arc.conf
options zfs zfs_arc_max=${arc_max}
EOF
        msg_ok "ZFS ARC CAP WRITTEN"
    else
        msg_ok "ZFS ARC CAP NOT REQUIRED"
    fi

    msg_info "Applying sysctl settings"
    run_optional sysctl --system
    msg_ok "MEMORY TUNING APPLIED"
}

# =========================================================
#  VERIFICATION / MARKER / SUMMARY
# =========================================================

# --- 54. VERIFICATION SCRIPT ---
# Creates and runs a verification report after storage creation.
function create_verification_report() {
    local verify_script="/root/new_storage_verify.sh"

    section "VERIFICATION"

    msg_info "Creating verification report"

    TEMP_FILES+=("$verify_script")

    cat <<EOF > "$verify_script"
#!/usr/bin/env bash
set +e
: > "$VERIFY_FILE"
exec > >(tee -a "$VERIFY_FILE") 2>&1

echo "--- NEW STORAGE SETUP VERIFICATION REPORT ---"
echo "Date: \$(date)"
echo "Disk: ${SELECTED_DISK}"
echo "Disk Type: ${DISK_TYPE}"
echo "Disk Bus: ${DISK_BUS}"
echo "Storage ID: ${STORAGE_ID}"
echo "VG: ${VG_NAME}"
echo "Thinpool: ${THINPOOL_NAME}"
echo ""

PASS() { echo "✓ PASS - \$1"; }
WARN() { echo "! WARN - \$1"; }
FAIL() { echo "✗ FAIL - \$1"; }

if pvesm config "${STORAGE_ID}" >/dev/null 2>&1; then PASS "Proxmox storage config exists"; else FAIL "Proxmox storage config missing"; fi
if pvesm status 2>/dev/null | awk '{print \$1, \$3}' | grep -q "^${STORAGE_ID} active"; then PASS "Proxmox storage is active"; else WARN "Proxmox storage active state not confirmed"; fi
if vgs "${VG_NAME}" >/dev/null 2>&1; then PASS "VG exists"; else FAIL "VG missing"; fi
if lvs "${VG_NAME}/${THINPOOL_NAME}" >/dev/null 2>&1; then PASS "Thinpool exists"; else FAIL "Thinpool missing"; fi
if lvs -o lv_monitor --noheadings "${VG_NAME}/${THINPOOL_NAME}" 2>/dev/null | grep -q monitored; then PASS "Thinpool monitoring enabled"; else WARN "Thinpool monitoring not confirmed"; fi
if [ -f "/etc/lvm/backup/${VG_NAME}" ]; then PASS "LVM metadata backup exists"; else WARN "LVM metadata backup not found"; fi

echo ""
echo "Proxmox storage config:"
pvesm config "${STORAGE_ID}" 2>/dev/null || true

echo ""
echo "VG details:"
vgs -o vg_name,vg_size,vg_free "${VG_NAME}" 2>/dev/null || true

echo ""
echo "Thinpool usage:"
lvs -a -o lv_name,lv_size,data_percent,metadata_percent,lv_attr "${VG_NAME}" 2>/dev/null || true

echo ""
echo "Selected disk residual signatures after setup:"
wipefs -n "${SELECTED_DISK}" 2>/dev/null || true

echo ""
if [ "${IS_SSD}" == "yes" ]; then
    systemctl is-active --quiet fstrim.timer && PASS "SSD TRIM active" || FAIL "SSD TRIM inactive"
else
    WARN "SSD TRIM check skipped because selected disk is HDD"
fi

if [ -n "${IO_SCHEDULER_SERVICE}" ]; then
    systemctl is-enabled --quiet "${IO_SCHEDULER_SERVICE}" && PASS "IO scheduler service enabled" || WARN "IO scheduler service not enabled"
else
    WARN "IO scheduler service was not created"
fi

if [ -f "$COMPLETED_MARKER" ]; then PASS "Completion marker exists"; else WARN "Completion marker missing"; fi

echo ""
echo "Verification complete."
rm -f "$verify_script"
EOF

    chmod +x "$verify_script"
    run_optional "$verify_script"

    msg_ok "VERIFICATION REPORT CREATED"
}


# --- 55. COMPLETION MARKER ---
# Creates marker so later reruns can detect previous setup.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing New Storage Setup completion marker"

    cat <<EOF > "$COMPLETED_MARKER"
New Storage Setup completed on: $(date)
Disk: $SELECTED_DISK
Disk Type: $DISK_TYPE
Disk Bus: $DISK_BUS
Disk Model: ${DISK_MODEL:-unknown}
Disk Size GB: $DISK_SIZE_GB
Storage ID: $STORAGE_ID
VG: $VG_NAME
Thinpool: $THINPOOL_NAME
Thin Allocation: ${THIN_PERCENT}%FREE
Content Types: $CONTENT_TYPES
IO Scheduler: $IO_SCHEDULER
Verify Log: $VERIFY_FILE
EOF

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 56. FINAL SUMMARY ---
# Shows final storage details.
function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    echo -e "${BL}NEW PROXMOX STORAGE CREATED:${CL}"
    echo -e " ${BL}━━━━━▶${CL} DISK: ${GN}${SELECTED_DISK}${CL}"
    echo -e " ${BL}━━━━━▶${CL} MODEL: ${GN}${DISK_MODEL:-unknown}${CL}"
    echo -e " ${BL}━━━━━▶${CL} TYPE/BUS/SIZE: ${GN}${DISK_TYPE} / ${DISK_BUS} / ${DISK_SIZE_GB}GB${CL}"
    echo -e " ${BL}━━━━━▶${CL} STORAGE ID: ${GN}${STORAGE_ID}${CL}"
    echo -e " ${BL}━━━━━▶${CL} VG / THINPOOL: ${GN}${VG_NAME} / ${THINPOOL_NAME}${CL}"
    echo -e " ${BL}━━━━━▶${CL} THIN ALLOCATION: ${GN}${THIN_PERCENT}%FREE${CL}"
    echo -e " ${BL}━━━━━▶${CL} CONTENT: ${GN}${CONTENT_TYPES}${CL}"
    echo -e " ${BL}━━━━━▶${CL} IO SCHEDULER: ${GN}${IO_SCHEDULER}${CL}"
    echo -e " ${BL}━━━━━▶${CL} VERIFY LOG: ${GN}${VERIFY_FILE}${CL}"
    echo ""
    echo -e "${YW}New Proxmox LVM-thin storage is ready for VM disks, containers and backups according to selected content types.${CL}"
    echo ""
}


# --- 57. MAIN FUNCTION ---
# Runs validation -> safe disk selection -> configuration -> destructive apply -> verification.
function main() {
    init_script
    check_previous_marker

    audit_disks
    select_disk
    inspect_selected_disk
    show_selected_disk_summary
    first_destructive_confirmation

    collect_storage_names
    check_storage_conflicts
    collect_thinpool_allocation
    collect_content_types
    final_destructive_confirmation

    wipe_selected_disk
    create_lvm_physical_volume
    create_lvm_volume_group
    create_lvm_thinpool
    register_proxmox_storage

    apply_trim_logic
    apply_io_scheduler_tuning
    apply_memory_tuning

    write_completion_marker
    create_verification_report
    show_final_summary

    exit 0
}

main "$@"
