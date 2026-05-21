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
YML_DOCKGE_NAME="13-dockge-compose.yml"
YML_KOMODO_NAME="14-komodo-compose.yml"
YML_12_NAME="12-docker-gc-compose.yml"

# Optional environment overrides for advanced/testing workflows.
# If these are not set, URLs are rebuilt from GITHUB_RAW_BASE after user input.
YML_00_URL_OVERRIDE="${YML_00_URL:-}"
YML_01_URL_OVERRIDE="${YML_01_URL:-}"
YML_01_OVERRIDE_URL_OVERRIDE="${YML_01_OVERRIDE_URL:-}"
YML_DOCKGE_URL_OVERRIDE="${YML_DOCKGE_URL:-}"
YML_DOCKGE_OVERRIDE_NAME="13-dockge-bootstrap-override.yml"
YML_DOCKGE_OVERRIDE_URL_OVERRIDE="${YML_DOCKGE_OVERRIDE_URL:-}"
YML_KOMODO_URL_OVERRIDE="${YML_KOMODO_URL:-}"
YML_KOMODO_OVERRIDE_NAME="14-komodo-bootstrap-override.yml"
YML_KOMODO_OVERRIDE_URL_OVERRIDE="${YML_KOMODO_OVERRIDE_URL:-}"
YML_00_URL="${YML_00_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_00_NAME}}"
YML_01_URL="${YML_01_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_01_NAME}}"
YML_01_OVERRIDE_URL="${YML_01_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_01_OVERRIDE_NAME}}"
YML_DOCKGE_URL="${YML_DOCKGE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_DOCKGE_NAME}}"
YML_DOCKGE_OVERRIDE_URL="${YML_DOCKGE_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_DOCKGE_OVERRIDE_NAME}}"
YML_KOMODO_URL="${YML_KOMODO_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_KOMODO_NAME}}"
YML_KOMODO_OVERRIDE_URL="${YML_KOMODO_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${YML_KOMODO_OVERRIDE_NAME}}"

SOCKET_PROXY_SUBNET_EXPECTED="192.168.91.0/24"
T2_PROXY_SUBNET_EXPECTED="192.168.90.0/24"
SOCKET_PROXY_SUBNET_ACTUAL=""
T2_PROXY_SUBNET_ACTUAL=""
DATABASE_NETWORK_NAME=""

PORTAINER_BOOTSTRAP_PORT="${PORTAINER_BOOTSTRAP_PORT:-9443}"
DOCKGE_BOOTSTRAP_PORT="${DOCKGE_BOOTSTRAP_PORT:-5001}"
KOMODO_BOOTSTRAP_PORT="${KOMODO_BOOTSTRAP_PORT:-9120}"
ADMIN_UI_BOOTSTRAP_BIND="${ADMIN_UI_BOOTSTRAP_BIND:-0.0.0.0}"
ADMIN_UI_BOOTSTRAP_PORT=""
ADMIN_UI_INTERNAL_PORT=""
ADMIN_UI_BOOTSTRAP_SCHEME="http"
ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME=""
ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE=""
ADMIN_UI_BOOTSTRAP_ACCESS_IP=""
ADMIN_UI_BOOTSTRAP_ACCESS_URL=""

ADMIN_UI="${ADMIN_UI:-portainer}"
ADMIN_UI_DISPLAY_NAME="Portainer"
ADMIN_UI_SERVICE_NAME="portainer"
ADMIN_UI_COMPOSE_FILE=""
ADMIN_UI_PROJECT_NAME="portainer"
ADMIN_UI_HOST=""
ADMIN_UI_URL=""
ADMIN_UI_DEPLOYED="no"
ADMIN_UI_VALIDATED="no"

DOMAIN_VALUE=""
DOCKER_SECRETS_DIR=""
CF_API_TOKEN_FILE=""
TRAEFIK_STATIC_CONFIG_FILE=""
TRAEFIK_DYNAMIC_CONFIG_FILE=""
TRAEFIK_ACME_STORAGE=""

SYSCTL_REDIS_OK="no"
TRAEFIK_PLACEHOLDERS_OK="no"
TRAEFIK_DNS_DELAY_OK="no"
TRAEFIK_ENCODED_CHARS_OK="no"
TRAEFIK_AUTHENTIK_REFERENCES_OK="no"
AUTHENTIK_FOLDERS_OK="no"
TEMPORAL_COMPOSE_OK="skipped"
CF_COMPANION_SECRET_OK="skipped"
FILEBROWSER_FOLDERS_OK="skipped"
YML_12_RETIRED="no"

POSTIZ_TEMPORAL_GUARD_PATH="/usr/local/sbin/postiz-temporal-guard"
POSTIZ_TEMPORAL_GUARD_INSTALLED="no"
POSTIZ_TEMPORAL_GUARD_RUN="not-run"
POSTIZ_TEMPORAL_GUARD_STATUS="not-run"

SUDO_CMD=""
DOCKER_NEEDS_SUDO="no"
TEMP_FILES=()

NETWORKS_CREATED="no"
NETWORKS_VERIFIED="no"
YML_00_DOWNLOADED="no"
YML_01_DOWNLOADED="no"
YML_01_OVERRIDE_DOWNLOADED="no"
YML_DOCKGE_DOWNLOADED="no"
YML_DOCKGE_OVERRIDE_DOWNLOADED="no"
YML_KOMODO_DOWNLOADED="no"
YML_KOMODO_OVERRIDE_DOWNLOADED="no"
SOCKET_PROXY_DEPLOYED="no"
PORTAINER_DEPLOYED="no"
ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN="no"
ADMIN_UI_BOOTSTRAP_PORT_EXPOSED="no"
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


# --- 29A. ENV VALUE HELPER ---
# Reads a variable from the generated .env without printing secret values.
function env_value() {
    local key="$1"

    awk -F= -v k="$key" '
        $1 == k {
            val=$0
            sub("^[^=]*=", "", val)
            gsub(/^"|"$/, "", val)
            print val
            exit
        }
    ' "$ENV_FILE" 2>/dev/null || true
}

# --- 29B. FILE WRITABILITY HELPER ---
# Verifies that the selected Docker user can create and remove a test file in a folder.
function verify_user_writable_dir() {
    local path="$1"
    local test_file="${path}/.bootstrap-write-test-$$"

    [ -d "$path" ] || return 1

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" -u "$DOCKER_USER" sh -c "touch '$test_file' && rm -f '$test_file'" >/dev/null 2>&1
    else
        su -s /bin/sh "$DOCKER_USER" -c "touch '$test_file' && rm -f '$test_file'" >/dev/null 2>&1
    fi
}

