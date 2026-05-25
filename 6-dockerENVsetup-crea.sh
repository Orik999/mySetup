#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker ENV Setup Crea
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Central visual theme for Docker ENV Setup.
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

SCRIPT_SOURCE="6-dockerENVsetup-crea.sh"
SCRIPT_VERSION="v1.5.7"
SCRIPT_UPDATED="2026-05-25"
SCRIPT_BUILD="pg18-redis-recursive-permissions-acme-wildcard-render"

# --- 2. GLOBAL VARIABLES ---
# Stores timers, defaults, paths, secret values, state flags and final result values.
T=15

LOG_FILE="/var/log/docker-env-setup.log"
RUNTIME_LOG_FILE=""
VERIFY_LOG="/var/log/docker-env-setup-verify.log"
COMPLETED_MARKER="/root/.docker-env-setup-completed"

DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-${USER:-dockeradmin}}}"
DEFAULT_TZ="Europe/London"
DEFAULT_DOMAIN="${DEFAULT_DOMAIN:-example.com}"
DEFAULT_CF_API_EMAIL="${DEFAULT_CF_API_EMAIL:-}"
DEFAULT_CF_ZONE_ID=""
DEFAULT_HTPASSWD_USER="admin"
DEFAULT_ADMIN_UI="dockge"

SUDO_CMD=""
LOGGING_ENABLED="no"

DOCKER_USER=""
USERDIR=""
DOCKER_DIR=""
DOCKER_SECRETS_DIR=""
CF_API_TOKEN_FILE=""

PUID_VALUE=""
PGID_VALUE=""
TZ_VALUE=""
DOMAIN_VALUE=""
CF_API_EMAIL_VALUE=""
CF_ZONE_ID_VALUE=""
CF_API_TOKEN_VALUE=""
CF_AUTH_MODE=""
CF_EMAIL_REQUIRED=""

EXISTING_SETUP="no"
REGENERATE_SECRETS="n"
DOCKER_READY="unknown"
DOCKER_COMPOSE_READY="unknown"
DOCKER_USER_IN_DOCKER_GROUP="unknown"

POSTGRES_PASSWORD=""
REDIS_PASSWORD=""
AUTHENTIK_SECRET_KEY=""
AUTHENTIK_POSTGRES_PASSWORD=""
POSTIZ_POSTGRES_PASSWORD=""
POSTIZ_JWT_SECRET=""
TEMPORAL_POSTGRES_PASSWORD=""
KOMODO_DB_PASSWORD=""
KOMODO_PASSKEY=""
KOMODO_JWT_SECRET=""
KOMODO_WEBHOOK_SECRET=""

ADMIN_UI="${DEFAULT_ADMIN_UI}"
ADMIN_UI_DISPLAY_NAME="Dockge"
ADMIN_UI_HOST=""
ADMIN_UI_URL=""

AUTHENTIK_HOST_VALUE=""
AUTHENTIK_HOST_BROWSER_VALUE=""
AUTHENTIK_BOOTSTRAP_EMAIL_VALUE=""
AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE=""
AUTHENTIK_BOOTSTRAP_TOKEN_VALUE=""
AUTHENTIK_API_TOKEN_MODE="skip"
AUTHENTIK_API_TOKEN_VALUE=""

HTPASSWD_MODE="empty"
HTPASSWD_USER_VALUE=""
HTPASSWD_PASSWORD_VALUE=""
HTPASSWD_HASH_VALUE=""
HTPASSWD_LINE_VALUE=""

SECRET_DISPLAY_WAS_SHOWN="no"
SECRET_SCREEN_CLEARED="no"

# Traefik template download defaults. These contain no secrets and can safely live in a public GitHub repo.
TRAEFIK_TEMPLATE_RAW_BASE="${TRAEFIK_TEMPLATE_RAW_BASE:-https://raw.githubusercontent.com/Orik999/mySetup/main/docker/traefik}"
TRAEFIK_STATIC_TEMPLATE_URL="${TRAEFIK_STATIC_TEMPLATE_URL:-${TRAEFIK_TEMPLATE_RAW_BASE}/traefik.yml.template}"
TRAEFIK_DYNAMIC_TEMPLATE_URL="${TRAEFIK_DYNAMIC_TEMPLATE_URL:-${TRAEFIK_TEMPLATE_RAW_BASE}/dynamic-config.yml.template}"

TRAEFIK_DIR=""
TRAEFIK_ACME_DIR=""
TRAEFIK_STATIC_CONFIG_FILE=""
TRAEFIK_DYNAMIC_CONFIG_FILE=""
TRAEFIK_TEMPLATE_TMP_DIR=""

TRAEFIK_DASHBOARD_HOST=""
PROXMOX_ROUTE_ENABLED="n"
PROXMOX_HOST=""
PROXMOX_URL=""

TEMP_FILES=()
TEMP_DIRS=()

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
# Displays the Docker ENV Setup banner.
function header_info {
echo -e "${BL}
██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗     ███████╗███╗   ██╗██╗   ██╗    ███████╗███████╗████████╗██╗   ██╗██████╗ 
██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗    ██╔════╝████╗  ██║██║   ██║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝    █████╗  ██╔██╗ ██║██║   ██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝
██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗    ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║    ███████╗██║ ╚████║ ╚████╔╝     ███████║███████╗   ██║   ╚██████╔╝██║     
╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═══╝  ╚═══╝      ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
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

# --- 5A. FLASHING SUCCESS SECTION HEADER HELPER ---
# Uses the script 1-style final success section with bold flashing green text.
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

# --- 7A. INPUT BUFFER FLUSH HELPER ---
# Clears only a small bounded amount of already-buffered terminal input.
# Important: this never reads from stdin, because streamed scripts may use stdin for the script body.
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

# --- 8. CLEANUP FUNCTION ---
# Removes temporary files created during execution.
function cleanup() {
    local exit_code="$?"
    local file=""

    # When running as a non-root user, logging is written to a temporary user-writable file first.
    # Copy it to /var/log at exit using sudo, then remove the temporary copy.
    if [ -n "${SUDO_CMD:-}" ] && [ -n "${RUNTIME_LOG_FILE:-}" ] && [ -s "$RUNTIME_LOG_FILE" ]; then
        "$SUDO_CMD" cp "$RUNTIME_LOG_FILE" "$LOG_FILE" 2>/dev/null || true
        "$SUDO_CMD" chmod 0644 "$LOG_FILE" 2>/dev/null || true
    fi

    for file in "${TEMP_FILES[@]:-}"; do
        [ -n "$file" ] && [ -f "$file" ] && rm -f "$file" 2>/dev/null || true
    done

    for file in "${TEMP_DIRS[@]:-}"; do
        [ -n "$file" ] && [ -d "$file" ] && rm -rf "$file" 2>/dev/null || true
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
# Do not use this to print secret values.
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
# Heredoc content is not echoed to terminal, so this is safe for .env secret writing.
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

# --- 14. ROOT FILE NOT EMPTY HELPER ---
# Checks whether a root-owned file exists and has content.
function root_file_not_empty() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -s "$path"
    else
        test -s "$path"
    fi
}

# --- 15. ROOT FILE READ HELPER ---
# Reads root-owned file content for secret reuse.
# Do not call this unless assigning output into a variable.
function root_read_file() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" cat "$path"
    else
        cat "$path"
    fi
}

# --- 16. ROOT STAT MODE HELPER ---
# Returns octal file mode for verification.
function root_stat_mode() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" stat -c '%a' "$path" 2>/dev/null || true
    else
        stat -c '%a' "$path" 2>/dev/null || true
    fi
}

# --- 16A. SERVICE DIRECTORY CREATION HELPER ---
# Creates all service bind-mount directories first.
# Permission changes are intentionally done later in a separate chown stage and chmod stage.
function ensure_required_service_directories() {
    # Core project paths.
    run_cmd "creating Docker root directory" mkdir -p "$DOCKER_DIR"
    run_cmd "creating Docker appdata directory" mkdir -p "${DOCKER_DIR}/appdata"
    run_cmd "creating Docker compose directory" mkdir -p "${DOCKER_DIR}/compose"
    run_cmd "creating Docker backups directory" mkdir -p "${DOCKER_DIR}/backups"
    run_cmd "creating Docker shared directory" mkdir -p "${DOCKER_DIR}/shared"
    run_cmd "creating Docker secrets directory" mkdir -p "$DOCKER_SECRETS_DIR"

    # PostgreSQL paths.
    run_cmd "creating PostgreSQL root directory" mkdir -p "${DOCKER_DIR}/appdata/postgres"
    run_cmd "creating PostgreSQL PG18-compatible data directory" mkdir -p "${DOCKER_DIR}/appdata/postgres/pgdata"
    run_cmd "creating PostgreSQL legacy data compatibility directory" mkdir -p "${DOCKER_DIR}/appdata/postgres/data"
    run_cmd "creating PostgreSQL init directory" mkdir -p "${DOCKER_DIR}/appdata/postgres/init"

    # Redis paths.
    # The active Redis compose bind-mounts ${DOCKER_DIR}/appdata/redis to container /data.
    # The nested ${DOCKER_DIR}/appdata/redis/data path is also created and permissioned as a
    # compatibility guard so future/rerun checks and alternate compose revisions cannot fail later.
    run_cmd "creating Redis data directory" mkdir -p "${DOCKER_DIR}/appdata/redis"
    run_cmd "creating Redis nested data compatibility directory" mkdir -p "${DOCKER_DIR}/appdata/redis/data"

    # Authentik paths.
    run_cmd "creating Authentik appdata directory" mkdir -p "${DOCKER_DIR}/appdata/authentik"
    run_cmd "creating Authentik media directory" mkdir -p "${DOCKER_DIR}/appdata/authentik/media"
    run_cmd "creating Authentik custom templates directory" mkdir -p "${DOCKER_DIR}/appdata/authentik/custom-templates"
    run_cmd "creating Authentik certs directory" mkdir -p "${DOCKER_DIR}/appdata/authentik/certs"

    # App and utility paths.
    run_cmd "creating Filebrowser database directory" mkdir -p "${DOCKER_DIR}/appdata/filebrowser/database"
    run_cmd "creating Filebrowser config directory" mkdir -p "${DOCKER_DIR}/appdata/filebrowser/config"
    run_cmd "creating Postiz uploads directory" mkdir -p "${DOCKER_DIR}/appdata/postiz/uploads"

    # Admin UI bind-mount paths.
    # Create every supported admin UI path up front so Script 6.5 can switch options
    # without Docker later creating missing bind-mount directories as root.
    run_cmd "creating Dockge appdata directory" mkdir -p "${DOCKER_DIR}/appdata/dockge"
    run_cmd "creating Portainer appdata directory" mkdir -p "${DOCKER_DIR}/appdata/portainer"
    run_cmd "creating Dockhand appdata directory" mkdir -p "${DOCKER_DIR}/appdata/dockhand"
    run_cmd "creating Dockhand stacks directory" mkdir -p "${DOCKER_DIR}/appdata/dockhand/stacks"
    run_cmd "creating Komodo appdata directory" mkdir -p "${DOCKER_DIR}/appdata/komodo"
    run_cmd "creating Komodo PostgreSQL data directory" mkdir -p "${DOCKER_DIR}/appdata/komodo/postgres"
    run_cmd "creating Komodo core config directory" mkdir -p "${DOCKER_DIR}/appdata/komodo/core"
    run_cmd "creating Komodo periphery config directory" mkdir -p "${DOCKER_DIR}/appdata/komodo/periphery"

    # Traefik paths.
    run_cmd "creating Traefik config directory" mkdir -p "$TRAEFIK_DIR"
    run_cmd "creating Traefik ACME directory" mkdir -p "$TRAEFIK_ACME_DIR"
    run_cmd "creating Traefik ACME storage" touch "${TRAEFIK_ACME_DIR}/acme.json"
}

# --- 16B. SERVICE OWNERSHIP HELPER ---
# Applies ownership after all required folders exist.
function chown_required_service_directories() {
    # Base project paths.
    run_cmd "setting Docker root directory ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$DOCKER_DIR"
    run_cmd "setting Docker appdata directory ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/appdata"
    run_cmd "setting compose directory ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/compose"
    run_cmd "setting backups directory ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/backups"
    run_cmd "setting shared directory ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/shared"
    run_cmd "setting secrets directory ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "$DOCKER_SECRETS_DIR"

    # PostgreSQL official image data paths use UID/GID 999.
    run_cmd "setting PostgreSQL root ownership" chown 999:999 "${DOCKER_DIR}/appdata/postgres"
    run_cmd "setting PostgreSQL PG18-compatible data ownership" chown -R 999:999 "${DOCKER_DIR}/appdata/postgres/pgdata"
    run_cmd "setting PostgreSQL legacy data ownership" chown -R 999:999 "${DOCKER_DIR}/appdata/postgres/data"
    run_cmd "setting PostgreSQL init ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/appdata/postgres/init"

    # Redis official image data path uses UID/GID 999.
    run_cmd "setting Redis data ownership recursively" chown -R 999:999 "${DOCKER_DIR}/appdata/redis"

    # Authentik non-root bind mounts use UID/GID 1000.
    run_cmd "setting Authentik ownership recursively" chown -R 1000:1000 "${DOCKER_DIR}/appdata/authentik"

    # User-facing application/storage folders.
    run_cmd "setting Filebrowser ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/filebrowser"
    run_cmd "setting Postiz ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/postiz"

    # Admin UI bind-mount ownership.
    run_cmd "setting Dockge ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/dockge"
    run_cmd "setting Portainer ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/portainer"
    run_cmd "setting Dockhand ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/dockhand"
    run_cmd "setting Komodo root ownership" chown "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/komodo"
    run_cmd "setting Komodo core ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/komodo/core"
    run_cmd "setting Komodo periphery ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/komodo/periphery"
    run_cmd "setting Komodo PostgreSQL data ownership recursively" chown -R 999:999 "${DOCKER_DIR}/appdata/komodo/postgres"

    # Traefik config and ACME files.
    run_cmd "setting Traefik ownership recursively" chown -R "${PUID_VALUE}:${PGID_VALUE}" "$TRAEFIK_DIR"

    # .env is written before permissions are applied and must be owned by the Docker user.
    run_cmd "setting .env ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/.env"
}

