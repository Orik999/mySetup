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
REBOOT_T=30
LOG_FILE="/var/log/docker-setup.log"
COMPLETED_MARKER="/root/.docker-setup-completed"

SUDO_CMD=""
TARGET_USER="${SUDO_USER:-${USER:-orik}}"
DISABLE_SWAP="y"
INSTALL_DOCKER_GC="n"
DOCKER_FIREWALL_MODE="enabled"
EXISTING_SETUP="no"

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

# --- 5. ROOT / SUDO VALIDATION ---
# Allows running as the normal Ubuntu VM user, validates sudo once, and then uses sudo for privileged writes.
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"

    echo -e "${YW}Sudo privileges are required for Docker Setup.${CL}"

    if ! sudo -v; then
        echo -e "${RD}ERROR:${CL} Sudo authentication failed."
        exit 1
    fi
fi

# --- 6. LOGGING & ERROR HANDLING ---
# Logs output and reports failing line. Uses sudo tee when not running as root.
if [ -n "$SUDO_CMD" ]; then
    exec > >($SUDO_CMD tee -a "$LOG_FILE") 2>&1
else
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

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

# --- 9. RAW KEY READ HELPER ---
# Reads exactly one character from the active terminal.
# This separates real ENTER/SPACE input from timeout, fixing double-press issues.
function read_key_timeout() {
    local timeout="$1"
    local __resultvar="$2"
    local key=""

    if [ -r /dev/tty ]; then
        if IFS= read -rsN1 -t "$timeout" key < /dev/tty; then
            printf -v "$__resultvar" '%s' "$key"
            return 0
        fi
    else
        if IFS= read -rsN1 -t "$timeout" key; then
            printf -v "$__resultvar" '%s' "$key"
            return 0
        fi
    fi

    printf -v "$__resultvar" ''
    return 1
}

# --- 10. RAW BLOCKING KEY READ HELPER ---
# Reads exactly one character with no timeout.
# Used after SPACE pauses countdown prompts.
function read_key_blocking() {
    local __resultvar="$1"
    local key=""

    if [ -r /dev/tty ]; then
        IFS= read -rsN1 key < /dev/tty || true
    else
        IFS= read -rsN1 key || true
    fi

    printf -v "$__resultvar" '%s' "$key"
}

# --- 11. YES/NO LABEL HELPER ---
# Converts Y/N answers to visible yes/no.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 12. BLOCKING YES/NO HELPER ---
# SPACE pauses countdown and waits for Y/N/ENTER. ENTER accepts default.
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
        read_key_blocking key

        case "$key" in
            $'\n'|$'\r')
                tty_print "${BFR}"
                echo "$default"
                return 0
                ;;
            [YyNn])
                tty_print "${BFR}"
                echo "$key"
                return 0
                ;;
        esac
    done
}

# --- 13. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown. SPACE pauses and waits. Timeout accepts default. Final answer stays visible.
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

        if read_key_timeout 1 key; then
            case "$key" in
                " ")
                    answer="$(tty_read_yes_no_blocking "$prompt" "$default")"
                    break
                    ;;
                $'\n'|$'\r')
                    answer="$default"
                    break
                    ;;
                [YyNn])
                    answer="$key"
                    break
                    ;;
            esac
        fi
    done

    [ -z "$answer" ] && answer="$default"
    final_label="$(yes_no_label "$answer")"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${final_label}${CL}"

    echo "$answer"
}

# --- 14. BLOCKING EDITABLE TEXT INPUT HELPER ---
# Used when user starts typing or presses SPACE during text input.
# The countdown disappears and the user can edit normally. ENTER accepts typed value or default.
function tty_read_text_blocking() {
    local prompt="$1"
    local default="$2"
    local buffer="${3:-}"
    local key=""

    while true; do
        tty_print "${BFR}${YW}${prompt} [default: ${default}]: ${CL}${buffer}"
        read_key_blocking key

        case "$key" in
            $'\n'|$'\r')
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

# --- 15. TIMED TEXT INPUT HELPER ---
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

        if read_key_timeout 1 key; then
            case "$key" in
                " ")
                    answer="$(tty_read_text_blocking "$prompt" "$default" "")"
                    break
                    ;;
                $'\n'|$'\r')
                    answer="$default"
                    break
                    ;;
                *)
                    answer="$(tty_read_text_blocking "$prompt" "$default" "$key")"
                    break
                    ;;
            esac
        fi
    done

    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"

    echo "$answer"
}

