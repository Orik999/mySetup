#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker Setup
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Central visual theme for Docker Setup.
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

SCRIPT_SOURCE="5-dockerSetup.sh"
SCRIPT_VERSION="v1.2.0"
SCRIPT_UPDATED="2026-05-22"
SCRIPT_BUILD="audit-reboot-collected-untimed-inputs-stability"

# --- 2. GLOBAL VARIABLES ---
# Stores timer, log paths, user choices, environment state and final status values.
T=15
REBOOT_T=30

LOG_FILE="/var/log/docker-setup.log"
RUNTIME_LOG_FILE=""
VERIFY_LOG="/var/log/docker-setup-verify.log"
COMPLETED_MARKER="/root/.docker-setup-completed"

DEFAULT_TARGET_USER="${SUDO_USER:-orik}"
TARGET_USER="$DEFAULT_TARGET_USER"

SUDO_CMD=""

IS_CONTAINER="no"
IS_LXC="no"
IS_VM="no"
VIRT_TYPE="unknown"

EXISTING_SETUP="no"
DOCKER_CLI_FOUND="no"
DOCKER_DAEMON_CONFIG_FOUND="no"
DOCKER_MARKER_FOUND="no"
DOCKER_SERVICE_ACTIVE="no"
CONTAINERD_SERVICE_ACTIVE="no"

DISABLE_SWAP="y"
INSTALL_DOCKER_GC="y"
CONFIGURE_UFW="y"
DOCKER_FIREWALL_MODE="docker-iptables-enabled"
REBOOT_AFTER_FINISH="y"

DOCKER_INSTALLED="no"
DOCKER_SERVICE_ENABLED="no"
CONTAINERD_SERVICE_ENABLED="no"
DOCKER_GROUP_READY="no"
USER_ADDED_TO_DOCKER="no"
DAEMON_CONFIG_VALID="no"
UFW_ENABLED="no"
SWAP_DISABLED="no"
DOCKER_GC_INSTALLED="no"
DOCKER_GC_TIMER_INSTALLED="no"
REDIS_OVERCOMMIT_CONFIGURED="no"
REDIS_OVERCOMMIT_VALUE="unknown"

UBUNTU_CODENAME=""
ARCHITECTURE=""

TEMP_FILES=()

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
# Displays the Docker Setup banner.
function header_info {
echo -e "${BL}
██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗     ███████╗███████╗████████╗██╗   ██╗██████╗ 
██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝    ███████╗█████╗     ██║   ██║   ██║██████╔╝
██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║    ███████║███████╗   ██║   ╚██████╔╝██║     
╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
${CL}"
}

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent status messages.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_skip() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- SCRIPT VERSION DISPLAY ---
# Prints the currently running script version immediately under the ASCII banner.
function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

# --- 5. SECTION HEADER HELPER ---
# Keeps terminal output organized into readable stages.
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

# --- 5A. FLASHING SUCCESS SECTION HEADER HELPER ---
# Uses the same section layout as script 1, but renders final success headings in bold flashing green.
function section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

# --- 5B. DETAIL LINE HELPER ---
# Prints clean script 1-style detail lines for summaries and audit output.
function detail_line() {
    local label="$1"
    local value="$2"
    echo -e " ${BL}━━━━━▶${CL} ${label}: ${GN}${value}${CL}"
}

# --- 6. TTY OUTPUT HELPER ---
# Prints directly to terminal from prompt functions.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 7. TTY OUTPUT WITH NEWLINE HELPER ---
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
# Removes temporary files created during repository/key/command handling.
function cleanup() {
    local exit_code="$?"
    local file=""

    # When running as a non-root user, write logs to a user-writable temp file first.
    # This avoids routing interactive prompts through sudo tee, which can break prompt ordering.
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
# Shows failing line number and points to the log file.
function on_error() {
    local line_no="$1"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"
}

# --- 10. COMMAND RUNNER ---
# Runs privileged commands quietly, but shows real stderr if they fail.
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

# --- 12. ROOT FILE WRITE HELPER ---
# Writes stdin to a privileged path with sudo when required.
function write_root_file() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" tee "$path" >/dev/null
    else
        cat > "$path"
    fi
}

# --- 13. ROOT PATH EXISTS HELPER ---
# Checks whether a root-owned path exists.
function root_path_exists() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -e "$path"
    else
        test -e "$path"
    fi
}

# --- 14. ROOT FILE CAT HELPER ---
# Reads root-owned file content.
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

# --- 15. INPUT BUFFER FLUSH HELPER ---
# Clears leftover buffered keyboard input between prompts.
# This prevents ENTER/SPACE from needing to be pressed twice on Ubuntu terminal sessions.
function flush_input_buffer() {
    local junk=""
    local i=""

    # Never flush stdin. Streamed/process-substituted scripts may use stdin for script content.
    [ -r /dev/tty ] || return 0

    for i in {1..20}; do
        if ! IFS= read -rsn1 -t 0.02 junk < /dev/tty 2>/dev/null; then
            break
        fi
    done

    return 0
}

# --- 16. YES/NO LABEL HELPER ---
# Converts Y/N answers to visible yes/no.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 17. BLOCKING YES/NO HELPER ---
# Used after SPACE is pressed during a timed Y/n prompt.
# The countdown disappears and the prompt waits for Y/N/ENTER.
# ENTER accepts the default.
function tty_read_yes_no_blocking() {
    local prompt="$1"
    local default="$2"
    local default_label="Y/n"
    local key=""

    if [[ "$default" =~ ^[Nn]$ ]]; then
        default_label="y/N"
    fi

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

# --- 18. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown.
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
    flush_input_buffer

    echo "$answer"
}

# --- 19. EDITABLE INPUT LOOP HELPER ---
# Shared editable input system for text prompts.
# The initial key is passed into the same editable buffer, so Backspace/Delete can delete it.
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
            $'\177'|$'\b')
                answer="${answer%?}"
                ;;
            *)
                answer+="$key"
                ;;
        esac
    done
}

