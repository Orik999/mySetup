#!/usr/bin/env bash -ex
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Ubuntu VM Setup
#  Post-install bootstrap for Ubuntu Server VM/LXC.
#  Designed for Docker, Traefik, Authentik, PostgreSQL,
#  Redis, Portainer, Postiz and future SaaS workloads.
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
LOG_FILE="/var/log/ubuntu-vm-setup.log"

# --- 2. GLOBAL DEFAULTS ---
# Default user and Docker folder layout based on your saved env/Portainer structure.
DEFAULT_USER="orik"
DEFAULT_TZ="Europe/London"
DEFAULT_DOCKER_DIR="/home/orik/docker"
DEFAULT_SECRETS_DIR="/home/orik/docker/secrets"
SETUP_MARKER="/opt/ubuntu-vm-setup.done"

USERNAME=""
USER_HOME=""
DOCKER_DIR=""
DOCKER_SECRETS_DIR=""
SYSTEM_TYPE="Unknown"
IS_LXC="no"
IS_VM="no"
IS_SSD="no"
TOTAL_RAM_GB=0
TOTAL_CORES=0
ROOT_KEYS_FOUND="no"
USER_KEYS_READY="no"
SSH_HARDENING_APPLIED="no"
UBUNTU_PRO_ATTACHED="no"

# --- 3. HEADER & MESSAGING FUNCTIONS ---
# Shows one-line Ubuntu VM Setup title and provides reusable status helpers.
function header_info {
echo -e "${BL}
██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗    ██╗   ██╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ 
██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║    ██║   ██║████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║    ██║   ██║██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝
██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║    ╚██╗ ██╔╝██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝     ╚████╔╝ ██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     
 ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝       ╚═══╝  ╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
${CL}"
}

function msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 4. LOGGING & ERROR HANDLING ---
# Logs all script output and reports line number on failure.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 5. ROOT CHECK ---
# Requires root because this script edits users, SSH, apt, systemd and kernel settings.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root, for example: sudo bash ubuntu-vm-setup.sh${CL}"
    exit 1
fi

clear
header_info

# --- 6. HELPER FUNCTIONS ---
# Provides timed prompts and safe config editing helpers.
function timed_prompt() {
    local prompt="$1"
    local default="$2"
    local input=""
    read -t "$T" -p "$prompt" input || input="$default"
    [ -z "$input" ] && input="$default"
    echo "$input"
}

function set_or_append_space_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    touch "$file"
    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$file"; then
        sed -i -E "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
    else
        echo "${key} ${value}" >> "$file"
    fi
}

function set_or_append_equals_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    touch "$file"
    if grep -Eq "^[#[:space:]]*${key}=.*" "$file"; then
        sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# --- 7. PRE-INSTALL AUDIT ---
# Detects VM/LXC type, resources, SSD state and whether this looks already configured.
msg_info "Running system audit"

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

if lsblk -dn -o ROTA | grep -q "^0$"; then
    IS_SSD="yes"
fi

if [ -s /root/.ssh/authorized_keys ]; then
    ROOT_KEYS_FOUND="yes"
fi

msg_ok "SYSTEM AUDIT COMPLETE"

# --- 8. AUDIT DISPLAY ---
# Shows detected system details before changes are made.
echo ""
echo -e "${DGN}SYSTEM AUDIT:${CL}"
echo -e "SYSTEM TYPE: ${GN}${SYSTEM_TYPE}${CL}"
echo -e "TOTAL RAM: ${GN}${TOTAL_RAM_GB}GB${CL}"
echo -e "CPU CORES: ${GN}${TOTAL_CORES}${CL}"
echo -e "SSD DETECTED: ${GN}${IS_SSD}${CL}"
echo -e "ROOT SSH KEYS FOUND: ${GN}${ROOT_KEYS_FOUND}${CL}"
echo "------------------------------------------------------"

# --- 9. FRESH SYSTEM WARNING ---
# Warns if the setup marker exists or target user already exists.
if [ -f "$SETUP_MARKER" ]; then
    msg_error "Ubuntu VM Setup already appears completed on this system"
fi

if id "$DEFAULT_USER" >/dev/null 2>&1; then
    echo -e "${YW}User '${DEFAULT_USER}' already exists. This may not be a fresh system.${CL}"
    continue_existing=$(timed_prompt "Continue anyway? (y/N): " "n")
    [[ "$continue_existing" =~ ^[Yy] ]] || msg_error "Aborted"
fi

