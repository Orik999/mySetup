#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker Setup
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
LOG_FILE="/var/log/docker-setup.log"
COMPLETED_MARKER="/root/.docker-setup-completed"

TARGET_USER="${SUDO_USER:-$USER}"
DISABLE_SWAP="y"
INSTALL_DOCKER_GC="n"
DOCKER_FIREWALL_MODE="enabled"

# --- 3. HEADER FUNCTION ---
# Displays the one-line Docker Setup banner.
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

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent status messages.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. LOGGING & ERROR HANDLING ---
# Logs output and reports failing line.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

clear
header_info

# --- 6. TTY OUTPUT HELPER ---
# Prints directly to terminal from prompt functions.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 7. TTY OUTPUT WITH NEWLINE HELPER ---
# Prints directly to terminal with newline.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 8. YES/NO LABEL HELPER ---
# Converts Y/N answers to visible yes/no.
function yes_no_label() {
    local value="$1"
    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 9. BLOCKING YES/NO HELPER ---
# SPACE pauses countdown and waits for Y/N/ENTER.
function tty_read_yes_no_blocking() {
    local prompt="$1"
    local default="$2"
    local default_label="Y/n"
    local key=""

    if [[ "$default" =~ ^[Nn]$ ]]; then
        default_label="y/N"
    fi

    while true; do
        tty_print "${BFR}${YW}${prompt} (${default_label}) [timer stopped - press Y/N or ENTER for default]${CL} "
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

# --- 10. TIMED YES/NO PROMPT HELPER ---
# SPACE pauses and waits. Timeout uses default. Final answer stays visible.
function timed_yes_no() {
    local prompt="$1"
    local default="$2"
    local answer=""
    local key=""
    local default_label="Y/n"
    local final_label=""

    if [[ "$default" =~ ^[Nn]$ ]]; then
        default_label="y/N"
    fi

    for ((i=T; i>0; i--)); do
        tty_print "${BFR}${YW}${prompt} (${default_label}) [${i}s]${CL} "

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

# --- 11. ROOT / SUDO DETECTION ---
# Uses sudo when not root.
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# --- 12. START CONFIRMATION ---
# Starts Docker installation.
echo -e "${YW}This script will install and configure Docker Engine, Docker CLI, containerd, Compose plugin and Buildx plugin.${CL}"
start_yn=$(timed_yes_no "Start the Docker Setup Script?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 13. USER OPTIONS ---
# Lets user decide swap behaviour and optional docker-gc install.
swap_yn=$(timed_yes_no "Disable swap in /etc/fstab?" "y")
[[ "$swap_yn" =~ ^[Nn] ]] && DISABLE_SWAP="n" || DISABLE_SWAP="y"

gc_yn=$(timed_yes_no "Install docker-gc cleanup helper?" "n")
[[ "$gc_yn" =~ ^[Yy] ]] && INSTALL_DOCKER_GC="y" || INSTALL_DOCKER_GC="n"

# --- 14. SWAP HANDLING ---
# Disables swap for Docker/database stability if selected.
if [ "$DISABLE_SWAP" == "y" ]; then
    msg_info "Disabling swap"

    $SUDO_CMD swapoff -a &>/dev/null || true
    $SUDO_CMD sed -i '/[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab

    msg_ok "SWAP DISABLED"
fi

# --- 15. DEPENDENCY INSTALL ---
# Installs packages needed to add Docker's official Ubuntu repository.
msg_info "Installing dependencies"

$SUDO_CMD apt-get update &>/dev/null
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    acl \
    ufw \
    &>/dev/null

msg_ok "DEPENDENCIES INSTALLED"

# --- 16. DOCKER REPOSITORY SETUP ---
# Adds Docker's official GPG key and apt repository using modern keyring layout.
msg_info "Adding Docker repository"

$SUDO_CMD install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO_CMD gpg --dearmor -o /etc/apt/keyrings/docker.gpg
$SUDO_CMD chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
$SUDO_CMD tee /etc/apt/sources.list.d/docker.list >/dev/null

msg_ok "DOCKER REPOSITORY ADDED"

# --- 17. DOCKER INSTALL ---
# Installs Docker Engine, CLI, containerd, Docker Compose plugin and Buildx plugin.
msg_info "Installing Docker"

$SUDO_CMD apt-get update &>/dev/null
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    &>/dev/null

$SUDO_CMD systemctl enable --now docker &>/dev/null
$SUDO_CMD systemctl enable --now containerd &>/dev/null

msg_ok "DOCKER INSTALLED"

# --- 18. DOCKER GROUP SETUP ---
# Adds the target user to the docker group for non-root Docker CLI usage after next login.
msg_info "Adding user ${TARGET_USER} to docker group"

$SUDO_CMD usermod -aG docker "$TARGET_USER" &>/dev/null || true

msg_ok "USER ADDED TO DOCKER GROUP"

# --- 19. DOCKER FIREWALL MODE ---
# Keeps Docker iptables enabled so Docker networking, NAT and published ports work correctly.
msg_info "Configuring Docker firewall mode"

$SUDO_CMD mkdir -p /etc/docker

cat <<EOF | $SUDO_CMD tee /etc/docker/daemon.json >/dev/null
{
  "iptables": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF

$SUDO_CMD systemctl restart docker &>/dev/null

msg_ok "DOCKER FIREWALL MODE CONFIGURED"

# --- 20. UFW BASELINE ---
# Allows SSH, HTTP and HTTPS on the Ubuntu VM.
msg_info "Configuring UFW firewall"

$SUDO_CMD ufw default deny incoming &>/dev/null || true
$SUDO_CMD ufw default allow outgoing &>/dev/null || true
$SUDO_CMD ufw allow OpenSSH &>/dev/null || true
$SUDO_CMD ufw allow 80/tcp &>/dev/null || true
$SUDO_CMD ufw allow 443/tcp &>/dev/null || true
$SUDO_CMD ufw --force enable &>/dev/null || true

msg_ok "UFW FIREWALL CONFIGURED"

# --- 21. DOCKER-GC OPTIONAL INSTALL ---
# Creates a simple safe Docker cleanup helper instead of aggressive automatic pruning.
if [ "$INSTALL_DOCKER_GC" == "y" ]; then
    msg_info "Installing docker-gc helper"

    cat <<'EOF' | $SUDO_CMD tee /usr/local/sbin/docker-gc-safe >/dev/null
#!/usr/bin/env bash
set -euo pipefail
docker system prune -f
docker image prune -f
docker builder prune -f --filter "until=168h"
EOF

    $SUDO_CMD chmod +x /usr/local/sbin/docker-gc-safe

    msg_ok "DOCKER-GC HELPER INSTALLED"
fi

# --- 22. VERIFY INSTALL ---
# Checks Docker and Compose versions.
msg_info "Verifying Docker installation"

docker --version >/dev/null
docker compose version >/dev/null

msg_ok "DOCKER VERIFIED"

# --- 23. COMPLETION MARKER ---
# Creates marker showing setup completed.
$SUDO_CMD bash -c "cat > '$COMPLETED_MARKER'" <<EOF
Docker Setup completed on: $(date)
Target user: $TARGET_USER
Swap disabled: $DISABLE_SWAP
Docker GC helper: $INSTALL_DOCKER_GC
EOF

# --- 24. FINAL SUMMARY ---
# Displays installed versions and logout/reboot reminder.
echo ""
echo -e "${GN}FINISHED!${CL}"
docker --version
docker compose version
echo ""
echo -e "${YW}Log out and back in, or reboot, for docker group membership to apply.${CL}"
echo ""

exit 0