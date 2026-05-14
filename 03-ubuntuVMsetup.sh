#!/usr/bin/env bash -ex
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Ubuntu VM Setup
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Keeps all colour variables available for future visual changes.
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
# Stores timer, log file, defaults and detected environment information.
T=15
REBOOT_T=30
LOG_FILE="/var/log/ubuntu-vm-setup.log"
COMPLETED_MARKER="/root/.ubuntu-vm-setup-completed"

DEFAULT_USERNAME="orik"

USERNAME=""
SUDO_USER_CREATED="no"
SSH_HARDENING_APPLIED="no"
QEMU_AGENT_INSTALLED="no"
UFW_ENABLED="no"
ROOT_EXPANDED="no"
UBUNTU_PRO_ATTACHED="no"

IS_CONTAINER="no"
IS_VM="no"

ROOT_KEYS="/root/.ssh/authorized_keys"
CURRENT_USER_KEYS=""
SOURCE_KEYS=""
DEST_KEYS=""

ROOT_SOURCE=""
ROOT_LV_PATH=""
VG_NAME=""
VG_FREE_BYTES="0"

PRO_TOKEN=""

# --- 3. HEADER FUNCTION ---
# Displays the Ubuntu VM Setup banner.
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
# Provides consistent display -> apply -> success output style.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. LOGGING & ERROR HANDLING ---
# Logs output and reports failing line.
# Sensitive input such as Ubuntu Pro token is read silently from /dev/tty and is not printed.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

clear
header_info

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
# Display style matches Proxmox VM Setup: no "timer stopped" wording.
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
# Uses wall-clock countdown instead of loop countdown.
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

