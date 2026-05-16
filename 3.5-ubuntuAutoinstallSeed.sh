#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Ubuntu Auto Install Seed
# =========================================================

# --- 1. COLOR VARIABLES ---
YW=`echo "\033[33m"`
BL=`echo "\033[36m"`
RD=`echo "\033[01;31m"`
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
CLF=`echo "\033[5m"`
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# --- 2. GLOBAL VARIABLES ---
T=15
LOG_FILE="/var/log/ubuntu-autoinstall-seed.log"
COMPLETED_MARKER="/root/.ubuntu-autoinstall-seed-completed"

DEFAULT_USERNAME="orik"
DEFAULT_TIMEZONE="Europe/London"
DEFAULT_KEYBOARD_LAYOUT="gb"
DEFAULT_KEYBOARD_VARIANT=""
DEFAULT_LOCALE="en_GB.UTF-8"
DEFAULT_ISO_NAME="ubuntu-26.04-live-server-amd64.iso"

TARGET_VMID=""
TARGET_VM_NAME=""
TARGET_VM_STATUS=""
TARGET_VM_MAC=""
TARGET_USERNAME=""
TARGET_TIMEZONE=""
TARGET_KEYBOARD_LAYOUT=""
TARGET_KEYBOARD_VARIANT=""
TARGET_LOCALE=""

INSTALL_ISO_PATH=""
INSTALL_ISO_REF=""

AUTOINSTALL_ISO_NAME=""
AUTOINSTALL_ISO_PATH=""
AUTOINSTALL_ISO_REF=""
WORK_DIR=""

SSH_KEYS=""
KEY_SOURCE=""

NETWORK_MODE="dhcp"
STATIC_IP_CIDR=""
STATIC_GATEWAY=""
STATIC_DNS="1.1.1.1,1.0.0.1"

BOOT_PARAM='autoinstall ds=nocloud\;s=/cdrom/nocloud/'

# --- 3. HEADER FUNCTION ---
# Displays the Ubuntu Auto Install Seed banner.
function header_info {
echo -e "${BL}
██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗     █████╗ ██╗   ██╗████████╗ ██████╗ 
██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║    ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗
██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║    ███████║██║   ██║   ██║   ██║   ██║
██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║    ██╔══██║██║   ██║   ██║   ██║   ██║
╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝    ██║  ██║╚██████╔╝   ██║   ╚██████╔╝
 ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ 
${CL}"
}

# --- 4. MESSAGE HELPERS ---
# Provides consistent display -> apply -> success output.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. LOGGING & ERROR HANDLING ---
# Logs script output and reports the line number if a command fails.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 6. ROOT CHECK ---
# Proxmox ISO creation and VM media attachment require root.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

clear
header_info

# =========================================================
#  INPUT HELPERS - SCRIPT 3 STYLE
# =========================================================

# --- 7. TTY PRINT HELPER ---
# Prints directly to terminal even when functions return values through stdout.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 8. TTY PRINTLN HELPER ---
# Prints directly to terminal with newline.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 9. YES/NO LABEL HELPER ---
# Converts raw Y/N answers to readable yes/no.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 10. BLOCKING YES/NO HELPER ---
# Used after SPACE is pressed during a timed Y/n prompt.
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

# --- 12. NUMERIC VALIDATION HELPER ---
# Validates numeric input against optional minimum and maximum values.
function validate_number() {
    local value="$1"
    local min_value="${2:-1}"
    local max_value="${3:-}"

    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$value" -lt "$min_value" ]; then
        return 1
    fi

    if [ -n "$max_value" ] && [ "$value" -gt "$max_value" ]; then
        return 1
    fi

    return 0
}

# --- 13. NUMERIC ERROR HELPER ---
# Shows a clear numeric validation error.
function print_number_error() {
    local min_value="${1:-1}"
    local max_value="${2:-}"

    if [ -n "$max_value" ]; then
        tty_println "${RD}Invalid input. Enter numbers only between ${min_value} and ${max_value}.${CL}"
    else
        tty_println "${RD}Invalid input. Enter numbers only. Minimum value is ${min_value}.${CL}"
    fi
}

# --- 14. EDITABLE INPUT LOOP HELPER ---
# Shared editable input system for text and numeric prompts.
function editable_input_loop() {
    local prompt="$1"
    local default="$2"
    local numeric_only="${3:-no}"
    local min_value="${4:-1}"
    local max_value="${5:-}"
    local initial_value="${6:-}"
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

                if [ "$numeric_only" == "yes" ]; then
                    if validate_number "$answer" "$min_value" "$max_value"; then
                        tty_print "${BFR}"
                        echo "$answer"
                        return 0
                    fi

                    tty_print "${BFR}"
                    print_number_error "$min_value" "$max_value"
                    answer=""
                else
                    tty_print "${BFR}"
                    echo "$answer"
                    return 0
                fi
                ;;
            $'\177'|$'\b')
                answer="${answer%?}"
                ;;
            *)
                if [ "$numeric_only" == "yes" ]; then
                    if [[ "$key" =~ ^[0-9]$ ]]; then
                        answer+="$key"
                    else
                        tty_print "${BFR}"
                        print_number_error "$min_value" "$max_value"
                        answer=""
                    fi
                else
                    answer+="$key"
                fi
                ;;
        esac
    done
}