# --- 10. TIMED START ---
# Starts the script with default YES after timer.
echo -e "${YW} This script will configure Ubuntu VM/LXC for Docker-based services.${CL}"
yn=$(timed_prompt "Start Ubuntu VM Setup (Y/n)? " "y")
echo ""
[[ "$yn" =~ ^[Nn] ]] && exit

# --- 11. USER OPTIONS ---
# Lets user choose username, timezone and Docker paths with timed defaults.
USERNAME=$(timed_prompt "Enter main username (Default ${DEFAULT_USER}): " "$DEFAULT_USER")
[ -z "$USERNAME" ] && USERNAME="$DEFAULT_USER"

USER_HOME="/home/$USERNAME"

DEFAULT_DOCKER_DIR="/home/${USERNAME}/docker"
DEFAULT_SECRETS_DIR="/home/${USERNAME}/docker/secrets"

TZ_INPUT=$(timed_prompt "Enter timezone (Default ${DEFAULT_TZ}): " "$DEFAULT_TZ")
[ -z "$TZ_INPUT" ] && TZ_INPUT="$DEFAULT_TZ"

DOCKER_DIR=$(timed_prompt "Enter DOCKER_DIR (Default ${DEFAULT_DOCKER_DIR}): " "$DEFAULT_DOCKER_DIR")
[ -z "$DOCKER_DIR" ] && DOCKER_DIR="$DEFAULT_DOCKER_DIR"

DOCKER_SECRETS_DIR=$(timed_prompt "Enter DOCKER_SECRETS_DIR (Default ${DEFAULT_SECRETS_DIR}): " "$DEFAULT_SECRETS_DIR")
[ -z "$DOCKER_SECRETS_DIR" ] && DOCKER_SECRETS_DIR="$DEFAULT_SECRETS_DIR"

# --- 12. SSH KEY INPUT SAFETY ---
# Uses root authorized_keys if available. If missing, user can paste a public key. SSH hardening only happens if keys exist.
PUBKEY_INPUT=""

if [ "$ROOT_KEYS_FOUND" == "no" ]; then
    echo -e "${YW}No root SSH authorized_keys found.${CL}"
    PUBKEY_INPUT=$(timed_prompt "Paste SSH public key now or leave blank to skip SSH hardening: " "")
fi

# --- 13. OPTIONAL UBUNTU PRO TOKEN ---
# Optionally attaches Ubuntu Pro. Tracing is disabled while reading/using token.
UBUNTU_PRO_YN=$(timed_prompt "Attach Ubuntu Pro token? (y/N): " "n")

UBUNTU_PRO_TOKEN=""
if [[ "$UBUNTU_PRO_YN" =~ ^[Yy] ]]; then
    set +x
    read -s -t "$T" -p "Paste Ubuntu Pro token or leave blank to skip: " UBUNTU_PRO_TOKEN || UBUNTU_PRO_TOKEN=""
    echo ""
    set -x
fi

# --- 14. BASE PACKAGE UPDATE ---
# Updates Ubuntu, upgrades packages, and installs required base tools.
msg_info "Updating system and installing base packages"

apt update
DEBIAN_FRONTEND=noninteractive apt -y dist-upgrade

DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common \
    sudo \
    openssh-server \
    qemu-guest-agent \
    git \
    nano \
    vim \
    htop \
    btop \
    unzip \
    zip \
    jq \
    rsync \
    net-tools \
    dnsutils \
    iproute2 \
    lsof \
    tree \
    acl \
    fail2ban \
    unattended-upgrades

msg_ok "BASE SYSTEM UPDATED"

# --- 15. TIMEZONE CONFIGURATION ---
# Sets system timezone for logs, Docker containers and scheduled tasks.
msg_info "Setting timezone"

timedatectl set-timezone "$TZ_INPUT" || true

msg_ok "TIMEZONE SET TO $TZ_INPUT"

# --- 16. USER CREATION / USER NORMALIZATION ---
# Creates main sudo user if missing, or normalizes shell/groups if user already exists.
if ! id "$USERNAME" >/dev/null 2>&1; then
    msg_info "Creating user $USERNAME"

    useradd -m -s /bin/bash "$USERNAME"
    usermod -aG sudo "$USERNAME"

    msg_ok "USER $USERNAME CREATED"
else
    msg_info "Normalizing user $USERNAME"

    usermod -aG sudo "$USERNAME"
    chsh -s /bin/bash "$USERNAME" || true

    msg_ok "USER $USERNAME NORMALIZED"
fi