# --- 29C. COMPOSE FILE VALIDATION HELPER ---
# Validates an optional compose file only if it exists.
function validate_optional_compose_file() {
    local project="$1"
    local file="$2"

    if [ ! -f "$file" ]; then
        return 2
    fi

    run_docker_cmd "validating ${file}" compose --env-file "$ENV_FILE" -p "$project" -f "$file" config -q
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
# Starts Docker network and Admin UI bootstrap after showing a clear description.
function start_confirmation() {
    local start_yn=""

    section "START"

    echo -e "${YW}This script creates shared Docker networks, validates Script 6 output, downloads bootstrap compose files, and deploys socket-proxy plus the selected admin UI.${CL}"
    echo -e "${YW}Selected admin UI is read from ${ENV_FILE}: Dockge, Portainer CE, or Komodo.${CL}"
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

    if [ -z "$YML_DOCKGE_URL_OVERRIDE" ]; then
        YML_DOCKGE_URL="${GITHUB_RAW_BASE}/${YML_DOCKGE_NAME}"
    fi

    if [ -z "$YML_DOCKGE_OVERRIDE_URL_OVERRIDE" ]; then
        YML_DOCKGE_OVERRIDE_URL="${GITHUB_RAW_BASE}/${YML_DOCKGE_OVERRIDE_NAME}"
    fi

    if [ -z "$YML_KOMODO_URL_OVERRIDE" ]; then
        YML_KOMODO_URL="${GITHUB_RAW_BASE}/${YML_KOMODO_NAME}"
    fi

    if [ -z "$YML_KOMODO_OVERRIDE_URL_OVERRIDE" ]; then
        YML_KOMODO_OVERRIDE_URL="${GITHUB_RAW_BASE}/${YML_KOMODO_OVERRIDE_NAME}"
    fi

    detail_line "Docker user" "$DOCKER_USER"
    detail_line "Docker dir" "$DOCKER_DIR"
    detail_line "Compose dir" "$COMPOSE_DIR"
    detail_line "Env file" "$ENV_FILE"
    detail_line "GitHub raw base" "$GITHUB_RAW_BASE"
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

    DOMAIN_VALUE="$(env_value DOMAIN)"
    DOCKER_SECRETS_DIR="$(env_value DOCKER_SECRETS_DIR)"
    CF_API_TOKEN_FILE="$(env_value CF_API_TOKEN_FILE)"
    ADMIN_UI="$(env_value ADMIN_UI)"
    ADMIN_UI="${ADMIN_UI:-portainer}"

    TRAEFIK_STATIC_CONFIG_FILE="${DOCKER_DIR}/appdata/traefik/traefik.yml"
    TRAEFIK_DYNAMIC_CONFIG_FILE="${DOCKER_DIR}/appdata/traefik/dynamic-config.yml"
    TRAEFIK_ACME_STORAGE="${DOCKER_DIR}/appdata/traefik/acme/acme.json"

    msg_ok "PROJECT PATHS READY"

    detail_line "Docker dir" "$DOCKER_DIR"
    detail_line "Compose dir" "$COMPOSE_DIR"
    detail_line ".env" "$ENV_FILE"
    detail_line "Domain" "${DOMAIN_VALUE:-missing}"
    detail_line "Selected admin UI" "$ADMIN_UI"
}


# =========================================================
#  SCRIPT 6 OUTPUT VALIDATION
# =========================================================

# --- 33A. REDIS HOST TUNING VERIFICATION ---
# Confirms Script 5 applied the Redis-recommended overcommit setting before Redis deployment.
function verify_redis_host_tuning() {
    section "REDIS HOST TUNING"

    local value=""
    value="$(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo "")"

    if [ "$value" == "1" ]; then
        SYSCTL_REDIS_OK="yes"
        msg_ok "VM.OVERCOMMIT_MEMORY IS 1"
    else
        msg_error "vm.overcommit_memory is ${value:-unknown}. Run fixed Script 5 before deploying Redis."
    fi

    if [ -f /etc/sysctl.d/99-redis-overcommit.conf ] || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" test -f /etc/sysctl.d/99-redis-overcommit.conf 2>/dev/null; }; then
        msg_ok "REDIS SYSCTL PERSISTENCE FILE FOUND"
    else
        msg_warn "Redis sysctl persistence file not found. Runtime value is correct, but reboot persistence should be fixed."
    fi
}

# --- 33B. TRAEFIK TEMPLATE RENDER VERIFICATION ---
# Ensures no unreplaced placeholders remain and final Traefik v3.7 settings exist.
function verify_traefik_rendered_configs() {
    section "TRAEFIK TEMPLATE VERIFICATION"

    [ -f "$TRAEFIK_STATIC_CONFIG_FILE" ] || msg_error "Traefik static config missing: ${TRAEFIK_STATIC_CONFIG_FILE}"
    [ -f "$TRAEFIK_DYNAMIC_CONFIG_FILE" ] || msg_error "Traefik dynamic config missing: ${TRAEFIK_DYNAMIC_CONFIG_FILE}"
    [ -f "$TRAEFIK_ACME_STORAGE" ] || msg_error "Traefik acme.json missing: ${TRAEFIK_ACME_STORAGE}"

    msg_info "Checking for unreplaced template placeholders"
    if grep -R '{{[^}]*}}' "$TRAEFIK_STATIC_CONFIG_FILE" "$TRAEFIK_DYNAMIC_CONFIG_FILE" >/dev/null 2>&1; then
        msg_error "Unrendered {{PLACEHOLDER}} values remain in Traefik config. Fix Script 6 render logic/templates."
    fi
    TRAEFIK_PLACEHOLDERS_OK="yes"
    msg_ok "TRAEFIK PLACEHOLDERS FULLY RENDERED"

    msg_info "Checking Traefik v3.7 DNS propagation syntax"
    if grep -q 'delayBeforeChecks' "$TRAEFIK_STATIC_CONFIG_FILE" && ! grep -q 'delayBeforeCheck:' "$TRAEFIK_STATIC_CONFIG_FILE"; then
        TRAEFIK_DNS_DELAY_OK="yes"
        msg_ok "TRAEFIK DNS PROPAGATION SYNTAX IS V3.7 COMPATIBLE"
    else
        msg_error "Traefik DNS challenge must use propagation.delayBeforeChecks, not deprecated delayBeforeCheck."
    fi

    msg_info "Checking Traefik encoded-character options"
    if grep -q 'encodedCharacters' "$TRAEFIK_STATIC_CONFIG_FILE"; then
        TRAEFIK_ENCODED_CHARS_OK="yes"
        msg_ok "TRAEFIK ENCODED-CHARACTER CONFIG FOUND"
    else
        msg_error "Traefik encoded-character options missing from static config. Fix Script 6 template."
    fi

    msg_info "Checking for stale authentik@docker references"
    if grep -q 'authentik@docker' "$TRAEFIK_DYNAMIC_CONFIG_FILE"; then
        msg_error "Stale authentik@docker reference found in dynamic config. Use authentik file-provider middleware."
    fi
    TRAEFIK_AUTHENTIK_REFERENCES_OK="yes"
    msg_ok "NO STALE AUTHENTIK@DOCKER REFERENCES"

    msg_info "Checking acme.json permissions"
    local acme_mode=""
    acme_mode="$(stat -c '%a' "$TRAEFIK_ACME_STORAGE" 2>/dev/null || true)"
    if [ "$acme_mode" == "600" ]; then
        msg_ok "TRAEFIK ACME STORAGE PERMISSIONS ARE 600"
    else
        msg_error "Traefik acme.json mode is ${acme_mode:-unknown}; expected 600."
    fi
}

# --- 33C. AUTHENTIK FOLDER VERIFICATION ---
# Confirms host bind mounts exist and are writable by the non-root Authentik container user.
function verify_authentik_folders() {
    section "AUTHENTIK FOLDER VERIFICATION"

    local folders=(
        "${DOCKER_DIR}/appdata/authentik"
        "${DOCKER_DIR}/appdata/authentik/media"
        "${DOCKER_DIR}/appdata/authentik/custom-templates"
        "${DOCKER_DIR}/appdata/authentik/certs"
    )
    local folder=""

    for folder in "${folders[@]}"; do
        msg_info "Checking ${folder}"
        [ -d "$folder" ] || msg_error "Required Authentik folder missing: ${folder}"

        if [ -n "$SUDO_CMD" ]; then
            "$SUDO_CMD" -u '#1000' sh -c "touch '${folder}/.ak-write-test-$$' && rm -f '${folder}/.ak-write-test-$$'" >/dev/null 2>&1 || msg_error "Authentik UID 1000 cannot write to ${folder}"
        else
            touch "${folder}/.ak-write-test-$$" && rm -f "${folder}/.ak-write-test-$$" || msg_error "Cannot verify Authentik write access to ${folder}"
        fi

        msg_ok "AUTHENTIK FOLDER READY: ${folder}"
    done

    AUTHENTIK_FOLDERS_OK="yes"
}

# --- 33D. TEMPORAL COMPOSE VERIFICATION ---
# Checks Temporal settings before yml 06 deployment when the file is present.
function verify_temporal_compose_settings() {
    section "TEMPORAL COMPOSE VERIFICATION"

    local file="${COMPOSE_DIR}/06-temporal-compose.yml"

    if [ ! -f "$file" ]; then
        TEMPORAL_COMPOSE_OK="not-present-yet"
        msg_skip "YML 06 NOT PRESENT YET; TEMPORAL CHECK WILL BE RUN AFTER DOWNLOAD/BEFORE DEPLOYMENT"
        return 0
    fi

    grep -q 'DB=postgres12\|DB:.*postgres12' "$file" || msg_error "Temporal compose must use DB=postgres12."
    grep -q 'DBNAME=temporal\|DBNAME:.*temporal' "$file" || msg_error "Temporal compose must set DBNAME=temporal."
    grep -q 'VISIBILITY_DBNAME=temporal_visibility\|VISIBILITY_DBNAME:.*temporal_visibility' "$file" || msg_error "Temporal compose must set VISIBILITY_DBNAME=temporal_visibility."
    grep -q 'SKIP_DB_CREATE=true\|SKIP_DB_CREATE:.*true' "$file" || msg_error "Temporal compose must set SKIP_DB_CREATE=true."

    if grep -q 'DYNAMIC_CONFIG_FILE_PATH' "$file"; then
        if ! grep -q 'development-sql.yaml' "$file" || [ ! -f "${DOCKER_DIR}/appdata/temporal/dynamicconfig/development-sql.yaml" ]; then
            msg_error "DYNAMIC_CONFIG_FILE_PATH is set but the required dynamic config file is not present. Remove the override or create the file."
        fi
    fi

    TEMPORAL_COMPOSE_OK="yes"
    msg_ok "TEMPORAL COMPOSE SETTINGS VERIFIED"
}

# --- 33E. ADMIN UI SELECTION VERIFICATION ---
# Maps .env ADMIN_UI to expected compose template and service.
function verify_admin_ui_selection() {
    section "ADMIN UI SELECTION"

    local expected_host=""

    case "$ADMIN_UI" in
        dockge)
            ADMIN_UI_PROJECT_NAME="dockge"
            ADMIN_UI_SERVICE_NAME="dockge"
            ADMIN_UI_DISPLAY_NAME="Dockge"
            ADMIN_UI_COMPOSE_FILE="${COMPOSE_DIR}/${YML_DOCKGE_NAME}"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME="$YML_DOCKGE_OVERRIDE_NAME"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE="${COMPOSE_DIR}/${YML_DOCKGE_OVERRIDE_NAME}"
            ADMIN_UI_BOOTSTRAP_PORT="$DOCKGE_BOOTSTRAP_PORT"
            ADMIN_UI_INTERNAL_PORT="5001"
            ADMIN_UI_BOOTSTRAP_SCHEME="http"
            expected_host="dockge.${DOMAIN_VALUE}"
            ;;
        portainer|portainer-ce)
            ADMIN_UI="portainer"
            ADMIN_UI_PROJECT_NAME="portainer"
            ADMIN_UI_SERVICE_NAME="portainer"
            ADMIN_UI_DISPLAY_NAME="Portainer"
            ADMIN_UI_COMPOSE_FILE="${COMPOSE_DIR}/${YML_01_NAME}"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME="$YML_01_OVERRIDE_NAME"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE="${COMPOSE_DIR}/${YML_01_OVERRIDE_NAME}"
            ADMIN_UI_BOOTSTRAP_PORT="$PORTAINER_BOOTSTRAP_PORT"
            ADMIN_UI_INTERNAL_PORT="9443"
            ADMIN_UI_BOOTSTRAP_SCHEME="https"
            expected_host="portainer.${DOMAIN_VALUE}"
            ;;
        komodo)
            ADMIN_UI_PROJECT_NAME="komodo"
            ADMIN_UI_SERVICE_NAME="komodo-core"
            ADMIN_UI_DISPLAY_NAME="Komodo"
            ADMIN_UI_COMPOSE_FILE="${COMPOSE_DIR}/${YML_KOMODO_NAME}"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME="$YML_KOMODO_OVERRIDE_NAME"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE="${COMPOSE_DIR}/${YML_KOMODO_OVERRIDE_NAME}"
            ADMIN_UI_BOOTSTRAP_PORT="$KOMODO_BOOTSTRAP_PORT"
            ADMIN_UI_INTERNAL_PORT="9120"
            ADMIN_UI_BOOTSTRAP_SCHEME="http"
            expected_host="komodo.${DOMAIN_VALUE}"
            ;;
        *)
            msg_error "Invalid ADMIN_UI value in .env: ${ADMIN_UI}. Expected dockge, portainer, or komodo."
            ;;
    esac

    [ -z "${ADMIN_UI_HOST:-}" ] && ADMIN_UI_HOST="$expected_host"
    [ -z "${ADMIN_UI_URL:-}" ] && ADMIN_UI_URL="https://${ADMIN_UI_HOST}"

    msg_ok "ADMIN UI SELECTION VERIFIED"
    detail_line "Admin UI" "$ADMIN_UI_DISPLAY_NAME"
    detail_line "Admin UI host" "$ADMIN_UI_HOST"
    detail_line "Admin UI URL" "$ADMIN_UI_URL"
    detail_line "Stack compose" "$ADMIN_UI_COMPOSE_FILE"
    detail_line "Bootstrap override" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
    detail_line "Temporary bootstrap port" "$ADMIN_UI_BOOTSTRAP_PORT"
}

