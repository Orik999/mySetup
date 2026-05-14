#!/usr/bin/env bash -ex
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  DOCKER ENV SETUP
#  Project: Home-Hosted Social Media SaaS
#  Creates Docker folders, .env variables, secrets,
#  PostgreSQL init scripts, and service passwords.
# =========================================================

# --- 1. COLOR VARIABLES ---
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

T=15
DEFAULT_USER="orik"
DEFAULT_DOMAIN="najafov.co.uk"
DEFAULT_TZ="Europe/London"
DEFAULT_CF_EMAIL="oriknj999@gmail.com"

# --- 2. HEADER & MESSAGE FUNCTIONS ---
# Displays one-line Docker ENV Setup banner and reusable message helpers.
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

function msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 3. HELPER FUNCTIONS ---
# Handles timed prompts, secret generation, secret files, and optional Argon2 display.
function timed_prompt() {
    local prompt="$1"
    local default="$2"
    local input=""
    read -t "$T" -p "$prompt" input || input="$default"
    [ -z "$input" ] && input="$default"
    echo "$input"
}

function generate_secret() {
    openssl rand -base64 48 | tr -d '\n'
}

function write_secret_file() {
    local file="$1"
    local value="$2"
    echo -n "$value" > "$file"
    chmod 600 "$file"
}

function argon2_hash() {
    local password="$1"
    if command -v argon2 >/dev/null 2>&1; then
        echo -n "$password" | argon2 "$(openssl rand -base64 16)" -id -t 3 -m 16 -p 4
    else
        echo "argon2 command not installed"
    fi
}

clear
header_info

# --- 4. START PROMPT ---
# Starts the unattended-friendly Docker environment setup flow.
echo -e "${YW} This script will create Docker project folders, .env, secrets and PostgreSQL init scripts.${CL}"
yn=$(timed_prompt "Start DOCKER ENV SETUP? (Y/n): " "y")
[[ "$yn" =~ ^[Nn] ]] && exit

# --- 5. USER / PROJECT INPUTS ---
# Lets user reuse this script for future projects while keeping your current project defaults.
USERNAME=$(timed_prompt "Main user (Default ${DEFAULT_USER}): " "$DEFAULT_USER")
DOMAIN=$(timed_prompt "Domain (Default ${DEFAULT_DOMAIN}): " "$DEFAULT_DOMAIN")
TZ=$(timed_prompt "Timezone (Default ${DEFAULT_TZ}): " "$DEFAULT_TZ")
CF_EMAIL=$(timed_prompt "Cloudflare email (Default ${DEFAULT_CF_EMAIL}): " "$DEFAULT_CF_EMAIL")
CF_ZONEID=$(timed_prompt "Cloudflare Zone ID (Default blank): " "")

if ! id "$USERNAME" >/dev/null 2>&1; then
    msg_error "User $USERNAME does not exist"
fi

USERDIR=$(eval echo "~$USERNAME")
DOCKER_DIR=$(timed_prompt "Docker dir (Default ${USERDIR}/docker): " "${USERDIR}/docker")
DOCKER_SECRETS_DIR=$(timed_prompt "Secrets dir (Default ${DOCKER_DIR}/secrets): " "${DOCKER_DIR}/secrets")

PUID=$(id -u "$USERNAME")
PGID=$(id -g "$USERNAME")

# --- 6. DOCKER FOLDER STRUCTURE ---
# Creates all folders needed by standalone Portainer stacks and future compose files.
msg_info "Creating Docker folders"

mkdir -p "$DOCKER_DIR"/{appdata,compose,backups,shared}
mkdir -p "$DOCKER_SECRETS_DIR"

mkdir -p "$DOCKER_DIR/appdata/postgres/data"
mkdir -p "$DOCKER_DIR/appdata/postgres/init"

mkdir -p "$DOCKER_DIR/appdata/redis"
mkdir -p "$DOCKER_DIR/appdata/traefik/acme"
mkdir -p "$DOCKER_DIR/appdata/authentik"/{media,certs,custom-templates}
mkdir -p "$DOCKER_DIR/appdata/postiz"/{config,uploads}
mkdir -p "$DOCKER_DIR/appdata/temporal/dynamicconfig"
mkdir -p "$DOCKER_DIR/appdata/portainer"
mkdir -p "$DOCKER_DIR/appdata/vscode/config"
mkdir -p "$DOCKER_DIR/appdata/filebrowser"/{database,config}
## 2. Create compose folders for CLI deployment
mkdir -p "$DOCKER_DIR/compose/socket-proxy"
mkdir -p "$DOCKER_DIR/compose/portainer"

