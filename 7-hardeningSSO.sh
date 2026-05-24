#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Final Hardening + SSO Integration
# =========================================================

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

SCRIPT_SOURCE="7-hardeningSSO.sh"
SCRIPT_VERSION="v1.4.1"
SCRIPT_UPDATED="2026-05-24"
SCRIPT_BUILD="hardening-only-authentik-moved-to-6-5"

# --- 2. GLOBAL VARIABLES ---
T=15

LOG_FILE="/var/log/final-hardening-sso.log"
RUNTIME_LOG_FILE=""
VERIFY_LOG="/var/log/final-hardening-sso-verify.log"
COMPLETED_MARKER="/root/.final-hardening-sso-completed"

DEFAULT_DOCKER_USER="${SUDO_USER:-orik}"
DOCKER_USER="${DOCKER_USER:-$DEFAULT_DOCKER_USER}"
DOCKER_DIR="${DOCKER_DIR:-/home/${DOCKER_USER}/docker}"
COMPOSE_DIR="${COMPOSE_DIR:-${DOCKER_DIR}/compose}"
ENV_FILE="${ENV_FILE:-${DOCKER_DIR}/.env}"

DOMAIN=""
AUTHENTIK_HOST=""
AUTHENTIK_API_BASE=""
AUTHENTIK_API_TOKEN="${AUTHENTIK_API_TOKEN:-}"
AUTHENTIK_TOKEN_SOURCE="none"

ADMIN_UI="auto"
PORTAINER_SELECTED="no"
DOCKGE_SELECTED="no"
KOMODO_SELECTED="no"

SUDO_CMD=""
DOCKER_NEEDS_SUDO="no"
LOGGING_ENABLED="no"

TRAEFIK_CONFIG_OK="no"
AUTHENTIK_CONTAINERS_OK="no"
AUTHENTIK_API_OK="no"
AUTHENTIK_PROVIDER_OK="no"
AUTHENTIK_APPLICATION_OK="no"
AUTHENTIK_OUTPOST_ATTACH_OK="no"
AUTHENTIK_OUTPOST_302_OK="no"
PORTAINER_OIDC_STATUS="not-applicable"
KOMODO_OIDC_STATUS="not-applicable"
PORTAINER_BOOTSTRAP_CLOSED="not-applicable"
UFW_PORTAINER_RULE_REMOVED="not-applicable"
ADMIN_UI_BOOTSTRAP_CLOSED="not-applicable"
UFW_ADMIN_UI_RULE_REMOVED="not-applicable"
AUTHENTIK_BOOTSTRAP_TOKEN_PRESENT="unknown"
NOPASSWD_HARDENED="no"
DOCKER_USER_RULES_REVIEWED="no"
POSTIZ_HEALTH_OK="no"
POSTIZ_BACKEND_PORT_OK="no"
POSTIZ_WEB_ROUTE_OK="no"
POSTIZ_TEMPORAL_GUARD_STATUS="not-found"
POSTIZ_TEMPORAL_GUARD_STOPPED="not-applicable"

TEMP_FILES=()
IMAGE_LOCK_REPORT=""

# =========================================================
#  OUTPUT HELPERS
# =========================================================

# --- 3. HEADER ---
function header_info() {
echo -e "${BL}
███████╗██╗███╗   ██╗ █████╗ ██╗         ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗
██╔════╝██║████╗  ██║██╔══██╗██║         ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║
█████╗  ██║██╔██╗ ██║███████║██║         ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║
██╔══╝  ██║██║╚██╗██║██╔══██║██║         ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║
██║     ██║██║ ╚████║██║  ██║███████╗    ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║
╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝
${CL}"
}

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

# --- 4. CLEANUP ---
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

function run_optional() {
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" "$@" >/dev/null 2>&1 || true
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

function write_root_file() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" tee "$path" >/dev/null
    else
        cat > "$path"
    fi
}

# =========================================================
#  LOGGING CONTROL
# =========================================================

# --- 5. LOGGING CONTROL ---
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

# --- 6. PROMPT SYSTEM ---
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

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

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

function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""

    # Text/path/name/domain/token prompts are deliberately NOT timed.
    # Countdown prompts are reserved only for Y/n decisions.
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

# =========================================================
#  INIT / VALIDATION
# =========================================================

# --- 7. ROOT / SUDO / LOGGING ---
function detect_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    else
        SUDO_CMD="sudo"
    fi
}

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

function init_logging() {
    exec 3>&1
    exec 4>&2

    if [ -n "$SUDO_CMD" ]; then
        RUNTIME_LOG_FILE="$(mktemp /tmp/final-hardening-sso-log.XXXXXX)"
        TEMP_FILES+=("$RUNTIME_LOG_FILE")
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        RUNTIME_LOG_FILE="$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    LOGGING_ENABLED="yes"
}

function validate_dependencies() {
    local required_commands=(
        awk
        cat
        chmod
        curl
        date
        docker
        grep
        id
        mkdir
        mktemp
        rm
        sed
        tee
        tr
    )

    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done

    if [ -n "$SUDO_CMD" ]; then
        command -v sudo >/dev/null 2>&1 || msg_error "sudo is required when not running as root."
    fi
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

# --- 8. DOCKER ACCESS ---
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

    msg_error "Docker daemon is not reachable. Run Script 5 first."
}

function docker_cmd() {
    if [ "$DOCKER_NEEDS_SUDO" == "yes" ]; then
        "$SUDO_CMD" docker "$@"
    else
        docker "$@"
    fi
}

# =========================================================
#  PROJECT CONFIG
# =========================================================

# --- 9. LOAD PROJECT ENV ---
function load_env_file() {
    section "PROJECT CONFIG"

    DOCKER_USER="$(timed_text_input "Enter Docker Linux user" "$DOCKER_USER")"
    DOCKER_DIR="$(timed_text_input "Enter Docker directory" "$DOCKER_DIR")"
    COMPOSE_DIR="$(timed_text_input "Enter compose directory" "$COMPOSE_DIR")"
    ENV_FILE="$(timed_text_input "Enter Docker .env path" "$ENV_FILE")"

    [ -f "$ENV_FILE" ] || msg_error ".env file not found: ${ENV_FILE}"

    # shellcheck disable=SC1090
    set -a
    . "$ENV_FILE"
    set +a

    DOCKER_DIR="${DOCKER_DIR:-/home/${DOCKER_USER}/docker}"
    COMPOSE_DIR="${COMPOSE_DIR:-${DOCKER_DIR}/compose}"
    ENV_FILE="${ENV_FILE:-${DOCKER_DIR}/.env}"
    export DOCKER_DIR COMPOSE_DIR ENV_FILE

    DOMAIN="${DOMAIN:-}"
    AUTHENTIK_HOST="${AUTHENTIK_HOST_BROWSER:-${AUTHENTIK_HOST:-https://auth.${DOMAIN}}}"
    AUTHENTIK_API_BASE="${AUTHENTIK_HOST%/}/api/v3"

    [ -n "$DOMAIN" ] || msg_error "DOMAIN is missing from ${ENV_FILE}"

    detail_line "Docker user" "$DOCKER_USER"
    detail_line "Docker dir" "$DOCKER_DIR"
    detail_line "Compose dir" "$COMPOSE_DIR"
    detail_line "Domain" "$DOMAIN"
    detail_line "Authentik API" "$AUTHENTIK_API_BASE"
}