# --- 16C. SERVICE MODE HELPER ---
# Applies permissions only after folder creation and ownership are complete.
function chmod_required_service_directories() {
    # Base project paths.
    run_cmd "setting Docker root directory mode" chmod 755 "$DOCKER_DIR"
    run_cmd "setting Docker appdata directory mode" chmod 755 "${DOCKER_DIR}/appdata"
    run_cmd "setting compose directory permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/compose"
    run_cmd "setting backups directory permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/backups"
    run_cmd "setting shared directory permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/shared"

    # PostgreSQL data must be private to UID/GID 999.
    # PostgreSQL 18 stores the real cluster below pgdata/18/docker when
    # ${DOCKER_DIR}/appdata/postgres/pgdata is mounted to /var/lib/postgresql.
    # Use find-based modes so every nested PG18 directory/file is corrected,
    # not only the top-level bind mount.
    run_cmd "setting PostgreSQL root directory mode" chmod 755 "${DOCKER_DIR}/appdata/postgres"
    run_cmd "setting PostgreSQL PG18-compatible data directory modes recursively" find "${DOCKER_DIR}/appdata/postgres/pgdata" -type d -exec chmod 700 {} \;
    run_cmd "setting PostgreSQL PG18-compatible data file modes recursively" find "${DOCKER_DIR}/appdata/postgres/pgdata" -type f -exec chmod 600 {} \;
    run_cmd "setting PostgreSQL legacy data directory modes recursively" find "${DOCKER_DIR}/appdata/postgres/data" -type d -exec chmod 700 {} \;
    run_cmd "setting PostgreSQL legacy data file modes recursively" find "${DOCKER_DIR}/appdata/postgres/data" -type f -exec chmod 600 {} \;
    run_cmd "setting PostgreSQL PG18-compatible data directory mode" chmod 700 "${DOCKER_DIR}/appdata/postgres/pgdata"
    run_cmd "setting PostgreSQL legacy data directory mode" chmod 700 "${DOCKER_DIR}/appdata/postgres/data"
    run_cmd "setting PostgreSQL init directory mode" chmod 755 "${DOCKER_DIR}/appdata/postgres/init"
    run_cmd "setting PostgreSQL init script mode" chmod 755 "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"

    # Redis data must be writable by UID/GID 999.
    # Use recursive directory/file modes so Redis can create temp RDB/AOF files
    # below /data after fresh deployment and after reruns.
    run_cmd "setting Redis data directory modes recursively" find "${DOCKER_DIR}/appdata/redis" -type d -exec chmod 770 {} \;
    run_cmd "setting Redis data file modes recursively" find "${DOCKER_DIR}/appdata/redis" -type f -exec chmod 660 {} \;
    run_cmd "setting Redis data directory mode" chmod 770 "${DOCKER_DIR}/appdata/redis"
    run_cmd "setting Redis nested data compatibility directory mode" chmod 770 "${DOCKER_DIR}/appdata/redis/data"

    # Authentik bind mounts must be writable by UID/GID 1000.
    run_cmd "setting Authentik permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/authentik"
    run_cmd "setting Authentik appdata directory mode" chmod 770 "${DOCKER_DIR}/appdata/authentik"
    run_cmd "setting Authentik media directory mode" chmod 770 "${DOCKER_DIR}/appdata/authentik/media"
    run_cmd "setting Authentik custom templates directory mode" chmod 770 "${DOCKER_DIR}/appdata/authentik/custom-templates"
    run_cmd "setting Authentik certs directory mode" chmod 770 "${DOCKER_DIR}/appdata/authentik/certs"

    # User-facing application/storage folders.
    run_cmd "setting Filebrowser permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/filebrowser"
    run_cmd "setting Postiz permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/postiz"

    # Admin UI bind-mount permissions.
    run_cmd "setting Dockge permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/dockge"
    run_cmd "setting Portainer permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/portainer"
    run_cmd "setting Dockhand permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/dockhand"
    run_cmd "setting Komodo root directory mode" chmod 755 "${DOCKER_DIR}/appdata/komodo"
    run_cmd "setting Komodo core permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/komodo/core"
    run_cmd "setting Komodo periphery permissions recursively" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/komodo/periphery"
    run_cmd "setting Komodo PostgreSQL data permissions recursively" chmod -R u+rwX,go-rwx "${DOCKER_DIR}/appdata/komodo/postgres"
    run_cmd "setting Komodo PostgreSQL data directory mode" chmod 700 "${DOCKER_DIR}/appdata/komodo/postgres"

    # Traefik config and ACME.
    run_cmd "setting Traefik config directory mode" chmod 750 "$TRAEFIK_DIR"
    run_cmd "setting Traefik ACME directory mode" chmod 700 "$TRAEFIK_ACME_DIR"
    run_cmd "setting Traefik static config mode" chmod 644 "$TRAEFIK_STATIC_CONFIG_FILE"
    run_cmd "setting Traefik dynamic config mode" chmod 644 "$TRAEFIK_DYNAMIC_CONFIG_FILE"
    run_cmd "setting Traefik ACME storage mode" chmod 600 "${TRAEFIK_ACME_DIR}/acme.json"

    # Secrets and .env.
    run_cmd "setting .env mode" chmod 600 "${DOCKER_DIR}/.env"
    run_cmd "setting secrets directory mode" chmod 700 "$DOCKER_SECRETS_DIR"

    if compgen -G "${DOCKER_SECRETS_DIR}/*" > /dev/null; then
        run_cmd "setting secret file modes" chmod 600 "${DOCKER_SECRETS_DIR}"/*
    fi
}

# =========================================================
#  LOGGING CONTROL
# =========================================================

# --- 17. ROOT / SUDO DETECTION ---
# Uses sudo when not root.
function detect_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    else
        SUDO_CMD="sudo"
    fi
}

# --- 18. SUDO VALIDATION ---
# Validates sudo once near the start so authentication failures happen before changes.
function validate_sudo_access() {
    if [ -n "$SUDO_CMD" ]; then
        msg_info "Validating sudo access"

        # First test the automation path created by script 3.5.
        # The Ubuntu autoinstall user is intentionally SSH-key-only and may not have a password.
        # sudo -n true confirms NOPASSWD sudo without ever prompting for a password.
        if "$SUDO_CMD" -n true >/dev/null 2>&1; then
            msg_ok "PASSWORDLESS SUDO CONFIRMED"
            return 0
        fi

        # Fallback for manually-created Ubuntu users that do have a normal sudo password.
        if "$SUDO_CMD" -v; then
            msg_ok "SUDO ACCESS CONFIRMED"
            return 0
        fi

        msg_error "Sudo authentication failed. Script cancelled."
    fi
}

# --- 19. LOGGING INITIALIZATION ---
# Starts tee logging while keeping original terminal descriptors available.
# When not root, logging goes to a temporary user-writable file first and is copied to /var/log during cleanup.
function init_logging() {
    exec 3>&1
    exec 4>&2

    if [ -n "$SUDO_CMD" ]; then
        # Avoid piping all interactive output through sudo tee.
        # Direct sudo tee can reorder /dev/tty prompts and make Enter appear inconsistent.
        RUNTIME_LOG_FILE="$(mktemp /tmp/docker-env-setup-log.XXXXXX)"
        TEMP_FILES+=("$RUNTIME_LOG_FILE")
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        RUNTIME_LOG_FILE="$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    LOGGING_ENABLED="yes"
}

# --- 20. DISABLE LOGGING HELPER ---
# Sends output directly to the terminal, bypassing tee logging.
# Used for sensitive inputs and final secret display.
function disable_logging() {
    if [ -w /dev/tty ]; then
        exec > /dev/tty 2> /dev/tty
    else
        exec >&3 2>&4
    fi

    LOGGING_ENABLED="no"
}

# --- 21. ENABLE LOGGING HELPER ---
# Re-enables tee logging after sensitive terminal-only sections are complete.
function enable_logging() {
    if [ -n "$RUNTIME_LOG_FILE" ]; then
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    LOGGING_ENABLED="yes"
}

# --- 22. CLEAR TERMINAL AND SCROLLBACK HELPER ---
# Clears visible terminal and scrollback where supported.
# This reduces the chance that displayed secrets remain visible after the user saves them.
function clear_terminal_scrollback() {
    if [ -w /dev/tty ]; then
        printf '\033[2J\033[3J\033[H' > /dev/tty
    else
        printf '\033[2J\033[3J\033[H'
    fi

    SECRET_SCREEN_CLEARED="yes"
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 23. YES/NO LABEL HELPER ---
# Converts Y/N answers to readable yes/no output.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 24. BLOCKING YES/NO HELPER ---
# Used when SPACE pauses a countdown and waits for Y/N/ENTER.
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

# --- 25. TIMED YES/NO PROMPT HELPER ---
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
                    flush_input_buffer
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    flush_input_buffer
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
                    flush_input_buffer
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    flush_input_buffer
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

# --- 26. EDITABLE INPUT LOOP HELPER ---
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

# --- 27. TIMED TEXT INPUT HELPER ---
# Shows wall-clock countdown.
# SPACE pauses with empty editable buffer.
# Any typed character pauses with that character already inside the editable buffer.
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""

    # Text/path/name/domain/number/token-style prompts are deliberately NOT timed.
    # Countdown prompts are reserved only for simple Y/n decisions.
    answer="$(editable_input_loop "$prompt" "$default" "")"
    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
    flush_input_buffer 2>/dev/null || true

    echo "$answer"
}

# --- 27A. UNTIMED MENU INPUT HELPER ---
# Reads a small menu choice without a countdown.
# Countdown prompts are reserved only for Y/n decisions.
function untimed_menu_input() {
    local prompt="$1"
    local default="$2"
    local answer=""

    while true; do
        answer="$(timed_text_input "$prompt" "$default")"
        answer="$(printf '%s' "$answer" | tr -d '\r\n' | xargs || true)"

        if [ -n "$answer" ]; then
            echo "$answer"
            return 0
        fi
    done
}


# --- 28. HIDDEN INPUT HELPER ---
# Reads sensitive input without echoing it to terminal.
# Call this while logging is disabled.
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

# --- 28A. SENSITIVE LINE INPUT HELPER ---
# Reads one sensitive pasted line directly from /dev/tty and clears the visible prompt/token line immediately after ENTER.
# The value is returned through stdout for command substitution only; prompt/token text is printed only to /dev/tty.
# Do not call flush_input_buffer here because it can consume pasted token characters.
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
        tty_print "[1A
[2K"
    done

    printf '%s' "$answer"
}

# --- 29. SECRET SAVE CONFIRMATION HELPER ---
# Waits until the user confirms they saved displayed secrets, then clears terminal/scrollback.
function wait_then_clear_secret_display() {
    echo ""
    echo -e "${RD}${CLF}Save the secrets above now.${CL}"
    echo -e "${YW}After pressing ENTER, this screen and terminal scrollback will be cleared where supported.${CL}"
    echo ""

    if [ -r /dev/tty ]; then
        read -r -p "Press ENTER after you have saved the secrets securely..." _ < /dev/tty || true
    else
        read -r -p "Press ENTER after you have saved the secrets securely..." _ || true
    fi

    clear_terminal_scrollback
}

# =========================================================
#  VALIDATION HELPERS
# =========================================================

# --- 30. USERNAME VALIDATION HELPER ---
# Validates Linux username format.
function validate_linux_username() {
    local username="$1"

    if [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 0
    fi

    return 1
}

# --- 31. ABSOLUTE PATH VALIDATION HELPER ---
# Validates an absolute path and blocks unsafe top-level paths.
function validate_absolute_path() {
    local path="$1"

    if [[ "$path" != /* ]]; then
        return 1
    fi

    case "$path" in
        "/"|"/root"|"/etc"|"/usr"|"/var"|"/home")
            return 1
            ;;
    esac

    return 0
}

# --- 32. DOMAIN VALIDATION HELPER ---
# Validates domain-style value without protocol or slash.
function validate_domain() {
    local domain="$1"

    if [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
        return 0
    fi

    return 1
}

# --- 33. EMAIL VALIDATION HELPER ---
# Simple email format validation for Cloudflare email.
function validate_email() {
    local email="$1"

    if [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
        return 0
    fi

    return 1
}

# --- 34. CLOUDFLARE ZONE ID VALIDATION HELPER ---
# Allows empty value, otherwise expects a hex-like Cloudflare zone ID.
function validate_cf_zone_id() {
    local zone_id="$1"

    if [ -z "$zone_id" ]; then
        return 0
    fi

    if [[ "$zone_id" =~ ^[A-Fa-f0-9]{16,64}$ ]]; then
        return 0
    fi

    return 1
}

# --- 35. HTPASSWD LINE VALIDATION HELPER ---
# Validates that provided htpasswd line looks like username:hash.
function validate_htpasswd_line() {
    local line="$1"

    if [[ "$line" =~ ^[^:[:space:]]+:.+ ]]; then
        return 0
    fi

    return 1
}

# --- 36. DEPENDENCY VALIDATION ---
# Validates required commands early so failures happen before partial file creation.
function validate_dependencies() {
    local required_commands=(
        awk
        cat
        chmod
        clear
        chown
        command
        cut
        date
        grep
        id
        mkdir
        mktemp
        openssl
        rm
        sed
        stat
        tee
        test
        touch
        tput
        tr
        xargs
    )

    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done

    if [ -n "$SUDO_CMD" ]; then
        command -v sudo >/dev/null 2>&1 || msg_error "sudo is required when not running as root."
    fi

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        msg_error "Either curl or wget is required to download Traefik template files."
    fi
}

# =========================================================
#  SECRET HELPERS
# =========================================================

# --- 37. SECRET GENERATOR HELPER ---
# Generates hex-only secrets. Hex avoids shell/YAML/SQL quoting problems.
function generate_secret() {
    openssl rand -hex 32 | cut -c1-48
}

# --- 38. SECRET REUSE / GENERATION HELPER ---
# Reuses existing secret files by default on reruns.
# Generates a new value only when missing or when regeneration is selected.
function get_or_generate_secret() {
    local file="$1"

    if [ "$REGENERATE_SECRETS" != "y" ] && root_file_not_empty "$file"; then
        root_read_file "$file"
    else
        generate_secret
    fi
}

# --- 39. NO-NEWLINE SECRET WRITE HELPER ---
# Writes secret files without trailing newline.
# This is intentional for file-based secrets.
function write_secret_file_no_newline() {
    local path="$1"
    local value="$2"

    if [ -n "$SUDO_CMD" ]; then
        printf '%s' "$value" | "$SUDO_CMD" tee "$path" >/dev/null
    else
        printf '%s' "$value" > "$path"
    fi
}

# --- 39A. DOWNLOAD FILE HELPER ---
# Downloads a public template file to a temporary path without printing its content.
# Uses curl when available and falls back to wget.
function download_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    else
        wget -qO "$dest" "$url"
    fi
}


# --- 39B.1. PRIMARY IPV4 DETECTION HELPER ---
# Detects the current machine's primary IPv4 address for network-context display.
function detect_primary_ipv4() {
    local ip_addr=""

    if command -v ip >/dev/null 2>&1; then
        ip_addr="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="src") {print $(i+1); exit}}' || true)"
    fi

    if [ -z "$ip_addr" ] && command -v hostname >/dev/null 2>&1; then
        ip_addr="$(hostname -I 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+\./) {print $i; exit}}' || true)"
    fi

    printf '%s' "$ip_addr"
    return 0
}

# --- 39B.2. DEFAULT GATEWAY DETECTION HELPER ---
# Detects the default gateway for display only. It is not assumed to be Proxmox.
function detect_default_gateway_ipv4() {
    local gateway=""

    if command -v ip >/dev/null 2>&1; then
        gateway="$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}' || true)"
    fi

    printf '%s' "$gateway"
    return 0
}

# --- 39B.2A. PROXMOX HTTPS PROBE HELPER ---
# Checks whether a candidate IP appears to be a Proxmox VE web UI on port 8006.
function probe_proxmox_ip() {
    local candidate_ip="$1"
    local probe_output=""

    [[ "$candidate_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

    if command -v curl >/dev/null 2>&1; then
        probe_output="$(curl -kfsS --connect-timeout 0.35 --max-time 1.2 "https://${candidate_ip}:8006/" 2>/dev/null | head -c 4096 || true)"
    elif command -v wget >/dev/null 2>&1; then
        probe_output="$(timeout 2 wget --no-check-certificate -qO- "https://${candidate_ip}:8006/" 2>/dev/null | head -c 4096 || true)"
    fi

    if grep -Eiq 'proxmox|pve|Proxmox Virtual Environment' <<< "$probe_output"; then
        printf 'https://%s:8006' "$candidate_ip"
        return 0
    fi

    return 1
}

# --- 39B.2B. LOCAL SUBNET PROXMOX DISCOVERY HELPER ---
# Attempts to find Proxmox from inside the Ubuntu VM without assuming the default gateway is Proxmox.
# As soon as a verified Proxmox host is found, this function returns immediately and skips remaining scans.
function discover_proxmox_url_from_lan() {
    local primary_ip=""
    local prefix=""
    local candidate=""
    local found_url=""
    local host=""
    local resolved_ip=""
    local octet=""

    if command -v getent >/dev/null 2>&1; then
        for host in pve2 pve proxmox proxmox.local pve2.local pve.local; do
            resolved_ip="$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}' || true)"
            if [[ "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                if found_url="$(probe_proxmox_ip "$resolved_ip")"; then
                    printf '%s' "$found_url"
                    return 0
                fi
            fi
        done
    fi

    if command -v ip >/dev/null 2>&1; then
        while IFS= read -r candidate; do
            if [[ "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                if found_url="$(probe_proxmox_ip "$candidate")"; then
                    printf '%s' "$found_url"
                    return 0
                fi
            fi
        done < <(ip -4 neigh show 2>/dev/null | awk '{print $1}' | sort -u || true)
    fi

    primary_ip="$(detect_primary_ipv4)"
    if [[ "$primary_ip" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
        prefix="${BASH_REMATCH[1]}"

        for octet in 10 11 2 3 5 20 50 100 101 102 156 200 1; do
            candidate="${prefix}.${octet}"
            [ "$candidate" = "$primary_ip" ] && continue
            if found_url="$(probe_proxmox_ip "$candidate")"; then
                printf '%s' "$found_url"
                return 0
            fi
        done

        for octet in $(seq 2 254); do
            candidate="${prefix}.${octet}"
            [ "$candidate" = "$primary_ip" ] && continue
            if found_url="$(probe_proxmox_ip "$candidate")"; then
                printf '%s' "$found_url"
                return 0
            fi
        done
    fi

    printf ''
    return 0
}

# --- 39B.3. PROXMOX URL DEFAULT DETECTION HELPER ---
# Builds the Proxmox internal URL default without hardcoding a fake static IP.
function detect_proxmox_internal_url_default() {
    local existing_env_url=""
    local discovered_url=""

    if [ -n "${PROXMOX_URL_DEFAULT:-}" ]; then
        printf '%s' "$PROXMOX_URL_DEFAULT"
        return 0
    fi

    if [ -n "${PROXMOX_URL:-}" ]; then
        printf '%s' "$PROXMOX_URL"
        return 0
    fi

    if [ -n "${DOCKER_DIR:-}" ] && [ -f "${DOCKER_DIR}/.env" ]; then
        existing_env_url="$(grep -E '^PROXMOX_URL=' "${DOCKER_DIR}/.env" 2>/dev/null | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | xargs || true)"
        if [ -n "$existing_env_url" ]; then
            printf '%s' "$existing_env_url"
            return 0
        fi
    fi

    discovered_url="$(discover_proxmox_url_from_lan || true)"
    if [ -n "$discovered_url" ]; then
        printf '%s' "$discovered_url"
        return 0
    fi

    printf ''
    return 0
}

# --- 39B. TRAEFIK TEMPLATE RENDER HELPER ---
# Replaces public-safe placeholders in downloaded Traefik templates.
# Secret values are never embedded into Traefik config files.
# Cloudflare and htpasswd credentials remain file-based Docker secrets.
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

# --- 39C. TRAEFIK DYNAMIC ROUTER BLOCK HELPER ---
# Builds dynamic file-provider routers/services for Traefik itself and optional Proxmox routing.
# The Traefik dashboard router is always generated.
# Proxmox routing is disabled by default and only generated when explicitly selected.
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
  # Only Proxmox gets insecureSkipVerify because Proxmox commonly uses a self-signed local cert.
  # Do not use global insecureSkipVerify.
  serversTransports:
    proxmoxTransport:
      insecureSkipVerify: true
EOF
}

# =========================================================
#  INITIALIZATION
# =========================================================

# --- 40. SCRIPT INITIALIZATION ---
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

# --- 41. PREVIOUS MARKER CHECK ---
# Warns if Docker ENV setup was already completed before.
function check_previous_marker() {
    local continue_yn=""

    if root_path_exists "$COMPLETED_MARKER"; then
        section "PREVIOUS DOCKER ENV SETUP MARKER DETECTED"

        echo -e "${YW}A previous Docker ENV Setup marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        root_read_file "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi
}

# =========================================================
#  INPUT COLLECTION
# =========================================================

# --- 42. START CONFIRMATION ---
# Starts Docker ENV setup after showing a clear description.
function start_confirmation() {
    local start_yn=""

    section "START"

    echo -e "${YW}This script creates Docker folders, .env and service secrets for the Home-Hosted Social Media SaaS project.${CL}"
    echo -e "${YW}Secrets are written to .env and ${DEFAULT_USER}'s Docker secrets folder.${CL}"
    echo -e "${YW}Sensitive input and final secret display bypass tee logging.${CL}"
    echo ""

    start_yn="$(timed_yes_no "Start the Docker ENV Setup Script?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    return 0
}

# --- 43. DOCKER READINESS CHECK ---
# Checks that script 5 likely ran successfully before this script.
function check_docker_readiness() {
    section "DOCKER READINESS CHECK"

    msg_info "Checking Docker readiness"

    if command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; then
        DOCKER_READY="yes"
    elif command -v docker >/dev/null 2>&1 && [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker --version >/dev/null 2>&1; then
        DOCKER_READY="yes"
    else
        DOCKER_READY="no"
    fi

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_READY="yes"
    elif command -v docker >/dev/null 2>&1 && [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_READY="yes"
    else
        DOCKER_COMPOSE_READY="no"
    fi

    msg_ok "DOCKER READINESS CHECK COMPLETE"

    echo ""
    detail_line "DOCKER CLI" "$DOCKER_READY"
    detail_line "DOCKER COMPOSE" "$DOCKER_COMPOSE_READY"

    if [ "$DOCKER_READY" != "yes" ] || [ "$DOCKER_COMPOSE_READY" != "yes" ]; then
        msg_warn "Docker or Docker Compose was not detected. Script 5 should normally run before this script."
    fi
}

# --- 44. USER AND PATH INPUTS ---
# Collects and validates Docker user, user home path and Docker project path.
function collect_user_and_path_inputs() {
    section "USER / PATH CONFIGURATION"

    while true; do
        DOCKER_USER="$(timed_text_input "Enter Linux username" "$DEFAULT_USER")"

        if validate_linux_username "$DOCKER_USER"; then
            break
        fi

        msg_warn "Invalid username. Use lowercase Linux username format, for example: dockeradmin"
    done

    if ! id "$DOCKER_USER" >/dev/null 2>&1; then
        msg_error "Linux user ${DOCKER_USER} does not exist. Run script 4 first or create the user."
    fi

    DEFAULT_USERDIR="/home/${DOCKER_USER}"
    DEFAULT_DOCKER_DIR="${DEFAULT_USERDIR}/docker"

    while true; do
        USERDIR="$(timed_text_input "Enter user home directory" "$DEFAULT_USERDIR")"

        if validate_absolute_path "$USERDIR"; then
            break
        fi

        msg_warn "Invalid user directory. Use a safe absolute path such as /home/${DOCKER_USER}"
    done

    DEFAULT_DOCKER_DIR="${USERDIR}/docker"

    while true; do
        DOCKER_DIR="$(timed_text_input "Enter Docker directory" "$DEFAULT_DOCKER_DIR")"

        if validate_absolute_path "$DOCKER_DIR"; then
            break
        fi

        msg_warn "Invalid Docker directory. Use a safe absolute path such as /home/${DOCKER_USER}/docker"
    done

    DOCKER_SECRETS_DIR="${DOCKER_DIR}/secrets"
    CF_API_TOKEN_FILE="${DOCKER_SECRETS_DIR}/cf_api_token"

    PUID_VALUE="$(id -u "$DOCKER_USER")"
    PGID_VALUE="$(id -g "$DOCKER_USER")"
    DOCKER_GID_VALUE="$(getent group docker 2>/dev/null | cut -d: -f3 || true)"

    if id -nG "$DOCKER_USER" 2>/dev/null | grep -qw docker; then
        DOCKER_USER_IN_DOCKER_GROUP="yes"
    else
        DOCKER_USER_IN_DOCKER_GROUP="no"
        msg_warn "User ${DOCKER_USER} is not currently in docker group. Script 5 should add it; reboot/login may be needed."
    fi
}

# --- 45. EXISTING SETUP DETECTION ---
# Detects existing .env, secrets folder or marker to prevent accidental secret rotation.
function detect_existing_setup() {
    local continue_existing_yn=""
    local regenerate_yn=""

    section "EXISTING SETUP CHECK"

    msg_info "Checking for existing Docker ENV setup"

    if root_path_exists "$COMPLETED_MARKER" || root_path_exists "${DOCKER_DIR}/.env" || root_path_exists "${DOCKER_SECRETS_DIR}"; then
        EXISTING_SETUP="yes"
    else
        EXISTING_SETUP="no"
    fi

    if [ "$EXISTING_SETUP" == "yes" ]; then
        msg_warn "Existing Docker ENV setup detected"
        echo ""
        echo -e "${RD}WARNING: Existing Docker ENV setup detected.${CL}"
        echo -e "${YW}Re-running can overwrite .env and service secret files.${CL}"
        echo -e "${YW}Existing secrets will be reused unless you explicitly choose to regenerate them.${CL}"
        echo ""

        continue_existing_yn="$(timed_yes_no "Continue with existing Docker ENV setup?" "n")"

        if [[ "$continue_existing_yn" =~ ^[Nn] ]]; then
            echo -e "${YW}Docker ENV setup cancelled. Existing files were left untouched.${CL}"
            exit 0
        fi

        regenerate_yn="$(timed_yes_no "Regenerate all service secrets?" "n")"

        if [[ "$regenerate_yn" =~ ^[Yy] ]]; then
            REGENERATE_SECRETS="y"
            msg_warn "Secret regeneration selected. Existing deployed containers may need rebuilding."
        else
            REGENERATE_SECRETS="n"
            msg_ok "EXISTING SECRETS WILL BE REUSED WHERE PRESENT"
        fi
    else
        REGENERATE_SECRETS="n"
        msg_ok "NO EXISTING DOCKER ENV SETUP DETECTED"
    fi
}

# --- 46. DOMAIN / CLOUDFLARE INPUTS ---
# Collects and validates timezone, domain, Cloudflare email/zone ID and token.
function collect_domain_cloudflare_inputs() {
    section "DOMAIN / CLOUDFLARE"

    TZ_VALUE="$(timed_text_input "Enter timezone" "$DEFAULT_TZ")"

    while true; do
        DOMAIN_VALUE="$(timed_text_input "Enter domain" "$DEFAULT_DOMAIN")"

        if validate_domain "$DOMAIN_VALUE"; then
            break
        fi

        msg_warn "Invalid domain. Use a bare domain such as example.com, without https:// or slashes."
    done

    while true; do
        CF_ZONE_ID_VALUE="$(timed_text_input "Enter Cloudflare Zone ID or leave empty" "$DEFAULT_CF_ZONE_ID")"

        if validate_cf_zone_id "$CF_ZONE_ID_VALUE"; then
            break
        fi

        msg_warn "Invalid Cloudflare Zone ID. Leave empty or enter the hex zone ID."
    done

    # Ask for API token before email. When token auth is used, Cloudflare email is not required.
    # This avoids cf-companion receiving email-style auth values when a scoped API token is intended.
    CF_API_TOKEN_VALUE="$(sensitive_line_input "Enter Cloudflare API Token, or leave empty")" || CF_API_TOKEN_VALUE=""
    CF_API_TOKEN_VALUE="$(printf '%s' "$CF_API_TOKEN_VALUE" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ -z "$CF_API_TOKEN_VALUE" ] && root_file_not_empty "$CF_API_TOKEN_FILE"; then
        CF_API_TOKEN_VALUE="$(root_read_file "$CF_API_TOKEN_FILE")"
        CF_AUTH_MODE="api_token_file_reuse"
        CF_EMAIL_REQUIRED="no"
        CF_API_EMAIL_VALUE=""
        msg_ok "EXISTING CLOUDFLARE API TOKEN WILL BE REUSED"
    elif [ -n "$CF_API_TOKEN_VALUE" ]; then
        CF_AUTH_MODE="api_token"
        CF_EMAIL_REQUIRED="no"
        CF_API_EMAIL_VALUE=""
        msg_ok "CLOUDFLARE API TOKEN CAPTURED"
    else
        CF_AUTH_MODE="email_or_manual"
        CF_EMAIL_REQUIRED="yes"
        msg_warn "Cloudflare API token left empty. Email can be entered for legacy/manual Cloudflare auth, but API token is recommended."
        while true; do
            CF_API_EMAIL_VALUE="$(timed_text_input "Enter Cloudflare API Email" "$DEFAULT_CF_API_EMAIL")"

            if validate_email "$CF_API_EMAIL_VALUE"; then
                break
            fi

            msg_warn "Invalid email format."
        done
    fi

    return 0
}


# --- 46A. TRAEFIK CONFIG INPUTS ---
# Collects non-secret Traefik values used to render template config files.
# Cloudflare token stays in ${CF_API_TOKEN_FILE}; it is never embedded into Traefik YAML.
function collect_traefik_inputs() {
    local default_traefik_host="traefik.${DOMAIN_VALUE}"
    local proxmox_yn=""
    local default_proxmox_host="proxmox.${DOMAIN_VALUE}"
    local default_proxmox_url=""
    local detected_primary_ip=""
    local detected_gateway_ip=""

    detected_primary_ip="$(detect_primary_ipv4)"
    detected_gateway_ip="$(detect_default_gateway_ipv4)"

    tty_println " ${BL}━━━━━▶${CL} ${YW}Discovering Proxmox host on local network...${CL}"
    default_proxmox_url="$(detect_proxmox_internal_url_default)"
    if [ -n "$default_proxmox_url" ]; then
        tty_println " ${CM} ${GN}PROXMOX HOST DISCOVERED:${CL} ${default_proxmox_url}"
    else
        tty_println " ${WARN} ${YW}PROXMOX HOST AUTO-DISCOVERY DID NOT FIND A VERIFIED HOST${CL}"
    fi

    section "TRAEFIK CONFIG"

    while true; do
        TRAEFIK_DASHBOARD_HOST="$(timed_text_input "Enter Traefik dashboard host" "$default_traefik_host")"

        if validate_domain "$TRAEFIK_DASHBOARD_HOST"; then
            break
        fi

        msg_warn "Invalid Traefik host. Use a bare hostname such as traefik.${DOMAIN_VALUE}."
    done

    echo ""
    [ -n "$detected_primary_ip" ] && detail_line "Detected current system IPv4" "$detected_primary_ip"
    [ -n "$detected_gateway_ip" ] && detail_line "Detected default gateway (not assumed Proxmox)" "$detected_gateway_ip"
    if [ -n "$default_proxmox_url" ]; then
        detail_line "Suggested Proxmox URL" "$default_proxmox_url"
    else
        msg_warn "No Proxmox URL could be auto-detected. You will need to type it if enabling the route."
    fi
    echo ""

    proxmox_yn="$(timed_yes_no "Create optional Proxmox route in Traefik dynamic config?" "y")"

    if [[ "$proxmox_yn" =~ ^[Yy] ]]; then
        PROXMOX_ROUTE_ENABLED="y"

        while true; do
            PROXMOX_HOST="$(timed_text_input "Enter Proxmox hostname" "$default_proxmox_host")"

            if validate_domain "$PROXMOX_HOST"; then
                break
            fi

            msg_warn "Invalid Proxmox hostname. Use a bare hostname such as proxmox.${DOMAIN_VALUE}."
        done

        PROXMOX_URL="$(timed_text_input "Enter Proxmox internal URL" "$default_proxmox_url")"
        msg_ok "PROXMOX ROUTE WILL BE CREATED"
    else
        PROXMOX_ROUTE_ENABLED="n"
        PROXMOX_HOST=""
        PROXMOX_URL=""
        msg_ok "PROXMOX ROUTE SKIPPED"
    fi

    TRAEFIK_DIR="${DOCKER_DIR}/appdata/traefik"
    TRAEFIK_ACME_DIR="${TRAEFIK_DIR}/acme"
    TRAEFIK_STATIC_CONFIG_FILE="${TRAEFIK_DIR}/traefik.yml"
    TRAEFIK_DYNAMIC_CONFIG_FILE="${TRAEFIK_DIR}/dynamic-config.yml"

    return 0
}


# --- 47. HTPASSWD OPTIONAL INPUT ---
# Handles optional Traefik basic-auth credentials without logging sensitive values.
# If username/password is entered, final output shows only the generated hashed htpasswd line.
# If full htpasswd line is provided, final output does not show the provided hash.
function collect_htpasswd_inputs() {
    local has_htpasswd_yn=""
    local create_htpasswd_yn=""

    section "OPTIONAL HTPASSWD"

    echo -e "${BL}Optional Traefik basic-auth htpasswd setup.${CL}"
    echo -e "${YW}Not required if you use Authentik, Authelia, or a similar SSO/auth gateway.${CL}"
    echo -e "${YW}If a password is entered, this script will generate a SHA-512 htpasswd hash.${CL}"
    echo -e "${YW}If a full htpasswd line is provided, it will be saved but not displayed in final output.${CL}"
    echo ""

    has_htpasswd_yn="$(timed_yes_no "Do you already have a hashed htpasswd line?" "n")"

    if [[ "$has_htpasswd_yn" =~ ^[Yy] ]]; then
        disable_logging
        HTPASSWD_LINE_VALUE="$(sensitive_line_input "Paste full htpasswd line username:hash")"
        enable_logging

        HTPASSWD_LINE_VALUE="$(printf '%s' "$HTPASSWD_LINE_VALUE" | tr -d '\r\n')"

        if [ -n "$HTPASSWD_LINE_VALUE" ]; then
            if validate_htpasswd_line "$HTPASSWD_LINE_VALUE"; then
                HTPASSWD_MODE="provided"
            else
                HTPASSWD_LINE_VALUE=""
                HTPASSWD_MODE="empty"
                msg_warn "Provided htpasswd line did not look valid. Empty placeholder will be used unless an existing file is present."
            fi
        fi
    else
        create_htpasswd_yn="$(timed_yes_no "Create htpasswd entry now?" "n")"

        if [[ "$create_htpasswd_yn" =~ ^[Yy] ]]; then
            HTPASSWD_USER_VALUE="$(timed_text_input "Enter htpasswd username" "$DEFAULT_HTPASSWD_USER")"

            disable_logging
            HTPASSWD_PASSWORD_VALUE="$(hidden_input "Enter htpasswd password")"
            enable_logging

            if [ -n "$HTPASSWD_PASSWORD_VALUE" ]; then
                HTPASSWD_HASH_VALUE="$(openssl passwd -6 "$HTPASSWD_PASSWORD_VALUE")"
                HTPASSWD_LINE_VALUE="${HTPASSWD_USER_VALUE}:${HTPASSWD_HASH_VALUE}"
                HTPASSWD_PASSWORD_VALUE=""
                HTPASSWD_MODE="generated"
            else
                HTPASSWD_MODE="empty"
                msg_warn "htpasswd password was empty. Empty placeholder will be used unless an existing file is present."
            fi
        else
            HTPASSWD_MODE="empty"
        fi
    fi
}

# --- 47AA. ADMIN UI DETAIL HELPER ---
# Derives the formal admin UI display name, hostname and URL from the selected admin UI key.
function set_admin_ui_details() {
    case "$ADMIN_UI" in
        dockge)
            ADMIN_UI_DISPLAY_NAME="Dockge"
            ADMIN_UI_HOST="dockge.${DOMAIN_VALUE}"
            ;;
        portainer|portainer-ce)
            ADMIN_UI="portainer"
            ADMIN_UI_DISPLAY_NAME="Portainer"
            ADMIN_UI_HOST="portainer.${DOMAIN_VALUE}"
            ;;
        komodo)
            ADMIN_UI_DISPLAY_NAME="Komodo"
            ADMIN_UI_HOST="komodo.${DOMAIN_VALUE}"
            ;;
        dockhand)
            ADMIN_UI_DISPLAY_NAME="Dockhand"
            ADMIN_UI_HOST="dockhand.${DOMAIN_VALUE}"
            ;;
        *)
            ADMIN_UI="dockge"
            ADMIN_UI_DISPLAY_NAME="Dockge"
            ADMIN_UI_HOST="dockge.${DOMAIN_VALUE}"
            ;;
    esac

    ADMIN_UI_URL="https://${ADMIN_UI_HOST}"
}

# --- 47A. ADMIN UI SELECTION ---
# Selects the container management interface once during configuration generation.
function collect_admin_ui_selection() {
    local choice=""
    local default_choice="1"

    section "ADMIN UI SELECTION"

    echo -e "${BL}Choose the Docker administration interface for this deployment:${CL}"
    echo "1) Dockge - lightweight Compose-focused admin UI"
    echo "2) Portainer CE - full Docker management UI"
    echo "3) Komodo - Git/server-oriented deployment UI"
    echo "4) Dockhand - modern multi-host Docker management UI"
    echo ""

    while true; do
        choice="$(untimed_menu_input "Select admin UI option [1-4]" "$default_choice")"

        case "$choice" in
            1|dockge|Dockge)
                ADMIN_UI="dockge"
                break
                ;;
            2|portainer|Portainer|portainer-ce|PortainerCE)
                ADMIN_UI="portainer"
                break
                ;;
            3|komodo|Komodo)
                ADMIN_UI="komodo"
                break
                ;;
            4|dockhand|Dockhand)
                ADMIN_UI="dockhand"
                break
                ;;
            *)
                msg_warn "Invalid admin UI selection. Choose 1, 2, 3, or 4."
                continue
                ;;
        esac

        break
    done

    set_admin_ui_details

    msg_ok "ADMIN UI SELECTED: ${ADMIN_UI_DISPLAY_NAME}"
    detail_line "Admin UI" "$ADMIN_UI_DISPLAY_NAME"
    detail_line "Admin UI host" "$ADMIN_UI_HOST"
    detail_line "Admin UI URL" "$ADMIN_UI_URL"

    return 0
}

# --- 47B. AUTHENTIK BOOTSTRAP INPUTS ---
# Collects Authentik external URL and bootstrap admin values before .env is written.
function collect_authentik_inputs() {
    local password_choice=""
    local token_choice=""
    local api_choice=""
    local default_admin_email=""

    section "AUTHENTIK BOOTSTRAP"

    AUTHENTIK_HOST_VALUE="$(timed_text_input "Enter Authentik external URL" "https://auth.${DOMAIN_VALUE}")"
    AUTHENTIK_HOST_BROWSER_VALUE="$(timed_text_input "Enter Authentik browser URL" "$AUTHENTIK_HOST_VALUE")"

    while true; do
        if [ -n "$CF_API_EMAIL_VALUE" ]; then
            default_admin_email="$CF_API_EMAIL_VALUE"
        else
            default_admin_email="admin@${DOMAIN_VALUE}"
        fi

        AUTHENTIK_BOOTSTRAP_EMAIL_VALUE="$(timed_text_input "Enter Authentik bootstrap admin email" "$default_admin_email")"

        if validate_email "$AUTHENTIK_BOOTSTRAP_EMAIL_VALUE"; then
            break
        fi

        msg_warn "Invalid email format."
    done

    echo ""
    echo -e "${YW}Choose how Script 6 should set the first Authentik bootstrap admin password.${CL}"
    echo -e "${YW}This is a menu choice, not the password prompt. Type 2 if you want to paste your own password.${CL}"
    echo -e "${BL}1) Auto-generate password ${GN}(recommended/default)${CL}"
    echo -e "${BL}2) Enter custom password${CL}"
    echo ""

    while true; do
        password_choice="$(untimed_menu_input "Select Authentik bootstrap password option [1-2]" "1")"
        case "$password_choice" in
            1|auto|Auto|generate|generated)
                AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE="$(generate_secret)"
                msg_ok "AUTHENTIK BOOTSTRAP PASSWORD WILL BE GENERATED"
                break
                ;;
            2|custom|Custom|manual|Manual)
                AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE="$(sensitive_line_input "Enter Authentik bootstrap admin password")" || AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE=""
                AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE="$(printf '%s' "$AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE" | tr -d '\r\n')"
                [ -n "$AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE" ] || msg_error "Authentik bootstrap password cannot be empty."
                msg_ok "AUTHENTIK BOOTSTRAP PASSWORD CAPTURED"
                break
                ;;
            *)
                msg_warn "Invalid choice. Type 1 to auto-generate or 2 to enter a custom password. Do not paste the password at this menu prompt."
                ;;
        esac
    done

    echo ""
    echo -e "${YW}Choose how Script 6 should set the Authentik bootstrap token.${CL}"
    echo -e "${YW}Fresh Authentik creates an akadmin API Access token from AUTHENTIK_BOOTSTRAP_TOKEN.${CL}"
    echo -e "${BL}1) Auto-generate bootstrap token ${GN}(recommended/default)${CL}"
    echo -e "${BL}2) Enter custom bootstrap token${CL}"
    echo ""

    while true; do
        token_choice="$(untimed_menu_input "Select Authentik bootstrap token option [1-2]" "1")"
        case "$token_choice" in
            1|auto|Auto|generate|generated)
                AUTHENTIK_BOOTSTRAP_TOKEN_VALUE="$(generate_secret)"
                msg_ok "AUTHENTIK BOOTSTRAP TOKEN WILL BE GENERATED"
                break
                ;;
            2|custom|Custom|manual|Manual)
                AUTHENTIK_BOOTSTRAP_TOKEN_VALUE="$(sensitive_line_input "Enter Authentik bootstrap token")" || AUTHENTIK_BOOTSTRAP_TOKEN_VALUE=""
                AUTHENTIK_BOOTSTRAP_TOKEN_VALUE="$(printf '%s' "$AUTHENTIK_BOOTSTRAP_TOKEN_VALUE" | tr -d '\r\n')"
                [ -n "$AUTHENTIK_BOOTSTRAP_TOKEN_VALUE" ] || msg_error "Authentik bootstrap token cannot be empty."
                msg_ok "AUTHENTIK BOOTSTRAP TOKEN CAPTURED"
                break
                ;;
            *)
                msg_warn "Invalid choice. Type 1 to auto-generate or 2 to enter a custom bootstrap token."
                ;;
        esac
    done

    echo ""
    echo -e "${YW}Script 6.5 will configure Authentik provider/application/outpost setup during deployment.${CL}"
    echo -e "${YW}Fresh Authentik creates an akadmin API Access token from AUTHENTIK_BOOTSTRAP_TOKEN.${CL}"
    echo -e "${YW}Default: reuse the bootstrap token automatically. Paste a different API token only for an existing Authentik install.${CL}"
    echo -e "${BL}1) Use AUTHENTIK_BOOTSTRAP_TOKEN as API token ${GN}(recommended/default)${CL}"
    echo -e "${BL}2) Paste existing Authentik API token${CL}"
    echo -e "${BL}3) Skip API automation for now${CL}"
    echo ""

    api_choice="$(untimed_menu_input "Select Authentik API token option [1-3]" "1")"
    case "$api_choice" in
        2)
            AUTHENTIK_API_TOKEN_VALUE="$(sensitive_line_input "Paste existing Authentik API token")" || AUTHENTIK_API_TOKEN_VALUE=""
            AUTHENTIK_API_TOKEN_VALUE="$(printf '%s' "$AUTHENTIK_API_TOKEN_VALUE" | tr -d '\r\n')"
            if [ -n "$AUTHENTIK_API_TOKEN_VALUE" ]; then
                AUTHENTIK_API_TOKEN_MODE="provided"
                msg_ok "AUTHENTIK API TOKEN CAPTURED"
            else
                AUTHENTIK_API_TOKEN_MODE="bootstrap"
                AUTHENTIK_API_TOKEN_VALUE="$AUTHENTIK_BOOTSTRAP_TOKEN_VALUE"
                msg_warn "No API token pasted. Script 6.5 will try AUTHENTIK_BOOTSTRAP_TOKEN."
            fi
            ;;
        3)
            AUTHENTIK_API_TOKEN_MODE="skip"
            AUTHENTIK_API_TOKEN_VALUE=""
            msg_ok "AUTHENTIK API AUTOMATION SKIPPED FOR NOW"
            ;;
        *)
            AUTHENTIK_API_TOKEN_MODE="bootstrap"
            AUTHENTIK_API_TOKEN_VALUE="$AUTHENTIK_BOOTSTRAP_TOKEN_VALUE"
            msg_ok "AUTHENTIK API TOKEN WILL REUSE BOOTSTRAP TOKEN"
            ;;
    esac

    return 0
}

# --- 47C. READY TO APPLY SUMMARY ---
# Shows every collected setting before directories, secrets, .env, templates or permissions are written.
function show_ready_summary_and_confirm() {
    local apply_yn=""

    section "READY TO APPLY"

    echo -e "${YW}All questions have been collected. No Docker ENV files, secrets or templates have been written yet.${CL}"
    echo ""
    detail_line "Docker user" "$DOCKER_USER"
    detail_line "User directory" "$USERDIR"
    detail_line "Docker directory" "$DOCKER_DIR"
    detail_line "Secrets directory" "$DOCKER_SECRETS_DIR"
    detail_line "PUID / PGID" "${PUID_VALUE} / ${PGID_VALUE}"
    detail_line "Timezone" "$TZ_VALUE"
    detail_line "Domain" "$DOMAIN_VALUE"
    detail_line "Cloudflare auth mode" "$CF_AUTH_MODE"
    detail_line "Cloudflare email" "${CF_API_EMAIL_VALUE:-not used with token auth}"
    detail_line "Cloudflare zone ID" "${CF_ZONE_ID_VALUE:-not set}"
    detail_line "Admin UI" "$ADMIN_UI_DISPLAY_NAME"
    detail_line "Admin UI host" "$ADMIN_UI_HOST"
    detail_line "Authentik host" "$AUTHENTIK_HOST_VALUE"
    detail_line "Authentik bootstrap email" "$AUTHENTIK_BOOTSTRAP_EMAIL_VALUE"
    detail_line "Traefik dashboard host" "$TRAEFIK_DASHBOARD_HOST"
    detail_line "Proxmox route enabled" "$PROXMOX_ROUTE_ENABLED"
    if [ "$PROXMOX_ROUTE_ENABLED" == "y" ]; then
        detail_line "Proxmox hostname" "$PROXMOX_HOST"
        detail_line "Proxmox internal URL" "$PROXMOX_URL"
    fi
    detail_line "Regenerate secrets" "$(yes_no_label "$REGENERATE_SECRETS")"
    echo ""
    echo -e "${RD}${CLF}After confirmation, the script will create/update folders, .env, secrets and templates.${CL}"
    echo ""

    apply_yn="$(timed_yes_no "Apply this Docker ENV setup plan now?" "y")"

    if [[ "$apply_yn" =~ ^[Nn] ]]; then
        echo -e "${YW}Docker ENV setup cancelled. No Docker ENV/system-changing actions were applied.${CL}"
        exit 0
    fi

    return 0
}

# =========================================================
#  FILE / SECRET CREATION
# =========================================================

# --- 48. DOCKER DIRECTORY CREATION ---
# Creates project folders for compose, appdata, backups, shared files and secrets.
function create_docker_directories() {
    section "DOCKER FOLDER STRUCTURE"

    msg_info "Creating Docker folder structure"
    ensure_required_service_directories
    msg_ok "DOCKER FOLDERS CREATED"
}


# --- 49. SECRET GENERATION / REUSE ---
# Generates service secrets on first run. On reruns, reuses existing secret files unless regeneration was explicitly selected.
function generate_or_reuse_secrets() {
    section "SECRET GENERATION / REUSE"

    msg_info "Generating or reusing secrets"

    POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/postgres_password")"
    REDIS_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/redis_password")"
    AUTHENTIK_SECRET_KEY="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/authentik_secret_key")"
    AUTHENTIK_POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/authentik_postgres_password")"
    POSTIZ_POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/postiz_postgres_password")"
    POSTIZ_JWT_SECRET="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/postiz_jwt_secret")"
    TEMPORAL_POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/temporal_postgres_password")"
    KOMODO_DB_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/komodo_db_password")"
    KOMODO_PASSKEY="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/komodo_passkey")"
    KOMODO_JWT_SECRET="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/komodo_jwt_secret")"
    KOMODO_WEBHOOK_SECRET="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/komodo_webhook_secret")"

    msg_ok "SECRETS GENERATED / REUSED"
}

# --- 50. POSTGRES INIT SCRIPT CREATION ---
# Creates unattended PostgreSQL init script for app databases on first PostgreSQL container startup.
function create_postgres_init_script() {
    section "POSTGRES INIT SCRIPT"

    msg_info "Writing PostgreSQL unattended app database init script"

    write_root_file "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

create_user_and_db() {
    local app_user="$1"
    local app_db="$2"
    local app_password="$3"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_catalog.pg_roles
        WHERE rolname = '${app_user}'
    ) THEN
        CREATE USER ${app_user} WITH PASSWORD '${app_password}';
    ELSE
        ALTER USER ${app_user} WITH PASSWORD '${app_password}';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${app_db} OWNER ${app_user}'
WHERE NOT EXISTS (
    SELECT FROM pg_database
    WHERE datname = '${app_db}'
)\gexec

GRANT ALL PRIVILEGES ON DATABASE ${app_db} TO ${app_user};
SQL
}

: "${AUTHENTIK_POSTGRES_PASSWORD:?AUTHENTIK_POSTGRES_PASSWORD is required}"
: "${POSTIZ_POSTGRES_PASSWORD:?POSTIZ_POSTGRES_PASSWORD is required}"
: "${TEMPORAL_POSTGRES_PASSWORD:?TEMPORAL_POSTGRES_PASSWORD is required}"

create_user_and_db "authentik" "authentik" "$AUTHENTIK_POSTGRES_PASSWORD"
create_user_and_db "postiz" "postiz" "$POSTIZ_POSTGRES_PASSWORD"
create_user_and_db "temporal" "temporal" "$TEMPORAL_POSTGRES_PASSWORD"
create_user_and_db "temporal" "temporal_visibility" "$TEMPORAL_POSTGRES_PASSWORD"
EOF

    run_cmd "making PostgreSQL init script executable" chmod 755 "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"

    msg_ok "POSTGRES INIT SCRIPT CREATED"
}


# --- 50A. TRAEFIK CONFIG TEMPLATE RENDERING ---
# Downloads public Traefik template files from GitHub and renders local config files.
# Only non-secret placeholders are replaced. Cloudflare token remains file-based via Docker secret.
function create_traefik_config_files() {
    local static_template=""
    local dynamic_template=""

    section "TRAEFIK CONFIG FILES"

    msg_info "Preparing temporary Traefik template workspace"
    TRAEFIK_TEMPLATE_TMP_DIR="$(mktemp -d /tmp/traefik-template-render.XXXXXX)"
    TEMP_DIRS+=("$TRAEFIK_TEMPLATE_TMP_DIR")
    static_template="${TRAEFIK_TEMPLATE_TMP_DIR}/traefik.yml.template"
    dynamic_template="${TRAEFIK_TEMPLATE_TMP_DIR}/dynamic-config.yml.template"
    msg_ok "TRAEFIK TEMPLATE WORKSPACE READY"

    msg_info "Downloading Traefik static template"
    download_file "$TRAEFIK_STATIC_TEMPLATE_URL" "$static_template" || msg_error "Failed to download Traefik template: ${TRAEFIK_STATIC_TEMPLATE_URL}"
    msg_ok "TRAEFIK STATIC TEMPLATE DOWNLOADED"

    msg_info "Downloading Traefik dynamic template"
    download_file "$TRAEFIK_DYNAMIC_TEMPLATE_URL" "$dynamic_template" || msg_error "Failed to download Traefik template: ${TRAEFIK_DYNAMIC_TEMPLATE_URL}"
    msg_ok "TRAEFIK DYNAMIC TEMPLATE DOWNLOADED"

    msg_info "Rendering Traefik static config"
    render_traefik_template "$static_template" "$TRAEFIK_STATIC_CONFIG_FILE"
    msg_ok "TRAEFIK STATIC CONFIG CREATED"

    msg_info "Rendering Traefik dynamic config"
    render_traefik_template "$dynamic_template" "$TRAEFIK_DYNAMIC_CONFIG_FILE"
    msg_ok "TRAEFIK DYNAMIC CONFIG CREATED"

    msg_info "Securing Traefik ACME storage"
    run_cmd "setting Traefik ACME storage permissions" chmod 600 "${TRAEFIK_ACME_DIR}/acme.json"
    msg_ok "TRAEFIK ACME STORAGE READY"
}

# --- 50B. TRAEFIK CONFIG POST-RENDER VERIFICATION ---
# Verifies Traefik files immediately after rendering so Script 6 fails here, not later in Script 6.5.
function verify_traefik_config_files_created() {
    section "TRAEFIK CONFIG VERIFICATION"

    [ -f "$TRAEFIK_STATIC_CONFIG_FILE" ] || msg_error "Traefik static config was not created: ${TRAEFIK_STATIC_CONFIG_FILE}"
    [ -f "$TRAEFIK_DYNAMIC_CONFIG_FILE" ] || msg_error "Traefik dynamic config was not created: ${TRAEFIK_DYNAMIC_CONFIG_FILE}"
    [ -f "${TRAEFIK_ACME_DIR}/acme.json" ] || msg_error "Traefik ACME storage was not created: ${TRAEFIK_ACME_DIR}/acme.json"

    if grep -R '{{[^}]*}}' "$TRAEFIK_STATIC_CONFIG_FILE" "$TRAEFIK_DYNAMIC_CONFIG_FILE" >/dev/null 2>&1; then
        msg_error "Unrendered {{PLACEHOLDER}} values remain in Traefik config files."
    fi

    if ! grep -q "main: \"${DOMAIN_VALUE}\"" "$TRAEFIK_STATIC_CONFIG_FILE" 2>/dev/null && ! grep -q "main: ${DOMAIN_VALUE}" "$TRAEFIK_STATIC_CONFIG_FILE" 2>/dev/null; then
        msg_error "Traefik static config does not contain the base wildcard certificate domain."
    fi

    if ! grep -q "\*.${DOMAIN_VALUE}" "$TRAEFIK_STATIC_CONFIG_FILE" 2>/dev/null; then
        msg_error "Traefik static config does not contain the wildcard SAN for *.${DOMAIN_VALUE}."
    fi

    if grep -q 'certResolver: cloudflare' "$TRAEFIK_DYNAMIC_CONFIG_FILE" 2>/dev/null; then
        msg_error "Traefik dynamic config still contains per-router certResolver entries. Keep wildcard issuance centralized in traefik.yml."
    fi

    msg_ok "TRAEFIK CONFIG FILES VERIFIED"
}


# --- 51. SECRET FILE CREATION ---
# Writes generated/reused secrets to individual secret files.
function write_secret_files() {
    section "SECRET FILES"

    msg_info "Writing secret files"

    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/postgres_password" "$POSTGRES_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/redis_password" "$REDIS_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/authentik_secret_key" "$AUTHENTIK_SECRET_KEY"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/authentik_postgres_password" "$AUTHENTIK_POSTGRES_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/postiz_postgres_password" "$POSTIZ_POSTGRES_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/postiz_jwt_secret" "$POSTIZ_JWT_SECRET"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/temporal_postgres_password" "$TEMPORAL_POSTGRES_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/komodo_db_password" "$KOMODO_DB_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/komodo_passkey" "$KOMODO_PASSKEY"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/komodo_jwt_secret" "$KOMODO_JWT_SECRET"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/komodo_webhook_secret" "$KOMODO_WEBHOOK_SECRET"

    if [ -n "$CF_API_TOKEN_VALUE" ]; then
        write_secret_file_no_newline "$CF_API_TOKEN_FILE" "$CF_API_TOKEN_VALUE"
    elif root_file_not_empty "$CF_API_TOKEN_FILE"; then
        msg_ok "EXISTING CLOUDFLARE TOKEN FILE PRESERVED"
    else
        run_cmd "creating empty Cloudflare API token placeholder" touch "$CF_API_TOKEN_FILE"
    fi

    if [ -n "$HTPASSWD_LINE_VALUE" ]; then
        write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/htpasswd" "$HTPASSWD_LINE_VALUE"
    elif root_file_not_empty "${DOCKER_SECRETS_DIR}/htpasswd"; then
        msg_ok "EXISTING HTPASSWD FILE PRESERVED"
    else
        run_cmd "creating empty htpasswd placeholder" touch "${DOCKER_SECRETS_DIR}/htpasswd"
    fi

    msg_ok "SECRET FILES WRITTEN"
}

# --- 52. ENV FILE CREATION ---
# Creates /updates Docker .env used by docker compose CLI and Portainer stacks.
# This file contains secrets and is locked down to 600 later.
function write_env_file() {
    section "DOCKER .ENV"

    msg_info "Creating Docker .env file"

    # Defensive compatibility alias for any legacy/template line that still
    # references the old DOMAIN variable name. Script 6's collected canonical
    # value is DOMAIN_VALUE, but set -u turns stale expansion into a hard failure
    # during heredoc rendering.
    local DOMAIN="${DOMAIN_VALUE}"

    # Fail with a clear message before the heredoc if any required collected
    # value is unexpectedly empty/unset. This avoids cryptic set -u messages.
    : "${DOMAIN_VALUE:?DOMAIN_VALUE is required before writing .env}"
    : "${DOCKER_DIR:?DOCKER_DIR is required before writing .env}"
    : "${DOCKER_SECRETS_DIR:?DOCKER_SECRETS_DIR is required before writing .env}"
    : "${USERDIR:?USERDIR is required before writing .env}"

    write_root_file "${DOCKER_DIR}/.env" <<EOF
# =========================================================
#  Project: Home-Hosted Social Media SaaS
# =========================================================

# --- Core paths ---
DOCKER_DIR="${DOCKER_DIR}"
DOCKER_SECRETS_DIR="${DOCKER_SECRETS_DIR}"
USERDIR="${USERDIR}"

# --- Linux user/container IDs ---
PUID="${PUID_VALUE}"
PGID="${PGID_VALUE}"
DOCKER_GID="${DOCKER_GID_VALUE}"

# --- Localisation ---
TZ="${TZ_VALUE}"

# --- Domain / Cloudflare ---
DOMAIN="${DOMAIN_VALUE}"
CF_AUTH_MODE="${CF_AUTH_MODE}"
CF_EMAIL_REQUIRED="${CF_EMAIL_REQUIRED}"
CF_API_EMAIL="${CF_API_EMAIL_VALUE}"
CF_ZONE_ID="${CF_ZONE_ID_VALUE}"
CF_API_TOKEN_FILE="${CF_API_TOKEN_FILE}"
CF_TOKEN_FILE="${CF_API_TOKEN_FILE}"
CF_TOKEN_SECRET_NAME="cf_token"
PROXMOX_ROUTE_ENABLED="${PROXMOX_ROUTE_ENABLED}"
PROXMOX_HOST="${PROXMOX_HOST}"
PROXMOX_URL="${PROXMOX_URL}"
TRAEFIK_DASHBOARD_HOST="${TRAEFIK_DASHBOARD_HOST}"
TRAEFIK_STATIC_CONFIG_FILE="${TRAEFIK_STATIC_CONFIG_FILE}"
TRAEFIK_DYNAMIC_CONFIG_FILE="${TRAEFIK_DYNAMIC_CONFIG_FILE}"
TRAEFIK_ACME_STORAGE="${TRAEFIK_ACME_DIR}/acme.json"

# --- Admin UI selection ---
ADMIN_UI="${ADMIN_UI}"
ADMIN_UI_DISPLAY_NAME="${ADMIN_UI_DISPLAY_NAME}"
ADMIN_UI_HOST="${ADMIN_UI_HOST}"
ADMIN_UI_URL="${ADMIN_UI_URL}"

# --- PostgreSQL root/admin password ---
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

# --- Redis ---
REDIS_PASSWORD="${REDIS_PASSWORD}"

# --- Authentik ---
AUTHENTIK_HOST="${AUTHENTIK_HOST_VALUE}"
AUTHENTIK_HOST_BROWSER="${AUTHENTIK_HOST_BROWSER_VALUE}"
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY}"
AUTHENTIK_POSTGRES_PASSWORD="${AUTHENTIK_POSTGRES_PASSWORD}"
AUTHENTIK_BOOTSTRAP_EMAIL="${AUTHENTIK_BOOTSTRAP_EMAIL_VALUE}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE}"
AUTHENTIK_BOOTSTRAP_TOKEN="${AUTHENTIK_BOOTSTRAP_TOKEN_VALUE}"
AUTHENTIK_API_TOKEN_MODE="${AUTHENTIK_API_TOKEN_MODE}"
AUTHENTIK_API_TOKEN="${AUTHENTIK_API_TOKEN_VALUE}"

# --- Authentik runtime safety / optional SMTP ---
# Disable update-check notifications unless SMTP is deliberately configured later.
# This prevents a healthy fresh Authentik worker from retrying failed update-notification emails.
AUTHENTIK_DISABLE_UPDATE_CHECK="true"
AUTHENTIK_DISABLE_STARTUP_ANALYTICS="true"
AUTHENTIK_ERROR_REPORTING__ENABLED="false"
AUTHENTIK_EMAIL__HOST=""
AUTHENTIK_EMAIL__PORT="587"
AUTHENTIK_EMAIL__USERNAME=""
AUTHENTIK_EMAIL__PASSWORD=""
AUTHENTIK_EMAIL__USE_TLS="true"
AUTHENTIK_EMAIL__USE_SSL="false"
AUTHENTIK_EMAIL__TIMEOUT="30"
AUTHENTIK_EMAIL__FROM="authentik@${DOMAIN_VALUE}"

# --- Postiz ---
POSTIZ_POSTGRES_PASSWORD="${POSTIZ_POSTGRES_PASSWORD}"
POSTIZ_JWT_SECRET="${POSTIZ_JWT_SECRET}"

# --- Temporal ---
TEMPORAL_POSTGRES_PASSWORD="${TEMPORAL_POSTGRES_PASSWORD}"
TEMPORAL_DBNAME="temporal"
TEMPORAL_VISIBILITY_DBNAME="temporal_visibility"

# --- Komodo ---
KOMODO_DB_PASSWORD="${KOMODO_DB_PASSWORD}"
KOMODO_PASSKEY="${KOMODO_PASSKEY}"
KOMODO_JWT_SECRET="${KOMODO_JWT_SECRET}"
KOMODO_WEBHOOK_SECRET="${KOMODO_WEBHOOK_SECRET}"

# --- Image defaults / development mode ---
# These intentionally default to latest during active testing.
# Script 7 can generate a lock report after a successful deployment.
SOCKET_PROXY_IMAGE="tecnativa/docker-socket-proxy:latest"
DOCKGE_IMAGE="louislam/dockge:latest"
DOCKHAND_IMAGE="fnsys/dockhand:latest"
KOMODO_POSTGRES_IMAGE="postgres:latest"
KOMODO_FERRETDB_IMAGE="ghcr.io/ferretdb/ferretdb:latest"
KOMODO_CORE_IMAGE="ghcr.io/moghtech/komodo-core:latest"
KOMODO_PERIPHERY_IMAGE="ghcr.io/moghtech/komodo-periphery:latest"
PORTAINER_IMAGE="portainer/portainer-ce:latest"
POSTGRES_IMAGE="postgres:latest"
REDIS_IMAGE="redis:latest"
TRAEFIK_IMAGE="traefik:latest"
AUTHENTIK_IMAGE="ghcr.io/goauthentik/server:latest"
TEMPORAL_IMAGE="temporalio/auto-setup:latest"
TEMPORAL_ADMIN_TOOLS_IMAGE="temporalio/admin-tools:latest"
POSTIZ_IMAGE="ghcr.io/gitroomhq/postiz-app:latest"
CF_DDNS_IMAGE="oznu/cloudflare-ddns:latest"
CF_COMPANION_IMAGE="tiredofit/traefik-cloudflare-companion:latest"
VSCODE_IMAGE="lscr.io/linuxserver/code-server:latest"
FILEBROWSER_IMAGE="filebrowser/filebrowser:latest"
EOF

    msg_ok "DOCKER .ENV CREATED"
}



# --- 53. PERMISSIONS ---
# Applies secure permissions without breaking PostgreSQL init script readability.
# .env and secret files are treated as high-value secret material.
function apply_permissions() {
    section "PERMISSIONS"

    msg_info "Ensuring all required service folders exist"
    ensure_required_service_directories
    msg_ok "SERVICE FOLDERS CONFIRMED"

    msg_info "Applying service ownership"
    chown_required_service_directories
    msg_ok "SERVICE OWNERSHIP SET"

    msg_info "Applying service permissions"
    chmod_required_service_directories
    msg_ok "SERVICE PERMISSIONS SET"
}



# --- 53A. SERVICE PERMISSION AUDIT ---
# Fails early if Script 6 did not leave service bind mounts in the state required by the compose stacks.
function assert_owner_mode() {
    local path="$1"
    local expected_uid="$2"
    local expected_gid="$3"
    local expected_mode="$4"
    local actual=""

    # Use sudo-aware existence/stat checks because service paths such as
    # ${DOCKER_DIR}/appdata/redis are intentionally locked to UID/GID 999 with
    # mode 770. A normal shell user cannot traverse those directories, so plain
    # [ -e ] and stat can falsely report nested paths like redis/data as missing.
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -e "$path" || msg_error "Permission audit path missing: ${path}"
        actual="$("$SUDO_CMD" stat -c '%u:%g:%a' "$path" 2>/dev/null || true)"
    else
        test -e "$path" || msg_error "Permission audit path missing: ${path}"
        actual="$(stat -c '%u:%g:%a' "$path" 2>/dev/null || true)"
    fi

    if [ "$actual" != "${expected_uid}:${expected_gid}:${expected_mode}" ]; then
        msg_error "Permission audit failed for ${path}. Expected ${expected_uid}:${expected_gid}:${expected_mode}, got ${actual:-unknown}."
    fi

    msg_ok "PERMISSION OK: ${path}"
}


function assert_root_executable() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -x "$path" || msg_error "Executable audit failed: ${path}"
    else
        test -x "$path" || msg_error "Executable audit failed: ${path}"
    fi

    msg_ok "EXECUTABLE OK: ${path}"
}


function assert_user_writable_dir() {
    local path="$1"
    local test_file="${path}/.script6-write-test-$$"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -d "$path" || msg_error "Writable audit path missing: ${path}"
        "$SUDO_CMD" -u "$DOCKER_USER" sh -c "touch '$test_file' && rm -f '$test_file'" >/dev/null 2>&1 || msg_error "Docker user ${DOCKER_USER} cannot write to ${path}"
    else
        test -d "$path" || msg_error "Writable audit path missing: ${path}"
        touch "$test_file" && rm -f "$test_file" >/dev/null 2>&1 || msg_error "Current user cannot write to ${path}"
    fi

    msg_ok "WRITABLE OK: ${path}"
}

function verify_service_permissions() {
    section "SERVICE PERMISSION AUDIT"

    # This audit deliberately does not create or repair paths.
    # It verifies that Script 6's create -> chown -> chmod stages already left the expected final state.

    # Core project paths.
    assert_owner_mode "$DOCKER_DIR" "$(id -u "$DOCKER_USER")" "$(id -g "$DOCKER_USER")" "755"
    assert_owner_mode "${DOCKER_DIR}/appdata" "$(id -u "$DOCKER_USER")" "$(id -g "$DOCKER_USER")" "755"

    # PostgreSQL latest/18 path and legacy compatibility path.
    assert_owner_mode "${DOCKER_DIR}/appdata/postgres" "999" "999" "755"
    assert_owner_mode "${DOCKER_DIR}/appdata/postgres/pgdata" "999" "999" "700"
    assert_owner_mode "${DOCKER_DIR}/appdata/postgres/data" "999" "999" "700"

    assert_root_executable "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"

    # Redis: both the active bind target and nested compatibility path must exist
    # and be writable by UID/GID 999 before Script 6.5 deploys Redis.
    assert_owner_mode "${DOCKER_DIR}/appdata/redis" "999" "999" "770"
    assert_owner_mode "${DOCKER_DIR}/appdata/redis/data" "999" "999" "770"

    # Authentik bind mounts must be owned by the non-root Authentik UID/GID.
    assert_owner_mode "${DOCKER_DIR}/appdata/authentik" "1000" "1000" "770"
    assert_owner_mode "${DOCKER_DIR}/appdata/authentik/media" "1000" "1000" "770"
    assert_owner_mode "${DOCKER_DIR}/appdata/authentik/custom-templates" "1000" "1000" "770"
    assert_owner_mode "${DOCKER_DIR}/appdata/authentik/certs" "1000" "1000" "770"

    # User-facing appdata and shared folders should be writable by the selected Docker user.
    assert_user_writable_dir "${DOCKER_DIR}/compose"
    assert_user_writable_dir "${DOCKER_DIR}/shared"
    assert_user_writable_dir "${DOCKER_DIR}/backups"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/filebrowser/database"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/filebrowser/config"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/postiz/uploads"

    # Admin UI bind-mount paths. These are all created by Script 6 so Docker never
    # has to create them later as root during Script 6.5 deployment.
    assert_user_writable_dir "${DOCKER_DIR}/appdata/dockge"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/portainer"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/dockhand"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/dockhand/stacks"
    assert_owner_mode "${DOCKER_DIR}/appdata/komodo" "$PUID_VALUE" "$PGID_VALUE" "755"
    assert_owner_mode "${DOCKER_DIR}/appdata/komodo/postgres" "999" "999" "700"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/komodo/core"
    assert_user_writable_dir "${DOCKER_DIR}/appdata/komodo/periphery"

    # Secrets and Traefik ACME must remain locked down.
    assert_owner_mode "$DOCKER_SECRETS_DIR" "$(id -u "$DOCKER_USER")" "$(id -g "$DOCKER_USER")" "700"
    assert_owner_mode "${DOCKER_DIR}/.env" "$(id -u "$DOCKER_USER")" "$(id -g "$DOCKER_USER")" "600"
    assert_owner_mode "${TRAEFIK_ACME_DIR}/acme.json" "$PUID_VALUE" "$PGID_VALUE" "600"

    msg_ok "SERVICE PERMISSION AUDIT PASSED"
}


# =========================================================
#  VERIFICATION / MARKER / SUMMARY
# =========================================================

# --- 54. VERIFICATION REPORT ---
# Creates a verification report without printing secret values.
function create_verification_report() {
    section "VERIFICATION"

    msg_info "Creating Docker ENV verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<EOF
--- DOCKER ENV SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE

Results:
EOF
    else
        cat > "$VERIFY_LOG" <<EOF
--- DOCKER ENV SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE

Results:
EOF
    fi

    {
        if id "$DOCKER_USER" >/dev/null 2>&1; then echo "✓ PASS - Docker user exists"; else echo "✗ FAIL - Docker user missing"; fi
        if [ -d "$DOCKER_DIR" ]; then echo "✓ PASS - Docker directory exists"; else echo "✗ FAIL - Docker directory missing"; fi
        if [ -f "${DOCKER_DIR}/.env" ]; then echo "✓ PASS - .env exists"; else echo "✗ FAIL - .env missing"; fi
        if [ "$(root_stat_mode "${DOCKER_DIR}/.env")" == "600" ]; then echo "✓ PASS - .env mode is 600"; else echo "! WARN - .env mode is not 600"; fi
        if [ -d "$DOCKER_SECRETS_DIR" ]; then echo "✓ PASS - secrets directory exists"; else echo "✗ FAIL - secrets directory missing"; fi
        if [ "$(root_stat_mode "$DOCKER_SECRETS_DIR")" == "700" ]; then echo "✓ PASS - secrets directory mode is 700"; else echo "! WARN - secrets directory mode is not 700"; fi

        for secret_file in \
            postgres_password \
            redis_password \
            authentik_secret_key \
            authentik_postgres_password \
            postiz_postgres_password \
            postiz_jwt_secret \
            temporal_postgres_password \
            komodo_db_password \
            komodo_passkey \
            komodo_jwt_secret \
            komodo_webhook_secret
        do
            if [ -s "${DOCKER_SECRETS_DIR}/${secret_file}" ]; then
                echo "✓ PASS - ${secret_file} exists and is non-empty"
            else
                echo "✗ FAIL - ${secret_file} missing or empty"
            fi

            if [ "$(root_stat_mode "${DOCKER_SECRETS_DIR}/${secret_file}")" == "600" ]; then
                echo "✓ PASS - ${secret_file} mode is 600"
            else
                echo "! WARN - ${secret_file} mode is not 600"
            fi
        done

        if [ -e "$CF_API_TOKEN_FILE" ]; then echo "✓ PASS - Cloudflare token file exists"; else echo "! WARN - Cloudflare token file missing"; fi
        if [ -e "${DOCKER_SECRETS_DIR}/htpasswd" ]; then echo "✓ PASS - htpasswd file exists"; else echo "! WARN - htpasswd file missing"; fi
        if [ -x "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh" ]; then echo "✓ PASS - PostgreSQL init script exists and is executable"; else echo "✗ FAIL - PostgreSQL init script missing or not executable"; fi
        if [ -f "$TRAEFIK_STATIC_CONFIG_FILE" ]; then echo "✓ PASS - Traefik static config exists"; else echo "✗ FAIL - Traefik static config missing"; fi
        if [ -f "$TRAEFIK_DYNAMIC_CONFIG_FILE" ]; then echo "✓ PASS - Traefik dynamic config exists"; else echo "✗ FAIL - Traefik dynamic config missing"; fi
        if [ -f "${TRAEFIK_ACME_DIR}/acme.json" ]; then echo "✓ PASS - Traefik acme.json exists"; else echo "✗ FAIL - Traefik acme.json missing"; fi
        if [ "$(root_stat_mode "${TRAEFIK_ACME_DIR}/acme.json")" == "600" ]; then echo "✓ PASS - Traefik acme.json mode is 600"; else echo "! WARN - Traefik acme.json mode is not 600"; fi
        if grep -q "POSTIZ_JWT_SECRET=" "${DOCKER_DIR}/.env"; then echo "✓ PASS - Postiz JWT secret env present"; else echo "✗ FAIL - Postiz JWT secret env missing"; fi
        if [ -s "${DOCKER_SECRETS_DIR}/postiz_jwt_secret" ]; then echo "✓ PASS - postiz_jwt_secret exists and is non-empty"; else echo "✗ FAIL - postiz_jwt_secret missing or empty"; fi

        if command -v docker >/dev/null 2>&1; then echo "✓ PASS - Docker CLI detected"; else echo "! WARN - Docker CLI not detected"; fi
        if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then echo "✓ PASS - Docker Compose plugin detected"; else echo "! WARN - Docker Compose plugin not detected for current shell"; fi
        if id -nG "$DOCKER_USER" 2>/dev/null | grep -qw docker; then echo "✓ PASS - Docker user is in docker group"; else echo "! WARN - Docker user is not currently in docker group"; fi

        if [ -f "$COMPLETED_MARKER" ]; then echo "✓ PASS - completion marker exists"; else echo "! WARN - completion marker not present yet at verification time"; fi
    } | if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee -a "$VERIFY_LOG" >/dev/null; else tee -a "$VERIFY_LOG" >/dev/null; fi

    msg_ok "DOCKER ENV VERIFICATION REPORT CREATED"
}

# --- 55. COMPLETION MARKER ---
# Creates marker showing ENV setup completed successfully.
# No secret values are stored in the marker.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<EOF
Docker ENV Setup completed on: $(date)
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE
User: $DOCKER_USER
PUID: $PUID_VALUE
PGID: $PGID_VALUE
Timezone: $TZ_VALUE
Existing setup detected: $EXISTING_SETUP
Secrets regenerated: $REGENERATE_SECRETS
Cloudflare token file: $CF_API_TOKEN_FILE
Traefik static config: $TRAEFIK_STATIC_CONFIG_FILE
Traefik dynamic config: $TRAEFIK_DYNAMIC_CONFIG_FILE
Traefik ACME storage: ${TRAEFIK_ACME_DIR}/acme.json
Traefik dashboard host: $TRAEFIK_DASHBOARD_HOST
Proxmox route enabled: $PROXMOX_ROUTE_ENABLED
Htpasswd mode: $HTPASSWD_MODE
Docker ready: $DOCKER_READY
Docker Compose ready: $DOCKER_COMPOSE_READY
Docker user in docker group: $DOCKER_USER_IN_DOCKER_GROUP
Secret screen displayed: $SECRET_DISPLAY_WAS_SHOWN
Secret screen cleared: $SECRET_SCREEN_CLEARED
Verify log: $VERIFY_LOG
EOF
    else
        cat > "$COMPLETED_MARKER" <<EOF
Docker ENV Setup completed on: $(date)
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE
User: $DOCKER_USER
PUID: $PUID_VALUE
PGID: $PGID_VALUE
Timezone: $TZ_VALUE
Existing setup detected: $EXISTING_SETUP
Secrets regenerated: $REGENERATE_SECRETS
Cloudflare token file: $CF_API_TOKEN_FILE
Traefik static config: $TRAEFIK_STATIC_CONFIG_FILE
Traefik dynamic config: $TRAEFIK_DYNAMIC_CONFIG_FILE
Traefik ACME storage: ${TRAEFIK_ACME_DIR}/acme.json
Traefik dashboard host: $TRAEFIK_DASHBOARD_HOST
Proxmox route enabled: $PROXMOX_ROUTE_ENABLED
Htpasswd mode: $HTPASSWD_MODE
Docker ready: $DOCKER_READY
Docker Compose ready: $DOCKER_COMPOSE_READY
Docker user in docker group: $DOCKER_USER_IN_DOCKER_GROUP
Secret screen displayed: $SECRET_DISPLAY_WAS_SHOWN
Secret screen cleared: $SECRET_SCREEN_CLEARED
Verify log: $VERIFY_LOG
EOF
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 55B. POST-APPLY AUDIT PAUSE ---
# Lets the user review all apply-stage output before the screen is cleared for one-time secret display.
function wait_before_secret_display() {
    section "APPLY STAGE COMPLETE"

    echo -e "${GN}Docker ENV files, service folders, secrets, templates and permissions have been created/updated.${CL}"
    echo -e "${YW}Review the output above now. The next screen shows sensitive secrets and clears terminal scrollback after confirmation.${CL}"
    echo ""

    if [ -r /dev/tty ]; then
        read -r -p "Press ENTER when you are ready to view the one-time secret display..." _ < /dev/tty || true
    else
        read -r -p "Press ENTER when you are ready to view the one-time secret display..." _ || true
    fi

    return 0
}

# --- 56. FINAL SECRET DISPLAY ---
# Shows generated/reused secret values once while logging is disabled.
# After user confirms they saved them, terminal and scrollback are cleared where supported.
function show_secrets_once_without_logging() {
    disable_logging

    SECRET_DISPLAY_WAS_SHOWN="yes"

    clear
    header_info
    show_script_version

    echo -e "${RD}${CLF}SENSITIVE SECRET OUTPUT - NOT LOGGED${CL}"
    echo -e "${YW}Save these values now. This screen will be cleared after confirmation.${CL}"
    echo ""

    echo -e "${BL}CORE PATHS:${CL}"
    echo -e "DOCKER_DIR=${GN}${DOCKER_DIR}${CL}"
    echo -e "DOCKER_SECRETS_DIR=${GN}${DOCKER_SECRETS_DIR}${CL}"
    echo -e "USERDIR=${GN}${USERDIR}${CL}"
    echo ""

    echo -e "${BL}LINUX USER / IDS:${CL}"
    echo -e "DOCKER_USER=${GN}${DOCKER_USER}${CL}"
    echo -e "PUID=${GN}${PUID_VALUE}${CL}"
    echo -e "PGID=${GN}${PGID_VALUE}${CL}"
    echo ""

    echo -e "${BL}DOMAIN / CLOUDFLARE:${CL}"
    echo -e "DOMAIN=${GN}${DOMAIN_VALUE}${CL}"
    echo -e "CF_API_EMAIL=${GN}${CF_API_EMAIL_VALUE:-not used with token auth}${CL}"
    echo -e "CF_ZONE_ID=${GN}${CF_ZONE_ID_VALUE}${CL}"
    echo -e "CF_API_TOKEN_FILE=${GN}${CF_API_TOKEN_FILE}${CL}"
    echo -e "TRAEFIK_STATIC_CONFIG=${GN}${TRAEFIK_STATIC_CONFIG_FILE}${CL}"
    echo -e "TRAEFIK_DYNAMIC_CONFIG=${GN}${TRAEFIK_DYNAMIC_CONFIG_FILE}${CL}"
    echo -e "TRAEFIK_ACME_STORAGE=${GN}${TRAEFIK_ACME_DIR}/acme.json${CL}"

    if [ -n "$CF_API_TOKEN_VALUE" ]; then
        echo -e "CF_API_TOKEN=${GN}${CF_API_TOKEN_VALUE}${CL}"
    else
        echo -e "CF_API_TOKEN=${YW}<empty / not provided>${CL}"
    fi

    echo ""
    echo -e "${BL}AUTHENTIK BOOTSTRAP / API:${CL}"
    echo -e "AUTHENTIK_HOST=${GN}${AUTHENTIK_HOST_VALUE}${CL}"
    echo -e "AUTHENTIK_HOST_BROWSER=${GN}${AUTHENTIK_HOST_BROWSER_VALUE}${CL}"
    echo -e "AUTHENTIK_BOOTSTRAP_EMAIL=${GN}${AUTHENTIK_BOOTSTRAP_EMAIL_VALUE}${CL}"
    echo -e "AUTHENTIK_BOOTSTRAP_PASSWORD=${GN}${AUTHENTIK_BOOTSTRAP_PASSWORD_VALUE}${CL}"
    echo -e "AUTHENTIK_BOOTSTRAP_TOKEN=${GN}${AUTHENTIK_BOOTSTRAP_TOKEN_VALUE}${CL}"
    echo -e "AUTHENTIK_API_TOKEN_MODE=${GN}${AUTHENTIK_API_TOKEN_MODE}${CL}"
    if [ -n "$AUTHENTIK_API_TOKEN_VALUE" ]; then
        echo -e "AUTHENTIK_API_TOKEN=${GN}${AUTHENTIK_API_TOKEN_VALUE}${CL}"
    else
        echo -e "AUTHENTIK_API_TOKEN=${YW}<empty / skipped>${CL}"
    fi
    echo -e "${YW}Reminder: for fresh Authentik, AUTHENTIK_BOOTSTRAP_TOKEN creates an akadmin API Access token and Script 6.5 can reuse it.${CL}"

    echo ""
    echo -e "${BL}SERVICE SECRETS:${CL}"
    echo -e "POSTGRES_PASSWORD=${GN}${POSTGRES_PASSWORD}${CL}"
    echo -e "REDIS_PASSWORD=${GN}${REDIS_PASSWORD}${CL}"
    echo -e "AUTHENTIK_SECRET_KEY=${GN}${AUTHENTIK_SECRET_KEY}${CL}"
    echo -e "AUTHENTIK_POSTGRES_PASSWORD=${GN}${AUTHENTIK_POSTGRES_PASSWORD}${CL}"
    echo -e "POSTIZ_POSTGRES_PASSWORD=${GN}${POSTIZ_POSTGRES_PASSWORD}${CL}"
    echo -e "POSTIZ_JWT_SECRET=${GN}${POSTIZ_JWT_SECRET}${CL}"
    echo -e "TEMPORAL_POSTGRES_PASSWORD=${GN}${TEMPORAL_POSTGRES_PASSWORD}${CL}"
    echo -e "KOMODO_DB_PASSWORD=${GN}${KOMODO_DB_PASSWORD}${CL}"
    echo -e "KOMODO_PASSKEY=${GN}${KOMODO_PASSKEY}${CL}"
    echo -e "KOMODO_JWT_SECRET=${GN}${KOMODO_JWT_SECRET}${CL}"
    echo -e "KOMODO_WEBHOOK_SECRET=${GN}${KOMODO_WEBHOOK_SECRET}${CL}"
    echo ""

    echo -e "${BL}HTPASSWD:${CL}"

    if [ "$HTPASSWD_MODE" == "generated" ]; then
        echo -e "HTPASSWD_HASHED_LINE=${GN}${HTPASSWD_LINE_VALUE}${CL}"
        echo -e "${YW}Plain htpasswd password was not displayed or logged.${CL}"
    elif [ "$HTPASSWD_MODE" == "provided" ]; then
        echo -e "${GN}Provided htpasswd entry saved to:${CL} ${DOCKER_SECRETS_DIR}/htpasswd"
        echo -e "${YW}Provided htpasswd hash is intentionally not displayed or logged.${CL}"
    elif root_file_not_empty "${DOCKER_SECRETS_DIR}/htpasswd"; then
        echo -e "${GN}Existing htpasswd file preserved at:${CL} ${DOCKER_SECRETS_DIR}/htpasswd"
        echo -e "${YW}Existing htpasswd content is intentionally not displayed.${CL}"
    else
        echo -e "${YW}htpasswd file created empty:${CL} ${DOCKER_SECRETS_DIR}/htpasswd"
        echo -e "${YW}This is fine when Authentik/Authelia/SSO is used instead of Traefik basic-auth.${CL}"
    fi


    echo ""
    echo -e "${BL}IMAGE DEFAULTS / DEVELOPMENT MODE:${CL}"
    echo -e "SOCKET_PROXY_IMAGE=${GN}tecnativa/docker-socket-proxy:latest${CL}"
    echo -e "DOCKGE_IMAGE=${GN}louislam/dockge:latest${CL}"
    echo -e "DOCKHAND_IMAGE=${GN}fnsys/dockhand:latest${CL}"
    echo -e "KOMODO_POSTGRES_IMAGE=${GN}postgres:latest${CL}"
    echo -e "KOMODO_FERRETDB_IMAGE=${GN}ghcr.io/ferretdb/ferretdb:latest${CL}"
    echo -e "KOMODO_CORE_IMAGE=${GN}ghcr.io/moghtech/komodo-core:latest${CL}"
    echo -e "KOMODO_PERIPHERY_IMAGE=${GN}ghcr.io/moghtech/komodo-periphery:latest${CL}"
    echo -e "PORTAINER_IMAGE=${GN}portainer/portainer-ce:latest${CL}"
    echo -e "POSTGRES_IMAGE=${GN}postgres:latest${CL}"
    echo -e "REDIS_IMAGE=${GN}redis:latest${CL}"
    echo -e "TRAEFIK_IMAGE=${GN}traefik:latest${CL}"
    echo -e "AUTHENTIK_IMAGE=${GN}ghcr.io/goauthentik/server:latest${CL}"
    echo -e "TEMPORAL_IMAGE=${GN}temporalio/auto-setup:latest${CL}"
    echo -e "TEMPORAL_ADMIN_TOOLS_IMAGE=${GN}temporalio/admin-tools:latest${CL}"
    echo -e "POSTIZ_IMAGE=${GN}ghcr.io/gitroomhq/postiz-app:latest${CL}"
    echo -e "CF_DDNS_IMAGE=${GN}oznu/cloudflare-ddns:latest${CL}"
    echo -e "CF_COMPANION_IMAGE=${GN}tiredofit/traefik-cloudflare-companion:latest${CL}"
    echo -e "VSCODE_IMAGE=${GN}lscr.io/linuxserver/code-server:latest${CL}"
    echo -e "FILEBROWSER_IMAGE=${GN}filebrowser/filebrowser:latest${CL}"
    echo ""
    echo -e "${YW}Sensitive final output above was intentionally not written to ${LOG_FILE}.${CL}"

    wait_then_clear_secret_display

    enable_logging
}

# --- 57. CLEAN FINAL SUMMARY ---
# Prints non-sensitive final summary after secrets have been cleared from the terminal.
function show_clean_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    detail_line "DOCKER DIR" "$DOCKER_DIR"
    detail_line ".ENV FILE" "${DOCKER_DIR}/.env"
    detail_line "SECRETS DIR" "$DOCKER_SECRETS_DIR"
    detail_line "POSTGRES INIT" "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"
    detail_line "TRAEFIK STATIC CONFIG" "$TRAEFIK_STATIC_CONFIG_FILE"
    detail_line "TRAEFIK DYNAMIC CONFIG" "$TRAEFIK_DYNAMIC_CONFIG_FILE"
    detail_line "TRAEFIK ACME STORAGE" "${TRAEFIK_ACME_DIR}/acme.json"
    detail_line "TRAEFIK DASHBOARD HOST" "$TRAEFIK_DASHBOARD_HOST"
    detail_line "CLOUDFLARE TOKEN FILE" "$CF_API_TOKEN_FILE"
    detail_line "HTPASSWD FILE" "${DOCKER_SECRETS_DIR}/htpasswd"
    detail_line "DOMAIN" "$DOMAIN_VALUE"
    detail_line "DOCKER USER" "$DOCKER_USER"
    detail_line "PUID / PGID" "${PUID_VALUE}:${PGID_VALUE}"
    detail_line "EXISTING SETUP" "$EXISTING_SETUP"
    detail_line "SECRETS REGENERATED" "$REGENERATE_SECRETS"
    detail_line "SECRET SCREEN CLEARED" "$SECRET_SCREEN_CLEARED"
    detail_line "VERIFY LOG" "$VERIFY_LOG"
    echo ""
    echo -e "${YW}Sensitive values were displayed once, not logged, then terminal output was cleared where supported.${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}Run script 6.5 to create Docker networks and deploy the selected dependency-aware stack plan.${CL}"
    echo ""
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 58. MAIN FUNCTION ---
# Runs full setup in validation -> input -> file creation -> verify -> one-time secret display order.
function main() {
    init_script

    check_previous_marker
    start_confirmation
    check_docker_readiness
    collect_user_and_path_inputs
    detect_existing_setup
    collect_domain_cloudflare_inputs
    collect_admin_ui_selection
    collect_authentik_inputs
    collect_traefik_inputs
    collect_htpasswd_inputs
    show_ready_summary_and_confirm

    create_docker_directories
    generate_or_reuse_secrets
    create_postgres_init_script
    create_traefik_config_files
    verify_traefik_config_files_created
    write_secret_files
    write_env_file
    apply_permissions
    verify_service_permissions

    wait_before_secret_display
    show_secrets_once_without_logging

    write_completion_marker
    create_verification_report
    show_clean_final_summary

    exit 0
}


main "$@"