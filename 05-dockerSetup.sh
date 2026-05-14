#!/usr/bin/env bash -ex
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker Setup
#  Installs Docker Engine, Docker Compose plugin, Buildx,
#  Docker-ready folders, daemon tuning, logging limits,
#  and SaaS/self-hosting defaults.
# =========================================================

# --- 1. COLOR VARIABLES (RESTORED ALL) ---
YW=`echo "\033[33m"`
BL=`echo "\033[36m"`
RD=`echo "\033[01;31m"`
BGN=`echo "\033[4;92m"`
GN=`echo "\033[1;92m"`
DGN=`echo "\033[32m"`
CL=`echo "\033[m"`
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

T=15
LOG_FILE="/var/log/docker-setup.log"

# --- 2. GLOBAL DEFAULTS ---
# These defaults match your saved Portainer .env layout and Ubuntu VM Setup.
DEFAULT_USER="orik"
DEFAULT_TZ="Europe/London"
DEFAULT_DOMAIN="najafov.co.uk"
DEFAULT_DOCKER_DIR="/home/orik/docker"
DEFAULT_SECRETS_DIR="/home/orik/docker/secrets"
SETUP_MARKER="/opt/docker-setup.done"

USERNAME=""
USER_HOME=""
DOCKER_DIR=""
DOCKER_SECRETS_DIR=""
TZ_INPUT=""
DOMAIN_INPUT=""
INSTALL_LAZYWATCH="n"
INSTALL_DOCKER_GC="n"
ENABLE_LIVE_RESTORE="y"
ENABLE_IPV6="n"
TOTAL_RAM_GB=0
TOTAL_CORES=0
IS_LXC="no"
IS_VM="no"
SYSTEM_TYPE="Unknown"
UBUNTU_CODENAME=""
ARCH=""

# --- 3. HEADER & MESSAGING FUNCTIONS ---
# Shows the Docker Setup ASCII banner and gives reusable status helpers.
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

function msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 4. LOGGING & ERROR HANDLING ---
# Logs all output and prints useful failure line info.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 5. ROOT CHECK ---
# Docker install needs root because it adds repos, packages, groups and daemon config.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root, for example: sudo bash docker-setup.sh${CL}"
    exit 1
fi

clear
header_info

# --- 6. HELPER FUNCTIONS ---
# Provides timed prompts and simple validation helpers.
function timed_prompt() {
    local prompt="$1"
    local default="$2"
    local input=""
    read -t "$T" -p "$prompt" input || input="$default"
    [ -z "$input" ] && input="$default"
    echo "$input"
}

function is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

# --- 7. SYSTEM AUDIT ---
# Detects Ubuntu version, architecture, VM/LXC type and basic host resources.
msg_info "Running system audit"

if [ ! -f /etc/os-release ]; then
    msg_error "Cannot detect OS. /etc/os-release missing."
fi

. /etc/os-release

if [ "${ID:-}" != "ubuntu" ]; then
    msg_error "This script is intended for Ubuntu only"
fi

UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [ -z "$UBUNTU_CODENAME" ]; then
    msg_error "Could not detect Ubuntu codename"
fi

ARCH="$(dpkg --print-architecture)"

if grep -qa container=lxc /proc/1/environ 2>/dev/null; then
    IS_LXC="yes"
    SYSTEM_TYPE="LXC Container"
elif command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet; then
    IS_VM="yes"
    SYSTEM_TYPE="Virtual Machine"
else
    SYSTEM_TYPE="Bare Metal / Unknown"
fi

TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
[ "$TOTAL_RAM_GB" -lt 1 ] && TOTAL_RAM_GB=1

TOTAL_CORES=$(nproc)
[ "$TOTAL_CORES" -lt 1 ] && TOTAL_CORES=1

msg_ok "SYSTEM AUDIT COMPLETE"

# --- 8. AUDIT DISPLAY ---
# Shows system state before Docker install.
echo ""
echo -e "${DGN}SYSTEM AUDIT:${CL}"
echo -e "SYSTEM TYPE: ${GN}${SYSTEM_TYPE}${CL}"
echo -e "UBUNTU VERSION: ${GN}${VERSION_ID:-unknown} (${UBUNTU_CODENAME})${CL}"
echo -e "ARCHITECTURE: ${GN}${ARCH}${CL}"
echo -e "TOTAL RAM: ${GN}${TOTAL_RAM_GB}GB${CL}"
echo -e "CPU CORES: ${GN}${TOTAL_CORES}${CL}"
echo "------------------------------------------------------"