# --- 20. TIMED TEXT INPUT HELPER ---
# Shows wall-clock countdown.
# SPACE pauses with empty editable buffer.
# Any typed character pauses with that character already inside the editable buffer.
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

# --- 21. REBOOT COUNTDOWN HELPER ---
# Offers Ubuntu VM Setup-compatible reboot flow so Docker group membership applies cleanly.
# ENTER/Y = reboot now.
# SPACE/N = cancel reboot.
# Timeout = reboot automatically.
function timed_reboot_countdown() {
    local seconds="$1"
    local key=""
    local deadline=""
    local now=""
    local remaining=""
    local first_draw="yes"

    deadline=$(( $(date +%s) + seconds ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            if [ "$first_draw" == "no" ]; then
                tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
            fi
            return 0
        fi

        if [ "$first_draw" == "yes" ]; then
            first_draw="no"
        else
            tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
        fi

        tty_print "${BL}${CLF}REBOOTING IN ${remaining} SECONDS...${CL}\n${YW}(ENTER/Y = Reboot Now, SPACE/N = Cancel)${CL}\n"

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                case "$key" in
                    ""|[Yy])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${BL}${CLF}REBOOTING NOW...${CL}"
                        flush_input_buffer
                        return 0
                        ;;
                    " "|[Nn])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                        flush_input_buffer
                        return 1
                        ;;
                esac
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                case "$key" in
                    ""|[Yy])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${BL}${CLF}REBOOTING NOW...${CL}"
                        flush_input_buffer
                        return 0
                        ;;
                    " "|[Nn])
                        tty_print "\033[2A\033[2K\r\033[1B\033[1A"
                        tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                        flush_input_buffer
                        return 1
                        ;;
                esac
            fi
        fi
    done
}

# =========================================================
#  VALIDATION HELPERS
# =========================================================