chown -R "$USERNAME:$USERNAME" "$DOCKER_DIR"
chmod 775 "$DOCKER_DIR"
chmod 700 "$DOCKER_SECRETS_DIR"

msg_ok "FOLDERS CREATED"

# --- 7. SECRET GENERATION ---
# Generates strong secrets for PostgreSQL, Redis, Authentik, Postiz and Temporal.
msg_info "Generating secrets"

POSTGRES_PASSWORD=$(generate_secret)
REDIS_PASSWORD=$(generate_secret)
AUTHENTIK_SECRET_KEY=$(generate_secret)
AUTHENTIK_POSTGRES_PASSWORD=$(generate_secret)
POSTIZ_POSTGRES_PASSWORD=$(generate_secret)
POSTIZ_JWT_SECRET=$(generate_secret)
TEMPORAL_POSTGRES_PASSWORD=$(generate_secret)

CF_TOKEN=$(timed_prompt "Cloudflare API token (Default blank): " "")
SMTP_HOST=$(timed_prompt "SMTP host (Default blank): " "")
SMTP_PORT=$(timed_prompt "SMTP port (Default 587): " "587")
SMTP_USERNAME=$(timed_prompt "SMTP username (Default blank): " "")
SMTP_PASSWORD=$(timed_prompt "SMTP password (Default blank): " "")
AUTHENTIK_EMAIL_FROM=$(timed_prompt "Authentik email FROM (Default auth@${DOMAIN}): " "auth@${DOMAIN}")

write_secret_file "$DOCKER_SECRETS_DIR/cf_token" "$CF_TOKEN"
write_secret_file "$DOCKER_SECRETS_DIR/postgres_password" "$POSTGRES_PASSWORD"
write_secret_file "$DOCKER_SECRETS_DIR/redis_password" "$REDIS_PASSWORD"
write_secret_file "$DOCKER_SECRETS_DIR/authentik_secret_key" "$AUTHENTIK_SECRET_KEY"
write_secret_file "$DOCKER_SECRETS_DIR/authentik_postgres_password" "$AUTHENTIK_POSTGRES_PASSWORD"
write_secret_file "$DOCKER_SECRETS_DIR/postiz_postgres_password" "$POSTIZ_POSTGRES_PASSWORD"
write_secret_file "$DOCKER_SECRETS_DIR/postiz_jwt_secret" "$POSTIZ_JWT_SECRET"
write_secret_file "$DOCKER_SECRETS_DIR/temporal_postgres_password" "$TEMPORAL_POSTGRES_PASSWORD"

touch "$DOCKER_SECRETS_DIR/htpasswd"
chmod 600 "$DOCKER_SECRETS_DIR/htpasswd"

msg_ok "SECRETS GENERATED"

# --- 8. DOCKER .env CREATION ---
# Writes central .env used by all standalone Docker Compose stacks.
msg_info "Creating .env"

cat > "$DOCKER_DIR/.env" <<EOF
# Project: Home-Hosted Social Media SaaS
DOCKER_DIR="${DOCKER_DIR}"
DOCKER_SECRETS_DIR="${DOCKER_SECRETS_DIR}"
PUID="${PUID}"
PGID="${PGID}"
TZ="${TZ}"
USERDIR="${USERDIR}"
DOMAIN="${DOMAIN}"

# Cloudflare
CF_EMAIL="${CF_EMAIL}"
CF_ZONEID="${CF_ZONEID}"

# Shared PostgreSQL admin
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

# Shared Redis
REDIS_PASSWORD="${REDIS_PASSWORD}"

# Authentik
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY}"
AUTHENTIK_POSTGRES_PASSWORD="${AUTHENTIK_POSTGRES_PASSWORD}"
AUTHENTIK_EMAIL_FROM="${AUTHENTIK_EMAIL_FROM}"

# Postiz
POSTIZ_POSTGRES_PASSWORD="${POSTIZ_POSTGRES_PASSWORD}"
POSTIZ_JWT_SECRET="${POSTIZ_JWT_SECRET}"