function detect_admin_ui() {
    section "ADMIN UI DETECTION"

    msg_info "Detecting selected admin UI"

    if docker_cmd ps -a --format '{{.Names}}' | grep -qx 'dockge'; then
        ADMIN_UI="dockge"
        DOCKGE_SELECTED="yes"
    elif docker_cmd ps -a --format '{{.Names}}' | grep -qx 'komodo-core'; then
        ADMIN_UI="komodo"
        KOMODO_SELECTED="yes"
    elif docker_cmd ps -a --format '{{.Names}}' | grep -qx 'dockhand'; then
        ADMIN_UI="dockhand"
    elif docker_cmd ps -a --format '{{.Names}}' | grep -qx 'portainer'; then
        ADMIN_UI="portainer"
        PORTAINER_SELECTED="yes"
    else
        ADMIN_UI="${ADMIN_UI:-unknown}"
    fi

    msg_ok "ADMIN UI DETECTION COMPLETE"
    detail_line "Selected admin UI" "$ADMIN_UI"

    if [ "$ADMIN_UI" == "unknown" ]; then
        msg_warn "No Dockge, Komodo, Dockhand, or Portainer container detected. Admin UI-specific hardening will be skipped."
    fi
}

# =========================================================
#  PREFLIGHT
# =========================================================

# --- 10. STACK HEALTH CHECK ---
function verify_required_containers() {
    section "STACK HEALTH CHECK"

    local required_containers=(
        traefik
        authentik-server
        authentik-worker
        postgres
        redis
        temporal
        postiz
    )

    local container=""

    for container in "${required_containers[@]}"; do
        msg_info "Checking ${container}"

        if docker_cmd ps --format '{{.Names}}' | grep -qx "$container"; then
            msg_ok "${container} RUNNING"
        else
            msg_error "${container} is not running. Deploy core stacks before Script 7."
        fi
    done

    AUTHENTIK_CONTAINERS_OK="yes"
}

function start_confirmation() {
    local start_yn=""

    section "START"

    echo -e "${YW}This script finalizes Authentik/Traefik integration, closes bootstrap exposure, and applies final hardening checks.${CL}"
    echo -e "${YW}Run it only after all stacks are deployed and healthy.${CL}"
    echo ""
    detail_line "Authentik URL" "${AUTHENTIK_HOST}"
    detail_line "Domain-level forward-auth" "${DOMAIN}"
    detail_line "Selected admin UI" "${ADMIN_UI}"
    echo ""

    start_yn="$(timed_yes_no "Start Final Hardening + SSO Integration?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi
}

# =========================================================
#  TRAEFIK CONFIG VERIFICATION
# =========================================================

# --- 11. TRAEFIK CONFIG AUDIT ---
function verify_traefik_dynamic_config() {
    section "TRAEFIK CONFIG AUDIT"

    local dynamic_config="${DOCKER_DIR}/appdata/traefik/dynamic-config.yml"
    local static_config="${DOCKER_DIR}/appdata/traefik/traefik.yml"

    [ -f "$dynamic_config" ] || msg_error "Traefik dynamic config not found: ${dynamic_config}"
    [ -f "$static_config" ] || msg_error "Traefik static config not found: ${static_config}"

    msg_info "Checking for stale Authentik Docker-provider middleware references"
    local stale_authentik_docker_middleware="authentik@""docker"
    if grep -q "$stale_authentik_docker_middleware" "$dynamic_config"; then
        msg_error "Stale Authentik Docker-provider middleware reference found in dynamic-config.yml. Use the file-provider authentik middleware instead."
    fi
    msg_ok "NO STALE AUTHENTIK@DOCKER REFERENCES"

    msg_info "Checking Authentik forwardAuth middleware"
    if grep -q 'forwardAuth:' "$dynamic_config" \
        && grep -q 'authentik-server:9000/outpost.goauthentik.io/auth/traefik' "$dynamic_config" \
        && grep -q 'maxResponseBodySize: 1048576' "$dynamic_config"; then
        msg_ok "AUTHENTIK FORWARDAUTH MIDDLEWARE FOUND"
    else
        msg_error "Authentik forwardAuth middleware is missing or incomplete."
    fi

    msg_info "Checking Authentik outpost callback router"
    if grep -q 'authentik-outpost:' "$dynamic_config" \
        && grep -q 'PathPrefix(`/outpost.goauthentik.io/`)' "$dynamic_config"; then
        msg_ok "AUTHENTIK OUTPOST CALLBACK ROUTER FOUND"
    else
        msg_error "Authentik outpost callback router missing from dynamic-config.yml."
    fi

    msg_info "Checking Traefik encoded-character configuration"
    if grep -q 'encodedCharacters:' "$static_config"; then
        msg_ok "TRAEFIK ENCODED-CHARACTER CONFIG FOUND"
    else
        msg_warn "Traefik encoded-character config not found. Add this to final Script 6 template fixes."
    fi

    TRAEFIK_CONFIG_OK="yes"
}

# =========================================================
#  AUTHENTIK API HELPERS
# =========================================================

# --- 12. AUTHENTIK TOKEN COLLECTION ---
function collect_authentik_api_token() {
    section "AUTHENTIK API TOKEN"

    if [ -n "${AUTHENTIK_BOOTSTRAP_TOKEN:-}" ]; then
        AUTHENTIK_BOOTSTRAP_TOKEN_PRESENT="yes"
        msg_ok "AUTHENTIK BOOTSTRAP TOKEN FOUND IN .ENV"
        echo -e "${YW}Note: AUTHENTIK_BOOTSTRAP_TOKEN is not an Authentik API token and will not be used for API automation.${CL}"
    else
        AUTHENTIK_BOOTSTRAP_TOKEN_PRESENT="no"
    fi

    if [ -n "${AUTHENTIK_API_TOKEN:-}" ]; then
        AUTHENTIK_TOKEN_SOURCE="environment-or-env-file"
        msg_ok "AUTHENTIK API TOKEN FOUND"
        return 0
    fi

    echo -e "${YW}Authentik app/provider/outpost setup is now handled by Script 6.5; Script 7 is hardening-only.${CL}"
    echo -e "${YW}Leave blank to skip API automation and keep verification/manual guidance only.${CL}"
    echo ""
    echo -e "${BL}Manual token path:${CL}"
    echo -e "${YW}Authentik Admin → Directory/System → Tokens/App passwords → Create token for an admin user.${CL}"
    echo ""

    AUTHENTIK_API_TOKEN="$(sensitive_line_input "Paste Authentik API token, or leave blank")"
    AUTHENTIK_API_TOKEN="$(printf '%s' "$AUTHENTIK_API_TOKEN" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ -z "$AUTHENTIK_API_TOKEN" ]; then
        AUTHENTIK_TOKEN_SOURCE="none"
        msg_warn "AUTHENTIK API TOKEN NOT PROVIDED; API AUTOMATION WILL BE SKIPPED"
    else
        AUTHENTIK_TOKEN_SOURCE="prompt"
        msg_ok "AUTHENTIK API TOKEN CAPTURED WITHOUT LOGGING"
    fi

    return 0
}

