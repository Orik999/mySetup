#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Project Crea - Post-Core Production/Add-on Setup
# =========================================================
# Current module: n8n Automation
# Future modules can be added using the same detect/prompt/deploy/repair/verify pattern.
# Script 8 is additive and service-aware: it must not touch working core stacks
# from Scripts 1-7 unless a current add-on service explicitly requires a read-only check.

# --- 1. COLOR VARIABLES ---
YW="$(printf '\033[33m')"
BL="$(printf '\033[36m')"
RD="$(printf '\033[01;31m')"
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

SCRIPT_SOURCE="8-postCoreSetup.sh"
SCRIPT_VERSION="v1.0.1"
SCRIPT_UPDATED="2026-05-26"
SCRIPT_BUILD="n8n-post-core-baseline-hardening"

# --- 2. GLOBAL VARIABLES ---
T=15

LOG_FILE="/var/log/crea-post-core-setup.log"
RUNTIME_LOG_FILE=""
VERIFY_LOG="/var/log/crea-post-core-setup-verify.log"
COMPLETED_MARKER="/root/.crea-post-core-setup-completed"

DEFAULT_DOCKER_USER="${SUDO_USER:-orik}"
DOCKER_USER="${DOCKER_USER:-$DEFAULT_DOCKER_USER}"
DOCKER_DIR="${DOCKER_DIR:-/home/${DOCKER_USER}/docker}"
COMPOSE_DIR="${COMPOSE_DIR:-${DOCKER_DIR}/compose}"
ENV_FILE="${ENV_FILE:-${DOCKER_DIR}/.env}"
GITHUB_RAW_BASE="${GITHUB_RAW_BASE:-https://raw.githubusercontent.com/Orik999/mySetup/main/docker}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


DOMAIN=""
ADMIN_UI="unknown"
DOCKER_NEEDS_SUDO="no"
SUDO_CMD=""
LOGGING_ENABLED="no"

# n8n module constants. User-facing UI must use friendly service names; internal filenames stay internal.
N8N_SERVICE_NAME="n8n Automation"
N8N_STACK_FILE="13-n8n-compose.yml"
N8N_STACK_URL_OVERRIDE="${N8N_STACK_URL:-}"
N8N_STACK_URL="${N8N_STACK_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${N8N_STACK_FILE}}"
N8N_PROJECT="n8n"
N8N_COMPOSE_FILE=""
N8N_FLAT_COMPOSE_FILE=""
N8N_APPDATA_DIR=""
N8N_BUNDLED_COMPOSE_FILE=""
N8N_COMPOSE_SOURCE="unknown"
N8N_ENV_MAY_EDIT="no"
N8N_ENV_BACKUP_CREATED="no"
N8N_ENV_BACKUP_PATH=""
ENV_BACKED_UP_THIS_RUN="no"
N8N_DB_IDENTIFIER_STATUS="not-checked"
N8N_SECRET_STATUS_LINES=()
N8N_APPDATA_OWNER=""
N8N_MAIN_HEALTH="unknown"
N8N_WORKER_HEALTH="unknown"
N8N_ROUTE_WARNING="not-checked"

# n8n state and results.
N8N_STATE="unknown"
N8N_ACTION="not-run"
N8N_ENV_READY="no"
N8N_APPDATA_READY="no"
N8N_DB_READY="no"
N8N_REDIS_READY="no"
N8N_COMPOSE_READY="no"
N8N_DEPLOYED="no"
N8N_MAIN_RUNNING="no"
N8N_WORKER_RUNNING="no"
N8N_UI_ROUTE_OK="no"
N8N_WEBHOOK_ROUTE_OK="no"
N8N_VERIFIED="no"
N8N_TOUCHED="no"

TEMP_FILES=()
GENERATED_SECRET_LINES=()
SUMMARY_LINES=()

# =========================================================
#  OUTPUT HELPERS
# =========================================================

function header_info() {
echo -e "${BL}
██████╗  ██████╗ ███████╗████████╗      ██████╗ ██████╗ ██████╗ ███████╗
██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝     ██╔════╝██╔═══██╗██╔══██╗██╔════╝
██████╔╝██║   ██║███████╗   ██║        ██║     ██║   ██║██████╔╝█████╗  
██╔═══╝ ██║   ██║╚════██║   ██║        ██║     ██║   ██║██╔══██╗██╔══╝  
██║     ╚██████╔╝███████║   ██║        ╚██████╗╚██████╔╝██║  ██║███████╗
╚═╝      ╚═════╝ ╚══════╝   ╚═╝         ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝
${CL}"
}

function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_skip() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }
function clear_transient_line() { tty_print "${BFR}"; }

function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

function section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

function detail_line() {
    local label="$1"
    local value="$2"
    echo -e " ${BL}━━━━━▶${CL} ${label}: ${GN}${value}${CL}"
}

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

# =========================================================
#  CLEANUP / ERROR HANDLING
# =========================================================

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

function on_error() {
    local line_no="$1"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"
}

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
            echo -e "${YW}Command arguments hidden for secret safety.${CL}"
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
            echo -e "${YW}Command arguments hidden for secret safety.${CL}"
            echo ""
            echo -e "${RD}Real error:${CL}"
            cat "$err_file"
            rm -f "$err_file"
            exit 1
        fi
    fi

    rm -f "$err_file"
}

function run_optional() {
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" "$@" >/dev/null 2>&1 || true
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

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
#  PROMPT HELPERS
# =========================================================

function flush_input_buffer() {
    local junk=""
    local i=""
    [ -r /dev/tty ] || return 0
    for i in {1..20}; do
        if ! IFS= read -rsn1 -t 0.02 junk < /dev/tty 2>/dev/null; then
            break
        fi
    done
}

function yes_no_label() {
    local value="$1"
    if [[ "$value" =~ ^[Yy]$ ]]; then echo "yes"; else echo "no"; fi
}

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
        if [ "$remaining" -le 0 ]; then answer="$default"; break; fi
        tty_print "${BFR}${YW}${prompt} (${default_label}) [${remaining}s]${CL} "

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                if [[ "$key" == " " ]]; then answer="$(tty_read_yes_no_blocking "$prompt" "$default")"; break
                elif [[ "$key" =~ ^[YyNn]$ ]]; then answer="$key"; break
                elif [[ -z "$key" ]]; then answer="$default"; break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then answer="$(tty_read_yes_no_blocking "$prompt" "$default")"; break
                elif [[ "$key" =~ ^[YyNn]$ ]]; then answer="$key"; break
                elif [[ -z "$key" ]]; then answer="$default"; break
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
            "") [ -z "$answer" ] && answer="$default"; tty_print "${BFR}"; echo "$answer"; flush_input_buffer; return 0 ;;
            $'\177'|$'\b') answer="${answer%?}" ;;
            *) answer+="$key" ;;
        esac
    done
}

function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""
    answer="$(editable_input_loop "$prompt" "$default" "")"
    [ -z "$answer" ] && answer="$default"
    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
    flush_input_buffer 2>/dev/null || true
    echo "$answer"
}