# --- 9. EXISTING INSTALL DETECTION ---
# Detects previous Docker installs and asks before continuing.
if [ -f "$SETUP_MARKER" ]; then
    msg_warn "Docker Setup marker already exists"
fi

if command -v docker >/dev/null 2>&1; then
    echo -e "${YW}Docker already appears installed:${CL}"
    docker --version || true
    continue_existing=$(timed_prompt "Continue and repair/update Docker install? (Y/n): " "y")
    [[ "$continue_existing" =~ ^[Nn] ]] && exit
fi

# --- 10. TIMED START ---
# Starts Docker setup with default YES.
echo -e "${YW} This script will install and configure Docker Engine + Docker Compose plugin.${CL}"
yn=$(timed_prompt "Start Docker Setup (Y/n)? " "y")
echo ""
[[ "$yn" =~ ^[Nn] ]] && exit

# --- 11. USER OPTIONS ---
# Lets user confirm main user, timezone, domain and Docker folder paths.
USERNAME=$(timed_prompt "Enter main username (Default ${DEFAULT_USER}): " "$DEFAULT_USER")
[ -z "$USERNAME" ] && USERNAME="$DEFAULT_USER"

if ! id "$USERNAME" >/dev/null 2>&1; then
    msg_error "User '$USERNAME' does not exist. Run Ubuntu VM Setup first or create the user."
fi

USER_HOME=$(eval echo "~$USERNAME")

DEFAULT_DOCKER_DIR="${USER_HOME}/docker"
DEFAULT_SECRETS_DIR="${USER_HOME}/docker/secrets"

TZ_INPUT=$(timed_prompt "Enter timezone (Default ${DEFAULT_TZ}): " "$DEFAULT_TZ")
DOMAIN_INPUT=$(timed_prompt "Enter domain (Default ${DEFAULT_DOMAIN}): " "$DEFAULT_DOMAIN")
DOCKER_DIR=$(timed_prompt "Enter DOCKER_DIR (Default ${DEFAULT_DOCKER_DIR}): " "$DEFAULT_DOCKER_DIR")
DOCKER_SECRETS_DIR=$(timed_prompt "Enter DOCKER_SECRETS_DIR (Default ${DEFAULT_SECRETS_DIR}): " "$DEFAULT_SECRETS_DIR")

ENABLE_LIVE_RESTORE=$(timed_prompt "Enable Docker live-restore? (Y/n): " "y")
[[ "$ENABLE_LIVE_RESTORE" =~ ^[Nn] ]] && ENABLE_LIVE_RESTORE="n" || ENABLE_LIVE_RESTORE="y"

ENABLE_IPV6=$(timed_prompt "Enable Docker IPv6? (y/N): " "n")
[[ "$ENABLE_IPV6" =~ ^[Yy] ]] && ENABLE_IPV6="y" || ENABLE_IPV6="n"

INSTALL_DOCKER_GC=$(timed_prompt "Install docker-gc cleanup helper later? (y/N): " "n")
[[ "$INSTALL_DOCKER_GC" =~ ^[Yy] ]] && INSTALL_DOCKER_GC="y" || INSTALL_DOCKER_GC="n"

# --- 12. SWAP WARNING / SAFE HANDLING ---
# Does not blindly disable swap. Warns and leaves it alone unless user chooses.
if swapon --show | grep -q .; then
    echo -e "${YW}Swap is currently active.${CL}"
    swap_yn=$(timed_prompt "Disable swap now and comment it in /etc/fstab? (y/N): " "n")
    if [[ "$swap_yn" =~ ^[Yy] ]]; then
        msg_info "Disabling swap"
        swapoff -a || true
        sed -i.bak '/[[:space:]]swap[[:space:]]/ s/^\(.*\)$/#\1/g' /etc/fstab
        msg_ok "SWAP DISABLED"
    else
        msg_warn "Swap left enabled"
    fi
fi

# --- 13. BASE DEPENDENCIES ---
# Installs packages required for Docker official repo and future Docker workflows.
msg_info "Installing dependencies"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    acl \
    jq \
    git \
    unzip