# --- 16. REBOOT COUNTDOWN HELPER ---
# Shows a two-line wall-clock reboot countdown without creating a new line every second.
# ENTER/Y = reboot immediately.
# SPACE/N = stop countdown and do not reboot.
# Timeout = reboot automatically.
function timed_reboot_countdown() {
    local seconds="$1"
    local key=""
    local deadline=""
    local now=""
    local remaining=""
    local first_draw="yes"

    deadline=$(( $(date +%s) + seconds ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            if [ "$first_draw" == "no" ]; then
                tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
            fi
            return 0
        fi

        if [ "$first_draw" == "yes" ]; then
            first_draw="no"
        else
            tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
        fi

        tty_print "${BL}${CLF}REBOOTING IN ${remaining} SECONDS...${CL}\n${YW}(ENTER/Y = Reboot Now, SPACE/N = Cancel)${CL}\n"

        if read_key_timeout 1 key; then
            case "$key" in
                $'\n'|$'\r'|[Yy])
                    tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                    tty_println "${BL}${CLF}REBOOTING NOW...${CL}"
                    return 0
                    ;;
                " "|[Nn])
                    tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                    tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                    return 1
                    ;;
            esac
        fi
    done
}

# --- 17. SUDO PATH EXISTS HELPER ---
# Checks whether a path exists, using sudo when required.
function sudo_path_exists() {
    local path="$1"
    $SUDO_CMD test -e "$path"
}