function ak_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [ -z "$AUTHENTIK_API_TOKEN" ]; then
        return 1
    fi

    if [ -n "$data" ]; then
        curl -ksS \
            -X "$method" \
            "${AUTHENTIK_API_BASE}${endpoint}" \
            -H "Authorization: Bearer ${AUTHENTIK_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            --data "$data"
    else
        curl -ksS \
            -X "$method" \
            "${AUTHENTIK_API_BASE}${endpoint}" \
            -H "Authorization: Bearer ${AUTHENTIK_API_TOKEN}" \
            -H "Accept: application/json"
    fi
}

function json_get_first_pk() {
    python3 -c 'import json,sys; data=json.load(sys.stdin); items=data.get("results", data if isinstance(data, list) else []); print(items[0].get("pk", "") if items else "")'
}

function json_get_first_uuid_or_pk() {
    python3 -c 'import json,sys; data=json.load(sys.stdin); items=data.get("results", data if isinstance(data, list) else []); print(items[0].get("pk") or items[0].get("uuid") or "" if items else "")'
}

function json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

# --- 13. AUTHENTIK API REACHABILITY ---
function verify_authentik_api() {
    section "AUTHENTIK API CHECK"

    if [ -z "$AUTHENTIK_API_TOKEN" ]; then
        AUTHENTIK_API_OK="skipped-no-token"
        msg_skip "AUTHENTIK API CHECK SKIPPED BECAUSE NO TOKEN WAS PROVIDED"
        return 0
    fi

    msg_info "Checking Authentik API access"

    if ak_api GET "/core/users/me/" >/dev/null 2>&1; then
        AUTHENTIK_API_OK="yes"
        msg_ok "AUTHENTIK API ACCESS CONFIRMED"
    else
        AUTHENTIK_API_OK="failed"
        msg_warn "Authentik API token did not authenticate. Automation will be skipped."
        AUTHENTIK_API_TOKEN=""
    fi
}

# --- 14. AUTHENTIK FORWARD AUTH AUTOMATION ---
function authentik_get_flow_pk() {
    local slug="$1"
    local pk=""

    pk="$(ak_api GET "/flows/instances/?slug=${slug}" | json_get_first_pk || true)"
    printf '%s' "$pk"
}

function authentik_find_proxy_provider_pk() {
    ak_api GET "/providers/proxy/?search=Traefik%20Forward%20Auth" | json_get_first_pk || true
}

function authentik_find_application_pk() {
    ak_api GET "/core/applications/?slug=traefik-forward-auth" | json_get_first_pk || true
}

function authentik_find_embedded_outpost_pk() {
    local pk=""
    pk="$(ak_api GET "/outposts/instances/?search=authentik%20Embedded%20Outpost" | json_get_first_uuid_or_pk || true)"

    if [ -z "$pk" ]; then
        pk="$(ak_api GET "/outposts/instances/?search=Embedded%20Outpost" | json_get_first_uuid_or_pk || true)"
    fi

    printf '%s' "$pk"
}

function create_or_update_authentik_forward_auth() {
    section "AUTHENTIK FORWARD-AUTH AUTOMATION"

    if [ "$AUTHENTIK_API_OK" != "yes" ]; then
        AUTHENTIK_PROVIDER_OK="skipped-no-api"
        AUTHENTIK_APPLICATION_OK="skipped-no-api"
        AUTHENTIK_OUTPOST_ATTACH_OK="skipped-no-api"
        msg_skip "AUTHENTIK API AUTOMATION SKIPPED"
        echo -e "${YW}Manual requirements:${CL}"
        echo -e "${YW}Provider mode: Forward auth, domain-level/single application depending UI wording${CL}"
        echo -e "${YW}Authentication URL: https://auth.${DOMAIN}${CL}"
        echo -e "${YW}Cookie domain: ${DOMAIN}${CL}"
        echo -e "${YW}Attach application/provider to existing authentik Embedded Outpost${CL}"
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
    local domain_json=""

    authorization_flow="$(authentik_get_flow_pk "default-provider-authorization-implicit-consent")"
    [ -z "$authorization_flow" ] && authorization_flow="$(authentik_get_flow_pk "default-provider-authorization-explicit-consent")"
    invalidation_flow="$(authentik_get_flow_pk "default-provider-invalidation-flow")"

    if [ -z "$authorization_flow" ] || [ -z "$invalidation_flow" ]; then
        msg_warn "Could not discover default Authentik authorization/invalidation flows. Provider automation skipped."
        AUTHENTIK_PROVIDER_OK="flow-missing"
        return 0
    fi

    auth_host_json="$(printf '%s' "$AUTHENTIK_HOST" | json_escape)"
    domain_json="$(printf '%s' "$DOMAIN" | json_escape)"

    provider_pk="$(authentik_find_proxy_provider_pk)"

    response_file="$(mktemp)"
    TEMP_FILES+=("$response_file")

    if [ -z "$provider_pk" ]; then
        msg_info "Creating Traefik Forward Auth provider"
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
        ak_api POST "/providers/proxy/" "$payload" > "$response_file" || true
        provider_pk="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data.get("pk", ""))' "$response_file" 2>/dev/null || true)"
    else
        msg_info "Updating Traefik Forward Auth provider"
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
        ak_api PATCH "/providers/proxy/${provider_pk}/" "$payload" > "$response_file" || true
    fi

    if [ -z "$provider_pk" ]; then
        AUTHENTIK_PROVIDER_OK="failed"
        msg_warn "Provider automation failed. Check Authentik API schema/version and use manual UI if needed."
        return 0
    fi

    AUTHENTIK_PROVIDER_OK="yes"
    msg_ok "TRAEFIK FORWARD AUTH PROVIDER READY"
    detail_line "Provider PK" "$provider_pk"

    app_pk="$(authentik_find_application_pk)"

    if [ -z "$app_pk" ]; then
        msg_info "Creating Traefik Forward Auth application"
        payload="$(cat <<JSON
{
  "name": "Traefik Forward Auth",
  "slug": "traefik-forward-auth",
  "provider": "${provider_pk}",
  "meta_launch_url": "${AUTHENTIK_HOST}"
}
JSON
)"
        ak_api POST "/core/applications/" "$payload" > "$response_file" || true
        app_pk="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print(data.get("pk", ""))' "$response_file" 2>/dev/null || true)"
    else
        msg_info "Updating Traefik Forward Auth application"
        payload="$(cat <<JSON
{
  "name": "Traefik Forward Auth",
  "slug": "traefik-forward-auth",
  "provider": "${provider_pk}",
  "meta_launch_url": "${AUTHENTIK_HOST}"
}
JSON
)"
        ak_api PATCH "/core/applications/${app_pk}/" "$payload" > "$response_file" || true
    fi

    if [ -z "$app_pk" ]; then
        AUTHENTIK_APPLICATION_OK="failed"
        msg_warn "Application automation failed. Check Authentik API schema/version and use manual UI if needed."
        return 0
    fi

    AUTHENTIK_APPLICATION_OK="yes"
    msg_ok "TRAEFIK FORWARD AUTH APPLICATION READY"
    detail_line "Application PK" "$app_pk"

    outpost_pk="$(authentik_find_embedded_outpost_pk)"

    if [ -z "$outpost_pk" ]; then
        AUTHENTIK_OUTPOST_ATTACH_OK="not-found"
        msg_warn "Could not find existing authentik Embedded Outpost. Do not create a second custom outpost; attach manually in UI."
        return 0
    fi

    msg_info "Attaching provider to existing embedded outpost"
    payload="$(cat <<JSON
{
  "providers": [${provider_pk}]
}
JSON
)"

    if ak_api PATCH "/outposts/instances/${outpost_pk}/" "$payload" >/dev/null 2>&1; then
        AUTHENTIK_OUTPOST_ATTACH_OK="yes"
        msg_ok "PROVIDER ATTACHED TO EXISTING EMBEDDED OUTPOST"
        detail_line "Outpost" "$outpost_pk"
    else
        AUTHENTIK_OUTPOST_ATTACH_OK="failed"
        msg_warn "Outpost attach failed. Attach the application/provider to authentik Embedded Outpost manually."
    fi
}