# --- 33F. CLOUDFLARE COMPANION SECRET VERIFICATION ---
# Ensures cf-companion can read Cloudflare token from a local secret file.
function verify_cf_companion_secret_file() {
    section "CF-COMPANION SECRET VERIFICATION"

    if [ -z "$CF_API_TOKEN_FILE" ]; then
        CF_COMPANION_SECRET_OK="missing-env"
        msg_warn "CF_API_TOKEN_FILE missing from .env"
        return 0
    fi

    if [ -s "$CF_API_TOKEN_FILE" ]; then
        CF_COMPANION_SECRET_OK="yes"
        msg_ok "CLOUDFLARE TOKEN FILE EXISTS AND IS NON-EMPTY"
    else
        CF_COMPANION_SECRET_OK="empty-or-missing"
        msg_warn "Cloudflare token file is empty or missing: ${CF_API_TOKEN_FILE}"
    fi
}

# --- 33G. FILEBROWSER FOLDER VERIFICATION ---
# Confirms Filebrowser-safe writable folders exist before yml 11 deployment.
function verify_filebrowser_folders() {
    section "FILEBROWSER FOLDER VERIFICATION"

    local folders=(
        "${DOCKER_DIR}/appdata/filebrowser/database"
        "${DOCKER_DIR}/appdata/filebrowser/config"
        "${DOCKER_DIR}/shared"
        "${DOCKER_DIR}/backups"
        "${DOCKER_DIR}/compose"
    )
    local folder=""

    for folder in "${folders[@]}"; do
        msg_info "Checking ${folder}"
        [ -d "$folder" ] || msg_error "Required Filebrowser folder missing: ${folder}"
        verify_user_writable_dir "$folder" || msg_error "Docker user ${DOCKER_USER} cannot write to ${folder}"
        msg_ok "FILEBROWSER FOLDER WRITABLE: ${folder}"
    done

    FILEBROWSER_FOLDERS_OK="yes"
}

