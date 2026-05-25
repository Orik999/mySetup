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

SCRIPT_SOURCE="6.5-stackDeployVerify.sh"
SCRIPT_VERSION="v1.3.29"
SCRIPT_UPDATED="2026-05-25"
SCRIPT_BUILD="postgres-redis-process-owner-authentik-wait-function-restored"

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
TRAEFIK_TEMPLATE_RAW_BASE="${TRAEFIK_TEMPLATE_RAW_BASE:-https://raw.githubusercontent.com/Orik999/mySetup/main/docker/traefik}"
TRAEFIK_STATIC_TEMPLATE_URL="${TRAEFIK_STATIC_TEMPLATE_URL:-${TRAEFIK_TEMPLATE_RAW_BASE}/traefik.yml.template}"
TRAEFIK_DYNAMIC_TEMPLATE_URL="${TRAEFIK_DYNAMIC_TEMPLATE_URL:-${TRAEFIK_TEMPLATE_RAW_BASE}/dynamic-config.yml.template}"
SOCKET_PROXY_STACK_FILE="00-socket-proxy-compose.yml"
PORTAINER_STACK_FILE="01-[4]-portainer-compose.yml"
PORTAINER_BOOTSTRAP_OVERRIDE_FILE_NAME="01-[4]-portainer-bootstrap-override.yml"
DOCKGE_STACK_FILE="01-[1]-dockge-compose.yml"
KOMODO_STACK_FILE="01-[3]-komodo-compose.yml"
DOCKHAND_STACK_FILE="01-[2]-dockhand-compose.yml"

# Optional environment overrides for advanced/testing workflows.
# If these are not set, URLs are rebuilt from GITHUB_RAW_BASE after user input.
SOCKET_PROXY_STACK_URL_OVERRIDE="${SOCKET_PROXY_STACK_URL:-}"
PORTAINER_STACK_URL_OVERRIDE="${PORTAINER_STACK_URL:-}"
PORTAINER_BOOTSTRAP_OVERRIDE_URL_OVERRIDE="${PORTAINER_BOOTSTRAP_OVERRIDE_URL:-}"
DOCKGE_STACK_URL_OVERRIDE="${DOCKGE_STACK_URL:-}"
DOCKGE_BOOTSTRAP_OVERRIDE_FILE_NAME="01-[1]-dockge-bootstrap-override.yml"
DOCKGE_BOOTSTRAP_OVERRIDE_URL_OVERRIDE="${DOCKGE_BOOTSTRAP_OVERRIDE_URL:-}"
KOMODO_STACK_URL_OVERRIDE="${KOMODO_STACK_URL:-}"
KOMODO_BOOTSTRAP_OVERRIDE_FILE_NAME="01-[3]-komodo-bootstrap-override.yml"
KOMODO_BOOTSTRAP_OVERRIDE_URL_OVERRIDE="${KOMODO_BOOTSTRAP_OVERRIDE_URL:-}"
DOCKHAND_STACK_URL_OVERRIDE="${DOCKHAND_STACK_URL:-}"
DOCKHAND_BOOTSTRAP_OVERRIDE_FILE_NAME="01-[2]-dockhand-bootstrap-override.yml"
DOCKHAND_BOOTSTRAP_OVERRIDE_URL_OVERRIDE="${DOCKHAND_BOOTSTRAP_OVERRIDE_URL:-}"
SOCKET_PROXY_STACK_URL="${SOCKET_PROXY_STACK_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${SOCKET_PROXY_STACK_FILE}}"
PORTAINER_STACK_URL="${PORTAINER_STACK_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${PORTAINER_STACK_FILE}}"
PORTAINER_BOOTSTRAP_OVERRIDE_URL="${PORTAINER_BOOTSTRAP_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${PORTAINER_BOOTSTRAP_OVERRIDE_FILE_NAME}}"
DOCKGE_STACK_URL="${DOCKGE_STACK_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${DOCKGE_STACK_FILE}}"
DOCKGE_BOOTSTRAP_OVERRIDE_URL="${DOCKGE_BOOTSTRAP_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${DOCKGE_BOOTSTRAP_OVERRIDE_FILE_NAME}}"
KOMODO_STACK_URL="${KOMODO_STACK_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${KOMODO_STACK_FILE}}"
KOMODO_BOOTSTRAP_OVERRIDE_URL="${KOMODO_BOOTSTRAP_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${KOMODO_BOOTSTRAP_OVERRIDE_FILE_NAME}}"
DOCKHAND_STACK_URL="${DOCKHAND_STACK_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${DOCKHAND_STACK_FILE}}"
DOCKHAND_BOOTSTRAP_OVERRIDE_URL="${DOCKHAND_BOOTSTRAP_OVERRIDE_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${DOCKHAND_BOOTSTRAP_OVERRIDE_FILE_NAME}}"


# Fixed project stack registry. No GitHub directory scanning is used.
POSTGRES_STACK_FILE="02-postgres-compose.yml"
REDIS_STACK_FILE="03-redis-compose.yml"
TRAEFIK_STACK_FILE="04-traefik-compose.yml"
AUTHENTIK_STACK_FILE="05-authentik-compose.yml"
TEMPORAL_STACK_FILE="06-temporal-compose.yml"
POSTIZ_TEMPORAL_GUARD_STACK_FILE="07-postiz-temporal-guard-compose.yml"
POSTIZ_STACK_FILE="08-postiz-compose.yml"
CF_DDNS_STACK_FILE="09-cf-ddns-compose.yml"
CF_COMPANION_STACK_FILE="10-cf-companion-compose.yml"
VSCODE_STACK_FILE="11-vscode-compose.yml"
FILEBROWSER_STACK_FILE="12-filebrowser-compose.yml"

DEPLOY_POSTIZ="n"
DEPLOY_CF_DDNS="n"
DEPLOY_CF_COMPANION="n"
DEPLOY_VSCODE="n"
DEPLOY_FILEBROWSER="n"

SELECTED_STACK_FILES=()
SELECTED_STACK_PROJECTS=()
SELECTED_STACK_SERVICES=()
DEPENDENCY_REASONS=()

SOCKET_PROXY_SUBNET_EXPECTED="192.168.91.0/24"
T2_PROXY_SUBNET_EXPECTED="192.168.90.0/24"
SOCKET_PROXY_SUBNET_ACTUAL=""
T2_PROXY_SUBNET_ACTUAL=""
DATABASE_NETWORK_NAME=""

PORTAINER_BOOTSTRAP_PORT="${PORTAINER_BOOTSTRAP_PORT:-9443}"
DOCKGE_BOOTSTRAP_PORT="${DOCKGE_BOOTSTRAP_PORT:-5001}"
KOMODO_BOOTSTRAP_PORT="${KOMODO_BOOTSTRAP_PORT:-9120}"
DOCKHAND_BOOTSTRAP_PORT="${DOCKHAND_BOOTSTRAP_PORT:-3000}"
ADMIN_UI_BOOTSTRAP_BIND="${ADMIN_UI_BOOTSTRAP_BIND:-0.0.0.0}"
ADMIN_UI_BOOTSTRAP_PORT=""
ADMIN_UI_INTERNAL_PORT=""
ADMIN_UI_BOOTSTRAP_SCHEME="http"
ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME=""
ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE=""
ADMIN_UI_BOOTSTRAP_ACCESS_IP=""
ADMIN_UI_BOOTSTRAP_ACCESS_URL=""

ADMIN_UI="${ADMIN_UI:-dockge}"
ADMIN_UI_DISPLAY_NAME="Dockge"
ADMIN_UI_SERVICE_NAME="dockge"
ADMIN_UI_COMPOSE_FILE=""
ADMIN_UI_PROJECT_NAME="dockge"
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
TRAEFIK_DASHBOARD_HOST=""
PROXMOX_ROUTE_ENABLED="n"
PROXMOX_HOST=""
PROXMOX_URL=""
CF_API_EMAIL_VALUE=""

SYSCTL_REDIS_OK="no"
TRAEFIK_PLACEHOLDERS_OK="no"
TRAEFIK_DNS_DELAY_OK="no"
TRAEFIK_ENCODED_CHARS_OK="no"
TRAEFIK_AUTHENTIK_REFERENCES_OK="no"
AUTHENTIK_FOLDERS_OK="no"
AUTHENTIK_DEPENDENCIES_OK="not-run"
AUTHENTIK_API_OK="not-run"
AUTHENTIK_PROVIDER_OK="not-run"
AUTHENTIK_APPLICATION_OK="not-run"
AUTHENTIK_OUTPOST_ATTACH_OK="not-run"
AUTHENTIK_OUTPOST_302_OK="not-run"
PROTECTED_ROUTE_VERIFY_OK="not-run"
AUTHENTIK_HOST_ROUTE_OK="not-run"
AUTHENTIK_API_TOKEN="${AUTHENTIK_API_TOKEN:-}"
AUTHENTIK_API_BASE=""
CF_COMPANION_SECRET_OK="skipped"
FILEBROWSER_FOLDERS_OK="skipped"
SUDO_CMD=""
DOCKER_NEEDS_SUDO="no"
DOCKERHUB_LOGIN_ATTEMPTED="no"
TEMP_FILES=()

NETWORKS_CREATED="no"
NETWORKS_VERIFIED="no"
SOCKET_PROXY_STACK_DOWNLOADED="no"
PORTAINER_STACK_DOWNLOADED="no"
PORTAINER_BOOTSTRAP_OVERRIDE_DOWNLOADED="no"
DOCKGE_STACK_DOWNLOADED="no"
DOCKGE_BOOTSTRAP_OVERRIDE_DOWNLOADED="no"
KOMODO_STACK_DOWNLOADED="no"
KOMODO_BOOTSTRAP_OVERRIDE_DOWNLOADED="no"
DOCKHAND_STACK_DOWNLOADED="no"
DOCKHAND_BOOTSTRAP_OVERRIDE_DOWNLOADED="no"
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

# --- SCRIPT VERSION DISPLAY ---
# Prints the currently running script version immediately under the ASCII banner.
function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

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

    # Text/path/name/domain/URL prompts are deliberately NOT timed.
    # Countdown prompts are reserved only for simple Y/n decisions.
    answer="$(editable_input_loop "$prompt" "$default" "")"
    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
    flush_input_buffer 2>/dev/null || true

    echo "$answer"
}

# --- 19A. SENSITIVE LINE INPUT HELPER ---
# Reads secret/token input without echoing it and without printing the value back to logs.
function sensitive_line_input() {
    local prompt="$1"
    local answer=""

    flush_input_buffer 2>/dev/null || true

    if [ -r /dev/tty ]; then
        tty_print "${YW}${prompt}: ${CL}"
        IFS= read -rs answer < /dev/tty || true
        tty_println ""
    else
        echo -ne "${YW}${prompt}: ${CL}" >&2
        IFS= read -rs answer || true
        echo "" >&2
    fi

    flush_input_buffer 2>/dev/null || true
    printf '%s' "$answer"
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
    show_script_version

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

# --- 28A. TRANSIENT LINE CLEAR HELPER ---
# Clears short live/progress messages after the operation completes.
function clear_transient_line() {
    tty_print "${BFR}"
}

# --- 28B. DOCKER CREDENTIAL STORE PATH HELPER ---
# Reports the Docker config path used by docker login without exposing credentials.
function docker_config_path_hint() {
    if [ "$DOCKER_NEEDS_SUDO" == "yes" ]; then
        echo "/root/.docker/config.json"
    else
        echo "${HOME:-/home/${DOCKER_USER}}/.docker/config.json"
    fi
}

# --- 29. DOCKER HUB RATE-LIMIT DETECTION ---
# Detects Docker Hub anonymous pull throttling and offers a secure docker login retry only when needed.
function is_dockerhub_rate_limit_error() {
    local err_file="$1"

    grep -Eiq \
        'toomanyrequests|unauthenticated pull rate limit|You have reached your unauthenticated pull rate limit|increase-rate-limit|docker\.com/increase-rate-limit' \
        "$err_file"
}


# --- 29A.1. DOCKER IMAGE EXTRACTION ERROR DETECTION ---
# Detects local Docker/containerd snapshot extraction corruption separately from compose/YAML errors.
function is_docker_layer_extract_error() {
    local err_file="$1"

    grep -Eiq         'failed to extract layer|failed to extract|containerd\.io\.containerd\.snapshotter|overlayfs|no such file or directory.*snapshot|no such file or directory.*layer'         "$err_file"
}

# --- 29A.2. DOCKER IMAGE EXTRACTION ERROR EXPLANATION ---
# Shows a targeted explanation when Docker/containerd fails while extracting pulled image layers.
function explain_docker_layer_extract_error() {
    local description="$1"
    local err_file="$2"

    echo ""
    echo -e "${RD}Docker image extraction failed during:${CL} ${description}"
    echo -e "${YW}This is usually a local Docker/containerd snapshot or partially-extracted image problem, not a compose path/YAML problem.${CL}"
    echo -e "${YW}Common fix: remove the failed image/container, restart Docker, then rerun Script 6.5.${CL}"
    echo ""
    echo -e "${BL}Suggested safe checks/fixes:${CL}"
    echo -e "${YW}docker compose -p postiz down${CL}"
    echo -e "${YW}docker image rm ghcr.io/gitroomhq/postiz-app:latest 2>/dev/null || true${CL}"
    echo -e "${YW}sudo systemctl restart docker${CL}"
    echo -e "${YW}Then rerun Script 6.5.${CL}"
    echo ""
    echo -e "${RD}Real error:${CL}"
    cat "$err_file"
}

# --- 29A. DOCKER HUB LOGIN / RETRY HELPER ---
# Uses Docker's own login prompt instead of collecting credentials in this script.
# This keeps passwords/tokens out of script variables and logs.
function offer_dockerhub_login_and_retry() {
    local description="$1"
    local err_file="$2"
    shift 2

    local login_yn=""
    local docker_username=""
    local config_hint=""

    echo ""
    msg_warn "DOCKER HUB RATE LIMIT DETECTED"
    echo -e "${YW}Docker Hub is throttling anonymous pulls from this IP. This is not a compose/YAML error.${CL}"
    echo -e "${YW}Login is only requested because the rate-limit error was detected.${CL}"
    echo -e "${BL}Tip:${CL} use your Docker Hub username and a Personal Access Token when Docker asks for a password."
    echo ""

    if [ "$DOCKERHUB_LOGIN_ATTEMPTED" == "yes" ]; then
        echo -e "${YW}Docker Hub login was already attempted once in this run.${CL}"
        return 1
    fi

    login_yn="$(timed_yes_no "Log in to Docker Hub now and retry this pull/deploy?" "y")"
    if [[ "$login_yn" =~ ^[Nn] ]]; then
        echo -e "${YW}Docker Hub login skipped. Run 'docker login' manually, then rerun Script 6.5.${CL}"
        return 1
    fi

    DOCKERHUB_LOGIN_ATTEMPTED="yes"

    echo ""
    echo -e "${YW}Starting Docker Hub login...${CL}"
    if ! docker_cmd login; then
        echo -e "${RD}Docker Hub login failed.${CL}"
        return 1
    fi

    docker_username="$(docker_cmd info --format '{{.Username}}' 2>/dev/null || true)"
    config_hint="$(docker_config_path_hint)"
    msg_ok "DOCKER HUB LOGIN SUCCEEDED"
    [ -n "$docker_username" ] && detail_line "Docker Hub user" "$docker_username"
    detail_line "Docker credentials file" "$config_hint"
    echo -e "${YW}Docker may store credentials unencrypted unless a credential helper is configured.${CL}"
    echo ""

    msg_info "Retrying failed Docker operation"
    : > "$err_file"
    if docker_cmd "$@" > /dev/null 2> "$err_file"; then
        msg_ok "RETRY SUCCEEDED: ${description^^}"
        return 0
    fi

    echo ""
    echo -e "${RD}Retry failed after Docker Hub login during:${CL} ${description}"
    echo -e "${YW}Command:${CL} docker $*"
    echo ""
    echo -e "${RD}Real error:${CL}"
    cat "$err_file"
    return 1
}

# --- 29B. DOCKER COMMAND RUNNER ---
# Runs docker commands quietly, with Docker Hub rate-limit detection and one secure login retry.
function run_docker_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    if ! docker_cmd "$@" > /dev/null 2> "$err_file"; then
        if is_dockerhub_rate_limit_error "$err_file"; then
            if offer_dockerhub_login_and_retry "$description" "$err_file" "$@"; then
                rm -f "$err_file"
                return 0
            fi
        fi

        if is_docker_layer_extract_error "$err_file"; then
            explain_docker_layer_extract_error "$description" "$err_file"
            rm -f "$err_file"
            exit 1
        fi

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


# --- 29B. CLEAN COMPOSE UP HELPER ---
# Runs docker compose up without terminal-flooding image pull/extract progress.
function compose_up_quiet() {
    local description="$1"
    shift

    msg_info "${description} (pulling/starting containers; this can take a few minutes)"

    if docker_cmd compose up --help 2>/dev/null | grep -q -- '--quiet-pull'; then
        run_docker_cmd "$description" compose "$@" up -d --quiet-pull
    else
        run_docker_cmd "$description" compose "$@" up -d
    fi

    clear_transient_line
}

# --- 29A. POSTIZ TEMPORAL GUARD RUNNER ---
# Runs the one-shot Temporal guard without hiding the container output. The guard
# is intentionally verbose because a failure here decides whether Postiz can start.
function run_postiz_temporal_guard_stack() {
    local project="$1"
    local file="$2"
    local guard_log=""
    local compose_path=""

    guard_log="$(mktemp)"
    TEMP_FILES+=("$guard_log")
    compose_path="$(compose_path_for_stack_file "$file")"

    msg_info "Running Postiz Temporal Guard from ${compose_path}"

    if docker_cmd compose --env-file "$ENV_FILE" -p "$project" -f "$compose_path" up --abort-on-container-exit --exit-code-from postiz-temporal-guard > "$guard_log" 2>&1; then
        clear_transient_line
        msg_ok "POSTIZ TEMPORAL GUARD COMPLETED"
        return 0
    fi

    if is_dockerhub_rate_limit_error "$guard_log"; then
        if offer_dockerhub_login_and_retry "running Postiz Temporal Guard" "$guard_log" compose --env-file "$ENV_FILE" -p "$project" -f "$compose_path" up --abort-on-container-exit --exit-code-from postiz-temporal-guard; then
            clear_transient_line
            msg_ok "POSTIZ TEMPORAL GUARD COMPLETED"
            return 0
        fi
    fi

    if is_docker_layer_extract_error "$guard_log"; then
        clear_transient_line
        explain_docker_layer_extract_error "running Postiz Temporal Guard" "$guard_log"
        exit 1
    fi

    clear_transient_line
    echo ""
    echo -e "${RD}Docker command failed during:${CL} running Postiz Temporal Guard"
    echo -e "${YW}Command:${CL} docker compose --env-file ${ENV_FILE} -p ${project} -f ${compose_path} up --abort-on-container-exit --exit-code-from postiz-temporal-guard"
    echo ""
    echo -e "${YW}Captured Postiz Temporal Guard output:${CL}"
    cat "$guard_log" 2>/dev/null || true
    echo ""
    echo -e "${YW}Postiz Temporal Guard container logs:${CL}"
    docker_cmd logs postiz-temporal-guard 2>/dev/null || true
    exit 1
}




# --- 29AA. ROOT FILE WRITE HELPER ---
# Writes stdin to a target path using sudo when needed.
function write_root_file() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" tee "$path" >/dev/null
    else
        cat > "$path"
    fi
}