msg_ok "DEPENDENCIES INSTALLED"

# --- 14. REMOVE CONFLICTING DOCKER PACKAGES ---
# Removes distro/old conflicting packages before installing Docker CE.
msg_info "Removing conflicting Docker packages"

for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

msg_ok "CONFLICTING PACKAGES REMOVED"

# --- 15. DOCKER OFFICIAL APT REPOSITORY ---
# Adds Docker official repository using modern /etc/apt/keyrings path.
msg_info "Adding Docker official repository"

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat <<EOF > /etc/apt/sources.list.d/docker.list
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF

apt-get update

msg_ok "DOCKER REPOSITORY ADDED"

# --- 16. DOCKER ENGINE / COMPOSE / BUILDX INSTALL ---
# Installs latest Docker Engine, CLI, containerd, Buildx and Compose plugin from Docker repo.
msg_info "Installing Docker Engine and plugins"

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

msg_ok "DOCKER ENGINE AND PLUGINS INSTALLED"

# --- 17. DOCKER GROUP / USER ACCESS ---
# Adds your main user to docker group so sudo is not needed after next login.
msg_info "Adding $USERNAME to docker group"

groupadd -f docker
usermod -aG docker "$USERNAME"

msg_ok "USER ADDED TO DOCKER GROUP"

# --- 18. DOCKER DIRECTORY STRUCTURE ---
# Creates standard folders used by your Portainer/Docker Compose project.
msg_info "Creating Docker directory structure"

mkdir -p "$DOCKER_DIR"
mkdir -p "$DOCKER_DIR/appdata"
mkdir -p "$DOCKER_DIR/compose"
mkdir -p "$DOCKER_DIR/backups"
mkdir -p "$DOCKER_DIR/shared"
mkdir -p "$DOCKER_SECRETS_DIR"

chmod 700 "$DOCKER_SECRETS_DIR"
chown -R "$USERNAME:$USERNAME" "$DOCKER_DIR"

msg_ok "DOCKER FOLDERS CREATED"

# --- 19. DOCKER DAEMON CONFIGURATION ---
# Configures Docker logging limits, live-restore and sane defaults. Does not disable iptables.
msg_info "Configuring Docker daemon"

mkdir -p /etc/docker

if [ "$ENABLE_LIVE_RESTORE" == "y" ]; then
    LIVE_RESTORE_JSON='true'
else
    LIVE_RESTORE_JSON='false'
fi

if [ "$ENABLE_IPV6" == "y" ]; then
    IPV6_BLOCK='
  "ipv6": true,
  "fixed-cidr-v6": "fd00:dead:beef::/64",'
else
    IPV6_BLOCK=''
fi

cat <<EOF > /etc/docker/daemon.json
{
  "live-restore": ${LIVE_RESTORE_JSON},
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  },${IPV6_BLOCK}
  "default-address-pools": [
    {
      "base": "172.30.0.0/16",
      "size": 24
    },
    {
      "base": "172.31.0.0/16",
      "size": 24
    }
  ]
}
EOF

msg_ok "DOCKER DAEMON CONFIGURED"

# --- 20. SYSTEMD OVERRIDE ---
# Ensures Docker starts after network-online target.
msg_info "Creating Docker systemd override"

mkdir -p /etc/systemd/system/docker.service.d

cat <<EOF > /etc/systemd/system/docker.service.d/override.conf
[Unit]
After=network-online.target
Wants=network-online.target
EOF

systemctl daemon-reload

msg_ok "DOCKER SYSTEMD OVERRIDE CREATED"

# --- 21. FIREWALL / IPTABLES NOTE ---
# Keeps Docker iptables enabled. Disabling it commonly breaks Docker networking.
msg_warn "Docker iptables remains enabled. This is intentional for normal Docker networking."

# --- 22. ENV FILE UPDATE ---
# Creates or updates the base .env file in your Docker directory.
msg_info "Creating Docker .env template"

cat <<EOF > "$DOCKER_DIR/.env"
# Docker Setup environment
PUID="1000"
PGID="1000"
TZ="${TZ_INPUT}"
USERDIR="${USER_HOME}"
DOCKER_DIR="${DOCKER_DIR}"
DOCKER_SECRETS_DIR="${DOCKER_SECRETS_DIR}"
DOMAIN="${DOMAIN_INPUT}"
CF_EMAIL="oriknj999@gmail.com"
CF_ZONEID=""
POSTGRES_PASSWORD=""
EOF