# --- 22. USERNAME VALIDATION HELPER ---
# Validates Linux username format before using it in usermod/group logic.
function validate_linux_username() {
    local username="$1"

    if [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 0
    fi

    return 1
}

# --- 23. DEPENDENCY VALIDATION ---
# Validates base commands before system changes.
function validate_dependencies() {
    local required_commands=(
        apt-get
        awk
        cat
        chmod
        cp
        date
        dpkg
        getent
        grep
        groupadd
        id
        install
        mkdir
        mktemp
        rm
        sed
        swapoff
        swapon
        systemctl
        tee
        uname
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

# --- 24. DAEMON JSON VALIDATION HELPER ---
# Validates daemon.json before restarting Docker.
function validate_docker_daemon_json() {
    if command -v dockerd >/dev/null 2>&1; then
        if dockerd --validate --config-file /etc/docker/daemon.json >/dev/null 2>&1; then
            DAEMON_CONFIG_VALID="yes"
            return 0
        fi
    fi

    if command -v python3 >/dev/null 2>&1; then
        if python3 -m json.tool /etc/docker/daemon.json >/dev/null 2>&1; then
            DAEMON_CONFIG_VALID="yes"
            return 0
        fi
    fi

    DAEMON_CONFIG_VALID="no"
    return 1
}

# =========================================================
#  INITIALIZATION
# =========================================================

# --- 25. ROOT / SUDO DETECTION ---
# Uses sudo when not root.
function detect_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    else
        SUDO_CMD="sudo"
    fi
}

# --- 26. SUDO VALIDATION ---
# Validates sudo once near the start so authentication failures happen before changes.
function validate_sudo_access() {
    if [ -n "$SUDO_CMD" ]; then
        echo -e "${YW}Sudo privileges are required for Docker Setup.${CL}"

        # Script 3.5 creates an SSH-key-only user with NOPASSWD sudo.
        # Test that path first so the script never asks for a password unnecessarily.
        if "$SUDO_CMD" -n true >/dev/null 2>&1; then
            echo -e " ${CM} ${GN}PASSWORDLESS SUDO CONFIRMED${CL}"
            return 0
        fi

        # Fallback for manually-created Ubuntu users that do have a normal sudo password.
        if "$SUDO_CMD" -v; then
            echo -e " ${CM} ${GN}SUDO ACCESS CONFIRMED${CL}"
            return 0
        fi

        echo -e "${RD}ERROR:${CL} Sudo authentication failed."
        exit 1
    fi
}

# --- 27. LOGGING INITIALIZATION ---
# Logs output and reports failing line. Uses sudo tee when not running as root.
function init_logging() {
    if [ -n "$SUDO_CMD" ]; then
        # Avoid piping interactive output through sudo tee.
        # Prompt functions write to /dev/tty and normal output is logged to a temp file first.
        RUNTIME_LOG_FILE="$(mktemp /tmp/docker-setup-log.XXXXXX)"
        TEMP_FILES+=("$RUNTIME_LOG_FILE")
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        RUNTIME_LOG_FILE="$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

# --- 28. SCRIPT INITIALIZATION ---
# Starts sudo, logging, traps, banner and validation.
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

# =========================================================
#  ENVIRONMENT / RERUN SAFETY
# =========================================================

# --- 29. ENVIRONMENT DETECTION ---
# Detects VM, LXC/container, or unknown host.
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
        CONFIGURE_UFW="n"
        DISABLE_SWAP="n"
        msg_ok "ENVIRONMENT DETECTED (${VIRT_TYPE} container)"
    elif [ "$IS_VM" == "yes" ]; then
        CONFIGURE_UFW="y"
        DISABLE_SWAP="y"
        msg_ok "ENVIRONMENT DETECTED (${VIRT_TYPE} VM)"
    else
        CONFIGURE_UFW="y"
        DISABLE_SWAP="y"
        msg_warn "Environment is not clearly VM/LXC (${VIRT_TYPE}); continuing with VM-style defaults"
        IS_VM="yes"
    fi
}

# --- 30. PREVIOUS MARKER CHECK ---
# Warns if Docker Setup was already completed previously.
function check_previous_marker() {
    local continue_yn=""

    if root_path_exists "$COMPLETED_MARKER"; then
        section "PREVIOUS DOCKER SETUP MARKER DETECTED"

        DOCKER_MARKER_FOUND="yes"

        echo -e "${YW}A previous Docker Setup marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        root_cat_file "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi
}

# --- 31. EXISTING SETUP DETECTION ---
# Detects current Docker state and shows exactly what was found.
function detect_existing_setup() {
    local continue_existing_yn=""

    section "EXISTING SETUP CHECK"

    msg_info "Checking for existing Docker setup"

    command -v docker >/dev/null 2>&1 && DOCKER_CLI_FOUND="yes" || DOCKER_CLI_FOUND="no"
    root_path_exists "/etc/docker/daemon.json" && DOCKER_DAEMON_CONFIG_FOUND="yes" || DOCKER_DAEMON_CONFIG_FOUND="no"
    root_path_exists "$COMPLETED_MARKER" && DOCKER_MARKER_FOUND="yes" || DOCKER_MARKER_FOUND="no"

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null; then
        DOCKER_SERVICE_ACTIVE="yes"
    else
        DOCKER_SERVICE_ACTIVE="no"
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet containerd 2>/dev/null; then
        CONTAINERD_SERVICE_ACTIVE="yes"
    else
        CONTAINERD_SERVICE_ACTIVE="no"
    fi

    if [ "$DOCKER_CLI_FOUND" == "yes" ] || [ "$DOCKER_DAEMON_CONFIG_FOUND" == "yes" ] || [ "$DOCKER_MARKER_FOUND" == "yes" ]; then
        EXISTING_SETUP="yes"
    else
        EXISTING_SETUP="no"
    fi

    msg_ok "EXISTING SETUP CHECK COMPLETE"

    echo ""
    echo -e "${BL}DETECTED STATE:${CL}"
    echo -e "DOCKER CLI FOUND:        ${GN}${DOCKER_CLI_FOUND}${CL}"
    echo -e "DAEMON CONFIG FOUND:     ${GN}${DOCKER_DAEMON_CONFIG_FOUND}${CL}"
    echo -e "COMPLETION MARKER FOUND: ${GN}${DOCKER_MARKER_FOUND}${CL}"
    echo -e "DOCKER SERVICE ACTIVE:   ${GN}${DOCKER_SERVICE_ACTIVE}${CL}"
    echo -e "CONTAINERD ACTIVE:       ${GN}${CONTAINERD_SERVICE_ACTIVE}${CL}"
    echo ""

    if [ "$EXISTING_SETUP" == "yes" ]; then
        echo -e "${RD}WARNING: Existing Docker setup detected.${CL}"
        echo -e "${YW}The script is mostly safe to rerun, but it can update packages, rewrite Docker daemon settings, and reapply firewall rules.${CL}"
        echo ""

        continue_existing_yn="$(timed_yes_no "Continue with existing Docker setup?" "n")"

        if [[ "$continue_existing_yn" =~ ^[Nn] ]]; then
            echo -e "${YW}Docker Setup cancelled. Existing files were left untouched.${CL}"
            exit 0
        fi
    fi
}

# --- 32. START CONFIRMATION ---
# Starts Docker installation after environment and existing setup checks.
function start_confirmation() {
    local lxc_continue_yn=""
    local start_yn=""

    section "START"

    echo -e "${YW}This script will install and configure Docker Engine, Docker CLI, containerd, Compose plugin and Buildx plugin.${CL}"

    if [ "$IS_CONTAINER" == "yes" ]; then
        echo ""
        echo -e "${RD}LXC/container mode detected.${CL}"
        echo -e "${YW}Docker inside LXC requires Proxmox host support such as nesting, cgroups and suitable container privileges.${CL}"
        echo -e "${YW}Swap handling, UFW and reboot are skipped/defaulted to safer container settings.${CL}"
        echo ""

        lxc_continue_yn="$(timed_yes_no "Continue Docker install inside LXC/container?" "n")"

        if [[ "$lxc_continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi

    start_yn="$(timed_yes_no "Start the Docker Setup Script?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    return 0

    return 0
}

# =========================================================
#  USER OPTIONS
# =========================================================

# --- 33. USER OPTIONS ---
# Lets user confirm target user, swap behaviour, UFW baseline and optional docker-gc install.
function collect_user_options() {
    local swap_yn=""
    local gc_yn=""
    local ufw_yn=""
    local reboot_yn=""

    section "USER OPTIONS"

    while true; do
        TARGET_USER="$(timed_text_input "Enter Linux user to add to docker group" "$TARGET_USER")"

        if validate_linux_username "$TARGET_USER"; then
            break
        fi

        msg_warn "Invalid username. Use lowercase Linux username format, for example: orik"
    done

    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        msg_error "Target user ${TARGET_USER} does not exist. Run script 4 first or create the user."
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        swap_yn="$(timed_yes_no "Disable swap in /etc/fstab? LXC default is no" "n")"
    else
        swap_yn="$(timed_yes_no "Disable swap in /etc/fstab?" "y")"
    fi
    if [[ "$swap_yn" =~ ^[Nn] ]]; then
        DISABLE_SWAP="n"
    else
        DISABLE_SWAP="y"
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        ufw_yn="$(timed_yes_no "Configure UFW firewall inside LXC/container?" "n")"
    else
        ufw_yn="$(timed_yes_no "Configure UFW firewall baseline?" "y")"
    fi
    if [[ "$ufw_yn" =~ ^[Nn] ]]; then
        CONFIGURE_UFW="n"
    else
        CONFIGURE_UFW="y"
    fi

    gc_yn="$(timed_yes_no "Install safe Docker cleanup helper and weekly systemd timer?" "y")"
    if [[ "$gc_yn" =~ ^[Yy] ]]; then
        INSTALL_DOCKER_GC="y"
    else
        INSTALL_DOCKER_GC="n"
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        REBOOT_AFTER_FINISH="n"
    else
        reboot_yn="$(timed_yes_no "Reboot automatically after Docker setup finishes?" "y")"
        if [[ "$reboot_yn" =~ ^[Nn] ]]; then
            REBOOT_AFTER_FINISH="n"
        else
            REBOOT_AFTER_FINISH="y"
        fi
    fi
}


# --- READY TO APPLY SUMMARY ---
# Shows all collected answers before any Docker/system-changing actions are applied.
function show_ready_to_apply() {
    local apply_yn=""

    section "READY TO APPLY"

    echo -e "${YW}All questions have been collected. No Docker/system-changing actions have been applied yet.${CL}"
    echo ""
    detail_line "Environment" "$VIRT_TYPE"
    detail_line "Target user" "$TARGET_USER"
    detail_line "Existing Docker setup" "$EXISTING_SETUP"
    detail_line "Disable swap" "$DISABLE_SWAP"
    detail_line "Configure UFW" "$CONFIGURE_UFW"
    detail_line "Install safe Docker cleanup timer" "$INSTALL_DOCKER_GC"
    detail_line "Reboot after finish" "$REBOOT_AFTER_FINISH"
    detail_line "Docker firewall mode" "$DOCKER_FIREWALL_MODE"
    echo ""

    apply_yn="$(timed_yes_no "Apply this Docker setup plan now?" "y")"

    if [[ "$apply_yn" =~ ^[Nn] ]]; then
        echo -e "${YW}Docker Setup cancelled. No Docker/system-changing actions were applied.${CL}"
        exit 0
    fi

    return 0

    return 0
}

# =========================================================
#  APPLY FUNCTIONS
# =========================================================

# --- 34. SWAP HANDLING ---
# Disables swap for Docker/database stability if selected.
# Backs up /etc/fstab before editing and avoids double-commenting lines.
function handle_swap() {
    section "SWAP HANDLING"

    if [ "$DISABLE_SWAP" != "y" ]; then
        SWAP_DISABLED="no"
        msg_skip "SWAP WAS NOT DISABLED BECAUSE USER CHOSE NO"
        return 0
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        msg_warn "Swap handling inside LXC/container may be controlled by the Proxmox host"
    fi

    msg_info "Backing up /etc/fstab"
    run_optional cp -n /etc/fstab /etc/fstab.docker-setup.bak
    msg_ok "FSTAB BACKUP CREATED OR ALREADY EXISTS"

    msg_info "Turning off active swap"
    run_optional swapoff -a
    msg_ok "ACTIVE SWAP TURNED OFF OR NOT ACTIVE"

    msg_info "Commenting swap entries in /etc/fstab"
    run_cmd "commenting swap entries in /etc/fstab" sed -i -E '/[[:space:]]swap[[:space:]]/ s/^([^#])/#\1/' /etc/fstab
    msg_ok "FSTAB SWAP ENTRIES DISABLED"

    SWAP_DISABLED="yes"

    msg_ok "SWAP DISABLED"
}

# --- 35. DOCKER REPOSITORY DEPENDENCIES ---
# Installs packages needed to add Docker's official Ubuntu repository.
function install_repository_dependencies() {
    section "DOCKER REPOSITORY DEPENDENCIES"

    msg_info "Updating APT package lists"
    run_cmd "updating APT package lists" apt-get update
    msg_ok "APT PACKAGE LISTS UPDATED"

    msg_info "Installing Docker repository dependencies"
    run_cmd "installing Docker repository dependencies" env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg
    msg_ok "DOCKER REPOSITORY DEPENDENCIES INSTALLED"
}

# --- 36. DOCKER APT REPOSITORY ---
# Adds Docker's official Ubuntu apt repository using docker.sources and docker.asc keyring.
function configure_docker_repository() {
    local key_tmp=""
    local sources_tmp=""

    section "DOCKER REPOSITORY"

    msg_info "Detecting Ubuntu codename and architecture"

    if [ ! -f /etc/os-release ]; then
        msg_error "/etc/os-release not found. Cannot configure Docker repository."
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    ARCHITECTURE="$(dpkg --print-architecture)"

    if [ -z "$UBUNTU_CODENAME" ]; then
        msg_error "Could not detect Ubuntu codename from /etc/os-release."
    fi

    msg_ok "UBUNTU REPOSITORY TARGET DETECTED (${UBUNTU_CODENAME}, ${ARCHITECTURE})"

    msg_info "Creating Docker apt keyring directory"
    run_cmd "creating /etc/apt/keyrings" install -m 0755 -d /etc/apt/keyrings
    msg_ok "DOCKER APT KEYRING DIRECTORY READY"

    msg_info "Downloading Docker official GPG key"
    key_tmp="$(mktemp)"
    TEMP_FILES+=("$key_tmp")
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$key_tmp"
    run_cmd "installing Docker official GPG key" install -m 0644 "$key_tmp" /etc/apt/keyrings/docker.asc
    msg_ok "DOCKER OFFICIAL GPG KEY INSTALLED"

    msg_info "Writing Docker apt source"
    sources_tmp="$(mktemp)"
    TEMP_FILES+=("$sources_tmp")

    cat > "$sources_tmp" <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME}
Components: stable
Architectures: ${ARCHITECTURE}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    run_cmd "installing Docker apt source" install -m 0644 "$sources_tmp" /etc/apt/sources.list.d/docker.sources
    msg_ok "DOCKER APT SOURCE WRITTEN"

    msg_info "Updating APT package lists with Docker repository"
    run_cmd "updating APT after Docker repository setup" apt-get update
    msg_ok "APT PACKAGE LISTS UPDATED WITH DOCKER REPOSITORY"
}

# --- 37. DOCKER ENGINE INSTALL ---
# Installs Docker CE, Docker CLI, containerd, Buildx plugin and Compose plugin.
function install_docker_engine() {
    section "DOCKER INSTALL"

    msg_info "Installing Docker Engine and plugins"
    run_cmd "installing Docker Engine and plugins" env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    DOCKER_INSTALLED="yes"

    msg_ok "DOCKER ENGINE AND PLUGINS INSTALLED"

    if command -v systemctl >/dev/null 2>&1; then
        msg_info "Enabling containerd service"

        if systemctl list-unit-files containerd.service >/dev/null 2>&1; then
            run_cmd "enabling containerd service" systemctl enable --now containerd
            CONTAINERD_SERVICE_ENABLED="yes"
            msg_ok "CONTAINERD SERVICE ENABLED"
        else
            CONTAINERD_SERVICE_ENABLED="not-found"
            msg_warn "containerd systemd unit not found"
        fi

        msg_info "Enabling Docker service"

        if systemctl list-unit-files docker.service >/dev/null 2>&1; then
            run_cmd "enabling Docker service" systemctl enable --now docker
            DOCKER_SERVICE_ENABLED="yes"
            msg_ok "DOCKER SERVICE ENABLED"
        else
            DOCKER_SERVICE_ENABLED="not-found"
            msg_warn "Docker systemd unit not found"
        fi
    else
        CONTAINERD_SERVICE_ENABLED="no-systemctl"
        DOCKER_SERVICE_ENABLED="no-systemctl"
        msg_warn "systemctl not available; Docker services were not enabled automatically"
    fi
}

# --- 38. DOCKER GROUP CONFIGURATION ---
# Ensures docker group exists and adds selected user to it.
function configure_docker_group() {
    section "DOCKER GROUP"

    msg_info "Checking docker group"

    if ! getent group docker >/dev/null 2>&1; then
        run_cmd "creating docker group" groupadd docker
    fi

    DOCKER_GROUP_READY="yes"
    msg_ok "DOCKER GROUP READY"

    msg_info "Adding ${TARGET_USER} to docker group"
    run_cmd "adding ${TARGET_USER} to docker group" usermod -aG docker "$TARGET_USER"
    USER_ADDED_TO_DOCKER="yes"
    msg_ok "USER ADDED TO DOCKER GROUP"
}

# --- 39. DOCKER DAEMON CONFIGURATION ---
# Writes Docker daemon.json with iptables enabled, log rotation and live-restore.
function configure_docker_daemon() {
    section "DAEMON CONFIG"

    msg_info "Creating /etc/docker directory"
    run_cmd "creating /etc/docker directory" mkdir -p /etc/docker
    msg_ok "DOCKER CONFIG DIRECTORY READY"

    msg_info "Writing Docker daemon config"

    write_root_file /etc/docker/daemon.json <<EOF
{
  "iptables": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF

    msg_ok "DOCKER DAEMON CONFIG WRITTEN"

    msg_info "Validating Docker daemon config"

    if validate_docker_daemon_json; then
        msg_ok "DOCKER DAEMON CONFIG VALID"
    else
        msg_error "Docker daemon config validation failed."
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files docker.service >/dev/null 2>&1; then
        msg_info "Restarting Docker service"
        run_cmd "restarting Docker service" systemctl restart docker
        msg_ok "DOCKER SERVICE RESTARTED"
    else
        msg_warn "Docker service restart skipped because systemd Docker service was not detected"
    fi

    msg_ok "DOCKER FIREWALL MODE CONFIGURED (${DOCKER_FIREWALL_MODE})"
}

# --- 40. UFW BASELINE ---
# Allows SSH, HTTP and HTTPS on the Ubuntu VM.
# Warns clearly that Docker-published ports can bypass UFW through Docker-managed iptables.
function configure_ufw_firewall() {
    section "FIREWALL"

    echo -e "${YW}Docker manages its own firewall/NAT rules.${CL}"
    echo -e "${YW}UFW protects the host, but Docker-published container ports may still be reachable unless controlled later with DOCKER-USER rules.${CL}"
    echo -e "${YW}For this project, avoid publishing random ports directly; expose public services through Traefik on 80/443.${CL}"
    echo ""

    if [ "$CONFIGURE_UFW" != "y" ]; then
        UFW_ENABLED="no"
        msg_skip "UFW FIREWALL WAS NOT CONFIGURED BECAUSE USER CHOSE NO"
        return 0
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        msg_warn "LXC/container mode detected. UFW may fail without container netfilter permissions."
    fi

    msg_info "Installing UFW"
    run_cmd "installing UFW" env DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
    msg_ok "UFW INSTALLED"

    msg_info "Setting UFW default policies"
    run_optional ufw default deny incoming
    run_optional ufw default allow outgoing
    msg_ok "UFW DEFAULT POLICIES CONFIGURED"

    msg_info "Allowing SSH, HTTP and HTTPS"
    run_optional ufw allow OpenSSH
    run_optional ufw allow 80/tcp
    run_optional ufw allow 443/tcp
    msg_ok "UFW ALLOW RULES ADDED"

    msg_info "Enabling UFW"

    if [ -n "$SUDO_CMD" ]; then
        if "$SUDO_CMD" ufw --force enable >/dev/null 2>&1; then
            UFW_ENABLED="yes"
            msg_ok "UFW ENABLED"
        else
            UFW_ENABLED="failed"
            msg_warn "UFW failed to enable. This can happen inside restricted LXC containers."
        fi
    else
        if ufw --force enable >/dev/null 2>&1; then
            UFW_ENABLED="yes"
            msg_ok "UFW ENABLED"
        else
            UFW_ENABLED="failed"
            msg_warn "UFW failed to enable. This can happen inside restricted LXC containers."
        fi
    fi

    msg_ok "UFW FIREWALL CONFIGURED"
}

# --- 41. REDIS HOST TUNING ---
# Persists and applies vm.overcommit_memory=1 for Redis stability.
# Redis warns when this is not enabled because background save/replication can fail under memory pressure.
function configure_redis_host_tuning() {
    section "REDIS HOST TUNING"

    if [ "$IS_CONTAINER" == "yes" ]; then
        msg_warn "Container mode detected. sysctl may be controlled by the host. Attempting safe configuration anyway."
    fi

    msg_info "Writing Redis overcommit sysctl config"

    write_root_file /etc/sysctl.d/99-redis-overcommit.conf <<'EOF'
# Redis background save/replication stability
# Managed by 5-dockerSetup.sh
vm.overcommit_memory=1
EOF

    msg_ok "REDIS SYSCTL CONFIG WRITTEN"

    msg_info "Applying vm.overcommit_memory=1 immediately"

    if [ -n "$SUDO_CMD" ]; then
        if "$SUDO_CMD" sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1; then
            REDIS_OVERCOMMIT_CONFIGURED="yes"
            msg_ok "REDIS OVERCOMMIT APPLIED"
        else
            REDIS_OVERCOMMIT_CONFIGURED="failed"
            msg_warn "Failed to apply vm.overcommit_memory immediately. It may apply after reboot."
        fi
    else
        if sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1; then
            REDIS_OVERCOMMIT_CONFIGURED="yes"
            msg_ok "REDIS OVERCOMMIT APPLIED"
        else
            REDIS_OVERCOMMIT_CONFIGURED="failed"
            msg_warn "Failed to apply vm.overcommit_memory immediately. It may apply after reboot."
        fi
    fi

    REDIS_OVERCOMMIT_VALUE="$(sysctl -n vm.overcommit_memory 2>/dev/null || echo unknown)"

    if [ "$REDIS_OVERCOMMIT_VALUE" == "1" ]; then
        REDIS_OVERCOMMIT_CONFIGURED="yes"
        msg_ok "REDIS HOST TUNING VERIFIED"
    else
        msg_warn "Redis overcommit value is ${REDIS_OVERCOMMIT_VALUE}; expected 1"
    fi
}

# --- 42. DOCKER-GC OPTIONAL INSTALL ---
# Creates a safe host-side Docker cleanup helper and optional weekly systemd timer.
# This intentionally avoids any Docker socket-proxy permission expansion and never prunes volumes.
function install_docker_gc_helper() {
    section "DOCKER CLEANUP HELPER"

    if [ "$INSTALL_DOCKER_GC" != "y" ]; then
        DOCKER_GC_INSTALLED="no"
        DOCKER_GC_TIMER_INSTALLED="no"
        msg_skip "DOCKER CLEANUP HELPER WAS NOT INSTALLED BECAUSE USER CHOSE NO"
        return 0
    fi

    msg_info "Writing safe Docker cleanup helper"

    write_root_file /usr/local/sbin/docker-gc-safe <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/docker-gc-safe.log"
LOCK_FILE="/run/docker-gc-safe.lock"

mkdir -p "$(dirname "$LOG_FILE")"

touch "$LOG_FILE"
chmod 0644 "$LOG_FILE" 2>/dev/null || true

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "[$(date -Is)] Another docker-gc-safe run is already active. Exiting." >> "$LOG_FILE"
    exit 0
fi

{
    echo "============================================================"
    echo "Docker safe cleanup started: $(date -Is)"
    echo "Hostname: $(hostname)"
    echo ""

    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: docker command not found."
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker daemon is not reachable."
        exit 1
    fi

    echo "Before cleanup:"
    docker system df || true
    echo ""

    echo "Pruning stopped containers only..."
    docker container prune -f || true
    echo ""

    echo "Pruning unused Docker networks..."
    docker network prune -f || true
    echo ""

    echo "Pruning dangling images..."
    docker image prune -f || true
    echo ""

    echo "Pruning unused images older than 7 days..."
    docker image prune -a -f --filter "until=168h" || true
    echo ""

    echo "Pruning old BuildKit/build cache older than 7 days..."
    docker builder prune -f --filter "until=168h" || true
    echo ""

    echo "IMPORTANT: Docker volumes are intentionally never pruned by this helper."
    echo ""

    echo "After cleanup:"
    docker system df || true
    echo ""
    echo "Docker safe cleanup finished: $(date -Is)"
    echo "============================================================"
    echo ""
} >> "$LOG_FILE" 2>&1
EOF

    msg_ok "DOCKER CLEANUP HELPER WRITTEN"

    msg_info "Making docker cleanup helper executable"
    run_cmd "making docker cleanup helper executable" chmod 0755 /usr/local/sbin/docker-gc-safe
    msg_ok "DOCKER CLEANUP HELPER MADE EXECUTABLE"

    DOCKER_GC_INSTALLED="yes"

    if command -v systemctl >/dev/null 2>&1; then
        msg_info "Writing docker-gc-safe systemd service"

        write_root_file /etc/systemd/system/docker-gc-safe.service <<'EOF'
[Unit]
Description=Safe Docker cleanup helper
Documentation=man:docker-system-prune(1)
Wants=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/docker-gc-safe
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

        msg_ok "DOCKER CLEANUP SERVICE WRITTEN"

        msg_info "Writing docker-gc-safe weekly timer"

        write_root_file /etc/systemd/system/docker-gc-safe.timer <<'EOF'
[Unit]
Description=Run safe Docker cleanup weekly

[Timer]
OnCalendar=Sun *-*-* 04:00:00
Persistent=true
RandomizedDelaySec=30m
Unit=docker-gc-safe.service

[Install]
WantedBy=timers.target
EOF

        msg_ok "DOCKER CLEANUP TIMER WRITTEN"

        msg_info "Enabling docker-gc-safe timer"
        run_cmd "reloading systemd for docker cleanup timer" systemctl daemon-reload
        run_cmd "enabling docker cleanup timer" systemctl enable --now docker-gc-safe.timer
        DOCKER_GC_TIMER_INSTALLED="yes"
        msg_ok "DOCKER CLEANUP TIMER ENABLED"
    else
        DOCKER_GC_TIMER_INSTALLED="no-systemctl"
        msg_warn "systemctl not available; cleanup helper installed without timer"
    fi

    msg_ok "SAFE DOCKER CLEANUP INSTALLED"
}

# =========================================================
#  VERIFICATION / MARKER / SUMMARY
# =========================================================

# --- 42. DOCKER VERIFICATION ---
# Checks Docker daemon, Docker CLI and Compose plugin through sudo so verification works before docker group re-login.
function verify_docker_installation() {
    section "VERIFICATION"

    msg_info "Checking Docker CLI"
    run_cmd "checking Docker CLI" docker --version
    msg_ok "DOCKER CLI VERIFIED"

    msg_info "Checking Docker daemon"
    run_cmd "checking Docker daemon" docker info
    msg_ok "DOCKER DAEMON VERIFIED"

    msg_info "Checking Docker Compose plugin"
    run_cmd "checking Docker Compose plugin" docker compose version
    msg_ok "DOCKER COMPOSE VERIFIED"

    msg_ok "DOCKER VERIFIED"
}

# --- 43. VERIFICATION REPORT ---
# Writes a detailed Docker verification report to /var/log/docker-setup-verify.log.
function create_verification_report() {
    section "VERIFICATION REPORT"

    msg_info "Writing Docker verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<EOF
--- DOCKER SETUP VERIFICATION REPORT ---
Date: $(date)
Target user: $TARGET_USER
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM

Results:
EOF
    else
        cat > "$VERIFY_LOG" <<EOF
--- DOCKER SETUP VERIFICATION REPORT ---
Date: $(date)
Target user: $TARGET_USER
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM

Results:
EOF
    fi

    {
        if command -v docker >/dev/null 2>&1; then echo "✓ PASS - Docker CLI exists"; else echo "✗ FAIL - Docker CLI missing"; fi
        if docker --version >/dev/null 2>&1 || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker --version >/dev/null 2>&1; }; then echo "✓ PASS - docker --version works"; else echo "✗ FAIL - docker --version failed"; fi
        if docker compose version >/dev/null 2>&1 || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker compose version >/dev/null 2>&1; }; then echo "✓ PASS - Docker Compose plugin works"; else echo "✗ FAIL - Docker Compose plugin failed"; fi
        if docker info >/dev/null 2>&1 || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker info >/dev/null 2>&1; }; then echo "✓ PASS - Docker daemon reachable"; else echo "✗ FAIL - Docker daemon not reachable"; fi

        if command -v systemctl >/dev/null 2>&1; then
            if systemctl is-active --quiet docker 2>/dev/null; then echo "✓ PASS - Docker service active"; else echo "! WARN - Docker service not active or unavailable"; fi
            if systemctl is-active --quiet containerd 2>/dev/null; then echo "✓ PASS - containerd service active"; else echo "! WARN - containerd service not active or unavailable"; fi
        else
            echo "! INFO - systemctl unavailable"
        fi

        if [ -f /etc/docker/daemon.json ]; then echo "✓ PASS - daemon.json exists"; else echo "✗ FAIL - daemon.json missing"; fi
        if validate_docker_daemon_json; then echo "✓ PASS - daemon.json valid"; else echo "✗ FAIL - daemon.json validation failed"; fi

        if [ -f /etc/sysctl.d/99-redis-overcommit.conf ]; then echo "✓ PASS - Redis overcommit sysctl file exists"; else echo "✗ FAIL - Redis overcommit sysctl file missing"; fi
        if [ "$(sysctl -n vm.overcommit_memory 2>/dev/null || echo unknown)" = "1" ]; then echo "✓ PASS - vm.overcommit_memory=1 active"; else echo "! WARN - vm.overcommit_memory is not 1"; fi

        if [ -x /usr/local/sbin/docker-gc-safe ]; then echo "✓ PASS - docker-gc-safe helper exists"; else echo "! INFO - docker-gc-safe helper not installed"; fi
        if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files docker-gc-safe.timer >/dev/null 2>&1; then echo "✓ PASS - docker-gc-safe.timer exists"; else echo "! INFO - docker-gc-safe.timer not installed"; fi

        if getent group docker >/dev/null 2>&1; then echo "✓ PASS - docker group exists"; else echo "✗ FAIL - docker group missing"; fi
        if id -nG "$TARGET_USER" 2>/dev/null | grep -qw docker; then echo "✓ PASS - target user is in docker group"; else echo "! WARN - target user docker group membership not confirmed"; fi

        if [ "$DISABLE_SWAP" == "y" ]; then
            if swapon --show 2>/dev/null | grep -q .; then echo "! WARN - active swap still detected"; else echo "✓ PASS - no active swap detected"; fi
        else
            echo "! INFO - swap disable not selected"
        fi

        if [ "$CONFIGURE_UFW" == "y" ]; then
            if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "Status: active"; then echo "✓ PASS - UFW active"; else echo "! WARN - UFW not active or not available"; fi
        else
            echo "! INFO - UFW setup not selected"
        fi

        if [ -f "$COMPLETED_MARKER" ]; then echo "✓ PASS - completion marker exists"; else echo "! WARN - completion marker not present yet at verification time"; fi

        echo ""
        echo "Docker versions:"
        docker --version 2>/dev/null || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker --version 2>/dev/null; } || true
        docker compose version 2>/dev/null || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker compose version 2>/dev/null; } || true
    } | if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee -a "$VERIFY_LOG" >/dev/null; else tee -a "$VERIFY_LOG" >/dev/null; fi

    msg_ok "DOCKER VERIFICATION REPORT WRITTEN"
}