function sensitive_line_input() {
    local prompt="$1"
    local answer=""
    tty_print "${YW}${prompt}: ${CL}"
    if [ -r /dev/tty ]; then
        IFS= read -rs answer < /dev/tty || true
    else
        IFS= read -rs answer || true
    fi
    tty_println ""
    printf '%s' "$answer"
}

function read_menu_choice() {
    local prompt="$1"
    local default="$2"
    local answer=""
    flush_input_buffer
    tty_print "${YW}${prompt} [default: ${default}]: ${CL}"
    if [ -r /dev/tty ]; then
        IFS= read -r answer < /dev/tty || true
    else
        IFS= read -r answer || true
    fi
    answer="${answer:-$default}"
    printf '%s' "$answer"
}

# =========================================================
#  INIT / VALIDATION
# =========================================================

function detect_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then SUDO_CMD=""; else SUDO_CMD="sudo"; fi
}

function validate_sudo_access() {
    if [ -n "$SUDO_CMD" ]; then
        msg_info "Validating sudo access"
        if "$SUDO_CMD" -n true >/dev/null 2>&1; then msg_ok "PASSWORDLESS SUDO CONFIRMED"; return 0; fi
        if "$SUDO_CMD" -v; then msg_ok "SUDO ACCESS CONFIRMED"; return 0; fi
        msg_error "Sudo authentication failed. Script cancelled."
    fi
}

function init_logging() {
    exec 3>&1
    exec 4>&2
    if [ -n "$SUDO_CMD" ]; then
        RUNTIME_LOG_FILE="$(mktemp /tmp/crea-post-core-log.XXXXXX)"
        TEMP_FILES+=("$RUNTIME_LOG_FILE")
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        RUNTIME_LOG_FILE="$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
    LOGGING_ENABLED="yes"
}

function validate_dependencies() {
    local required_commands=(awk cat chmod cp curl date docker grep id mkdir mktemp openssl python3 rm sed tee tr)
    local cmd=""
    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done
    if [ -n "$SUDO_CMD" ]; then command -v sudo >/dev/null 2>&1 || msg_error "sudo is required when not running as root."; fi
}

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
        return 0
    fi
    msg_error "Docker daemon is not reachable. Run core Docker setup first."
}

function docker_cmd() {
    if [ "$DOCKER_NEEDS_SUDO" == "yes" ]; then "$SUDO_CMD" docker "$@"; else docker "$@"; fi
}

function run_docker_cmd() {
    local description="$1"
    shift
    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")
    if ! docker_cmd "$@" >/dev/null 2>"$err_file"; then
        echo ""
        echo -e "${RD}Docker command failed during:${CL} ${description}"
        echo -e "${YW}Docker command arguments hidden for secret safety.${CL}"
        echo ""
        echo -e "${RD}Real error:${CL}"
        cat "$err_file"
        rm -f "$err_file"
        exit 1
    fi
    rm -f "$err_file"
}

# =========================================================
#  PROJECT CONFIG / ENV HELPERS
# =========================================================

function load_env_file() {
    section "PROJECT CONFIG"

    DOCKER_USER="$(timed_text_input "Enter Docker Linux user" "$DOCKER_USER")"
    DOCKER_DIR="$(timed_text_input "Enter Docker directory" "$DOCKER_DIR")"
    COMPOSE_DIR="$(timed_text_input "Enter compose directory" "$COMPOSE_DIR")"
    ENV_FILE="$(timed_text_input "Enter Docker .env path" "$ENV_FILE")"
    GITHUB_RAW_BASE="$(timed_text_input "Enter GitHub raw compose base" "$GITHUB_RAW_BASE")"

    [ -f "$ENV_FILE" ] || msg_error ".env file not found: ${ENV_FILE}. Run Script 6 first."

    # shellcheck disable=SC1090
    set -a
    . "$ENV_FILE"
    set +a

    DOMAIN="${DOMAIN:-}"
    [ -n "$DOMAIN" ] || msg_error "DOMAIN is missing from ${ENV_FILE}."

    DOCKER_DIR="${DOCKER_DIR:-/home/${DOCKER_USER}/docker}"
    COMPOSE_DIR="${COMPOSE_DIR:-${DOCKER_DIR}/compose}"
    ENV_FILE="${ENV_FILE:-${DOCKER_DIR}/.env}"
    N8N_STACK_URL="${N8N_STACK_URL_OVERRIDE:-${GITHUB_RAW_BASE}/${N8N_STACK_FILE}}"
    N8N_FLAT_COMPOSE_FILE="${COMPOSE_DIR}/${N8N_STACK_FILE}"
    N8N_BUNDLED_COMPOSE_FILE="${SCRIPT_DIR}/docker/${N8N_STACK_FILE}"
    N8N_APPDATA_DIR="${DOCKER_DIR}/appdata/n8n"

    export DOCKER_DIR COMPOSE_DIR ENV_FILE DOMAIN

    detail_line "Docker user" "$DOCKER_USER"
    detail_line "Docker dir" "$DOCKER_DIR"
    detail_line "Compose dir" "$COMPOSE_DIR"
    detail_line "Domain" "$DOMAIN"
    detail_line "GitHub raw base" "$GITHUB_RAW_BASE"
}