# --- 15. TIMED TEXT INPUT HELPER ---
# Shows wall-clock countdown.
# SPACE pauses with empty editable buffer.
# Any typed character pauses with that character already inside the editable buffer.
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
                    answer="$(editable_input_loop "$prompt" "$default" "no" "1" "" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "no" "1" "" "$key")"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(editable_input_loop "$prompt" "$default" "no" "1" "" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "no" "1" "" "$key")"
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

# --- 16. TIMED NUMERIC INPUT HELPER ---
# Shows wall-clock countdown and validates numeric input.
function timed_number_input() {
    local prompt="$1"
    local default="$2"
    local min_value="${3:-1}"
    local max_value="${4:-}"
    local answer=""
    local key=""
    local deadline=""
    local now=""
    local remaining=""

    while true; do
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
                        answer="$(editable_input_loop "$prompt" "$default" "yes" "$min_value" "$max_value" "")"
                        break
                    elif [[ -z "$key" ]]; then
                        answer="$default"
                        break
                    elif [[ "$key" =~ ^[0-9]$ ]]; then
                        answer="$(editable_input_loop "$prompt" "$default" "yes" "$min_value" "$max_value" "$key")"
                        break
                    else
                        tty_print "${BFR}"
                        print_number_error "$min_value" "$max_value"
                        answer="INVALID"
                        break
                    fi
                fi
            else
                if IFS= read -rsn1 -t 1 key; then
                    if [[ "$key" == " " ]]; then
                        answer="$(editable_input_loop "$prompt" "$default" "yes" "$min_value" "$max_value" "")"
                        break
                    elif [[ -z "$key" ]]; then
                        answer="$default"
                        break
                    elif [[ "$key" =~ ^[0-9]$ ]]; then
                        answer="$(editable_input_loop "$prompt" "$default" "yes" "$min_value" "$max_value" "$key")"
                        break
                    else
                        tty_print "${BFR}"
                        print_number_error "$min_value" "$max_value"
                        answer="INVALID"
                        break
                    fi
                fi
            fi
        done

        if [ "$answer" == "INVALID" ]; then
            continue
        fi

        if validate_number "$answer" "$min_value" "$max_value"; then
            tty_print "${BFR}"
            tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
            echo "$answer"
            return 0
        fi

        tty_print "${BFR}"
        print_number_error "$min_value" "$max_value"
    done
}

# --- 17. MENU SELECTION HELPER ---
# Shows a numbered menu directly on the terminal and returns only the selected value.
function timed_menu_select() {
    local title="$1"
    local default_index="$2"
    shift 2
    local options=("$@")
    local idx=""
    local selected=""

    tty_println ""
    tty_println "${BL}${title}:${CL}"

    for i in "${!options[@]}"; do
        tty_println "$((i+1))) ${options[$i]}"
    done

    idx=$(timed_number_input "Select ${title} option number" "$default_index" "1" "${#options[@]}")
    selected="${options[$((idx-1))]}"

    echo "$selected"
}

# =========================================================
#  SCRIPT HELPERS
# =========================================================

# --- 18. YAML QUOTE HELPER ---
# Safely quotes values used inside YAML lists.
function yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# --- 19. SAFE HOSTNAME HELPER ---
# Converts VM names into Ubuntu-safe hostnames.
function safe_hostname() {
    local value="$1"

    value="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
    value="$(echo "$value" | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"

    if [ -z "$value" ]; then
        value="ubuntu-vm"
    fi

    echo "$value"
}

# --- 20. PATCH GRUB FILE HELPER ---
# Adds autoinstall boot parameters to Ubuntu GRUB linux lines without duplicating them.
function patch_grub_file() {
    local file="$1"
    local temp_file=""

    [ -f "$file" ] || return 0

    temp_file="$(mktemp)"

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == *"linux"*"/casper/vmlinuz"* ]] && [[ "$line" != *"ds=nocloud"* ]]; then
            if [[ "$line" == *" ---"* ]]; then
                line="${line/ ---/ ${BOOT_PARAM} ---}"
            else
                line="${line} ${BOOT_PARAM}"
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$file"

    cat "$temp_file" > "$file"
    rm -f "$temp_file"
}