# --- 18. START CONFIRMATION ---
# Starts Docker installation.
echo -e "${YW}This script will install and configure Docker Engine, Docker CLI, containerd, Compose plugin and Buildx plugin.${CL}"
start_yn=$(timed_yes_no "Start the Docker Setup Script?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 19. EXISTING SETUP DETECTION ---
# Detects existing Docker install or completion marker before applying changes.
msg_info "Checking for existing Docker setup"

if command -v docker >/dev/null 2>&1 || sudo_path_exists "$COMPLETED_MARKER" || sudo_path_exists "/etc/docker/daemon.json"; then
    EXISTING_SETUP="yes"
fi

if [ "$EXISTING_SETUP" == "yes" ]; then
    msg_warn "Existing Docker setup detected"
    echo ""
    echo -e "${RD}WARNING: Existing Docker setup detected.${CL}"
    echo -e "${YW}The script is mostly safe to rerun, but it can update packages, rewrite Docker daemon settings, and reapply firewall rules.${CL}"
    echo ""

    continue_existing_yn=$(timed_yes_no "Continue with existing Docker setup?" "n")

    if [[ "$continue_existing_yn" =~ ^[Nn] ]]; then
        echo -e "${YW}Docker Setup cancelled. Existing files were left untouched.${CL}"
        exit 0
    fi
else
    msg_ok "NO EXISTING DOCKER SETUP DETECTED"
fi

# --- 20. USER OPTIONS ---
# Lets user confirm target user, swap behaviour and optional docker-gc install.
TARGET_USER=$(timed_text_input "Enter Linux user to add to docker group" "$TARGET_USER")

swap_yn=$(timed_yes_no "Disable swap in /etc/fstab?" "y")
[[ "$swap_yn" =~ ^[Nn] ]] && DISABLE_SWAP="n" || DISABLE_SWAP="y"

gc_yn=$(timed_yes_no "Install docker-gc cleanup helper?" "n")
[[ "$gc_yn" =~ ^[Yy] ]] && INSTALL_DOCKER_GC="y" || INSTALL_DOCKER_GC="n"

# --- 21. SWAP HANDLING ---
# Disables swap for Docker/database stability if selected.
if [ "$DISABLE_SWAP" == "y" ]; then
    msg_info "Disabling swap"

    msg_info "Turning off active swap"
    $SUDO_CMD swapoff -a &>/dev/null || true
    msg_ok "ACTIVE SWAP TURNED OFF"

    msg_info "Commenting swap entries in /etc/fstab"
    $SUDO_CMD sed -i '/[[:space:]]swap[[:space:]]/ s/^/#/' /etc/fstab
    msg_ok "FSTAB SWAP ENTRIES DISABLED"

    msg_ok "SWAP DISABLED"
else
    msg_ok "SWAP LEFT ENABLED"
fi

# --- 22. DEPENDENCY INSTALL ---
# Installs packages needed to add Docker's official Ubuntu repository.
msg_info "Installing dependencies"

msg_info "Updating APT package lists"
$SUDO_CMD apt-get update &>/dev/null
msg_ok "APT PACKAGE LISTS UPDATED"

msg_info "Installing Docker repository dependencies"
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    acl \
    ufw \
    &>/dev/null
msg_ok "DOCKER REPOSITORY DEPENDENCIES INSTALLED"

msg_ok "DEPENDENCIES INSTALLED"

# --- 23. DOCKER REPOSITORY SETUP ---
# Adds Docker's official GPG key and apt repository using modern keyring layout.
msg_info "Adding Docker repository"

msg_info "Creating APT keyrings directory"
$SUDO_CMD install -m 0755 -d /etc/apt/keyrings
msg_ok "APT KEYRINGS DIRECTORY READY"

msg_info "Installing Docker GPG key"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO_CMD gpg --dearmor -o /etc/apt/keyrings/docker.gpg
$SUDO_CMD chmod a+r /etc/apt/keyrings/docker.gpg
msg_ok "DOCKER GPG KEY INSTALLED"

msg_info "Writing Docker APT repository"
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
$SUDO_CMD tee /etc/apt/sources.list.d/docker.list >/dev/null
msg_ok "DOCKER APT REPOSITORY WRITTEN"

msg_ok "DOCKER REPOSITORY ADDED"

# --- 24. DOCKER INSTALL ---
# Installs Docker Engine, CLI, containerd, Docker Compose plugin and Buildx plugin.
msg_info "Installing Docker"

msg_info "Updating APT package lists after Docker repository add"
$SUDO_CMD apt-get update &>/dev/null
msg_ok "APT PACKAGE LISTS UPDATED"

msg_info "Installing Docker Engine, CLI, containerd, Compose and Buildx"
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    &>/dev/null
msg_ok "DOCKER PACKAGES INSTALLED"

msg_info "Enabling and starting Docker service"
$SUDO_CMD systemctl enable --now docker &>/dev/null
msg_ok "DOCKER SERVICE ENABLED AND STARTED"

msg_info "Enabling and starting containerd service"
$SUDO_CMD systemctl enable --now containerd &>/dev/null
msg_ok "CONTAINERD SERVICE ENABLED AND STARTED"

msg_ok "DOCKER INSTALLED"

# --- 25. DOCKER GROUP SETUP ---
# Adds the target user to the docker group for non-root Docker CLI usage after next login.
msg_info "Adding user ${TARGET_USER} to docker group"

if id "$TARGET_USER" >/dev/null 2>&1; then
    $SUDO_CMD usermod -aG docker "$TARGET_USER" &>/dev/null
    msg_ok "USER ADDED TO DOCKER GROUP"
else
    msg_warn "Target user ${TARGET_USER} does not exist; docker group membership skipped"
fi

# --- 26. DOCKER FIREWALL MODE ---
# Keeps Docker iptables enabled so Docker networking, NAT and published ports work correctly.
msg_info "Configuring Docker firewall mode"

msg_info "Creating Docker config directory"
$SUDO_CMD mkdir -p /etc/docker
msg_ok "DOCKER CONFIG DIRECTORY READY"

if sudo_path_exists "/etc/docker/daemon.json"; then
    msg_info "Backing up existing Docker daemon config"
    $SUDO_CMD cp -n /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%Y%m%d%H%M%S)" || true
    msg_ok "EXISTING DOCKER DAEMON CONFIG BACKED UP"
fi

msg_info "Writing Docker daemon config"
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
msg_ok "DOCKER DAEMON CONFIG WRITTEN"

msg_info "Restarting Docker service"
$SUDO_CMD systemctl restart docker &>/dev/null
msg_ok "DOCKER SERVICE RESTARTED"

msg_ok "DOCKER FIREWALL MODE CONFIGURED"

# --- 27. UFW BASELINE ---
# Allows SSH, HTTP and HTTPS on the Ubuntu VM.
msg_info "Configuring UFW firewall"

msg_info "Setting UFW default policies"
$SUDO_CMD ufw default deny incoming &>/dev/null || true
$SUDO_CMD ufw default allow outgoing &>/dev/null || true
msg_ok "UFW DEFAULT POLICIES CONFIGURED"