function env_get() {
    local key="$1"
    awk -F= -v k="$key" '
        $0 ~ "^[[:space:]]*#" {next}
        $1 == k {
            v=$0; sub("^[^=]*=", "", v); gsub(/^\"|\"$/, "", v); print v; exit
        }
    ' "$ENV_FILE" 2>/dev/null || true
}

function env_key_exists() {
    local key="$1"
    grep -Eq "^${key}=" "$ENV_FILE"
}

function backup_env_once() {
    local backup="${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"

    if [ "$ENV_BACKED_UP_THIS_RUN" == "yes" ]; then
        return 0
    fi

    run_cmd "backing up .env before Script 8 edits" cp -a "$ENV_FILE" "$backup"
    run_cmd "setting env backup ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$backup"
    ENV_BACKED_UP_THIS_RUN="yes"
    N8N_ENV_BACKUP_CREATED="yes"
    N8N_ENV_BACKUP_PATH="$backup"
    msg_ok ".ENV BACKUP CREATED"
    detail_line "Backup" "$backup"
}

function env_set_or_update() {
    local key="$1"
    local value="$2"
    local tmp=""
    backup_env_once
    N8N_ENV_MAY_EDIT="yes"
    tmp="$(mktemp)"
    TEMP_FILES+=("$tmp")

    if env_key_exists "$key"; then
        awk -v k="$key" -v v="$value" 'BEGIN{done=0} $0 ~ "^[[:space:]]*#" {print; next} $1 ~ "^" k "=" {print k "=" v; done=1; next} {print} END{if(done==0) print k "=" v}' "$ENV_FILE" > "$tmp"
    else
        cat "$ENV_FILE" > "$tmp"
        {
            echo ""
            echo "# n8n Automation - managed by Script 8"
            echo "${key}=${value}"
        } >> "$tmp"
    fi

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" install -m 0600 -o "$DOCKER_USER" -g "$DOCKER_USER" "$tmp" "$ENV_FILE"
    else
        install -m 0600 -o "$DOCKER_USER" -g "$DOCKER_USER" "$tmp" "$ENV_FILE"
    fi
}

function record_generated_secret() {
    local key="$1"
    local value="$2"
    local mode="$3"
    GENERATED_SECRET_LINES+=("${key}|${value}|${mode}")
    N8N_SECRET_STATUS_LINES+=("${key}:${mode}")
}

function record_secret_reused() {
    local key="$1"
    N8N_SECRET_STATUS_LINES+=("${key}:existing-reused")
}

function generate_secret() {
    local length="${1:-48}"
    python3 - "$length" <<'PY_SECRET'
import secrets, string, sys
length = int(sys.argv[1])
alphabet = string.ascii_letters + string.digits + "_-"
print(''.join(secrets.choice(alphabet) for _ in range(length)))
PY_SECRET
}

function ensure_env_value() {
    local key="$1"
    local default_value="$2"
    local current=""
    current="$(env_get "$key")"
    if [ -n "$current" ]; then
        return 0
    fi
    env_set_or_update "$key" "$default_value"
}

function ensure_secret_env_value() {
    local key="$1"
    local generated_length="$2"
    local critical_message="$3"
    local current=""
    local paste_yn=""
    local value=""

    current="$(env_get "$key")"
    if [ -n "$current" ]; then
        record_secret_reused "$key"
        return 0
    fi

    echo -e "${YW}${key} is missing from ${ENV_FILE}.${CL}"
    [ -n "$critical_message" ] && echo -e "${YW}${critical_message}${CL}"
    paste_yn="$(timed_yes_no "Paste a previously saved value for ${key}?" "n")"

    if [[ "$paste_yn" =~ ^[Yy] ]]; then
        disable_logging
        value="$(sensitive_line_input "Paste ${key}")"
        enable_logging
        value="$(printf '%s' "$value" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -n "$value" ] || msg_error "No value pasted for ${key}."
        env_set_or_update "$key" "$value"
        record_generated_secret "$key" "$value" "pasted"
        return 0
    fi

    value="$(generate_secret "$generated_length")"
    env_set_or_update "$key" "$value"
    record_generated_secret "$key" "$value" "generated"
}

# =========================================================
#  CORE CHECKS
# =========================================================

function detect_admin_ui() {
    section "ADMIN UI DETECTION"
    msg_info "Detecting selected admin UI"
    if docker_cmd ps -a --format '{{.Names}}' | grep -qx 'dockge'; then
        ADMIN_UI="dockge"
    elif docker_cmd ps -a --format '{{.Names}}' | grep -qx 'komodo-core'; then
        ADMIN_UI="komodo"
    elif docker_cmd ps -a --format '{{.Names}}' | grep -qx 'dockhand'; then
        ADMIN_UI="dockhand"
    elif docker_cmd ps -a --format '{{.Names}}' | grep -qx 'portainer'; then
        ADMIN_UI="portainer"
    else
        ADMIN_UI="unknown"
    fi
    msg_ok "ADMIN UI DETECTION COMPLETE"
    detail_line "Admin UI" "$ADMIN_UI"
}

function verify_core_services_read_only() {
    section "CORE SERVICE READ-ONLY CHECK"
    local required_containers=(postgres redis traefik authentik-server)
    local required_networks=(database t2_proxy)
    local item=""

    for item in "${required_containers[@]}"; do
        msg_info "Checking ${item}"
        if docker_cmd ps --format '{{.Names}}' | grep -qx "$item"; then
            msg_ok "${item} RUNNING"
        else
            msg_error "${item} is not running. Script 8 requires Scripts 6/6.5/7 to be complete first."
        fi
    done

    for item in "${required_networks[@]}"; do
        msg_info "Checking Docker network ${item}"
        if docker_cmd network inspect "$item" >/dev/null 2>&1; then
            msg_ok "NETWORK ${item} EXISTS"
        else
            msg_error "Docker network ${item} is missing. Run core deployment first."
        fi
    done
}

# =========================================================
#  COMPOSE PATH / DOCKGE LAYOUT HELPERS
# =========================================================

function n8n_dockge_compose_file() {
    printf '%s' "${COMPOSE_DIR}/n8n/compose.yaml"
}

function resolve_n8n_compose_file() {
    local dockge_path=""
    dockge_path="$(n8n_dockge_compose_file)"
    if [ "$ADMIN_UI" == "dockge" ] && [ -f "$dockge_path" ]; then
        printf '%s' "$dockge_path"
        return 0
    fi
    if [ -f "$N8N_FLAT_COMPOSE_FILE" ]; then
        printf '%s' "$N8N_FLAT_COMPOSE_FILE"
        return 0
    fi
    if [ "$ADMIN_UI" == "dockge" ]; then
        printf '%s' "$dockge_path"
    else
        printf '%s' "$N8N_FLAT_COMPOSE_FILE"
    fi
}

function sync_n8n_compose_for_dockge() {
    local target_dir="${COMPOSE_DIR}/n8n"
    local target_file="${target_dir}/compose.yaml"

    if [ "$ADMIN_UI" != "dockge" ]; then
        N8N_COMPOSE_FILE="$N8N_FLAT_COMPOSE_FILE"
        return 0
    fi

    run_cmd "creating Dockge n8n compose folder" mkdir -p "$target_dir"
    run_cmd "syncing n8n compose into Dockge layout" cp "$N8N_FLAT_COMPOSE_FILE" "$target_file"
    run_cmd "setting Dockge n8n compose ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$target_file"
    run_cmd "setting Dockge n8n compose permissions" chmod 640 "$target_file"
    N8N_COMPOSE_FILE="$target_file"
    msg_ok "DOCKGE COMPOSE READY FOR N8N AUTOMATION"
    detail_line "Compose" "$target_file"
}

function download_n8n_compose_if_needed() {
    local mode="$1"
    determine_n8n_compose_source "$mode"

    case "$mode" in
        update)
            msg_info "Downloading updated ${N8N_SERVICE_NAME} compose"
            run_cmd "creating compose directory" mkdir -p "$COMPOSE_DIR"
            if [ -f "$N8N_FLAT_COMPOSE_FILE" ]; then
                run_cmd "backing up existing n8n compose" cp -a "$N8N_FLAT_COMPOSE_FILE" "${N8N_FLAT_COMPOSE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
            fi
            if ! curl --globoff -fsSL "$N8N_STACK_URL" -o "$N8N_FLAT_COMPOSE_FILE"; then
                msg_error "Could not download ${N8N_STACK_FILE} from ${N8N_STACK_URL}. Upload it to GitHub or set N8N_STACK_URL."
            fi
            run_cmd "setting n8n compose ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$N8N_FLAT_COMPOSE_FILE"
            run_cmd "setting n8n compose permissions" chmod 640 "$N8N_FLAT_COMPOSE_FILE"
            N8N_COMPOSE_SOURCE="remote-downloaded"
            sync_n8n_compose_for_dockge
            msg_ok "N8N AUTOMATION COMPOSE DOWNLOADED"
            ;;
        deploy|repair|recreate)
            case "$N8N_COMPOSE_SOURCE" in
                existing-runtime)
                    N8N_COMPOSE_FILE="${N8N_COMPOSE_FILE:-$(resolve_n8n_compose_file)}"
                    msg_ok "N8N AUTOMATION COMPOSE ALREADY PRESENT"
                    detail_line "Compose source" "$N8N_COMPOSE_SOURCE"
                    detail_line "Compose" "$N8N_COMPOSE_FILE"
                    ;;
                bundled-local)
                    msg_info "Installing bundled ${N8N_SERVICE_NAME} compose"
                    run_cmd "creating compose directory" mkdir -p "$COMPOSE_DIR"
                    run_cmd "copying bundled n8n compose" cp "$N8N_BUNDLED_COMPOSE_FILE" "$N8N_FLAT_COMPOSE_FILE"
                    run_cmd "setting n8n compose ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$N8N_FLAT_COMPOSE_FILE"
                    run_cmd "setting n8n compose permissions" chmod 640 "$N8N_FLAT_COMPOSE_FILE"
                    sync_n8n_compose_for_dockge
                    msg_ok "BUNDLED N8N AUTOMATION COMPOSE INSTALLED"
                    ;;
                remote-missing-local)
                    msg_info "n8n compose missing locally; downloading"
                    run_cmd "creating compose directory" mkdir -p "$COMPOSE_DIR"
                    if ! curl --globoff -fsSL "$N8N_STACK_URL" -o "$N8N_FLAT_COMPOSE_FILE"; then
                        msg_error "Could not download ${N8N_STACK_FILE} from ${N8N_STACK_URL}."
                    fi
                    run_cmd "setting n8n compose ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$N8N_FLAT_COMPOSE_FILE"
                    run_cmd "setting n8n compose permissions" chmod 640 "$N8N_FLAT_COMPOSE_FILE"
                    N8N_COMPOSE_SOURCE="remote-downloaded"
                    sync_n8n_compose_for_dockge
                    msg_ok "N8N AUTOMATION COMPOSE DOWNLOADED"
                    ;;
            esac
            ;;
        *)
            N8N_COMPOSE_FILE="$(resolve_n8n_compose_file)"
            ;;
    esac
}