# --- 21. ISO PATH FROM PROXMOX REF HELPER ---
# Converts local:iso/file.iso into /var/lib/vz/template/iso/file.iso for local storage.
function iso_ref_to_path() {
    local ref="$1"

    if [[ "$ref" =~ ^local:iso/(.+)$ ]]; then
        echo "/var/lib/vz/template/iso/${BASH_REMATCH[1]}"
        return 0
    fi

    echo ""
    return 1
}

# =========================================================
#  PHASE 1: SAFE AUDIT + USER INPUT COLLECTION ONLY
# =========================================================

# --- 22. PROXMOX VALIDATION ---
# Confirms the script is being run on Proxmox VE 9 or newer.
if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This system is not Proxmox VE. Script cancelled."
fi

PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)

if ! [[ "$PVE_MAJOR" =~ ^[0-9]+$ ]] || [ "$PVE_MAJOR" -lt 9 ]; then
    msg_error "Requires Proxmox VE 9+."
fi

# --- 23. DEPENDENCY CHECK ---
# Installs tools required to create a bootable generated ISO copy.
msg_info "Checking required tools"

for pkg in xorriso rsync p7zip-full; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        msg_warn "${pkg} not found. Installing it now."
        DEBIAN_FRONTEND=noninteractive apt-get update &>/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" &>/dev/null
    fi
done

command -v xorriso >/dev/null 2>&1 || msg_error "xorriso is required."
command -v qm >/dev/null 2>&1 || msg_error "qm command not found."
command -v openssl >/dev/null 2>&1 || msg_error "openssl command not found."

msg_ok "REQUIRED TOOLS FOUND"

# --- 24. START WARNING ---
# Explains the purpose and destructive nature of Ubuntu autoinstall.
echo -e "${YW}This script creates a generated Ubuntu 26.04 autoinstall ISO copy.${CL}"
echo -e "${YW}The original Ubuntu ISO remains untouched.${CL}"
echo -e "${YW}Written for: ${GN}${DEFAULT_ISO_NAME}${CL}"
echo ""
echo -e "${RD}WARNING:${CL} Ubuntu autoinstall can erase the selected VM install disk."
echo -e "${YW}For best results, use a fresh VM created by script 3 with one OS disk.${CL}"
echo ""

start_yn=$(timed_yes_no "Start Ubuntu Auto Install ISO Creator?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 25. VM DETECTION AND SAFE SELECTION ---
# Detects existing VMs and lets the user select the target VM.
msg_info "Detecting Proxmox VMs"

mapfile -t VM_LINES < <(qm list | awk 'NR>1 {print $1 "|" $2 "|" $3}')

if [ "${#VM_LINES[@]}" -eq 0 ]; then
    msg_error "No VMs found. Run script 3 first, then run this script."
fi

msg_ok "PROXMOX VMS DETECTED"

echo ""
echo -e "${BL}AVAILABLE VMS:${CL}"

DEFAULT_VM_INDEX="1"
HIGHEST_VMID="0"

for i in "${!VM_LINES[@]}"; do
    vmid="$(echo "${VM_LINES[$i]}" | cut -d'|' -f1)"
    name="$(echo "${VM_LINES[$i]}" | cut -d'|' -f2)"
    status="$(echo "${VM_LINES[$i]}" | cut -d'|' -f3)"

    if [ "$vmid" -gt "$HIGHEST_VMID" ]; then
        HIGHEST_VMID="$vmid"
        DEFAULT_VM_INDEX="$((i+1))"
    fi

    echo "$((i+1))) ${vmid} | ${name} | ${status}"
done

[ "${#VM_LINES[@]}" -eq 1 ] && DEFAULT_VM_INDEX="1"

VM_INDEX=$(timed_number_input "Select VM for Ubuntu autoinstall" "$DEFAULT_VM_INDEX" "1" "${#VM_LINES[@]}")

TARGET_VMID="$(echo "${VM_LINES[$((VM_INDEX-1))]}" | cut -d'|' -f1)"
TARGET_VM_NAME="$(echo "${VM_LINES[$((VM_INDEX-1))]}" | cut -d'|' -f2)"
TARGET_VM_STATUS="$(echo "${VM_LINES[$((VM_INDEX-1))]}" | cut -d'|' -f3)"

qm config "$TARGET_VMID" >/dev/null 2>&1 || msg_error "Selected VM ${TARGET_VMID} does not exist."

# --- 26. VM MAC DETECTION ---
# Reads VM MAC address from net0 so DHCP router reservation can stay stable.
msg_info "Detecting VM MAC address"

TARGET_VM_MAC="$(qm config "$TARGET_VMID" | awk -F'[=,]' '/^net0:/ {print $2; exit}' | tr '[:lower:]' '[:upper:]')"

if [ -z "$TARGET_VM_MAC" ]; then
    msg_error "Could not detect net0 MAC address for VM ${TARGET_VMID}. Check: qm config ${TARGET_VMID}"
fi

msg_ok "VM MAC DETECTED (${TARGET_VM_MAC})"

# --- 27. USERNAME / TIMEZONE / LOCALE INPUTS ---
# Collects Ubuntu identity and UK-friendly locale defaults.
TARGET_USERNAME=$(timed_text_input "Enter Ubuntu admin username" "$DEFAULT_USERNAME")
TARGET_TIMEZONE=$(timed_text_input "Enter timezone" "$DEFAULT_TIMEZONE")
TARGET_LOCALE=$(timed_text_input "Enter Ubuntu locale" "$DEFAULT_LOCALE")

KEYBOARD_CHOICE=$(timed_menu_select "Keyboard Layout" "1" \
    "UK / British keyboard (gb)" \
    "US keyboard (us)" \
    "Custom keyboard layout")

case "$KEYBOARD_CHOICE" in
    "UK / British keyboard (gb)")
        TARGET_KEYBOARD_LAYOUT="gb"
        TARGET_KEYBOARD_VARIANT=""
        ;;
    "US keyboard (us)")
        TARGET_KEYBOARD_LAYOUT="us"
        TARGET_KEYBOARD_VARIANT=""
        ;;
    *)
        TARGET_KEYBOARD_LAYOUT=$(timed_text_input "Enter keyboard layout code" "$DEFAULT_KEYBOARD_LAYOUT")
        TARGET_KEYBOARD_VARIANT=$(timed_text_input "Enter keyboard variant or leave blank" "$DEFAULT_KEYBOARD_VARIANT")
        ;;