# =========================================================
#  AUTHENTIK OUTPOST VERIFICATION
# =========================================================

# --- 15. TRUE 302 TEST ---
function verify_authentik_outpost_302() {
    section "AUTHENTIK OUTPOST VERIFICATION"

    local test_host=""
    local test_url=""
    local http_code=""

    if [ "$PORTAINER_SELECTED" == "yes" ]; then
        test_host="portainer.${DOMAIN}"
    elif [ "$DOCKGE_SELECTED" == "yes" ]; then
        test_host="dockge.${DOMAIN}"
    elif [ "$KOMODO_SELECTED" == "yes" ]; then
        test_host="komodo.${DOMAIN}"
    else
        test_host="traefik.${DOMAIN}"
    fi

    test_url="https://${test_host}/outpost.goauthentik.io/start?rd=https://${test_host}/"

    msg_info "Testing Authentik outpost route without following redirects"
    http_code="$(curl -ksS -o /dev/null -w '%{http_code}' -I "$test_url" || true)"

    if [ "$http_code" == "302" ]; then
        AUTHENTIK_OUTPOST_302_OK="yes"
        msg_ok "AUTHENTIK OUTPOST ROUTE RETURNED TRUE HTTP 302"
    else
        AUTHENTIK_OUTPOST_302_OK="no"
        msg_warn "Authentik outpost test returned HTTP ${http_code:-none}; expected 302"
        echo ""
        echo -e "${YW}Manual Authentik check required:${CL}"
        echo -e "${YW}Applications → Outposts → authentik Embedded Outpost → Edit${CL}"
        echo -e "${YW}Ensure Traefik Forward Auth is in Selected Applications, then Update.${CL}"
        echo ""
        echo -e "${YW}Retest:${CL}"
        echo -e "${GN}curl -Ik \"${test_url}\"${CL}"
    fi

    detail_line "Outpost test URL" "$test_url"
    detail_line "HTTP result" "${http_code:-none}"
}

# =========================================================
#  ADMIN UI SSO NOTES / CLEANUP
# =========================================================

# --- 16. ADMIN UI OIDC GUIDANCE ---
function configure_admin_ui_sso() {
    section "ADMIN UI SSO"

    if [ "$PORTAINER_SELECTED" == "yes" ]; then
        PORTAINER_OIDC_STATUS="manual-oauth-required"
        echo -e "${YW}Portainer CE cannot hide the internal auth prompt without Business Edition.${CL}"
        echo -e "${YW}Final expected setup is Authentik front-door protection plus Portainer OAuth button.${CL}"
        echo ""
        detail_line "Portainer Authorization URL" "${AUTHENTIK_HOST}/application/o/authorize/"
        detail_line "Portainer Token URL" "${AUTHENTIK_HOST}/application/o/token/"
        detail_line "Portainer Resource URL" "${AUTHENTIK_HOST}/application/o/userinfo/"
        detail_line "Portainer Redirect URL" "https://portainer.${DOMAIN}/"
        detail_line "Portainer Scopes" "email openid profile"
        detail_line "Portainer User identifier" "preferred_username"
        msg_ok "PORTAINER OIDC GUIDANCE RECORDED"
        return 0
    fi

    if [ "$DOCKGE_SELECTED" == "yes" ]; then
        msg_ok "DOCKGE USES AUTHENTIK FORWARD-AUTH PROTECTION; NO INTERNAL OIDC REQUIRED"
        return 0
    fi

    if [ "$KOMODO_SELECTED" == "yes" ]; then
        KOMODO_OIDC_STATUS="manual-oidc-required"
        echo -e "${YW}Komodo should use Authentik OIDC for clean app-level SSO.${CL}"
        echo -e "${YW}This script records the requirement; final Komodo automation can be added after its compose/env schema is locked.${CL}"
        msg_ok "KOMODO OIDC REQUIREMENT RECORDED"
        return 0
    fi

    msg_skip "NO SUPPORTED ADMIN UI DETECTED; SSO GUIDANCE SKIPPED"
}