# =========================================================
#  N8N MODULE: DETECT / PROMPT / PREPARE / DEPLOY / VERIFY
# =========================================================

function is_valid_pg_identifier() {
    local ident="$1"
    # Conservative PostgreSQL identifier policy for .env-managed database/user names.
    # Keeps SQL idempotent and prevents unsafe interpolation from edited/restored .env files.
    [[ "$ident" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]
}

function require_valid_pg_identifier() {
    local key="$1"
    local ident="$2"
    if ! is_valid_pg_identifier "$ident"; then
        msg_error "${key} must be a safe PostgreSQL identifier: letters, numbers, underscores, max 63 chars, starting with letter/underscore."
    fi
}

function n8n_secret_status_for() {
    local key="$1"
    local line=""
    for line in "${N8N_SECRET_STATUS_LINES[@]:-}"; do
        case "$line" in
            "${key}:"*) printf '%s' "${line#*:}"; return 0 ;;
        esac
    done
    if [ -n "$(env_get "$key")" ]; then
        printf '%s' "existing-reused"
    else
        printf '%s' "missing"
    fi
}

function n8n_container_health_state() {
    local name="$1"
    local health=""
    health="$(docker_cmd inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$name" 2>/dev/null || true)"
    printf '%s' "${health:-unknown}"
}

function n8n_redis_ping_readonly() {
    local redis_db="${N8N_REDIS_DB:-$(env_get N8N_REDIS_DB)}"
    redis_db="${redis_db:-2}"
    [ -n "${REDIS_PASSWORD:-}" ] || return 1
    docker_cmd exec -e REDISCLI_AUTH="$REDIS_PASSWORD" redis redis-cli -n "$redis_db" ping 2>/dev/null | grep -q PONG
}

function n8n_db_login_readonly() {
    local db="${N8N_POSTGRES_DB:-$(env_get N8N_POSTGRES_DB)}"
    local user="${N8N_POSTGRES_USER:-$(env_get N8N_POSTGRES_USER)}"
    local password="${N8N_POSTGRES_PASSWORD:-$(env_get N8N_POSTGRES_PASSWORD)}"
    db="${db:-n8n}"
    user="${user:-n8n}"
    [ -n "$password" ] || return 1
    is_valid_pg_identifier "$db" || return 1
    is_valid_pg_identifier "$user" || return 1
    docker_cmd exec -i -e PGPASSWORD="$password" postgres psql -U "$user" -d "$db" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null 2>&1
}

function determine_n8n_compose_source() {
    local mode="$1"
    local existing=""
    local dockge_path=""
    dockge_path="$(n8n_dockge_compose_file)"

    if [ "$ADMIN_UI" == "dockge" ] && [ -f "$dockge_path" ]; then
        existing="$dockge_path"
    elif [ -f "$N8N_FLAT_COMPOSE_FILE" ]; then
        existing="$N8N_FLAT_COMPOSE_FILE"
    else
        existing=""
    fi

    case "$mode" in
        update)
            N8N_COMPOSE_SOURCE="remote-update"
            N8N_COMPOSE_FILE="${existing:-$(resolve_n8n_compose_file)}"
            ;;
        deploy|repair|recreate|detect)
            if [ -n "$existing" ]; then
                N8N_COMPOSE_SOURCE="existing-runtime"
                N8N_COMPOSE_FILE="$existing"
            elif [ -f "$N8N_BUNDLED_COMPOSE_FILE" ]; then
                N8N_COMPOSE_SOURCE="bundled-local"
                N8N_COMPOSE_FILE="$N8N_FLAT_COMPOSE_FILE"
            else
                N8N_COMPOSE_SOURCE="remote-missing-local"
                N8N_COMPOSE_FILE="$N8N_FLAT_COMPOSE_FILE"
            fi
            ;;
        *)
            N8N_COMPOSE_SOURCE="not-needed"
            N8N_COMPOSE_FILE="$(resolve_n8n_compose_file)"
            ;;
    esac
}