esac

TARGET_HOSTNAME="$(safe_hostname "$TARGET_VM_NAME")"

# --- 28. SSH KEY DETECTION ---
# Detects SSH keys and refuses to continue if none are found.
msg_info "Detecting SSH authorized keys"

KEY_SOURCE=""

if [ -s "/home/${TARGET_USERNAME}/.ssh/authorized_keys" ]; then
    KEY_SOURCE="/home/${TARGET_USERNAME}/.ssh/authorized_keys"
elif [ -s "/root/.ssh/authorized_keys" ]; then
    KEY_SOURCE="/root/.ssh/authorized_keys"
else
    for pubkey in /root/.ssh/id_*.pub "/home/${TARGET_USERNAME}/.ssh/id_"*.pub; do
        if [ -s "$pubkey" ]; then
            KEY_SOURCE="$pubkey"
            break
        fi
    done
fi

if [ -z "$KEY_SOURCE" ]; then
    echo ""
    echo -e "${RD}No SSH public key source found.${CL}"
    echo -e "${YW}This autoinstall is SSH-key-only and will not create usable password SSH login.${CL}"
    echo -e "${YW}Add a key to /root/.ssh/authorized_keys or /home/${TARGET_USERNAME}/.ssh/authorized_keys and rerun.${CL}"
    exit 1
fi

SSH_KEYS="$(grep -E '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-|sk-ssh-)' "$KEY_SOURCE" | sed '/^[[:space:]]*$/d' || true)"

if [ -z "$SSH_KEYS" ]; then
    msg_error "SSH key source exists but no valid public key lines were found: ${KEY_SOURCE}"
fi

msg_ok "SSH KEYS DETECTED (${KEY_SOURCE})"

# --- 29. NETWORK MODE ---
# Recommends DHCP plus router reservation by VM MAC, but supports static IP.
echo ""
echo -e "${BL}NETWORK CONFIGURATION:${CL}"
echo -e "${YW}Recommended: use DHCP here and reserve static IP in your router using this MAC:${CL} ${GN}${TARGET_VM_MAC}${CL}"
echo ""

dhcp_yn=$(timed_yes_no "Use DHCP networking inside Ubuntu?" "y")

if [[ "$dhcp_yn" =~ ^[Nn] ]]; then
    NETWORK_MODE="static"
    STATIC_IP_CIDR=$(timed_text_input "Enter static IP/CIDR" "192.168.1.50/24")
    STATIC_GATEWAY=$(timed_text_input "Enter gateway IP" "192.168.1.1")
    STATIC_DNS=$(timed_text_input "Enter DNS servers comma-separated" "$STATIC_DNS")
else
    NETWORK_MODE="dhcp"
fi

# --- 30. UBUNTU ISO SELECTION ---
# Selects the original Ubuntu ISO. It remains untouched.
msg_info "Finding Ubuntu install ISO"