# --- 11. EDITABLE INPUT LOOP HELPER ---
# Provides editable text input with backspace support.
# SPACE starts this same editable mode with no extra wording.
function editable_input_loop() {
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
# Uses wall-clock countdown with editable text input.
# SPACE pauses countdown and opens editable mode.
# Any typed character pauses countdown and starts editable mode with that character.
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
                    answer="$(editable_input_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "$key")"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(editable_input_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "$key")"
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

# --- 13. HIDDEN INPUT HELPER ---
# Reads sensitive input from terminal without echoing it.
# Used for Ubuntu Pro token so it does not appear on-screen or in logs.
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

# --- 14. REBOOT COUNTDOWN HELPER ---
# Shows a safe reboot countdown.
# SPACE stops the reboot.
# Uses sudo reboot when the script is not running as root.
function timed_reboot_countdown() {
    local seconds="$1"
    local key=""
    local deadline=""
    local now=""
    local remaining=""

    deadline=$(( $(date +%s) + seconds ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            tty_print "${BFR}"
            return 0
        fi

        tty_print "${BFR}${BL}${CLF}REBOOTING IN ${remaining} SECONDS...${CL} ${YW}(press SPACE to stop)${CL}"

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                if [[ "$key" == " " ]]; then
                    tty_println "${BFR}${YW}Reboot cancelled. Reboot manually with: sudo reboot${CL}"
                    return 1
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    tty_println "${BFR}${YW}Reboot cancelled. Reboot manually with: sudo reboot${CL}"
                    return 1
                fi
            fi
        fi
    done
}

# --- 15. ROOT / SUDO DETECTION ---
# Uses sudo when not root.
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# --- 16. SUDO VALIDATION ---
# Validates sudo once near the start so authentication failures happen before changes.
if [ -n "$SUDO_CMD" ]; then
    msg_info "Validating sudo access"

    $SUDO_CMD -v || msg_error "Sudo authentication failed. Script cancelled."

    msg_ok "SUDO ACCESS CONFIRMED"
fi

# --- 17. ENVIRONMENT DETECTION ---
# Detects whether system is VM or LXC container.
msg_info "Detecting environment"

if grep -qa container=lxc /proc/1/environ 2>/dev/null; then
    IS_CONTAINER="yes"
else
    IS_VM="yes"
fi

msg_ok "ENVIRONMENT DETECTED"

# --- 18. START CONFIRMATION ---
# Starts Ubuntu VM/LXC setup.
echo -e "${YW}This script will configure Ubuntu VM/LXC for Docker workloads.${CL}"

start_yn=$(timed_yes_no "Start the Ubuntu VM Setup Script?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 19. USERNAME INPUT ---
# Selects target non-root admin user.
USERNAME=$(timed_text_input "Enter username" "$DEFAULT_USERNAME")

# --- 20. USER EXISTENCE CHECK ---
# Detects whether the user already exists.
msg_info "Checking existing user"

if id "$USERNAME" >/dev/null 2>&1; then
    EXISTING_USER="yes"
else
    EXISTING_USER="no"
fi

msg_ok "USER CHECK COMPLETE"

# --- 21. SSH KEY SOURCE DETECTION ---
# Detects best SSH key source automatically.
# Priority:
# 1. Target user's existing authorized_keys
# 2. Root authorized_keys
msg_info "Detecting SSH key source"

CURRENT_USER_KEYS="/home/${USERNAME}/.ssh/authorized_keys"

if [ -s "$CURRENT_USER_KEYS" ]; then
    SOURCE_KEYS="$CURRENT_USER_KEYS"
elif [ -s "$ROOT_KEYS" ]; then
    SOURCE_KEYS="$ROOT_KEYS"
else
    SOURCE_KEYS=""
fi

msg_ok "SSH KEY DETECTION COMPLETE"

# --- 22. USER CREATION ---
# Creates user only if missing.
# Existing Ubuntu installer user is reused safely.
if [ "$EXISTING_USER" == "no" ]; then
    msg_info "Creating user ${USERNAME}"

    $SUDO_CMD useradd -m -s /bin/bash "$USERNAME"
    $SUDO_CMD usermod -aG sudo "$USERNAME"
    $SUDO_CMD passwd -l "$USERNAME" &>/dev/null || true

    SUDO_USER_CREATED="yes"

    msg_ok "USER CREATED"
else
    msg_ok "USER ${USERNAME} ALREADY EXISTS"
fi

# --- 23. SSH KEY CONFIGURATION ---
# Configures SSH keys safely.
# If source and destination are the same file, copy is skipped to avoid cp same-file failure.
if [ -n "$SOURCE_KEYS" ]; then
    DEST_KEYS="/home/${USERNAME}/.ssh/authorized_keys"

    if [ "$(readlink -f "$SOURCE_KEYS")" = "$(readlink -f "$DEST_KEYS" 2>/dev/null || echo "$DEST_KEYS")" ]; then
        msg_ok "SSH KEYS ALREADY CONFIGURED"
    else
        msg_info "Configuring SSH keys for ${USERNAME}"

        $SUDO_CMD mkdir -p "/home/${USERNAME}/.ssh"
        $SUDO_CMD cp "$SOURCE_KEYS" "$DEST_KEYS"
        $SUDO_CMD chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.ssh"
        $SUDO_CMD chmod 700 "/home/${USERNAME}/.ssh"
        $SUDO_CMD chmod 600 "$DEST_KEYS"

        msg_ok "SSH KEYS CONFIGURED"
    fi
else
    msg_warn "No SSH authorized_keys source found"
fi

# --- 24. SYSTEM UPDATE ---
# Updates Ubuntu packages before optional Ubuntu Pro attachment and system configuration.
msg_info "Updating system packages"

$SUDO_CMD apt-get update &>/dev/null
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade &>/dev/null
$SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get -y autoremove &>/dev/null

msg_ok "SYSTEM UPDATED"

# --- 25. UBUNTU PRO ATTACHMENT ---
# Optionally attaches Ubuntu Pro using a token entered by the user.
# The token is read silently and is not written to the log, marker file, or final summary.
pro_yn=$(timed_yes_no "Attach Ubuntu Pro token?" "n")

if [[ "$pro_yn" =~ ^[Yy] ]]; then
    PRO_TOKEN="$(hidden_input "Enter Ubuntu Pro token")"

    if [ -z "$PRO_TOKEN" ]; then
        msg_warn "Ubuntu Pro token was empty. Skipping Ubuntu Pro attachment"
    else
        msg_info "Installing Ubuntu Pro client"

        $SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-advantage-tools ubuntu-pro-client &>/dev/null || \
        $SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-advantage-tools &>/dev/null

        msg_ok "UBUNTU PRO CLIENT READY"

        msg_info "Attaching Ubuntu Pro"

        if printf '%s\n' "$PRO_TOKEN" | $SUDO_CMD pro attach "$PRO_TOKEN" &>/dev/null; then
            UBUNTU_PRO_ATTACHED="yes"
            msg_ok "UBUNTU PRO ATTACHED"
        else
            UBUNTU_PRO_ATTACHED="failed"
            msg_warn "Ubuntu Pro attachment failed. Check token or run: sudo pro status"
        fi

        PRO_TOKEN=""
    fi
else
    UBUNTU_PRO_ATTACHED="no"
fi

# --- 26. QEMU GUEST AGENT INSTALL ---
# Installs qemu-guest-agent for Proxmox VM visibility and clean shutdown support.
if [ "$IS_VM" == "yes" ]; then
    msg_info "Installing QEMU guest agent"

    $SUDO_CMD DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent &>/dev/null
    $SUDO_CMD systemctl enable --now qemu-guest-agent &>/dev/null || true

    QEMU_AGENT_INSTALLED="yes"

    msg_ok "QEMU GUEST AGENT INSTALLED"
fi

# --- 27. ROOT FILESYSTEM LVM EXPANSION ---
# Detects if Ubuntu installed / on LVM and automatically expands it to use remaining free VG space.
# This fixes Ubuntu Server installer behaviour where a 40GB Proxmox disk may only give / around 18GB.
# No user interaction is required. If free LVM space exists, the script applies the expansion automatically.
msg_info "Checking root filesystem free space"

ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
ROOT_LV_PATH=""

if [ -n "$ROOT_SOURCE" ]; then
    ROOT_LV_PATH="$(readlink -f "$ROOT_SOURCE" 2>/dev/null || echo "$ROOT_SOURCE")"
fi

if [ -n "$ROOT_LV_PATH" ] && $SUDO_CMD lvs "$ROOT_LV_PATH" &>/dev/null; then
    VG_NAME="$($SUDO_CMD lvs --noheadings -o vg_name "$ROOT_LV_PATH" | xargs)"
    VG_FREE_BYTES="$($SUDO_CMD vgs --noheadings --units b --nosuffix -o vg_free "$VG_NAME" | xargs | cut -d'.' -f1)"

    if [[ "$VG_FREE_BYTES" =~ ^[0-9]+$ ]] && [ "$VG_FREE_BYTES" -gt 1073741824 ]; then
        msg_ok "FOUND EMPTY LVM SPACE"

        msg_info "Expanding Ubuntu root filesystem"

        $SUDO_CMD lvextend -r -l +100%FREE "$ROOT_LV_PATH" &>/dev/null

        ROOT_EXPANDED="yes"

        msg_ok "UBUNTU ROOT FILESYSTEM EXPANDED"
    else
        msg_ok "NO EMPTY LVM SPACE FOUND"
    fi
else
    msg_ok "ROOT FILESYSTEM LVM EXPANSION NOT NEEDED"
fi

# --- 28. UFW FIREWALL SETUP ---
# Enables UFW baseline firewall.
# Allows SSH, HTTP and HTTPS for Docker/Traefik workloads.
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

# --- 29. SSH HARDENING ---
# Disables SSH password login and root login only if SSH keys exist.
# This avoids lockout on systems where no authorized_keys are present.
if [ -s "/home/${USERNAME}/.ssh/authorized_keys" ]; then
    msg_info "Hardening SSH configuration"

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

    msg_ok "SSH HARDENING APPLIED"
else
    msg_warn "SSH hardening skipped because SSH keys were not detected"
fi

# --- 30. SYSTEM CLEANUP ---
# Cleans package cache and orphan packages.
msg_info "Cleaning system"

$SUDO_CMD apt-get clean &>/dev/null
$SUDO_CMD apt-get -y autoremove &>/dev/null

msg_ok "SYSTEM CLEANED"

# --- 31. COMPLETION MARKER ---
# Stores successful setup information.
# Ubuntu Pro token is intentionally not stored.
msg_info "Writing completion marker"

$SUDO_CMD bash -c "cat > '$COMPLETED_MARKER'" <<EOF
Ubuntu VM Setup completed on: $(date)
Username: $USERNAME
User Created: $SUDO_USER_CREATED
Container: $IS_CONTAINER
VM: $IS_VM
Ubuntu Pro Attached: $UBUNTU_PRO_ATTACHED
QEMU Agent: $QEMU_AGENT_INSTALLED
Root Expanded: $ROOT_EXPANDED
UFW: $UFW_ENABLED
SSH Hardened: $SSH_HARDENING_APPLIED
EOF

msg_ok "COMPLETION MARKER WRITTEN"

# --- 32. FINAL SUMMARY ---
# Displays clean final setup summary.
echo ""
echo -e "${BL}UBUNTU VM SETUP SUMMARY${CL}"
echo "------------------------------------------------------"
echo -e "USERNAME:             ${GN}${USERNAME}${CL}"
echo -e "USER CREATED:         ${GN}${SUDO_USER_CREATED}${CL}"
echo -e "ENVIRONMENT:          ${GN}$([ "$IS_VM" == "yes" ] && echo "VM" || echo "LXC")${CL}"
echo -e "UBUNTU PRO ATTACHED:  ${GN}${UBUNTU_PRO_ATTACHED}${CL}"
echo -e "QEMU GUEST AGENT:     ${GN}${QEMU_AGENT_INSTALLED}${CL}"
echo -e "ROOT EXPANDED:        ${GN}${ROOT_EXPANDED}${CL}"
echo -e "UFW FIREWALL:         ${GN}${UFW_ENABLED}${CL}"
echo -e "SSH HARDENING:        ${GN}${SSH_HARDENING_APPLIED}${CL}"
echo -e "LOG FILE:             ${GN}${LOG_FILE}${CL}"
echo "------------------------------------------------------"
echo -e "${GN}Ubuntu VM setup completed successfully.${CL}"
echo ""

# --- 33. REBOOT PROMPT ---
# Offers safe reboot using sudo reboot when not root.
reboot_yn=$(timed_yes_no "Reboot Ubuntu VM now?" "y")

if [[ "$reboot_yn" =~ ^[Yy] ]]; then
    if timed_reboot_countdown "$REBOOT_T"; then
        if [ -n "$SUDO_CMD" ]; then
            $SUDO_CMD reboot
        else
            reboot
        fi
    fi
else
    echo -e "${YW}Reboot skipped. Reboot manually with: sudo reboot${CL}"
fi

exit 0