msg_info "Allowing SSH, HTTP and HTTPS"
$SUDO_CMD ufw allow OpenSSH &>/dev/null || true
$SUDO_CMD ufw allow 80/tcp &>/dev/null || true
$SUDO_CMD ufw allow 443/tcp &>/dev/null || true
msg_ok "UFW ALLOW RULES ADDED"

msg_info "Enabling UFW"
$SUDO_CMD ufw --force enable &>/dev/null || true
msg_ok "UFW ENABLED"

msg_ok "UFW FIREWALL CONFIGURED"

# --- 28. DOCKER-GC OPTIONAL INSTALL ---
# Creates a simple safe Docker cleanup helper instead of aggressive automatic pruning.
if [ "$INSTALL_DOCKER_GC" == "y" ]; then
    msg_info "Installing docker-gc helper"

    msg_info "Writing safe Docker cleanup helper"
    cat <<'EOF' | $SUDO_CMD tee /usr/local/sbin/docker-gc-safe >/dev/null
#!/usr/bin/env bash
set -euo pipefail
docker system prune -f
docker image prune -f
docker builder prune -f --filter "until=168h"
EOF
    msg_ok "DOCKER-GC HELPER WRITTEN"

    msg_info "Making docker-gc helper executable"
    $SUDO_CMD chmod +x /usr/local/sbin/docker-gc-safe
    msg_ok "DOCKER-GC HELPER MADE EXECUTABLE"

    msg_ok "DOCKER-GC HELPER INSTALLED"
else
    msg_ok "DOCKER-GC HELPER NOT SELECTED"
fi

# --- 29. VERIFY INSTALL ---
# Checks Docker daemon, Docker CLI and Compose plugin through sudo so verification works before docker group re-login.
msg_info "Verifying Docker installation"

msg_info "Checking Docker CLI"
$SUDO_CMD docker --version >/dev/null
msg_ok "DOCKER CLI VERIFIED"

msg_info "Checking Docker daemon"
$SUDO_CMD docker info >/dev/null
msg_ok "DOCKER DAEMON VERIFIED"

msg_info "Checking Docker Compose plugin"
$SUDO_CMD docker compose version >/dev/null
msg_ok "DOCKER COMPOSE VERIFIED"

msg_ok "DOCKER VERIFIED"

# --- 30. COMPLETION MARKER ---
# Creates marker showing setup completed.
msg_info "Writing completion marker"

$SUDO_CMD tee "$COMPLETED_MARKER" >/dev/null <<EOF
Docker Setup completed on: $(date)
Target user: $TARGET_USER
Swap disabled: $DISABLE_SWAP
Docker GC helper: $INSTALL_DOCKER_GC
Docker firewall mode: $DOCKER_FIREWALL_MODE
Existing setup detected: $EXISTING_SETUP
EOF

msg_ok "COMPLETION MARKER WRITTEN"

# --- 31. FINAL SUMMARY ---
# Displays installed versions and logout/reboot reminder.
echo ""
echo -e "${GN}FINISHED!${CL}"
$SUDO_CMD docker --version
$SUDO_CMD docker compose version
echo ""
echo -e "TARGET USER: ${GN}${TARGET_USER}${CL}"
echo -e "SWAP DISABLED: ${GN}${DISABLE_SWAP}${CL}"
echo -e "DOCKER-GC HELPER: ${GN}${INSTALL_DOCKER_GC}${CL}"
echo -e "EXISTING SETUP DETECTED: ${GN}${EXISTING_SETUP}${CL}"
echo ""
echo -e "${YW}Docker group membership usually requires logout/login or reboot before using Docker without sudo.${CL}"
echo ""

# --- 32. REBOOT OPTION ---
# Offers Ubuntu VM Setup-compatible reboot flow so Docker group membership applies cleanly.
reboot_yn=$(timed_yes_no "Reboot Ubuntu VM now so Docker group membership applies?" "y")

if [[ "$reboot_yn" =~ ^[Yy] ]]; then
    if timed_reboot_countdown "$REBOOT_T"; then
        $SUDO_CMD reboot
    fi
else
    echo -e "${YW}Reboot skipped. Log out and back in before using Docker without sudo.${CL}"
fi

exit 0