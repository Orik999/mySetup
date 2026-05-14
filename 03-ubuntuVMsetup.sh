#!/usr/bin/env bash -ex
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Ubuntu VM Setup
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
LOG_FILE="/var/log/ubuntu-vm-setup.log"
COMPLETED_MARKER="/root/.ubuntu-vm-setup-completed"

DEFAULT_USERNAME="orik"
USERNAME=""
SUDO_USER_CREATED="no"
SSH_HARDENING_APPLIED="no"
QEMU_AGENT_INSTALLED="no"
UFW_ENABLED="no"
IS_CONTAINER="no"
IS_VM="no"

# --- 3. HEADER FUNCTION ---
# Displays the one-line Ubuntu VM Setup banner.
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
# Converts Y/N answers to readable yes/no text.
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

# --- 10. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown. SPACE pauses and waits. Timeout accepts default.
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

# --- 11. EDITABLE TEXT INPUT HELPER ---
# Allows text input with countdown. Any typed character or SPACE pauses countdown.
function editable_text_loop() {
    local prompt="$1"
    local default="$2"
    local initial_value="${3:-}"
    local answer="$initial_value"
    local key=""

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

# --- 12. TIMED TEXT INPUT HELPER ---
# Uses Proxmox VM Setup style countdown and input behaviour.
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
                    answer="$(editable_text_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_text_loop "$prompt" "$default" "$key")"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(editable_text_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_text_loop "$prompt" "$default" "$key")"
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

# --- 13. ROOT / SUDO COMMAND DETECTION ---
# Uses sudo when not root, otherwise runs commands directly.
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# --- 14. ENVIRONMENT DETECTION ---
# Detects whether the script is running inside LXC or VM/bare Ubuntu.
if grep -qa container=lxc /proc/1/environ 2>/dev/null; then
    IS_CONTAINER="yes"
else
    IS_VM="yes"
fi

# --- 15. START CONFIRMATION ---
# Starts Ubuntu VM/LXC setup.
echo -e "${YW}This script will configure Ubuntu VM/LXC for Docker workloads.${CL}"
start_yn=$(timed_yes_no "Start the Ubuntu VM Setup Script?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 16. USERNAME INPUT ---
# Selects the admin user to configure.
USERNAME=$(timed_text_input "Enter username" "$DEFAULT_USERNAME")

# --- 17. USER CHECK / CREATE LOGIC ---
# If the user already exists, the script configures it instead of aborting.
if id "$USERNAME" >/dev/null 2>&1; then
    msg_ok "USER ${USERNAME} ALREADY EXISTS"
else
    msg_info "Creating user ${USERNAME}"
    $SUDO_CMD useradd -m -s /bin/bash "$USERNAME"
    $SUDO_CMD usermod -aG sudo "$USERNAME"
    $SUDO_CMD passwd -l "$USERNAME" &>/dev/null || true
    SUDO_USER_CREATED="yes"
    msg_ok "USER CREATED"
fi

# --- 18. SSH KEY SOURCE CHECK ---
# Uses existing user's SSH keys first, then root keys if available.
SOURCE_KEYS=""

if [ -s "/home/${USERNAME}/.ssh/authorized_keys" ]; then
    SOURCE_KEYS="/home/${USERNAME}/.ssh/authorized_keys"
elif [ -n "${SUDO_USER:-}" ] && [ -s "/home/${SUDO_USER}/.ssh/authorized_keys" ]; then
    SOURCE_KEYS="/home/${SUDO_USER}/.ssh/authorized_keys"
elif [ -s "/root/.ssh/authorized_keys" ]; then
    SOURCE_KEYS="/root/.ssh/authorized_keys"
fi

if [ -z "$SOURCE_KEYS" ]; then
    msg_warn "No SSH authorized_keys found. SSH password hardening will be skipped."
fi

# --- 19. SSH KEY COPY ---
# Copies detected SSH keys to the target user if needed.
if [ -n "$SOURCE_KEYS" ]; then
    msg_info "Configuring SSH keys for ${USERNAME}"

    $SUDO_CMD mkdir -p "/home/${USERNAME}/.ssh"
    $SUDO_CMD cp "$SOURCE_KEYS" "/home/${USERNAME}/.ssh/authorized_keys"
    $SUDO_CMD chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
    $SUDO_CMD chmod 700 "/home/${USERNAME}/.ssh"
    $SUDO_CMD chmod 600 "/home/${USERNAME}/.ssh/authorized_keys"

    msg_ok "SSH KEYS CONFIGURED"
fi

# --- 20. SYSTEM UPDATE ---
# Updates Ubuntu packages before installing QEMU guest agent and firewall tools.
msg_info "Updating system"

$SUDO_CMD apt-get update &>/dev/null
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade &>/dev/null
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get -y autoremove &>/dev/null

msg_ok "SYSTEM UPDATED"

# --- 21. QEMU GUEST AGENT INSTALL ---
# Installs qemu-guest-agent for Proxmox VM visibility and clean shutdown support.
if [ "$IS_VM" == "yes" ]; then
    msg_info "Installing QEMU guest agent"

    $SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent &>/dev/null
    $SUDO_CMD systemctl enable --now qemu-guest-agent &>/dev/null || true

    QEMU_AGENT_INSTALLED="yes"

    msg_ok "QEMU GUEST AGENT INSTALLED"
fi

# --- 22. UFW FIREWALL BASELINE ---
# Enables UFW with SSH, HTTP and HTTPS allowed for Docker/Traefik workloads.
msg_info "Configuring UFW firewall"

$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y ufw &>/dev/null
$SUDO_CMD ufw default deny incoming &>/dev/null || true
$SUDO_CMD ufw default allow outgoing &>/dev/null || true
$SUDO_CMD ufw allow OpenSSH &>/dev/null || true
$SUDO_CMD ufw allow 80/tcp &>/dev/null || true
$SUDO_CMD ufw allow 443/tcp &>/dev/null || true
$SUDO_CMD ufw --force enable &>/dev/null || true

UFW_ENABLED="yes"

msg_ok "UFW FIREWALL ENABLED"

# --- 23. SSH HARDENING ---
# Disables root SSH and password login only if SSH keys exist for the target user.
if [ -s "/home/${USERNAME}/.ssh/authorized_keys" ]; then
    msg_info "Hardening SSH"

    SSH_CONFIG="/etc/ssh/sshd_config"

    $SUDO_CMD sed -i -E 's/^[#[:space:]]*AddressFamily.*/AddressFamily inet/' "$SSH_CONFIG" || true
    grep -q "^AddressFamily" "$SSH_CONFIG" || echo "AddressFamily inet" | $SUDO_CMD tee -a "$SSH_CONFIG" >/dev/null

    $SUDO_CMD sed -i -E 's/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG" || true
    grep -q "^PasswordAuthentication" "$SSH_CONFIG" || echo "PasswordAuthentication no" | $SUDO_CMD tee -a "$SSH_CONFIG" >/dev/null

    $SUDO_CMD sed -i -E 's/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG" || true
    grep -q "^PermitRootLogin" "$SSH_CONFIG" || echo "PermitRootLogin no" | $SUDO_CMD tee -a "$SSH_CONFIG" >/dev/null

    $SUDO_CMD sshd -t &>/dev/null
    $SUDO_CMD systemctl restart ssh &>/dev/null || $SUDO_CMD systemctl restart sshd &>/dev/null || true

    SSH_HARDENING_APPLIED="yes"

    msg_ok "SSH HARDENED"
else
    msg_warn "SSH hardening skipped because user SSH keys were not found."
fi

# --- 24. CLEANUP ---
# Cleans package cache and removes orphan packages.
msg_info "Cleaning system"

$SUDO_CMD apt-get clean &>/dev/null
$SUDO_CMD apt-get -y autoremove &>/dev/null

msg_ok "SYSTEM CLEANED"

# --- 25. COMPLETION MARKER ---
# Creates marker showing the setup ran successfully.
$SUDO_CMD bash -c "cat > '$COMPLETED_MARKER'" <<EOF
Ubuntu VM Setup completed on: $(date)
Username: $USERNAME
User Created: $SUDO_USER_CREATED
Container: $IS_CONTAINER
VM: $IS_VM
QEMU Agent: $QEMU_AGENT_INSTALLED
UFW: $UFW_ENABLED
SSH Hardened: $SSH_HARDENING_APPLIED
EOF

# --- 26. FINAL SUMMARY ---
# Displays final result and next action.
echo ""
echo -e "${GN}FINISHED!${CL}"
echo -e "USERNAME: ${GN}${USERNAME}${CL}"
echo -e "USER CREATED: ${GN}${SUDO_USER_CREATED}${CL}"
echo -e "QEMU GUEST AGENT: ${GN}${QEMU_AGENT_INSTALLED}${CL}"
echo -e "UFW FIREWALL: ${GN}${UFW_ENABLED}${CL}"
echo -e "SSH HARDENING: ${GN}${SSH_HARDENING_APPLIED}${CL}"
echo ""

if [ "$IS_VM" == "yes" ]; then
    echo -e "${YW}Power off the VM now, then enable/check QEMU Guest Agent in Proxmox if needed.${CL}"
else
    echo -e "${YW}Reboot the container when ready.${CL}"
fi

exit 0