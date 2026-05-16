#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Ubuntu VM Setup
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Keeps all colour variables available for future visual changes.
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

# --- 2. GLOBAL VARIABLES ---
# Stores timer, log file, defaults, detected environment information, and final status values.
T=15
REBOOT_T=30

LOG_FILE="/var/log/ubuntu-vm-setup.log"
VERIFY_LOG="/var/log/ubuntu-vm-setup-verify.log"
COMPLETED_MARKER="/root/.ubuntu-vm-setup-completed"

DEFAULT_USERNAME="orik"

USERNAME=""
EXISTING_USER="no"
SUDO_USER_CREATED="no"
USER_ADDED_TO_SUDO="no"
USER_PASSWORD_LOCKED="no"

SSH_HARDENING_APPLIED="no"
QEMU_AGENT_INSTALLED="no"
UFW_ENABLED="no"
ROOT_EXPANDED="no"
UBUNTU_PRO_ATTACHED="no"

IS_CONTAINER="no"
IS_LXC="no"
IS_VM="no"
VIRT_TYPE="unknown"

ROOT_KEYS="/root/.ssh/authorized_keys"
CURRENT_USER_KEYS=""
SOURCE_KEYS=""
DEST_KEYS=""

ROOT_SOURCE=""
ROOT_LV_PATH=""
VG_NAME=""
VG_FREE_BYTES="0"

PRO_TOKEN=""

SUDO_CMD=""
TEMP_FILES=()

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
# Displays the Ubuntu VM Setup banner.
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

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent display -> apply -> success output style.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. SECTION HEADER HELPER ---
# Keeps terminal output clean and grouped by task.
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
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
# Removes temporary files created by run_cmd.
function cleanup() {
    local exit_code="$?"

    for file in "${TEMP_FILES[@]:-}"; do
        [ -n "$file" ] && [ -f "$file" ] && rm -f "$file" 2>/dev/null || true
    done

    exit "$exit_code"
}

# --- 9. ERROR TRAP HELPER ---
# Shows the failing line number and points to the log file.
function on_error() {
    local line_no="$1"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"
}

# --- 10. COMMAND RUNNER ---
# Runs privileged commands quietly, but shows real stderr if they fail.
# Do not use this for commands containing secrets such as Ubuntu Pro token.
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
# Runs non-critical privileged commands quietly and does not stop the script.
function run_optional() {
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" "$@" >/dev/null 2>&1 || true
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

# --- 12. ROOT FILE TEST HELPER ---
# Checks root-owned paths safely when the script is running with sudo.
function root_file_exists() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -f "$path"
    else
        test -f "$path"
    fi
}

# --- 13. ROOT FILE CAT HELPER ---
# Prints root-owned files safely when the script is running with sudo.
function root_cat_file() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" cat "$path"
    else
        cat "$path"
    fi
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 14. YES/NO LABEL HELPER ---
# Converts Y/N answers to readable yes/no text.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 15. BLOCKING YES/NO HELPER ---
# SPACE pauses countdown and waits for Y/N/ENTER.
# Display style matches Proxmox VM Setup: no "timer stopped" wording.
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

# --- 16. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown instead of loop countdown.
# SPACE pauses and waits.
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

# --- 17. EDITABLE INPUT LOOP HELPER ---
# Provides editable text input with backspace support.
# SPACE starts this same editable mode with no extra wording.
function editable_input_loop() {
    local prompt="$1"
    local default="$2"
    local initial_value="${3:-}"
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
                tty_print "${BFR}"
                echo "$answer"
                return 0
                ;;
            $'\177'|$'\b')
                answer="${answer%?}"
                ;;
            *)
                answer+="$key"
                ;;
        esac
    done
}

