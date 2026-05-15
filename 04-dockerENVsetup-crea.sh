#!/usr/bin/env bash -ex
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker ENV Setup
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
YW=`echo "\033[33m"`
BL=`echo "\033[36m"`
RD=`echo "\033[01;31m"`
BGN=`echo "\033[4;92m"`
GN=`echo "\033[1;92m"`
DGN=`echo "\033[32m"`
CL=`echo "\033[m"`
CLF=`echo "\033[5m"`
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# --- 2. GLOBAL VARIABLES ---
T=15
LOG_FILE="/var/log/docker-env-setup.log"
COMPLETED_MARKER="/root/.docker-env-setup-completed"

DEFAULT_USER="youruser"
DEFAULT_USERDIR="/home/${DEFAULT_USER}"
DEFAULT_DOCKER_DIR="${DEFAULT_USERDIR}/docker"
DEFAULT_TZ="Europe/London"
DEFAULT_DOMAIN="example.com"
DEFAULT_CF_EMAIL="cloudflare-email@example.com"
DEFAULT_CF_ZONEID=""

DOCKER_USER=""
USERDIR=""
DOCKER_DIR=""
DOCKER_SECRETS_DIR=""
TZ_VALUE=""
DOMAIN_VALUE=""
CF_EMAIL_VALUE=""
CF_ZONEID_VALUE=""
PUID_VALUE=""
PGID_VALUE=""

POSTGRES_PASSWORD=""
REDIS_PASSWORD=""
AUTHENTIK_SECRET_KEY=""
AUTHENTIK_POSTGRES_PASSWORD=""
POSTIZ_POSTGRES_PASSWORD=""
TEMPORAL_POSTGRES_PASSWORD=""

# --- 3. HEADER FUNCTION ---
# Displays one-line Docker ENV Setup banner.
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
# Provides consistent status messages.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. ROOT CHECK ---
# This script writes to /var/log, /root and system-owned paths, so it must run as root.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root: sudo bash docker-env-setup.sh${CL}"
    exit 1
fi

# --- 6. LOGGING & ERROR HANDLING ---
# Logs output and reports failing line.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

clear
header_info

# --- 7. TTY OUTPUT HELPER ---
# Prints directly to terminal from prompt functions.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 8. TTY OUTPUT WITH NEWLINE HELPER ---
# Prints directly to terminal with newline.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 9. YES/NO LABEL HELPER ---
# Converts Y/N answer into visible yes/no text.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 10. BLOCKING YES/NO HELPER ---
# Used when SPACE pauses countdown.
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

# --- 11. TIMED YES/NO PROMPT HELPER ---
# SPACE pauses and waits. Timeout accepts default. Final answer stays visible.
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

# --- 12. BLOCKING EDITABLE TEXT INPUT HELPER ---
# Used when user starts typing or presses SPACE during text input.
# The countdown disappears and the user can edit normally. ENTER accepts typed value or default.
function tty_read_text_blocking() {
    local prompt="$1"
    local default="$2"
    local buffer="${3:-}"
    local key=""

    while true; do
        tty_print "${BFR}${YW}${prompt} [default: ${default}]: ${CL}${buffer}"

        if [ -r /dev/tty ]; then
            IFS= read -rsn1 key < /dev/tty || true
        else
            IFS= read -rsn1 key || true
        fi

        case "$key" in
            "")
                tty_print "${BFR}"
                if [ -z "$buffer" ]; then
                    echo "$default"
                else
                    echo "$buffer"
                fi
                return 0
                ;;
            $'\177'|$'\b')
                buffer="${buffer%?}"
                ;;
            *)
                buffer+="$key"
                ;;
        esac
    done
}

# --- 13. TIMED TEXT INPUT HELPER ---
# Reads editable text with countdown. Typing or SPACE stops timer. Empty input or timeout uses default.
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
                    answer="$(tty_read_text_blocking "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(tty_read_text_blocking "$prompt" "$default" "$key")"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(tty_read_text_blocking "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(tty_read_text_blocking "$prompt" "$default" "$key")"
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

# --- 14. SECRET GENERATOR HELPER ---
# Generates URL-safe random secrets for app/database credentials.
function generate_secret() {
    openssl rand -hex 32 | cut -c1-48
}

