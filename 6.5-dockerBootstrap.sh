#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker Bootstrap Setup
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Central visual theme aligned with Script 1 / Script 4 / Script 5 / Script 6.
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
# Stores timers, paths, GitHub source, Docker state and final bootstrap results.
T=15

LOG_FILE="/var/log/docker-bootstrap-setup.log"
RUNTIME_LOG_FILE=""
VERIFY_LOG="/var/log/docker-bootstrap-setup-verify.log"
COMPLETED_MARKER="/root/.docker-bootstrap-setup-completed"

DEFAULT_DOCKER_USER="${SUDO_USER:-orik}"
DOCKER_USER="${DOCKER_USER:-$DEFAULT_DOCKER_USER}"
DOCKER_DIR="${DOCKER_DIR:-/home/${DOCKER_USER}/docker}"
COMPOSE_DIR="${COMPOSE_DIR:-${DOCKER_DIR}/compose}"
ENV_FILE="${ENV_FILE:-${DOCKER_DIR}/.env}"

GITHUB_RAW_BASE="${GITHUB_RAW_BASE:-https://raw.githubusercontent.com/Orik999/mySetup/main/docker}"
YML_00_NAME="00-socket-proxy-compose.yml"
YML_01_NAME="01-portainer-compose.yml"
YML_01_OVERRIDE_NAME="01-portainer-bootstrap-override.yml"

# Optional environment overrides for advanced/testing workflows.
# If these are not set, URLs are rebuilt from GITHUB_RAW_BASE after user input.
YML_00_URL_OVERRIDE="${YML_00_URL:-}"
YML_01_URL_OVERRIDE="${YML_01_URL:-}"
YML_01_OVERRIDE_URL_OVERRIDE="${YML_01_OVERRIDE_URL:-}"
YML_00_URL="${YML_00_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_00_NAME}}"
YML_01_URL="${YML_01_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_01_NAME}}"
YML_01_OVERRIDE_URL="${YML_01_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_01_OVERRIDE_NAME}}"

SOCKET_PROXY_SUBNET_EXPECTED="192.168.91.0/24"
T2_PROXY_SUBNET_EXPECTED="192.168.90.0/24"
SOCKET_PROXY_SUBNET_ACTUAL=""
T2_PROXY_SUBNET_ACTUAL=""
DATABASE_NETWORK_NAME=""

PORTAINER_BOOTSTRAP_PORT="${PORTAINER_BOOTSTRAP_PORT:-9443}"
PORTAINER_BOOTSTRAP_BIND="${PORTAINER_BOOTSTRAP_BIND:-0.0.0.0}"
PORTAINER_OVERRIDE_FILE="${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"
PORTAINER_ACCESS_IP=""
PORTAINER_ACCESS_URL=""

SUDO_CMD=""
DOCKER_NEEDS_SUDO="no"
TEMP_FILES=()

NETWORKS_CREATED="no"
NETWORKS_VERIFIED="no"
YML_00_DOWNLOADED="no"
YML_01_DOWNLOADED="no"
YML_01_OVERRIDE_DOWNLOADED="no"
SOCKET_PROXY_DEPLOYED="no"
PORTAINER_DEPLOYED="no"
PORTAINER_BOOTSTRAP_OVERRIDE_WRITTEN="no"
PORTAINER_BOOTSTRAP_PORT_EXPOSED="no"
UFW_BOOTSTRAP_PORT_OPENED="no"

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
# Displays the Docker Bootstrap banner.
function header_info() {
echo -e "${BL}
██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗     ██████╗  ██████╗  ██████╗ ████████╗███████╗████████╗██████╗  █████╗ ██████╗ 
██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗    ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗
██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝    ██████╔╝██║   ██║██║   ██║   ██║   ███████╗   ██║   ██████╔╝███████║██████╔╝
██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗    ██╔══██╗██║   ██║██║   ██║   ██║   ╚════██║   ██║   ██╔══██╗██╔══██║██╔═══╝ 
██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║    ██████╔╝╚██████╔╝╚██████╔╝   ██║   ███████║   ██║   ██║  ██║██║  ██║██║     
╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚═════╝  ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     
${CL}"
}

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent display -> apply -> success output style.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_skip() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. SECTION HEADER HELPER ---
# Keeps terminal output clean and grouped by stage.
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