# --- 33H. YML 12 RETIREMENT CHECK ---
# Prevents deployment of the retired Docker-GC container stack.
function retire_yml_12_docker_gc() {
    YML_12_RETIRED="retired-host-side-cleanup"
    return 0
}


# =========================================================
#  POSTIZ / TEMPORAL RUNTIME GUARD
# =========================================================

# --- 33I. POSTIZ TEMPORAL GUARD INSTALLER ---
# Installs a reusable helper that fixes the known Postiz + Temporal fresh/rerun startup issue.
# Temporal auto-setup can create default Text search attributes that conflict with Postiz startup.
# The helper must run after Temporal is fully started and before Postiz starts.
function install_postiz_temporal_guard() {
    section "POSTIZ / TEMPORAL GUARD"

    msg_info "Installing Postiz Temporal guard helper"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" tee "$POSTIZ_TEMPORAL_GUARD_PATH" >/dev/null <<'POSTIZ_TEMPORAL_GUARD_EOF'
#!/usr/bin/env bash
set -euo pipefail

# =========================================================
#  Postiz Temporal Guard
# =========================================================
# Run after Temporal is started and before Postiz is started.
# It removes Temporal default Text search attributes that can make Postiz fail with:
# cannot have more than 3 search attribute of type Text
# Do not restart Temporal after this helper removes the attributes.

TEMPORAL_CONTAINER="${TEMPORAL_CONTAINER:-temporal}"
POSTIZ_CONTAINER="${POSTIZ_CONTAINER:-postiz}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
SLEEP_SECONDS="${SLEEP_SECONDS:-5}"

cleanup_tmp() {
    rm -f /tmp/postiz-temporal-search-attributes.$$ /tmp/postiz-temporal-guard-error.$$ 2>/dev/null || true
}
trap cleanup_tmp EXIT

if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    DOCKER=(docker)
elif command -v sudo >/dev/null 2>&1 && sudo -n docker ps >/dev/null 2>&1; then
    DOCKER=(sudo docker)
else
    echo "ERROR: Docker is not reachable. Run as a docker user or with sudo." >&2
    exit 1
fi

if ! "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -qx "$TEMPORAL_CONTAINER"; then
    echo "SKIP: Temporal container not found: $TEMPORAL_CONTAINER"
    exit 0
fi

if "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -qx "$POSTIZ_CONTAINER"; then
    if "${DOCKER[@]}" ps --format '{{.Names}}' | grep -qx "$POSTIZ_CONTAINER"; then
        echo "Stopping Postiz before Temporal search-attribute cleanup..."
        "${DOCKER[@]}" stop "$POSTIZ_CONTAINER" >/dev/null || true
    fi
fi

if ! "${DOCKER[@]}" ps --format '{{.Names}}' | grep -qx "$TEMPORAL_CONTAINER"; then
    echo "Starting Temporal..."
    "${DOCKER[@]}" start "$TEMPORAL_CONTAINER" >/dev/null
fi

waited=0
TEMPORAL_IP=""
while [ "$waited" -le "$WAIT_SECONDS" ]; do
    TEMPORAL_IP="$("${DOCKER[@]}" inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$TEMPORAL_CONTAINER" 2>/dev/null || true)"

    if [ -n "$TEMPORAL_IP" ]; then
        if "${DOCKER[@]}" exec "$TEMPORAL_CONTAINER" temporal --address "${TEMPORAL_IP}:7233" operator search-attribute list >/tmp/postiz-temporal-search-attributes.$$ 2>/tmp/postiz-temporal-guard-error.$$; then
            break
        fi
    fi

    sleep "$SLEEP_SECONDS"
    waited=$((waited + SLEEP_SECONDS))
done

if [ ! -s /tmp/postiz-temporal-search-attributes.$$ ]; then
    echo "ERROR: Temporal did not become reachable on port 7233 within ${WAIT_SECONDS}s." >&2
    cat /tmp/postiz-temporal-guard-error.$$ 2>/dev/null || true
    exit 1
fi

attrs="$(cat /tmp/postiz-temporal-search-attributes.$$)"

remove_args=()
if grep -q '^  CustomTextField[[:space:]]\+Text' <<< "$attrs"; then
    remove_args+=(--name CustomTextField)
fi
if grep -q '^  CustomStringField[[:space:]]\+Text' <<< "$attrs"; then
    remove_args+=(--name CustomStringField)
fi

if [ "${#remove_args[@]}" -gt 0 ]; then
    echo "Removing Temporal Text attributes that conflict with Postiz: ${remove_args[*]}"
    "${DOCKER[@]}" exec "$TEMPORAL_CONTAINER" temporal --address "${TEMPORAL_IP}:7233" operator search-attribute remove "${remove_args[@]}" --yes
else
    echo "No conflicting Temporal Text attributes found."
fi

# Important: do not restart Temporal after attribute removal.
# Restarting Temporal can recreate the attributes before Postiz starts.
if "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -qx "$POSTIZ_CONTAINER"; then
    echo "Starting Postiz..."
    "${DOCKER[@]}" start "$POSTIZ_CONTAINER" >/dev/null || true

    sleep 30
    if "${DOCKER[@]}" exec "$POSTIZ_CONTAINER" sh -c "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -qi ':0BB8'"; then
        echo "PASS: Postiz backend port 3000 is listening."
    else
        echo "WARN: Postiz container exists, but backend port 3000 was not confirmed yet. Check: docker logs postiz --tail=180" >&2
    fi