# --- 15. START CONFIRMATION ---
# Starts Docker env setup.
echo -e "${YW}This script creates Docker folders, .env and service secrets for the Home-Hosted Social Media SaaS project.${CL}"
start_yn=$(timed_yes_no "Start the Docker ENV Setup Script?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 16. USER INPUTS ---
# Collects reusable defaults for user, paths, timezone, domain and Cloudflare values.
DOCKER_USER=$(timed_text_input "Enter Linux username" "$DEFAULT_USER")

DEFAULT_USERDIR="/home/${DOCKER_USER}"
DEFAULT_DOCKER_DIR="${DEFAULT_USERDIR}/docker"

USERDIR=$(timed_text_input "Enter user home directory" "$DEFAULT_USERDIR")
DEFAULT_DOCKER_DIR="${USERDIR}/docker"

DOCKER_DIR=$(timed_text_input "Enter Docker directory" "$DEFAULT_DOCKER_DIR")
DOCKER_SECRETS_DIR="${DOCKER_DIR}/secrets"

TZ_VALUE=$(timed_text_input "Enter timezone" "$DEFAULT_TZ")
DOMAIN_VALUE=$(timed_text_input "Enter domain" "$DEFAULT_DOMAIN")
CF_EMAIL_VALUE=$(timed_text_input "Enter Cloudflare email" "$DEFAULT_CF_EMAIL")
CF_ZONEID_VALUE=$(timed_text_input "Enter Cloudflare Zone ID" "$DEFAULT_CF_ZONEID")

# --- 17. USER/GROUP ID DETECTION ---
# Detects PUID/PGID for container permissions.
if id "$DOCKER_USER" >/dev/null 2>&1; then
    PUID_VALUE=$(id -u "$DOCKER_USER")
    PGID_VALUE=$(id -g "$DOCKER_USER")
else
    PUID_VALUE="1000"
    PGID_VALUE="1000"
fi

# --- 18. SECRET GENERATION ---
# Generates service secrets for PostgreSQL, Redis, Authentik, Postiz and Temporal.
msg_info "Generating secrets"

POSTGRES_PASSWORD="$(generate_secret)"
REDIS_PASSWORD="$(generate_secret)"
AUTHENTIK_SECRET_KEY="$(generate_secret)"
AUTHENTIK_POSTGRES_PASSWORD="$(generate_secret)"
POSTIZ_POSTGRES_PASSWORD="$(generate_secret)"
TEMPORAL_POSTGRES_PASSWORD="$(generate_secret)"

msg_ok "SECRETS GENERATED"

# --- 19. DOCKER DIRECTORY CREATION ---
# Creates project folders for compose, appdata, backups, shared files and secrets.
msg_info "Creating Docker folder structure"

mkdir -p "${DOCKER_DIR}/appdata"
mkdir -p "${DOCKER_DIR}/compose"
mkdir -p "${DOCKER_DIR}/backups"
mkdir -p "${DOCKER_DIR}/shared"
mkdir -p "${DOCKER_SECRETS_DIR}"

mkdir -p "${DOCKER_DIR}/appdata/postgres/data"
mkdir -p "${DOCKER_DIR}/appdata/postgres/init"

msg_ok "DOCKER FOLDERS CREATED"

# --- 20. POSTGRES INIT SCRIPT CREATION ---
# Creates first-start PostgreSQL init script so app databases/users are created unattended.
msg_info "Creating PostgreSQL init script"

cat <<'EOF' > "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"
#!/usr/bin/env bash
set -euo pipefail

create_user_db() {
    local user="$1"
    local password="$2"
    local database="$3"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<EOSQL
DO
\$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${user}') THEN
      CREATE USER ${user} WITH PASSWORD '${password}';
   END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${database} OWNER ${user}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${database}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${database} TO ${user};
EOSQL
}

create_user_db "authentik" "${AUTHENTIK_POSTGRES_PASSWORD}" "authentik"
create_user_db "postiz" "${POSTIZ_POSTGRES_PASSWORD}" "postiz"
create_user_db "temporal" "${TEMPORAL_POSTGRES_PASSWORD}" "temporal"
EOF

chmod +x "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"

msg_ok "POSTGRES INIT SCRIPT CREATED"

# --- 21. SECRET FILE WRITING ---
# Writes secrets to individual files so Docker Compose can consume them as file-based secrets where suitable.
msg_info "Writing secret files"

printf '%s' "$POSTGRES_PASSWORD" > "${DOCKER_SECRETS_DIR}/postgres_password"
printf '%s' "$REDIS_PASSWORD" > "${DOCKER_SECRETS_DIR}/redis_password"
printf '%s' "$AUTHENTIK_SECRET_KEY" > "${DOCKER_SECRETS_DIR}/authentik_secret_key"
printf '%s' "$AUTHENTIK_POSTGRES_PASSWORD" > "${DOCKER_SECRETS_DIR}/authentik_postgres_password"
printf '%s' "$POSTIZ_POSTGRES_PASSWORD" > "${DOCKER_SECRETS_DIR}/postiz_postgres_password"
printf '%s' "$TEMPORAL_POSTGRES_PASSWORD" > "${DOCKER_SECRETS_DIR}/temporal_postgres_password"
printf '%s' "$CF_EMAIL_VALUE" > "${DOCKER_SECRETS_DIR}/cf_email"
touch "${DOCKER_SECRETS_DIR}/cf_token"
touch "${DOCKER_SECRETS_DIR}/htpasswd"

msg_ok "SECRET FILES WRITTEN"

# --- 22. ENV FILE CREATION ---
# Creates /updates Docker .env used by docker compose CLI and Portainer stacks.
msg_info "Creating Docker .env file"

cat <<EOF > "${DOCKER_DIR}/.env"
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

# --- Localisation ---
TZ="${TZ_VALUE}"

# --- Domain / Cloudflare ---
DOMAIN="${DOMAIN_VALUE}"
CF_EMAIL="${CF_EMAIL_VALUE}"
CF_ZONEID="${CF_ZONEID_VALUE}"

# --- PostgreSQL root/admin password ---
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

# --- Redis ---
REDIS_PASSWORD="${REDIS_PASSWORD}"

# --- Authentik ---
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY}"
AUTHENTIK_POSTGRES_PASSWORD="${AUTHENTIK_POSTGRES_PASSWORD}"