# --- 17. PORTAINER BOOTSTRAP PORT CLOSURE ---
function close_portainer_bootstrap_exposure() {
    section "ADMIN UI BOOTSTRAP CLOSURE"

    local project=""
    local service=""
    local compose_file=""
    local override_file=""
    local internal_port=""
    local bootstrap_port=""
    local close_yn=""

    case "$ADMIN_UI" in
        portainer)
            project="portainer"; service="portainer"; compose_file="${COMPOSE_DIR}/01-[4]-portainer-compose.yml"; override_file="${COMPOSE_DIR}/01-[4]-portainer-bootstrap-override.yml"; internal_port="9443"; bootstrap_port="9443";;
        dockge)
            project="dockge"; service="dockge"; compose_file="${COMPOSE_DIR}/01-[1]-dockge-compose.yml"; override_file="${COMPOSE_DIR}/01-[1]-dockge-bootstrap-override.yml"; internal_port="5001"; bootstrap_port="5001";;
        komodo)
            project="komodo"; service="komodo-core"; compose_file="${COMPOSE_DIR}/01-[3]-komodo-compose.yml"; override_file="${COMPOSE_DIR}/01-[3]-komodo-bootstrap-override.yml"; internal_port="9120"; bootstrap_port="9120";;
        dockhand)
            project="dockhand"; service="dockhand"; compose_file="${COMPOSE_DIR}/01-[2]-dockhand-compose.yml"; override_file="${COMPOSE_DIR}/01-[2]-dockhand-bootstrap-override.yml"; internal_port="3000"; bootstrap_port="3000";;
        *)
            ADMIN_UI_BOOTSTRAP_CLOSED="not-applicable"
            PORTAINER_BOOTSTRAP_CLOSED="not-applicable"
            msg_skip "NO SUPPORTED ADMIN UI DETECTED; BOOTSTRAP CLOSURE SKIPPED"
            return 0
            ;;
    esac

    if [ ! -f "$compose_file" ]; then
        ADMIN_UI_BOOTSTRAP_CLOSED="missing-compose"
        PORTAINER_BOOTSTRAP_CLOSED="$ADMIN_UI_BOOTSTRAP_CLOSED"
        msg_warn "Admin UI compose file not found: ${compose_file}"
        return 0
    fi

    if [ ! -f "$override_file" ]; then
        ADMIN_UI_BOOTSTRAP_CLOSED="already-no-override"
        PORTAINER_BOOTSTRAP_CLOSED="$ADMIN_UI_BOOTSTRAP_CLOSED"
        msg_ok "NO ADMIN UI BOOTSTRAP OVERRIDE FILE FOUND"
        return 0
    fi

    echo -e "${YW}This redeploys ${ADMIN_UI} without its bootstrap override so direct bootstrap port exposure closes.${CL}"
    echo -e "${YW}Traefik/AuthentiK domain access should remain available.${CL}"
    echo ""

    close_yn="$(timed_yes_no "Close temporary ${ADMIN_UI} bootstrap port now?" "y")"

    if [[ "$close_yn" =~ ^[Nn] ]]; then
        ADMIN_UI_BOOTSTRAP_CLOSED="user-skipped"
        PORTAINER_BOOTSTRAP_CLOSED="$ADMIN_UI_BOOTSTRAP_CLOSED"
        msg_skip "ADMIN UI BOOTSTRAP PORT CLOSURE SKIPPED"
        return 0
    fi

    msg_info "Redeploying ${ADMIN_UI} without bootstrap override"
    docker_cmd compose --env-file "$ENV_FILE" -p "$project" -f "$compose_file" up -d >/dev/null
    msg_ok "${ADMIN_UI} REDEPLOYED WITHOUT BOOTSTRAP OVERRIDE"

    msg_info "Checking direct ${ADMIN_UI} bootstrap mapping"
    if docker_cmd port "$service" "${internal_port}/tcp" 2>/dev/null | grep -q ":${bootstrap_port}$"; then
        ADMIN_UI_BOOTSTRAP_CLOSED="not-confirmed"
        msg_warn "${ADMIN_UI} still appears to have direct bootstrap mapping. Check compose labels/ports."
    else
        ADMIN_UI_BOOTSTRAP_CLOSED="yes"
        msg_ok "ADMIN UI DIRECT BOOTSTRAP PORT CLOSED"
    fi

    PORTAINER_BOOTSTRAP_CLOSED="$ADMIN_UI_BOOTSTRAP_CLOSED"
}

# --- 18. UFW CLEANUP ---
function remove_portainer_ufw_rule() {
    section "UFW BOOTSTRAP RULE CLEANUP"

    local bootstrap_port=""

    case "$ADMIN_UI" in
        portainer) bootstrap_port="9443" ;;
        dockge) bootstrap_port="5001" ;;
        komodo) bootstrap_port="9120" ;;
        dockhand) bootstrap_port="3000" ;;
        *)
            UFW_ADMIN_UI_RULE_REMOVED="not-applicable"
            UFW_PORTAINER_RULE_REMOVED="$UFW_ADMIN_UI_RULE_REMOVED"
            msg_skip "NO SUPPORTED ADMIN UI DETECTED; UFW CLEANUP SKIPPED"
            return 0
            ;;
    esac

    if ! command -v ufw >/dev/null 2>&1; then
        UFW_ADMIN_UI_RULE_REMOVED="ufw-not-found"
        UFW_PORTAINER_RULE_REMOVED="$UFW_ADMIN_UI_RULE_REMOVED"
        msg_skip "UFW NOT FOUND; RULE CLEANUP SKIPPED"
        return 0
    fi

    if ! ufw status 2>/dev/null | grep -qi "Status: active" && ! { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" ufw status 2>/dev/null | grep -qi "Status: active"; }; then
        UFW_ADMIN_UI_RULE_REMOVED="ufw-not-active"
        UFW_PORTAINER_RULE_REMOVED="$UFW_ADMIN_UI_RULE_REMOVED"
        msg_skip "UFW NOT ACTIVE; RULE CLEANUP SKIPPED"
        return 0
    fi

    msg_info "Removing temporary ${ADMIN_UI} ${bootstrap_port}/tcp UFW rule"
    run_optional ufw delete allow "${bootstrap_port}/tcp"
    UFW_ADMIN_UI_RULE_REMOVED="attempted"
    UFW_PORTAINER_RULE_REMOVED="$UFW_ADMIN_UI_RULE_REMOVED"
    msg_ok "TEMPORARY ADMIN UI UFW RULE REMOVAL ATTEMPTED"
}

# =========================================================
#  POSTIZ / TEMPORAL GUARD CLEANUP
# =========================================================

# --- 19. POSTIZ HEALTH VERIFICATION ---
# Confirms the real Postiz stack is healthy before stopping the temporary yml 07 guard.
# The guard exists only to remove Temporal's default Text search attributes before Postiz starts.
function verify_postiz_health() {
    section "POSTIZ HEALTH CHECK"

    local postiz_running="no"
    local temporal_running="no"
    local backend_port_found=""
    local auth_url="https://postiz.${DOMAIN}/auth"
    local auth_code=""

    msg_info "Checking Temporal container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'temporal'; then
        temporal_running="yes"
        msg_ok "TEMPORAL RUNNING"
    else
        POSTIZ_HEALTH_OK="no"
        msg_warn "TEMPORAL IS NOT RUNNING; POSTIZ GUARD CLEANUP WILL BE SKIPPED"
        return 0
    fi

    msg_info "Checking Postiz container"
    if docker_cmd ps --format '{{.Names}}' | grep -qx 'postiz'; then
        postiz_running="yes"
        msg_ok "POSTIZ RUNNING"
    else
        POSTIZ_HEALTH_OK="no"
        msg_warn "POSTIZ IS NOT RUNNING; POSTIZ GUARD CLEANUP WILL BE SKIPPED"
        return 0
    fi

    msg_info "Checking Postiz backend port 3000"
    backend_port_found="$(docker_cmd exec postiz sh -c "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -i ':0BB8' || true" 2>/dev/null || true)"

    if [ -n "$backend_port_found" ]; then
        POSTIZ_BACKEND_PORT_OK="yes"
        msg_ok "POSTIZ BACKEND PORT 3000 IS LISTENING"
    else
        POSTIZ_BACKEND_PORT_OK="no"
        POSTIZ_HEALTH_OK="no"
        msg_warn "POSTIZ BACKEND PORT 3000 IS NOT LISTENING; POSTIZ GUARD CLEANUP WILL BE SKIPPED"
        return 0
    fi

    msg_info "Checking Postiz web route"
    auth_code="$(curl -ksS -o /dev/null -w '%{http_code}' -I "$auth_url" || true)"

    case "$auth_code" in
        200|301|302|307|308|401|403)
            POSTIZ_WEB_ROUTE_OK="yes"
            POSTIZ_HEALTH_OK="yes"
            msg_ok "POSTIZ WEB ROUTE RESPONDED WITH HTTP ${auth_code}"
            ;;
        *)
            POSTIZ_WEB_ROUTE_OK="no"
            POSTIZ_HEALTH_OK="no"
            msg_warn "POSTIZ WEB ROUTE RETURNED HTTP ${auth_code:-none}; POSTIZ GUARD CLEANUP WILL BE SKIPPED"
            return 0
            ;;
    esac

    detail_line "Postiz health" "$POSTIZ_HEALTH_OK"
    detail_line "Backend port 3000" "$POSTIZ_BACKEND_PORT_OK"
    detail_line "Web route" "${auth_url} -> ${auth_code}"
}