chown "$USERNAME:$USERNAME" "$DOCKER_DIR/.env"
chmod 600 "$DOCKER_DIR/.env"

msg_ok "DOCKER .env CREATED"

# --- 23. DOCKER SERVICE ENABLE / START ---
# Enables and starts Docker/containerd.
msg_info "Enabling and starting Docker"

systemctl enable --now containerd
systemctl enable --now docker
systemctl restart docker

msg_ok "DOCKER ENABLED AND STARTED"

# --- 24. OPTIONAL docker-gc PLACEHOLDER ---
# Creates a cleanup folder only. Actual docker-gc compose/service can be deployed later with your stack.
if [ "$INSTALL_DOCKER_GC" == "y" ]; then
    msg_info "Preparing docker-gc folder"

    mkdir -p "$DOCKER_DIR/compose/docker-gc"
    chown -R "$USERNAME:$USERNAME" "$DOCKER_DIR/compose/docker-gc"

    msg_ok "DOCKER-GC FOLDER READY"
fi

# --- 25. VERIFY INSTALLATION ---
# Verifies Docker, Compose plugin and Buildx.
msg_info "Verifying Docker installation"

docker --version >/dev/null
docker compose version >/dev/null
docker buildx version >/dev/null

msg_ok "DOCKER VERIFIED"

# --- 26. TEST CONTAINER ---
# Runs hello-world to verify Docker can pull and run containers.
msg_info "Running Docker test container"

docker run --rm hello-world >/dev/null

msg_ok "DOCKER TEST PASSED"

# --- 27. CLEANUP ---
# Cleans apt cache and removes unused packages.
msg_info "Cleaning packages"

apt-get clean
apt-get -y autoremove

msg_ok "SYSTEM CLEANED"

# --- 28. SETUP MARKER ---
# Writes a marker documenting Docker install details.
msg_info "Writing setup marker"

mkdir -p /opt

cat <<EOF > "$SETUP_MARKER"
Docker Setup completed: $(date)
User: $USERNAME
System type: $SYSTEM_TYPE
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_INPUT
Live restore: $ENABLE_LIVE_RESTORE
IPv6: $ENABLE_IPV6
Docker version: $(docker --version)
Compose version: $(docker compose version)
Buildx version: $(docker buildx version)
EOF

msg_ok "SETUP MARKER WRITTEN"

# --- 29. FINAL SUMMARY ---
# Shows final Docker installation status.
echo ""
echo -e "${GN}DOCKER SETUP COMPLETE!${CL}"
echo "------------------------------------------------------"
echo -e "SYSTEM TYPE: ${GN}${SYSTEM_TYPE}${CL}"
echo -e "USER: ${GN}${USERNAME}${CL}"
echo -e "DOCKER DIR: ${GN}${DOCKER_DIR}${CL}"
echo -e "SECRETS DIR: ${GN}${DOCKER_SECRETS_DIR}${CL}"
echo -e "DOMAIN: ${GN}${DOMAIN_INPUT}${CL}"
echo -e "LIVE RESTORE: ${GN}${ENABLE_LIVE_RESTORE}${CL}"
echo -e "DOCKER IPV6: ${GN}${ENABLE_IPV6}${CL}"
echo -e "DOCKER: ${GN}$(docker --version)${CL}"
echo -e "COMPOSE: ${GN}$(docker compose version)${CL}"
echo -e "BUILDX: ${GN}$(docker buildx version)${CL}"
echo "------------------------------------------------------"
echo -e "${YW}Important: user '$USERNAME' must log out/in or reboot for docker group permissions to apply.${CL}"
echo -e "${YW}Next step: deploy Traefik, PostgreSQL, Redis, Authentik, Portainer, and Postiz stacks.${CL}"
echo ""

# --- 30. REBOOT COUNTDOWN ---
# Reboots by default so Docker group membership and services settle cleanly.
echo -e "${GN}REBOOTING IN 30 SECONDS...${CL}"
echo -e "${YW}Press Ctrl+C now to cancel automatic reboot.${CL}"
sleep 30
reboot