# --- 44. COMPLETION MARKER ---
# Creates marker showing setup completed.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<EOF
Docker Setup completed on: $(date)
Target user: $TARGET_USER
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM
Swap disabled selected: $DISABLE_SWAP
Swap disabled result: $SWAP_DISABLED
Docker installed: $DOCKER_INSTALLED
Docker service enabled: $DOCKER_SERVICE_ENABLED
containerd service enabled: $CONTAINERD_SERVICE_ENABLED
Docker group ready: $DOCKER_GROUP_READY
User added to docker group: $USER_ADDED_TO_DOCKER
Docker GC helper: $DOCKER_GC_INSTALLED
Docker GC timer: $DOCKER_GC_TIMER_INSTALLED
Redis overcommit configured: $REDIS_OVERCOMMIT_CONFIGURED
Redis overcommit value: $REDIS_OVERCOMMIT_VALUE
Docker firewall mode: $DOCKER_FIREWALL_MODE
UFW configured selected: $CONFIGURE_UFW
UFW result: $UFW_ENABLED
Daemon config valid: $DAEMON_CONFIG_VALID
Existing setup detected: $EXISTING_SETUP
Verify log: $VERIFY_LOG
EOF
    else
        cat > "$COMPLETED_MARKER" <<EOF
Docker Setup completed on: $(date)
Target user: $TARGET_USER
Virt Type: $VIRT_TYPE
Container: $IS_CONTAINER
LXC: $IS_LXC
VM: $IS_VM
Swap disabled selected: $DISABLE_SWAP
Swap disabled result: $SWAP_DISABLED
Docker installed: $DOCKER_INSTALLED
Docker service enabled: $DOCKER_SERVICE_ENABLED
containerd service enabled: $CONTAINERD_SERVICE_ENABLED
Docker group ready: $DOCKER_GROUP_READY
User added to docker group: $USER_ADDED_TO_DOCKER
Docker GC helper: $DOCKER_GC_INSTALLED
Docker GC timer: $DOCKER_GC_TIMER_INSTALLED
Redis overcommit configured: $REDIS_OVERCOMMIT_CONFIGURED
Redis overcommit value: $REDIS_OVERCOMMIT_VALUE
Docker firewall mode: $DOCKER_FIREWALL_MODE
UFW configured selected: $CONFIGURE_UFW
UFW result: $UFW_ENABLED
Daemon config valid: $DAEMON_CONFIG_VALID
Existing setup detected: $EXISTING_SETUP
Verify log: $VERIFY_LOG
EOF
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 45. FINAL SUMMARY ---
# Displays installed versions and next step using script 1-style output.
function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" docker --version || true
        "$SUDO_CMD" docker compose version || true
    else
        docker --version || true
        docker compose version || true
    fi

    echo ""
    detail_line "TARGET USER" "$TARGET_USER"

    if [ "$IS_CONTAINER" == "yes" ]; then
        detail_line "ENVIRONMENT" "LXC/Container (${VIRT_TYPE})"
    else
        detail_line "ENVIRONMENT" "VM (${VIRT_TYPE})"
    fi

    detail_line "SWAP DISABLED" "$SWAP_DISABLED"
    detail_line "DOCKER INSTALLED" "$DOCKER_INSTALLED"
    detail_line "DOCKER SERVICE" "$DOCKER_SERVICE_ENABLED"
    detail_line "CONTAINERD SERVICE" "$CONTAINERD_SERVICE_ENABLED"
    detail_line "DOCKER GROUP READY" "$DOCKER_GROUP_READY"
    detail_line "USER ADDED TO DOCKER" "$USER_ADDED_TO_DOCKER"
    detail_line "DOCKER-GC HELPER" "$DOCKER_GC_INSTALLED"
    detail_line "DOCKER-GC TIMER" "$DOCKER_GC_TIMER_INSTALLED"
    detail_line "REDIS OVERCOMMIT" "${REDIS_OVERCOMMIT_CONFIGURED} (${REDIS_OVERCOMMIT_VALUE})"
    detail_line "UFW FIREWALL" "$UFW_ENABLED"
    detail_line "DAEMON CONFIG VALID" "$DAEMON_CONFIG_VALID"
    detail_line "EXISTING SETUP DETECTED" "$EXISTING_SETUP"
    detail_line "VERIFY LOG" "$VERIFY_LOG"

    echo ""
    echo -e "${YW}Docker group membership usually requires logout/login or reboot before using Docker without sudo.${CL}"
    echo ""
    echo -e "${BL}SECURITY NOTE:${CL}"
    echo -e "${YW}Docker can publish container ports using Docker-managed firewall rules. Keep public exposure limited to Traefik/80/443 unless intentionally needed.${CL}"
    echo -e "${YW}We will revisit DOCKER-USER firewall hardening after the compose stack is fully deployed and stable.