# --- 20. POSTIZ TEMPORAL GUARD STOPPER ---
# Stops the temporary yml 07 guard after Postiz is confirmed healthy.
# It does not delete Portainer stack definitions or compose files.
function stop_postiz_temporal_guard_if_safe() {
    section "POSTIZ TEMPORAL GUARD CLEANUP"

    local guard_container="postiz-temporal-guard"
    local stop_yn=""

    if ! docker_cmd ps -a --format '{{.Names}}' | grep -qx "$guard_container"; then
        POSTIZ_TEMPORAL_GUARD_STATUS="not-found"
        POSTIZ_TEMPORAL_GUARD_STOPPED="not-applicable"
        msg_ok "NO POSTIZ TEMPORAL GUARD CONTAINER FOUND"
        return 0
    fi

    POSTIZ_TEMPORAL_GUARD_STATUS="found"

    if [ "$POSTIZ_HEALTH_OK" != "yes" ]; then
        POSTIZ_TEMPORAL_GUARD_STOPPED="kept-postiz-not-healthy"
        msg_warn "POSTIZ IS NOT CONFIRMED HEALTHY; TEMPORAL GUARD WILL BE LEFT RUNNING"
        return 0
    fi

    echo -e "${YW}The temporary yml 07 Postiz Temporal guard is no longer needed because Postiz is healthy.${CL}"
    echo -e "${YW}This will only stop the guard container. It will not delete Portainer stack data or GitHub backup.${CL}"
    echo ""

    stop_yn="$(timed_yes_no "Stop temporary Postiz Temporal guard now?" "y")"

    if [[ "$stop_yn" =~ ^[Nn] ]]; then
        POSTIZ_TEMPORAL_GUARD_STOPPED="user-skipped"
        msg_skip "POSTIZ TEMPORAL GUARD STOP SKIPPED"
        return 0
    fi

    msg_info "Stopping Postiz Temporal guard"
    docker_cmd stop "$guard_container" >/dev/null 2>&1 || true

    if docker_cmd ps --format '{{.Names}}' | grep -qx "$guard_container"; then
        POSTIZ_TEMPORAL_GUARD_STOPPED="failed"
        msg_warn "POSTIZ TEMPORAL GUARD STILL APPEARS RUNNING"
    else
        POSTIZ_TEMPORAL_GUARD_STOPPED="yes"
        msg_ok "POSTIZ TEMPORAL GUARD STOPPED"
    fi
}

# =========================================================
#  SYSTEM HARDENING
# =========================================================

# --- 19. SUDO HARDENING SAFETY CHECK ---
function verify_real_sudo_password_before_hardening() {
    if [ -z "$SUDO_CMD" ]; then
        echo -e "${YW}Running as root; cannot verify the target user's sudo password interactively from this session.${CL}"
        echo -e "${YW}Skip this unless you have already set and tested a real sudo password for ${DOCKER_USER}.${CL}"
        return 1
    fi

    echo -e "${YW}For safety, the script will ask sudo to require a real password before disabling NOPASSWD.${CL}"
    echo -e "${YW}If this fails, NOPASSWD hardening will be skipped to avoid locking you out.${CL}"
    echo ""

    if "$SUDO_CMD" -k && "$SUDO_CMD" -v; then
        return 0
    fi

    return 1
}

# --- 20. SUDO HARDENING ---
function harden_sudo_nopasswd() {
    section "SUDO HARDENING"

    local harden_yn=""
    local sudoers_files=(
        "/etc/sudoers.d/90-cloud-init-users"
        "/etc/sudoers.d/99-${DOCKER_USER}-nopasswd"
        "/etc/sudoers.d/${DOCKER_USER}"
    )

    local file=""

    echo -e "${YW}This step looks for broad NOPASSWD sudo entries for ${DOCKER_USER}.${CL}"
    echo -e "${YW}Default is NO. Only enable after you have confirmed a real sudo password works.${CL}"
    echo ""

    for file in "${sudoers_files[@]}"; do
        if [ -f "$file" ] || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" test -f "$file" 2>/dev/null; }; then
            detail_line "Detected sudoers candidate" "$file"
        fi
    done

    harden_yn="$(timed_yes_no "Disable broad NOPASSWD sudo entries if found?" "n")"

    if [[ "$harden_yn" =~ ^[Nn] ]]; then
        NOPASSWD_HARDENED="user-skipped"
        msg_skip "SUDO NOPASSWD HARDENING SKIPPED"
        return 0
    fi

    if ! verify_real_sudo_password_before_hardening; then
        NOPASSWD_HARDENED="skipped-password-not-verified"
        msg_warn "REAL SUDO PASSWORD WAS NOT VERIFIED; NOPASSWD HARDENING SKIPPED"
        return 0
    fi

    for file in "${sudoers_files[@]}"; do
        if [ -f "$file" ] || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" test -f "$file" 2>/dev/null; }; then
            msg_info "Backing up ${file}"
            run_optional cp -n "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
            msg_ok "BACKUP CREATED FOR ${file}"

            msg_info "Commenting NOPASSWD lines in ${file}"
            if [ -n "$SUDO_CMD" ]; then
                "$SUDO_CMD" sed -i -E '/NOPASSWD/ s/^/# disabled by final hardening: /' "$file" || true
            else
                sed -i -E '/NOPASSWD/ s/^/# disabled by final hardening: /' "$file" || true
            fi
            msg_ok "NOPASSWD LINES COMMENTED IN ${file}"
        fi
    done

    NOPASSWD_HARDENED="yes"
}

# --- 21. DOCKER-USER FIREWALL REVIEW ---
function docker_user_firewall_review() {
    section "DOCKER-USER FIREWALL REVIEW"

    echo -e "${YW}Docker can bypass UFW for published container ports.${CL}"
    echo -e "${YW}For this project, public access should normally be only Traefik on 80/443.${CL}"
    echo ""
    echo -e "${BL}Recommended later:${CL}"
    echo -e "${YW}Review DOCKER-USER rules after confirming every service works.${CL}"
    echo -e "${YW}Do not apply broad blocking automatically until all ports and flows are confirmed.${CL}"
    echo ""

    DOCKER_USER_RULES_REVIEWED="yes"
    msg_ok "DOCKER-USER FIREWALL REVIEW RECORDED"
}

# =========================================================
#  VERIFICATION / SUMMARY
# =========================================================

# --- 22. FINAL CONTAINER SUMMARY ---
function show_container_summary() {
    section "CONTAINER SUMMARY"

    docker_cmd ps --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}' || true
}