# --- 17. SSH KEY SETUP ---
# Copies root SSH keys or pasted key to the main user. This prevents lockout before SSH hardening.
msg_info "Configuring SSH keys for $USERNAME"

mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"
touch "$USER_HOME/.ssh/authorized_keys"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

if [ "$ROOT_KEYS_FOUND" == "yes" ]; then
    cat /root/.ssh/authorized_keys >> "$USER_HOME/.ssh/authorized_keys"
fi

if [ -n "$PUBKEY_INPUT" ]; then
    echo "$PUBKEY_INPUT" >> "$USER_HOME/.ssh/authorized_keys"
fi

sort -u "$USER_HOME/.ssh/authorized_keys" -o "$USER_HOME/.ssh/authorized_keys"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"

if [ -s "$USER_HOME/.ssh/authorized_keys" ]; then
    USER_KEYS_READY="yes"
fi

msg_ok "SSH KEYS CONFIGURED"

# --- 18. SSH HARDENING ---
# Disables password login and root login only if the target user has SSH keys.
if [ "$USER_KEYS_READY" == "yes" ]; then
    msg_info "Hardening SSH"

    mkdir -p /etc/ssh/sshd_config.d

    cat <<EOF > /etc/ssh/sshd_config.d/99-ubuntu-vm-setup.conf
# Ubuntu VM Setup SSH hardening
AddressFamily inet
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
X11Forwarding no
EOF

    sshd -t

    if systemctl list-unit-files | grep -q "^ssh.service"; then
        systemctl restart ssh
    else
        systemctl restart sshd
    fi

    SSH_HARDENING_APPLIED="yes"
    msg_ok "SSH SECURED"
else
    SSH_HARDENING_APPLIED="no"
    msg_warn "SSH hardening skipped because no user SSH key exists"
fi

# --- 19. QEMU GUEST AGENT ---
# Enables qemu-guest-agent in VM mode. Skips it in LXC where it is not needed.
if [ "$IS_LXC" == "no" ]; then
    msg_info "Enabling qemu-guest-agent"

    systemctl enable --now qemu-guest-agent &>/dev/null || true

    msg_ok "QEMU GUEST AGENT ENABLED"
else
    msg_warn "LXC detected, skipping qemu-guest-agent"
fi

# --- 20. DOCKER-READY DIRECTORY STRUCTURE ---
# Creates standard folders for future Docker Compose stacks, secrets, appdata and backups.
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

# --- 21. ENV TEMPLATE CREATION ---
# Creates a base .env file matching your saved Portainer/environment variable style.
msg_info "Creating base .env template"

cat <<EOF > "$DOCKER_DIR/.env"
# Ubuntu VM Setup environment
PUID="1000"
PGID="1000"
TZ="${TZ_INPUT}"
USERDIR="${USER_HOME}"
DOCKER_DIR="${DOCKER_DIR}"
DOCKER_SECRETS_DIR="${DOCKER_SECRETS_DIR}"
DOMAIN="najafov.co.uk"
CF_EMAIL="oriknj999@gmail.com"
CF_ZONEID=""
POSTGRES_PASSWORD=""
EOF

chown "$USERNAME:$USERNAME" "$DOCKER_DIR/.env"
chmod 600 "$DOCKER_DIR/.env"

msg_ok "BASE .env CREATED"

# --- 22. SSD TRIM / STORAGE OPTIMIZATION ---
# Enables fstrim on SSD-backed systems and applies sane VM storage memory tuning.
if [ "$IS_SSD" == "yes" ]; then
    msg_info "Enabling SSD TRIM"

    systemctl enable --now fstrim.timer &>/dev/null || true

    msg_ok "SSD TRIM ENABLED"
fi

msg_info "Applying VM storage tuning"

cat <<EOF > /etc/sysctl.d/99-ubuntu-vm-storage-tuning.conf
# Ubuntu VM storage tuning for Docker/database workloads
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

sysctl --system &>/dev/null || true

msg_ok "VM STORAGE TUNING APPLIED"

# --- 23. NETWORK / HIGH TRAFFIC TUNING ---
# Adds safe high-traffic tuning for reverse proxy, uploads, downloads and many connections.
msg_info "Applying network tuning"

cat <<EOF > /etc/sysctl.d/99-ubuntu-vm-network-tuning.conf
# Ubuntu VM network tuning for Docker reverse-proxy workloads
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1
EOF

sysctl --system &>/dev/null || true

msg_ok "NETWORK TUNING APPLIED"