# --- Postiz ---
POSTIZ_POSTGRES_PASSWORD="${POSTIZ_POSTGRES_PASSWORD}"

# --- Temporal ---
TEMPORAL_POSTGRES_PASSWORD="${TEMPORAL_POSTGRES_PASSWORD}"
EOF

msg_ok "DOCKER .ENV CREATED"

# --- 23. PERMISSIONS ---
# Sets Docker folder permissions and stricter secret permissions.
msg_info "Setting folder permissions"

if id "$DOCKER_USER" >/dev/null 2>&1; then
    chown -R "${DOCKER_USER}:${DOCKER_USER}" "$DOCKER_DIR"
fi

chmod -R 775 "$DOCKER_DIR"
chmod -R 700 "$DOCKER_SECRETS_DIR"
chmod -R 600 "$DOCKER_SECRETS_DIR"/* 2>/dev/null || true

msg_ok "PERMISSIONS SET"

# --- 24. COMPLETION MARKER ---
# Creates marker showing ENV setup ran successfully.
cat <<EOF > "$COMPLETED_MARKER"
Docker ENV Setup completed on: $(date)
Docker dir: $DOCKER_DIR
Domain: $DOMAIN_VALUE
User: $DOCKER_USER
EOF

# --- 25. FINAL SECRET DISPLAY WARNING ---
# Displays generated values once so user can save them securely.
echo ""
echo -e "${RD}${CLF}SAVE THESE VALUES NOW. THEY WILL NOT BE DISPLAYED AGAIN BY THIS SCRIPT.${CL}"
echo ""
echo -e "${GN}POSTGRES_PASSWORD:${CL} ${POSTGRES_PASSWORD}"
echo -e "${GN}REDIS_PASSWORD:${CL} ${REDIS_PASSWORD}"
echo -e "${GN}AUTHENTIK_SECRET_KEY:${CL} ${AUTHENTIK_SECRET_KEY}"
echo -e "${GN}AUTHENTIK_POSTGRES_PASSWORD:${CL} ${AUTHENTIK_POSTGRES_PASSWORD}"
echo -e "${GN}POSTIZ_POSTGRES_PASSWORD:${CL} ${POSTIZ_POSTGRES_PASSWORD}"
echo -e "${GN}TEMPORAL_POSTGRES_PASSWORD:${CL} ${TEMPORAL_POSTGRES_PASSWORD}"
echo ""
echo -e "${YW}Cloudflare token file created empty:${CL} ${DOCKER_SECRETS_DIR}/cf_token"
echo -e "${YW}Add your Cloudflare API token before deploying Traefik/cf-ddns/cf-companion.${CL}"
echo ""

# --- 26. FINAL SUMMARY ---
# Shows final folder layout.
echo -e "${GN}FINISHED!${CL}"
echo -e "DOCKER DIR: ${GN}${DOCKER_DIR}${CL}"
echo -e ".ENV FILE: ${GN}${DOCKER_DIR}/.env${CL}"
echo -e "SECRETS DIR: ${GN}${DOCKER_SECRETS_DIR}${CL}"
echo -e "POSTGRES INIT: ${GN}${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh${CL}"
echo ""

exit 0