function show_n8n_ready_to_apply() {
    section "READY TO APPLY - N8N AUTOMATION"

    local db="${N8N_POSTGRES_DB:-$(env_get N8N_POSTGRES_DB)}"
    local user="${N8N_POSTGRES_USER:-$(env_get N8N_POSTGRES_USER)}"
    local redis_db="${N8N_REDIS_DB:-$(env_get N8N_REDIS_DB)}"
    db="${db:-n8n}"
    user="${user:-n8n}"
    redis_db="${redis_db:-2}"
    require_valid_pg_identifier "N8N_POSTGRES_DB" "$db"
    require_valid_pg_identifier "N8N_POSTGRES_USER" "$user"
    N8N_DB_IDENTIFIER_STATUS="valid-planned"

    detail_line "Service" "$N8N_SERVICE_NAME"
    detail_line "Selected action" "$N8N_ACTION"
    detail_line ".env path" "$ENV_FILE"
    detail_line ".env may be edited" "yes, only missing n8n keys/secrets"
    detail_line ".env backup" "once before first edit in this run"
    detail_line "n8n appdata" "$N8N_APPDATA_DIR"
    detail_line "Permission scope" "${N8N_APPDATA_DIR} only"
    detail_line "PostgreSQL database" "$db"
    detail_line "PostgreSQL user" "$user"
    detail_line "Redis DB" "$redis_db"
    detail_line "Compose source" "$N8N_COMPOSE_SOURCE"
    detail_line "Compose target" "${N8N_COMPOSE_FILE:-$(resolve_n8n_compose_file)}"
    if [ "$ADMIN_UI" == "dockge" ]; then
        detail_line "Dockge compose target" "$(n8n_dockge_compose_file)"
    fi
    detail_line "Affected containers" "n8n, n8n-worker"
    detail_line "Route" "https://n8n.${DOMAIN}/"
    detail_line "UI protection" "Authentik via chain-authentik@file"
    detail_line "Public production webhook" "https://n8n.${DOMAIN}/webhook/..."
    detail_line "webhook-test" "not public by default; remains behind Authentik UI route"

    echo ""
    echo -e "${YW}No Scripts 1-7 core infrastructure will be changed.${CL}"
    echo -e "${YW}No n8n data reset, database drop, appdata delete, or encryption-key regeneration will be performed.${CL}"
    echo ""

    local apply_yn=""
    apply_yn="$(timed_yes_no "Apply this ${N8N_SERVICE_NAME} plan?" "y")"
    if [[ "$apply_yn" =~ ^[Nn] ]]; then
        N8N_ACTION="skip"
        msg_skip "N8N AUTOMATION PLAN CANCELLED; EXISTING SETUP LEFT UNTOUCHED"
        return 1
    fi
    return 0
}

function prepare_n8n_env_values() {
    section "N8N AUTOMATION ENVIRONMENT"

    ensure_env_value "N8N_IMAGE" "docker.n8n.io/n8nio/n8n:latest"
    ensure_env_value "N8N_HOST" "n8n.${DOMAIN}"
    ensure_env_value "N8N_URL" "https://n8n.${DOMAIN}"
    ensure_env_value "N8N_WEBHOOK_URL" "https://n8n.${DOMAIN}/"
    ensure_env_value "N8N_POSTGRES_DB" "n8n"
    ensure_env_value "N8N_POSTGRES_USER" "n8n"
    ensure_env_value "N8N_EXECUTIONS_MODE" "queue"
    ensure_env_value "N8N_WORKER_CONCURRENCY" "5"
    ensure_env_value "N8N_REDIS_DB" "2"
    ensure_env_value "N8N_LOG_LEVEL" "info"

    ensure_secret_env_value "N8N_POSTGRES_PASSWORD" "48" "This password is for the n8n PostgreSQL role only. Existing values are always preserved."
    ensure_secret_env_value "N8N_ENCRYPTION_KEY" "64" "CRITICAL: Never regenerate this after n8n has stored credentials unless you intentionally reset n8n data."

    # Reload .env after updates.
    # shellcheck disable=SC1090
    set -a
    . "$ENV_FILE"
    set +a

    N8N_ENV_READY="yes"
    msg_ok "N8N ENVIRONMENT VALUES READY"
}

function prepare_n8n_appdata() {
    section "N8N AUTOMATION DIRECTORIES"

    local owner_uid="${N8N_APPDATA_UID:-1000}"
    local owner_gid="${N8N_APPDATA_GID:-1000}"
    N8N_APPDATA_OWNER="${owner_uid}:${owner_gid}"

    # Service-scoped permissions only. Never blanket chown/chmod ${DOCKER_DIR}/appdata.
    # The official n8n image stores data under /home/node/.n8n and is expected to run as node (UID/GID 1000).
    # Optional N8N_APPDATA_UID/N8N_APPDATA_GID may override this without changing the compose user model.
    run_cmd "creating n8n appdata directory" mkdir -p "$N8N_APPDATA_DIR" "${N8N_APPDATA_DIR}/files" "${N8N_APPDATA_DIR}/backups"
    run_cmd "setting n8n appdata ownership" chown -R "$N8N_APPDATA_OWNER" "$N8N_APPDATA_DIR"
    run_cmd "setting n8n appdata permissions" chmod 750 "$N8N_APPDATA_DIR"
    run_cmd "setting n8n child directory permissions" chmod 750 "${N8N_APPDATA_DIR}/files" "${N8N_APPDATA_DIR}/backups"

    N8N_APPDATA_READY="yes"
    msg_ok "N8N AUTOMATION DIRECTORIES READY"
    detail_line "n8n appdata" "$N8N_APPDATA_DIR"
    detail_line "n8n appdata owner" "$N8N_APPDATA_OWNER"
}

function postgres_exec_sql() {
    local sql="$1"
    docker_cmd exec -i -e PGPASSWORD="${POSTGRES_PASSWORD}" postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<< "$sql"
}

function ensure_n8n_database() {
    section "N8N AUTOMATION DATABASE"

    local db="${N8N_POSTGRES_DB:-n8n}"
    local user="${N8N_POSTGRES_USER:-n8n}"
    local password="${N8N_POSTGRES_PASSWORD:-}"
    local escaped_password=""
    local sql=""

    [ -n "$password" ] || msg_error "N8N_POSTGRES_PASSWORD is empty after environment preparation."
    [ -n "${POSTGRES_PASSWORD:-}" ] || msg_error "POSTGRES_PASSWORD is missing from ${ENV_FILE}."
    require_valid_pg_identifier "N8N_POSTGRES_DB" "$db"
    require_valid_pg_identifier "N8N_POSTGRES_USER" "$user"
    N8N_DB_IDENTIFIER_STATUS="valid"

    escaped_password="${password//\'/\'\'}"

    msg_info "Creating/updating n8n PostgreSQL role and database"
    sql="DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${user}') THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${user}', '${escaped_password}');
    ELSE
        EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', '${user}', '${escaped_password}');
    END IF;
END
\$\$;
SELECT format('CREATE DATABASE %I OWNER %I', '${db}', '${user}') WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\\gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', '${db}', '${user}')\\gexec"

    if postgres_exec_sql "$sql" >/dev/null 2>&1; then
        msg_ok "N8N POSTGRESQL DATABASE READY"
    else
        msg_error "Failed to create/update n8n PostgreSQL database/user."
    fi

    msg_info "Verifying n8n PostgreSQL login"
    if docker_cmd exec -i -e PGPASSWORD="$password" postgres psql -U "$user" -d "$db" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null 2>&1; then
        N8N_DB_READY="yes"
        msg_ok "N8N POSTGRESQL LOGIN VERIFIED"
    else
        msg_error "n8n PostgreSQL login verification failed."
    fi
}

function verify_redis_for_n8n() {
    section "N8N AUTOMATION REDIS CHECK"

    [ -n "${REDIS_PASSWORD:-}" ] || msg_error "REDIS_PASSWORD is missing from ${ENV_FILE}."

    msg_info "Checking Redis queue backend"
    if docker_cmd exec -e REDISCLI_AUTH="$REDIS_PASSWORD" redis redis-cli -n "${N8N_REDIS_DB:-2}" ping 2>/dev/null | grep -q PONG; then
        N8N_REDIS_READY="yes"
        msg_ok "REDIS QUEUE BACKEND VERIFIED"
    else
        msg_error "Redis queue backend check failed."
    fi
}