mapfile -t ISOS < <(find /var/lib/vz/template/iso -maxdepth 1 -type f -iname "*.iso" ! -iname "*autoinstall*" ! -iname "*seed*" | sort || true)

if [ "${#ISOS[@]}" -eq 0 ]; then
    msg_error "No original ISO files found in /var/lib/vz/template/iso."
fi

msg_ok "ISO FILES FOUND"

echo ""
echo -e "${BL}SELECT SOURCE UBUNTU INSTALL ISO:${CL}"

DEFAULT_ISO_INDEX="1"

for i in "${!ISOS[@]}"; do
    iso_base="$(basename "${ISOS[$i]}")"
    [ "$iso_base" == "$DEFAULT_ISO_NAME" ] && DEFAULT_ISO_INDEX="$((i+1))"
    echo "$((i+1))) ${iso_base}"
done

ISO_INDEX=$(timed_number_input "Select Ubuntu ISO number" "$DEFAULT_ISO_INDEX" "1" "${#ISOS[@]}")
INSTALL_ISO_PATH="${ISOS[$((ISO_INDEX-1))]}"
INSTALL_ISO_REF="local:iso/$(basename "$INSTALL_ISO_PATH")"

# --- 31. UBUNTU PRO NOTE ---
# Keeps Ubuntu Pro handling in script 4.
echo ""
echo -e "${BL}UBUNTU PRO:${CL}"
echo -e "${YW}Ubuntu Pro is intentionally not attached by this script.${CL}"
echo -e "${YW}script 4 can attach Ubuntu Pro later, or manually use:${CL} ${GN}sudo pro attach <token>${CL}"
echo ""

# --- 32. GENERATED ISO PATHS ---
# Prepares paths for generated autoinstall ISO copy and temporary files.
AUTOINSTALL_ISO_NAME="ubuntu-26.04-autoinstall-vm${TARGET_VMID}.iso"
AUTOINSTALL_ISO_PATH="/var/lib/vz/template/iso/${AUTOINSTALL_ISO_NAME}"
AUTOINSTALL_ISO_REF="local:iso/${AUTOINSTALL_ISO_NAME}"
WORK_DIR="/tmp/ubuntu-autoinstall-vm${TARGET_VMID}"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/nocloud"
mkdir -p "$WORK_DIR/grub"

# --- 33. RANDOM PASSWORD HASH ---
# Autoinstall requires a password hash. The password is random and never displayed.
# SSH password login is disabled. Sudo is configured as NOPASSWD for automation/script 4 compatibility.
RANDOM_PASSWORD_HASH="$(openssl passwd -6 "$(openssl rand -base64 48)")"

# --- 34. SSH KEY YAML BLOCK ---
# Converts detected SSH public keys into YAML list entries.
SSH_KEYS_YAML=""

while IFS= read -r keyline; do
    [ -z "$keyline" ] && continue
    SSH_KEYS_YAML+="      - $(yaml_quote "$keyline")"$'\n'
done <<< "$SSH_KEYS"

# --- 35. NETWORK CONFIG CREATION ---
# Creates cloud-init network-config matching the VM MAC address.
if [ "$NETWORK_MODE" == "dhcp" ]; then
cat > "${WORK_DIR}/nocloud/network-config" <<EOF
version: 2
ethernets:
  vmnic0:
    match:
      macaddress: "${TARGET_VM_MAC}"
    set-name: ens18
    dhcp4: true
    dhcp6: false
EOF
else
DNS_YAML=""
IFS=',' read -ra DNS_ARRAY <<< "$STATIC_DNS"

for dns in "${DNS_ARRAY[@]}"; do
    dns="$(echo "$dns" | xargs)"
    [ -n "$dns" ] && DNS_YAML+="        - ${dns}"$'\n'
done

cat > "${WORK_DIR}/nocloud/network-config" <<EOF
version: 2
ethernets:
  vmnic0:
    match:
      macaddress: "${TARGET_VM_MAC}"
    set-name: ens18
    dhcp4: false
    dhcp6: false
    addresses:
      - ${STATIC_IP_CIDR}
    routes:
      - to: default
        via: ${STATIC_GATEWAY}
    nameservers:
      addresses:
${DNS_YAML}
EOF
fi

# --- 36. META-DATA CREATION ---
# Creates NoCloud meta-data with stable instance ID and hostname.
cat > "${WORK_DIR}/nocloud/meta-data" <<EOF
instance-id: ubuntu-autoinstall-vm${TARGET_VMID}
local-hostname: ${TARGET_HOSTNAME}
EOF