else
    echo "Postiz container is not deployed yet. Run this helper after yml 06 Temporal is up and before yml 07 Postiz, or immediately after yml 07 if Postiz already exists."
fi

exit 0
POSTIZ_TEMPORAL_GUARD_EOF
        "$SUDO_CMD" chmod 0755 "$POSTIZ_TEMPORAL_GUARD_PATH"
    else
        cat > "$POSTIZ_TEMPORAL_GUARD_PATH" <<'POSTIZ_TEMPORAL_GUARD_EOF'
#!/usr/bin/env bash
set -euo pipefail

# =========================================================
#  Postiz Temporal Guard
# =========================================================
# Run after Temporal is started and before Postiz is started.
# It removes Temporal default Text search attributes that can make Postiz fail with:
# cannot have more than 3 search attribute of type Text
# Do not restart Temporal after this helper removes the attributes.

TEMPORAL_CONTAINER="${TEMPORAL_CONTAINER:-temporal}"
POSTIZ_CONTAINER="${POSTIZ_CONTAINER:-postiz}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
SLEEP_SECONDS="${SLEEP_SECONDS:-5}"

cleanup_tmp() {
    rm -f /tmp/postiz-temporal-search-attributes.$$ /tmp/postiz-temporal-guard-error.$$ 2>/dev/null || true
}
trap cleanup_tmp EXIT

if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    DOCKER=(docker)
elif command -v sudo >/dev/null 2>&1 && sudo -n docker ps >/dev/null 2>&1; then
    DOCKER=(sudo docker)
else
    echo "ERROR: Docker is not reachable. Run as a docker user or with sudo." >&2
    exit 1
fi

if ! "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -qx "$TEMPORAL_CONTAINER"; then
    echo "SKIP: Temporal container not found: $TEMPORAL_CONTAINER"
    exit 0
fi

if "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -qx "$POSTIZ_CONTAINER"; then
    if "${DOCKER[@]}" ps --format '{{.Names}}' | grep -qx "$POSTIZ_CONTAINER"; then
        echo "Stopping Postiz before Temporal search-attribute cleanup..."
        "${DOCKER[@]}" stop "$POSTIZ_CONTAINER" >/dev/null || true
    fi
fi

if ! "${DOCKER[@]}" ps --format '{{.Names}}' | grep -qx "$TEMPORAL_CONTAINER"; then
    echo "Starting Temporal..."
    "${DOCKER[@]}" start "$TEMPORAL_CONTAINER" >/dev/null
fi

waited=0
TEMPORAL_IP=""
while [ "$waited" -le "$WAIT_SECONDS" ]; do
    TEMPORAL_IP="$("${DOCKER[@]}" inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$TEMPORAL_CONTAINER" 2>/dev/null || true)"

    if [ -n "$TEMPORAL_IP" ]; then
        if "${DOCKER[@]}" exec "$TEMPORAL_CONTAINER" temporal --address "${TEMPORAL_IP}:7233" operator search-attribute list >/tmp/postiz-temporal-search-attributes.$$ 2>/tmp/postiz-temporal-guard-error.$$; then
            break
        fi
    fi

    sleep "$SLEEP_SECONDS"
    waited=$((waited + SLEEP_SECONDS))
done

if [ ! -s /tmp/postiz-temporal-search-attributes.$$ ]; then
    echo "ERROR: Temporal did not become reachable on port 7233 within ${WAIT_SECONDS}s." >&2
    cat /tmp/postiz-temporal-guard-error.$$ 2>/dev/null || true
    exit 1
fi

attrs="$(cat /tmp/postiz-temporal-search-attributes.$$)"

remove_args=()
if grep -q '^  CustomTextField[[:space:]]\+Text' <<< "$attrs"; then
    remove_args+=(--name CustomTextField)
fi
if grep -q '^  CustomStringField[[:space:]]\+Text' <<< "$attrs"; then
    remove_args+=(--name CustomStringField)
fi

if [ "${#remove_args[@]}" -gt 0 ]; then
    echo "Removing Temporal Text attributes that conflict with Postiz: ${remove_args[*]}"
    "${DOCKER[@]}" exec "$TEMPORAL_CONTAINER" temporal --address "${TEMPORAL_IP}:7233" operator search-attribute remove "${remove_args[@]}" --yes
else
    echo "No conflicting Temporal Text attributes found."
fi

# Important: do not restart Temporal after attribute removal.
# Restarting Temporal can recreate the attributes before Postiz starts.
if "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -qx "$POSTIZ_CONTAINER"; then
    echo "Starting Postiz..."
    "${DOCKER[@]}" start "$POSTIZ_CONTAINER" >/dev/null || true

    sleep 30
    if "${DOCKER[@]}" exec "$POSTIZ_CONTAINER" sh -c "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -qi ':0BB8'"; then
        echo "PASS: Postiz backend port 3000 is listening."
    else
        echo "WARN: Postiz container exists, but backend port 3000 was not confirmed yet. Check: docker logs postiz --tail=180" >&2
    fi
else
    echo "Postiz container is not deployed yet. Run this helper after yml 06 Temporal is up and before yml 07 Postiz, or immediately after yml 07 if Postiz already exists."
fi

exit 0
POSTIZ_TEMPORAL_GUARD_EOF
        chmod 0755 "$POSTIZ_TEMPORAL_GUARD_PATH"
    fi

    POSTIZ_TEMPORAL_GUARD_INSTALLED="yes"
    msg_ok "POSTIZ TEMPORAL GUARD INSTALLED"
    detail_line "Guard command" "$POSTIZ_TEMPORAL_GUARD_PATH"
}

