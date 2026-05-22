#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Ubuntu VM Setup - Crea Final
# =========================================================
# Purpose:
#   Configure a fresh Ubuntu VM/LXC for the Crea Docker deployment chain.
#
# Design rules:
#   - Phase 1: detect + collect every user answer first.
#   - Phase 2: show a final READY TO APPLY summary.
#   - Phase 3: only then change the system.
#   - Text/path/name/token inputs are untimed; only Y/n prompts use countdowns.
#   - Ubuntu Pro is attached/enabled before the main package upgrade.
#   - Sensitive values are never printed to logs, marker files, or summaries.
#   - Script 1 visual style is preserved.
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
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

SCRIPT_SOURCE="4-ubuntuVMsetup.sh"
SCRIPT_VERSION="v2.1.0"
SCRIPT_UPDATED="2026-05-22"
SCRIPT_BUILD="audit-pro-first-untimed-inputs-stability"

# --- 2. GLOBAL VARIABLES ---
T=15
REBOOT_T=30

LOG_FILE="/var/log/ubuntu-vm-setup.log"
RUNTIME_LOG_FILE=""
VERIFY_LOG="/var/log/ubuntu-vm-setup-verify.log"
COMPLETED_MARKER="/root/.ubuntu-vm-setup-completed"

DEFAULT_USERNAME="${DEFAULT_USERNAME:-orik}"

SUDO_CMD=""
TEMP_FILES=()
LOGGING_ENABLED="no"

IS_CONTAINER="no"
IS_LXC="no"
IS_VM="no"
VIRT_TYPE="unknown"
ROOT_KEYS="/root/.ssh/authorized_keys"
CURRENT_USER_KEYS=""
SOURCE_KEYS=""
DEST_KEYS=""

USERNAME=""
LOCK_USER_PASSWORD="y"
ATTACH_UBUNTU_PRO="n"
PRO_TOKEN=""
ENABLE_ESM_APPS="y"
ENABLE_ESM_INFRA="y"
ENABLE_LIVEPATCH="y"
RUN_SYSTEM_UPDATE="y"
INSTALL_QEMU_AGENT="y"
EXPAND_ROOT_LVM="y"
CONFIGURE_UFW="y"
APPLY_SSH_HARDENING="y"
RUN_SYSTEM_CLEANUP="y"
REBOOT_AFTER_FINISH="y"

EXISTING_USER="no"
SUDO_USER_CREATED="no"
USER_ADDED_TO_SUDO="no"
USER_PASSWORD_LOCKED="no"
SSH_KEYS_CONFIGURED="no"
SSH_HARDENING_APPLIED="no"
QEMU_AGENT_INSTALLED="no"
UFW_ENABLED="no"
ROOT_EXPANDED="no"
UBUNTU_PRO_ATTACHED="no"
UBUNTU_PRO_ESM_APPS="not-requested"
UBUNTU_PRO_ESM_INFRA="not-requested"
UBUNTU_PRO_LIVEPATCH="not-requested"
SYSTEM_UPDATED="no"
SYSTEM_CLEANED="no"

ROOT_SOURCE=""
ROOT_LV_PATH=""
VG_NAME=""
VG_FREE_BYTES="0"

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
function header_info {
echo -e "${BL}
██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗    ██╗   ██╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ 
██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║    ██║   ██║████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║    ██║   ██║██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝
██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║    ╚██╗ ██╔╝██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝     ╚████╔╝ ██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     
 ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝       ╚═══╝  ╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
${CL}"
}

# --- 4. MESSAGE HELPERS ---
function msg_info() { local text="${1:-}"; echo -ne " ${HOLD} ${YW}${text}...${CL}"; }
function msg_ok() { local text="${1:-}"; echo -e "${BFR} ${CM} ${GN}${text}${CL}"; }
function msg_warn() { local text="${1:-}"; echo -e "${BFR} ${WARN} ${YW}${text}${CL}"; }
function msg_skip() { local text="${1:-}"; echo -e "${BFR} ${WARN} ${YW}${text}${CL}"; }
function msg_error() { local text="${1:-Unknown error}"; echo -e "${BFR} ${CROSS} ${RD}${text}${CL}"; exit 1; }

# --- SCRIPT VERSION DISPLAY ---
# Prints the currently running script version immediately under the ASCII banner.
function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

# --- 5. SECTION HEADER HELPER ---
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

# --- 5A. FLASHING SUCCESS SECTION HEADER HELPER ---
function section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

# --- 5B. DETAIL LINE HELPER ---
function detail_line() {
    local label="${1:-}"
    local value="${2:-}"
    echo -e " ${BL}━━━━━▶${CL} ${label}: ${GN}${value}${CL}"
}

# --- 6. TTY PRINT HELPERS ---
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 7. INPUT BUFFER FLUSH HELPER ---
function flush_input_buffer() {
    local junk=""
    local i=""

    [ -r /dev/tty ] || return 0

    for i in {1..20}; do
        if ! IFS= read -rsn1 -t 0.02 junk < /dev/tty 2>/dev/null; then
            break
        fi
    done

    return 0
}

# =========================================================
#  CLEANUP / ERROR HANDLING
# =========================================================

# --- 8. CLEANUP FUNCTION ---
function cleanup() {
    local exit_code="$?"
    local file=""

    stty sane < /dev/tty 2>/dev/null || true

    if [ -n "${SUDO_CMD:-}" ] && [ -n "${RUNTIME_LOG_FILE:-}" ] && [ -s "$RUNTIME_LOG_FILE" ]; then
        "$SUDO_CMD" cp "$RUNTIME_LOG_FILE" "$LOG_FILE" 2>/dev/null || true
        "$SUDO_CMD" chmod 0644 "$LOG_FILE" 2>/dev/null || true
    fi

    for file in "${TEMP_FILES[@]:-}"; do
        [ -n "$file" ] && [ -f "$file" ] && rm -f "$file" 2>/dev/null || true
    done

    exit "$exit_code"
}

# --- 9. ERROR TRAP HELPER ---
function on_error() {
    local line_no="${1:-unknown}"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"
}

# --- 10. COMMAND RUNNER ---
function run_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    if [ -n "$SUDO_CMD" ]; then
        if ! "$SUDO_CMD" "$@" > /dev/null 2> "$err_file"; then
            echo ""
            echo -e "${RD}Command failed during:${CL} ${description}"
            echo -e "${YW}Command:${CL} sudo $*"
            echo ""
            echo -e "${RD}Real error:${CL}"
            cat "$err_file"
            rm -f "$err_file"
            exit 1
        fi
    else
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
    fi

    rm -f "$err_file"
}