# --- 37. USER-DATA CREATION ---
# Creates Ubuntu autoinstall config with SSH keys, UK defaults, no SSH password login, QEMU agent, and first-login verifier.
cat > "${WORK_DIR}/nocloud/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  refresh-installer:
    update: false
  locale: ${TARGET_LOCALE}
  keyboard:
    layout: ${TARGET_KEYBOARD_LAYOUT}
    variant: "${TARGET_KEYBOARD_VARIANT}"
  timezone: ${TARGET_TIMEZONE}
  identity:
    hostname: ${TARGET_HOSTNAME}
    username: ${TARGET_USERNAME}
    password: "${RANDOM_PASSWORD_HASH}"
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
${SSH_KEYS_YAML}
  apt:
    preserve_sources_list: false
    primary:
      - arches: [default]
        uri: http://archive.ubuntu.com/ubuntu
  storage:
    layout:
      name: lvm
  late-commands:
    - curtin in-target --target=/target -- usermod -aG sudo ${TARGET_USERNAME}
    - curtin in-target --target=/target -- bash -c 'echo "${TARGET_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${TARGET_USERNAME}-nopasswd'
    - curtin in-target --target=/target -- chmod 0440 /etc/sudoers.d/90-${TARGET_USERNAME}-nopasswd
    - curtin in-target --target=/target -- bash -c 'apt-get update || true'
    - curtin in-target --target=/target -- bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent curl ca-certificates || true'
    - curtin in-target --target=/target -- systemctl enable qemu-guest-agent || true
    - curtin in-target --target=/target -- bash -c 'sed -i -E "s/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config || true'
    - curtin in-target --target=/target -- bash -c 'grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config'
    - curtin in-target --target=/target -- bash -c 'sed -i -E "s/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config || true'
    - curtin in-target --target=/target -- bash -c 'grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config'
    - curtin in-target --target=/target -- bash -c 'sed -i -E "s/^[#[:space:]]*AddressFamily.*/AddressFamily inet/" /etc/ssh/sshd_config || true'
    - curtin in-target --target=/target -- bash -c 'grep -q "^AddressFamily" /etc/ssh/sshd_config || echo "AddressFamily inet" >> /etc/ssh/sshd_config'
    - curtin in-target --target=/target -- bash -c 'date > /var/log/ubuntu-autoinstall-completed'
    - |
      cat > /target/etc/profile.d/ubuntu-autoinstall-verify-display.sh <<'EOS'
#!/usr/bin/env bash

VERIFY_MARKER="/home/${TARGET_USERNAME}/.ubuntu-autoinstall-verify-displayed"

if [ "\$(id -un)" != "${TARGET_USERNAME}" ] && [ "\$(id -u)" -ne 0 ]; then
    return 0 2>/dev/null || exit 0
fi

if [ -f "\$VERIFY_MARKER" ]; then
    return 0 2>/dev/null || exit 0
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " UBUNTU AUTOINSTALL VERIFICATION REPORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Date: \$(date)"
echo "Host: \$(hostname)"
echo "User: ${TARGET_USERNAME}"
echo "Expected VM MAC: ${TARGET_VM_MAC}"
echo "Keyboard Layout: ${TARGET_KEYBOARD_LAYOUT}"
echo "Locale: ${TARGET_LOCALE}"
echo ""

PASS() { echo "✓ PASS - \$1"; }
WARN() { echo "! WARN - \$1"; }
FAIL() { echo "✗ FAIL - \$1"; }

if [ -s "/home/${TARGET_USERNAME}/.ssh/authorized_keys" ]; then PASS "SSH authorized_keys present"; else FAIL "SSH authorized_keys missing"; fi
if sshd -T 2>/dev/null | grep -q "^passwordauthentication no"; then PASS "SSH password authentication disabled"; else FAIL "SSH password authentication not disabled"; fi
if sshd -T 2>/dev/null | grep -q "^permitrootlogin no"; then PASS "Root SSH login disabled"; else WARN "Root SSH login not confirmed disabled"; fi
if [ -f "/etc/sudoers.d/90-${TARGET_USERNAME}-nopasswd" ]; then PASS "NOPASSWD sudo rule present"; else WARN "NOPASSWD sudo rule missing"; fi
if systemctl is-enabled --quiet qemu-guest-agent 2>/dev/null; then PASS "QEMU guest agent enabled"; else WARN "QEMU guest agent not enabled"; fi
if systemctl is-active --quiet qemu-guest-agent 2>/dev/null; then PASS "QEMU guest agent active"; else WARN "QEMU guest agent not active yet"; fi
if [ -f /var/log/ubuntu-autoinstall-completed ]; then PASS "Autoinstall completion marker exists"; else WARN "Autoinstall marker missing"; fi
if findmnt / >/dev/null 2>&1; then PASS "Root filesystem mounted"; else FAIL "Root filesystem check failed"; fi
if command -v ip >/dev/null 2>&1 && ip -4 addr show | grep -q "inet "; then PASS "IPv4 address detected"; else WARN "IPv4 address not detected"; fi
if apt-get check >/dev/null 2>&1; then PASS "APT database healthy"; else WARN "APT database check failed"; fi