# --- 6. FLASHING SUCCESS SECTION HEADER HELPER ---
# Uses the same section layout as source-of-truth scripts, but renders final success heading in bold flashing green.
function section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

# --- 7. DETAIL LINE HELPER ---
# Prints clean script 1-style detail lines for summaries and audit output.
function detail_line() {
    local label="$1"
    local value="$2"
    echo -e " ${BL}━━━━━▶${CL} ${label}: ${GN}${value}${CL}"
}

# --- 8. TTY PRINT HELPER ---
# Prints directly to terminal even when functions return values through stdout.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 9. TTY PRINTLN HELPER ---
# Prints directly to terminal with newline.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 10. INPUT BUFFER FLUSH HELPER ---
# Clears only a small bounded amount of already-buffered terminal input.
# Important: never reads from stdin because streamed scripts use stdin for the script body.
function flush_input_buffer() {
    local junk=""
    local i=""

    if [ ! -r /dev/tty ]; then
        return 0
    fi

    for i in {1..20}; do
        if ! IFS= read -rsn1 -t 0.02 junk < /dev/tty; then
            break
        fi
    done

    return 0
}

# =========================================================
#  CLEANUP / ERROR HANDLING
# =========================================================

# --- 11. CLEANUP FUNCTION ---
# Removes temporary files and copies runtime log to /var/log when running non-root.
function cleanup() {
    local exit_code="$?"
    local file=""

    if [ -n "${SUDO_CMD:-}" ] && [ -n "${RUNTIME_LOG_FILE:-}" ] && [ -s "$RUNTIME_LOG_FILE" ]; then
        "$SUDO_CMD" cp "$RUNTIME_LOG_FILE" "$LOG_FILE" 2>/dev/null || true
        "$SUDO_CMD" chmod 0644 "$LOG_FILE" 2>/dev/null || true
    fi

    for file in "${TEMP_FILES[@]:-}"; do
        [ -n "$file" ] && [ -f "$file" ] && rm -f "$file" 2>/dev/null || true
    done

    exit "$exit_code"
}

# --- 12. ERROR TRAP HELPER ---
# Shows the failing line number and points to the log file.
function on_error() {
    local line_no="$1"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"
}

# --- 13. COMMAND RUNNER ---
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

# --- 14. ROOT PATH EXISTS HELPER ---
# Checks whether a root-owned path exists.
function root_path_exists() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -e "$path"
    else
        test -e "$path"
    fi
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 15. YES/NO LABEL HELPER ---
# Converts Y/N answers to readable yes/no output.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 16. BLOCKING YES/NO HELPER ---
# SPACE pauses countdown and waits for Y/N/ENTER.
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

# --- 17. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown. SPACE pauses, timeout accepts default, final answer stays visible.
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

# --- 18. EDITABLE INPUT LOOP HELPER ---
# Shared editable input system for text prompts.
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

# --- 19. TIMED TEXT INPUT HELPER ---
# Shows wall-clock countdown. SPACE pauses with empty editable buffer.
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""
    local key=""
    local deadline=""
    local now=""
    local remaining=""

    flush_input_buffer
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
    flush_input_buffer

    echo "$answer"
}

# =========================================================
#  VALIDATION HELPERS
# =========================================================