# --- 29AB. TRAEFIK TEMPLATE DOWNLOAD HELPER ---
# Downloads public Traefik templates when Script 6 output is missing.
function download_file() {
    local url="$1"
    local dest="$2"

    curl --globoff -fsSL "$url" -o "$dest"
}

# --- 29AC. TRAEFIK PROXMOX ROUTE BLOCK HELPER ---
# Rebuilds the same dynamic file-provider Proxmox block generated by Script 6.
function build_proxmox_route_block() {
    cat <<EOF
  # -------------------------------------------------------
  # FILE-PROVIDER ROUTERS
  # -------------------------------------------------------
  routers:
    traefik-dashboard:
      entryPoints:
        - https
      rule: Host(\`${TRAEFIK_DASHBOARD_HOST}\`)
      middlewares:
        - chain-authentik@file
      tls: {}
      service: api@internal
EOF

    if [ "$PROXMOX_ROUTE_ENABLED" != "y" ]; then
        cat <<'EOF'

  # Proxmox routing was disabled during setup.
EOF
        return 0
    fi

    cat <<EOF

    proxmox:
      entryPoints:
        - https
      rule: Host(\`${PROXMOX_HOST}\`)
      middlewares:
        - chain-authentik@file
      tls: {}
      service: proxmox

  # -------------------------------------------------------
  # FILE-PROVIDER SERVICES
  # -------------------------------------------------------
  services:
    proxmox:
      loadBalancer:
        serversTransport: proxmoxTransport
        passHostHeader: true
        servers:
          - url: "${PROXMOX_URL}"

  # -------------------------------------------------------
  # TARGETED SERVER TRANSPORTS
  # -------------------------------------------------------
  serversTransports:
    proxmoxTransport:
      insecureSkipVerify: true
EOF
}

# --- 29AD. TRAEFIK TEMPLATE RENDER HELPER ---
# Renders public-safe placeholders without embedding raw Cloudflare tokens.
function render_traefik_template() {
    local src="$1"
    local dest="$2"
    local content=""
    local proxmox_block=""

    content="$(cat "$src")"
    proxmox_block="$(build_proxmox_route_block)"

    content="${content//\{\{DOCKER_DIR\}\}/$DOCKER_DIR}"
    content="${content//\{\{DOMAIN\}\}/$DOMAIN_VALUE}"
    content="${content//\{\{CF_API_EMAIL\}\}/$CF_API_EMAIL_VALUE}"
    content="${content//\{\{TRAEFIK_DASHBOARD_HOST\}\}/$TRAEFIK_DASHBOARD_HOST}"
    content="${content//\{\{TRAEFIK_ACME_EMAIL\}\}/$CF_API_EMAIL_VALUE}"
    content="${content//\{\{CF_API_TOKEN_SECRET_PATH\}\}//run/secrets/cf_api_token}"
    content="${content//\{\{HTPASSWD_SECRET_PATH\}\}//run/secrets/htpasswd}"
    content="${content//\{\{PROXMOX_ROUTE_BLOCK\}\}/$proxmox_block}"

    if grep -q '{{CF_API_TOKEN\|{{CLOUDFLARE_API_TOKEN' <<< "$content"; then
        msg_error "Traefik template contains a raw token placeholder. Use file-based token placeholders only."
    fi

    printf '%s\n' "$content" | write_root_file "$dest"
}

# --- 29AE. TRAEFIK CONFIG SELF-HEAL HELPER ---
# If Script 6 completed but Traefik config files are missing, rebuild them from the public templates.
function rebuild_missing_traefik_configs() {
    local tmp_dir=""
    local static_template=""
    local dynamic_template=""

    section "TRAEFIK TEMPLATE SELF-HEAL"

    msg_warn "Traefik rendered config files are missing. Attempting to rebuild them from templates."

    tmp_dir="$(mktemp -d /tmp/traefik-template-repair.XXXXXX)"
    TEMP_FILES+=("${tmp_dir}/traefik.yml.template" "${tmp_dir}/dynamic-config.yml.template")
    static_template="${tmp_dir}/traefik.yml.template"
    dynamic_template="${tmp_dir}/dynamic-config.yml.template"

    run_cmd "creating Traefik config directory" mkdir -p "$(dirname "$TRAEFIK_STATIC_CONFIG_FILE")"
    run_cmd "creating Traefik ACME directory" mkdir -p "$(dirname "$TRAEFIK_ACME_STORAGE")"
    run_cmd "creating Traefik ACME storage" touch "$TRAEFIK_ACME_STORAGE"

    msg_info "Downloading Traefik static template"
    download_file "$TRAEFIK_STATIC_TEMPLATE_URL" "$static_template" || msg_error "Failed to download Traefik static template: ${TRAEFIK_STATIC_TEMPLATE_URL}"
    msg_ok "TRAEFIK STATIC TEMPLATE DOWNLOADED"

    msg_info "Downloading Traefik dynamic template"
    download_file "$TRAEFIK_DYNAMIC_TEMPLATE_URL" "$dynamic_template" || msg_error "Failed to download Traefik dynamic template: ${TRAEFIK_DYNAMIC_TEMPLATE_URL}"
    msg_ok "TRAEFIK DYNAMIC TEMPLATE DOWNLOADED"

    msg_info "Rendering Traefik static config"
    render_traefik_template "$static_template" "$TRAEFIK_STATIC_CONFIG_FILE"
    msg_ok "TRAEFIK STATIC CONFIG REBUILT"

    msg_info "Rendering Traefik dynamic config"
    render_traefik_template "$dynamic_template" "$TRAEFIK_DYNAMIC_CONFIG_FILE"
    msg_ok "TRAEFIK DYNAMIC CONFIG REBUILT"

    run_cmd "setting Traefik config ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/appdata/traefik"
    run_cmd "setting Traefik config directory permissions" chmod 750 "$(dirname "$TRAEFIK_STATIC_CONFIG_FILE")"
    run_cmd "setting Traefik static config permissions" chmod 644 "$TRAEFIK_STATIC_CONFIG_FILE"
    run_cmd "setting Traefik dynamic config permissions" chmod 644 "$TRAEFIK_DYNAMIC_CONFIG_FILE"
    run_cmd "setting Traefik ACME directory permissions" chmod 700 "$(dirname "$TRAEFIK_ACME_STORAGE")"
    run_cmd "setting Traefik ACME storage permissions" chmod 600 "$TRAEFIK_ACME_STORAGE"

    rm -rf "$tmp_dir" 2>/dev/null || true
    msg_ok "TRAEFIK CONFIG SELF-HEAL COMPLETE"
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
    echo -e "${YW}Selected admin UI is read from ${ENV_FILE}: Dockge, Portainer CE, Komodo, or Dockhand.${CL}"
    echo ""

    start_yn="$(timed_yes_no "Start Docker Bootstrap Setup?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    return 0

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
    ENV_FILE="$(timed_text_input "Enter Docker .env path" "${DOCKER_DIR}/.env")"

    if [ -f "$ENV_FILE" ]; then
        # shellcheck disable=SC1090
        set -a
        . "$ENV_FILE"
        set +a
        DOCKER_DIR="${DOCKER_DIR:-$(env_value DOCKER_DIR)}"
        COMPOSE_DIR="${COMPOSE_DIR:-$(env_value COMPOSE_DIR)}"
    fi

    COMPOSE_DIR="$(timed_text_input "Enter Docker compose directory" "${COMPOSE_DIR:-${DOCKER_DIR}/compose}")"
    GITHUB_RAW_BASE="$(timed_text_input "Enter GitHub raw compose base" "$GITHUB_RAW_BASE")"

    export DOCKER_DIR COMPOSE_DIR ENV_FILE

    if ! validate_url "$GITHUB_RAW_BASE"; then
        msg_error "GitHub raw base is not a valid HTTP/HTTPS URL."
    fi

    if [ -z "$SOCKET_PROXY_STACK_URL_OVERRIDE" ]; then
        SOCKET_PROXY_STACK_URL="${GITHUB_RAW_BASE}/${SOCKET_PROXY_STACK_FILE}"
    fi

    if [ -z "$PORTAINER_STACK_URL_OVERRIDE" ]; then
        PORTAINER_STACK_URL="${GITHUB_RAW_BASE}/${PORTAINER_STACK_FILE}"
    fi

    if [ -z "$PORTAINER_BOOTSTRAP_OVERRIDE_URL_OVERRIDE" ]; then
        PORTAINER_BOOTSTRAP_OVERRIDE_URL="${GITHUB_RAW_BASE}/${PORTAINER_BOOTSTRAP_OVERRIDE_FILE_NAME}"
    fi

    if [ -z "$DOCKGE_STACK_URL_OVERRIDE" ]; then
        DOCKGE_STACK_URL="${GITHUB_RAW_BASE}/${DOCKGE_STACK_FILE}"
    fi

    if [ -z "$DOCKGE_BOOTSTRAP_OVERRIDE_URL_OVERRIDE" ]; then
        DOCKGE_BOOTSTRAP_OVERRIDE_URL="${GITHUB_RAW_BASE}/${DOCKGE_BOOTSTRAP_OVERRIDE_FILE_NAME}"
    fi

    if [ -z "$KOMODO_STACK_URL_OVERRIDE" ]; then
        KOMODO_STACK_URL="${GITHUB_RAW_BASE}/${KOMODO_STACK_FILE}"
    fi

    if [ -z "$KOMODO_BOOTSTRAP_OVERRIDE_URL_OVERRIDE" ]; then
        KOMODO_BOOTSTRAP_OVERRIDE_URL="${GITHUB_RAW_BASE}/${KOMODO_BOOTSTRAP_OVERRIDE_FILE_NAME}"
    fi

    if [ -z "$DOCKHAND_STACK_URL_OVERRIDE" ]; then
        DOCKHAND_STACK_URL="${GITHUB_RAW_BASE}/${DOCKHAND_STACK_FILE}"
    fi

    if [ -z "$DOCKHAND_BOOTSTRAP_OVERRIDE_URL_OVERRIDE" ]; then
        DOCKHAND_BOOTSTRAP_OVERRIDE_URL="${GITHUB_RAW_BASE}/${DOCKHAND_BOOTSTRAP_OVERRIDE_FILE_NAME}"
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

    # shellcheck disable=SC1090
    set -a
    . "$ENV_FILE"
    set +a

    DOCKER_DIR="${DOCKER_DIR:-$(env_value DOCKER_DIR)}"
    COMPOSE_DIR="${COMPOSE_DIR:-${DOCKER_DIR}/compose}"
    export DOCKER_DIR COMPOSE_DIR ENV_FILE

    DOMAIN_VALUE="$(env_value DOMAIN)"
    DOCKER_SECRETS_DIR="$(env_value DOCKER_SECRETS_DIR)"
    CF_API_TOKEN_FILE="$(env_value CF_API_TOKEN_FILE)"
    CF_API_EMAIL_VALUE="$(env_value CF_API_EMAIL)"
    TRAEFIK_DASHBOARD_HOST="$(env_value TRAEFIK_DASHBOARD_HOST)"
    [ -z "$TRAEFIK_DASHBOARD_HOST" ] && TRAEFIK_DASHBOARD_HOST="traefik.${DOMAIN_VALUE}"
    PROXMOX_ROUTE_ENABLED="$(env_value PROXMOX_ROUTE_ENABLED)"
    PROXMOX_ROUTE_ENABLED="${PROXMOX_ROUTE_ENABLED:-n}"
    PROXMOX_HOST="$(env_value PROXMOX_HOST)"
    PROXMOX_URL="$(env_value PROXMOX_URL)"
    ADMIN_UI="$(env_value ADMIN_UI)"
    ADMIN_UI="${ADMIN_UI:-dockge}"

    TRAEFIK_STATIC_CONFIG_FILE="$(env_value TRAEFIK_STATIC_CONFIG_FILE)"
    [ -z "$TRAEFIK_STATIC_CONFIG_FILE" ] && TRAEFIK_STATIC_CONFIG_FILE="${DOCKER_DIR}/appdata/traefik/traefik.yml"
    TRAEFIK_DYNAMIC_CONFIG_FILE="$(env_value TRAEFIK_DYNAMIC_CONFIG_FILE)"
    [ -z "$TRAEFIK_DYNAMIC_CONFIG_FILE" ] && TRAEFIK_DYNAMIC_CONFIG_FILE="${DOCKER_DIR}/appdata/traefik/dynamic-config.yml"
    TRAEFIK_ACME_STORAGE="$(env_value TRAEFIK_ACME_STORAGE)"
    [ -z "$TRAEFIK_ACME_STORAGE" ] && TRAEFIK_ACME_STORAGE="${DOCKER_DIR}/appdata/traefik/acme/acme.json"

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

    if [ ! -f "$TRAEFIK_STATIC_CONFIG_FILE" ] || [ ! -f "$TRAEFIK_DYNAMIC_CONFIG_FILE" ] || [ ! -f "$TRAEFIK_ACME_STORAGE" ]; then
        rebuild_missing_traefik_configs
    fi

    [ -f "$TRAEFIK_STATIC_CONFIG_FILE" ] || msg_error "Traefik static config missing after self-heal: ${TRAEFIK_STATIC_CONFIG_FILE}"
    [ -f "$TRAEFIK_DYNAMIC_CONFIG_FILE" ] || msg_error "Traefik dynamic config missing after self-heal: ${TRAEFIK_DYNAMIC_CONFIG_FILE}"
    [ -f "$TRAEFIK_ACME_STORAGE" ] || msg_error "Traefik acme.json missing after self-heal: ${TRAEFIK_ACME_STORAGE}"

    msg_info "Checking for unreplaced template placeholders"
    if grep -R '{{[^}]*}}' "$TRAEFIK_STATIC_CONFIG_FILE" "$TRAEFIK_DYNAMIC_CONFIG_FILE" >/dev/null 2>&1; then
        msg_error "Unrendered {{PLACEHOLDER}} values remain in Traefik config. Fix Script 6 render logic/templates."
    fi
    TRAEFIK_PLACEHOLDERS_OK="yes"
    msg_ok "TRAEFIK PLACEHOLDERS FULLY RENDERED"

    msg_info "Checking Traefik v3.7 DNS propagation syntax"
    if grep -q 'delayBefore''Checks' "$TRAEFIK_STATIC_CONFIG_FILE" && ! grep -q 'delayBefore''Check:' "$TRAEFIK_STATIC_CONFIG_FILE"; then
        TRAEFIK_DNS_DELAY_OK="yes"
        msg_ok "TRAEFIK DNS PROPAGATION SYNTAX IS V3.7 COMPATIBLE"
    else
        msg_error "Traefik DNS challenge must use the current Traefik v3 propagation delay key, not the deprecated singular key."
    fi

    msg_info "Checking Traefik encoded-character options"
    if grep -q 'encodedCharacters' "$TRAEFIK_STATIC_CONFIG_FILE"; then
        TRAEFIK_ENCODED_CHARS_OK="yes"
        msg_ok "TRAEFIK ENCODED-CHARACTER CONFIG FOUND"
    else
        msg_error "Traefik encoded-character options missing from static config. Fix Script 6 template."
    fi

    msg_info "Checking for stale Authentik Docker-provider middleware references"
    if grep -q "authentik@""docker" "$TRAEFIK_DYNAMIC_CONFIG_FILE"; then
        msg_error "Stale Authentik Docker-provider middleware reference found in dynamic config. Use authentik file-provider middleware."
    fi
    TRAEFIK_AUTHENTIK_REFERENCES_OK="yes"
    msg_ok "NO STALE AUTHENTIK@DOCKER REFERENCES"

    msg_info "Checking centralized wildcard certificate strategy"
    if ! grep -q "main: \"${DOMAIN_VALUE}\"" "$TRAEFIK_STATIC_CONFIG_FILE" 2>/dev/null && ! grep -q "main: ${DOMAIN_VALUE}" "$TRAEFIK_STATIC_CONFIG_FILE" 2>/dev/null; then
        msg_error "Traefik static config does not contain the base wildcard certificate domain."
    fi
    if ! grep -q "\*.${DOMAIN_VALUE}" "$TRAEFIK_STATIC_CONFIG_FILE" 2>/dev/null; then
        msg_error "Traefik static config does not contain wildcard SAN *.${DOMAIN_VALUE}."
    fi
    if grep -q 'certResolver: cloudflare' "$TRAEFIK_DYNAMIC_CONFIG_FILE" 2>/dev/null; then
        msg_error "Traefik dynamic config still contains per-router certResolver entries. Wildcard issuance must stay centralized in traefik.yml."
    fi
    msg_ok "TRAEFIK WILDCARD CERTIFICATE STRATEGY VERIFIED"

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
            ADMIN_UI_COMPOSE_FILE="${COMPOSE_DIR}/${DOCKGE_STACK_FILE}"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME="$DOCKGE_BOOTSTRAP_OVERRIDE_FILE_NAME"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE="${COMPOSE_DIR}/${DOCKGE_BOOTSTRAP_OVERRIDE_FILE_NAME}"
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
            ADMIN_UI_COMPOSE_FILE="${COMPOSE_DIR}/${PORTAINER_STACK_FILE}"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME="$PORTAINER_BOOTSTRAP_OVERRIDE_FILE_NAME"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE="${COMPOSE_DIR}/${PORTAINER_BOOTSTRAP_OVERRIDE_FILE_NAME}"
            ADMIN_UI_BOOTSTRAP_PORT="$PORTAINER_BOOTSTRAP_PORT"
            ADMIN_UI_INTERNAL_PORT="9443"
            ADMIN_UI_BOOTSTRAP_SCHEME="https"
            expected_host="portainer.${DOMAIN_VALUE}"
            ;;
        komodo)
            ADMIN_UI_PROJECT_NAME="komodo"
            ADMIN_UI_SERVICE_NAME="komodo-core"
            ADMIN_UI_DISPLAY_NAME="Komodo"
            ADMIN_UI_COMPOSE_FILE="${COMPOSE_DIR}/${KOMODO_STACK_FILE}"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME="$KOMODO_BOOTSTRAP_OVERRIDE_FILE_NAME"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE="${COMPOSE_DIR}/${KOMODO_BOOTSTRAP_OVERRIDE_FILE_NAME}"
            ADMIN_UI_BOOTSTRAP_PORT="$KOMODO_BOOTSTRAP_PORT"
            ADMIN_UI_INTERNAL_PORT="9120"
            ADMIN_UI_BOOTSTRAP_SCHEME="http"
            expected_host="komodo.${DOMAIN_VALUE}"
            ;;
        dockhand)
            ADMIN_UI_PROJECT_NAME="dockhand"
            ADMIN_UI_SERVICE_NAME="dockhand"
            ADMIN_UI_DISPLAY_NAME="Dockhand"
            ADMIN_UI_COMPOSE_FILE="${COMPOSE_DIR}/${DOCKHAND_STACK_FILE}"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME="$DOCKHAND_BOOTSTRAP_OVERRIDE_FILE_NAME"
            ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE="${COMPOSE_DIR}/${DOCKHAND_BOOTSTRAP_OVERRIDE_FILE_NAME}"
            ADMIN_UI_BOOTSTRAP_PORT="$DOCKHAND_BOOTSTRAP_PORT"
            ADMIN_UI_INTERNAL_PORT="3000"
            ADMIN_UI_BOOTSTRAP_SCHEME="http"
            expected_host="dockhand.${DOMAIN_VALUE}"
            ;;
        *)
            msg_error "Invalid ADMIN_UI value in .env: ${ADMIN_UI}. Expected dockge, portainer, komodo, or dockhand."
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
# Confirms Filebrowser-safe writable folders exist before Filebrowser stack deployment.
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



# --- 33H. POSTGRESQL / REDIS RUNTIME REPAIR + READINESS ---
# Re-applies proven safe service-specific permissions immediately before deployment.
function selected_stack_contains() {
    local wanted="$1"
    local item=""
    for item in "${SELECTED_STACK_FILES[@]:-}"; do
        [ "$item" == "$wanted" ] && return 0
    done
    return 1
}


function service_compose_uses_puid_pgid() {
    local file="$1"
    local compose_path=""

    compose_path="$(compose_path_for_stack_file "$file")"

    [ -f "$compose_path" ] || return 1

    if grep -Eq 'PUID|PGID|\$\{PUID\}|\$\{PGID\}' "$compose_path"; then
        return 0
    fi

    return 1
}

function default_docker_user_uid() {
    id -u "$DOCKER_USER" 2>/dev/null || echo "1000"
}

function default_docker_user_gid() {
    id -g "$DOCKER_USER" 2>/dev/null || echo "1000"
}

function service_data_owner() {
    local file="$1"
    local default_uid="$2"
    local default_gid="$3"
    local uid=""
    local gid=""

    if service_compose_uses_puid_pgid "$file"; then
        uid="$(env_value PUID)"
        gid="$(env_value PGID)"
        [ -z "$uid" ] && uid="$(default_docker_user_uid)"
        [ -z "$gid" ] && gid="$(default_docker_user_gid)"
    else
        uid="$default_uid"
        gid="$default_gid"
    fi

    printf '%s:%s' "$uid" "$gid"
}

function postgres_process_owner() {
    local runtime_uid=""
    local runtime_gid=""

    # PostgreSQL can create/write the mounted cluster tree as the actual
    # running postgres server process user. Fresh testing proved this may differ
    # from the fallback 999:999, so runtime repairs must follow the live process
    # owner once the container exists.
    if docker_cmd ps --format '{{.Names}}' 2>/dev/null | grep -qx 'postgres'; then
        runtime_uid="$(docker_cmd exec postgres sh -lc "awk '/^Uid:/ {print \\$2; exit}' /proc/1/status" 2>/dev/null || true)"
        runtime_gid="$(docker_cmd exec postgres sh -lc "awk '/^Gid:/ {print \\$2; exit}' /proc/1/status" 2>/dev/null || true)"

        if [[ "$runtime_uid" =~ ^[0-9]+$ ]] && [[ "$runtime_gid" =~ ^[0-9]+$ ]]; then
            printf '%s:%s' "$runtime_uid" "$runtime_gid"
            return 0
        fi
    fi

    return 1
}

function postgres_data_owner() {
    local process_owner=""

    if process_owner="$(postgres_process_owner 2>/dev/null)" && [ -n "$process_owner" ]; then
        printf '%s' "$process_owner"
        return 0
    fi

    service_data_owner "$POSTGRES_STACK_FILE" "999" "999"
}

function redis_process_owner() {
    local runtime_uid=""
    local runtime_gid=""

    # docker exec id -u can report the exec/default user, not the actual Redis
    # server process owner. Use /proc/1/status first because temp RDB files are
    # created by the running redis-server process.
    if docker_cmd ps --format '{{.Names}}' 2>/dev/null | grep -qx 'redis'; then
        runtime_uid="$(docker_cmd exec redis sh -lc "awk '/^Uid:/ {print \\$2; exit}' /proc/1/status" 2>/dev/null || true)"
        runtime_gid="$(docker_cmd exec redis sh -lc "awk '/^Gid:/ {print \\$2; exit}' /proc/1/status" 2>/dev/null || true)"

        if [[ "$runtime_uid" =~ ^[0-9]+$ ]] && [[ "$runtime_gid" =~ ^[0-9]+$ ]]; then
            printf '%s:%s' "$runtime_uid" "$runtime_gid"
            return 0
        fi
    fi

    return 1
}

function redis_data_owner() {
    local process_owner=""

    if process_owner="$(redis_process_owner 2>/dev/null)" && [ -n "$process_owner" ]; then
        printf '%s' "$process_owner"
        return 0
    fi

    service_data_owner "$REDIS_STACK_FILE" "999" "999"
}

function repair_postgres_pgdata_permissions() {
    local pg_data_dir="${DOCKER_DIR}/appdata/postgres/pgdata"
    local pg_owner=""

    pg_owner="$(postgres_data_owner)"

    run_cmd "creating PostgreSQL PG18-compatible data directory" mkdir -p "$pg_data_dir"
    run_cmd "setting PostgreSQL pgdata ownership recursively" chown -R "$pg_owner" "$pg_data_dir"
    run_cmd "setting PostgreSQL pgdata permissions recursively" chmod -R u+rwX,go-rwx "$pg_data_dir"
    run_cmd "setting PostgreSQL pgdata root mode" chmod 700 "$pg_data_dir"
}

function verify_postgres_pgdata_permissions() {
    local pg_data_dir="${DOCKER_DIR}/appdata/postgres/pgdata"
    local pg_owner=""
    local pg_uid=""
    local pg_gid=""
    local bad=""

    pg_owner="$(postgres_data_owner)"
    pg_uid="${pg_owner%%:*}"
    pg_gid="${pg_owner##*:}"

    if [ -n "$SUDO_CMD" ]; then
        bad="$($SUDO_CMD find "$pg_data_dir" \( ! -uid "$pg_uid" -o ! -gid "$pg_gid" \) -printf '%u:%g %m %p\n' 2>/dev/null | head -20 || true)"
    else
        bad="$(find "$pg_data_dir" \( ! -uid "$pg_uid" -o ! -gid "$pg_gid" \) -printf '%u:%g %m %p\n' 2>/dev/null | head -20 || true)"
    fi

    if [ -n "$bad" ]; then
        echo -e "${YW}PostgreSQL permission offenders:${CL}"
        printf '%s\n' "$bad"
        msg_error "PostgreSQL pgdata still contains files not owned by ${pg_owner}. Refusing to deploy dependants."
    fi
}

function repair_redis_data_permissions() {
    local redis_data_dir="${DOCKER_DIR}/appdata/redis"
    local redis_owner=""

    redis_owner="$(redis_data_owner)"

    run_cmd "creating Redis data directory" mkdir -p "$redis_data_dir"
    run_cmd "setting Redis data ownership recursively" chown -R "$redis_owner" "$redis_data_dir"
    run_cmd "setting Redis data permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "$redis_data_dir"
    run_cmd "setting Redis data root mode" chmod 770 "$redis_data_dir"
}

function verify_redis_data_permissions() {
    local redis_data_dir="${DOCKER_DIR}/appdata/redis"
    local redis_owner=""
    local redis_uid=""
    local redis_gid=""
    local bad=""

    redis_owner="$(redis_data_owner)"
    redis_uid="${redis_owner%%:*}"
    redis_gid="${redis_owner##*:}"

    if [ -n "$SUDO_CMD" ]; then
        bad="$($SUDO_CMD find "$redis_data_dir" \( ! -uid "$redis_uid" -o ! -gid "$redis_gid" \) -printf '%u:%g %m %p\n' 2>/dev/null | head -20 || true)"
    else
        bad="$(find "$redis_data_dir" \( ! -uid "$redis_uid" -o ! -gid "$redis_gid" \) -printf '%u:%g %m %p\n' 2>/dev/null | head -20 || true)"
    fi

    if [ -n "$bad" ]; then
        echo -e "${YW}Redis permission offenders:${CL}"
        printf '%s\n' "$bad"
        msg_error "Redis data path still contains files not owned by ${redis_owner}. Refusing to continue."
    fi
}
function prepare_postgres_runtime_prereqs() {
    if ! selected_stack_contains "$POSTGRES_STACK_FILE"; then
        return 0
    fi

    section "POSTGRESQL RUNTIME PREREQS"

    local pg_root_dir="${DOCKER_DIR}/appdata/postgres"
    local pg_data_dir="${pg_root_dir}/pgdata"
    local pg_init_dir="${pg_root_dir}/init"

    require_nonempty_env_value "POSTGRES_PASSWORD"
    require_nonempty_env_value "AUTHENTIK_POSTGRES_PASSWORD"
    require_nonempty_env_value "POSTIZ_POSTGRES_PASSWORD"
    require_nonempty_env_value "TEMPORAL_POSTGRES_PASSWORD"

    run_cmd "creating PostgreSQL data directory" mkdir -p "$pg_data_dir"
    run_cmd "creating PostgreSQL init directory" mkdir -p "$pg_init_dir"
    repair_postgres_pgdata_permissions
    verify_postgres_pgdata_permissions
    run_cmd "setting PostgreSQL init directory readability" chmod 755 "$pg_init_dir"

    msg_ok "POSTGRESQL DATA DIRECTORY READY"
    detail_line "Data path" "$pg_data_dir"
    detail_line "Data owner" "$(postgres_data_owner) recursive"
    detail_line "Data mode" "700 root, u+rwX,go-rwx recursive"

    if docker_cmd inspect postgres --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null | grep -Eq 'restarting|unhealthy|exited|dead'; then
        msg_info "Existing PostgreSQL container is stale/unhealthy; removing container only, keeping data"
        docker_cmd rm -f postgres >/dev/null 2>&1 || true
        clear_transient_line
        msg_ok "STALE POSTGRESQL CONTAINER REMOVED; DATA KEPT"
    fi
}

function prepare_redis_runtime_prereqs() {
    if ! selected_stack_contains "$REDIS_STACK_FILE"; then
        return 0
    fi

    section "REDIS RUNTIME PREREQS"

    local redis_data_dir="${DOCKER_DIR}/appdata/redis"

    run_cmd "creating Redis data directory" mkdir -p "$redis_data_dir"
    repair_redis_data_permissions
    verify_redis_data_permissions

    msg_ok "REDIS DATA DIRECTORY READY"
    detail_line "Path" "$redis_data_dir"
    detail_line "Owner" "$(redis_data_owner)"
    detail_line "Mode" "770"
}

function require_nonempty_env_value() {
    local key="$1"
    local value=""

    value="$(env_value "$key")"

    if [ -z "$value" ]; then
        msg_error "Required .env value ${key} is missing or empty. Run fixed Script 6 before deployment."
    fi

    msg_ok "REQUIRED SECRET/VALUE PRESENT: ${key}"
}

function show_postgres_diagnostics() {
    echo ""
    echo -e "${YW}PostgreSQL diagnostics:${CL}"
    docker_cmd ps -a --filter "name=postgres" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
    docker_cmd inspect postgres --format 'status={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} exit={{.State.ExitCode}} restart_count={{.RestartCount}} oom={{.State.OOMKilled}} error={{.State.Error}}' 2>/dev/null || true
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" stat -c 'path=%n owner=%u:%g mode=%a type=%F' "${DOCKER_DIR}/appdata/postgres" "${DOCKER_DIR}/appdata/postgres/pgdata" "${DOCKER_DIR}/appdata/postgres/init" 2>/dev/null || true
    else
        stat -c 'path=%n owner=%u:%g mode=%a type=%F' "${DOCKER_DIR}/appdata/postgres" "${DOCKER_DIR}/appdata/postgres/pgdata" "${DOCKER_DIR}/appdata/postgres/init" 2>/dev/null || true
    fi
    docker_cmd logs --tail=160 postgres 2>/dev/null || true
}

function wait_for_postgres_ready() {
    section "POSTGRESQL READINESS CHECK"

    local attempt=""
    local max_attempts="150"
    local container_status=""
    local health_status=""
    local restart_count=""

    for attempt in $(seq 1 "$max_attempts"); do
        container_status="$(docker_cmd inspect postgres --format '{{.State.Status}}' 2>/dev/null || true)"
        health_status="$(docker_cmd inspect postgres --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' 2>/dev/null || true)"
        restart_count="$(docker_cmd inspect postgres --format '{{.RestartCount}}' 2>/dev/null || true)"

        if [ "$container_status" == "running" ] && [ "$health_status" == "healthy" ]; then
            clear_transient_line
            msg_ok "POSTGRESQL READY"
            detail_line "PostgreSQL container" "postgres"
            return 0
        fi

        if [ "$container_status" == "restarting" ] && [ "${restart_count:-0}" -ge 1 ]; then
            clear_transient_line
            msg_warn "PostgreSQL container is restarting instead of starting cleanly."
            show_postgres_diagnostics
            msg_error "PostgreSQL is in a restart loop. Fix data directory permission/init/existing-data issue before continuing."
        fi

        if [ "$attempt" -eq 1 ] || [ $((attempt % 15)) -eq 0 ]; then
            tty_print "${BFR}${YW}PostgreSQL not ready yet (${attempt}/${max_attempts}) | status=${container_status:-missing} health=${health_status:-none} restart_count=${restart_count:-unknown}${CL}"
        fi

        sleep 2
    done

    clear_transient_line
    show_postgres_diagnostics
    msg_error "PostgreSQL did not become healthy before dependent stacks."
}

function verify_redis_persistence_ready() {
    if ! selected_stack_contains "$REDIS_STACK_FILE"; then
        return 0
    fi

    section "REDIS PERSISTENCE CHECK"

    local attempt=""
    local max_attempts="60"
    local state=""
    local info=""
    local bgsave_status=""
    local bgsave_in_progress=""

    for attempt in $(seq 1 "$max_attempts"); do
        state="$(docker_cmd inspect redis --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)"
        if [ "$state" == "healthy" ] || [ "$state" == "running" ]; then
            break
        fi
        tty_print "${BFR}${YW}Redis not ready yet (${attempt}/${max_attempts}) | state=${state:-missing}${CL}"
        sleep 2
    done
    clear_transient_line

    # Re-apply the proven host path fix immediately before the write test.
    repair_redis_data_permissions
    verify_redis_data_permissions

    if ! docker_cmd exec redis redis-cli BGSAVE >/dev/null 2>&1; then
        docker_cmd logs --tail=120 redis 2>/dev/null || true
        msg_error "Redis BGSAVE failed. Fix ${DOCKER_DIR}/appdata/redis ownership/permissions before continuing."
    fi

    for attempt in $(seq 1 30); do
        info="$(docker_cmd exec redis redis-cli INFO persistence 2>/dev/null || true)"
        bgsave_in_progress="$(printf '%s\n' "$info" | awk -F: '/^rdb_bgsave_in_progress:/ {gsub(/\r/,"",$2); print $2; exit}')"
        bgsave_status="$(printf '%s\n' "$info" | awk -F: '/^rdb_last_bgsave_status:/ {gsub(/\r/,"",$2); print $2; exit}')"

        if [ "$bgsave_in_progress" == "0" ] && [ "$bgsave_status" == "ok" ]; then
            msg_ok "REDIS PERSISTENCE VERIFIED"
            detail_line "BGSAVE status" "ok"
            return 0
        fi

        sleep 1
    done

    docker_cmd exec redis redis-cli INFO persistence 2>/dev/null || true
    docker_cmd logs --tail=120 redis 2>/dev/null || true
    msg_error "Redis persistence did not report rdb_last_bgsave_status:ok after BGSAVE. Fix ${DOCKER_DIR}/appdata/redis before continuing."
}

function wait_for_temporal_ready() {
    if ! selected_stack_contains "$TEMPORAL_STACK_FILE"; then
        return 0
    fi

    section "TEMPORAL READINESS CHECK"

    local temporal_address="${TEMPORAL_ADDRESS:-temporal:7233}"
    local temporal_namespace="${TEMPORAL_NAMESPACE:-default}"
    local temporal_admin_tools_image=""
    local attempt=""
    local max_attempts="150"
    local err_file=""

    temporal_admin_tools_image="$(env_value TEMPORAL_ADMIN_TOOLS_IMAGE)"
    [ -z "$temporal_admin_tools_image" ] && temporal_admin_tools_image="temporalio/admin-tools:latest"

    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    for attempt in $(seq 1 "$max_attempts"); do
        if docker_cmd run --rm --network database "$temporal_admin_tools_image" \
            temporal --address "$temporal_address" --namespace "$temporal_namespace" \
            operator search-attribute list >/dev/null 2>"$err_file"; then
            clear_transient_line
            msg_ok "TEMPORAL API READY"
            detail_line "Temporal address" "$temporal_address"
            detail_line "Temporal namespace" "$temporal_namespace"
            return 0
        fi

        if [ "$attempt" -eq 1 ] || [ $((attempt % 15)) -eq 0 ]; then
            tty_print "${BFR}${YW}Temporal API not ready yet (${attempt}/${max_attempts}). Waiting before Postiz Temporal Guard...${CL}"
        fi

        sleep 2
    done

    echo -e "${RD}Last Temporal CLI error:${CL}"
    cat "$err_file" 2>/dev/null || true
    docker_cmd logs --tail=160 temporal 2>/dev/null || true
    docker_cmd logs --tail=100 postgres 2>/dev/null || true
    msg_error "Temporal is not reachable on ${temporal_address}. Fix Temporal/PostgreSQL before running Postiz Temporal Guard."
}

# --- 33I. DOCKGE COMPOSE LAYOUT SYNC ---
# Dockge expects stacks in ${DOCKER_DIR}/compose/<stack name>/compose.yaml.
function dockge_stack_dir_name_for_file() {
    local file="$1"

    case "$file" in
        "$SOCKET_PROXY_STACK_FILE") echo "socket-proxy" ;;
        "$DOCKGE_STACK_FILE") echo "dockge" ;;
        "$DOCKHAND_STACK_FILE") echo "dockhand" ;;
        "$KOMODO_STACK_FILE") echo "komodo" ;;
        "$PORTAINER_STACK_FILE") echo "portainer" ;;
        "$POSTGRES_STACK_FILE") echo "postgres" ;;
        "$REDIS_STACK_FILE") echo "redis" ;;
        "$TRAEFIK_STACK_FILE") echo "traefik" ;;
        "$AUTHENTIK_STACK_FILE") echo "authentik" ;;
        "$TEMPORAL_STACK_FILE") echo "temporal" ;;
        "$POSTIZ_TEMPORAL_GUARD_STACK_FILE") echo "postiz-temporal-guard" ;;
        "$POSTIZ_STACK_FILE") echo "postiz" ;;
        "$CF_DDNS_STACK_FILE") echo "cf-ddns" ;;
        "$CF_COMPANION_STACK_FILE") echo "cf-companion" ;;
        "$VSCODE_STACK_FILE") echo "vscode" ;;
        "$FILEBROWSER_STACK_FILE") echo "filebrowser" ;;
        *) echo "${file%.yml}" | sed -E 's/^[0-9]+-//' ;;
    esac
}

function sync_compose_file_for_dockge() {
    local file="$1"
    local source_path="$2"
    local stack_dir=""
    local target_dir=""
    local target_file=""

    if [ "$ADMIN_UI" != "dockge" ]; then
        return 0
    fi

    stack_dir="$(dockge_stack_dir_name_for_file "$file")"
    target_dir="${COMPOSE_DIR}/${stack_dir}"
    target_file="${target_dir}/compose.yaml"

    run_cmd "creating Dockge stack folder ${stack_dir}" mkdir -p "$target_dir"
    run_cmd "syncing ${file} into Dockge compose layout" cp "$source_path" "$target_file"
    run_cmd "setting Dockge compose ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$target_file"
    run_cmd "setting Dockge compose permissions" chmod 640 "$target_file"
    msg_ok "DOCKGE COMPOSE READY: ${target_file}"
}

function sync_bootstrap_override_for_dockge() {
    local primary_file="$1"
    local source_path="$2"
    local stack_dir=""
    local target_dir=""
    local target_file=""

    if [ "$ADMIN_UI" != "dockge" ]; then
        return 0
    fi

    stack_dir="$(dockge_stack_dir_name_for_file "$primary_file")"
    target_dir="${COMPOSE_DIR}/${stack_dir}"
    target_file="${target_dir}/bootstrap-override.yaml"

    run_cmd "creating Dockge stack folder ${stack_dir}" mkdir -p "$target_dir"
    run_cmd "syncing bootstrap override into Dockge compose layout" cp "$source_path" "$target_file"
    run_cmd "setting Dockge bootstrap override ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$target_file"
    run_cmd "setting Dockge bootstrap override permissions" chmod 640 "$target_file"
    msg_ok "DOCKGE BOOTSTRAP OVERRIDE READY: ${target_file}"
}


# --- 33I.1. COMPOSE PATH RESOLUTION HELPERS ---
# When Dockge is the selected admin UI, Script 6.5 deploys from the same
# ${DOCKER_DIR}/compose/<stack>/compose.yaml layout that Dockge displays.
# The flat downloaded filename remains as a fallback and source file.
function compose_path_for_stack_file() {
    local file="$1"
    local stack_dir=""
    local dockge_path=""

    if [ "$ADMIN_UI" == "dockge" ]; then
        stack_dir="$(dockge_stack_dir_name_for_file "$file")"
        dockge_path="${COMPOSE_DIR}/${stack_dir}/compose.yaml"
        if [ -f "$dockge_path" ]; then
            printf '%s' "$dockge_path"
            return 0
        fi
    fi

    printf '%s' "${COMPOSE_DIR}/${file}"
}

function bootstrap_override_path_for_primary_file() {
    local primary_file="$1"
    local stack_dir=""
    local dockge_path=""

    if [ "$ADMIN_UI" == "dockge" ]; then
        stack_dir="$(dockge_stack_dir_name_for_file "$primary_file")"
        dockge_path="${COMPOSE_DIR}/${stack_dir}/bootstrap-override.yaml"
        if [ -f "$dockge_path" ]; then
            printf '%s' "$dockge_path"
            return 0
        fi
    fi

    printf '%s' "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
}

function primary_stack_for_bootstrap_override() {
    local file="$1"

    case "$file" in
        "$DOCKGE_BOOTSTRAP_OVERRIDE_FILE_NAME") echo "$DOCKGE_STACK_FILE" ;;
        "$PORTAINER_BOOTSTRAP_OVERRIDE_FILE_NAME") echo "$PORTAINER_STACK_FILE" ;;
        "$KOMODO_BOOTSTRAP_OVERRIDE_FILE_NAME") echo "$KOMODO_STACK_FILE" ;;
        "$DOCKHAND_BOOTSTRAP_OVERRIDE_FILE_NAME") echo "$DOCKHAND_STACK_FILE" ;;
        *) echo "" ;;
    esac
}


# --- 33H. STACK REGISTRY HELPERS ---
# Uses the fixed uploaded project structure. No GitHub scanning is performed.
function stack_project_for_file() {
    local file="$1"
    case "$file" in
        "$POSTGRES_STACK_FILE") echo "postgres" ;;
        "$REDIS_STACK_FILE") echo "redis" ;;
        "$TRAEFIK_STACK_FILE") echo "traefik" ;;
        "$AUTHENTIK_STACK_FILE") echo "authentik" ;;
        "$TEMPORAL_STACK_FILE") echo "temporal" ;;
        "$POSTIZ_TEMPORAL_GUARD_STACK_FILE") echo "postiz-temporal-guard" ;;
        "$POSTIZ_STACK_FILE") echo "postiz" ;;
        "$CF_DDNS_STACK_FILE") echo "cf-ddns" ;;
        "$CF_COMPANION_STACK_FILE") echo "cf-companion" ;;
        "$VSCODE_STACK_FILE") echo "vscode" ;;
        "$FILEBROWSER_STACK_FILE") echo "filebrowser" ;;
        *) echo "${file%.yml}" | tr '[:upper:]' '[:lower:]' ;;
    esac
}

function stack_primary_service_for_file() {
    local file="$1"
    case "$file" in
        "$POSTGRES_STACK_FILE") echo "postgres" ;;
        "$REDIS_STACK_FILE") echo "redis" ;;
        "$TRAEFIK_STACK_FILE") echo "traefik" ;;
        "$AUTHENTIK_STACK_FILE") echo "authentik-server" ;;
        "$TEMPORAL_STACK_FILE") echo "temporal" ;;
        "$POSTIZ_TEMPORAL_GUARD_STACK_FILE") echo "postiz-temporal-guard" ;;
        "$POSTIZ_STACK_FILE") echo "postiz" ;;
        "$CF_DDNS_STACK_FILE") echo "cf-ddns" ;;
        "$CF_COMPANION_STACK_FILE") echo "cf-companion" ;;
        "$VSCODE_STACK_FILE") echo "vscode" ;;
        "$FILEBROWSER_STACK_FILE") echo "filebrowser" ;;
        *) echo "" ;;
    esac
}

function add_selected_stack_once() {
    local file="$1"
    local reason="$2"
    local existing=""

    for existing in "${SELECTED_STACK_FILES[@]}"; do
        [ "$existing" == "$file" ] && return 0
    done

    SELECTED_STACK_FILES+=("$file")
    SELECTED_STACK_PROJECTS+=("$(stack_project_for_file "$file")")
    SELECTED_STACK_SERVICES+=("$(stack_primary_service_for_file "$file")")
    DEPENDENCY_REASONS+=("$reason")
}

function add_authentik_routing_dependencies() {
    local source_reason="$1"

    add_selected_stack_once "$POSTGRES_STACK_FILE" "PostgreSQL auto-selected because ${source_reason} requires Authentik/database-backed SSO."
    add_selected_stack_once "$REDIS_STACK_FILE" "Redis auto-selected because ${source_reason} requires Authentik cache/session storage."
    add_selected_stack_once "$TRAEFIK_STACK_FILE" "Traefik auto-selected because ${source_reason} requires HTTPS routing."
    add_selected_stack_once "$AUTHENTIK_STACK_FILE" "Authentik auto-selected because ${source_reason} is protected by file-provider forward-auth."
}

function add_traefik_only_dependency() {
    local source_reason="$1"
    add_selected_stack_once "$TRAEFIK_STACK_FILE" "Traefik auto-selected because ${source_reason} requires Traefik routing/labels."
}

# --- 33I. STACK DEPLOYMENT CHOICE COLLECTION ---
# Collects all deployment choices before any compose files, networks or containers are changed.
function collect_stack_deployment_choices() {
    section "STACK DEPLOYMENT SELECTION"

    echo -e "${YW}Socket Proxy is required and will always be deployed.${CL}"
    echo -e "${YW}${ADMIN_UI_DISPLAY_NAME} was selected in Script 6 and will be deployed with temporary bootstrap access.${CL}"
    echo ""

    DEPLOY_POSTIZ="$(timed_yes_no "Deploy Postiz social media stack?" "y")"
    if [[ "$DEPLOY_POSTIZ" =~ ^[Yy] ]]; then
        add_selected_stack_once "$POSTGRES_STACK_FILE" "PostgreSQL auto-selected because Authentik, Temporal and Postiz need database storage."
        add_selected_stack_once "$REDIS_STACK_FILE" "Redis auto-selected because Authentik and Postiz need cache/session storage."
        add_selected_stack_once "$TRAEFIK_STACK_FILE" "Traefik auto-selected because public HTTPS routing is required."
        add_selected_stack_once "$AUTHENTIK_STACK_FILE" "Authentik auto-selected because SSO/front-door protection is required."
        add_selected_stack_once "$TEMPORAL_STACK_FILE" "Temporal auto-selected because Postiz requires workflow orchestration."
        add_selected_stack_once "$POSTIZ_TEMPORAL_GUARD_STACK_FILE" "Postiz Temporal Guard auto-selected because Postiz can crash if Temporal Text attributes remain."
        add_selected_stack_once "$POSTIZ_STACK_FILE" "Postiz selected by user."
    else
        echo -e "${YW}Postiz not selected. You can still deploy optional utility stacks below.${CL}"
    fi

    DEPLOY_CF_DDNS="$(timed_yes_no "Deploy Cloudflare DDNS stack?" "y")"
    [[ "$DEPLOY_CF_DDNS" =~ ^[Yy] ]] && add_selected_stack_once "$CF_DDNS_STACK_FILE" "Cloudflare DDNS selected by user."

    DEPLOY_CF_COMPANION="$(timed_yes_no "Deploy Cloudflare Companion DNS automation stack?" "y")"
    if [[ "$DEPLOY_CF_COMPANION" =~ ^[Yy] ]]; then
        add_traefik_only_dependency "Cloudflare Companion"
        add_selected_stack_once "$CF_COMPANION_STACK_FILE" "Cloudflare Companion selected by user for Traefik label-driven DNS automation."
    fi

    DEPLOY_VSCODE="$(timed_yes_no "Deploy VS Code server utility stack?" "n")"
    if [[ "$DEPLOY_VSCODE" =~ ^[Yy] ]]; then
        add_authentik_routing_dependencies "VS Code"
        add_selected_stack_once "$VSCODE_STACK_FILE" "VS Code utility stack selected by user."
    fi

    DEPLOY_FILEBROWSER="$(timed_yes_no "Deploy Filebrowser utility stack?" "n")"
    if [[ "$DEPLOY_FILEBROWSER" =~ ^[Yy] ]]; then
        add_authentik_routing_dependencies "Filebrowser"
        add_selected_stack_once "$FILEBROWSER_STACK_FILE" "Filebrowser utility stack selected by user."
    fi

    msg_ok "STACK CHOICES COLLECTED"
}

# --- 33J. SELECTED STACK PREFLIGHTS ---
# Performs permission and secret checks for the selected plan before READY TO APPLY.
function verify_selected_stack_preflight() {
    section "SELECTED STACK PREFLIGHT"

    if [[ "$DEPLOY_POSTIZ" =~ ^[Yy] ]]; then
        verify_redis_host_tuning
        verify_traefik_rendered_configs
        verify_authentik_folders
    fi

    if [[ "$DEPLOY_CF_COMPANION" =~ ^[Yy] ]]; then
        verify_cf_companion_secret_file
    else
        CF_COMPANION_SECRET_OK="skipped"
        msg_skip "CF-COMPANION SECRET CHECK SKIPPED; STACK NOT SELECTED"
    fi

    if [[ "$DEPLOY_FILEBROWSER" =~ ^[Yy] ]]; then
        verify_filebrowser_folders
    else
        FILEBROWSER_FOLDERS_OK="skipped"
        msg_skip "FILEBROWSER FOLDER CHECK SKIPPED; STACK NOT SELECTED"
    fi
}

# --- 33K. COMPOSE ENV VARIABLE COVERAGE CHECK ---
# Checks selected compose files for required ${VARIABLE} references without fallbacks.
function verify_compose_env_coverage_for_file() {
    local file="$1"
    local path=""

    path="$(compose_path_for_stack_file "$file")"
    local missing="no"
    local token=""
    local var=""

    [ -f "$path" ] || msg_error "Compose file missing for env coverage check: ${path}"

    while IFS= read -r token; do
        # Convert a compose token like ${DOCKER_DIR} or ${POSTIZ_IMAGE:-image:latest}
        # into a safe variable name before indirect expansion. This prevents Bash from
        # treating malformed leftovers such as DOCKER_DIR}} as an indirect variable name.
        var="${token#\$\{}"
        var="${var%\}}"

        # Skip variables with compose/default fallbacks because they are not mandatory.
        if [[ "$var" == *:-* ]] || [[ "$var" == *-* ]]; then
            continue
        fi

        # Ignore variables intentionally escaped for container-side shell scripts, e.g. $${i} in one-shot guards.
        [ "$var" == "i" ] && continue

        # Defensive guard before ${!var}; indirect expansion requires a valid shell variable name.
        if ! [[ "$var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            continue
        fi

        if ! grep -qE "^${var}=" "$ENV_FILE" && [ -z "${!var:-}" ]; then
            echo -e "${RD}Missing variable for ${file}:${CL} ${var}"
            missing="yes"
        fi
    done < <(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}' "$path" | sort -u || true)

    [ "$missing" == "no" ] || msg_error "Compose variable coverage failed for ${file}. Run fixed Script 6 first."
}

function verify_selected_compose_env_coverage() {
    section "COMPOSE VARIABLE COVERAGE"
    local file=""

    verify_compose_env_coverage_for_file "$SOCKET_PROXY_STACK_FILE"
    verify_compose_env_coverage_for_file "$(basename "$ADMIN_UI_COMPOSE_FILE")"

    for file in "${SELECTED_STACK_FILES[@]}"; do
        verify_compose_env_coverage_for_file "$file"
    done

    msg_ok "SELECTED COMPOSE VARIABLE COVERAGE PASSED"
}

function normalize_compose_for_wildcard_tls() {
    local target="$1"
    local file="$2"

    [ -f "$target" ] || return 0

    # Router-level certresolver labels create a new ACME order per subdomain during
    # repeated fresh tests. Keep TLS enabled on each router, but let Traefik's
    # HTTPS entryPoint use the single wildcard certificate configured in traefik.yml.
    if grep -q 'traefik\.http\.routers\..*\.tls\.certresolver' "$target" 2>/dev/null; then
        sed -i '/traefik\.http\.routers\..*\.tls\.certresolver:/d' "$target"
        msg_ok "NORMALIZED WILDCARD TLS LABELS: ${file}"
    fi
}

function download_fixed_stack_file() {
    local file="$1"
    local target="${COMPOSE_DIR}/${file}"
    local url="${GITHUB_RAW_BASE}/${file}"
    local primary_for_override=""

    msg_info "Downloading ${file}"
    curl --globoff -fsSL "$url" -o "$target" || msg_error "Failed to download ${url}"
    [ -s "$target" ] || msg_error "Downloaded file is empty: ${target}"
    if grep -q "authentik@""docker" "$target"; then
        msg_error "Forbidden stale Authentik Docker-provider middleware reference found in ${file}."
    fi
    normalize_compose_for_wildcard_tls "$target" "$file"
    run_cmd "setting compose file ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$target"
    run_cmd "setting compose file permissions" chmod 640 "$target"

    primary_for_override="$(primary_stack_for_bootstrap_override "$file")"
    if [ -n "$primary_for_override" ]; then
        sync_bootstrap_override_for_dockge "$primary_for_override" "$target"
    else
        sync_compose_file_for_dockge "$file" "$target"
    fi

    msg_ok "DOWNLOADED ${file}"
}

function download_selected_compose_files() {
    section "STACK COMPOSE DOWNLOAD"
    local file=""

    download_fixed_stack_file "$SOCKET_PROXY_STACK_FILE"
    download_fixed_stack_file "$(basename "$ADMIN_UI_COMPOSE_FILE")"
    download_fixed_stack_file "$ADMIN_UI_BOOTSTRAP_OVERRIDE_NAME"

    for file in "${SELECTED_STACK_FILES[@]}"; do
        download_fixed_stack_file "$file"
    done

    SOCKET_PROXY_STACK_DOWNLOADED="yes"
    ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN="downloaded"
}

function validate_selected_compose_files() {
    section "SELECTED STACK COMPOSE VALIDATION"
    local i=""
    local file=""
    local project=""

    export DOCKER_DIR COMPOSE_DIR ENV_FILE PORTAINER_BOOTSTRAP_PORT DOCKGE_BOOTSTRAP_PORT KOMODO_BOOTSTRAP_PORT DOCKHAND_BOOTSTRAP_PORT ADMIN_UI_BOOTSTRAP_BIND

    msg_info "Validating Socket Proxy stack compose"
    run_docker_cmd "validating Socket Proxy stack compose" compose --env-file "$ENV_FILE" -p socket-proxy -f "$(compose_path_for_stack_file "$SOCKET_PROXY_STACK_FILE")" config -q
    msg_ok "SOCKET PROXY STACK COMPOSE VALID"

    msg_info "Validating ${ADMIN_UI_DISPLAY_NAME} stack compose with bootstrap override"
    run_docker_cmd "validating ${ADMIN_UI_DISPLAY_NAME} stack compose" compose --env-file "$ENV_FILE" -p "$ADMIN_UI_PROJECT_NAME" -f "$(compose_path_for_stack_file "$(basename "$ADMIN_UI_COMPOSE_FILE")")" -f "$(bootstrap_override_path_for_primary_file "$(basename "$ADMIN_UI_COMPOSE_FILE")")" config -q
    msg_ok "${ADMIN_UI_DISPLAY_NAME^^} STACK COMPOSE VALID"

    for i in "${!SELECTED_STACK_FILES[@]}"; do
        file="${SELECTED_STACK_FILES[$i]}"
        project="${SELECTED_STACK_PROJECTS[$i]}"
        msg_info "Validating ${file}"
        run_docker_cmd "validating ${file}" compose --env-file "$ENV_FILE" -p "$project" -f "$(compose_path_for_stack_file "$file")" config -q
        msg_ok "VALID COMPOSE: ${file}"
    done

    ADMIN_UI_VALIDATED="yes"
}

function deploy_selected_stacks() {
    section "DEPENDENCY-AWARE STACK DEPLOYMENT"
    local i=""
    local file=""
    local project=""
    local service=""
    local compose_path=""

    detail_line "Bootstrap stacks" "socket-proxy + ${ADMIN_UI_DISPLAY_NAME}"
    if [ "${#SELECTED_STACK_FILES[@]}" -eq 0 ]; then
        detail_line "Additional stacks" "none selected"
    else
        for i in "${!SELECTED_STACK_FILES[@]}"; do
            detail_line "Deploy order $((i + 1))" "${SELECTED_STACK_PROJECTS[$i]} from $(compose_path_for_stack_file "${SELECTED_STACK_FILES[$i]}")"
        done
    fi

    deploy_socket_proxy
    deploy_admin_ui

    for i in "${!SELECTED_STACK_FILES[@]}"; do
        file="${SELECTED_STACK_FILES[$i]}"
        project="${SELECTED_STACK_PROJECTS[$i]}"
        service="${SELECTED_STACK_SERVICES[$i]}"
        compose_path="$(compose_path_for_stack_file "$file")"

        if [ "$file" == "$POSTIZ_TEMPORAL_GUARD_STACK_FILE" ]; then
            section "RUN STACK - POSTIZ TEMPORAL GUARD"
            run_postiz_temporal_guard_stack "$project" "$file"
            continue
        fi

        section "DEPLOY STACK - ${project^^}"
        detail_line "Compose file" "$compose_path"
        compose_up_quiet "deploying ${project}" --env-file "$ENV_FILE" -p "$project" -f "$compose_path"
        msg_ok "DEPLOYED ${project^^}"

        if [ -n "$service" ]; then
            if docker_cmd ps --format '{{.Names}}' | grep -qx "$service"; then
                msg_ok "RUNNING CONTAINER CONFIRMED: ${service}"
            else
                msg_warn "Container ${service} not confirmed yet. It may still be starting; check docker logs if needed."
            fi
        fi

        if [ "$file" == "$POSTGRES_STACK_FILE" ]; then
            wait_for_postgres_ready
        fi

        if [ "$file" == "$REDIS_STACK_FILE" ]; then
            verify_redis_persistence_ready
        fi

        if [ "$file" == "$TEMPORAL_STACK_FILE" ]; then
            wait_for_temporal_ready
        fi
    done
}

function verify_cf_companion_runtime_if_selected() {
    section "CF-COMPANION RUNTIME VERIFICATION"

    if ! [[ "$DEPLOY_CF_COMPANION" =~ ^[Yy] ]]; then
        msg_skip "CF-COMPANION RUNTIME CHECK SKIPPED; STACK NOT SELECTED"
        return 0
    fi

    if ! docker_cmd ps --format '{{.Names}}' | grep -qx 'cf-companion'; then
        msg_warn "cf-companion container is not running yet. Check logs after startup."
        return 0
    fi

    if docker_cmd logs cf-companion --tail=120 2>/dev/null | grep -Eiq 'unauthorized|authentication failed|invalid token|missing token|permission denied'; then
        msg_error "Cloudflare Companion logs show authentication/token errors. Verify cf_token secret and API token permissions."
    fi

    msg_ok "CF-COMPANION LOGS SHOW NO OBVIOUS AUTH FAILURE"
}


# =========================================================
#  AUTHENTIK FORWARD-AUTH SETUP / ROUTE VERIFICATION
# =========================================================

function json_get_first_pk() {
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
items = data.get("results", data if isinstance(data, list) else []) if isinstance(data, (dict, list)) else []
print(items[0].get("pk", "") if items else "")
'
}

function json_get_first_uuid_or_pk() {
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)
items = data.get("results", data if isinstance(data, list) else []) if isinstance(data, (dict, list)) else []
print((items[0].get("pk") or items[0].get("uuid") or "") if items else "")
'
}

function json_is_valid_object_or_array() {
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if isinstance(data, (dict, list)) else 1)
'
}

function json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

function verify_authentik_dependencies_for_deploy() {
    section "AUTHENTIK DEPENDENCY GATE"

    local required="no"
    local check_output=""

    if [[ "$DEPLOY_POSTIZ" =~ ^[Yy] ]] || [[ "$DEPLOY_VSCODE" =~ ^[Yy] ]] || [[ "$DEPLOY_FILEBROWSER" =~ ^[Yy] ]]; then
        required="yes"
    fi

    if [ "$required" != "yes" ]; then
        AUTHENTIK_DEPENDENCIES_OK="skipped"
        msg_skip "AUTHENTIK DEPENDENCY GATE SKIPPED"
        return 0
    fi

    if ! docker_cmd ps --format '{{.Names}}' | grep -qx 'authentik-server'; then
        AUTHENTIK_DEPENDENCIES_OK="authentik-not-running"
        msg_warn "authentik-server is not running; API automation skipped."
        return 0
    fi

    if ! docker_cmd ps --format '{{.Names}}' | grep -qx 'postgres'; then
        msg_error "PostgreSQL container is not running. Fix PostgreSQL before Authentik automation."
    fi

    if ! docker_cmd ps --format '{{.Names}}' | grep -qx 'redis'; then
        msg_error "Redis container is not running. Fix Redis before Authentik automation."
    fi

    repair_postgres_pgdata_permissions
    verify_postgres_pgdata_permissions
    repair_redis_data_permissions
    verify_redis_data_permissions

    if ! docker_cmd exec redis redis-cli BGSAVE >/dev/null 2>&1 || docker_cmd logs --tail=120 redis 2>/dev/null | grep -Eiq 'MISCONF|Permission denied|Background saving error'; then
        docker_cmd logs --tail=120 redis 2>/dev/null || true
        msg_error "Redis persistence is not healthy. Fix ${DOCKER_DIR}/appdata/redis before Authentik API automation."
    fi

    check_output="$(docker_cmd exec authentik-server sh -lc '
python - <<PY
import socket, sys
failed = False
for host, port in [("postgres", 5432), ("redis", 6379)]:
    try:
        socket.create_connection((host, port), timeout=5).close()
        print(f"OK {host}:{port}")
    except Exception as e:
        print(f"FAIL {host}:{port} {e}")
        failed = True
sys.exit(1 if failed else 0)
PY
' 2>&1)" || {
        echo "$check_output"
        docker_cmd logs --tail=100 postgres 2>/dev/null || true
        docker_cmd logs --tail=100 redis 2>/dev/null || true
        msg_error "authentik-server cannot reach PostgreSQL/Redis. Fix dependency DNS/connectivity before API token setup."
    }

    echo "$check_output"
    AUTHENTIK_DEPENDENCIES_OK="yes"
    msg_ok "AUTHENTIK DEPENDENCIES VERIFIED"
}


function wait_for_authentik_internal_api_ready() {
    section "AUTHENTIK INTERNAL API READINESS"

    local attempt=""
    local max_attempts="120"
    local status_output=""
    local http_code=""

    if ! docker_cmd ps --format '{{.Names}}' | grep -qx 'authentik-server'; then
        msg_warn "authentik-server is not running; internal API readiness check skipped."
        return 1
    fi

    for attempt in $(seq 1 "$max_attempts"); do
        status_output="$(docker_cmd exec authentik-server sh -lc '
python - <<AK_READY_PY
import urllib.request, urllib.error
url="http://127.0.0.1:9000/api/v3/core/users/me/"
try:
    r=urllib.request.urlopen(url, timeout=5)
    print(r.status)
except urllib.error.HTTPError as e:
    print(e.code)
except Exception as e:
    print("ERR", repr(e))
AK_READY_PY
' 2>/dev/null || true)"
        http_code="$(printf '%s\n' "$status_output" | tail -n 1 | awk '{print $1}')"

        # 401/403 means the API is alive and only requires authentication.
        # 200 can happen if the endpoint becomes accessible in a future Authentik version.
        if [[ "$http_code" =~ ^(200|401|403)$ ]]; then
            clear_transient_line
            msg_ok "AUTHENTIK INTERNAL API READY"
            detail_line "Internal API unauthenticated status" "$http_code"
            return 0
        fi

        if [ "$attempt" -eq 1 ] || [ $((attempt % 10)) -eq 0 ]; then
            tty_print "${BFR}${YW}Authentik internal API not ready yet (${attempt}/${max_attempts}) | status=${http_code:-unknown}${CL}"
        fi

        sleep 3
    done

    clear_transient_line
    echo -e "${YW}Authentik server logs:${CL}"
    docker_cmd logs --tail=160 authentik-server 2>/dev/null || true
    echo -e "${YW}Authentik worker logs:${CL}"
    docker_cmd logs --tail=120 authentik-worker 2>/dev/null || true
    echo -e "${YW}PostgreSQL logs:${CL}"
    docker_cmd logs --tail=100 postgres 2>/dev/null || true
    echo -e "${YW}Redis logs:${CL}"
    docker_cmd logs --tail=80 redis 2>/dev/null || true
    msg_error "Authentik internal API stayed unavailable/HTTP 500 after waiting. Fix Authentik logs before route automation."
}

function collect_authentik_api_token_for_deploy() {
    local env_api_token=""
    local env_bootstrap_token=""

    if [ -n "${AUTHENTIK_API_TOKEN:-}" ]; then
        msg_ok "AUTHENTIK API TOKEN FOUND IN ENVIRONMENT"
        return 0
    fi

    env_api_token="$(env_value AUTHENTIK_API_TOKEN)"
    env_bootstrap_token="$(env_value AUTHENTIK_BOOTSTRAP_TOKEN)"

    if [ -n "$env_api_token" ]; then
        AUTHENTIK_API_TOKEN="$env_api_token"
        export AUTHENTIK_API_TOKEN
        msg_ok "AUTHENTIK API TOKEN LOADED FROM .ENV"
        return 0
    fi

    if [ -n "$env_bootstrap_token" ]; then
        AUTHENTIK_API_TOKEN="$env_bootstrap_token"
        export AUTHENTIK_API_TOKEN
        msg_ok "AUTHENTIK API TOKEN LOADED FROM AUTHENTIK_BOOTSTRAP_TOKEN"
        return 0
    fi

    section "AUTHENTIK API TOKEN"
    echo -e "${YW}A valid Authentik API token is required to automate provider/application/outpost setup.${CL}"
    echo -e "${YW}Fresh Authentik creates the akadmin API Access token from AUTHENTIK_BOOTSTRAP_TOKEN.${CL}"
    echo -e "${YW}Leave blank to skip automation and keep bootstrap/direct access open.${CL}"

    AUTHENTIK_API_TOKEN="$(sensitive_line_input "Paste Authentik API token, or leave blank")"
    AUTHENTIK_API_TOKEN="$(printf '%s' "$AUTHENTIK_API_TOKEN" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ -z "$AUTHENTIK_API_TOKEN" ]; then
        msg_warn "AUTHENTIK API TOKEN NOT PROVIDED; PROTECTED ROUTE AUTOMATION SKIPPED"
    else
        export AUTHENTIK_API_TOKEN
        msg_ok "AUTHENTIK API TOKEN CAPTURED WITHOUT LOGGING"
    fi
}

function ak_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local internal_base="http://127.0.0.1:9000/api/v3"

    [ -n "${AUTHENTIK_API_TOKEN:-}" ] || return 1

    # Important: use the Authentik container's local HTTP API for automation.
    # Calling https://auth.${DOMAIN_VALUE} goes through Cloudflare/Traefik and can return
    # HTML errors such as Cloudflare 525 or Authentik Server Error pages. Those are not JSON
    # API responses and previously caused false API success plus Python JSON tracebacks.
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'authentik-server'; then
        if [ -n "$data" ]; then
            printf '%s' "$data" | docker_cmd exec -i authentik-server python3 -c '
import sys, urllib.request, urllib.error
method, url, token = sys.argv[1], sys.argv[2], sys.argv[3]
body = sys.stdin.read()
payload = body.encode() if body else None
headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
if payload is not None:
    headers["Content-Type"] = "application/json"
req = urllib.request.Request(url, data=payload, method=method, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=30) as response:
        sys.stdout.write(response.read().decode(errors="replace"))
except urllib.error.HTTPError as exc:
    sys.stderr.write(f"HTTP {exc.code} {exc.reason} while calling Authentik internal API\n")
    sys.stderr.write(exc.read().decode(errors="replace")[:4000])
    sys.exit(22)
except Exception as exc:
    sys.stderr.write(f"Authentik internal API request failed: {exc}\n")
    sys.exit(1)
' "$method" "${internal_base}${endpoint}" "$AUTHENTIK_API_TOKEN"
        else
            docker_cmd exec -i authentik-server python3 -c '
import sys, urllib.request, urllib.error
method, url, token = sys.argv[1], sys.argv[2], sys.argv[3]
headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
req = urllib.request.Request(url, method=method, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=30) as response:
        sys.stdout.write(response.read().decode(errors="replace"))
except urllib.error.HTTPError as exc:
    sys.stderr.write(f"HTTP {exc.code} {exc.reason} while calling Authentik internal API\n")
    sys.stderr.write(exc.read().decode(errors="replace")[:4000])
    sys.exit(22)
except Exception as exc:
    sys.stderr.write(f"Authentik internal API request failed: {exc}\n")
    sys.exit(1)
' "$method" "${internal_base}${endpoint}" "$AUTHENTIK_API_TOKEN"
        fi
        return $?
    fi

    msg_warn "authentik-server is not running; cannot call internal Authentik API."
    return 1
}

function verify_authentik_api_for_deploy() {
    section "AUTHENTIK API CHECK"

    local api_response=""
    local api_error=""

    if [ -z "${AUTHENTIK_API_TOKEN:-}" ]; then
        AUTHENTIK_API_OK="skipped-no-token"
        msg_skip "AUTHENTIK API CHECK SKIPPED"
        return 0
    fi

    api_error="$(mktemp)"
    TEMP_FILES+=("$api_error")

    if api_response="$(ak_api GET "/core/users/me/" 2>"$api_error")" && printf '%s' "$api_response" | json_is_valid_object_or_array >/dev/null 2>&1; then
        AUTHENTIK_API_OK="yes"
        msg_ok "AUTHENTIK INTERNAL API ACCESS CONFIRMED"
    else
        AUTHENTIK_API_OK="failed"
        AUTHENTIK_API_TOKEN=""
        msg_warn "Authentik API token/internal API check failed. Protected route automation skipped."
        if [ -s "$api_error" ]; then
            echo -e "${YW}Authentik API diagnostic:${CL}"
            head -n 20 "$api_error" || true
        fi
    fi
}

function authentik_get_flow_pk() {
    local slug="$1"
    local response=""

    response="$(ak_api GET "/flows/instances/?slug=${slug}" 2>/dev/null || true)"
    printf '%s' "$response" | json_get_first_pk
}

function authentik_find_proxy_provider_pk() {
    local response=""
    response="$(ak_api GET "/providers/proxy/?search=Traefik%20Forward%20Auth" 2>/dev/null || true)"
    printf '%s' "$response" | json_get_first_pk
}

function authentik_find_application_pk() {
    local response=""
    response="$(ak_api GET "/core/applications/?slug=traefik-forward-auth" 2>/dev/null || true)"
    printf '%s' "$response" | json_get_first_pk
}

function authentik_find_embedded_outpost_pk() {
    local pk=""
    local response=""

    response="$(ak_api GET "/outposts/instances/?search=authentik%20Embedded%20Outpost" 2>/dev/null || true)"
    pk="$(printf '%s' "$response" | json_get_first_uuid_or_pk)"
    if [ -z "$pk" ]; then
        response="$(ak_api GET "/outposts/instances/?search=Embedded%20Outpost" 2>/dev/null || true)"
        pk="$(printf '%s' "$response" | json_get_first_uuid_or_pk)"
    fi
    printf '%s' "$pk"
}


function authentik_build_outpost_patch_payload() {
    local outpost_file="$1"
    local provider_pk="$2"
    local auth_host="$3"
    local auth_host_browser="$4"

    python3 - "$outpost_file" "$provider_pk" "$auth_host" "$auth_host_browser" <<'AK_OUTPOST_JSON'
import json, sys
path, provider_pk, auth_host, auth_host_browser = sys.argv[1:5]
with open(path, "r", encoding="utf-8") as fh:
    outpost = json.load(fh)
providers = list(outpost.get("providers") or [])
provider_value = int(provider_pk) if provider_pk.isdigit() else provider_pk
if provider_value not in providers:
    providers.append(provider_value)
config = dict(outpost.get("config") or {})
config["authentik_host"] = auth_host
config["authentik_host_browser"] = auth_host_browser or auth_host
payload = {"name": outpost.get("name", "authentik Embedded Outpost"), "type": outpost.get("type", "proxy"), "providers": providers, "config": config}
print(json.dumps(payload))
AK_OUTPOST_JSON
}

function authentik_verify_outpost_patch() {
    local outpost_pk="$1"
    local provider_pk="$2"
    local expected_auth_host="$3"
    local expected_browser_host="$4"
    local response_file=""

    response_file="$(mktemp)"
    TEMP_FILES+=("$response_file")

    if ! ak_api GET "/outposts/instances/${outpost_pk}/" > "$response_file" 2>/dev/null; then
        msg_warn "Could not re-read embedded outpost after patch."
        return 1
    fi

    python3 - "$response_file" "$provider_pk" "$expected_auth_host" "$expected_browser_host" <<'AK_VERIFY_OUTPOST'
import json, sys
path, provider_pk, expected_auth_host, expected_browser_host = sys.argv[1:5]
with open(path, "r", encoding="utf-8") as fh:
    outpost = json.load(fh)
providers = outpost.get("providers") or []
provider_value = int(provider_pk) if provider_pk.isdigit() else provider_pk
config = outpost.get("config") or {}
errors = []
if provider_value not in providers:
    errors.append(f"provider {provider_pk} not attached")
if config.get("authentik_host") != expected_auth_host:
    errors.append("authentik_host mismatch or blank")
if config.get("authentik_host_browser") != (expected_browser_host or expected_auth_host):
    errors.append("authentik_host_browser mismatch or blank")
if errors:
    print("; ".join(errors))
    sys.exit(1)
print("outpost config verified")
AK_VERIFY_OUTPOST
}

function restart_authentik_after_outpost_update() {
    if [ "$AUTHENTIK_OUTPOST_ATTACH_OK" != "yes" ]; then
        return 0
    fi

    msg_info "Restarting Authentik to reload embedded outpost config"
    docker_cmd restart authentik-server authentik-worker >/dev/null
    clear_transient_line
    msg_ok "AUTHENTIK RESTARTED AFTER OUTPOST CONFIG UPDATE"

    msg_info "Waiting for Authentik API and embedded outpost to reload"
    sleep 45
    clear_transient_line
    msg_ok "AUTHENTIK OUTPOST RELOAD WAIT COMPLETE"
}
function create_or_update_authentik_forward_auth_for_deploy() {
    section "AUTHENTIK FORWARD-AUTH SETUP"

    if [ "$AUTHENTIK_API_OK" != "yes" ]; then
        AUTHENTIK_PROVIDER_OK="skipped-no-api"
        AUTHENTIK_APPLICATION_OK="skipped-no-api"
        AUTHENTIK_OUTPOST_ATTACH_OK="skipped-no-api"
        msg_skip "AUTHENTIK API AUTOMATION SKIPPED"
        return 0
    fi

    local authorization_flow=""
    local invalidation_flow=""
    local provider_pk=""
    local app_pk=""
    local outpost_pk=""
    local payload=""
    local response_file=""
    local auth_host_json=""
    local auth_host_value=""
    local auth_host_browser_value=""
    local domain_json=""
    local outpost_response_file=""

    response_file="$(mktemp)"
    TEMP_FILES+=("$response_file")

    authorization_flow="$(authentik_get_flow_pk "default-provider-authorization-implicit-consent")"
    [ -n "$authorization_flow" ] || authorization_flow="$(authentik_get_flow_pk "default-provider-authorization-explicit-consent")"
    invalidation_flow="$(authentik_get_flow_pk "default-provider-invalidation-flow")"

    if [ -z "$authorization_flow" ] || [ -z "$invalidation_flow" ]; then
        AUTHENTIK_PROVIDER_OK="flow-missing"
        msg_warn "Required Authentik default provider flows were not found through the internal API."
        detail_line "Authorization flow" "${authorization_flow:-missing}"
        detail_line "Invalidation flow" "${invalidation_flow:-missing}"
        return 0
    fi

    auth_host_value="${AUTHENTIK_HOST:-https://auth.${DOMAIN_VALUE}}"
    auth_host_browser_value="${AUTHENTIK_HOST_BROWSER:-$auth_host_value}"
    auth_host_json="$(printf '%s' "$auth_host_value" | json_escape)"
    domain_json="$(printf '%s' ".${DOMAIN_VALUE}" | json_escape)"

    provider_pk="$(authentik_find_proxy_provider_pk)"
    payload="$(cat <<JSON
{
  "name": "Traefik Forward Auth",
  "authorization_flow": "${authorization_flow}",
  "invalidation_flow": "${invalidation_flow}",
  "mode": "forward_domain",
  "external_host": ${auth_host_json},
  "cookie_domain": ${domain_json},
  "basic_auth_enabled": false,
  "skip_path_regex": "^/outpost.goauthentik.io/.*$"
}
JSON
)"

    if [ -z "$provider_pk" ]; then
        ak_api POST "/providers/proxy/" "$payload" > "$response_file" || true
        provider_pk="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data.get("pk", ""))' "$response_file" 2>/dev/null || true)"
    else
        ak_api PATCH "/providers/proxy/${provider_pk}/" "$payload" > "$response_file" || true
    fi

    if [ -z "$provider_pk" ]; then
        AUTHENTIK_PROVIDER_OK="failed"
        msg_warn "Forward-auth provider automation failed."
        return 0
    fi
    AUTHENTIK_PROVIDER_OK="yes"
    msg_ok "TRAEFIK FORWARD-AUTH PROVIDER READY"

    app_pk="$(authentik_find_application_pk)"
    payload="$(cat <<JSON
{
  "name": "Traefik Forward Auth",
  "slug": "traefik-forward-auth",
  "provider": "${provider_pk}",
  "meta_launch_url": "${auth_host_value}"
}
JSON
)"

    if [ -z "$app_pk" ]; then
        ak_api POST "/core/applications/" "$payload" > "$response_file" || true
        app_pk="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data.get("pk", ""))' "$response_file" 2>/dev/null || true)"
    else
        ak_api PATCH "/core/applications/${app_pk}/" "$payload" > "$response_file" || true
    fi

    if [ -z "$app_pk" ]; then
        AUTHENTIK_APPLICATION_OK="failed"
        msg_warn "Forward-auth application automation failed."
        return 0
    fi
    AUTHENTIK_APPLICATION_OK="yes"
    msg_ok "TRAEFIK FORWARD-AUTH APPLICATION READY"

    outpost_pk="$(authentik_find_embedded_outpost_pk)"
    if [ -z "$outpost_pk" ]; then
        AUTHENTIK_OUTPOST_ATTACH_OK="not-found"
        msg_warn "Existing authentik Embedded Outpost was not found; do not create a second custom outpost."
        return 0
    fi

    outpost_response_file="$(mktemp)"
    TEMP_FILES+=("$outpost_response_file")

    if ! ak_api GET "/outposts/instances/${outpost_pk}/" > "$outpost_response_file" 2>/dev/null; then
        AUTHENTIK_OUTPOST_ATTACH_OK="failed-read"
        msg_warn "Could not read embedded outpost before patching."
        return 0
    fi

    payload="$(authentik_build_outpost_patch_payload "$outpost_response_file" "$provider_pk" "$auth_host_value" "$auth_host_browser_value")"

    if ak_api PATCH "/outposts/instances/${outpost_pk}/" "$payload" >/dev/null 2>&1; then
        if authentik_verify_outpost_patch "$outpost_pk" "$provider_pk" "$auth_host_value" "$auth_host_browser_value" >/dev/null 2>&1; then
            AUTHENTIK_OUTPOST_ATTACH_OK="yes"
            msg_ok "PROVIDER AND AUTHENTIK HOST CONFIG ATTACHED TO EXISTING EMBEDDED OUTPOST"
            detail_line "Outpost" "$outpost_pk"
            detail_line "authentik_host" "$auth_host_value"
            detail_line "authentik_host_browser" "$auth_host_browser_value"
        else
            AUTHENTIK_OUTPOST_ATTACH_OK="verify-failed"
            msg_warn "Outpost patch completed but verification failed. Re-check embedded outpost config in Authentik."
        fi
    else
        AUTHENTIK_OUTPOST_ATTACH_OK="failed"
        msg_warn "Outpost attach/config patch failed. Attach the provider and Authentik host manually in Authentik."
    fi
}

function verify_authentik_outpost_route_for_deploy() {
    section "AUTHENTIK OUTPOST ROUTE CHECK"

    local test_host="${ADMIN_UI_HOST:-dockge.${DOMAIN_VALUE}}"
    local test_url="https://${test_host}/outpost.goauthentik.io/start?rd=https://${test_host}/"
    local http_code=""

    # Use GET instead of HEAD because some Authentik/Traefik protected routes handle HEAD
    # differently and can produce misleading Authentik-powered 404 results.
    http_code="$(curl -ksS -o /dev/null -w '%{http_code}' "$test_url" || true)"
    if [[ "$http_code" =~ ^(302|303|307)$ ]]; then
        AUTHENTIK_OUTPOST_302_OK="yes"
        msg_ok "AUTHENTIK OUTPOST ROUTE REDIRECTED AS EXPECTED"
    else
        AUTHENTIK_OUTPOST_302_OK="no"
        msg_warn "Authentik outpost GET route returned HTTP ${http_code:-none}; protected routes may still need UI confirmation."
    fi

    detail_line "Outpost test URL" "$test_url"
    detail_line "HTTP result" "${http_code:-none}"
}

function detect_recent_acme_rate_limit() {
    local domain_pattern="${DOMAIN_VALUE:-}"

    [ -n "$domain_pattern" ] || return 1

    docker_cmd logs --tail=260 traefik 2>/dev/null | grep -Eiq "rateLimited|too many certificates|acme: error: 429|${domain_pattern}"
}

function verify_authentik_public_host_route() {
    section "AUTHENTIK PUBLIC HOST CHECK"

    local auth_host="auth.${DOMAIN_VALUE}"
    local public_code=""
    local local_code=""
    local headers_file=""

    headers_file="$(mktemp)"
    TEMP_FILES+=("$headers_file")

    # Public check catches Cloudflare 525. Local --resolve check catches missing
    # Traefik SNI/router/certificate before Cloudflare is involved.
    public_code="$(curl -ksS -D "$headers_file" -o /dev/null -w '%{http_code}' "https://${auth_host}/" || true)"
    local_code="$(curl -ksS -o /dev/null -w '%{http_code}' --resolve "${auth_host}:443:127.0.0.1" "https://${auth_host}/" || true)"

    case "$public_code" in
        200|301|302|303|307|401|403)
            AUTHENTIK_HOST_ROUTE_OK="yes"
            msg_ok "AUTHENTIK PUBLIC HOST RESPONDED: ${auth_host} HTTP ${public_code}"
            detail_line "Local Traefik/SNI check" "HTTP ${local_code:-none}"
            return 0
            ;;
        525)
            if detect_recent_acme_rate_limit; then
                AUTHENTIK_HOST_ROUTE_OK="acme-rate-limited"
                msg_warn "AUTHENTIK PUBLIC HOST FAILED: ${auth_host} HTTP 525 with recent ACME rate-limit evidence."
                detail_line "Diagnosis" "Let’s Encrypt ACME 429/rate-limit; wait for retry window or use staging/origin-cert test mode"
            else
                AUTHENTIK_HOST_ROUTE_OK="auth-host-tls-failed"
                msg_warn "AUTHENTIK PUBLIC HOST FAILED: ${auth_host} HTTP 525. Origin TLS/Traefik certificate is not ready."
            fi
            detail_line "Local Traefik/SNI check" "HTTP ${local_code:-none}"
            return 1
            ;;
        *)
            if [ "$local_code" == "000" ] || [ -z "$local_code" ]; then
                if detect_recent_acme_rate_limit; then
                    AUTHENTIK_HOST_ROUTE_OK="acme-rate-limited"
                    msg_warn "AUTHENTIK LOCAL SNI CHECK FAILED and Traefik logs show ACME rate-limit evidence."
                    detail_line "Diagnosis" "Traefik cannot present auth.${DOMAIN_VALUE} certificate yet because ACME is rate-limited"
                else
                    AUTHENTIK_HOST_ROUTE_OK="auth-host-tls-failed"
                    msg_warn "AUTHENTIK LOCAL SNI CHECK FAILED for ${auth_host}; Traefik has no usable TLS route/cert yet."
                fi
                detail_line "Public HTTP result" "${public_code:-none}"
                detail_line "Local Traefik/SNI check" "HTTP ${local_code:-none}"
                return 1
            fi
            AUTHENTIK_HOST_ROUTE_OK="needs-review"
            msg_warn "AUTHENTIK PUBLIC HOST NEEDS REVIEW: ${auth_host} HTTP ${public_code:-none}, local HTTP ${local_code:-none}"
            return 1
            ;;
    esac
}

function verify_selected_protected_routes() {
    section "PROTECTED ROUTE CHECKS"

    local host=""
    local code=""
    local headers_file=""
    local powered_by=""
    local failures="0"
    local hosts=()

    headers_file="$(mktemp)"
    TEMP_FILES+=("$headers_file")

    verify_authentik_public_host_route || failures=$((failures + 1))

    hosts+=("${ADMIN_UI_HOST:-dockge.${DOMAIN_VALUE}}")
    if [[ "$DEPLOY_VSCODE" =~ ^[Yy] ]]; then hosts+=("code.${DOMAIN_VALUE}"); fi
    if [[ "$DEPLOY_FILEBROWSER" =~ ^[Yy] ]]; then hosts+=("fb.${DOMAIN_VALUE}"); fi

    for host in "${hosts[@]}"; do
        : > "$headers_file"
        # Use GET and capture headers so Authentik-powered 404s are treated as a protected-route
        # setup failure instead of a healthy app response.
        code="$(curl -ksS -D "$headers_file" -o /dev/null -w '%{http_code}' "https://${host}/" || true)"
        powered_by="$(awk 'BEGIN{IGNORECASE=1} /^x-powered-by:/ {print $0}' "$headers_file" | tr -d '\r' || true)"
        case "$code" in
            200|302|303|307|401|403)
                msg_ok "ROUTE RESPONDED: ${host} HTTP ${code}"
                ;;
            404)
                failures=$((failures + 1))
                if printf '%s' "$powered_by" | grep -qi 'authentik'; then
                    msg_warn "ROUTE CHECK FAILED: ${host} HTTP 404 from Authentik. Verify provider/application/outpost attachment and Traefik forward-auth."
                else
                    msg_warn "ROUTE CHECK FAILED: ${host} HTTP 404"
                fi
                ;;
            525)
                failures=$((failures + 1))
                msg_warn "ROUTE CHECK FAILED: ${host} HTTP 525 from Cloudflare. Origin TLS/Traefik certificate is not compatible with current Cloudflare SSL mode yet."
                ;;
            *)
                failures=$((failures + 1))
                msg_warn "ROUTE CHECK NEEDS ATTENTION: ${host} HTTP ${code:-none}"
                ;;
        esac
    done

    if [ "$failures" -eq 0 ] && [ "$AUTHENTIK_HOST_ROUTE_OK" == "yes" ]; then
        PROTECTED_ROUTE_VERIFY_OK="yes"
    elif [ "$AUTHENTIK_HOST_ROUTE_OK" == "acme-rate-limited" ]; then
        PROTECTED_ROUTE_VERIFY_OK="acme-rate-limited"
    elif [ "$AUTHENTIK_HOST_ROUTE_OK" == "auth-host-tls-failed" ]; then
        PROTECTED_ROUTE_VERIFY_OK="auth-host-tls-failed"
    else
        PROTECTED_ROUTE_VERIFY_OK="needs-review"
    fi
}

function configure_authentik_and_verify_routes() {
    verify_authentik_dependencies_for_deploy
    if [ "$AUTHENTIK_DEPENDENCIES_OK" == "yes" ]; then
        wait_for_authentik_internal_api_ready
    fi
    collect_authentik_api_token_for_deploy
    verify_authentik_api_for_deploy
    create_or_update_authentik_forward_auth_for_deploy
    restart_authentik_after_outpost_update
    verify_authentik_outpost_route_for_deploy
    verify_selected_protected_routes
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
# Downloads Socket Proxy stack, selected Admin UI stack and Admin UI bootstrap override from GitHub into docker/compose.
function download_bootstrap_compose_files() {
    section "STACK COMPOSE DOWNLOAD"

    msg_info "Downloading Socket Proxy stack compose"
    curl --globoff -fsSL "$SOCKET_PROXY_STACK_URL" -o "${COMPOSE_DIR}/${SOCKET_PROXY_STACK_FILE}"
    SOCKET_PROXY_STACK_DOWNLOADED="yes"
    msg_ok "SOCKET PROXY STACK COMPOSE DOWNLOADED"

    case "$ADMIN_UI" in
        portainer)
            msg_info "Downloading Portainer stack compose"
            curl --globoff -fsSL "$PORTAINER_STACK_URL" -o "${COMPOSE_DIR}/${PORTAINER_STACK_FILE}"
            PORTAINER_STACK_DOWNLOADED="yes"
            msg_ok "ADMIN UI STACK COMPOSE DOWNLOADED"

            msg_info "Downloading Admin UI bootstrap override"
            curl --globoff -fsSL "$PORTAINER_BOOTSTRAP_OVERRIDE_URL" -o "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
            PORTAINER_BOOTSTRAP_OVERRIDE_DOWNLOADED="yes"
            msg_ok "PORTAINER BOOTSTRAP OVERRIDE DOWNLOADED"
            ;;
        dockge)
            msg_info "Downloading Dockge stack compose"
            curl --globoff -fsSL "$DOCKGE_STACK_URL" -o "${COMPOSE_DIR}/${DOCKGE_STACK_FILE}"
            DOCKGE_STACK_DOWNLOADED="yes"
            msg_ok "DOCKGE STACK COMPOSE DOWNLOADED"

            msg_info "Downloading Dockge bootstrap override"
            curl --globoff -fsSL "$DOCKGE_BOOTSTRAP_OVERRIDE_URL" -o "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
            DOCKGE_BOOTSTRAP_OVERRIDE_DOWNLOADED="yes"
            msg_ok "DOCKGE BOOTSTRAP OVERRIDE DOWNLOADED"
            ;;
        komodo)
            msg_info "Downloading Komodo stack compose"
            curl --globoff -fsSL "$KOMODO_STACK_URL" -o "${COMPOSE_DIR}/${KOMODO_STACK_FILE}"
            KOMODO_STACK_DOWNLOADED="yes"
            msg_ok "KOMODO STACK COMPOSE DOWNLOADED"

            msg_info "Downloading Komodo bootstrap override"
            curl --globoff -fsSL "$KOMODO_BOOTSTRAP_OVERRIDE_URL" -o "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
            KOMODO_BOOTSTRAP_OVERRIDE_DOWNLOADED="yes"
            msg_ok "KOMODO BOOTSTRAP OVERRIDE DOWNLOADED"
            ;;
        dockhand)
            msg_info "Downloading Dockhand stack compose"
            curl --globoff -fsSL "$DOCKHAND_STACK_URL" -o "${COMPOSE_DIR}/${DOCKHAND_STACK_FILE}"
            DOCKHAND_STACK_DOWNLOADED="yes"
            msg_ok "DOCKHAND STACK COMPOSE DOWNLOADED"

            msg_info "Downloading Dockhand bootstrap override"
            curl --globoff -fsSL "$DOCKHAND_BOOTSTRAP_OVERRIDE_URL" -o "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
            DOCKHAND_BOOTSTRAP_OVERRIDE_DOWNLOADED="yes"
            msg_ok "DOCKHAND BOOTSTRAP OVERRIDE DOWNLOADED"
            ;;
    esac

    ADMIN_UI_BOOTSTRAP_OVERRIDE_WRITTEN="downloaded"

    run_cmd "setting Socket Proxy compose file ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "${COMPOSE_DIR}/${SOCKET_PROXY_STACK_FILE}"
    run_cmd "setting Socket Proxy compose file permissions" chmod 640 "${COMPOSE_DIR}/${SOCKET_PROXY_STACK_FILE}"
    run_cmd "setting ${ADMIN_UI_DISPLAY_NAME} compose ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$ADMIN_UI_COMPOSE_FILE" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
    run_cmd "setting ${ADMIN_UI_DISPLAY_NAME} compose permissions" chmod 640 "$ADMIN_UI_COMPOSE_FILE" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"
    sync_compose_file_for_dockge "$SOCKET_PROXY_STACK_FILE" "${COMPOSE_DIR}/${SOCKET_PROXY_STACK_FILE}"
    sync_compose_file_for_dockge "$(basename "$ADMIN_UI_COMPOSE_FILE")" "$ADMIN_UI_COMPOSE_FILE"
    sync_bootstrap_override_for_dockge "$(basename "$ADMIN_UI_COMPOSE_FILE")" "$ADMIN_UI_BOOTSTRAP_OVERRIDE_FILE"

    detail_line "Socket Proxy stack" "${COMPOSE_DIR}/${SOCKET_PROXY_STACK_FILE}"
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
# Validates Socket Proxy stack, selected Admin UI stack and Admin UI bootstrap override before deployment.
function validate_bootstrap_compose_files() {
    section "STACK COMPOSE VALIDATION"

    msg_info "Validating Socket Proxy stack compose"
    run_docker_cmd "validating Socket Proxy stack compose" compose --env-file "$ENV_FILE" -p socket-proxy -f "$(compose_path_for_stack_file "$SOCKET_PROXY_STACK_FILE")" config -q
    msg_ok "SOCKET PROXY STACK COMPOSE VALID"

    msg_info "Validating ${ADMIN_UI_DISPLAY_NAME} stack compose with bootstrap override"
    export PORTAINER_BOOTSTRAP_PORT DOCKGE_BOOTSTRAP_PORT KOMODO_BOOTSTRAP_PORT DOCKHAND_BOOTSTRAP_PORT ADMIN_UI_BOOTSTRAP_BIND
    run_docker_cmd "validating ${ADMIN_UI_DISPLAY_NAME} stack compose" compose --env-file "$ENV_FILE" -p "$ADMIN_UI_PROJECT_NAME" -f "$(compose_path_for_stack_file "$(basename "$ADMIN_UI_COMPOSE_FILE")")" -f "$(bootstrap_override_path_for_primary_file "$(basename "$ADMIN_UI_COMPOSE_FILE")")" config -q
    msg_ok "${ADMIN_UI_DISPLAY_NAME^^} STACK COMPOSE VALID"

    ADMIN_UI_VALIDATED="yes"
}
# --- 39. SOCKET-PROXY DEPLOYMENT ---
# Deploys the Socket Proxy stack using Docker Compose.
function deploy_socket_proxy() {
    section "DEPLOY STACK - SOCKET PROXY"

    local compose_path=""
    compose_path="$(compose_path_for_stack_file "$SOCKET_PROXY_STACK_FILE")"
    detail_line "Compose file" "$compose_path"
    compose_up_quiet "deploying socket-proxy" --env-file "$ENV_FILE" -p socket-proxy -f "$compose_path"
    SOCKET_PROXY_DEPLOYED="yes"
    msg_ok "SOCKET-PROXY DEPLOYED"
}

# --- 40. PORTAINER DEPLOYMENT ---
# Deploys the selected Admin UI stack with its temporary bootstrap override.
function deploy_admin_ui() {
    section "DEPLOY STACK - ${ADMIN_UI_DISPLAY_NAME}"

    local admin_compose_path=""
    local admin_override_path=""

    export PORTAINER_BOOTSTRAP_PORT DOCKGE_BOOTSTRAP_PORT KOMODO_BOOTSTRAP_PORT DOCKHAND_BOOTSTRAP_PORT ADMIN_UI_BOOTSTRAP_BIND
    admin_compose_path="$(compose_path_for_stack_file "$(basename "$ADMIN_UI_COMPOSE_FILE")")"
    admin_override_path="$(bootstrap_override_path_for_primary_file "$(basename "$ADMIN_UI_COMPOSE_FILE")")"
    detail_line "Compose file" "$admin_compose_path"
    detail_line "Bootstrap override" "$admin_override_path"
    compose_up_quiet "deploying ${ADMIN_UI_DISPLAY_NAME}" --env-file "$ENV_FILE" -p "$ADMIN_UI_PROJECT_NAME" -f "$admin_compose_path" -f "$admin_override_path"
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
        echo "Socket Proxy stack compose downloaded: ${SOCKET_PROXY_STACK_DOWNLOADED}"
        echo "Portainer stack compose downloaded: ${PORTAINER_STACK_DOWNLOADED}"
        echo "Portainer bootstrap override downloaded: ${PORTAINER_BOOTSTRAP_OVERRIDE_DOWNLOADED}"
        echo "Dockge stack compose downloaded: ${DOCKGE_STACK_DOWNLOADED}"
        echo "Komodo stack compose downloaded: ${KOMODO_STACK_DOWNLOADED}"
        echo "Dockhand stack compose downloaded: ${DOCKHAND_STACK_DOWNLOADED}"
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
        echo "CF companion secret: ${CF_COMPANION_SECRET_OK}"
        echo "Filebrowser folders: ${FILEBROWSER_FOLDERS_OK}"
        echo "Authentik dependency gate: ${AUTHENTIK_DEPENDENCIES_OK}"
        echo "Authentik API: ${AUTHENTIK_API_OK}"
        echo "Authentik provider: ${AUTHENTIK_PROVIDER_OK}"
        echo "Authentik application: ${AUTHENTIK_APPLICATION_OK}"
        echo "Authentik outpost attach: ${AUTHENTIK_OUTPOST_ATTACH_OK}"
        echo "Authentik outpost 302: ${AUTHENTIK_OUTPOST_302_OK}"
        echo "Authentik public host route: ${AUTHENTIK_HOST_ROUTE_OK}"
        echo "Protected routes: ${PROTECTED_ROUTE_VERIFY_OK}"
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
Socket Proxy stack downloaded: $SOCKET_PROXY_STACK_DOWNLOADED
Admin stack downloaded: $PORTAINER_STACK_DOWNLOADED
Portainer bootstrap override downloaded: $PORTAINER_BOOTSTRAP_OVERRIDE_DOWNLOADED
Dockge stack compose downloaded: $DOCKGE_STACK_DOWNLOADED
Komodo stack compose downloaded: $KOMODO_STACK_DOWNLOADED
Dockhand stack compose downloaded: $DOCKHAND_STACK_DOWNLOADED
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
CF companion secret OK: $CF_COMPANION_SECRET_OK
Filebrowser folders OK: $FILEBROWSER_FOLDERS_OK
Authentik dependency gate: $AUTHENTIK_DEPENDENCIES_OK
Authentik API OK: $AUTHENTIK_API_OK
Authentik provider OK: $AUTHENTIK_PROVIDER_OK
Authentik application OK: $AUTHENTIK_APPLICATION_OK
Authentik outpost attach OK: $AUTHENTIK_OUTPOST_ATTACH_OK
Authentik outpost 302 OK: $AUTHENTIK_OUTPOST_302_OK
Authentik public host route: $AUTHENTIK_HOST_ROUTE_OK
Protected routes OK: $PROTECTED_ROUTE_VERIFY_OK
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
Socket Proxy stack downloaded: $SOCKET_PROXY_STACK_DOWNLOADED
Admin stack downloaded: $PORTAINER_STACK_DOWNLOADED
Portainer bootstrap override downloaded: $PORTAINER_BOOTSTRAP_OVERRIDE_DOWNLOADED
Dockge stack compose downloaded: $DOCKGE_STACK_DOWNLOADED
Komodo stack compose downloaded: $KOMODO_STACK_DOWNLOADED
Dockhand stack compose downloaded: $DOCKHAND_STACK_DOWNLOADED
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
CF companion secret OK: $CF_COMPANION_SECRET_OK
Filebrowser folders OK: $FILEBROWSER_FOLDERS_OK
Authentik dependency gate: $AUTHENTIK_DEPENDENCIES_OK
Authentik API OK: $AUTHENTIK_API_OK
Authentik provider OK: $AUTHENTIK_PROVIDER_OK
Authentik application OK: $AUTHENTIK_APPLICATION_OK
Authentik outpost attach OK: $AUTHENTIK_OUTPOST_ATTACH_OK
Authentik outpost 302 OK: $AUTHENTIK_OUTPOST_302_OK
Authentik public host route: $AUTHENTIK_HOST_ROUTE_OK
Protected routes OK: $PROTECTED_ROUTE_VERIFY_OK
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
    detail_line "SOCKET PROXY STACK" "${COMPOSE_DIR}/${SOCKET_PROXY_STACK_FILE}"
    detail_line "ADMIN UI" "$ADMIN_UI_DISPLAY_NAME"
    detail_line "ADMIN UI COMPOSE" "$ADMIN_UI_COMPOSE_FILE"
    detail_line "ADMIN UI HOST" "$ADMIN_UI_HOST"
    detail_line "REDIS SYSCTL" "$SYSCTL_REDIS_OK"
    detail_line "TRAEFIK PLACEHOLDERS" "$TRAEFIK_PLACEHOLDERS_OK"
    detail_line "TRAEFIK DNS V3.7" "$TRAEFIK_DNS_DELAY_OK"
    detail_line "TRAEFIK ENCODED CHARS" "$TRAEFIK_ENCODED_CHARS_OK"
    detail_line "AUTHENTIK FOLDERS" "$AUTHENTIK_FOLDERS_OK"
    detail_line "FILEBROWSER FOLDERS" "$FILEBROWSER_FOLDERS_OK"
    detail_line "AUTHENTIK DEPENDENCIES" "$AUTHENTIK_DEPENDENCIES_OK"
    detail_line "AUTHENTIK API" "$AUTHENTIK_API_OK"
    detail_line "AUTHENTIK PUBLIC HOST" "$AUTHENTIK_HOST_ROUTE_OK"
    detail_line "PROTECTED ROUTES" "$PROTECTED_ROUTE_VERIFY_OK"
    detail_line "Admin UI temporary URL" "$ADMIN_UI_BOOTSTRAP_ACCESS_URL"
    detail_line "Bootstrap port" "$ADMIN_UI_BOOTSTRAP_PORT"
    detail_line "Verify log" "$VERIFY_LOG"

    echo ""
    echo -e "${YW}${ADMIN_UI_DISPLAY_NAME} is temporarily available by direct IP for bootstrap:${CL}"
    echo -e "${GN}${ADMIN_UI_BOOTSTRAP_ACCESS_URL}${CL}"
    echo -e "${YW}Script 7 will close this direct bootstrap port and leave access through Traefik/AuthentiK.${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}Review the route verification results above.${CL}"
    echo -e "${YW}When protected domain access is confirmed, run Script 7 for final hardening, cleanup and bootstrap-port closure.${CL}"
    echo ""
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 47. MAIN FUNCTION ---
# Runs Docker network + socket-proxy + Admin UI bootstrap in safe order.
# --- READY TO APPLY SUMMARY ---
# Confirms all collected bootstrap answers before networks, compose downloads, firewall changes or containers are changed.
function show_ready_to_apply() {
    local apply_yn=""

    section "READY TO APPLY"

    echo -e "${YW}All questions have been collected. No Docker networks, compose files, firewall rules or containers have been changed yet.${CL}"
    echo ""
    detail_line "Docker user" "$DOCKER_USER"
    detail_line "Docker directory" "$DOCKER_DIR"
    detail_line "Compose directory" "$COMPOSE_DIR"
    detail_line ".env file" "$ENV_FILE"
    detail_line "Admin UI" "$ADMIN_UI_DISPLAY_NAME"
    detail_line "Admin UI host" "$ADMIN_UI_HOST"
    detail_line "Bootstrap port" "$ADMIN_UI_BOOTSTRAP_PORT"
    detail_line "GitHub raw base" "$GITHUB_RAW_BASE"
    echo ""
    echo -e "${BL}DEPENDENCY / STACK PLAN:${CL}"
    detail_line "Required" "Socket Proxy + ${ADMIN_UI_DISPLAY_NAME} bootstrap"
    if [ "${#SELECTED_STACK_FILES[@]}" -eq 0 ]; then
        detail_line "Additional stacks" "none selected"
    else
        local i=""
        for i in "${!SELECTED_STACK_FILES[@]}"; do
            detail_line "${SELECTED_STACK_FILES[$i]}" "${DEPENDENCY_REASONS[$i]}"
        done
    fi
    echo ""
    echo -e "${RD}${CLF}After confirmation, the script will create networks, download fixed compose files, open bootstrap access and deploy selected containers in safe order.${CL}"
    echo ""

    apply_yn="$(timed_yes_no "Apply this Docker Bootstrap setup plan now?" "y")"

    if [[ "$apply_yn" =~ ^[Nn] ]]; then
        echo -e "${YW}Docker Bootstrap Setup cancelled. No Docker/bootstrap-changing actions were applied.${CL}"
        exit 0
    fi

    return 0
}

function main() {
    init_script

    detect_docker_access
    check_previous_marker
    start_confirmation
    collect_bootstrap_settings
    validate_project_paths
    verify_admin_ui_selection
    collect_stack_deployment_choices
    verify_selected_stack_preflight
    show_ready_to_apply

    create_shared_networks
    verify_shared_networks

    download_selected_compose_files
    verify_admin_ui_bootstrap_override_file
    verify_selected_compose_env_coverage
    validate_selected_compose_files
    prepare_postgres_runtime_prereqs
    prepare_redis_runtime_prereqs

    configure_bootstrap_firewall
    deploy_selected_stacks
    verify_bootstrap_containers
    verify_cf_companion_runtime_if_selected
    configure_authentik_and_verify_routes
    create_verification_report
    write_completion_marker
    show_final_summary

    exit 0
}

main "$@"