# --- 22A. IMAGE LOCK REPORT ---
# Generates a post-deployment image/digest report without automatically rewriting YAML files.
function generate_image_lock_report() {
    section "IMAGE LOCK REPORT"

    local report="${DOCKER_DIR}/docker-image-lock-report.txt"
    local tmp_report=""

    tmp_report="$(mktemp)"
    TEMP_FILES+=("$tmp_report")

    {
        echo "--- CREA DOCKER IMAGE LOCK REPORT ---"
        echo "Date: $(date)"
        echo "Docker dir: ${DOCKER_DIR}"
        echo ""
        echo "Purpose: deploy with latest during active testing, then review this report before pinning known-good tags/digests."
        echo "No compose YAML was modified by Script 7."
        echo ""
        docker_cmd ps --format '{{.Names}}' | while IFS= read -r container; do
            [ -n "$container" ] || continue
            image="$(docker_cmd inspect --format '{{.Config.Image}}' "$container" 2>/dev/null || true)"
            digest="$(docker_cmd inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{end}}' "$container" 2>/dev/null || true)"
            echo "Container: ${container}"
            echo "Current image: ${image:-unknown}"
            echo "Resolved digest: ${digest:-not available locally}"
            echo "Recommendation: pin after this deployment is verified stable."
            echo ""
        done
    } > "$tmp_report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" install -m 0640 -o "$DOCKER_USER" -g "$DOCKER_USER" "$tmp_report" "$report"
    else
        install -m 0640 "$tmp_report" "$report"
    fi

    IMAGE_LOCK_REPORT="$report"
    msg_ok "IMAGE LOCK REPORT CREATED"
    detail_line "Image lock report" "$IMAGE_LOCK_REPORT"
}

# --- 23. VERIFICATION REPORT ---
function create_verification_report() {
    section "VERIFICATION REPORT"

    msg_info "Writing final hardening verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<EOF2
--- FINAL HARDENING + SSO VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
Admin UI: $ADMIN_UI
Authentik token source: $AUTHENTIK_TOKEN_SOURCE

Results:
Traefik config OK: $TRAEFIK_CONFIG_OK
Authentik containers OK: $AUTHENTIK_CONTAINERS_OK
Authentik API OK: $AUTHENTIK_API_OK
Authentik provider OK: $AUTHENTIK_PROVIDER_OK
Authentik application OK: $AUTHENTIK_APPLICATION_OK
Authentik outpost attach OK: $AUTHENTIK_OUTPOST_ATTACH_OK
Authentik outpost 302 OK: $AUTHENTIK_OUTPOST_302_OK
Portainer OIDC status: $PORTAINER_OIDC_STATUS
Komodo OIDC status: $KOMODO_OIDC_STATUS
Admin UI bootstrap closed: $ADMIN_UI_BOOTSTRAP_CLOSED
Portainer bootstrap closed: $PORTAINER_BOOTSTRAP_CLOSED
UFW admin UI rule removed: $UFW_ADMIN_UI_RULE_REMOVED
UFW Portainer rule removed: $UFW_PORTAINER_RULE_REMOVED
NOPASSWD hardened: $NOPASSWD_HARDENED
Postiz health OK: $POSTIZ_HEALTH_OK
Postiz backend port OK: $POSTIZ_BACKEND_PORT_OK
Postiz web route OK: $POSTIZ_WEB_ROUTE_OK
Postiz Temporal guard status: $POSTIZ_TEMPORAL_GUARD_STATUS
Postiz Temporal guard stopped: $POSTIZ_TEMPORAL_GUARD_STOPPED
DOCKER-USER review: $DOCKER_USER_RULES_REVIEWED
Image lock report: $IMAGE_LOCK_REPORT
EOF2
    else
        cat > "$VERIFY_LOG" <<EOF2
--- FINAL HARDENING + SSO VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
Admin UI: $ADMIN_UI
Authentik token source: $AUTHENTIK_TOKEN_SOURCE

Results:
Traefik config OK: $TRAEFIK_CONFIG_OK
Authentik containers OK: $AUTHENTIK_CONTAINERS_OK
Authentik API OK: $AUTHENTIK_API_OK
Authentik provider OK: $AUTHENTIK_PROVIDER_OK
Authentik application OK: $AUTHENTIK_APPLICATION_OK
Authentik outpost attach OK: $AUTHENTIK_OUTPOST_ATTACH_OK
Authentik outpost 302 OK: $AUTHENTIK_OUTPOST_302_OK
Portainer OIDC status: $PORTAINER_OIDC_STATUS
Komodo OIDC status: $KOMODO_OIDC_STATUS
Portainer bootstrap closed: $PORTAINER_BOOTSTRAP_CLOSED
UFW Portainer rule removed: $UFW_PORTAINER_RULE_REMOVED
NOPASSWD hardened: $NOPASSWD_HARDENED
Postiz health OK: $POSTIZ_HEALTH_OK
Postiz backend port OK: $POSTIZ_BACKEND_PORT_OK
Postiz web route OK: $POSTIZ_WEB_ROUTE_OK
Postiz Temporal guard status: $POSTIZ_TEMPORAL_GUARD_STATUS
Postiz Temporal guard stopped: $POSTIZ_TEMPORAL_GUARD_STOPPED
DOCKER-USER review: $DOCKER_USER_RULES_REVIEWED
Image lock report: $IMAGE_LOCK_REPORT
EOF2
    fi

    {
        echo ""
        echo "Containers:"
        docker_cmd ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Networks}}' 2>/dev/null || true
        echo ""
        echo "Traefik recent warnings/errors:"
        docker_cmd logs traefik --tail=80 2>/dev/null | grep -E "ERR|WRN|authentik@\"\"docker|middleware .* does not exist" || true
    } | if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee -a "$VERIFY_LOG" >/dev/null; else tee -a "$VERIFY_LOG" >/dev/null; fi

    msg_ok "FINAL HARDENING VERIFICATION REPORT WRITTEN"
}

# --- 24. COMPLETION MARKER ---
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<EOF2
Final Hardening + SSO completed on: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
Admin UI: $ADMIN_UI
Traefik config OK: $TRAEFIK_CONFIG_OK
Authentik containers OK: $AUTHENTIK_CONTAINERS_OK
Authentik API OK: $AUTHENTIK_API_OK
Authentik provider OK: $AUTHENTIK_PROVIDER_OK
Authentik application OK: $AUTHENTIK_APPLICATION_OK
Authentik outpost attach OK: $AUTHENTIK_OUTPOST_ATTACH_OK
Authentik outpost 302 OK: $AUTHENTIK_OUTPOST_302_OK
Portainer OIDC status: $PORTAINER_OIDC_STATUS
Komodo OIDC status: $KOMODO_OIDC_STATUS
Portainer bootstrap closed: $PORTAINER_BOOTSTRAP_CLOSED
UFW Portainer rule removed: $UFW_PORTAINER_RULE_REMOVED
NOPASSWD hardened: $NOPASSWD_HARDENED
DOCKER-USER review: $DOCKER_USER_RULES_REVIEWED
Verify log: $VERIFY_LOG
EOF2
    else
        cat > "$COMPLETED_MARKER" <<EOF2