# --- 18. TIMED TEXT INPUT HELPER ---
# Uses wall-clock countdown with editable text input.
# SPACE pauses countdown and opens editable mode.
# Any typed character pauses countdown and starts editable mode with that character.
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""
    local key=""
    local deadline=""
    local now=""
    local remaining=""

    deadline=$(( $(date +%s) + T ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            answer="$default"
            break
        fi

        tty_print "${BFR}${YW}${prompt} [default: ${default}] [${remaining}s]: ${CL}"

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                if [[ "$key" == " " ]]; then
                    answer="$(editable_input_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "$key")"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(editable_input_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "$key")"
                    break
                fi
            fi
        fi
    done

    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"

    echo "$answer"
}

# --- 19. HIDDEN INPUT HELPER ---
# Reads sensitive input from terminal without echoing it.
# Used for Ubuntu Pro token so it does not appear on-screen or in logs.
function hidden_input() {
    local prompt="$1"
    local answer=""

    tty_print "${YW}${prompt}: ${CL}"

    if [ -r /dev/tty ]; then
        IFS= read -rs answer < /dev/tty || true
    else
        IFS= read -rs answer || true
    fi

    tty_println ""

    echo "$answer"
}

# --- 20. REBOOT COUNTDOWN HELPER ---
# Shows a safe reboot countdown.
# SPACE stops the reboot.
# Uses sudo reboot when the script is not running as root.
function timed_reboot_countdown() {
    local seconds="$1"
    local key=""
    local deadline=""
    local now=""
    local remaining=""

    deadline=$(( $(date +%s) + seconds ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            tty_print "${BFR}"
            return 0
        fi

        tty_print "${BFR}${BL}${CLF}REBOOTING IN ${remaining} SECONDS...${CL} ${YW}(press SPACE to stop)${CL}"

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                if [[ "$key" == " " ]]; then
                    tty_println "${BFR}${YW}Reboot cancelled. Reboot manually with: sudo reboot${CL}"
                    return 1
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    tty_println "${BFR}${YW}Reboot cancelled. Reboot manually with: sudo reboot${CL}"
                    return 1
                fi
            fi
        fi
    done
}

# =========================================================
#  VALIDATION HELPERS
# =========================================================

# --- 21. USERNAME VALIDATION HELPER ---
# Validates Linux username format before using it in paths and user commands.
function validate_linux_username() {
    local username="$1"

    if [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 0
    fi

    return 1
}

# --- 22. DEPENDENCY VALIDATION ---
# Validates required commands early so failures happen before system changes.
function validate_dependencies() {
    local required_commands=(
        apt-get
        awk
        cat
        chmod
        chown
        date
        findmnt
        grep
        id
        mkdir
        passwd
        readlink
        sed
        sshd
        systemctl
        tee
        useradd
        usermod
        xargs
    )

    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done

    if [ -n "$SUDO_CMD" ]; then
        command -v sudo >/dev/null 2>&1 || msg_error "sudo is required when not running as root."
    fi
}

# =========================================================
#  INITIALIZATION
# =========================================================

# --- 23. ROOT / SUDO DETECTION ---
# Uses sudo when not root.
function detect_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    else
        SUDO_CMD="sudo"
    fi
}

# --- 24. SUDO VALIDATION ---
# Validates sudo once near the start so authentication failures happen before changes.
function validate_sudo_access() {
    if [ -n "$SUDO_CMD" ]; then
        msg_info "Validating sudo access"

        "$SUDO_CMD" -v || msg_error "Sudo authentication failed. Script cancelled."

        msg_ok "SUDO ACCESS CONFIRMED"
    fi
}

# --- 25. LOGGING INITIALIZATION ---
# Starts logging after sudo validation so non-root users can still write to /var/log through sudo tee.
function init_logging() {
    if [ -n "$SUDO_CMD" ]; then
        exec > >("$SUDO_CMD" tee -a "$LOG_FILE") 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

# --- 26. SCRIPT INITIALIZATION ---
# Detects sudo/root, validates access, starts logging, installs traps, shows banner, and validates dependencies.
function init_script() {
    detect_root_or_sudo
    validate_sudo_access
    init_logging

    trap 'on_error "$LINENO"' ERR
    trap cleanup EXIT

    clear
    header_info

    validate_dependencies
}

# --- 27. PREVIOUS MARKER CHECK ---
# Warns if script 4 was already completed previously.
function check_previous_marker() {
    local continue_yn=""

    if root_file_exists "$COMPLETED_MARKER"; then
        section "PREVIOUS UBUNTU VM SETUP MARKER DETECTED"

        echo -e "${YW}A previous Ubuntu VM Setup marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        root_cat_file "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi
}

# =========================================================
#  ENVIRONMENT DETECTION
# =========================================================

# --- 28. ENVIRONMENT DETECTION ---
# Detects whether system is VM, LXC/container, or bare/unknown.
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
        fi
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        msg_ok "ENVIRONMENT DETECTED (${VIRT_TYPE} container)"
    elif [ "$IS_VM" == "yes" ]; then
        msg_ok "ENVIRONMENT DETECTED (${VIRT_TYPE} VM)"
    else
        msg_warn "Environment is not clearly VM/LXC (${VIRT_TYPE}); continuing with safe VM-style defaults"
        IS_VM="yes"
    fi
}

# --- 29. START CONFIRMATION ---
# Starts Ubuntu setup after environment detection.
function start_confirmation() {
    echo ""
    echo -e "${YW}This script will configure Ubuntu for Docker workloads.${CL}"

    if [ "$IS_CONTAINER" == "yes" ]; then
        echo -e "${YW}LXC/container mode detected: QEMU Guest Agent and LVM root expansion will be skipped.${CL}"
        echo -e "${YW}UFW firewall will be optional because some containers do not allow firewall control inside the guest.${CL}"
    else
        echo -e "${YW}VM mode detected: QEMU Guest Agent, LVM root expansion, UFW and SSH hardening will be configured where applicable.${CL}"
    fi

    echo ""

    start_yn="$(timed_yes_no "Start the Ubuntu VM Setup Script?" "y")"
    [[ "$start_yn" =~ ^[Nn] ]] && exit 0
}

# =========================================================
#  USER / SSH SETUP
# =========================================================

# --- 30. USERNAME INPUT ---
# Selects target non-root admin user and validates username format.
function collect_username() {
    section "USER SETUP"

    while true; do
        USERNAME="$(timed_text_input "Enter username" "$DEFAULT_USERNAME")"

        if validate_linux_username "$USERNAME"; then
            break
        fi

        msg_warn "Invalid username. Use lowercase Linux username format, for example: orik"
    done
}

# --- 31. USER EXISTENCE CHECK ---
# Detects whether the selected user already exists.
function check_user_exists() {
    msg_info "Checking existing user"

    if id "$USERNAME" >/dev/null 2>&1; then
        EXISTING_USER="yes"
    else
        EXISTING_USER="no"
    fi

    msg_ok "USER CHECK COMPLETE"
}

# --- 32. SSH KEY SOURCE DETECTION ---
# Detects best SSH key source automatically.
# Priority:
# 1. Target user's existing authorized_keys
# 2. Root authorized_keys
function detect_ssh_key_source() {
    section "SSH KEY SETUP"

    msg_info "Detecting SSH key source"

    CURRENT_USER_KEYS="/home/${USERNAME}/.ssh/authorized_keys"

    if [ -s "$CURRENT_USER_KEYS" ]; then
        SOURCE_KEYS="$CURRENT_USER_KEYS"
    elif [ -s "$ROOT_KEYS" ]; then
        SOURCE_KEYS="$ROOT_KEYS"
    else
        SOURCE_KEYS=""
    fi

    if [ -n "$SOURCE_KEYS" ]; then
        msg_ok "SSH KEY SOURCE DETECTED (${SOURCE_KEYS})"
    else
        msg_warn "No SSH authorized_keys source found"
    fi
}

# --- 33. USER CREATION / REUSE ---
# Creates the user only if missing and ensures the selected user is in the sudo group.
function create_or_reuse_user() {
    local lock_yn=""

    if [ "$EXISTING_USER" == "no" ]; then
        msg_info "Creating user ${USERNAME}"

        run_cmd "creating user ${USERNAME}" useradd -m -s /bin/bash "$USERNAME"
        SUDO_USER_CREATED="yes"

        msg_ok "USER CREATED"

        lock_yn="$(timed_yes_no "Lock password for SSH-key-only user?" "y")"

        if [[ "$lock_yn" =~ ^[Yy] ]]; then
            msg_info "Locking password for ${USERNAME}"
            run_optional passwd -l "$USERNAME"
            USER_PASSWORD_LOCKED="yes"
            msg_ok "USER PASSWORD LOCKED"
        else
            USER_PASSWORD_LOCKED="no"
            msg_warn "User password was not locked"
        fi
    else
        msg_ok "USER ${USERNAME} ALREADY EXISTS"
    fi

    msg_info "Ensuring ${USERNAME} is in sudo group"
    run_cmd "adding ${USERNAME} to sudo group" usermod -aG sudo "$USERNAME"
    USER_ADDED_TO_SUDO="yes"
    msg_ok "USER SUDO ACCESS CONFIRMED"
}

# --- 34. SSH KEY CONFIGURATION ---
# Configures SSH keys safely.
# If source and destination are the same file, copy is skipped to avoid cp same-file failure.
function configure_ssh_keys() {
    if [ -z "$SOURCE_KEYS" ]; then
        msg_warn "SSH key configuration skipped because no authorized_keys source was found"
        return 0
    fi

    DEST_KEYS="/home/${USERNAME}/.ssh/authorized_keys"

    run_cmd "creating SSH directory for ${USERNAME}" mkdir -p "/home/${USERNAME}/.ssh"

    if [ "$(readlink -f "$SOURCE_KEYS")" = "$(readlink -f "$DEST_KEYS" 2>/dev/null || echo "$DEST_KEYS")" ]; then
        msg_ok "SSH KEYS ALREADY CONFIGURED"
    else
        msg_info "Configuring SSH keys for ${USERNAME}"

        run_cmd "copying SSH keys for ${USERNAME}" cp "$SOURCE_KEYS" "$DEST_KEYS"

        msg_ok "SSH KEYS CONFIGURED"
    fi

    msg_info "Fixing SSH key ownership and permissions"
    run_cmd "setting SSH directory ownership" chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
    run_cmd "setting SSH directory permissions" chmod 700 "/home/${USERNAME}/.ssh"
    run_cmd "setting authorized_keys permissions" chmod 600 "$DEST_KEYS"
    msg_ok "SSH KEY PERMISSIONS VERIFIED"
}

# =========================================================
#  SYSTEM UPDATE / UBUNTU PRO
# =========================================================

# --- 35. SYSTEM UPDATE ---
# Updates Ubuntu packages before optional Ubuntu Pro attachment and system configuration.
function update_system_packages() {
    section "SYSTEM UPDATE"

    msg_info "Updating package lists"
    run_cmd "updating package lists" apt-get update
    msg_ok "PACKAGE LISTS UPDATED"

    msg_info "Upgrading system packages"
    run_cmd "upgrading system packages" env DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade
    msg_ok "SYSTEM PACKAGES UPGRADED"

    msg_info "Removing unused packages"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
    msg_ok "UNUSED PACKAGES REMOVED"
}

# --- 36. UBUNTU PRO ATTACHMENT ---
# Optionally attaches Ubuntu Pro using a token entered by the user.
# The token is read silently and is not written to the log, marker file, or final summary.
function handle_ubuntu_pro() {
    local pro_yn=""
    local err_file=""

    section "UBUNTU PRO"

    pro_yn="$(timed_yes_no "Attach Ubuntu Pro token?" "n")"

    if [[ "$pro_yn" =~ ^[Nn] ]]; then
        UBUNTU_PRO_ATTACHED="no"
        msg_ok "UBUNTU PRO ATTACHMENT SKIPPED"
        return 0
    fi

    PRO_TOKEN="$(hidden_input "Enter Ubuntu Pro token")"

    if [ -z "$PRO_TOKEN" ]; then
        UBUNTU_PRO_ATTACHED="no"
        msg_warn "Ubuntu Pro token was empty. Skipping Ubuntu Pro attachment"
        return 0
    fi

    msg_info "Installing Ubuntu Pro client"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-advantage-tools ubuntu-pro-client
    run_cmd "installing Ubuntu Pro client" env DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-advantage-tools
    msg_ok "UBUNTU PRO CLIENT READY"

    msg_info "Attaching Ubuntu Pro"

    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    if [ -n "$SUDO_CMD" ]; then
        if "$SUDO_CMD" pro attach "$PRO_TOKEN" > /dev/null 2> "$err_file"; then
            UBUNTU_PRO_ATTACHED="yes"
            msg_ok "UBUNTU PRO ATTACHED"
        else
            UBUNTU_PRO_ATTACHED="failed"
            msg_warn "Ubuntu Pro attachment failed. Check token or run: sudo pro status"
            cat "$err_file" >/dev/null 2>&1 || true
        fi
    else
        if pro attach "$PRO_TOKEN" > /dev/null 2> "$err_file"; then
            UBUNTU_PRO_ATTACHED="yes"
            msg_ok "UBUNTU PRO ATTACHED"
        else
            UBUNTU_PRO_ATTACHED="failed"
            msg_warn "Ubuntu Pro attachment failed. Check token or run: sudo pro status"
            cat "$err_file" >/dev/null 2>&1 || true
        fi
    fi

    rm -f "$err_file"
    PRO_TOKEN=""
}

# =========================================================
#  VM / LXC BRANCHES
# =========================================================

# --- 37. QEMU GUEST AGENT INSTALL ---
# Installs qemu-guest-agent for Proxmox VM visibility and clean shutdown support.
# Skips inside LXC/container mode.
function install_qemu_guest_agent() {
    section "QEMU GUEST AGENT"

    if [ "$IS_CONTAINER" == "yes" ]; then
        QEMU_AGENT_INSTALLED="skipped-lxc"
        msg_ok "QEMU GUEST AGENT SKIPPED FOR LXC/CONTAINER"
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

# --- 38. ROOT FILESYSTEM LVM EXPANSION ---
# Detects if Ubuntu installed / on LVM and automatically expands it to use remaining free VG space.
# Skips inside LXC/container mode because root storage is controlled by the host.
function expand_root_lvm_if_possible() {
    section "ROOT DISK EXPANSION"

    if [ "$IS_CONTAINER" == "yes" ]; then
        ROOT_EXPANDED="skipped-lxc"
        msg_ok "ROOT LVM EXPANSION SKIPPED FOR LXC/CONTAINER"
        return 0
    fi

    if ! command -v lvs >/dev/null 2>&1 || ! command -v vgs >/dev/null 2>&1 || ! command -v lvextend >/dev/null 2>&1; then
        ROOT_EXPANDED="not-needed"
        msg_ok "LVM TOOLS NOT FOUND; ROOT LVM EXPANSION NOT NEEDED"
        return 0
    fi

    msg_info "Checking root filesystem free space"

    ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    ROOT_LV_PATH=""

    if [ -n "$ROOT_SOURCE" ]; then
        ROOT_LV_PATH="$(readlink -f "$ROOT_SOURCE" 2>/dev/null || echo "$ROOT_SOURCE")"
    fi

    if [ -n "$ROOT_LV_PATH" ] && lvs "$ROOT_LV_PATH" &>/dev/null; then
        VG_NAME="$(lvs --noheadings -o vg_name "$ROOT_LV_PATH" | xargs)"
        VG_FREE_BYTES="$(vgs --noheadings --units b --nosuffix -o vg_free "$VG_NAME" | xargs | cut -d'.' -f1)"

        if [[ "$VG_FREE_BYTES" =~ ^[0-9]+$ ]] && [ "$VG_FREE_BYTES" -gt 1073741824 ]; then
            msg_ok "FOUND EMPTY LVM SPACE"

            msg_info "Expanding Ubuntu root filesystem"
            run_cmd "expanding Ubuntu root filesystem" lvextend -r -l +100%FREE "$ROOT_LV_PATH"
            ROOT_EXPANDED="yes"
            msg_ok "UBUNTU ROOT FILESYSTEM EXPANDED"
        else
            ROOT_EXPANDED="not-needed"
            msg_ok "NO EMPTY LVM SPACE FOUND"
        fi
    else
        ROOT_EXPANDED="not-needed"
        msg_ok "ROOT FILESYSTEM LVM EXPANSION NOT NEEDED"
    fi
}

# --- 39. UFW FIREWALL SETUP ---
# Enables UFW baseline firewall for VM mode.
# In LXC/container mode, asks before attempting because firewall control may be blocked by container restrictions.
function configure_ufw_firewall() {
    local lxc_ufw_yn=""

    section "FIREWALL"

    if [ "$IS_CONTAINER" == "yes" ]; then
        echo -e "${YW}LXC/container mode detected. UFW may not work unless the container has required netfilter permissions.${CL}"
        lxc_ufw_yn="$(timed_yes_no "Attempt UFW firewall setup inside LXC/container?" "n")"

        if [[ "$lxc_ufw_yn" =~ ^[Nn] ]]; then
            UFW_ENABLED="skipped-lxc"
            msg_ok "UFW FIREWALL SKIPPED FOR LXC/CONTAINER"
            return 0
        fi
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
            msg_warn "UFW failed to enable. This can happen inside restricted LXC containers."
        fi
    else
        if ufw --force enable >/dev/null 2>&1; then
            UFW_ENABLED="yes"
            msg_ok "UFW FIREWALL ENABLED"
        else
            UFW_ENABLED="failed"
            msg_warn "UFW failed to enable. This can happen inside restricted LXC containers."
        fi
    fi
}

# =========================================================
#  SSH HARDENING / CLEANUP
# =========================================================

# --- 40. SSH HARDENING ---
# Disables SSH password login and root login only if target user SSH keys exist.
# This avoids lockout on systems where no authorized_keys are present.
function harden_ssh() {
    local ssh_config="/etc/ssh/sshd_config"

    section "SSH HARDENING"

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

    msg_info "Hardening SSH configuration"

    run_optional sed -i -E 's/^[#[:space:]]*AddressFamily.*/AddressFamily inet/' "$ssh_config"
    grep -q "^AddressFamily" "$ssh_config" || printf '%s\n' "AddressFamily inet" | $SUDO_CMD tee -a "$ssh_config" >/dev/null

    run_optional sed -i -E 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' "$ssh_config"
    grep -q "^PasswordAuthentication" "$ssh_config" || printf '%s\n' "PasswordAuthentication no" | $SUDO_CMD tee -a "$ssh_config" >/dev/null

    run_optional sed -i -E 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$ssh_config"
    grep -q "^PermitRootLogin" "$ssh_config" || printf '%s\n' "PermitRootLogin no" | $SUDO_CMD tee -a "$ssh_config" >/dev/null

    run_cmd "validating sshd configuration" sshd -t

    run_optional systemctl restart ssh
    run_optional systemctl restart sshd

    SSH_HARDENING_APPLIED="yes"

    msg_ok "SSH HARDENING APPLIED"
}

# --- 41. SYSTEM CLEANUP ---
# Cleans package cache and orphan packages.
function clean_system() {
    section "SYSTEM CLEANUP"

    msg_info "Cleaning system"
    run_optional apt-get clean
    run_optional apt-get -y autoremove
    msg_ok "SYSTEM CLEANED"
}

# =========================================================
#  VERIFICATION / MARKER / SUMMARY
# =========================================================

# --- 42. COMPLETION MARKER ---
# Stores successful setup information.
# Ubuntu Pro token is intentionally not stored.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<EOF
Ubuntu VM Setup completed on: $(date)
Username: $USERNAME
User Created: $SUDO_USER_CREATED
User Added To Sudo: $USER_ADDED_TO_SUDO
User Password Locked: $USER_PASSWORD_LOCKED
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM
Ubuntu Pro Attached: $UBUNTU_PRO_ATTACHED
QEMU Agent: $QEMU_AGENT_INSTALLED
Root Expanded: $ROOT_EXPANDED
UFW: $UFW_ENABLED
SSH Hardened: $SSH_HARDENING_APPLIED
Verify Log: $VERIFY_LOG
EOF
    else
        cat > "$COMPLETED_MARKER" <<EOF
Ubuntu VM Setup completed on: $(date)
Username: $USERNAME
User Created: $SUDO_USER_CREATED
User Added To Sudo: $USER_ADDED_TO_SUDO
User Password Locked: $USER_PASSWORD_LOCKED
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM
Ubuntu Pro Attached: $UBUNTU_PRO_ATTACHED
QEMU Agent: $QEMU_AGENT_INSTALLED
Root Expanded: $ROOT_EXPANDED
UFW: $UFW_ENABLED
SSH Hardened: $SSH_HARDENING_APPLIED
Verify Log: $VERIFY_LOG
EOF
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 43. VERIFICATION REPORT ---
# Writes a clear verification report to /var/log and prints it once at the end.
function create_verification_report() {
    section "VERIFICATION"

    msg_info "Creating verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<EOF
--- UBUNTU VM SETUP VERIFICATION REPORT ---
Date: $(date)
Username: $USERNAME
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM

Results:
EOF
    else
        cat > "$VERIFY_LOG" <<EOF
--- UBUNTU VM SETUP VERIFICATION REPORT ---
Date: $(date)
Username: $USERNAME
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM

Results:
EOF
    fi

    {
        if id "$USERNAME" >/dev/null 2>&1; then echo "✓ PASS - User exists"; else echo "✗ FAIL - User missing"; fi
        if id -nG "$USERNAME" 2>/dev/null | grep -qw sudo; then echo "✓ PASS - User is in sudo group"; else echo "! WARN - User sudo group not confirmed"; fi
        if [ -s "/home/${USERNAME}/.ssh/authorized_keys" ]; then echo "✓ PASS - SSH authorized_keys present"; else echo "! WARN - SSH authorized_keys missing"; fi
        if sshd -t >/dev/null 2>&1; then echo "✓ PASS - sshd configuration valid"; else echo "✗ FAIL - sshd configuration invalid"; fi

        if [ "$SSH_HARDENING_APPLIED" == "yes" ]; then
            if sshd -T 2>/dev/null | grep -q "^passwordauthentication no"; then echo "✓ PASS - SSH password authentication disabled"; else echo "✗ FAIL - SSH password authentication still enabled"; fi
            if sshd -T 2>/dev/null | grep -Eq "^permitrootlogin (no|prohibit-password|without-password)"; then echo "✓ PASS - Root SSH login disabled or passwordless-only"; else echo "! WARN - Root SSH login not confirmed secure"; fi
        else
            echo "! WARN - SSH hardening was not applied"
        fi

        if [ "$IS_CONTAINER" == "yes" ]; then
            echo "! INFO - QEMU Guest Agent skipped for container"
            echo "! INFO - Root LVM expansion skipped for container"
        else
            if systemctl is-active --quiet qemu-guest-agent 2>/dev/null; then echo "✓ PASS - QEMU guest agent active"; else echo "! WARN - QEMU guest agent not active"; fi
            df -h / 2>/dev/null || true
        fi

        if [ "$UFW_ENABLED" == "yes" ]; then
            if ufw status 2>/dev/null | grep -qi "Status: active"; then echo "✓ PASS - UFW active"; else echo "! WARN - UFW expected active but not confirmed"; fi
        else
            echo "! INFO - UFW state: $UFW_ENABLED"
        fi

        if command -v pro >/dev/null 2>&1; then
            pro status 2>/dev/null | head -n 10 || true
        else
            echo "! INFO - Ubuntu Pro client not available"
        fi

        if [ -f "$COMPLETED_MARKER" ]; then echo "✓ PASS - Completion marker exists"; else echo "! WARN - Completion marker missing"; fi
    } | if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee -a "$VERIFY_LOG" >/dev/null; else tee -a "$VERIFY_LOG" >/dev/null; fi

    msg_ok "VERIFICATION REPORT CREATED"
}

# --- 44. FINAL SUMMARY ---
# Displays clean final setup summary and next step.
function show_final_summary() {
    section "UBUNTU VM SETUP SUMMARY"

    echo -e "USERNAME:             ${GN}${USERNAME}${CL}"
    echo -e "USER CREATED:         ${GN}${SUDO_USER_CREATED}${CL}"
    echo -e "USER ADDED TO SUDO:   ${GN}${USER_ADDED_TO_SUDO}${CL}"
    echo -e "PASSWORD LOCKED:      ${GN}${USER_PASSWORD_LOCKED}${CL}"
    echo -e "ENVIRONMENT:          ${GN}$([ "$IS_CONTAINER" == "yes" ] && echo "LXC/Container (${VIRT_TYPE})" || echo "VM (${VIRT_TYPE})")${CL}"
    echo -e "UBUNTU PRO ATTACHED:  ${GN}${UBUNTU_PRO_ATTACHED}${CL}"
    echo -e "QEMU GUEST AGENT:     ${GN}${QEMU_AGENT_INSTALLED}${CL}"
    echo -e "ROOT EXPANDED:        ${GN}${ROOT_EXPANDED}${CL}"
    echo -e "UFW FIREWALL:         ${GN}${UFW_ENABLED}${CL}"
    echo -e "SSH HARDENING:        ${GN}${SSH_HARDENING_APPLIED}${CL}"
    echo -e "LOG FILE:             ${GN}${LOG_FILE}${CL}"
    echo -e "VERIFY LOG:           ${GN}${VERIFY_LOG}${CL}"
    echo ""
    echo -e "${GN}Ubuntu setup completed successfully.${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}After reboot and SSH reconnect, run script 5-dockerSetup.sh.${CL}"
    echo ""
}

# --- 45. REBOOT PROMPT ---
# Offers safe reboot using sudo reboot when not root.
# In LXC/container mode, default is no because host/container policy may control restarts.
function reboot_prompt() {
    local reboot_yn=""
    local default_reboot="y"

    section "REBOOT"

    if [ "$IS_CONTAINER" == "yes" ]; then
        default_reboot="n"
        echo -e "${YW}Container mode detected. Reboot/restart may be controlled from the Proxmox host.${CL}"
    fi

    reboot_yn="$(timed_yes_no "Reboot Ubuntu system now?" "$default_reboot")"

    if [[ "$reboot_yn" =~ ^[Yy] ]]; then
        if timed_reboot_countdown "$REBOOT_T"; then
            if [ -n "$SUDO_CMD" ]; then
                "$SUDO_CMD" reboot
            else
                reboot
            fi
        fi
    else
        echo -e "${YW}Reboot skipped. Reboot manually with: sudo reboot${CL}"
    fi
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 46. MAIN FUNCTION ---
# Runs the full setup in clear validation -> input -> apply -> verify order.
function main() {
    init_script
    check_previous_marker
    detect_environment
    start_confirmation

    collect_username
    check_user_exists
    detect_ssh_key_source
    create_or_reuse_user
    configure_ssh_keys

    update_system_packages
    handle_ubuntu_pro

    install_qemu_guest_agent
    expand_root_lvm_if_possible
    configure_ufw_firewall
    harden_ssh
    clean_system

    write_completion_marker
    create_verification_report
    show_final_summary
    reboot_prompt

    exit 0
}

main "$@"