# --- 33J. POSTIZ TEMPORAL GUARD RERUN CHECK ---
# Runs the guard only when Temporal is already deployed during a rerun.
# On a brand-new deployment, this safely skips and the installed helper is used after yml 06 starts.
function run_postiz_temporal_guard_if_ready() {
    section "POSTIZ / TEMPORAL RERUN CHECK"

    if ! docker_cmd ps -a --format '{{.Names}}' | grep -qx 'temporal'; then
        POSTIZ_TEMPORAL_GUARD_RUN="skipped-temporal-not-present"
        POSTIZ_TEMPORAL_GUARD_STATUS="helper-installed-for-later"
        msg_skip "TEMPORAL NOT DEPLOYED YET; GUARD HELPER INSTALLED FOR LATER"
        echo -e "${YW}After yml 06 Temporal is deployed and before yml 07 Postiz is started, run:${CL}"
        echo -e " ${GN}${POSTIZ_TEMPORAL_GUARD_PATH}${CL}"
        return 0
    fi

    msg_info "Running Postiz Temporal guard against existing Temporal container"

    POSTIZ_TEMPORAL_GUARD_RUN="yes"

    if [ -n "$SUDO_CMD" ]; then
        if "$SUDO_CMD" "$POSTIZ_TEMPORAL_GUARD_PATH"; then
            POSTIZ_TEMPORAL_GUARD_STATUS="passed"
            msg_ok "POSTIZ TEMPORAL GUARD PASSED"
        else
            POSTIZ_TEMPORAL_GUARD_STATUS="failed"
            msg_error "Postiz Temporal guard failed. Check Temporal/Postiz logs before deploying Postiz."
        fi
    else
        if "$POSTIZ_TEMPORAL_GUARD_PATH"; then
            POSTIZ_TEMPORAL_GUARD_STATUS="passed"
            msg_ok "POSTIZ TEMPORAL GUARD PASSED"
        else
            POSTIZ_TEMPORAL_GUARD_STATUS="failed"
            msg_error "Postiz Temporal guard failed. Check Temporal/Postiz logs before deploying Postiz."
        fi
    fi
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
# Downloads yml 00, yml 01 and the Admin UI bootstrap override from GitHub into docker/compose.
function download_bootstrap_compose_files() {
    section "STACK COMPOSE DOWNLOAD"

    msg_info "Downloading Socket Proxy stack compose"
    curl -fsSL "$YML_00_URL" -o "${COMPOSE_DIR}/${YML_00_NAME}"
    YML_00_DOWNLOADED="yes"
    msg_ok "SOCKET PROXY STACK COMPOSE DOWNLOADED"

    case "$ADMIN_UI" in
        portainer)
            msg_info "Downloading Portainer stack compose"
            curl -fsSL "$YML_01_URL" -o "${COMPOSE_DIR}/${YML_01_NAME}"
            YML_01_DOWNLOADED="yes"
            msg_ok "PORTAINER STACK COMPOSE DOWNLOADED"

            msg_info "Downloading Admin UI bootstrap override"
            curl -fsSL "$YML_01_OVERRIDE_URL" -o "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
            YML_01_OVERRIDE_DOWNLOADED="yes"
            msg_ok "PORTAINER BOOTSTRAP OVERRIDE DOWNLOADED"
            ;;
        dockge)
            msg_info "Downloading Dockge stack compose"
            curl -fsSL "$YML_DOCKGE_URL" -o "${COMPOSE_DIR}/${YML_DOCKGE_NAME}"
            YML_DOCKGE_DOWNLOADED="yes"
            msg_ok "DOCKGE STACK COMPOSE DOWNLOADED"

            msg_info "Downloading Dockge bootstrap override"
            curl -fsSL "$YML_DOCKGE_OVERRIDE_URL" -o "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
            YML_DOCKGE_OVERRIDE_DOWNLOADED="yes"
            msg_ok "DOCKGE BOOTSTRAP OVERRIDE DOWNLOADED"
            ;;
        komodo)
            msg_info "Downloading Komodo stack compose"
            curl -fsSL "$YML_KOMODO_URL" -o "${COMPOSE_DIR}/${YML_KOMODO_NAME}"
            YML_KOMODO_DOWNLOADED="yes"
            msg_ok "KOMODO STACK COMPOSE DOWNLOADED"

            msg_info "Downloading Komodo bootstrap override"
            curl -fsSL "$YML_KOMODO_OVERRIDE_URL" -o "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
            YML_KOMODO_OVERRIDE_DOWNLOADED="yes"
            msg_ok "KOMODO BOOTSTRAP OVERRIDE DOWNLOADED"
            ;;
    esac

    ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN="downloaded"

    run_cmd "setting Socket Proxy compose file ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "${COMPOSE_DIR}/${YML_00_NAME}"
    run_cmd "setting Socket Proxy compose file permissions" chmod 640 "${COMPOSE_DIR}/${YML_00_NAME}"
    run_cmd "setting ${ADMIN_UI_DISPLAY_NAME} compose ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$ADMIN_UI_COMPOSE_FILE" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
    run_cmd "setting ${ADMIN_UI_DISPLAY_NAME} compose permissions" chmod 640 "$ADMIN_UI_COMPOSE_FILE" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"

    if declare -F retire_yml_12_docker_gc >/dev/null 2>&1; then
        retire_yml_12_docker_gc
    fi

    detail_line "Socket Proxy stack" "${COMPOSE_DIR}/${YML_00_NAME}"
    detail_line "Admin UI stack" "$ADMIN_UI_COMPOSE_FILE"
    detail_line "Admin UI bootstrap override" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
}
# --- 37. PORTAINER BOOTSTRAP OVERRIDE CHECK ---
# Confirms the downloaded Admin UI bootstrap override exists locally.
# Script 7 should later redeploy Portainer without this override to close the bootstrap port.
function verify_admin_ui_bootstrap_override_file() {
    section "ADMIN UI BOOTSTRAP OVERRIDE"

    msg_info "Checking ${ADMIN_UI_DISPLAY_NAME} bootstrap override"

    if [ ! -f "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE" ]; then
        msg_error "${ADMIN_UI_DISPLAY_NAME} bootstrap override was not downloaded: ${ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE}"
    fi

    ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN="downloaded"
    msg_ok "${ADMIN_UI_DISPLAY_NAME^^} BOOTSTRAP OVERRIDE READY"
    detail_line "Override file" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
    detail_line "Bootstrap port" "${ADMIN_UI_BOOTSTRAP_PORT}->${ADMIN_UI_INTERNAL_PORT}"
}


# --- 38. COMPOSE CONFIG VALIDATION ---
# Validates yml 00, yml 01 and the Admin UI bootstrap override before deployment.
function validate_bootstrap_compose_files() {
    section "STACK COMPOSE VALIDATION"

    msg_info "Validating Socket Proxy stack compose"
    run_docker_cmd "validating Socket Proxy stack compose" compose --env-file "$ENV_FILE" -p socket-proxy -f "${COMPOSE_DIR}/${YML_00_NAME}" config -q
    msg_ok "SOCKET PROXY STACK COMPOSE VALID"

    msg_info "Validating ${ADMIN_UI_DISPLAY_NAME} stack compose with bootstrap override"
    export PORTAINER_BOOTSTRAP_PORT DOCKGE_BOOTSTRAP_PORT KOMODO_BOOTSTRAP_PORT ADMIN_UI_BOOTSTRAP_BIND
    run_docker_cmd "validating ${ADMIN_UI_DISPLAY_NAME} stack compose" compose --env-file "$ENV_FILE" -p "$ADMIN_UI_PROJECT_NAME" -f "$ADMIN_UI_COMPOSE_FILE" -f "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE" config -q
    msg_ok "${ADMIN_UI_DISPLAY_NAME^^} STACK COMPOSE VALID"

    ADMIN_UI_VALIDATED="yes"
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
function deploy_admin_ui() {
    section "DEPLOY STACK - ${ADMIN_UI_DISPLAY_NAME}"

    export PORTAINER_BOOTSTRAP_PORT DOCKGE_BOOTSTRAP_PORT KOMODO_BOOTSTRAP_PORT ADMIN_UI_BOOTSTRAP_BIND
    msg_info "Deploying ${ADMIN_UI_DISPLAY_NAME} with bootstrap port"
    run_docker_cmd "deploying ${ADMIN_UI_DISPLAY_NAME}" compose --env-file "$ENV_FILE" -p "$ADMIN_UI_PROJECT_NAME" -f "$ADMIN_UI_COMPOSE_FILE" -f "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE" up -d
    ADMIN_UI_DEPLOYED="yes"

    if [ "$ADMIN_UI" == "portainer" ]; then
        PORTAINER_DEPLOYED="yes"
    fi

    msg_ok "${ADMIN_UI_DISPLAY_NAME^^} DEPLOYED"
}

# --- 41. UFW BOOTSTRAP PORT HELPER ---
# Opens temporary Admin UI bootstrap port if UFW is active.
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

    msg_info "Allowing temporary ${ADMIN_UI_DISPLAY_NAME} bootstrap port ${ADMIN_UI_BOOTSTRAP_PORT}/tcp"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" ufw allow "${ADMIN_UI_BOOTSTRAP_PORT}/tcp" comment "temporary ${ADMIN_UI_DISPLAY_NAME} bootstrap" >/dev/null 2>&1 || true
    else
        ufw allow "${ADMIN_UI_BOOTSTRAP_PORT}/tcp" comment "temporary ${ADMIN_UI_DISPLAY_NAME} bootstrap" >/dev/null 2>&1 || true
    fi

    UFW_BOOTSTRAP_PORT_OPENED="yes"
    msg_ok "TEMPORARY ${ADMIN_UI_DISPLAY_NAME^^} BOOTSTRAP PORT ALLOWED"
}