# --- 24. FAIL2BAN BASIC SSH JAIL ---
# Enables basic SSH protection inside the VM. Main public protection still comes from Cloudflare/Traefik/CrowdSec later.
msg_info "Configuring fail2ban"
cat <<EOF > /etc/fail2ban/jail.d/sshd.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
maxretry = 5
bantime = 1h
findtime = 10m
EOF

systemctl enable --now fail2ban &>/dev/null || true
systemctl restart fail2ban &>/dev/null || true
msg_ok "FAIL2BAN CONFIGURED"

# --- FIREWALL BASICS ---
# Enables UFW baseline firewall for Docker VM. Allows SSH, HTTP and HTTPS only.
msg_info "Configuring basic firewall"
apt install -y ufw &>/dev/null

ufw --force reset &>/dev/null
ufw default deny incoming &>/dev/null
ufw default allow outgoing &>/dev/null

ufw allow 22/tcp comment 'SSH' &>/dev/null
ufw allow 80/tcp comment 'HTTP Traefik' &>/dev/null
ufw allow 443/tcp comment 'HTTPS Traefik' &>/dev/null

ufw --force enable &>/dev/null
msg_ok "BASIC FIREWALL ENABLED"

# --- 25. UNATTENDED UPGRADES ---
# Enables automatic security package update checks.
msg_info "Configuring unattended upgrades"

cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

systemctl enable --now unattended-upgrades &>/dev/null || true

msg_ok "UNATTENDED UPGRADES ENABLED"

# --- 26. OPTIONAL UBUNTU PRO ATTACH ---
# Attaches Ubuntu Pro only if a token was provided.
if [ -n "$UBUNTU_PRO_TOKEN" ]; then
    msg_info "Attaching Ubuntu Pro"

    set +x
    pro attach "$UBUNTU_PRO_TOKEN" >/dev/null 2>&1 && UBUNTU_PRO_ATTACHED="yes" || UBUNTU_PRO_ATTACHED="no"
    set -x

    if [ "$UBUNTU_PRO_ATTACHED" == "yes" ]; then
        msg_ok "UBUNTU PRO ATTACHED"
    else
        msg_warn "Ubuntu Pro attach failed or was skipped"
    fi
fi

# --- 27. CLEANUP ---
# Cleans apt cache and removes unused packages.
msg_info "Cleaning packages"

apt clean
apt -y autoremove

msg_ok "SYSTEM CLEANED"

# --- 28. SETUP MARKER ---
# Writes a marker file documenting completed setup details.
msg_info "Writing setup marker"

mkdir -p /opt

cat <<EOF > "$SETUP_MARKER"
Ubuntu VM Setup completed: $(date)
User: $USERNAME
System type: $SYSTEM_TYPE
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
SSH hardening applied: $SSH_HARDENING_APPLIED
Ubuntu Pro attached: $UBUNTU_PRO_ATTACHED
EOF

msg_ok "SETUP MARKER WRITTEN"

# --- 29. FINAL SUMMARY ---
# Displays final status and recommends reboot/poweroff based on VM/LXC type.
echo ""
echo -e "${GN}UBUNTU VM SETUP COMPLETE!${CL}"
echo "------------------------------------------------------"
echo -e "SYSTEM TYPE: ${GN}${SYSTEM_TYPE}${CL}"
echo -e "USER: ${GN}${USERNAME}${CL}"
echo -e "SSH HARDENING: ${GN}${SSH_HARDENING_APPLIED}${CL}"
echo -e "DOCKER DIR: ${GN}${DOCKER_DIR}${CL}"
echo -e "SECRETS DIR: ${GN}${DOCKER_SECRETS_DIR}${CL}"
echo -e "SSD TRIM: ${GN}${IS_SSD}${CL}"
echo -e "QEMU AGENT: ${GN}$([ "$IS_LXC" == "no" ] && echo "enabled" || echo "skipped")${CL}"
echo -e "FIREWALL: ${GN}UFW enabled, ports 22/80/443 allowed${CL}"
echo -e "UBUNTU PRO: ${GN}${UBUNTU_PRO_ATTACHED}${CL}"
echo "------------------------------------------------------"
echo -e "${YW}Next script should install Docker Engine and Docker Compose plugin.${CL}"
echo ""

# --- 30. REBOOT / POWEROFF ---
# Reboots by default after 30 seconds. User can cancel with Ctrl+C.
echo -e "${GN}REBOOTING IN 30 SECONDS...${CL}"
echo -e "${YW}Press Ctrl+C now to cancel automatic reboot.${CL}"
sleep 30
reboot