Final Hardening + SSO completed on: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Compose dir: $COMPOSE_DIR
Domain: $DOMAIN
Admin UI: $ADMIN_UI
Traefik config OK: $TRAEFIK_CONFIG_OK
Authentik containers OK: $AUTHENTIK_CONTAINERS_OK
Authentik API OK: $AUTHENTIK_API_OK
Authentik provider OK: $AUTHENTIK_PROVIDER_OK
Authentik application OK: $AUTHENTIK_APPLICATION_OK
Authentik outpost attach OK: $AUTHENTIK_OUTPOST_ATTACH_OK
Authentik outpost 302 OK: $AUTHENTIK_OUTPOST_302_OK
Portainer OIDC status: $PORTAINER_OIDC_STATUS
Komodo OIDC status: $KOMODO_OIDC_STATUS
Portainer bootstrap closed: $PORTAINER_BOOTSTRAP_CLOSED
UFW Portainer rule removed: $UFW_PORTAINER_RULE_REMOVED
NOPASSWD hardened: $NOPASSWD_HARDENED
DOCKER-USER review: $DOCKER_USER_RULES_REVIEWED
Verify log: $VERIFY_LOG
EOF2
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 25. FINAL SUMMARY ---
function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    detail_line "DOMAIN" "$DOMAIN"
    detail_line "ADMIN UI" "$ADMIN_UI"
    detail_line "TRAEFIK CONFIG OK" "$TRAEFIK_CONFIG_OK"
    detail_line "AUTHENTIK CONTAINERS OK" "$AUTHENTIK_CONTAINERS_OK"
    detail_line "AUTHENTIK API OK" "$AUTHENTIK_API_OK"
    detail_line "AUTHENTIK PROVIDER" "$AUTHENTIK_PROVIDER_OK"
    detail_line "AUTHENTIK APPLICATION" "$AUTHENTIK_APPLICATION_OK"
    detail_line "AUTHENTIK OUTPOST ATTACH" "$AUTHENTIK_OUTPOST_ATTACH_OK"
    detail_line "AUTHENTIK OUTPOST 302" "$AUTHENTIK_OUTPOST_302_OK"
    detail_line "PORTAINER OIDC" "$PORTAINER_OIDC_STATUS"
    detail_line "KOMODO OIDC" "$KOMODO_OIDC_STATUS"
    detail_line "ADMIN UI BOOTSTRAP CLOSED" "$ADMIN_UI_BOOTSTRAP_CLOSED"
    detail_line "PORTAINER BOOTSTRAP CLOSED" "$PORTAINER_BOOTSTRAP_CLOSED"
    detail_line "UFW ADMIN UI RULE REMOVED" "$UFW_ADMIN_UI_RULE_REMOVED"
    detail_line "UFW PORTAINER RULE REMOVED" "$UFW_PORTAINER_RULE_REMOVED"
    detail_line "NOPASSWD HARDENED" "$NOPASSWD_HARDENED"
    detail_line "POSTIZ HEALTH" "$POSTIZ_HEALTH_OK"
    detail_line "POSTIZ BACKEND 3000" "$POSTIZ_BACKEND_PORT_OK"
    detail_line "POSTIZ WEB ROUTE" "$POSTIZ_WEB_ROUTE_OK"
    detail_line "POSTIZ TEMPORAL GUARD" "$POSTIZ_TEMPORAL_GUARD_STOPPED"
    detail_line "DOCKER-USER REVIEW" "$DOCKER_USER_RULES_REVIEWED"
    detail_line "VERIFY LOG" "$VERIFY_LOG"
    detail_line "IMAGE LOCK REPORT" "$IMAGE_LOCK_REPORT"

    echo ""
    echo -e "${BL}IMPORTANT:${CL}"

    if [ "$AUTHENTIK_OUTPOST_302_OK" != "yes" ]; then
        echo -e "${YW}Authentik outpost verification did not pass. Attach the Traefik Forward Auth app/provider to the existing authentik Embedded Outpost, then rerun Script 7.${CL}"
    else
        echo -e "${GN}Authentik forward-auth outpost route is responding with true HTTP 302.${CL}"
    fi

    if [ "$POSTIZ_TEMPORAL_GUARD_STOPPED" == "yes" ]; then
        echo -e "${GN}Temporary Postiz Temporal guard was stopped because Postiz is healthy.${CL}"
    elif [ "$POSTIZ_TEMPORAL_GUARD_STATUS" == "found" ]; then
        echo -e "${YW}Postiz Temporal guard was found but not stopped. Keep it until Postiz health is confirmed.${CL}"
    fi

    echo ""
    echo -e "${YW}If all services are stable, the next future improvement is DOCKER-USER firewall hardening.${CL}"
    echo ""
}


# --- 25A. READY TO APPLY SUMMARY ---
# Confirms final hardening actions before Authentik, admin UI, firewall or cleanup changes are applied.
function show_ready_to_apply() {
    local apply_yn=""

    section "READY TO APPLY"

    echo -e "${YW}Preflight checks and token collection are complete. No Authentik/provider/admin UI/firewall cleanup changes have been applied yet.${CL}"
    echo ""
    detail_line "Docker user" "$DOCKER_USER"
    detail_line "Docker directory" "$DOCKER_DIR"
    detail_line "Compose directory" "$COMPOSE_DIR"
    detail_line "Domain" "$DOMAIN"
    detail_line "Authentik API" "$AUTHENTIK_API_BASE"
    detail_line "Authentik token source" "$AUTHENTIK_TOKEN_SOURCE"
    detail_line "Authentik bootstrap token present" "$AUTHENTIK_BOOTSTRAP_TOKEN_PRESENT"
    detail_line "Admin UI" "$ADMIN_UI"
    echo ""

    apply_yn="$(timed_yes_no "Apply final hardening and SSO plan now?" "y")"

    if [[ "$apply_yn" =~ ^[Nn] ]]; then
        echo -e "${YW}Final hardening cancelled. No final hardening changes were applied.${CL}"
        exit 0
    fi

    return 0
}

# =========================================================
#  MAIN
# =========================================================

# --- 26. MAIN ORCHESTRATION ---
function main() {
    init_script

    detect_docker_access
    load_env_file
    detect_admin_ui
    verify_required_containers
    start_confirmation

    verify_traefik_dynamic_config
    AUTHENTIK_API_OK="handled-by-script-6.5"
    AUTHENTIK_PROVIDER_OK="handled-by-script-6.5"
    AUTHENTIK_APPLICATION_OK="handled-by-script-6.5"
    AUTHENTIK_OUTPOST_ATTACH_OK="handled-by-script-6.5"
    AUTHENTIK_OUTPOST_302_OK="handled-by-script-6.5"
    show_ready_to_apply

    configure_admin_ui_sso
    close_portainer_bootstrap_exposure
    remove_portainer_ufw_rule

    verify_postiz_health
    stop_postiz_temporal_guard_if_safe

    harden_sudo_nopasswd
    docker_user_firewall_review

    show_container_summary
    generate_image_lock_report
    create_verification_report
    write_completion_marker
    show_final_summary

    exit 0
}

main "$@"