# --- 11. OPTIONAL COMMAND RUNNER ---
function run_optional() {
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" "$@" >/dev/null 2>&1 || true
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

# --- 12. ROOT FILE HELPERS ---
function root_file_exists() {
    local path="$1"
    if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" test -f "$path"; else test -f "$path"; fi
}

function root_grep_quiet() {
    local pattern="$1"
    local path="$2"
    if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" grep -Eq "$pattern" "$path"; else grep -Eq "$pattern" "$path"; fi
}

function root_cat_file() {
    local path="$1"
    if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" cat "$path"; else cat "$path"; fi
}

function root_append_line() {
    local path="$1"
    local line="$2"
    if [ -n "$SUDO_CMD" ]; then
        printf '%s\n' "$line" | "$SUDO_CMD" tee -a "$path" >/dev/null
    else
        printf '%s\n' "$line" >> "$path"
    fi
}

function get_effective_sshd_config() {
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" sshd -T -C user="${USERNAME:-root}",host=localhost,addr=127.0.0.1 2>/dev/null || true
    else
        sshd -T -C user="${USERNAME:-root}",host=localhost,addr=127.0.0.1 2>/dev/null || true
    fi
}

# =========================================================
#  LOGGING CONTROL
# =========================================================

# --- 13. LOGGING CONTROL ---
function disable_logging() {
    if [ -w /dev/tty ]; then
        exec > /dev/tty 2> /dev/tty
    else
        exec >&3 2>&4
    fi
    LOGGING_ENABLED="no"
}

function enable_logging() {
    if [ -n "$RUNTIME_LOG_FILE" ]; then
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    LOGGING_ENABLED="yes"
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 14. YES/NO LABEL HELPER ---
function yes_no_label() {
    local value="${1:-n}"
    if [[ "$value" =~ ^[Yy]$ ]]; then echo "yes"; else echo "no"; fi
}

# --- 15. BLOCKING YES/NO HELPER ---
function tty_read_yes_no_blocking() {
    local prompt="$1"
    local default="$2"
    local default_label="Y/n"
    local key=""

    if [[ "$default" =~ ^[Nn]$ ]]; then default_label="y/N"; fi

    flush_input_buffer

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
            flush_input_buffer
            return 0
        elif [[ "$key" =~ ^[YyNn]$ ]]; then
            tty_print "${BFR}"
            echo "$key"
            flush_input_buffer
            return 0
        fi
    done
}

# --- 16. TIMED YES/NO PROMPT HELPER ---
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

    if [[ "$default" =~ ^[Nn]$ ]]; then default_label="y/N"; fi

    flush_input_buffer
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
                case "$key" in
                    " ") answer="$(tty_read_yes_no_blocking "$prompt" "$default")"; break ;;
                    [YyNn]) answer="$key"; flush_input_buffer; break ;;
                    "") answer="$default"; flush_input_buffer; break ;;
                esac
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                case "$key" in
                    " ") answer="$(tty_read_yes_no_blocking "$prompt" "$default")"; break ;;
                    [YyNn]) answer="$key"; flush_input_buffer; break ;;
                    "") answer="$default"; flush_input_buffer; break ;;
                esac
            fi
        fi
    done

    [ -z "$answer" ] && answer="$default"
    final_label="$(yes_no_label "$answer")"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${final_label}${CL}"
    flush_input_buffer

    echo "$answer"
}

# --- 17. EDITABLE INPUT LOOP HELPER ---
function editable_input_loop() {
    local prompt="$1"
    local default="$2"
    local initial_value="${3:-}"
    local answer="$initial_value"
    local key=""

    flush_input_buffer

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
                tty_print "${BFR}"
                echo "$answer"
                flush_input_buffer
                return 0
                ;;
            $'\177'|$'\b') answer="${answer%?}" ;;
            *) answer+="$key" ;;
        esac
    done
}

# --- 18. TEXT INPUT HELPER ---
# Text/path/name inputs are intentionally untimed.
# Yes/no prompts keep countdown timers, but anything the user may need to type or paste waits normally.
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""

    # Text/path/name inputs are deliberately NOT timed.
    # Countdown prompts are reserved only for simple Y/n decisions.
    # This prevents defaults being accepted while the user is away and gives enough time to type/paste.
    answer="$(editable_input_loop "$prompt" "$default" "")"
    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
    flush_input_buffer 2>/dev/null || true

    echo "$answer"
}