echo ""
echo "Network:"
ip -br addr 2>/dev/null || true
echo ""
echo "Disk:"
df -h / 2>/dev/null || true
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

touch "\$VERIFY_MARKER" 2>/dev/null || true
rm -f /etc/profile.d/ubuntu-autoinstall-verify-display.sh 2>/dev/null || true
EOS
    - chmod +x /target/etc/profile.d/ubuntu-autoinstall-verify-display.sh
  shutdown: reboot
EOF

# --- 38. EXTRACT GRUB CONFIGS FROM ORIGINAL ISO ---
# Extracts only boot config files. The original ISO remains untouched.
msg_info "Extracting Ubuntu boot configuration"

xorriso -osirrox on -indev "$INSTALL_ISO_PATH" -extract /boot/grub/grub.cfg "$WORK_DIR/grub/grub.cfg" &>/dev/null || \
    msg_error "Could not extract /boot/grub/grub.cfg from source ISO."

xorriso -osirrox on -indev "$INSTALL_ISO_PATH" -extract /boot/grub/loopback.cfg "$WORK_DIR/grub/loopback.cfg" &>/dev/null || true

msg_ok "UBUNTU BOOT CONFIGURATION EXTRACTED"

# --- 39. PATCH BOOT PARAMETERS ---
# Adds autoinstall and NoCloud path to generated ISO boot entries.
msg_info "Patching Ubuntu autoinstall boot parameters"

patch_grub_file "$WORK_DIR/grub/grub.cfg"
patch_grub_file "$WORK_DIR/grub/loopback.cfg"

if ! grep -q "ds=nocloud" "$WORK_DIR/grub/grub.cfg"; then
    msg_error "Autoinstall boot parameter was not injected into grub.cfg."
fi

msg_ok "AUTOINSTALL BOOT PARAMETERS PATCHED"

# --- 40. BUILD GENERATED AUTOINSTALL ISO COPY ---
# Uses xorriso replay mode to preserve the original Ubuntu ISO boot structure.
# Maps patched GRUB files and /nocloud data into the generated ISO copy.
msg_info "Building generated Ubuntu autoinstall ISO copy"

rm -f "$AUTOINSTALL_ISO_PATH"

XORRISO_ARGS=(
    -indev "$INSTALL_ISO_PATH"
    -outdev "$AUTOINSTALL_ISO_PATH"
    -boot_image any replay
    -map "$WORK_DIR/nocloud" /nocloud
    -map "$WORK_DIR/grub/grub.cfg" /boot/grub/grub.cfg
)

if [ -f "$WORK_DIR/grub/loopback.cfg" ]; then
    XORRISO_ARGS+=(
        -map "$WORK_DIR/grub/loopback.cfg" /boot/grub/loopback.cfg
    )
fi

xorriso "${XORRISO_ARGS[@]}" &>/dev/null

if [ ! -s "$AUTOINSTALL_ISO_PATH" ]; then
    msg_error "Generated Ubuntu autoinstall ISO was not created."
fi

msg_ok "GENERATED AUTOINSTALL ISO CREATED (${AUTOINSTALL_ISO_REF})"

# --- 41. FINAL SUMMARY BEFORE APPLY ---
# Shows all collected settings before modifying the VM.
echo ""
echo -e "${BL}READY TO ATTACH GENERATED UBUNTU AUTOINSTALL ISO:${CL}"
echo -e "VM ID: ${GN}${TARGET_VMID}${CL}"
echo -e "VM NAME: ${GN}${TARGET_VM_NAME}${CL}"
echo -e "VM STATUS: ${GN}${TARGET_VM_STATUS}${CL}"
echo -e "VM MAC: ${GN}${TARGET_VM_MAC}${CL}"
echo -e "UBUNTU HOSTNAME: ${GN}${TARGET_HOSTNAME}${CL}"
echo -e "UBUNTU USER: ${GN}${TARGET_USERNAME}${CL}"
echo -e "TIMEZONE: ${GN}${TARGET_TIMEZONE}${CL}"
echo -e "LOCALE: ${GN}${TARGET_LOCALE}${CL}"
echo -e "KEYBOARD LAYOUT: ${GN}${TARGET_KEYBOARD_LAYOUT}${CL}"
echo -e "KEYBOARD VARIANT: ${GN}${TARGET_KEYBOARD_VARIANT:-none}${CL}"
echo -e "NETWORK MODE: ${GN}${NETWORK_MODE}${CL}"