${YW}Safe Docker cleanup uses host-side /usr/local/sbin/docker-gc-safe and never prunes volumes automatically.${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}After reboot and SSH reconnect, run script 6-dockerENVsetup-crea.sh.${CL}"
    echo ""
}

# --- 46. REBOOT OPTION ---
# Uses the same single-countdown reboot flow as script 1/script 4.
# ENTER/Y = reboot now. SPACE/N = cancel. Timeout = reboot automatically.
function reboot_prompt() {
    section "REBOOT"

    if [ "$REBOOT_AFTER_FINISH" != "y" ]; then
        echo -e "${YW}Reboot was disabled during question collection. Reboot manually when ready.${CL}"
        return 0
    fi

    if [ "$IS_CONTAINER" == "yes" ]; then
        echo -e "${YW}Container mode detected. Restart may be controlled from the Proxmox host.${CL}"
        echo -e "${YW}Reboot skipped. Log out/in or restart the container from Proxmox if needed.${CL}"
        return 0
    fi

    echo -e "${YW}Docker group membership usually requires logout/login or reboot before using Docker without sudo.${CL}"
    echo ""

    if timed_reboot_countdown "$REBOOT_T"; then
        if [ -n "$SUDO_CMD" ]; then
            "$SUDO_CMD" reboot
        else
            reboot
        fi
    fi

    return 0
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 47. MAIN FUNCTION ---
# Runs the full setup in validation -> option collection -> install -> verify order.
function main() {
    init_script

    detect_environment
    check_previous_marker
    detect_existing_setup
    start_confirmation
    collect_user_options
    show_ready_to_apply

    handle_swap
    configure_redis_host_tuning
    install_repository_dependencies
    configure_docker_repository
    install_docker_engine
    configure_docker_group
    configure_docker_daemon
    configure_ufw_firewall
    install_docker_gc_helper

    verify_docker_installation
    write_completion_marker
    create_verification_report
    show_final_summary
    reboot_prompt

    exit 0
}

main "$@"