function validate_n8n_compose() {
    section "N8N AUTOMATION COMPOSE VALIDATION"
    N8N_COMPOSE_FILE="$(resolve_n8n_compose_file)"
    [ -f "$N8N_COMPOSE_FILE" ] || msg_error "n8n compose file not found: ${N8N_COMPOSE_FILE}"

    export DOCKER_DIR COMPOSE_DIR ENV_FILE DOMAIN
    msg_info "Validating n8n compose"
    run_docker_cmd "validating n8n compose" compose --env-file "$ENV_FILE" -p "$N8N_PROJECT" -f "$N8N_COMPOSE_FILE" config -q
    N8N_COMPOSE_READY="yes"
    msg_ok "N8N AUTOMATION COMPOSE VALID"
}

function deploy_n8n_stack() {
    section "N8N AUTOMATION DEPLOYMENT"

    N8N_COMPOSE_FILE="$(resolve_n8n_compose_file)"
    [ -f "$N8N_COMPOSE_FILE" ] || msg_error "n8n compose file not found: ${N8N_COMPOSE_FILE}"

    msg_info "Deploying n8n Automation"
    run_docker_cmd "deploying n8n Automation" compose --env-file "$ENV_FILE" -p "$N8N_PROJECT" -f "$N8N_COMPOSE_FILE" up -d
    N8N_DEPLOYED="yes"
    N8N_TOUCHED="yes"
    msg_ok "N8N AUTOMATION DEPLOYED"
}

function recreate_n8n_containers() {
    section "N8N AUTOMATION RECREATE"

    N8N_COMPOSE_FILE="$(resolve_n8n_compose_file)"
    [ -f "$N8N_COMPOSE_FILE" ] || msg_error "n8n compose file not found: ${N8N_COMPOSE_FILE}"

    echo -e "${YW}This recreates n8n containers only. It does not delete n8n database, appdata, or encryption key.${CL}"
    echo -e "${YW}Destructive data reset is intentionally not part of this safe Script 8 flow.${CL}"
    echo ""
    local confirm=""
    confirm="$(timed_yes_no "Recreate n8n containers now?" "n")"
    if [[ "$confirm" =~ ^[Nn] ]]; then
        N8N_ACTION="recreate-skipped"
        msg_skip "N8N CONTAINER RECREATE SKIPPED"
        return 0
    fi

    msg_info "Recreating n8n containers"
    run_docker_cmd "recreating n8n containers" compose --env-file "$ENV_FILE" -p "$N8N_PROJECT" -f "$N8N_COMPOSE_FILE" up -d --force-recreate
    N8N_DEPLOYED="yes"
    N8N_TOUCHED="yes"
    msg_ok "N8N CONTAINERS RECREATED"
}

function http_code_for_url() {
    local url="$1"
    curl -ksS -o /dev/null -w '%{http_code}' "$url" || true
}

function verify_n8n_routes() {
    local ui_code=""
    local webhook_code=""
    local ui_url="https://${N8N_HOST:-n8n.${DOMAIN}}/"
    local webhook_url="https://${N8N_HOST:-n8n.${DOMAIN}}/webhook/crea-script8-health-check"

    msg_info "Checking protected n8n UI route"
    ui_code="$(http_code_for_url "$ui_url")"
    case "$ui_code" in
        200|301|302|303|307|308|401|403)
            N8N_UI_ROUTE_OK="yes"
            msg_ok "N8N PROTECTED UI ROUTE RESPONDED WITH HTTP ${ui_code}"
            ;;
        *)
            N8N_UI_ROUTE_OK="no"
            msg_warn "n8n UI route returned HTTP ${ui_code:-none}. Review DNS/Traefik/AuthentiK."
            ;;
    esac

    msg_info "Checking public n8n webhook route"
    webhook_code="$(http_code_for_url "$webhook_url")"
    case "$webhook_code" in
        200|400|404|405)
            N8N_WEBHOOK_ROUTE_OK="yes"
            msg_ok "N8N WEBHOOK ROUTE REACHED N8N WITH HTTP ${webhook_code}"
            ;;
        301|302|303|307|308)
            N8N_WEBHOOK_ROUTE_OK="maybe-auth-protected"
            msg_warn "n8n webhook route redirected with HTTP ${webhook_code}. Ensure external webhooks are not blocked by Authentik."
            ;;
        *)
            N8N_WEBHOOK_ROUTE_OK="no"
            msg_warn "n8n webhook route returned HTTP ${webhook_code:-none}."
            ;;
    esac

    detail_line "n8n UI" "${ui_url} -> ${ui_code:-none}"
    detail_line "n8n webhook" "${webhook_url} -> ${webhook_code:-none}"
}

function verify_n8n_stack() {
    section "N8N AUTOMATION VERIFICATION"

    msg_info "Checking n8n container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'n8n'; then
        N8N_MAIN_RUNNING="yes"
        msg_ok "N8N CONTAINER RUNNING"
    else
        N8N_MAIN_RUNNING="no"
        msg_warn "n8n container is not running"
    fi

    msg_info "Checking n8n worker container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'n8n-worker'; then
        N8N_WORKER_RUNNING="yes"
        msg_ok "N8N WORKER RUNNING"
    else
        N8N_WORKER_RUNNING="no"
        msg_warn "n8n-worker container is not running"
    fi

    verify_redis_for_n8n
    # Database login was already checked during deploy/repair. Re-check read-only here.
    if n8n_db_login_readonly; then
        N8N_DB_READY="yes"
        msg_ok "N8N DATABASE LOGIN STILL WORKS"
    else
        N8N_DB_READY="no"
        msg_warn "n8n database login check failed"
    fi

    verify_n8n_routes

    if [ "$N8N_MAIN_RUNNING" == "yes" ] && [ "$N8N_WORKER_RUNNING" == "yes" ] && [ "$N8N_DB_READY" == "yes" ] && [ "$N8N_REDIS_READY" == "yes" ]; then
        N8N_VERIFIED="yes"
        msg_ok "N8N AUTOMATION CORE VERIFIED"
    else
        N8N_VERIFIED="no"
        msg_warn "N8N AUTOMATION NEEDS REVIEW"
    fi
}