# --- 20. USERNAME VALIDATION HELPER ---
# Validates Linux username format.
function validate_linux_username() {
    local username="$1"

    if [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 0
    fi

    return 1
}

# --- 21. URL VALIDATION HELPER ---
# Validates HTTP(S) URLs used for GitHub raw downloads.
function validate_url() {
    local url="$1"

    if [[ "$url" =~ ^https?://[^[:space:]]+$ ]]; then
        return 0
    fi

    return 1
}

# --- 22. DEPENDENCY VALIDATION ---
# Validates base commands before system changes.
function validate_dependencies() {
    local required_commands=(
        awk
        cat
        chmod
        cp
        curl
        date
        docker
        grep
        head
        hostname
        id
        ip
        mkdir
        mktemp
        rm
        sed
        tee
        tput
        xargs
    )

    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done

    if [ -n "$SUDO_CMD" ]; then
        command -v sudo >/dev/null 2>&1 || msg_error "sudo is required when not running as root."
    fi

    if ! docker compose version >/dev/null 2>&1 && ! { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker compose version >/dev/null 2>&1; }; then
        msg_error "Docker Compose plugin not available. Run script 5 first."
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
# Validates sudo once near the start. Supports passwordless sudo from earlier scripts.
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
# Avoids piping interactive prompts through sudo tee. Runtime log is copied to /var/log during cleanup.
function init_logging() {
    if [ -n "$SUDO_CMD" ]; then
        RUNTIME_LOG_FILE="$(mktemp /tmp/docker-bootstrap-setup-log.XXXXXX)"
        TEMP_FILES+=("$RUNTIME_LOG_FILE")
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        RUNTIME_LOG_FILE="$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

# --- 26. SCRIPT INITIALIZATION ---
# Detects sudo, validates access, starts logging, installs traps, shows banner and validates dependencies.
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

# --- 27. DOCKER ACCESS DETECTION ---
# Prefers normal docker group access, falls back to sudo docker if needed.
function detect_docker_access() {
    section "DOCKER ACCESS CHECK"

    msg_info "Checking Docker access"

    if docker ps >/dev/null 2>&1; then
        DOCKER_NEEDS_SUDO="no"
        msg_ok "DOCKER ACCESS CONFIRMED"
        detail_line "Docker mode" "current user"
        return 0
    fi

    if [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker ps >/dev/null 2>&1; then
        DOCKER_NEEDS_SUDO="yes"
        msg_ok "DOCKER ACCESS CONFIRMED WITH SUDO"
        detail_line "Docker mode" "sudo fallback"
        msg_warn "Current shell cannot use Docker without sudo. Reboot/logout may still be needed after script 5."
        return 0
    fi

    msg_error "Docker daemon is not reachable. Run script 5 first and reboot/log back in."
}

# =========================================================
#  DOCKER WRAPPERS
# =========================================================

# --- 28. DOCKER COMMAND WRAPPER ---
# Runs docker through current user or sudo fallback depending on detected access.
function docker_cmd() {
    if [ "$DOCKER_NEEDS_SUDO" == "yes" ]; then
        "$SUDO_CMD" docker "$@"
    else
        docker "$@"
    fi
}

# --- 29. DOCKER COMMAND RUNNER ---
# Runs docker commands quietly, with real stderr on failure.
function run_docker_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    if ! docker_cmd "$@" > /dev/null 2> "$err_file"; then
        echo ""
        echo -e "${RD}Docker command failed during:${CL} ${description}"
        echo -e "${YW}Command:${CL} docker $*"
        echo ""
        echo -e "${RD}Real error:${CL}"
        cat "$err_file"
        rm -f "$err_file"
        exit 1
    fi

    rm -f "$err_file"
}

# =========================================================
#  INPUT / PRECHECKS
# =========================================================

# --- 30. PREVIOUS MARKER CHECK ---
# Warns if Docker Bootstrap was already completed before.
function check_previous_marker() {
    local continue_yn=""

    if root_path_exists "$COMPLETED_MARKER"; then
        section "PREVIOUS DOCKER BOOTSTRAP MARKER DETECTED"

        echo -e "${YW}A previous Docker Bootstrap marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        if [ -n "$SUDO_CMD" ]; then
            "$SUDO_CMD" cat "$COMPLETED_MARKER" 2>/dev/null || true
        else
            cat "$COMPLETED_MARKER" 2>/dev/null || true
        fi
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi

    return 0
}

# --- 31. START CONFIRMATION ---
# Starts Docker network and Portainer bootstrap after showing a clear description.
function start_confirmation() {
    local start_yn=""

    section "START"

    echo -e "${YW}This script creates shared Docker networks, downloads yml 00/yml 01 plus the Portainer bootstrap override, and deploys socket-proxy + Portainer.${CL}"
    echo -e "${YW}Portainer will be temporarily exposed on direct port ${PORTAINER_BOOTSTRAP_PORT} for bootstrap access.${CL}"
    echo -e "${YW}Script 7 should later remove the temporary Portainer port and leave Traefik/AuthentiK access only.${CL}"
    echo ""

    start_yn="$(timed_yes_no "Start Docker Bootstrap Setup?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    return 0
}

# --- 32. BOOTSTRAP SETTINGS COLLECTION ---
# Lets user confirm Docker user/path/source while defaulting to the established project layout.
function collect_bootstrap_settings() {
    section "BOOTSTRAP SETTINGS"

    while true; do
        DOCKER_USER="$(timed_text_input "Enter Docker Linux user" "$DOCKER_USER")"

        if validate_linux_username "$DOCKER_USER"; then
            break
        fi

        msg_warn "Invalid username. Use lowercase Linux username format, for example: orik"
    done

    if ! id "$DOCKER_USER" >/dev/null 2>&1; then
        msg_error "Linux user ${DOCKER_USER} does not exist. Run script 4 first or create the user."
    fi

    DOCKER_DIR="$(timed_text_input "Enter Docker directory" "$DOCKER_DIR")"
    COMPOSE_DIR="$(timed_text_input "Enter Docker compose directory" "$COMPOSE_DIR")"
    ENV_FILE="$(timed_text_input "Enter Docker .env path" "$ENV_FILE")"
    GITHUB_RAW_BASE="$(timed_text_input "Enter GitHub raw compose base" "$GITHUB_RAW_BASE")"

    if ! validate_url "$GITHUB_RAW_BASE"; then
        msg_error "GitHub raw base is not a valid HTTP/HTTPS URL."
    fi

    if [ -z "$YML_00_URL_OVERRIDE" ]; then
        YML_00_URL="${GITHUB_RAW_BASE}/${YML_00_NAME}"
    fi

    if [ -z "$YML_01_URL_OVERRIDE" ]; then
        YML_01_URL="${GITHUB_RAW_BASE}/${YML_01_NAME}"
    fi

    if [ -z "$YML_01_OVERRIDE_URL_OVERRIDE" ]; then
        YML_01_OVERRIDE_URL="${GITHUB_RAW_BASE}/${YML_01_OVERRIDE_NAME}"
    fi

    PORTAINER_OVERRIDE_FILE="${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"

    detail_line "Docker user" "$DOCKER_USER"
    detail_line "Docker dir" "$DOCKER_DIR"
    detail_line "Compose dir" "$COMPOSE_DIR"
    detail_line "Env file" "$ENV_FILE"
    detail_line "GitHub raw base" "$GITHUB_RAW_BASE"
    detail_line "Portainer override" "$YML_01_OVERRIDE_NAME"
}

# --- 33. PATH PRECHECKS ---
# Validates Docker ENV output and compose directory before network/deploy work.
function validate_project_paths() {
    section "PROJECT PATH CHECK"

    msg_info "Validating Docker project paths"

    if ! root_path_exists "$DOCKER_DIR"; then
        msg_error "Docker directory not found: ${DOCKER_DIR}. Run script 6 first."
    fi

    if ! root_path_exists "$ENV_FILE"; then
        msg_error "Docker .env file not found: ${ENV_FILE}. Run script 6 first."
    fi

    run_cmd "creating compose directory" mkdir -p "$COMPOSE_DIR"
    run_cmd "setting compose directory ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "$COMPOSE_DIR"

    msg_ok "PROJECT PATHS READY"

    detail_line "Docker dir" "$DOCKER_DIR"
    detail_line "Compose dir" "$COMPOSE_DIR"
    detail_line ".env" "$ENV_FILE"
}

# =========================================================
#  NETWORK BOOTSTRAP
# =========================================================

# --- 34. NETWORK CREATION ---
# Creates the shared external networks used by all independent compose stacks.
function create_shared_networks() {
    section "DOCKER NETWORKS"

    msg_info "Creating socket_proxy network"
    docker_cmd network create --driver bridge --subnet "$SOCKET_PROXY_SUBNET_EXPECTED" socket_proxy >/dev/null 2>&1 || true
    msg_ok "SOCKET_PROXY NETWORK READY"

    msg_info "Creating t2_proxy network"
    docker_cmd network create --driver bridge --subnet "$T2_PROXY_SUBNET_EXPECTED" t2_proxy >/dev/null 2>&1 || true
    msg_ok "T2_PROXY NETWORK READY"

    msg_info "Creating database network"
    docker_cmd network create --driver bridge database >/dev/null 2>&1 || true
    msg_ok "DATABASE NETWORK READY"

    NETWORKS_CREATED="yes"
}

# --- 35. NETWORK VERIFICATION ---
# Verifies network existence and expected subnets before compose deployment.
function verify_shared_networks() {
    section "NETWORK VERIFICATION"

    msg_info "Inspecting Docker networks"

    SOCKET_PROXY_SUBNET_ACTUAL="$(docker_cmd network inspect socket_proxy --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
    T2_PROXY_SUBNET_ACTUAL="$(docker_cmd network inspect t2_proxy --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
    DATABASE_NETWORK_NAME="$(docker_cmd network inspect database --format '{{.Name}}' 2>/dev/null || true)"

    if [ "$SOCKET_PROXY_SUBNET_ACTUAL" != "$SOCKET_PROXY_SUBNET_EXPECTED" ]; then
        msg_error "socket_proxy subnet mismatch: expected ${SOCKET_PROXY_SUBNET_EXPECTED}, got ${SOCKET_PROXY_SUBNET_ACTUAL:-missing}"
    fi

    if [ "$T2_PROXY_SUBNET_ACTUAL" != "$T2_PROXY_SUBNET_EXPECTED" ]; then
        msg_error "t2_proxy subnet mismatch: expected ${T2_PROXY_SUBNET_EXPECTED}, got ${T2_PROXY_SUBNET_ACTUAL:-missing}"
    fi

    if [ "$DATABASE_NETWORK_NAME" != "database" ]; then
        msg_error "database network missing or invalid."
    fi

    NETWORKS_VERIFIED="yes"

    msg_ok "DOCKER NETWORKS VERIFIED"
    detail_line "socket_proxy" "$SOCKET_PROXY_SUBNET_ACTUAL"
    detail_line "t2_proxy" "$T2_PROXY_SUBNET_ACTUAL"
    detail_line "database" "$DATABASE_NETWORK_NAME"
}

# =========================================================
#  COMPOSE DOWNLOAD / DEPLOY
# =========================================================

# --- 36. COMPOSE FILE DOWNLOAD ---
# Downloads yml 00, yml 01 and the Portainer bootstrap override from GitHub into docker/compose.
function download_bootstrap_compose_files() {
    section "COMPOSE DOWNLOAD"

    msg_info "Downloading ${YML_00_NAME}"
    curl -fsSL "$YML_00_URL" -o "${COMPOSE_DIR}/${YML_00_NAME}"
    YML_00_DOWNLOADED="yes"
    msg_ok "YML 00 DOWNLOADED"

    msg_info "Downloading ${YML_01_NAME}"
    curl -fsSL "$YML_01_URL" -o "${COMPOSE_DIR}/${YML_01_NAME}"
    YML_01_DOWNLOADED="yes"
    msg_ok "YML 01 DOWNLOADED"

    msg_info "Downloading ${YML_01_OVERRIDE_NAME}"
    curl -fsSL "$YML_01_OVERRIDE_URL" -o "${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"
    YML_01_OVERRIDE_DOWNLOADED="yes"
    PORTAINER_BOOTSTRAP_OVERRIDE_WRITTEN="downloaded"
    msg_ok "PORTAINER BOOTSTRAP OVERRIDE DOWNLOADED"

    run_cmd "setting compose file ownership" chown "${DOCKER_USER}:${DOCKER_USER}"         "${COMPOSE_DIR}/${YML_00_NAME}"         "${COMPOSE_DIR}/${YML_01_NAME}"         "${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"

    run_cmd "setting compose file permissions" chmod 640         "${COMPOSE_DIR}/${YML_00_NAME}"         "${COMPOSE_DIR}/${YML_01_NAME}"         "${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"

    detail_line "YML 00" "${COMPOSE_DIR}/${YML_00_NAME}"
    detail_line "YML 01" "${COMPOSE_DIR}/${YML_01_NAME}"
    detail_line "YML 01 override" "${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"
}

# --- 37. PORTAINER BOOTSTRAP OVERRIDE CHECK ---
# Confirms the downloaded Portainer bootstrap override exists locally.
# Script 7 should later redeploy Portainer without this override to close the bootstrap port.
function verify_portainer_bootstrap_override_file() {
    section "PORTAINER BOOTSTRAP OVERRIDE"

    msg_info "Checking downloaded Portainer bootstrap override"

    if [ ! -f "$PORTAINER_OVERRIDE_FILE" ]; then
        msg_error "Portainer bootstrap override was not downloaded: ${PORTAINER_OVERRIDE_FILE}"
    fi

    PORTAINER_BOOTSTRAP_OVERRIDE_WRITTEN="downloaded"

    msg_ok "PORTAINER BOOTSTRAP OVERRIDE READY"
    detail_line "Override file" "$PORTAINER_OVERRIDE_FILE"
    detail_line "Bootstrap port" "${PORTAINER_BOOTSTRAP_PORT}->9443"
}

# --- 38. COMPOSE CONFIG VALIDATION ---
# Validates yml 00, yml 01 and the Portainer bootstrap override before deployment.
function validate_bootstrap_compose_files() {
    section "COMPOSE VALIDATION"

    msg_info "Validating socket-proxy compose"
    run_docker_cmd "validating socket-proxy compose" compose --env-file "$ENV_FILE" -p socket-proxy -f "${COMPOSE_DIR}/${YML_00_NAME}" config -q
    msg_ok "YML 00 COMPOSE VALID"

    export PORTAINER_BOOTSTRAP_BIND PORTAINER_BOOTSTRAP_PORT

    msg_info "Validating Portainer compose"
    run_docker_cmd "validating Portainer compose" compose --env-file "$ENV_FILE" -p portainer -f "${COMPOSE_DIR}/${YML_01_NAME}" -f "$PORTAINER_OVERRIDE_FILE" config -q
    msg_ok "YML 01 COMPOSE VALID"
}

# --- 39. SOCKET-PROXY DEPLOYMENT ---
# Deploys yml 00 using Docker CLI.
function deploy_socket_proxy() {
    section "DEPLOY YML 00 - SOCKET PROXY"

    msg_info "Deploying socket-proxy"
    run_docker_cmd "deploying socket-proxy" compose --env-file "$ENV_FILE" -p socket-proxy -f "${COMPOSE_DIR}/${YML_00_NAME}" up -d
    SOCKET_PROXY_DEPLOYED="yes"
    msg_ok "SOCKET-PROXY DEPLOYED"
}

# --- 40. PORTAINER DEPLOYMENT ---
# Deploys yml 01 using Docker CLI with temporary bootstrap port override.
function deploy_portainer() {
    section "DEPLOY YML 01 - PORTAINER"

    export PORTAINER_BOOTSTRAP_BIND PORTAINER_BOOTSTRAP_PORT

    msg_info "Deploying Portainer with bootstrap port"
    run_docker_cmd "deploying Portainer" compose --env-file "$ENV_FILE" -p portainer -f "${COMPOSE_DIR}/${YML_01_NAME}" -f "$PORTAINER_OVERRIDE_FILE" up -d
    PORTAINER_DEPLOYED="yes"
    msg_ok "PORTAINER DEPLOYED"
}

# --- 41. UFW BOOTSTRAP PORT HELPER ---
# Opens temporary Portainer bootstrap port if UFW is active.
function configure_bootstrap_firewall() {
    section "BOOTSTRAP FIREWALL"

    if ! command -v ufw >/dev/null 2>&1; then
        msg_skip "UFW NOT FOUND; BOOTSTRAP PORT RULE SKIPPED"
        UFW_BOOTSTRAP_PORT_OPENED="not-found"
        return 0
    fi

    if ! ufw status 2>/dev/null | grep -qi "Status: active" && ! { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" ufw status 2>/dev/null | grep -qi "Status: active"; }; then
        msg_skip "UFW NOT ACTIVE; BOOTSTRAP PORT RULE SKIPPED"
        UFW_BOOTSTRAP_PORT_OPENED="not-active"
        return 0
    fi

    msg_info "Allowing temporary Portainer bootstrap port ${PORTAINER_BOOTSTRAP_PORT}/tcp"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" ufw allow "${PORTAINER_BOOTSTRAP_PORT}/tcp" comment "temporary Portainer bootstrap" >/dev/null 2>&1 || true
    else
        ufw allow "${PORTAINER_BOOTSTRAP_PORT}/tcp" comment "temporary Portainer bootstrap" >/dev/null 2>&1 || true
    fi

    UFW_BOOTSTRAP_PORT_OPENED="yes"
    msg_ok "TEMPORARY PORTAINER PORT ALLOWED"
}

# =========================================================
#  VERIFICATION / SUMMARY
# =========================================================

# --- 42. ACCESS IP DETECTION ---
# Detects a likely LAN IPv4 for the Portainer bootstrap URL.
function detect_portainer_access_ip() {
    local detected_ip=""

    detected_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"

    if [ -z "$detected_ip" ]; then
        detected_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    fi

    PORTAINER_ACCESS_IP="${detected_ip:-127.0.0.1}"
    PORTAINER_ACCESS_URL="https://${PORTAINER_ACCESS_IP}:${PORTAINER_BOOTSTRAP_PORT}"
}

# --- 43. CONTAINER VERIFICATION ---
# Verifies the bootstrap containers are running and visible.
function verify_bootstrap_containers() {
    section "BOOTSTRAP VERIFICATION"

    msg_info "Checking socket-proxy container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'socket-proxy'; then
        msg_ok "SOCKET-PROXY RUNNING"
    else
        msg_error "socket-proxy container is not running."
    fi

    msg_info "Checking Portainer container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'portainer'; then
        msg_ok "PORTAINER RUNNING"
    else
        msg_error "portainer container is not running."
    fi

    detect_portainer_access_ip

    msg_info "Checking Portainer bootstrap port"
    if docker_cmd port portainer 9443/tcp 2>/dev/null | grep -q ":${PORTAINER_BOOTSTRAP_PORT}$"; then
        PORTAINER_BOOTSTRAP_PORT_EXPOSED="yes"
        msg_ok "PORTAINER BOOTSTRAP PORT EXPOSED"
    else
        PORTAINER_BOOTSTRAP_PORT_EXPOSED="not-confirmed"
        msg_warn "Portainer is running, but bootstrap port ${PORTAINER_BOOTSTRAP_PORT} was not confirmed"
    fi

    detail_line "Portainer URL" "$PORTAINER_ACCESS_URL"
    detail_line "Bootstrap port" "$PORTAINER_BOOTSTRAP_PORT"
}

# --- 44. VERIFICATION REPORT ---
# Writes a small Docker bootstrap verification report to /var/log.
function create_verification_report() {
    section "VERIFICATION REPORT"

    msg_info "Writing Docker bootstrap verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<VERIFY_LOG_EOF
--- DOCKER BOOTSTRAP SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Env file: $ENV_FILE
GitHub raw base: $GITHUB_RAW_BASE

Results:
VERIFY_LOG_EOF
    else
        cat > "$VERIFY_LOG" <<VERIFY_LOG_EOF
--- DOCKER BOOTSTRAP SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Env file: $ENV_FILE
GitHub raw base: $GITHUB_RAW_BASE

Results:
VERIFY_LOG_EOF
    fi

    {
        echo "Networks:"
        echo "socket_proxy=${SOCKET_PROXY_SUBNET_ACTUAL}"
        echo "t2_proxy=${T2_PROXY_SUBNET_ACTUAL}"
        echo "database=${DATABASE_NETWORK_NAME}"
        echo ""
        echo "Compose files:"
        echo "${YML_00_NAME}: ${YML_00_DOWNLOADED}"
        echo "${YML_01_NAME}: ${YML_01_DOWNLOADED}"
        echo "${YML_01_OVERRIDE_NAME}: ${YML_01_OVERRIDE_DOWNLOADED}"
        echo "Portainer override: ${PORTAINER_BOOTSTRAP_OVERRIDE_WRITTEN}"
        echo ""
        echo "Deployments:"
        echo "socket-proxy deployed: ${SOCKET_PROXY_DEPLOYED}"
        echo "portainer deployed: ${PORTAINER_DEPLOYED}"
        echo "Portainer bootstrap port exposed: ${PORTAINER_BOOTSTRAP_PORT_EXPOSED}"
        echo "UFW bootstrap port opened: ${UFW_BOOTSTRAP_PORT_OPENED}"
        echo "Portainer URL: ${PORTAINER_ACCESS_URL}"
        echo ""
        echo "Docker containers:"
        docker_cmd ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
    } | if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee -a "$VERIFY_LOG" >/dev/null; else tee -a "$VERIFY_LOG" >/dev/null; fi

    msg_ok "DOCKER BOOTSTRAP VERIFICATION REPORT WRITTEN"
}

# --- 45. COMPLETION MARKER ---
# Stores successful bootstrap information.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<MARKER_EOF
Docker Bootstrap Setup completed on: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Env file: $ENV_FILE
GitHub raw base: $GITHUB_RAW_BASE
Networks created: $NETWORKS_CREATED
Networks verified: $NETWORKS_VERIFIED
socket_proxy subnet: $SOCKET_PROXY_SUBNET_ACTUAL
t2_proxy subnet: $T2_PROXY_SUBNET_ACTUAL
database network: $DATABASE_NETWORK_NAME
YML 00 downloaded: $YML_00_DOWNLOADED
YML 01 downloaded: $YML_01_DOWNLOADED
YML 01 override downloaded: $YML_01_OVERRIDE_DOWNLOADED
Socket proxy deployed: $SOCKET_PROXY_DEPLOYED
Portainer deployed: $PORTAINER_DEPLOYED
Portainer bootstrap override: $PORTAINER_BOOTSTRAP_OVERRIDE_WRITTEN
Portainer bootstrap port: $PORTAINER_BOOTSTRAP_PORT
Portainer bootstrap port exposed: $PORTAINER_BOOTSTRAP_PORT_EXPOSED
UFW bootstrap port opened: $UFW_BOOTSTRAP_PORT_OPENED
Portainer URL: $PORTAINER_ACCESS_URL
Verify log: $VERIFY_LOG
MARKER_EOF
    else
        cat > "$COMPLETED_MARKER" <<MARKER_EOF
Docker Bootstrap Setup completed on: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Env file: $ENV_FILE
GitHub raw base: $GITHUB_RAW_BASE
Networks created: $NETWORKS_CREATED
Networks verified: $NETWORKS_VERIFIED
socket_proxy subnet: $SOCKET_PROXY_SUBNET_ACTUAL
t2_proxy subnet: $T2_PROXY_SUBNET_ACTUAL
database network: $DATABASE_NETWORK_NAME
YML 00 downloaded: $YML_00_DOWNLOADED
YML 01 downloaded: $YML_01_DOWNLOADED
YML 01 override downloaded: $YML_01_OVERRIDE_DOWNLOADED
Socket proxy deployed: $SOCKET_PROXY_DEPLOYED
Portainer deployed: $PORTAINER_DEPLOYED
Portainer bootstrap override: $PORTAINER_BOOTSTRAP_OVERRIDE_WRITTEN
Portainer bootstrap port: $PORTAINER_BOOTSTRAP_PORT
Portainer bootstrap port exposed: $PORTAINER_BOOTSTRAP_PORT_EXPOSED
UFW bootstrap port opened: $UFW_BOOTSTRAP_PORT_OPENED
Portainer URL: $PORTAINER_ACCESS_URL
Verify log: $VERIFY_LOG
MARKER_EOF
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 46. FINAL SUMMARY ---
# Displays clean final setup summary and next step.
function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    detail_line "socket_proxy" "$SOCKET_PROXY_SUBNET_ACTUAL"
    detail_line "t2_proxy" "$T2_PROXY_SUBNET_ACTUAL"
    detail_line "database" "$DATABASE_NETWORK_NAME"
    detail_line "YML 00" "${COMPOSE_DIR}/${YML_00_NAME}"
    detail_line "YML 01" "${COMPOSE_DIR}/${YML_01_NAME}"
    detail_line "YML 01 override" "${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"
    detail_line "Portainer URL" "$PORTAINER_ACCESS_URL"
    detail_line "Bootstrap port" "$PORTAINER_BOOTSTRAP_PORT"
    detail_line "Verify log" "$VERIFY_LOG"

    echo ""
    echo -e "${YW}Portainer is temporarily exposed directly for bootstrap access.${CL}"
    echo -e "${YW}After Traefik/AuthentiK deployment is stable, run Script 7 to close this direct port and harden sudo/Docker access.${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}Open Portainer at:${CL} ${GN}${PORTAINER_ACCESS_URL}${CL}"
    echo -e "${YW}Then deploy the remaining compose stacks through Portainer in order.${CL}"
    echo ""
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 47. MAIN FUNCTION ---
# Runs Docker network + socket-proxy + Portainer bootstrap in safe order.
function main() {
    init_script

    detect_docker_access
    check_previous_marker
    start_confirmation
    collect_bootstrap_settings
    validate_project_paths

    create_shared_networks
    verify_shared_networks

    download_bootstrap_compose_files
    verify_portainer_bootstrap_override_file
    validate_bootstrap_compose_files

    configure_bootstrap_firewall
    deploy_socket_proxy
    deploy_portainer
    verify_bootstrap_containers

    create_verification_report
    write_completion_marker
    show_final_summary

    exit 0
}

main "$@"