# Temporal
TEMPORAL_POSTGRES_PASSWORD="${TEMPORAL_POSTGRES_PASSWORD}"

# SMTP
SMTP_HOST="${SMTP_HOST}"
SMTP_PORT="${SMTP_PORT}"
SMTP_USERNAME="${SMTP_USERNAME}"
SMTP_PASSWORD="${SMTP_PASSWORD}"
EOF

chown "$USERNAME:$USERNAME" "$DOCKER_DIR/.env"
chmod 600 "$DOCKER_DIR/.env"

msg_ok ".env CREATED"

# --- 9. POSTGRESQL FIRST-START INIT SCRIPT ---
# Creates app databases/users automatically on first PostgreSQL container startup.
msg_info "Creating PostgreSQL init script"

cat > "$DOCKER_DIR/appdata/postgres/init/01-create-app-databases.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# PostgreSQL Init Databases
# Project: Home-Hosted Social Media SaaS
# Runs automatically only on first PostgreSQL container startup.
# Creates separate users/databases for Authentik, Postiz and Temporal.
# =========================================================

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
-- --- 1. AUTHENTIK DATABASE ---
-- Used by Authentik server/worker for identity, SSO, 2FA, sessions and app configuration.
CREATE USER authentik WITH PASSWORD '${AUTHENTIK_POSTGRES_PASSWORD}';
CREATE DATABASE authentik OWNER authentik;
GRANT ALL PRIVILEGES ON DATABASE authentik TO authentik;

-- --- 2. POSTIZ DATABASE ---
-- Used by Postiz for social accounts, posts, schedules, users and app state.
CREATE USER postiz WITH PASSWORD '${POSTIZ_POSTGRES_PASSWORD}';
CREATE DATABASE postiz OWNER postiz;
GRANT ALL PRIVILEGES ON DATABASE postiz TO postiz;

-- --- 3. TEMPORAL DATABASE ---
-- Used by Temporal workflow engine for queues, jobs and workflow state.
CREATE USER temporal WITH PASSWORD '${TEMPORAL_POSTGRES_PASSWORD}';
CREATE DATABASE temporal OWNER temporal;
GRANT ALL PRIVILEGES ON DATABASE temporal TO temporal;
EOSQL
EOF

chmod +x "$DOCKER_DIR/appdata/postgres/init/01-create-app-databases.sh"
chown -R "$USERNAME:$USERNAME" "$DOCKER_DIR/appdata/postgres"

msg_ok "POSTGRESQL INIT SCRIPT CREATED"

# --- 10. FINAL OUTPUT ---
# Displays generated values and tells user what to save.
echo ""
echo -e "${GN}DOCKER ENV SETUP COMPLETE${CL}"
echo "------------------------------------------------------"
echo "DOCKER_DIR=${DOCKER_DIR}"
echo "DOCKER_SECRETS_DIR=${DOCKER_SECRETS_DIR}"
echo "DOMAIN=${DOMAIN}"
echo "CF_EMAIL=${CF_EMAIL}"
echo "CF_ZONEID=${CF_ZONEID}"
echo ""
echo -e "${YW}SAVE THESE VALUES IN YOUR PASSWORD MANAGER:${CL}"
echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
echo "REDIS_PASSWORD=${REDIS_PASSWORD}"
echo "AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}"
echo "AUTHENTIK_POSTGRES_PASSWORD=${AUTHENTIK_POSTGRES_PASSWORD}"
echo "POSTIZ_POSTGRES_PASSWORD=${POSTIZ_POSTGRES_PASSWORD}"
echo "POSTIZ_JWT_SECRET=${POSTIZ_JWT_SECRET}"
echo "TEMPORAL_POSTGRES_PASSWORD=${TEMPORAL_POSTGRES_PASSWORD}"
echo ""
echo -e "${YW}PostgreSQL init script created at:${CL}"
echo "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"
echo ""
echo -e "${YW}It will run automatically only on the first startup of 02-postgres-compose.${CL}"
echo ""
echo -e "${YW}Optional Argon2 display for copying into apps that require hashes:${CL}"
echo "REDIS_PASSWORD_ARGON2=$(argon2_hash "$REDIS_PASSWORD")"
echo "POSTGRES_PASSWORD_ARGON2=$(argon2_hash "$POSTGRES_PASSWORD")"
echo "------------------------------------------------------"