# --- 19. SENSITIVE LINE INPUT HELPER ---
function sensitive_line_input() {
    local prompt="$1"
    local answer=""
    local cols="80"
    local visible_len="0"
    local lines_to_clear="1"
    local i=""

    tty_print "${YW}${prompt}: ${CL}"

    if [ -r /dev/tty ]; then
        IFS= read -r answer < /dev/tty || answer=""
    else
        IFS= read -r answer || answer=""
    fi

    cols="$(tput cols 2>/dev/null || echo 80)"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols="80"
    [ "$cols" -lt 20 ] && cols="80"

    visible_len=$(( ${#prompt} + 2 + ${#answer} ))
    lines_to_clear=$(( (visible_len + cols - 1) / cols ))
    [ "$lines_to_clear" -lt 1 ] && lines_to_clear="1"

    for ((i=0; i<lines_to_clear; i++)); do
        tty_print $'\033[1A\r\033[2K'
    done

    printf '%s' "$answer"
}

# --- 20. REBOOT COUNTDOWN HELPER ---
function timed_reboot_countdown() {
    local seconds="$1"
    local key=""
    local deadline=""
    local now=""
    local remaining=""
    local first_draw="yes"

    flush_input_buffer
    deadline=$(( $(date +%s) + seconds ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            [ "$first_draw" == "no" ] && tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
            return 0
        fi

        if [ "$first_draw" == "yes" ]; then
            first_draw="no"
        else
            tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
        fi

        tty_print "${BL}${CLF}REBOOTING IN ${remaining} SECONDS...${CL}\n${YW}(ENTER/Y = Reboot Now, SPACE/N = Cancel)${CL}\n"

        key=""
        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                case "$key" in
                    ""|[Yy])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${BL}${CLF}REBOOTING NOW...${CL}"
                        return 0
                        ;;
                    " "|[Nn])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                        return 1
                        ;;
                esac
            fi
        else
            sleep 1
        fi
    done
}

# =========================================================
#  VALIDATION / INIT
# =========================================================

# --- 21. USERNAME VALIDATION HELPER ---
function validate_linux_username() {
    local username="$1"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

# --- 22. DEPENDENCY VALIDATION ---
function validate_dependencies() {
    local required_commands=(
        apt-get awk cat chmod chown cp date findmnt grep id mkdir mktemp
        passwd readlink sed sleep sshd systemctl tee useradd usermod xargs
    )
    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done

    if [ -n "$SUDO_CMD" ]; then
        command -v sudo >/dev/null 2>&1 || msg_error "sudo is required when not running as root."
    fi
}

# --- 23. ROOT / SUDO DETECTION ---
function detect_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then SUDO_CMD=""; else SUDO_CMD="sudo"; fi
}

# --- 24. SUDO VALIDATION ---
function validate_sudo_access() {
    if [ -n "$SUDO_CMD" ]; then
        msg_info "Validating sudo access"

        if "$SUDO_CMD" -n true >/dev/null 2>&1; then
            msg_ok "PASSWORDLESS SUDO CONFIRMED"
            return 0
        fi

        if "$SUDO_CMD" -v; then
            msg_ok "SUDO ACCESS CONFIRMED"
            return 0
        fi

        msg_error "Sudo authentication failed. Script cancelled."
    fi
}

# --- 25. LOGGING INITIALIZATION ---
function init_logging() {
    exec 3>&1
    exec 4>&2

    if [ -n "$SUDO_CMD" ]; then
        RUNTIME_LOG_FILE="$(mktemp /tmp/ubuntu-vm-setup-log.XXXXXX)"
        TEMP_FILES+=("$RUNTIME_LOG_FILE")
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        RUNTIME_LOG_FILE="$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    LOGGING_ENABLED="yes"
}

# --- 26. SCRIPT INITIALIZATION ---
function init_script() {
    detect_root_or_sudo
    validate_sudo_access
    init_logging

    trap 'on_error "$LINENO"' ERR
    trap cleanup EXIT

    clear
    header_info
    show_script_version

    validate_dependencies
}

# --- 27. PREVIOUS MARKER CHECK ---
function check_previous_marker() {
    local continue_yn=""

    if root_file_exists "$COMPLETED_MARKER"; then
        section "PREVIOUS UBUNTU VM SETUP MARKER DETECTED"

        echo -e "${YW}A previous Ubuntu VM Setup marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        root_cat_file "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"
        [[ "$continue_yn" =~ ^[Nn] ]] && exit 0
    fi
}

# =========================================================
#  PHASE 1: DETECTION + INPUT COLLECTION
# =========================================================

# --- 28. ENVIRONMENT DETECTION ---
function detect_environment() {
    section "ENVIRONMENT CHECK"

    msg_info "Detecting environment"

    IS_CONTAINER="no"
    IS_LXC="no"
    IS_VM="no"
    VIRT_TYPE="unknown"

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        VIRT_TYPE="$(systemd-detect-virt 2>/dev/null || echo "none")"

        if systemd-detect-virt --container --quiet 2>/dev/null; then
            IS_CONTAINER="yes"
            [ "$VIRT_TYPE" == "lxc" ] && IS_LXC="yes"
        elif systemd-detect-virt --vm --quiet 2>/dev/null; then
            IS_VM="yes"
        fi
    fi

    if [ "$VIRT_TYPE" == "unknown" ] || [ "$VIRT_TYPE" == "none" ]; then
        if grep -qa container=lxc /proc/1/environ 2>/dev/null; then
            IS_CONTAINER="yes"
            IS_LXC="yes"
            VIRT_TYPE="lxc"
        elif [ -d /sys/class/dmi/id ] && grep -qiE "qemu|kvm|vmware|virtualbox|hyper-v" /sys/class/dmi/id/product_name 2>/dev/null; then
            IS_VM="yes"
            VIRT_TYPE="vm"
        else
            VIRT_TYPE="${VIRT_TYPE:-unknown}"
            IS_VM="yes"
        fi
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        msg_ok "ENVIRONMENT DETECTED (${VIRT_TYPE} container)"
    elif [ "$IS_VM" == "yes" ]; then
        msg_ok "ENVIRONMENT DETECTED (${VIRT_TYPE} VM)"
    else
        IS_VM="yes"
        msg_warn "Environment unclear (${VIRT_TYPE}); continuing with VM-safe defaults"
    fi
}

# --- 29. START CONFIRMATION ---
function start_confirmation() {
    local start_yn=""

    section "START"

    echo -e "${YW}This script collects all answers first, then applies Ubuntu VM changes in one controlled run.${CL}"
    echo -e "${YW}Ubuntu Pro attachment is handled before the main package upgrade so Pro/ESM repositories can be used.${CL}"

    if [ "$IS_CONTAINER" == "yes" ]; then
        echo -e "${YW}Container mode detected: QEMU Guest Agent and LVM root expansion will be skipped.${CL}"
    else
        echo -e "${YW}VM mode detected: QEMU Guest Agent, LVM root expansion, UFW and SSH hardening can be configured.${CL}"
    fi

    echo ""

    start_yn="$(timed_yes_no "Start the Ubuntu VM Setup Script?" "y")"
    [[ "$start_yn" =~ ^[Nn] ]] && exit 0

    return 0

    return 0
}

# --- 30. USERNAME INPUT ---
function collect_username() {
    section "COLLECT INPUTS - USER"

    while true; do
        USERNAME="$(timed_text_input "Enter username" "$DEFAULT_USERNAME")"

        if validate_linux_username "$USERNAME"; then
            break
        fi

        msg_warn "Invalid username. Use lowercase Linux username format, for example: orik"
    done

    if id "$USERNAME" >/dev/null 2>&1; then
        EXISTING_USER="yes"
    else
        EXISTING_USER="no"
    fi

    CURRENT_USER_KEYS="/home/${USERNAME}/.ssh/authorized_keys"

    if [ -s "$CURRENT_USER_KEYS" ]; then
        SOURCE_KEYS="$CURRENT_USER_KEYS"
    elif [ -s "$ROOT_KEYS" ]; then
        SOURCE_KEYS="$ROOT_KEYS"
    else
        SOURCE_KEYS=""
    fi

    LOCK_USER_PASSWORD="$(timed_yes_no "Lock password for SSH-key-only user?" "y")"
    APPLY_SSH_HARDENING="$(timed_yes_no "Apply SSH key-only hardening after keys are verified?" "y")"

    return 0
}

# --- 31. UBUNTU PRO INPUTS ---
function collect_ubuntu_pro_inputs() {
    section "COLLECT INPUTS - UBUNTU PRO"

    echo -e "${YW}Ubuntu Pro is optional. If enabled, this script attaches Pro before the main system upgrade.${CL}"
    echo -e "${YW}Token input is not logged and is never written to disk by this script.${CL}"
    echo ""

    ATTACH_UBUNTU_PRO="$(timed_yes_no "Attach Ubuntu Pro token?" "n")"

    if [[ "$ATTACH_UBUNTU_PRO" =~ ^[Yy] ]]; then
        disable_logging

        if [ -n "${UBUNTU_PRO_TOKEN:-}" ]; then
            PRO_TOKEN="$UBUNTU_PRO_TOKEN"
            unset UBUNTU_PRO_TOKEN
        else
            PRO_TOKEN="$(sensitive_line_input "Enter Ubuntu Pro token")"
        fi

        enable_logging

        PRO_TOKEN="$(printf '%s' "$PRO_TOKEN" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        if [ -z "$PRO_TOKEN" ]; then
            msg_warn "Ubuntu Pro token was empty; Ubuntu Pro attachment will be skipped"
            ATTACH_UBUNTU_PRO="n"
            ENABLE_ESM_APPS="n"
            ENABLE_ESM_INFRA="n"
            ENABLE_LIVEPATCH="n"
            return 0
        fi

        ENABLE_ESM_APPS="$(timed_yes_no "Enable Ubuntu Pro ESM Apps?" "y")"
        ENABLE_ESM_INFRA="$(timed_yes_no "Enable Ubuntu Pro ESM Infra?" "y")"
        ENABLE_LIVEPATCH="$(timed_yes_no "Enable Ubuntu Pro Livepatch?" "y")"
    else
        ENABLE_ESM_APPS="n"
        ENABLE_ESM_INFRA="n"
        ENABLE_LIVEPATCH="n"
    fi

    return 0
}

# --- 32. SYSTEM ACTION INPUTS ---
function collect_system_action_inputs() {
    section "COLLECT INPUTS - SYSTEM ACTIONS"

    RUN_SYSTEM_UPDATE="$(timed_yes_no "Run apt update and full upgrade?" "y")"

    if [ "$IS_CONTAINER" == "yes" ]; then
        INSTALL_QEMU_AGENT="n"
        EXPAND_ROOT_LVM="n"
        CONFIGURE_UFW="$(timed_yes_no "Attempt UFW firewall setup inside LXC/container?" "n")"
    else
        INSTALL_QEMU_AGENT="$(timed_yes_no "Install and enable QEMU Guest Agent?" "y")"
        EXPAND_ROOT_LVM="$(timed_yes_no "Expand root LVM filesystem if free space exists?" "y")"
        CONFIGURE_UFW="$(timed_yes_no "Install and enable UFW firewall baseline?" "y")"
    fi

    RUN_SYSTEM_CLEANUP="$(timed_yes_no "Run package cleanup at the end?" "y")"
    REBOOT_AFTER_FINISH="$(timed_yes_no "Reboot automatically after setup finishes?" "y")"

    return 0
}

# --- 33. READY SUMMARY ---
function show_ready_summary_and_confirm() {
    local apply_yn=""

    section "READY TO APPLY"

    echo -e "${YW}All questions have been collected. No system-changing setup actions have been applied yet.${CL}"
    echo ""

    detail_line "Username" "$USERNAME"
    detail_line "Existing user" "$EXISTING_USER"
    detail_line "SSH key source" "${SOURCE_KEYS:-none detected}"
    detail_line "Lock user password" "$(yes_no_label "$LOCK_USER_PASSWORD")"
    detail_line "SSH hardening" "$(yes_no_label "$APPLY_SSH_HARDENING")"

    if [ "$IS_CONTAINER" == "yes" ]; then
        detail_line "Environment" "Container/LXC (${VIRT_TYPE})"
    else
        detail_line "Environment" "VM (${VIRT_TYPE})"
    fi

    detail_line "Attach Ubuntu Pro" "$(yes_no_label "$ATTACH_UBUNTU_PRO")"
    if [[ "$ATTACH_UBUNTU_PRO" =~ ^[Yy] ]]; then
        detail_line "Enable ESM Apps" "$(yes_no_label "$ENABLE_ESM_APPS")"
        detail_line "Enable ESM Infra" "$(yes_no_label "$ENABLE_ESM_INFRA")"
        detail_line "Enable Livepatch" "$(yes_no_label "$ENABLE_LIVEPATCH")"
    fi

    detail_line "System update" "$(yes_no_label "$RUN_SYSTEM_UPDATE")"
    detail_line "QEMU Guest Agent" "$(yes_no_label "$INSTALL_QEMU_AGENT")"
    detail_line "Root LVM expansion" "$(yes_no_label "$EXPAND_ROOT_LVM")"
    detail_line "UFW firewall" "$(yes_no_label "$CONFIGURE_UFW")"
    detail_line "System cleanup" "$(yes_no_label "$RUN_SYSTEM_CLEANUP")"
    detail_line "Auto reboot" "$(yes_no_label "$REBOOT_AFTER_FINISH")"

    echo ""
    echo -e "${RD}${CLF}After confirmation, the script will begin making system changes.${CL}"
    echo ""

    apply_yn="$(timed_yes_no "Apply this Ubuntu VM setup plan now?" "y")"
    [[ "$apply_yn" =~ ^[Nn] ]] && exit 0

    return 0

    return 0
}

# =========================================================
#  PHASE 2: APPLY SYSTEM CHANGES
# =========================================================

# --- 34. USER CREATION / REUSE ---
function apply_user_setup() {
    section "APPLY - USER / SSH KEYS"

    if [ "$EXISTING_USER" == "no" ]; then
        msg_info "Creating user ${USERNAME}"
        run_cmd "creating user ${USERNAME}" useradd -m -s /bin/bash "$USERNAME"
        SUDO_USER_CREATED="yes"
        msg_ok "USER CREATED"
    else
        msg_ok "USER ${USERNAME} ALREADY EXISTS"
    fi

    msg_info "Ensuring ${USERNAME} is in sudo group"
    run_cmd "adding ${USERNAME} to sudo group" usermod -aG sudo "$USERNAME"
    USER_ADDED_TO_SUDO="yes"
    msg_ok "USER SUDO ACCESS CONFIRMED"

    DEST_KEYS="/home/${USERNAME}/.ssh/authorized_keys"

    if [ -n "$SOURCE_KEYS" ]; then
        run_cmd "creating SSH directory for ${USERNAME}" mkdir -p "/home/${USERNAME}/.ssh"

        if [ "$(readlink -f "$SOURCE_KEYS")" = "$(readlink -f "$DEST_KEYS" 2>/dev/null || echo "$DEST_KEYS")" ]; then
            msg_ok "SSH KEYS ALREADY CONFIGURED"
        else
            msg_info "Copying SSH keys for ${USERNAME}"
            run_cmd "copying SSH keys for ${USERNAME}" cp "$SOURCE_KEYS" "$DEST_KEYS"
            msg_ok "SSH KEYS CONFIGURED"
        fi

        msg_info "Fixing SSH key ownership and permissions"
        run_cmd "setting SSH directory ownership" chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
        run_cmd "setting SSH directory permissions" chmod 700 "/home/${USERNAME}/.ssh"
        run_cmd "setting authorized_keys permissions" chmod 600 "$DEST_KEYS"
        SSH_KEYS_CONFIGURED="yes"
        msg_ok "SSH KEY PERMISSIONS VERIFIED"
    else
        SSH_KEYS_CONFIGURED="no"
        msg_warn "SSH key setup skipped because no authorized_keys source was found"
    fi

    if [[ "$LOCK_USER_PASSWORD" =~ ^[Yy] ]]; then
        local passwd_state=""

        msg_info "Locking password for ${USERNAME}"
        run_cmd "locking password for ${USERNAME}" passwd -l "$USERNAME"

        passwd_state="$(passwd -S "$USERNAME" 2>/dev/null | awk '{print $2}' || true)"
        if [ "$passwd_state" == "L" ] || [ "$passwd_state" == "NP" ]; then
            USER_PASSWORD_LOCKED="yes"
            msg_ok "USER PASSWORD LOCKED"
        else
            USER_PASSWORD_LOCKED="verify-failed"
            msg_warn "Password lock command ran but verification did not confirm locked state"
        fi
    else
        USER_PASSWORD_LOCKED="no"
        msg_warn "USER PASSWORD LOCK SKIPPED"
    fi
}

# --- 35. UBUNTU PRO CLIENT INSTALL HELPER ---
function ensure_ubuntu_pro_client() {
    if command -v pro >/dev/null 2>&1; then
        msg_ok "UBUNTU PRO CLIENT FOUND"
        return 0
    fi

    msg_warn "Ubuntu Pro client not found; installing it before Pro attach"

    msg_info "Updating package lists for Ubuntu Pro client"
    run_cmd "updating package lists for Ubuntu Pro client" apt-get update
    msg_ok "PACKAGE LISTS UPDATED"

    msg_info "Installing Ubuntu Pro client"
    run_cmd "installing Ubuntu Pro client" env DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-pro-client ubuntu-advantage-tools
    msg_ok "UBUNTU PRO CLIENT INSTALLED"
}

# --- 36A. UBUNTU PRO SERVICE ENABLE HELPER ---
function run_pro_enable_service() {
    local service="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" pro enable "$service" --assume-yes >/dev/null 2>&1
    else
        pro enable "$service" --assume-yes >/dev/null 2>&1
    fi
}

# --- 36. UBUNTU PRO APPLY ---
function apply_ubuntu_pro() {
    section "APPLY - UBUNTU PRO"

    if [[ ! "$ATTACH_UBUNTU_PRO" =~ ^[Yy] ]]; then
        UBUNTU_PRO_ATTACHED="no"
        msg_skip "UBUNTU PRO ATTACHMENT SKIPPED"
        return 0
    fi

    ensure_ubuntu_pro_client

    if pro status 2>/dev/null | grep -qi 'Subscription:'; then
        UBUNTU_PRO_ATTACHED="already-attached"
        msg_ok "UBUNTU PRO ALREADY ATTACHED"
    else
        local err_file=""
        err_file="$(mktemp)"
        TEMP_FILES+=("$err_file")

        msg_info "Attaching Ubuntu Pro"

        if [ -n "$SUDO_CMD" ]; then
            if "$SUDO_CMD" pro attach "$PRO_TOKEN" --no-auto-enable > /dev/null 2> "$err_file"; then
                UBUNTU_PRO_ATTACHED="yes"
                msg_ok "UBUNTU PRO ATTACHED"
            else
                UBUNTU_PRO_ATTACHED="failed"
                msg_warn "Ubuntu Pro attachment failed"
                echo -e "${YW}Real error:${CL}"
                sed -E 's/[A-Za-z0-9_-]{20,}/[redacted]/g' "$err_file" || true
            fi
        else
            if pro attach "$PRO_TOKEN" --no-auto-enable > /dev/null 2> "$err_file"; then
                UBUNTU_PRO_ATTACHED="yes"
                msg_ok "UBUNTU PRO ATTACHED"
            else
                UBUNTU_PRO_ATTACHED="failed"
                msg_warn "Ubuntu Pro attachment failed"
                echo -e "${YW}Real error:${CL}"
                sed -E 's/[A-Za-z0-9_-]{20,}/[redacted]/g' "$err_file" || true
            fi
        fi

        rm -f "$err_file"
    fi

    unset PRO_TOKEN
    PRO_TOKEN=""

    if [ "$UBUNTU_PRO_ATTACHED" == "failed" ]; then
        msg_warn "Pro service enablement skipped because attach failed"
        return 0
    fi

    if [[ "$ENABLE_ESM_APPS" =~ ^[Yy] ]]; then
        msg_info "Enabling Ubuntu Pro ESM Apps"
        if run_pro_enable_service "esm-apps"; then UBUNTU_PRO_ESM_APPS="yes"; msg_ok "ESM APPS ENABLED"; else UBUNTU_PRO_ESM_APPS="failed"; msg_warn "ESM Apps could not be enabled"; fi
    fi

    if [[ "$ENABLE_ESM_INFRA" =~ ^[Yy] ]]; then
        msg_info "Enabling Ubuntu Pro ESM Infra"
        if run_pro_enable_service "esm-infra"; then UBUNTU_PRO_ESM_INFRA="yes"; msg_ok "ESM INFRA ENABLED"; else UBUNTU_PRO_ESM_INFRA="failed"; msg_warn "ESM Infra could not be enabled"; fi
    fi

    if [[ "$ENABLE_LIVEPATCH" =~ ^[Yy] ]]; then
        msg_info "Enabling Ubuntu Pro Livepatch"
        if run_pro_enable_service "livepatch"; then UBUNTU_PRO_LIVEPATCH="yes"; msg_ok "LIVEPATCH ENABLED"; else UBUNTU_PRO_LIVEPATCH="failed"; msg_warn "Livepatch could not be enabled"; fi
    fi
}

# --- 37. SYSTEM UPDATE ---
function update_system_packages() {
    section "APPLY - SYSTEM UPDATE"

    if [[ ! "$RUN_SYSTEM_UPDATE" =~ ^[Yy] ]]; then
        SYSTEM_UPDATED="skipped"
        msg_skip "SYSTEM UPDATE SKIPPED"
        return 0
    fi

    msg_info "Updating package lists"
    run_cmd "updating package lists" apt-get update
    msg_ok "PACKAGE LISTS UPDATED"

    msg_info "Upgrading system packages"
    run_cmd "upgrading system packages" env DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade
    SYSTEM_UPDATED="yes"
    msg_ok "SYSTEM PACKAGES UPGRADED"

    msg_info "Removing unused packages"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
    msg_ok "UNUSED PACKAGES REMOVED"
}

# --- 38. QEMU GUEST AGENT INSTALL ---
function install_qemu_guest_agent() {
    section "APPLY - QEMU GUEST AGENT"

    if [ "$IS_CONTAINER" == "yes" ] || [[ ! "$INSTALL_QEMU_AGENT" =~ ^[Yy] ]]; then
        QEMU_AGENT_INSTALLED="skipped"
        msg_skip "QEMU GUEST AGENT SKIPPED"
        return 0
    fi

    msg_info "Installing QEMU guest agent"
    run_cmd "installing QEMU guest agent" env DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent
    msg_ok "QEMU GUEST AGENT PACKAGE INSTALLED"

    msg_info "Enabling QEMU guest agent"
    run_cmd "enabling QEMU guest agent" systemctl enable --now qemu-guest-agent
    msg_ok "QEMU GUEST AGENT ENABLED"

    if systemctl is-active --quiet qemu-guest-agent; then
        QEMU_AGENT_INSTALLED="yes"
        msg_ok "QEMU GUEST AGENT ACTIVE"
    else
        QEMU_AGENT_INSTALLED="installed-not-active"
        msg_warn "QEMU guest agent installed but service is not active"
    fi
}

# --- 39. ROOT FILESYSTEM LVM EXPANSION ---
function expand_root_lvm_if_possible() {
    section "APPLY - ROOT DISK EXPANSION"

    local root_source=""
    local root_candidate=""
    local lvm_rows=""
    local lv_path=""
    local lv_dm_path=""
    local vg_name=""
    local lv_name=""
    local resolved_lv_path=""
    local resolved_dm_path=""
    local vg_free_raw=""
    local vg_free_int="0"
    local min_expand_bytes="1073741824"

    if [ "$IS_CONTAINER" == "yes" ] || [[ ! "$EXPAND_ROOT_LVM" =~ ^[Yy] ]]; then
        ROOT_EXPANDED="skipped"
        msg_skip "ROOT LVM EXPANSION SKIPPED"
        return 0
    fi

    if ! command -v lvs >/dev/null 2>&1 || ! command -v vgs >/dev/null 2>&1 || ! command -v lvextend >/dev/null 2>&1; then
        ROOT_EXPANDED="not-needed"
        msg_ok "LVM TOOLS NOT FOUND; ROOT LVM EXPANSION NOT NEEDED"
        return 0
    fi

    msg_info "Checking root filesystem free space"

    root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    ROOT_SOURCE="$root_source"

    if [ -n "$root_source" ]; then
        root_candidate="$(readlink -f "$root_source" 2>/dev/null || echo "$root_source")"
    fi

    if [ -n "$SUDO_CMD" ]; then
        lvm_rows="$($SUDO_CMD lvs --noheadings --separator '|' -o lv_path,lv_dm_path,vg_name,lv_name 2>/dev/null || true)"
    else
        lvm_rows="$(lvs --noheadings --separator '|' -o lv_path,lv_dm_path,vg_name,lv_name 2>/dev/null || true)"
    fi

    while IFS='|' read -r lv_path lv_dm_path vg_name lv_name; do
        lv_path="$(echo "$lv_path" | xargs)"
        lv_dm_path="$(echo "$lv_dm_path" | xargs)"
        vg_name="$(echo "$vg_name" | xargs)"
        lv_name="$(echo "$lv_name" | xargs)"

        [ -z "$lv_path" ] && continue

        resolved_lv_path="$(readlink -f "$lv_path" 2>/dev/null || echo "$lv_path")"
        resolved_dm_path="$(readlink -f "$lv_dm_path" 2>/dev/null || echo "$lv_dm_path")"

        if [ "$root_source" == "$lv_path" ] || \
           [ "$root_source" == "$lv_dm_path" ] || \
           [ "$root_candidate" == "$resolved_lv_path" ] || \
           [ "$root_candidate" == "$resolved_dm_path" ]; then
            ROOT_LV_PATH="$lv_path"
            VG_NAME="$vg_name"
            break
        fi
    done <<< "$lvm_rows"

    if [ -z "$ROOT_LV_PATH" ] || [ -z "$VG_NAME" ]; then
        ROOT_EXPANDED="not-needed"
        msg_ok "ROOT FILESYSTEM LVM EXPANSION NOT NEEDED"
        detail_line "Root source" "${ROOT_SOURCE:-unknown}"
        detail_line "Resolved root source" "${root_candidate:-unknown}"
        return 0
    fi

    if [ -n "$SUDO_CMD" ]; then
        vg_free_raw="$($SUDO_CMD vgs --noheadings --units b --nosuffix -o vg_free "$VG_NAME" 2>/dev/null | xargs || true)"
    else
        vg_free_raw="$(vgs --noheadings --units b --nosuffix -o vg_free "$VG_NAME" 2>/dev/null | xargs || true)"
    fi

    vg_free_int="${vg_free_raw%%.*}"
    vg_free_int="${vg_free_int//[^0-9]/}"
    [ -z "$vg_free_int" ] && vg_free_int="0"
    VG_FREE_BYTES="$vg_free_int"

    detail_line "Root source" "$ROOT_SOURCE"
    detail_line "Root LV path" "$ROOT_LV_PATH"
    detail_line "Volume group" "$VG_NAME"
    detail_line "Free LVM bytes" "$VG_FREE_BYTES"

    if [[ "$VG_FREE_BYTES" =~ ^[0-9]+$ ]] && [ "$VG_FREE_BYTES" -gt "$min_expand_bytes" ]; then
        msg_ok "FOUND EMPTY LVM SPACE"

        msg_info "Expanding Ubuntu root filesystem"
        run_cmd "expanding Ubuntu root filesystem" lvextend -r -l +100%FREE "$ROOT_LV_PATH"
        ROOT_EXPANDED="yes"
        msg_ok "UBUNTU ROOT FILESYSTEM EXPANDED"
    else
        ROOT_EXPANDED="not-needed"
        msg_ok "NO EMPTY LVM SPACE FOUND"
    fi
}

# --- 40. UFW FIREWALL SETUP ---
function configure_ufw_firewall() {
    section "APPLY - FIREWALL"

    if [[ ! "$CONFIGURE_UFW" =~ ^[Yy] ]]; then
        UFW_ENABLED="skipped"
        msg_skip "UFW FIREWALL SKIPPED"
        return 0
    fi

    msg_info "Installing UFW"
    run_cmd "installing UFW" env DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
    msg_ok "UFW INSTALLED"

    msg_info "Configuring UFW firewall rules"
    run_optional ufw default deny incoming
    run_optional ufw default allow outgoing
    run_optional ufw allow OpenSSH
    run_optional ufw allow 80/tcp
    run_optional ufw allow 443/tcp
    msg_ok "UFW FIREWALL RULES CONFIGURED"

    msg_info "Enabling UFW firewall"

    if [ -n "$SUDO_CMD" ]; then
        if "$SUDO_CMD" ufw --force enable >/dev/null 2>&1; then
            UFW_ENABLED="yes"
            msg_ok "UFW FIREWALL ENABLED"
        else
            UFW_ENABLED="failed"
            msg_warn "UFW failed to enable. This can happen inside restricted containers."
        fi
    else
        if ufw --force enable >/dev/null 2>&1; then
            UFW_ENABLED="yes"
            msg_ok "UFW FIREWALL ENABLED"
        else
            UFW_ENABLED="failed"
            msg_warn "UFW failed to enable. This can happen inside restricted containers."
        fi
    fi
}

# --- 41. SSH HARDENING ---
function harden_ssh() {
    local ssh_config="/etc/ssh/sshd_config"
    local effective_config=""
    local effective_password_auth=""
    local effective_pubkey_auth=""
    local effective_permit_root=""
    local effective_kbd_auth=""

    section "APPLY - SSH HARDENING"

    if [[ ! "$APPLY_SSH_HARDENING" =~ ^[Yy] ]]; then
        SSH_HARDENING_APPLIED="skipped"
        msg_skip "SSH HARDENING SKIPPED"
        return 0
    fi

    if [ ! -s "/home/${USERNAME}/.ssh/authorized_keys" ]; then
        SSH_HARDENING_APPLIED="no"
        msg_warn "SSH hardening skipped because SSH keys were not detected for ${USERNAME}"
        return 0
    fi

    msg_info "Verifying SSH key permissions before hardening"
    run_cmd "setting SSH directory ownership" chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
    run_cmd "setting SSH directory permissions" chmod 700 "/home/${USERNAME}/.ssh"
    run_cmd "setting authorized_keys permissions" chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"
    msg_ok "SSH KEY PERMISSIONS VERIFIED"

    msg_info "Writing SSH key-only policy"

    run_optional sed -i -E 's/^[#[:space:]]*AddressFamily.*/AddressFamily inet/' "$ssh_config"
    root_grep_quiet '^AddressFamily[[:space:]]+' "$ssh_config" || root_append_line "$ssh_config" "AddressFamily inet"

    run_optional sed -i -E 's/^[#[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$ssh_config"
    root_grep_quiet '^PubkeyAuthentication[[:space:]]+' "$ssh_config" || root_append_line "$ssh_config" "PubkeyAuthentication yes"

    run_optional sed -i -E 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' "$ssh_config"
    root_grep_quiet '^PasswordAuthentication[[:space:]]+' "$ssh_config" || root_append_line "$ssh_config" "PasswordAuthentication no"

    run_optional sed -i -E 's/^[#[:space:]]*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$ssh_config"
    root_grep_quiet '^KbdInteractiveAuthentication[[:space:]]+' "$ssh_config" || root_append_line "$ssh_config" "KbdInteractiveAuthentication no"

    run_optional sed -i -E 's/^[#[:space:]]*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$ssh_config"
    root_grep_quiet '^ChallengeResponseAuthentication[[:space:]]+' "$ssh_config" || root_append_line "$ssh_config" "ChallengeResponseAuthentication no"

    run_optional sed -i -E 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$ssh_config"
    root_grep_quiet '^PermitRootLogin[[:space:]]+' "$ssh_config" || root_append_line "$ssh_config" "PermitRootLogin no"

    msg_ok "SSH KEY-ONLY POLICY WRITTEN"

    msg_info "Validating effective SSH configuration"
    run_cmd "validating sshd configuration" sshd -t

    effective_config="$(get_effective_sshd_config)"
    effective_password_auth="$(awk '$1=="passwordauthentication" {print $2; exit}' <<< "$effective_config")"
    effective_pubkey_auth="$(awk '$1=="pubkeyauthentication" {print $2; exit}' <<< "$effective_config")"
    effective_permit_root="$(awk '$1=="permitrootlogin" {print $2; exit}' <<< "$effective_config")"
    effective_kbd_auth="$(awk '$1=="kbdinteractiveauthentication" {print $2; exit}' <<< "$effective_config")"

    [ "${effective_pubkey_auth:-unknown}" == "yes" ] || msg_error "SSH validation failed: PubkeyAuthentication is ${effective_pubkey_auth:-unknown}, expected yes"
    [ "${effective_password_auth:-unknown}" == "no" ] || msg_error "SSH validation failed: PasswordAuthentication is ${effective_password_auth:-unknown}, expected no"

    case "${effective_permit_root:-unknown}" in
        no|prohibit-password|without-password) ;;
        *) msg_error "SSH validation failed: PermitRootLogin is ${effective_permit_root:-unknown}, expected no/prohibit-password/without-password" ;;
    esac

    if [ -n "$effective_kbd_auth" ] && [ "$effective_kbd_auth" != "no" ]; then
        msg_error "SSH validation failed: KbdInteractiveAuthentication is ${effective_kbd_auth}, expected no"
    fi

    msg_ok "EFFECTIVE SSH CONFIG VERIFIED"

    msg_info "Restarting SSH service"
    run_optional systemctl restart ssh
    run_optional systemctl restart sshd
    msg_ok "SSH SERVICE RESTARTED"

    SSH_HARDENING_APPLIED="yes"

    msg_ok "SSH SECURITY HARDENED"
    echo -e "  ${DGN}${USERNAME} SSH KEY LOGIN PRESERVED${CL}"
    echo -e "  ${DGN}SSH PASSWORD LOGIN DISABLED${CL}"
    echo -e "  ${DGN}ROOT SSH LOGIN DISABLED${CL}"
}

# --- 42. SYSTEM CLEANUP ---
function clean_system() {
    section "APPLY - SYSTEM CLEANUP"

    if [[ ! "$RUN_SYSTEM_CLEANUP" =~ ^[Yy] ]]; then
        SYSTEM_CLEANED="skipped"
        msg_skip "SYSTEM CLEANUP SKIPPED"
        return 0
    fi

    msg_info "Cleaning system"
    run_optional apt-get clean
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
    SYSTEM_CLEANED="yes"
    msg_ok "SYSTEM CLEANED"
}

# =========================================================
#  VERIFICATION / MARKER / SUMMARY
# =========================================================

# --- 43. COMPLETION MARKER ---
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<EOF_MARKER
Ubuntu VM Setup completed on: $(date)
Username: $USERNAME
User Created: $SUDO_USER_CREATED
User Added To Sudo: $USER_ADDED_TO_SUDO
User Password Locked: $USER_PASSWORD_LOCKED
SSH Keys Configured: $SSH_KEYS_CONFIGURED
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM
Ubuntu Pro Attached: $UBUNTU_PRO_ATTACHED
Ubuntu Pro ESM Apps: $UBUNTU_PRO_ESM_APPS
Ubuntu Pro ESM Infra: $UBUNTU_PRO_ESM_INFRA
Ubuntu Pro Livepatch: $UBUNTU_PRO_LIVEPATCH
System Updated: $SYSTEM_UPDATED
QEMU Agent: $QEMU_AGENT_INSTALLED
Root Expanded: $ROOT_EXPANDED
UFW: $UFW_ENABLED
SSH Hardened: $SSH_HARDENING_APPLIED
System Cleaned: $SYSTEM_CLEANED
Verify Log: $VERIFY_LOG
EOF_MARKER
    else
        cat > "$COMPLETED_MARKER" <<EOF_MARKER
Ubuntu VM Setup completed on: $(date)
Username: $USERNAME
User Created: $SUDO_USER_CREATED
User Added To Sudo: $USER_ADDED_TO_SUDO
User Password Locked: $USER_PASSWORD_LOCKED
SSH Keys Configured: $SSH_KEYS_CONFIGURED
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM
Ubuntu Pro Attached: $UBUNTU_PRO_ATTACHED
Ubuntu Pro ESM Apps: $UBUNTU_PRO_ESM_APPS
Ubuntu Pro ESM Infra: $UBUNTU_PRO_ESM_INFRA
Ubuntu Pro Livepatch: $UBUNTU_PRO_LIVEPATCH
System Updated: $SYSTEM_UPDATED
QEMU Agent: $QEMU_AGENT_INSTALLED
Root Expanded: $ROOT_EXPANDED
UFW: $UFW_ENABLED
SSH Hardened: $SSH_HARDENING_APPLIED
System Cleaned: $SYSTEM_CLEANED
Verify Log: $VERIFY_LOG
EOF_MARKER
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 44. VERIFICATION REPORT ---
function create_verification_report() {
    section "VERIFICATION"

    msg_info "Creating verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<EOF_VERIFY
--- UBUNTU VM SETUP VERIFICATION REPORT ---
Date: $(date)
Username: $USERNAME
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM

Results:
EOF_VERIFY
    else
        cat > "$VERIFY_LOG" <<EOF_VERIFY
--- UBUNTU VM SETUP VERIFICATION REPORT ---
Date: $(date)
Username: $USERNAME
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM

Results:
EOF_VERIFY
    fi

    {
        if id "$USERNAME" >/dev/null 2>&1; then echo "✓ PASS - User exists"; else echo "✗ FAIL - User missing"; fi
        if id -nG "$USERNAME" 2>/dev/null | grep -qw sudo; then echo "✓ PASS - User is in sudo group"; else echo "! WARN - User sudo group not confirmed"; fi
        if [ -s "/home/${USERNAME}/.ssh/authorized_keys" ]; then echo "✓ PASS - SSH authorized_keys present"; else echo "! WARN - SSH authorized_keys missing"; fi
        if sshd -t >/dev/null 2>&1; then echo "✓ PASS - sshd configuration valid"; else echo "✗ FAIL - sshd configuration invalid"; fi

        effective_config="$(get_effective_sshd_config)"

        if [ "$SSH_HARDENING_APPLIED" == "yes" ]; then
            if grep -q "^passwordauthentication no" <<< "$effective_config"; then echo "✓ PASS - SSH password authentication disabled"; else echo "✗ FAIL - SSH password authentication still enabled"; fi
            if grep -q "^pubkeyauthentication yes" <<< "$effective_config"; then echo "✓ PASS - SSH public key authentication enabled"; else echo "✗ FAIL - SSH public key authentication not confirmed"; fi
            if grep -Eq "^permitrootlogin (no|prohibit-password|without-password)" <<< "$effective_config"; then echo "✓ PASS - Root SSH login disabled or passwordless-only"; else echo "! WARN - Root SSH login not confirmed secure"; fi
            if grep -q "^kbdinteractiveauthentication no" <<< "$effective_config"; then echo "✓ PASS - SSH keyboard-interactive auth disabled"; else echo "! WARN - SSH keyboard-interactive auth not confirmed disabled"; fi
        else
            echo "! INFO - SSH hardening state: $SSH_HARDENING_APPLIED"
        fi

        if command -v ip >/dev/null 2>&1 && ip -4 addr show | grep -q "inet "; then echo "✓ PASS - IPv4 address detected"; else echo "! WARN - IPv4 address not detected"; fi

        if [ "$IS_CONTAINER" == "yes" ]; then
            echo "! INFO - QEMU Guest Agent skipped for container"
            echo "! INFO - Root LVM expansion skipped for container"
        else
            if systemctl is-enabled --quiet qemu-guest-agent 2>/dev/null; then echo "✓ PASS - QEMU guest agent enabled"; else echo "! WARN - QEMU guest agent not enabled"; fi
            if systemctl is-active --quiet qemu-guest-agent 2>/dev/null; then echo "✓ PASS - QEMU guest agent active"; else echo "! WARN - QEMU guest agent not active"; fi
            df -h / 2>/dev/null || true
        fi

        if [ "$UFW_ENABLED" == "yes" ]; then
            if ufw status 2>/dev/null | grep -qi "Status: active"; then echo "✓ PASS - UFW active"; else echo "! WARN - UFW expected active but not confirmed"; fi
            ufw status numbered 2>/dev/null || true
        else
            echo "! INFO - UFW state: $UFW_ENABLED"
        fi

        if command -v pro >/dev/null 2>&1; then
            pro status 2>/dev/null | head -n 20 || true
        else
            echo "! INFO - Ubuntu Pro client not available"
        fi

        if [ -f "$COMPLETED_MARKER" ]; then echo "✓ PASS - Completion marker exists"; else echo "! WARN - Completion marker missing"; fi
    } | if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee -a "$VERIFY_LOG" >/dev/null; else tee -a "$VERIFY_LOG" >/dev/null; fi

    msg_ok "VERIFICATION REPORT CREATED"
}

# --- 45. FINAL SUMMARY ---
function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    detail_line "USERNAME" "$USERNAME"
    detail_line "USER CREATED" "$SUDO_USER_CREATED"
    detail_line "USER ADDED TO SUDO" "$USER_ADDED_TO_SUDO"
    detail_line "PASSWORD LOCKED" "$USER_PASSWORD_LOCKED"
    detail_line "SSH KEYS" "$SSH_KEYS_CONFIGURED"

    if [ "$IS_CONTAINER" == "yes" ]; then
        detail_line "ENVIRONMENT" "LXC/Container (${VIRT_TYPE})"
    else
        detail_line "ENVIRONMENT" "VM (${VIRT_TYPE})"
    fi

    detail_line "UBUNTU PRO ATTACHED" "$UBUNTU_PRO_ATTACHED"
    detail_line "ESM APPS" "$UBUNTU_PRO_ESM_APPS"
    detail_line "ESM INFRA" "$UBUNTU_PRO_ESM_INFRA"
    detail_line "LIVEPATCH" "$UBUNTU_PRO_LIVEPATCH"
    detail_line "SYSTEM UPDATED" "$SYSTEM_UPDATED"
    detail_line "QEMU GUEST AGENT" "$QEMU_AGENT_INSTALLED"
    detail_line "ROOT EXPANDED" "$ROOT_EXPANDED"
    detail_line "UFW FIREWALL" "$UFW_ENABLED"
    detail_line "SSH HARDENING" "$SSH_HARDENING_APPLIED"
    detail_line "SYSTEM CLEANED" "$SYSTEM_CLEANED"
    detail_line "LOG FILE" "$LOG_FILE"
    detail_line "VERIFY LOG" "$VERIFY_LOG"

    echo ""
    echo -e "${GN}Ubuntu setup completed successfully.${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}After reboot and SSH reconnect, run script 5-dockerSetup.sh.${CL}"
    echo ""
}