function detect_n8n_state() {
    section "N8N AUTOMATION DETECTION"

    local compose_exists="no"
    local env_ok="no"
    local appdata_exists="no"
    local main_exists="no"
    local main_running="no"
    local worker_running="no"
    local db_readonly="no"
    local redis_readonly="no"
    local compose_path=""

    determine_n8n_compose_source "detect"
    compose_path="$(resolve_n8n_compose_file)"
    [ -f "$compose_path" ] && compose_exists="yes"
    [ -d "$N8N_APPDATA_DIR" ] && appdata_exists="yes"
    if [ -n "$(env_get N8N_POSTGRES_PASSWORD)" ] && [ -n "$(env_get N8N_ENCRYPTION_KEY)" ]; then env_ok="yes"; fi
    docker_cmd ps -a --format '{{.Names}}' | grep -qx 'n8n' && main_exists="yes"
    docker_cmd ps --format '{{.Names}}' | grep -qx 'n8n' && main_running="yes"
    docker_cmd ps --format '{{.Names}}' | grep -qx 'n8n-worker' && worker_running="yes"

    if [ "$main_running" == "yes" ]; then
        N8N_MAIN_HEALTH="$(n8n_container_health_state n8n)"
    else
        N8N_MAIN_HEALTH="not-running"
    fi
    if [ "$worker_running" == "yes" ]; then
        N8N_WORKER_HEALTH="$(n8n_container_health_state n8n-worker)"
    else
        N8N_WORKER_HEALTH="not-running"
    fi

    if [ "$env_ok" == "yes" ] && n8n_db_login_readonly; then db_readonly="yes"; fi
    if [ "$env_ok" == "yes" ] && n8n_redis_ping_readonly; then redis_readonly="yes"; fi

    detail_line "Compose file" "${compose_exists} (${compose_path})"
    detail_line "Compose source" "$N8N_COMPOSE_SOURCE"
    detail_line "Appdata" "$appdata_exists"
    detail_line "Secrets present" "$env_ok"
    detail_line "n8n container exists" "$main_exists"
    detail_line "n8n running" "$main_running"
    detail_line "n8n health" "$N8N_MAIN_HEALTH"
    detail_line "n8n worker running" "$worker_running"
    detail_line "n8n worker health" "$N8N_WORKER_HEALTH"
    detail_line "DB login read-only check" "$db_readonly"
    detail_line "Redis read-only check" "$redis_readonly"
    detail_line "Route check" "not used for healthy detection; checked during verification only"

    if [ "$compose_exists" == "yes" ]         && [ "$appdata_exists" == "yes" ]         && [ "$env_ok" == "yes" ]         && [ "$main_running" == "yes" ]         && [ "$worker_running" == "yes" ]         && [[ "$N8N_MAIN_HEALTH" != "unhealthy" ]]         && [[ "$N8N_WORKER_HEALTH" != "unhealthy" ]]         && [ "$db_readonly" == "yes" ]         && [ "$redis_readonly" == "yes" ]; then
        N8N_STATE="installed-appears-healthy"
        N8N_DB_READY="yes"
        N8N_REDIS_READY="yes"
    elif [ "$main_exists" == "yes" ] || [ "$compose_exists" == "yes" ] || [ "$appdata_exists" == "yes" ]; then
        N8N_STATE="installed-needs-review"
    else
        N8N_STATE="missing"
    fi

    msg_ok "N8N DETECTION COMPLETE"
    detail_line "Detected state" "$N8N_STATE"
}

function prompt_n8n_action() {
    section "N8N AUTOMATION PLAN"

    local skip_yn=""
    local choice=""

    case "$N8N_STATE" in
        missing)
            echo -e "${YW}${N8N_SERVICE_NAME} is not deployed yet.${CL}"
            skip_yn="$(timed_yes_no "Deploy ${N8N_SERVICE_NAME} now?" "y")"
            if [[ "$skip_yn" =~ ^[Nn] ]]; then N8N_ACTION="skip"; else N8N_ACTION="deploy"; fi
            ;;
        installed-appears-healthy)
            echo -e "${GN}${N8N_SERVICE_NAME} appears deployed and running.${CL}"
            echo -e "${YW}Default is to skip and leave the working setup untouched.${CL}"
            skip_yn="$(timed_yes_no "Skip ${N8N_SERVICE_NAME} and continue?" "y")"
            if [[ "$skip_yn" =~ ^[Yy] ]]; then
                N8N_ACTION="skip"
            else
                echo ""
                echo -e "${BL}Choose action:${CL}"
                echo -e "${YW}1) Check/repair ${N8N_SERVICE_NAME} and continue${CL}"
                echo -e "${YW}2) Update/redeploy compose for ${N8N_SERVICE_NAME}${CL}"
                echo -e "${YW}3) Recreate ${N8N_SERVICE_NAME} containers only${CL}"
                echo -e "${YW}4) Skip${CL}"
                choice="$(read_menu_choice "Select action" "4")"
                case "$choice" in
                    1) N8N_ACTION="repair" ;;
                    2) N8N_ACTION="update" ;;
                    3) N8N_ACTION="recreate" ;;
                    *) N8N_ACTION="skip" ;;
                esac
            fi
            ;;
        *)
            echo -e "${YW}${N8N_SERVICE_NAME} has existing files/containers but is not fully healthy.${CL}"
            echo ""
            echo -e "${BL}Choose action:${CL}"
            echo -e "${YW}1) Check/repair ${N8N_SERVICE_NAME} and continue${CL}"
            echo -e "${YW}2) Update/redeploy compose for ${N8N_SERVICE_NAME}${CL}"
            echo -e "${YW}3) Recreate ${N8N_SERVICE_NAME} containers only${CL}"
            echo -e "${YW}4) Skip and leave untouched${CL}"
            choice="$(read_menu_choice "Select action" "1")"
            case "$choice" in
                1) N8N_ACTION="repair" ;;
                2) N8N_ACTION="update" ;;
                3) N8N_ACTION="recreate" ;;
                *) N8N_ACTION="skip" ;;
            esac
            ;;
    esac

    detail_line "Selected action" "$N8N_ACTION"
}

function run_n8n_module() {
    detect_n8n_state
    prompt_n8n_action

    if [ "$N8N_ACTION" == "skip" ]; then
        SUMMARY_LINES+=("${N8N_SERVICE_NAME}|skipped|existing setup left untouched")
        msg_skip "${N8N_SERVICE_NAME} SKIPPED; EXISTING SETUP LEFT UNTOUCHED"
        return 0
    fi

    determine_n8n_compose_source "$N8N_ACTION"
    if ! show_n8n_ready_to_apply; then
        SUMMARY_LINES+=("${N8N_SERVICE_NAME}|skipped|plan cancelled before changes")
        return 0
    fi

    prepare_n8n_env_values
    prepare_n8n_appdata
    ensure_n8n_database
    verify_redis_for_n8n

    case "$N8N_ACTION" in
        deploy)
            download_n8n_compose_if_needed deploy
            validate_n8n_compose
            deploy_n8n_stack
            ;;
        repair)
            download_n8n_compose_if_needed repair
            validate_n8n_compose
            deploy_n8n_stack
            ;;
        update)
            download_n8n_compose_if_needed update
            validate_n8n_compose
            deploy_n8n_stack
            ;;
        recreate)
            download_n8n_compose_if_needed repair
            validate_n8n_compose
            recreate_n8n_containers
            ;;
        *)
            msg_skip "Unknown n8n action; skipping"
            return 0
            ;;
    esac

    verify_n8n_stack
    SUMMARY_LINES+=("${N8N_SERVICE_NAME}|${N8N_ACTION}|verified=${N8N_VERIFIED}")
}

# =========================================================
#  REPORTING
# =========================================================