# =========================================================
#  VERIFICATION / SUMMARY
# =========================================================

# --- 42. ACCESS IP DETECTION ---
# Detects a likely LAN IPv4 for the Admin UI bootstrap URL.
function detect_admin_ui_access_ip() {
    local detected_ip=""

    detected_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)"

    if [ -z "$detected_ip" ]; then
        detected_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    fi

    ADMIN_UI_BOOTSTRAP_ACCESS_IP="${detected_ip:-127.0.0.1}"
    ADMIN_UI_BOOTSTRAP_ACCESS_URL="${ADMIN_UI_BOOTSTRAP_SCHEME}://${ADMIN_UI_BOOTSTRAP_ACCESS_IP}:${ADMIN_UI_BOOTSTRAP_PORT}"
    PORTAINER_ACCESS_URL="$ADMIN_UI_BOOTSTRAP_ACCESS_URL"
}

function detect_portainer_access_ip() {
    detect_admin_ui_access_ip
}

# --- 43. CONTAINER VERIFICATION ---
# Verifies the bootstrap containers are running and visible.
function verify_bootstrap_containers() {
    section "BOOTSTRAP VERIFICATION"

    msg_info "Checking Socket Proxy container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'socket-proxy'; then
        msg_ok "SOCKET PROXY RUNNING"
    else
        msg_error "socket-proxy container is not running."
    fi

    msg_info "Checking ${ADMIN_UI_DISPLAY_NAME} container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx "$ADMIN_UI_SERVICE_NAME"; then
        msg_ok "${ADMIN_UI_DISPLAY_NAME^^} RUNNING"
    else
        msg_error "${ADMIN_UI_SERVICE_NAME} container is not running."
    fi

    detect_admin_ui_access_ip

    msg_info "Checking ${ADMIN_UI_DISPLAY_NAME} bootstrap port"
    if docker_cmd port "$ADMIN_UI_SERVICE_NAME" "${ADMIN_UI_INTERNAL_PORT}/tcp" 2>/dev/null | grep -q ":${ADMIN_UI_BOOTSTRAP_PORT}$"; then
        ADMIN_UI_BOOTSTRAP_PORT_EXPOSED="yes"
        ADMIN_UI_BOOTSTRAP_PORT_EXPOSED="yes"
        msg_ok "${ADMIN_UI_DISPLAY_NAME^^} BOOTSTRAP PORT EXPOSED"
    else
        ADMIN_UI_BOOTSTRAP_PORT_EXPOSED="not-confirmed"
        ADMIN_UI_BOOTSTRAP_PORT_EXPOSED="not-confirmed"
        msg_warn "${ADMIN_UI_DISPLAY_NAME} is running, but bootstrap port ${ADMIN_UI_BOOTSTRAP_PORT} was not confirmed"
    fi

    detail_line "Temporary access" "$ADMIN_UI_BOOTSTRAP_ACCESS_URL"
    detail_line "Domain access after Traefik/AuthentiK" "$ADMIN_UI_URL"
    detail_line "Bootstrap port" "$ADMIN_UI_BOOTSTRAP_PORT"
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
        echo "${YML_DOCKGE_NAME}: ${YML_DOCKGE_DOWNLOADED}"
        echo "${YML_KOMODO_NAME}: ${YML_KOMODO_DOWNLOADED}"
        echo "Admin UI bootstrap override: ${ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN}"
        echo ""
        echo "Deployments:"
        echo "socket-proxy deployed: ${SOCKET_PROXY_DEPLOYED}"
        echo "admin UI: ${ADMIN_UI}"
        echo "admin UI validated: ${ADMIN_UI_VALIDATED}"
        echo "admin UI deployed: ${ADMIN_UI_DEPLOYED}"
        echo "portainer deployed: ${PORTAINER_DEPLOYED}"
        echo "Admin UI bootstrap port exposed: ${ADMIN_UI_BOOTSTRAP_PORT_EXPOSED}"
        echo "UFW bootstrap port opened: ${UFW_BOOTSTRAP_PORT_OPENED}"
        echo "Admin UI temporary URL: ${PORTAINER_ACCESS_URL}"
        echo "Admin UI host: ${ADMIN_UI_HOST}"
        echo ""
        echo "Preflight checks:"
        echo "vm.overcommit_memory=1: ${SYSCTL_REDIS_OK}"
        echo "Traefik placeholders rendered: ${TRAEFIK_PLACEHOLDERS_OK}"
        echo "Traefik DNS v3.7 syntax: ${TRAEFIK_DNS_DELAY_OK}"
        echo "Traefik encoded characters: ${TRAEFIK_ENCODED_CHARS_OK}"
        echo "Traefik authentik references: ${TRAEFIK_AUTHENTIK_REFERENCES_OK}"
        echo "Authentik folders: ${AUTHENTIK_FOLDERS_OK}"
        echo "Temporal compose: ${TEMPORAL_COMPOSE_OK}"
        echo "CF companion secret: ${CF_COMPANION_SECRET_OK}"
        echo "Filebrowser folders: ${FILEBROWSER_FOLDERS_OK}"
        echo "Postiz Temporal guard installed: ${POSTIZ_TEMPORAL_GUARD_INSTALLED}"
        echo "Postiz Temporal guard run: ${POSTIZ_TEMPORAL_GUARD_RUN}"
        echo "Postiz Temporal guard status: ${POSTIZ_TEMPORAL_GUARD_STATUS}"
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
Dockge compose downloaded: $YML_DOCKGE_DOWNLOADED
Komodo compose downloaded: $YML_KOMODO_DOWNLOADED
Socket proxy deployed: $SOCKET_PROXY_DEPLOYED
Admin UI: $ADMIN_UI
Admin UI validated: $ADMIN_UI_VALIDATED
Admin UI deployed: $ADMIN_UI_DEPLOYED
Portainer deployed: $PORTAINER_DEPLOYED
Admin UI bootstrap override: $ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN
Admin UI bootstrap port: $ADMIN_UI_BOOTSTRAP_PORT
Admin UI bootstrap port exposed: $ADMIN_UI_BOOTSTRAP_PORT_EXPOSED
UFW bootstrap port opened: $UFW_BOOTSTRAP_PORT_OPENED
Admin UI temporary URL: $ADMIN_UI_BOOTSTRAP_ACCESS_URL
vm.overcommit_memory OK: $SYSCTL_REDIS_OK
Traefik placeholders OK: $TRAEFIK_PLACEHOLDERS_OK
Traefik DNS v3.7 OK: $TRAEFIK_DNS_DELAY_OK
Traefik encoded characters OK: $TRAEFIK_ENCODED_CHARS_OK
Traefik authentik references OK: $TRAEFIK_AUTHENTIK_REFERENCES_OK
Authentik folders OK: $AUTHENTIK_FOLDERS_OK
Temporal compose OK: $TEMPORAL_COMPOSE_OK
CF companion secret OK: $CF_COMPANION_SECRET_OK
Filebrowser folders OK: $FILEBROWSER_FOLDERS_OK
Postiz Temporal guard installed: $POSTIZ_TEMPORAL_GUARD_INSTALLED
Postiz Temporal guard run: $POSTIZ_TEMPORAL_GUARD_RUN
Postiz Temporal guard status: $POSTIZ_TEMPORAL_GUARD_STATUS
Postiz Temporal guard path: $POSTIZ_TEMPORAL_GUARD_PATH
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
Dockge compose downloaded: $YML_DOCKGE_DOWNLOADED
Komodo compose downloaded: $YML_KOMODO_DOWNLOADED
Socket proxy deployed: $SOCKET_PROXY_DEPLOYED
Admin UI: $ADMIN_UI
Admin UI validated: $ADMIN_UI_VALIDATED
Admin UI deployed: $ADMIN_UI_DEPLOYED
Portainer deployed: $PORTAINER_DEPLOYED
Admin UI bootstrap override: $ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN
Admin UI bootstrap port: $ADMIN_UI_BOOTSTRAP_PORT
Admin UI bootstrap port exposed: $ADMIN_UI_BOOTSTRAP_PORT_EXPOSED
UFW bootstrap port opened: $UFW_BOOTSTRAP_PORT_OPENED
Admin UI temporary URL: $ADMIN_UI_BOOTSTRAP_ACCESS_URL
vm.overcommit_memory OK: $SYSCTL_REDIS_OK
Traefik placeholders OK: $TRAEFIK_PLACEHOLDERS_OK
Traefik DNS v3.7 OK: $TRAEFIK_DNS_DELAY_OK
Traefik encoded characters OK: $TRAEFIK_ENCODED_CHARS_OK
Traefik authentik references OK: $TRAEFIK_AUTHENTIK_REFERENCES_OK
Authentik folders OK: $AUTHENTIK_FOLDERS_OK
Temporal compose OK: $TEMPORAL_COMPOSE_OK
CF companion secret OK: $CF_COMPANION_SECRET_OK
Filebrowser folders OK: $FILEBROWSER_FOLDERS_OK
Postiz Temporal guard installed: $POSTIZ_TEMPORAL_GUARD_INSTALLED
Postiz Temporal guard run: $POSTIZ_TEMPORAL_GUARD_RUN
Postiz Temporal guard status: $POSTIZ_TEMPORAL_GUARD_STATUS
Postiz Temporal guard path: $POSTIZ_TEMPORAL_GUARD_PATH
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
    detail_line "ADMIN UI" "$ADMIN_UI"
    detail_line "ADMIN UI COMPOSE" "$ADMIN_UI_COMPOSE_FILE"
    detail_line "ADMIN UI HOST" "$ADMIN_UI_HOST"
    detail_line "REDIS SYSCTL" "$SYSCTL_REDIS_OK"
    detail_line "TRAEFIK PLACEHOLDERS" "$TRAEFIK_PLACEHOLDERS_OK"
    detail_line "TRAEFIK DNS V3.7" "$TRAEFIK_DNS_DELAY_OK"
    detail_line "TRAEFIK ENCODED CHARS" "$TRAEFIK_ENCODED_CHARS_OK"
    detail_line "AUTHENTIK FOLDERS" "$AUTHENTIK_FOLDERS_OK"
    detail_line "TEMPORAL COMPOSE" "$TEMPORAL_COMPOSE_OK"
    detail_line "FILEBROWSER FOLDERS" "$FILEBROWSER_FOLDERS_OK"
    detail_line "POSTIZ TEMPORAL GUARD" "$POSTIZ_TEMPORAL_GUARD_STATUS"
    detail_line "GUARD COMMAND" "$POSTIZ_TEMPORAL_GUARD_PATH"
    detail_line "Admin UI temporary URL" "$ADMIN_UI_BOOTSTRAP_ACCESS_URL"
    detail_line "Bootstrap port" "$ADMIN_UI_BOOTSTRAP_PORT"
    detail_line "Verify log" "$VERIFY_LOG"

    echo ""
    if [ "$ADMIN_UI" == "portainer" ]; then
        echo -e "${YW}Portainer is temporarily exposed directly for bootstrap access.${CL}"
        echo -e "${YW}After Traefik/AuthentiK deployment is stable, run Script 7 to close this direct port and harden sudo/Docker access.${CL}"
    else
        echo -e "${YW}${ADMIN_UI} is deployed behind Traefik/AuthentiK labels with no direct bootstrap port.${CL}"
    fi
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}Deploy/verify remaining stacks in order. After yml 06 Temporal starts and before yml 07 Postiz, run:${CL}"
    echo -e "${GN}${POSTIZ_TEMPORAL_GUARD_PATH}${CL}"
    echo -e "${YW}Do not restart Temporal after the guard runs. Then deploy/start Postiz and finally run Script 7.${CL}"
    echo ""
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 47. MAIN FUNCTION ---
# Runs Docker network + socket-proxy + Admin UI bootstrap in safe order.
function main() {
    init_script

    detect_docker_access
    check_previous_marker
    start_confirmation
    collect_bootstrap_settings
    validate_project_paths
    verify_admin_ui_selection

    verify_redis_host_tuning
    verify_traefik_rendered_configs
    verify_authentik_folders
    verify_temporal_compose_settings
    verify_cf_companion_secret_file
    verify_filebrowser_folders
    install_postiz_temporal_guard

    create_shared_networks
    verify_shared_networks

    download_bootstrap_compose_files
    verify_admin_ui_bootstrap_override_file
    validate_bootstrap_compose_files

    configure_bootstrap_firewall
    deploy_socket_proxy
    deploy_admin_ui
    verify_bootstrap_containers
    run_postiz_temporal_guard_if_ready

    create_verification_report
    write_completion_marker
    show_final_summary

    exit 0
}

main "$@"