# --- 46. REBOOT PROMPT ---
function reboot_prompt() {
    section "REBOOT"

    if [[ ! "$REBOOT_AFTER_FINISH" =~ ^[Yy] ]]; then
        msg_skip "AUTO REBOOT SKIPPED"
        echo -e "${YW}Reboot manually when ready.${CL}"
        return 0
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        echo -e "${YW}Container mode detected. Reboot/restart may be controlled from the Proxmox host.${CL}"
        echo -e "${YW}Reboot skipped. Restart the container from Proxmox host if needed.${CL}"
        return 0
    fi

    if timed_reboot_countdown "$REBOOT_T"; then
        if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" reboot; else reboot; fi
    fi
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 47. MAIN FUNCTION ---
function main() {
    init_script
    check_previous_marker
    detect_environment
    start_confirmation

    # Phase 1: all questions first.
    collect_username
    collect_ubuntu_pro_inputs
    collect_system_action_inputs
    show_ready_summary_and_confirm

    # Phase 2: apply changes after final confirmation.
    apply_user_setup
    apply_ubuntu_pro
    update_system_packages
    install_qemu_guest_agent
    expand_root_lvm_if_possible
    configure_ufw_firewall
    harden_ssh
    clean_system

    # Phase 3: verify, summarize and reboot.
    write_completion_marker
    create_verification_report
    show_final_summary
    reboot_prompt

    exit 0
}

main "$@"