function write_verification_report() {
    section "VERIFICATION REPORT"

    msg_info "Writing post-core verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<EOF_REPORT
--- CREA POST-CORE SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
Admin UI: $ADMIN_UI

n8n Automation:
State: $N8N_STATE
Action: $N8N_ACTION
Touched: $N8N_TOUCHED
Compose source: $N8N_COMPOSE_SOURCE
Env backup created this run: $N8N_ENV_BACKUP_CREATED
Env backup path: ${N8N_ENV_BACKUP_PATH:-none}
N8N_POSTGRES_PASSWORD status: $(n8n_secret_status_for N8N_POSTGRES_PASSWORD)
N8N_ENCRYPTION_KEY status: $(n8n_secret_status_for N8N_ENCRYPTION_KEY)
PostgreSQL identifier status: $N8N_DB_IDENTIFIER_STATUS
Env ready: $N8N_ENV_READY
Appdata ready: $N8N_APPDATA_READY
DB ready: $N8N_DB_READY
Redis ready: $N8N_REDIS_READY
Compose ready: $N8N_COMPOSE_READY
Deployed: $N8N_DEPLOYED
Main running: $N8N_MAIN_RUNNING
Worker running: $N8N_WORKER_RUNNING
UI route OK: $N8N_UI_ROUTE_OK
Webhook route OK: $N8N_WEBHOOK_ROUTE_OK
Verified: $N8N_VERIFIED
Compose file: ${N8N_COMPOSE_FILE:-$(resolve_n8n_compose_file)}
Appdata: $N8N_APPDATA_DIR
Appdata owner: ${N8N_APPDATA_OWNER:-not-set}
Main health: $N8N_MAIN_HEALTH
Worker health: $N8N_WORKER_HEALTH
Route warning: $N8N_ROUTE_WARNING
EOF_REPORT
    else
        cat > "$VERIFY_LOG" <<EOF_REPORT
--- CREA POST-CORE SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
Admin UI: $ADMIN_UI

n8n Automation:
State: $N8N_STATE
Action: $N8N_ACTION
Touched: $N8N_TOUCHED
Compose source: $N8N_COMPOSE_SOURCE
Env backup created this run: $N8N_ENV_BACKUP_CREATED
Env backup path: ${N8N_ENV_BACKUP_PATH:-none}
N8N_POSTGRES_PASSWORD status: $(n8n_secret_status_for N8N_POSTGRES_PASSWORD)
N8N_ENCRYPTION_KEY status: $(n8n_secret_status_for N8N_ENCRYPTION_KEY)
PostgreSQL identifier status: $N8N_DB_IDENTIFIER_STATUS
Env ready: $N8N_ENV_READY
Appdata ready: $N8N_APPDATA_READY
DB ready: $N8N_DB_READY
Redis ready: $N8N_REDIS_READY
Compose ready: $N8N_COMPOSE_READY
Deployed: $N8N_DEPLOYED
Main running: $N8N_MAIN_RUNNING
Worker running: $N8N_WORKER_RUNNING
UI route OK: $N8N_UI_ROUTE_OK
Webhook route OK: $N8N_WEBHOOK_ROUTE_OK
Verified: $N8N_VERIFIED
Compose file: ${N8N_COMPOSE_FILE:-$(resolve_n8n_compose_file)}
Appdata: $N8N_APPDATA_DIR
Appdata owner: ${N8N_APPDATA_OWNER:-not-set}
Main health: $N8N_MAIN_HEALTH
Worker health: $N8N_WORKER_HEALTH
Route warning: $N8N_ROUTE_WARNING
EOF_REPORT
    fi

    msg_ok "POST-CORE VERIFICATION REPORT WRITTEN"
    detail_line "Verify log" "$VERIFY_LOG"
}

function write_completion_marker() {
    section "COMPLETION MARKER"
    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<EOF_MARKER
Crea Post-Core Setup completed on: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
n8n action: $N8N_ACTION
n8n verified: $N8N_VERIFIED
Verify log: $VERIFY_LOG
EOF_MARKER
    else
        cat > "$COMPLETED_MARKER" <<EOF_MARKER
Crea Post-Core Setup completed on: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
n8n action: $N8N_ACTION
n8n verified: $N8N_VERIFIED
Verify log: $VERIFY_LOG
EOF_MARKER
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

function show_secret_summary() {
    section "SAVE THESE NEW OR PASTED SECRETS"

    if [ "${#GENERATED_SECRET_LINES[@]}" -eq 0 ]; then
        echo -e "${GN}No new or pasted secrets were created in this run.${CL}"
        echo -e "${YW}Existing secrets were reused and not displayed.${CL}"
        return 0
    fi

    echo -e "${YW}Store these values in your password manager. Do not commit them to GitHub.${CL}"
    echo ""
    local line=""
    local key=""
    local value=""
    local mode=""
    for line in "${GENERATED_SECRET_LINES[@]}"; do
        IFS='|' read -r key value mode <<< "$line"
        detail_line "${key} (${mode})" "$value"
    done
}

function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    POST-CORE SETUP FINISHED    ━━━━━━━━━━━━━━━━━"

    detail_line "DOMAIN" "$DOMAIN"
    detail_line "ADMIN UI" "$ADMIN_UI"
    detail_line "N8N STATE" "$N8N_STATE"
    detail_line "N8N ACTION" "$N8N_ACTION"
    detail_line "N8N TOUCHED" "$N8N_TOUCHED"
    detail_line "N8N VERIFIED" "$N8N_VERIFIED"
    detail_line "N8N COMPOSE SOURCE" "$N8N_COMPOSE_SOURCE"
    detail_line "ENV BACKUP THIS RUN" "$N8N_ENV_BACKUP_CREATED"
    detail_line "N8N UI ROUTE" "$N8N_UI_ROUTE_OK"
    detail_line "N8N WEBHOOK ROUTE" "$N8N_WEBHOOK_ROUTE_OK"
    detail_line "VERIFY LOG" "$VERIFY_LOG"

    echo ""
    if [ "$N8N_ACTION" == "skip" ]; then
        echo -e "${GN}${N8N_SERVICE_NAME} was skipped and left untouched.${CL}"
    elif [ "$N8N_VERIFIED" == "yes" ]; then
        echo -e "${GN}${N8N_SERVICE_NAME} is deployed and core checks passed.${CL}"
        echo -e "${YW}UI/editor:${CL} https://n8n.${DOMAIN}/"
        echo -e "${YW}Production webhooks:${CL} https://n8n.${DOMAIN}/webhook/..."
    else
        echo -e "${YW}${N8N_SERVICE_NAME} completed with warnings. Review the verification report and container logs.${CL}"
    fi
    echo ""
}

# =========================================================
#  MAIN
# =========================================================

function start_confirmation() {
    section "START"
    echo -e "${YW}This script manages post-core production add-on services for Project Crea.${CL}"
    echo -e "${YW}It does not touch working Scripts 1-7 core infrastructure unless a selected add-on service requires a read-only check.${CL}"
    echo ""
    echo -e "${BL}Current module:${CL} ${N8N_SERVICE_NAME}"
    echo ""
    local start_yn=""
    start_yn="$(timed_yes_no "Start Post-Core Setup?" "y")"
    if [[ "$start_yn" =~ ^[Nn] ]]; then exit 0; fi
}

function main() {
    init_script
    detect_docker_access
    load_env_file
    detect_admin_ui
    verify_core_services_read_only
    start_confirmation

    run_n8n_module

    write_verification_report
    write_completion_marker
    show_secret_summary
    show_final_summary

    exit 0
}

main "$@"