if [ "$NETWORK_MODE" == "static" ]; then
    echo -e "STATIC IP/CIDR: ${GN}${STATIC_IP_CIDR}${CL}"
    echo -e "GATEWAY: ${GN}${STATIC_GATEWAY}${CL}"
    echo -e "DNS: ${GN}${STATIC_DNS}${CL}"
fi

echo -e "SOURCE ISO: ${GN}${INSTALL_ISO_REF}${CL}"
echo -e "GENERATED AUTOINSTALL ISO: ${GN}${AUTOINSTALL_ISO_REF}${CL}"
echo ""
echo -e "${RD}WARNING:${CL} Starting this VM can begin Ubuntu autoinstall and wipe its VM disk."
echo ""

attach_yn=$(timed_yes_no "Attach generated autoinstall ISO and start VM now?" "y")
[[ "$attach_yn" =~ ^[Nn] ]] && exit 0

# =========================================================
#  PHASE 2: APPLY ONLY AFTER FINAL CONFIRMATION
# =========================================================

# --- 42. VM STOP HANDLING ---
# Ensures the VM is stopped before attaching boot media.
if [ "$TARGET_VM_STATUS" == "running" ]; then
    msg_warn "VM ${TARGET_VMID} is currently running"
    stop_yn=$(timed_yes_no "Shutdown VM before attaching install media?" "n")

    if [[ "$stop_yn" =~ ^[Yy] ]]; then
        msg_info "Shutting down VM ${TARGET_VMID}"
        qm shutdown "$TARGET_VMID" --timeout 60 &>/dev/null || qm stop "$TARGET_VMID" &>/dev/null
        msg_ok "VM STOPPED"
    else
        msg_error "VM must be stopped before attaching install media safely."
    fi
fi

# --- 43. ATTACH GENERATED AUTOINSTALL ISO ---
# Replaces the install CD-ROM with the generated autoinstall ISO copy.
msg_info "Attaching generated Ubuntu autoinstall ISO"

qm set "$TARGET_VMID" --ide2 "${AUTOINSTALL_ISO_REF},media=cdrom" &>/dev/null

msg_ok "GENERATED UBUNTU AUTOINSTALL ISO ATTACHED"

# --- 44. BOOT ORDER SETUP ---
# Boots the generated ISO first, then the OS disk.
msg_info "Setting VM boot order"

qm set "$TARGET_VMID" --boot "order=ide2;scsi0" &>/dev/null

msg_ok "VM BOOT ORDER CONFIGURED"

# --- 45. START VM ---
# Starts the VM so Ubuntu autoinstall can begin.
msg_info "Starting VM ${TARGET_VMID}"

qm start "$TARGET_VMID" &>/dev/null

msg_ok "VM STARTED"

# --- 46. COMPLETION MARKER ---
# Records what this script generated and attached.
cat > "$COMPLETED_MARKER" <<EOF
Ubuntu Auto Install ISO completed on: $(date)
VMID: $TARGET_VMID
VM Name: $TARGET_VM_NAME
VM MAC: $TARGET_VM_MAC
Hostname: $TARGET_HOSTNAME
Username: $TARGET_USERNAME
Timezone: $TARGET_TIMEZONE
Locale: $TARGET_LOCALE
Keyboard Layout: $TARGET_KEYBOARD_LAYOUT
Keyboard Variant: ${TARGET_KEYBOARD_VARIANT:-none}
Network Mode: $NETWORK_MODE
Source ISO: $INSTALL_ISO_REF
Generated ISO: $AUTOINSTALL_ISO_REF
EOF

# --- 47. FINAL NOTES ---
# Shows next steps.
echo ""
echo -e "${GN}FINISHED!${CL}"
echo -e "VM ID: ${GN}${TARGET_VMID}${CL}"
echo -e "VM NAME: ${GN}${TARGET_VM_NAME}${CL}"
echo -e "VM MAC: ${GN}${TARGET_VM_MAC}${CL}"
echo -e "SOURCE ISO: ${GN}${INSTALL_ISO_REF}${CL}"
echo -e "GENERATED AUTOINSTALL ISO: ${GN}${AUTOINSTALL_ISO_REF}${CL}"
echo -e "KEYBOARD: ${GN}${TARGET_KEYBOARD_LAYOUT}${CL}"
echo -e "LOCALE: ${GN}${TARGET_LOCALE}${CL}"
echo ""
echo -e "${YW}Watch the Proxmox console now. Ubuntu should boot directly into autoinstall without manual GRUB editing.${CL}"
echo -e "${YW}After Ubuntu finishes and reboots, SSH in as:${CL} ${GN}${TARGET_USERNAME}${CL}"
echo -e "${YW}Then run script 4 inside the Ubuntu VM.${CL}"
echo ""

exit 0