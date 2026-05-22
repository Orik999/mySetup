#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Ubuntu Auto Install
# =========================================================

# --- 1. COLOR VARIABLES / VISUAL THEME ---
# Keeps the visual theme centralized so colours can be changed easily later.
YW="$(printf '\033[33m')"
BL="$(printf '\033[36m')"
RD="$(printf '\033[01;31m')"
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

SCRIPT_SOURCE="3.5-ubuntuAutoInstallSeed.sh"
SCRIPT_VERSION="v1.2.0"
SCRIPT_UPDATED="2026-05-22"
SCRIPT_BUILD="audit-untimed-inputs-stability"

# --- 2. GLOBAL DEFAULTS ---
# Stores defaults, paths, timeout values and runtime state.
T=15
LOG_FILE="/var/log/ubuntu-autoinstall-seed.log"
VERIFY_LOG="/var/log/ubuntu-autoinstall-seed-verify.log"
COMPLETED_MARKER="/root/.ubuntu-autoinstall-seed-completed"

DEFAULT_USERNAME="orik"
DEFAULT_TIMEZONE="Europe/London"
DEFAULT_KEYBOARD_LAYOUT="gb"
DEFAULT_KEYBOARD_VARIANT=""
DEFAULT_LOCALE="en_GB.UTF-8"
DEFAULT_ISO_NAME="ubuntu-26.04-live-server-amd64.iso"

DEFAULT_INSTALL_WAIT_MINUTES="30"
INSTALL_WAIT_MINUTES="30"

POST_INSTALL_START_VM="y"
DELETE_GENERATED_ISO_AFTER_INSTALL="y"

SSH_IP_DETECT_TIMEOUT_SECONDS="90"
SSH_IP_CHECK_INTERVAL_SECONDS="3"

ASSIGNED_IPV4=""
SSH_COMMAND=""

TARGET_VMID=""
TARGET_VM_NAME=""
TARGET_VM_STATUS=""
TARGET_VM_MAC=""
TARGET_USERNAME=""
TARGET_TIMEZONE=""
TARGET_KEYBOARD_LAYOUT=""
TARGET_KEYBOARD_VARIANT=""
TARGET_LOCALE=""
TARGET_HOSTNAME=""

INSTALL_ISO_PATH=""
INSTALL_ISO_REF=""

AUTOINSTALL_ISO_NAME=""
AUTOINSTALL_ISO_PATH=""
AUTOINSTALL_ISO_REF=""
WORK_DIR=""

SSH_KEYS=""
KEY_SOURCE=""
SSH_KEYS_YAML=""
VERIFIER_B64=""
RANDOM_PASSWORD_HASH=""

NETWORK_MODE="dhcp"
STATIC_IP_CIDR=""
STATIC_GATEWAY=""
STATIC_DNS="1.1.1.1,1.0.0.1"

INSTALL_POWERED_OFF="no"

CLEANUP_INSTALLED_TOOLS="yes"
CLEANUP_TEMP_WORKFILES="yes"
INSTALLED_TOOL_PACKAGES=()
TEMP_FILES=()

REUSE_EXISTING_AUTOINSTALL_ISO="no"
GENERATED_ISO_EXISTS="no"
TOOLS_CHECKED="no"
MISSING_TOOL_PACKAGES=()

BOOT_PARAM='autoinstall ds=nocloud\;s=/cdrom/nocloud/ subiquity.autoinstallpath=cdrom/autoinstall.yaml'

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
# Displays a clear script banner. Intentionally says AUTO INSTALL, not just AUTO.
header_info() {
    echo -e "${BL}
██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗     █████╗ ██╗   ██╗████████╗ ██████╗     ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     
██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║    ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     
██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║    ███████║██║   ██║   ██║   ██║   ██║    ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     
██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║    ██╔══██║██║   ██║   ██║   ██║   ██║    ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     
╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝    ██║  ██║╚██████╔╝   ██║   ╚██████╔╝    ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
 ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝     ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
${CL}"
}

# --- 4. MESSAGE HELPERS ---
# Provides consistent Success / Warning / Error prefixes.
msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- SCRIPT VERSION DISPLAY ---
# Prints the currently running script version immediately under the ASCII banner.
function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

detail_line() {
    if [ "$#" -ge 2 ]; then
        echo -e "  ${DGN}━━━━━▶${CL} $1: ${GN}$2${CL}"
    else
        echo -e "  ${DGN}━━━━━▶${CL} $1"
    fi
}

# --- 5. TTY PRINT HELPERS ---
# Prints directly to terminal even when functions return values through stdout.
tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# =========================================================
#  CLEANUP / ERROR HANDLING
# =========================================================

# --- 6. CLEANUP FUNCTION ---
# Cleans temporary working files and uninstalls packages that were installed by this script.
cleanup() {
    local exit_code="$?"
    local pkg=""
    local file=""

    # Always remove small internal temporary files such as captured stderr logs.
    # The larger ISO build workspace is controlled separately by CLEANUP_TEMP_WORKFILES.
    for file in "${TEMP_FILES[@]:-}"; do
        if [ -n "$file" ] && [ -e "$file" ]; then
            if [ -n "${WORK_DIR:-}" ] && [ "$file" == "$WORK_DIR" ]; then
                continue
            fi
            rm -rf "$file" 2>/dev/null || true
        fi
    done

    if [ "$CLEANUP_TEMP_WORKFILES" == "yes" ] && [ "${DEBUG_KEEP_WORKDIR:-0}" != "1" ] && [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR" 2>/dev/null || true
    elif [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        echo ""
        echo -e "${YW}Temporary ISO workspace kept for inspection:${CL} ${GN}${WORK_DIR}${CL}"
    fi

    if [ "$CLEANUP_INSTALLED_TOOLS" == "yes" ] && [ "${#INSTALLED_TOOL_PACKAGES[@]}" -gt 0 ]; then
        echo ""
        echo -e "${YW}Cleaning up tools installed by this script...${CL}"

        for pkg in "${INSTALLED_TOOL_PACKAGES[@]}"; do
            [ -z "$pkg" ] && continue
            DEBIAN_FRONTEND=noninteractive apt-get purge -y "$pkg" >/dev/null 2>&1 || true
        done

        DEBIAN_FRONTEND=noninteractive apt-get autoremove -y >/dev/null 2>&1 || true
        echo -e "${GN}✓ TEMPORARY TOOL CLEANUP COMPLETE${CL}"
    fi

    exit "$exit_code"
}

# --- 7. ERROR TRAP ---
# Reports failing line while preserving normal cleanup.
on_error() {
    local line_no="$1"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"
}

# --- 8. COMMAND RUNNER ---
# Runs critical commands quietly but shows real stderr if they fail.
run_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

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

    rm -f "$err_file"
}

# --- 9. OPTIONAL COMMAND RUNNER ---
# Runs non-critical commands quietly and does not stop the script.
run_optional() {
    "$@" >/dev/null 2>&1 || true
}

# =========================================================
#  INPUT FUNCTIONS
# =========================================================

# --- 10. YES/NO LABEL HELPER ---
yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 11. BLOCKING YES/NO HELPER ---
# Used after SPACE is pressed during a timed Y/n prompt.
tty_read_yes_no_blocking() {
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

# --- 12. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown. SPACE pauses. Timeout accepts default.
timed_yes_no() {
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

# --- 13. NUMERIC VALIDATION HELPER ---
validate_number() {
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

print_number_error() {
    local min_value="${1:-1}"
    local max_value="${2:-}"

    if [ -n "$max_value" ]; then
        tty_println "${RD}Invalid input. Enter numbers only between ${min_value} and ${max_value}.${CL}"
    else
        tty_println "${RD}Invalid input. Enter numbers only. Minimum value is ${min_value}.${CL}"
    fi
}

# --- 14. EDITABLE INPUT LOOP HELPER ---
editable_input_loop() {
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
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""

    # Text/path/name inputs are deliberately NOT timed.
    # Countdown prompts are reserved only for simple Y/n decisions.
    # This prevents defaults being accepted while the user is away and gives enough time to type/paste.
    answer="$(editable_input_loop "$prompt" "$default" "no" "1" "" "")"
    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"

    echo "$answer"
}

# --- 16. TIMED NUMERIC INPUT HELPER ---
function timed_number_input() {
    local prompt="$1"
    local default="$2"
    local min_value="${3:-1}"
    local max_value="${4:-}"
    local answer=""

    # Numeric inputs are deliberately NOT timed.
    # Countdown prompts are reserved only for simple Y/n decisions.
    while true; do
        answer="$(editable_input_loop "$prompt" "$default" "yes" "$min_value" "$max_value" "")"
        [ -z "$answer" ] && answer="$default"

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
timed_menu_select() {
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

    idx="$(timed_number_input "Select ${title} option number" "$default_index" "1" "${#options[@]}")"
    selected="${options[$((idx-1))]}"

    echo "$selected"
}

# =========================================================
#  VALIDATION HELPERS
# =========================================================

# --- 18. UBUNTU USERNAME VALIDATOR ---
# Linux username rule: starts with lowercase letter or underscore, then lowercase letters, numbers, underscore or hyphen.
validate_linux_username() {
    local username="$1"

    if [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 0
    fi

    return 1
}

# --- 19. IPV4 VALIDATOR ---
# Validates dotted IPv4 address and octet range.
validate_ipv4() {
    local ip="$1"
    local a=""
    local b=""
    local c=""
    local d=""

    if ! [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    IFS='.' read -r a b c d <<< "$ip"

    for octet in "$a" "$b" "$c" "$d"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            return 1
        fi
    done

    return 0
}

# --- 20. IPV4 CIDR VALIDATOR ---
# Validates IPv4/CIDR format, for example 192.168.1.50/24.
validate_ipv4_cidr() {
    local value="$1"
    local ip=""
    local prefix=""

    if ! [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 1
    fi

    ip="${value%/*}"
    prefix="${value#*/}"

    validate_ipv4 "$ip" || return 1

    if [ "$prefix" -lt 1 ] || [ "$prefix" -gt 32 ]; then
        return 1
    fi

    return 0
}

# --- 21. DNS LIST VALIDATOR ---
# Validates comma-separated IPv4 DNS server list.
validate_dns_list() {
    local value="$1"
    local dns=""

    [ -z "$value" ] && return 1

    IFS=',' read -ra DNS_CHECK_ARRAY <<< "$value"

    for dns in "${DNS_CHECK_ARRAY[@]}"; do
        dns="$(echo "$dns" | xargs)"
        validate_ipv4 "$dns" || return 1
    done

    return 0
}

# =========================================================
#  GENERAL HELPERS
# =========================================================

# --- 22. YAML QUOTE HELPER ---
yaml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# --- 23. SAFE HOSTNAME HELPER ---
safe_hostname() {
    local value="$1"

    value="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
    value="$(echo "$value" | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"

    if [ -z "$value" ]; then
        value="ubuntu-vm"
    fi

    echo "$value"
}

# --- 24. VM STATUS HELPER ---
get_vm_status() {
    local vmid="$1"
    qm status "$vmid" 2>/dev/null | awk '{print $2}'
}

# --- 25. WAIT FOR VM POWEROFF HELPER ---
wait_for_vm_poweroff() {
    local vmid="$1"
    local timeout_minutes="$2"
    local timeout_seconds=$(( timeout_minutes * 60 ))
    local start_time=""
    local now_time=""
    local elapsed=""
    local status=""
    local elapsed_min=""
    local elapsed_sec=""

    start_time="$(date +%s)"

    section "INSTALL MONITORING"

    echo -e "${BL}Ubuntu autoinstall is running inside VM ${vmid}.${CL}"
    echo -e "${YW}Waiting for VM to power off after installation...${CL}"
    echo -e "${YW}Timeout: ${timeout_minutes} minutes.${CL}"
    echo -e "${YW}Do not manually restart the VM during this stage.${CL}"
    echo ""

    while true; do
        now_time="$(date +%s)"
        elapsed=$(( now_time - start_time ))
        elapsed_min=$(( elapsed / 60 ))
        elapsed_sec=$(( elapsed % 60 ))

        status="$(get_vm_status "$vmid")"

        if [ "$status" == "stopped" ]; then
            tty_print "${BFR}"
            msg_ok "VM ${vmid} POWERED OFF AFTER AUTOINSTALL (${elapsed_min}m ${elapsed_sec}s)"
            return 0
        fi

        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            tty_print "${BFR}"
            msg_warn "Autoinstall wait timeout reached. VM ${vmid} is still ${status:-unknown}."
            return 1
        fi

        tty_print "${BFR}${YW}Waiting for VM ${vmid} to power off... elapsed ${elapsed_min}m ${elapsed_sec}s / ${timeout_minutes}m, status=${status:-unknown}${CL}"
        sleep 10
    done
}

# --- 26. VM IPV4 DETECTION HELPER ---
get_vm_ipv4_from_guest_agent() {
    local vmid="$1"

    qm guest cmd "$vmid" network-get-interfaces 2>/dev/null | \
        grep -oE '"ip-address"[[:space:]]*:[[:space:]]*"([0-9]{1,3}\.){3}[0-9]{1,3}"' | \
        sed -E 's/.*"(([0-9]{1,3}\.){3}[0-9]{1,3})".*/\1/' | \
        grep -Ev '^(127\.|169\.254\.)' | \
        head -n 1
}

# --- 27. WAIT FOR VM IPV4 HELPER ---
# Progress goes to /dev/tty; only the final IPv4 goes to stdout.
wait_for_vm_ipv4() {
    local vmid="$1"
    local timeout_seconds="$2"
    local interval_seconds="$3"
    local start_time=""
    local now_time=""
    local elapsed=""
    local ip=""

    start_time="$(date +%s)"

    tty_println ""
    tty_println "${YW}Waiting for VM ${vmid} to report an IPv4 address through QEMU Guest Agent...${CL}"
    tty_println "${YW}This continues immediately when an IPv4 address appears. Timeout: ${timeout_seconds}s.${CL}"

    while true; do
        now_time="$(date +%s)"
        elapsed=$(( now_time - start_time ))

        ip="$(get_vm_ipv4_from_guest_agent "$vmid" || true)"

        if [ -n "$ip" ]; then
            tty_print "${BFR}"
            echo "$ip"
            return 0
        fi

        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            tty_print "${BFR}"
            echo ""
            return 1
        fi

        tty_print "${BFR}${YW}Waiting for assigned IPv4... elapsed ${elapsed}s / ${timeout_seconds}s${CL}"
        sleep "$interval_seconds"
    done
}

# --- 28. PATCH GRUB FILE HELPER ---
patch_grub_file() {
    local file="$1"
    local temp_file=""
    local line=""
    local default_present="no"

    [ -f "$file" ] || return 0

    if grep -q "^set default=" "$file"; then
        default_present="yes"
    fi

    temp_file="$(mktemp)"
    TEMP_FILES+=("$temp_file")

    if [ "$default_present" == "no" ]; then
        echo "set default=0" >> "$temp_file"
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^set[[:space:]]+timeout= ]]; then
            echo "set timeout=3" >> "$temp_file"
            continue
        fi

        if [[ "$line" =~ ^set[[:space:]]+default= ]]; then
            echo "set default=0" >> "$temp_file"
            continue
        fi

        if [[ "$line" == *'menuentry "Try or Install Ubuntu Server"'* ]]; then
            line="${line//menuentry \"Try or Install Ubuntu Server\"/menuentry \"AUTO-INSTALL Ubuntu Server\"}"
        fi

        if [[ "$line" == *"menuentry 'Try or Install Ubuntu Server'"* ]]; then
            line="${line//menuentry \'Try or Install Ubuntu Server\'/menuentry \'AUTO-INSTALL Ubuntu Server\'}"
        fi

        if [[ "$line" == *"/casper/vmlinuz"* ]]; then
            if [[ "$line" == *" ---"* ]]; then
                line="${line%% ---*} ${BOOT_PARAM} ---"
            else
                line="${line} ${BOOT_PARAM}"
            fi
        fi

        echo "$line" >> "$temp_file"
    done < "$file"

    cat "$temp_file" > "$file"
    rm -f "$temp_file"
}

# --- 29. NETWORK AUTOINSTALL YAML BUILDER ---
build_network_autoinstall_yaml() {
    if [ "$NETWORK_MODE" == "dhcp" ]; then
        cat <<EOF
network:
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
        local dns_yaml=""
        local dns=""
        IFS=',' read -ra DNS_ARRAY <<< "$STATIC_DNS"

        for dns in "${DNS_ARRAY[@]}"; do
            dns="$(echo "$dns" | xargs)"
            [ -n "$dns" ] && dns_yaml+="          - ${dns}"$'\n'
        done

        cat <<EOF
network:
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
${dns_yaml}
EOF
    fi
}

# --- 30. LOGIN VERIFIER BUILDER ---
build_verifier_base64() {
    local verifier_file="$1"

    cat > "$verifier_file" <<EOF
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
if sshd -T 2>/dev/null | grep -Eq "^permitrootlogin (no|prohibit-password|without-password)"; then PASS "Root SSH login disabled or passwordless-only"; else WARN "Root SSH login not confirmed secure"; fi
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
EOF

    base64 -w0 "$verifier_file"
}

# --- 31. AUTOINSTALL DIRECT CONFIG WRITER ---
write_direct_autoinstall_yaml() {
    local file="$1"

    cat > "$file" <<EOF
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
$(build_network_autoinstall_yaml)
storage:
  layout:
    name: lvm
late-commands:
  - curtin in-target --target=/target -- usermod -aG sudo ${TARGET_USERNAME}
  - curtin in-target --target=/target -- bash -c 'echo "${TARGET_USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${TARGET_USERNAME}-nopasswd'
  - curtin in-target --target=/target -- chmod 0440 /etc/sudoers.d/90-${TARGET_USERNAME}-nopasswd
  - curtin in-target --target=/target -- apt-get update
  - curtin in-target --target=/target -- bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -y qemu-guest-agent curl ca-certificates'
  - curtin in-target --target=/target -- systemctl enable qemu-guest-agent
  - curtin in-target --target=/target -- bash -c 'sed -i -E "s/^[#[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config'
  - curtin in-target --target=/target -- bash -c 'grep -q "^PasswordAuthentication" /etc/ssh/sshd_config || echo "PasswordAuthentication no" >> /etc/ssh/sshd_config'
  - curtin in-target --target=/target -- bash -c 'sed -i -E "s/^[#[:space:]]*PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config'
  - curtin in-target --target=/target -- bash -c 'grep -q "^PermitRootLogin" /etc/ssh/sshd_config || echo "PermitRootLogin no" >> /etc/ssh/sshd_config'
  - curtin in-target --target=/target -- bash -c 'sed -i -E "s/^[#[:space:]]*AddressFamily.*/AddressFamily inet/" /etc/ssh/sshd_config'
  - curtin in-target --target=/target -- bash -c 'grep -q "^AddressFamily" /etc/ssh/sshd_config || echo "AddressFamily inet" >> /etc/ssh/sshd_config'
  - curtin in-target --target=/target -- bash -c 'date > /var/log/ubuntu-autoinstall-completed'
  - curtin in-target --target=/target -- bash -c 'echo "${VERIFIER_B64}" | base64 -d > /etc/profile.d/ubuntu-autoinstall-verify-display.sh'
  - curtin in-target --target=/target -- chmod +x /etc/profile.d/ubuntu-autoinstall-verify-display.sh
shutdown: poweroff
EOF
}

# --- 32. CLOUD-CONFIG USER-DATA WRITER ---
write_cloud_config_user_data() {
    local source_file="$1"
    local output_file="$2"

    {
        echo "#cloud-config"
        echo "autoinstall:"
        sed 's/^/  /' "$source_file"
    } > "$output_file"
}

# =========================================================
#  VALIDATION / INITIALIZATION
# =========================================================

# --- 33. DEPENDENCY VALIDATION ---
validate_dependencies() {
    local required_commands=(
        awk
        base64
        basename
        cat
        chmod
        cut
        date
        dpkg
        env
        find
        grep
        head
        mkdir
        mktemp
        openssl
        pveversion
        qm
        rm
        sed
        sleep
        sort
        tee
        tr
        xargs
    )

    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done
}

# --- 34. PROXMOX VALIDATION ---
validate_proxmox() {
    local pve_major=""

    if ! command -v pveversion >/dev/null 2>&1; then
        msg_error "This system is not Proxmox VE. Script cancelled."
    fi

    pve_major="$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)"

    if ! [[ "$pve_major" =~ ^[0-9]+$ ]] || [ "$pve_major" -lt 9 ]; then
        msg_error "Requires Proxmox VE 9+."
    fi
}

# --- 35. TOOL INSTALLATION ---
# Installs required temporary ISO tooling only if missing, then cleanup removes only packages installed by this script.
ensure_tools() {
    local missing_packages=()
    local pkg=""
    local install_yn=""

    section "ISO TOOL CHECK"

    msg_info "Checking required ISO tools"

    for pkg in xorriso rsync p7zip-full; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing_packages+=("$pkg")
        fi
    done

    MISSING_TOOL_PACKAGES=("${missing_packages[@]}")
    TOOLS_CHECKED="yes"

    if [ "${#missing_packages[@]}" -gt 0 ]; then
        msg_warn "Missing required tools: ${missing_packages[*]}"
        echo ""
        echo -e "${YW}These packages are required only when creating or verifying a generated autoinstall ISO.${CL}"
        echo -e "${YW}Packages already installed before this script will not be removed by cleanup.${CL}"
        echo ""

        install_yn="$(timed_yes_no "Install missing ISO tools now?" "y")"

        if [[ "$install_yn" =~ ^[Nn] ]]; then
            msg_error "Required ISO tools are missing. Cannot create a new autoinstall ISO."
        fi

        msg_info "Installing missing ISO tools"
        run_cmd "updating APT package lists before tool install" env DEBIAN_FRONTEND=noninteractive apt-get update

        for pkg in "${missing_packages[@]}"; do
            run_cmd "installing ${pkg}" env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
            INSTALLED_TOOL_PACKAGES+=("$pkg")
        done

        msg_ok "MISSING ISO TOOLS INSTALLED"
    else
        msg_ok "REQUIRED ISO TOOLS ALREADY INSTALLED"
        detail_line "Tool cleanup" "not needed; no packages installed by this script"
    fi

    command -v xorriso >/dev/null 2>&1 || msg_error "xorriso is required."
}

# --- 35A. EARLY CLEANUP PREFERENCES ---
# Collects cleanup decisions before package installation, work directories, ISO writes, or VM changes.
# This keeps reruns predictable and ensures the user decides cleanup behaviour at the beginning.
collect_early_cleanup_preferences() {
    local tool_cleanup_yn=""
    local temp_cleanup_yn=""
    local iso_cleanup_yn=""

    section "CLEANUP PREFERENCES"

    echo -e "${YW}These choices are collected before any package install, temporary workspace, generated ISO, or VM change.${CL}"
    echo -e "${YW}Already-installed ISO tools will never be removed. Only tools installed by this run are eligible for cleanup.${CL}"
    echo ""

    tool_cleanup_yn="$(timed_yes_no "Remove ISO tools installed by this script when finished?" "y")"
    if [[ "$tool_cleanup_yn" =~ ^[Nn] ]]; then
        CLEANUP_INSTALLED_TOOLS="no"
    else
        CLEANUP_INSTALLED_TOOLS="yes"
    fi

    temp_cleanup_yn="$(timed_yes_no "Remove temporary ISO build workspace when finished?" "y")"
    if [[ "$temp_cleanup_yn" =~ ^[Nn] ]]; then
        CLEANUP_TEMP_WORKFILES="no"
    else
        CLEANUP_TEMP_WORKFILES="yes"
    fi

    iso_cleanup_yn="$(timed_yes_no "Delete generated autoinstall ISO after successful install?" "y")"
    if [[ "$iso_cleanup_yn" =~ ^[Nn] ]]; then
        DELETE_GENERATED_ISO_AFTER_INSTALL="n"
    else
        DELETE_GENERATED_ISO_AFTER_INSTALL="y"
    fi

    detail_line "Cleanup installed tools" "$CLEANUP_INSTALLED_TOOLS"
    detail_line "Cleanup temporary workspace" "$CLEANUP_TEMP_WORKFILES"
    detail_line "Delete generated ISO after install" "$DELETE_GENERATED_ISO_AFTER_INSTALL"
}

# --- 35B. GENERATED ISO PATH PREPARATION ---
# Calculates the generated ISO path before any work directory or file changes are made.
set_autoinstall_iso_paths() {
    AUTOINSTALL_ISO_NAME="ubuntu-26.04-autoinstall-vm${TARGET_VMID}.iso"
    AUTOINSTALL_ISO_PATH="/var/lib/vz/template/iso/${AUTOINSTALL_ISO_NAME}"
    AUTOINSTALL_ISO_REF="local:iso/${AUTOINSTALL_ISO_NAME}"
}

# --- 35C. GENERATED ISO REUSE / RECREATE PREFLIGHT ---
# Handles reruns before work directories, ISO writes, VM shutdowns, or VM config changes.
precheck_generated_iso_reuse() {
    local reuse_yn=""
    local recreate_yn=""

    set_autoinstall_iso_paths

    section "RERUN / GENERATED ISO PREFLIGHT"

    detail_line "Expected generated ISO" "$AUTOINSTALL_ISO_PATH"

    if [ -f "$AUTOINSTALL_ISO_PATH" ]; then
        GENERATED_ISO_EXISTS="yes"
        msg_warn "Generated autoinstall ISO already exists"
        echo ""
        echo -e "${YW}You can reuse it to redeploy the VM without rebuilding the ISO, or recreate it with the current answers.${CL}"
        echo ""

        reuse_yn="$(timed_yes_no "Reuse existing generated ISO?" "y")"

        if [[ "$reuse_yn" =~ ^[Yy] ]]; then
            REUSE_EXISTING_AUTOINSTALL_ISO="yes"
            msg_ok "EXISTING GENERATED ISO WILL BE REUSED"
            return 0
        fi

        recreate_yn="$(timed_yes_no "Recreate and replace existing generated ISO?" "y")"

        if [[ "$recreate_yn" =~ ^[Nn] ]]; then
            msg_error "Existing generated ISO was not reused or replaced. Script cancelled before changes."
        fi

        REUSE_EXISTING_AUTOINSTALL_ISO="no"
        msg_ok "EXISTING GENERATED ISO WILL BE REPLACED DURING ISO BUILD"
    else
        GENERATED_ISO_EXISTS="no"
        REUSE_EXISTING_AUTOINSTALL_ISO="no"
        msg_ok "NO EXISTING GENERATED ISO FOUND"
    fi
}

# --- 36. PREVIOUS RUN MARKER CHECK ---
check_previous_marker() {
    local continue_yn=""

    if [ -f "$COMPLETED_MARKER" ]; then
        section "PREVIOUS UBUNTU AUTO INSTALL MARKER DETECTED"

        echo -e "${YW}A previous Ubuntu Auto Install marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        cat "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi
}

# --- 37. INITIALIZATION ---
init_script() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RD}Please run as root.${CL}"
        exit 1
    fi

    exec > >(tee -a "$LOG_FILE") 2>&1

    trap 'on_error "$LINENO"' ERR
    trap cleanup EXIT

    clear
    header_info
    show_script_version

    validate_dependencies
    validate_proxmox
}

# =========================================================
#  INPUT COLLECTION
# =========================================================

# --- 38. START WARNING ---
show_start_warning() {
    echo -e "${YW}This script creates a generated Ubuntu 26.04 autoinstall ISO copy.${CL}"
    echo -e "${YW}The original Ubuntu ISO remains untouched.${CL}"
    echo -e "${YW}Written for: ${GN}${DEFAULT_ISO_NAME}${CL}"
    echo ""
    echo -e "${RD}WARNING:${CL} Ubuntu autoinstall can erase the selected VM install disk."
    echo -e "${YW}For best results, use a fresh VM created by script 3-proxmoxVMsetup with one OS disk.${CL}"
    echo ""
}

# --- 39. VM SELECTION ---
select_vm() {
    local vmid=""
    local name=""
    local status=""
    local default_vm_index="1"
    local highest_vmid="0"
    local vm_index=""

    section "VM SELECTION"

    msg_info "Detecting Proxmox VMs"

    mapfile -t VM_LINES < <(qm list | awk 'NR>1 {print $1 "|" $2 "|" $3}')

    if [ "${#VM_LINES[@]}" -eq 0 ]; then
        msg_error "No VMs found. Run script 3 first, then run this script."
    fi

    msg_ok "PROXMOX VMS DETECTED"

    echo ""
    echo -e "${BL}AVAILABLE VMS:${CL}"

    for i in "${!VM_LINES[@]}"; do
        vmid="$(echo "${VM_LINES[$i]}" | cut -d'|' -f1)"
        name="$(echo "${VM_LINES[$i]}" | cut -d'|' -f2)"
        status="$(echo "${VM_LINES[$i]}" | cut -d'|' -f3)"

        if [ "$vmid" -gt "$highest_vmid" ]; then
            highest_vmid="$vmid"
            default_vm_index="$((i+1))"
        fi

        echo "$((i+1))) ${vmid} | ${name} | ${status}"
    done

    [ "${#VM_LINES[@]}" -eq 1 ] && default_vm_index="1"

    vm_index="$(timed_number_input "Select VM for Ubuntu autoinstall" "$default_vm_index" "1" "${#VM_LINES[@]}")"

    TARGET_VMID="$(echo "${VM_LINES[$((vm_index-1))]}" | cut -d'|' -f1)"
    TARGET_VM_NAME="$(echo "${VM_LINES[$((vm_index-1))]}" | cut -d'|' -f2)"
    TARGET_VM_STATUS="$(echo "${VM_LINES[$((vm_index-1))]}" | cut -d'|' -f3)"

    qm config "$TARGET_VMID" >/dev/null 2>&1 || msg_error "Selected VM ${TARGET_VMID} does not exist."

    if [ "$TARGET_VM_STATUS" == "running" ]; then
        msg_warn "VM ${TARGET_VMID} is running; it will not be stopped until final apply."
    fi

    detail_line "Selected VM" "${TARGET_VMID} / ${TARGET_VM_NAME} / ${TARGET_VM_STATUS}"
}

# --- 39A. VM STOP SAFETY BEFORE APPLY ---
# Stops the selected VM only after all prechecks, ISO decisions and final confirmation are complete.
ensure_vm_stopped_before_apply() {
    local shutdown_yn=""
    local current_status=""

    current_status="$(get_vm_status "$TARGET_VMID")"
    TARGET_VM_STATUS="${current_status:-unknown}"

    if [ "$TARGET_VM_STATUS" != "running" ]; then
        return 0
    fi

    section "VM SHUTDOWN BEFORE APPLY"

    msg_warn "VM ${TARGET_VMID} is currently running"
    echo -e "${YW}The VM must be stopped before attaching installer media safely.${CL}"
    echo ""

    shutdown_yn="$(timed_yes_no "Shutdown VM now?" "y")"

    if [[ "$shutdown_yn" =~ ^[Yy] ]]; then
        msg_info "Shutting down VM ${TARGET_VMID}"
        if qm shutdown "$TARGET_VMID" --timeout 60 >/dev/null 2>&1; then
            msg_ok "VM SHUTDOWN COMPLETE"
        else
            msg_warn "Graceful shutdown failed or timed out; forcing stop"
            run_cmd "stopping VM ${TARGET_VMID}" qm stop "$TARGET_VMID"
            msg_ok "VM STOPPED"
        fi
        TARGET_VM_STATUS="stopped"
    else
        msg_error "VM must be stopped before attaching install media safely."
    fi
}

# --- 40. VM MAC DETECTION ---
detect_vm_mac() {
    msg_info "Detecting VM MAC address"

    TARGET_VM_MAC="$(qm config "$TARGET_VMID" | awk -F'[=,]' '/^net0:/ {print $2; exit}' | tr '[:lower:]' '[:upper:]')"

    if [ -z "$TARGET_VM_MAC" ]; then
        msg_error "Could not detect net0 MAC address for VM ${TARGET_VMID}. Check: qm config ${TARGET_VMID}"
    fi

    msg_ok "VM MAC DETECTED (${TARGET_VM_MAC})"
}

# --- 41. USER / LOCALE INPUTS ---
collect_user_locale_inputs() {
    local keyboard_choice=""

    section "IDENTITY / LOCALE"

    while true; do
        TARGET_USERNAME="$(timed_text_input "Enter Ubuntu admin username" "$DEFAULT_USERNAME")"

        if validate_linux_username "$TARGET_USERNAME"; then
            break
        fi

        msg_warn "Invalid username. Use lowercase Linux username format, for example: orik"
    done

    TARGET_TIMEZONE="$(timed_text_input "Enter timezone" "$DEFAULT_TIMEZONE")"
    TARGET_LOCALE="$(timed_text_input "Enter Ubuntu locale" "$DEFAULT_LOCALE")"

    keyboard_choice="$(timed_menu_select "Keyboard Layout" "1" \
        "UK / British keyboard (gb)" \
        "US keyboard (us)" \
        "Custom keyboard layout")"

    case "$keyboard_choice" in
        "UK / British keyboard (gb)")
            TARGET_KEYBOARD_LAYOUT="gb"
            TARGET_KEYBOARD_VARIANT=""
            ;;
        "US keyboard (us)")
            TARGET_KEYBOARD_LAYOUT="us"
            TARGET_KEYBOARD_VARIANT=""
            ;;
        *)
            TARGET_KEYBOARD_LAYOUT="$(timed_text_input "Enter keyboard layout code" "$DEFAULT_KEYBOARD_LAYOUT")"
            TARGET_KEYBOARD_VARIANT="$(timed_text_input "Enter keyboard variant or leave blank" "$DEFAULT_KEYBOARD_VARIANT")"
            ;;
    esac

    TARGET_HOSTNAME="$(safe_hostname "$TARGET_VM_NAME")"
}

# --- 42. SSH KEY DETECTION ---
detect_ssh_keys() {
    section "SSH KEY DETECTION"

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
}

# --- 43. NETWORK INPUTS ---
collect_network_inputs() {
    local dhcp_yn=""

    section "NETWORK CONFIGURATION"

    echo -e "${YW}Recommended: use DHCP here and reserve static IP in your router using this MAC:${CL} ${GN}${TARGET_VM_MAC}${CL}"
    echo ""

    dhcp_yn="$(timed_yes_no "Use DHCP networking inside Ubuntu?" "y")"

    if [[ "$dhcp_yn" =~ ^[Nn] ]]; then
        NETWORK_MODE="static"

        while true; do
            STATIC_IP_CIDR="$(timed_text_input "Enter static IP/CIDR" "192.168.1.50/24")"
            validate_ipv4_cidr "$STATIC_IP_CIDR" && break
            msg_warn "Invalid static IP/CIDR. Example: 192.168.1.50/24"
        done

        while true; do
            STATIC_GATEWAY="$(timed_text_input "Enter gateway IP" "192.168.1.1")"
            validate_ipv4 "$STATIC_GATEWAY" && break
            msg_warn "Invalid gateway IPv4 address. Example: 192.168.1.1"
        done

        while true; do
            STATIC_DNS="$(timed_text_input "Enter DNS servers comma-separated" "$STATIC_DNS")"
            validate_dns_list "$STATIC_DNS" && break
            msg_warn "Invalid DNS list. Example: 1.1.1.1,1.0.0.1"
        done
    else
        NETWORK_MODE="dhcp"
    fi
}

# --- 44. POST-INSTALL INPUTS ---
collect_post_install_options() {
    local start_installed_yn=""

    section "POST-INSTALL OPTIONS"

    INSTALL_WAIT_MINUTES="$(timed_number_input "Enter autoinstall wait timeout in minutes" "$DEFAULT_INSTALL_WAIT_MINUTES" "10" "240")"

    echo -e "${YW}Generated ISO deletion was already selected during early cleanup preferences:${CL} ${GN}${DELETE_GENERATED_ISO_AFTER_INSTALL}${CL}"
    echo ""

    start_installed_yn="$(timed_yes_no "Start installed Ubuntu VM after cleanup?" "y")"
    [[ "$start_installed_yn" =~ ^[Nn] ]] && POST_INSTALL_START_VM="n" || POST_INSTALL_START_VM="y"
}

# --- 45. UBUNTU ISO SELECTION ---
select_ubuntu_iso() {
    local default_iso_index="1"
    local iso_base=""
    local iso_index=""

    section "ISO SELECTION"

    msg_info "Finding Ubuntu install ISO"

    mapfile -t ISOS < <(find /var/lib/vz/template/iso -maxdepth 1 -type f -iname "*.iso" ! -iname "*autoinstall*" ! -iname "*seed*" | sort || true)

    if [ "${#ISOS[@]}" -eq 0 ]; then
        msg_error "No original ISO files found in /var/lib/vz/template/iso."
    fi

    msg_ok "ISO FILES FOUND"

    echo ""
    echo -e "${BL}SELECT SOURCE UBUNTU INSTALL ISO:${CL}"

    for i in "${!ISOS[@]}"; do
        iso_base="$(basename "${ISOS[$i]}")"
        [ "$iso_base" == "$DEFAULT_ISO_NAME" ] && default_iso_index="$((i+1))"
        echo "$((i+1))) ${iso_base}"
    done

    iso_index="$(timed_number_input "Select Ubuntu ISO number" "$default_iso_index" "1" "${#ISOS[@]}")"
    INSTALL_ISO_PATH="${ISOS[$((iso_index-1))]}"
    INSTALL_ISO_REF="local:iso/$(basename "$INSTALL_ISO_PATH")"
}

# --- 46. UBUNTU PRO NOTE ---
show_ubuntu_pro_note() {
    echo ""
    echo -e "${BL}UBUNTU PRO:${CL}"
    echo -e "${YW}Ubuntu Pro is intentionally not attached by this script.${CL}"
    echo -e "${YW}script 4-ubuntuVMsetup can attach Ubuntu Pro later, or manually use:${CL} ${GN}sudo pro attach <token>${CL}"
    echo ""
}

# =========================================================
#  ISO / AUTOINSTALL GENERATION
# =========================================================

# --- 47. PREPARE WORKSPACE ---
prepare_workspace() {
    WORK_DIR="$(mktemp -d "/tmp/ubuntu-autoinstall-vm${TARGET_VMID}.XXXXXX")"
    TEMP_FILES+=("$WORK_DIR")

    mkdir -p "$WORK_DIR/nocloud"
    mkdir -p "$WORK_DIR/grub"
    mkdir -p "$WORK_DIR/verify"
}

# --- 47A. EXISTING GENERATED ISO VALIDATION ---
# Lightweight validation for reuse mode. It avoids modifying files or VM config.
verify_reused_generated_iso() {
    section "REUSED ISO CHECK"

    if [ ! -s "$AUTOINSTALL_ISO_PATH" ]; then
        msg_error "Selected reuse ISO is missing or empty: ${AUTOINSTALL_ISO_PATH}"
    fi

    msg_ok "EXISTING GENERATED ISO FOUND"
    detail_line "Generated ISO" "$AUTOINSTALL_ISO_REF"

    if command -v xorriso >/dev/null 2>&1; then
        msg_info "Quick-checking reused ISO boot data"
        if xorriso -indev "$AUTOINSTALL_ISO_PATH" -report_el_torito plain >/dev/null 2>&1; then
            msg_ok "REUSED ISO BOOT DATA READABLE"
        else
            msg_warn "Could not read reused ISO boot data with xorriso. You may recreate it if boot fails."
        fi
    else
        msg_warn "xorriso not installed; reused ISO was not deep-verified. This is acceptable for reuse mode."
    fi
}

# --- 48. BUILD SSH KEY YAML ---
build_ssh_key_yaml() {
    SSH_KEYS_YAML=""

    while IFS= read -r keyline; do
        [ -z "$keyline" ] && continue
        SSH_KEYS_YAML+="      - $(yaml_quote "$keyline")"$'\n'
    done <<< "$SSH_KEYS"
}

# --- 49. WRITE NETWORK CONFIG ---
write_nocloud_network_config() {
    local dns_yaml=""
    local dns=""

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
        IFS=',' read -ra DNS_ARRAY <<< "$STATIC_DNS"

        for dns in "${DNS_ARRAY[@]}"; do
            dns="$(echo "$dns" | xargs)"
            [ -n "$dns" ] && dns_yaml+="        - ${dns}"$'\n'
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
${dns_yaml}
EOF
    fi
}

# --- 50. WRITE META-DATA ---
write_metadata() {
cat > "${WORK_DIR}/nocloud/meta-data" <<EOF
instance-id: ubuntu-autoinstall-vm${TARGET_VMID}
local-hostname: ${TARGET_HOSTNAME}
EOF
}

# --- 51. WRITE AUTOINSTALL CONFIG ---
write_autoinstall_config() {
    section "AUTOINSTALL CONFIGURATION"

    msg_info "Creating Ubuntu autoinstall configuration"

    RANDOM_PASSWORD_HASH="$(openssl passwd -6 "$(openssl rand -base64 48)")"
    build_ssh_key_yaml
    VERIFIER_B64="$(build_verifier_base64 "${WORK_DIR}/ubuntu-autoinstall-verify-display.sh")"

    write_direct_autoinstall_yaml "${WORK_DIR}/autoinstall.yaml"
    write_cloud_config_user_data "${WORK_DIR}/autoinstall.yaml" "${WORK_DIR}/nocloud/user-data"

    if grep -q "^#!/usr/bin/env bash" "${WORK_DIR}/autoinstall.yaml"; then
        msg_error "Generated autoinstall.yaml contains an unindented shell script and would fail YAML parsing."
    fi

    if ! grep -q "^shutdown: poweroff" "${WORK_DIR}/autoinstall.yaml"; then
        msg_error "Generated autoinstall.yaml must use shutdown: poweroff to prevent reinstall loops."
    fi

    msg_ok "UBUNTU AUTOINSTALL CONFIGURATION CREATED"
}

# --- 52. EXTRACT GRUB CONFIGS ---
extract_grub_configs() {
    section "BOOT CONFIG EXTRACTION"

    msg_info "Extracting Ubuntu boot configuration"

    run_cmd "extracting /boot/grub/grub.cfg from source ISO" \
        xorriso -osirrox on -indev "$INSTALL_ISO_PATH" -extract /boot/grub/grub.cfg "$WORK_DIR/grub/grub.cfg"

    xorriso -osirrox on -indev "$INSTALL_ISO_PATH" -extract /boot/grub/loopback.cfg "$WORK_DIR/grub/loopback.cfg" &>/dev/null || true

    msg_ok "UBUNTU BOOT CONFIGURATION EXTRACTED"
}

# --- 53. PATCH BOOT PARAMETERS ---
patch_boot_parameters() {
    section "BOOT PARAMETER PATCHING"

    msg_info "Patching Ubuntu autoinstall boot parameters"

    patch_grub_file "$WORK_DIR/grub/grub.cfg"
    patch_grub_file "$WORK_DIR/grub/loopback.cfg"

    if ! grep -q "AUTO-INSTALL Ubuntu Server" "$WORK_DIR/grub/grub.cfg"; then
        msg_error "Autoinstall menu title was not injected into grub.cfg."
    fi

    if ! grep -q "ds=nocloud" "$WORK_DIR/grub/grub.cfg"; then
        msg_error "NoCloud boot parameter was not injected into grub.cfg."
    fi

    if ! grep -q "subiquity.autoinstallpath" "$WORK_DIR/grub/grub.cfg"; then
        msg_error "Subiquity autoinstall path was not injected into grub.cfg."
    fi

    msg_ok "AUTOINSTALL BOOT PARAMETERS PATCHED"
}

# --- 54. BUILD GENERATED ISO ---
build_generated_iso() {
    section "AUTOINSTALL ISO BUILD"

    msg_info "Building generated Ubuntu autoinstall ISO copy"

    rm -f "$AUTOINSTALL_ISO_PATH"

    XORRISO_ARGS=(
        -indev "$INSTALL_ISO_PATH"
        -outdev "$AUTOINSTALL_ISO_PATH"
        -boot_image any replay
        -map "$WORK_DIR/autoinstall.yaml" /autoinstall.yaml
        -map "$WORK_DIR/nocloud" /nocloud
        -map "$WORK_DIR/grub/grub.cfg" /boot/grub/grub.cfg
    )

    if [ -f "$WORK_DIR/grub/loopback.cfg" ]; then
        XORRISO_ARGS+=(
            -map "$WORK_DIR/grub/loopback.cfg" /boot/grub/loopback.cfg
        )
    fi

    run_cmd "building generated Ubuntu autoinstall ISO copy" xorriso "${XORRISO_ARGS[@]}"

    if [ ! -s "$AUTOINSTALL_ISO_PATH" ]; then
        msg_error "Generated Ubuntu autoinstall ISO was not created."
    fi

    msg_ok "GENERATED AUTOINSTALL ISO CREATED (${AUTOINSTALL_ISO_REF})"
}

# --- 55. VERIFY GENERATED ISO ---
verify_generated_iso() {
    section "AUTOINSTALL ISO VERIFICATION"

    msg_info "Verifying generated autoinstall ISO"

    rm -rf "$WORK_DIR/verify"
    mkdir -p "$WORK_DIR/verify"

    run_cmd "verifying generated ISO grub.cfg" \
        xorriso -osirrox on -indev "$AUTOINSTALL_ISO_PATH" -extract /boot/grub/grub.cfg "$WORK_DIR/verify/grub.cfg"

    run_cmd "verifying generated ISO /autoinstall.yaml" \
        xorriso -osirrox on -indev "$AUTOINSTALL_ISO_PATH" -extract /autoinstall.yaml "$WORK_DIR/verify/autoinstall.yaml"

    run_cmd "verifying generated ISO /nocloud/user-data" \
        xorriso -osirrox on -indev "$AUTOINSTALL_ISO_PATH" -extract /nocloud/user-data "$WORK_DIR/verify/user-data"

    grep -q "AUTO-INSTALL Ubuntu Server" "$WORK_DIR/verify/grub.cfg" || msg_error "Generated ISO boot menu title was not patched."
    grep -q "ds=nocloud" "$WORK_DIR/verify/grub.cfg" || msg_error "Generated ISO is missing NoCloud boot parameter."
    grep -q "subiquity.autoinstallpath" "$WORK_DIR/verify/grub.cfg" || msg_error "Generated ISO is missing Subiquity autoinstall path parameter."
    grep -q "^version: 1" "$WORK_DIR/verify/autoinstall.yaml" || msg_error "Generated ISO /autoinstall.yaml is not valid direct autoinstall format."
    grep -q "^shutdown: poweroff" "$WORK_DIR/verify/autoinstall.yaml" || msg_error "Generated ISO /autoinstall.yaml is missing shutdown: poweroff."
    ! grep -q "^#!/usr/bin/env bash" "$WORK_DIR/verify/autoinstall.yaml" || msg_error "Generated ISO /autoinstall.yaml contains unindented shell script content."
    grep -q "^#cloud-config" "$WORK_DIR/verify/user-data" || msg_error "Generated ISO /nocloud/user-data is missing #cloud-config header."

    msg_ok "GENERATED AUTOINSTALL ISO VERIFIED"
}

# --- 56. GENERATE AUTOINSTALL ISO ---
generate_autoinstall_iso() {
    if [ "$REUSE_EXISTING_AUTOINSTALL_ISO" == "yes" ]; then
        verify_reused_generated_iso
        return 0
    fi

    prepare_workspace
    write_nocloud_network_config
    write_metadata
    write_autoinstall_config
    extract_grub_configs
    patch_boot_parameters
    build_generated_iso
    verify_generated_iso
}

# =========================================================
#  APPLY / EXECUTION
# =========================================================

# --- 57. FINAL SUMMARY BEFORE APPLY ---
show_apply_summary() {
    section "READY TO APPLY"

    echo -e "VM ID: ${GN}${TARGET_VMID}${CL}"
    echo -e "VM NAME: ${GN}${TARGET_VM_NAME}${CL}"
    echo -e "VM STATUS: ${GN}${TARGET_VM_STATUS}${CL}"
    echo -e "VM MAC: ${GN}${TARGET_VM_MAC}${CL}"
    echo -e "UBUNTU HOSTNAME: ${GN}${TARGET_HOSTNAME}${CL}"
    echo -e "UBUNTU USER: ${GN}${TARGET_USERNAME}${CL}"
    echo -e "TIMEZONE: ${GN}${TARGET_TIMEZONE}${CL}"
    echo -e "LOCALE: ${GN}${TARGET_LOCALE}${CL}"
    echo -e "VERIFY LOG: ${GN}${VERIFY_LOG}${CL}"
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
    echo -e "REUSE EXISTING ISO: ${GN}${REUSE_EXISTING_AUTOINSTALL_ISO}${CL}"
    echo -e "WAIT TIMEOUT: ${GN}${INSTALL_WAIT_MINUTES} minutes${CL}"
    echo -e "DELETE GENERATED ISO AFTER INSTALL: ${GN}${DELETE_GENERATED_ISO_AFTER_INSTALL}${CL}"
    echo -e "CLEANUP TEMP WORKSPACE: ${GN}${CLEANUP_TEMP_WORKFILES}${CL}"
    echo -e "CLEANUP INSTALLED TOOLS: ${GN}${CLEANUP_INSTALLED_TOOLS}${CL}"
    echo -e "START INSTALLED VM AFTER CLEANUP: ${GN}${POST_INSTALL_START_VM}${CL}"
    echo -e "IP DETECTION TIMEOUT: ${GN}${SSH_IP_DETECT_TIMEOUT_SECONDS}s${CL}"
    echo ""
    echo -e "${RD}WARNING:${CL} Starting this VM can begin Ubuntu autoinstall and wipe its VM disk."
    echo ""
    echo -e "${YW}After install, Ubuntu should power off. This script will then detach installer media and boot from disk.${CL}"
    echo ""
}

# --- 58. ATTACH AND START INSTALL ---
attach_iso_and_start_install() {
    ensure_vm_stopped_before_apply

    section "ATTACH INSTALLER AND START VM"

    msg_info "Attaching generated Ubuntu autoinstall ISO"
    run_cmd "attaching generated Ubuntu autoinstall ISO" qm set "$TARGET_VMID" --ide2 "${AUTOINSTALL_ISO_REF},media=cdrom"
    msg_ok "GENERATED UBUNTU AUTOINSTALL ISO ATTACHED"

    msg_info "Setting VM boot order to installer first"
    run_cmd "setting VM boot order to installer first" qm set "$TARGET_VMID" --boot "order=ide2;scsi0"
    msg_ok "VM BOOT ORDER CONFIGURED"

    msg_info "Starting VM ${TARGET_VMID} for Ubuntu autoinstall"
    run_cmd "starting VM ${TARGET_VMID} for Ubuntu autoinstall" qm start "$TARGET_VMID"
    msg_ok "VM STARTED FOR AUTOINSTALL"
}

# --- 59. POST-INSTALL CLEANUP ---
post_install_cleanup() {
    section "POST-INSTALL CLEANUP"

    if wait_for_vm_poweroff "$TARGET_VMID" "$INSTALL_WAIT_MINUTES"; then
        INSTALL_POWERED_OFF="yes"
    else
        INSTALL_POWERED_OFF="no"
    fi

    if [ "$INSTALL_POWERED_OFF" != "yes" ]; then
        echo ""
        echo -e "${RD}AUTOINSTALL DID NOT REACH POWEROFF BEFORE TIMEOUT.${CL}"
        echo -e "${YW}Leaving installer ISO attached for troubleshooting.${CL}"
        echo -e "${YW}Check the Proxmox console for installer errors.${CL}"
        echo ""
        echo -e "${YW}Useful host checks:${CL}"
        echo -e "${GN}qm config ${TARGET_VMID} | grep -E \"ide2|boot\"${CL}"
        echo -e "${GN}xorriso -indev ${AUTOINSTALL_ISO_PATH} -report_el_torito plain${CL}"
        echo ""
        exit 1
    fi

    msg_info "Detaching generated autoinstall ISO from VM"
    run_cmd "detaching installer ISO from VM" qm set "$TARGET_VMID" --delete ide2
    msg_ok "INSTALLER ISO DETACHED FROM VM"

    msg_info "Setting VM boot order to installed disk"
    run_cmd "setting VM boot order to installed disk" qm set "$TARGET_VMID" --boot "order=scsi0"
    msg_ok "VM BOOT ORDER SET TO INSTALLED DISK"

    if [ "$DELETE_GENERATED_ISO_AFTER_INSTALL" == "y" ]; then
        msg_info "Deleting generated autoinstall ISO"
        rm -f "$AUTOINSTALL_ISO_PATH"
        msg_ok "GENERATED AUTOINSTALL ISO DELETED"
    else
        msg_warn "Generated autoinstall ISO kept at ${AUTOINSTALL_ISO_PATH}"
    fi
}

# --- 60. START INSTALLED VM AND DETECT IP ---
start_installed_vm_and_detect_ip() {
    section "START INSTALLED VM"

    if [ "$POST_INSTALL_START_VM" == "y" ]; then
        msg_info "Starting installed Ubuntu VM"
        run_cmd "starting installed Ubuntu VM" qm start "$TARGET_VMID"
        msg_ok "INSTALLED UBUNTU VM STARTED"

        ASSIGNED_IPV4="$(wait_for_vm_ipv4 "$TARGET_VMID" "$SSH_IP_DETECT_TIMEOUT_SECONDS" "$SSH_IP_CHECK_INTERVAL_SECONDS" || true)"

        if [ -n "$ASSIGNED_IPV4" ]; then
            SSH_COMMAND="ssh ${TARGET_USERNAME}@${ASSIGNED_IPV4}"
            msg_ok "VM IPV4 DETECTED (${ASSIGNED_IPV4})"
        else
            msg_warn "VM started but IPv4 was not reported by QEMU Guest Agent within ${SSH_IP_DETECT_TIMEOUT_SECONDS}s"
        fi
    else
        msg_warn "Installed Ubuntu VM was left powered off because user selected no"
    fi
}

# --- 61. WRITE COMPLETION MARKER ---
write_completion_marker() {
    cat > "$COMPLETED_MARKER" <<EOF
Ubuntu Auto Install completed on: $(date)
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
Install Powered Off: $INSTALL_POWERED_OFF
Installer Detached: yes
Boot Order: scsi0
Generated ISO Deleted: $DELETE_GENERATED_ISO_AFTER_INSTALL
Installed VM Started: $POST_INSTALL_START_VM
Assigned IPv4: ${ASSIGNED_IPV4:-not-detected}
SSH Command: ${SSH_COMMAND:-not-generated}
Verify Log: $VERIFY_LOG
Tools Installed By Script: ${INSTALLED_TOOL_PACKAGES[*]:-none}
Tools Cleanup Enabled: ${CLEANUP_INSTALLED_TOOLS}
Temporary Workspace Cleanup Enabled: ${CLEANUP_TEMP_WORKFILES}
EOF
}

# --- 62. HOST VERIFICATION REPORT ---
# Writes a host-side verification report after install cleanup and optional VM start.
create_host_verification_report() {
    section "HOST VERIFICATION"

    msg_info "Creating host verification report"

    cat > "$VERIFY_LOG" <<EOF
--- UBUNTU AUTOINSTALL HOST VERIFICATION REPORT ---
Date: $(date)
VMID: $TARGET_VMID
VM Name: $TARGET_VM_NAME
VM MAC: $TARGET_VM_MAC
Source ISO: $INSTALL_ISO_REF
Generated ISO: $AUTOINSTALL_ISO_REF
Install Powered Off: $INSTALL_POWERED_OFF
Post Install Start VM: $POST_INSTALL_START_VM
Assigned IPv4: ${ASSIGNED_IPV4:-not-detected}
SSH Command: ${SSH_COMMAND:-not-generated}

Results:
EOF

    {
        PASS() { echo "✓ PASS - $1"; }
        WARN() { echo "! WARN - $1"; }
        FAIL() { echo "✗ FAIL - $1"; }

        if qm config "$TARGET_VMID" >/dev/null 2>&1; then PASS "VM config exists"; else FAIL "VM config missing"; fi
        if qm config "$TARGET_VMID" 2>/dev/null | grep -q "^boot: order=scsi0"; then PASS "Boot order is installed disk first"; else WARN "Boot order is not confirmed as scsi0"; fi
        if ! qm config "$TARGET_VMID" 2>/dev/null | grep -q "^ide2:"; then PASS "Installer ISO is detached"; else FAIL "Installer ISO still attached on ide2"; fi

        if [ "$INSTALL_POWERED_OFF" == "yes" ]; then PASS "VM powered off after autoinstall"; else FAIL "VM did not power off after autoinstall"; fi

        if [ "$DELETE_GENERATED_ISO_AFTER_INSTALL" == "y" ]; then
            if [ ! -f "$AUTOINSTALL_ISO_PATH" ]; then PASS "Generated autoinstall ISO deleted"; else WARN "Generated autoinstall ISO still exists"; fi
        else
            if [ -f "$AUTOINSTALL_ISO_PATH" ]; then PASS "Generated autoinstall ISO kept as requested"; else WARN "Generated autoinstall ISO not found even though keep was selected"; fi
        fi

        if [ "$POST_INSTALL_START_VM" == "y" ]; then
            if [ "$(get_vm_status "$TARGET_VMID")" == "running" ]; then PASS "Installed VM is running"; else WARN "Installed VM is not running"; fi
            if [ -n "${ASSIGNED_IPV4:-}" ]; then PASS "IPv4 detected through QEMU Guest Agent: ${ASSIGNED_IPV4}"; else WARN "IPv4 was not detected through QEMU Guest Agent"; fi
            if [ -n "${SSH_COMMAND:-}" ]; then PASS "SSH command generated: ${SSH_COMMAND}"; else WARN "SSH command not generated"; fi
        else
            WARN "Installed VM start skipped by user"
        fi

        if [ -f "$COMPLETED_MARKER" ]; then PASS "Completion marker exists"; else WARN "Completion marker missing at verification time"; fi
    } >> "$VERIFY_LOG"

    msg_ok "HOST VERIFICATION REPORT CREATED"
}

# --- 63. GENERATED ISO ONLY SUMMARY ---
# Shows a clean summary when user generated the ISO but chose not to attach/start it.
show_generated_iso_only_summary() {
    section "GENERATED ISO READY"

    detail_line "VM: ${TARGET_VMID} / ${TARGET_VM_NAME}"
    detail_line "Generated ISO: ${AUTOINSTALL_ISO_REF}"
    detail_line "Host path: ${AUTOINSTALL_ISO_PATH}"
    echo ""
    echo -e "${YW}The ISO was generated and verified but was not attached or started.${CL}"
    echo -e "${YW}Run this script again when you are ready to attach it and start autoinstall.${CL}"
    echo ""
}

# --- 64. FINAL OUTPUT ---
show_final_output() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    echo -e "VM ID: ${GN}${TARGET_VMID}${CL}"
    echo -e "VM NAME: ${GN}${TARGET_VM_NAME}${CL}"
    echo -e "VM MAC: ${GN}${TARGET_VM_MAC}${CL}"
    echo -e "SOURCE ISO: ${GN}${INSTALL_ISO_REF}${CL}"
    echo -e "GENERATED ISO DELETED: ${GN}${DELETE_GENERATED_ISO_AFTER_INSTALL}${CL}"
    echo -e "BOOT ORDER: ${GN}scsi0${CL}"
    echo -e "INSTALLED VM STARTED: ${GN}${POST_INSTALL_START_VM}${CL}"
    echo -e "KEYBOARD: ${GN}${TARGET_KEYBOARD_LAYOUT}${CL}"
    echo -e "LOCALE: ${GN}${TARGET_LOCALE}${CL}"
    echo -e "VERIFY LOG: ${GN}${VERIFY_LOG}${CL}"

    if [ -n "$ASSIGNED_IPV4" ]; then
        echo -e "ASSIGNED IPV4: ${GN}${ASSIGNED_IPV4}${CL}"
    fi

    echo ""
    echo -e "${YW}Ubuntu autoinstall powered off successfully, installer media was detached.${CL}"

    if [ "$POST_INSTALL_START_VM" == "y" ]; then
        echo ""

        if [ -n "$SSH_COMMAND" ]; then
            echo -e "${YW}Wait for Ubuntu to finish first boot, then use SSH:${CL}"
            echo -e "${GN}${SSH_COMMAND}${CL}"
        else
            echo -e "${YW}Ubuntu VM was started, but an IPv4 address was not reported yet.${CL}"
            echo -e "${YW}Check the IP from the Proxmox host with:${CL}"
            echo -e "${GN}qm guest cmd ${TARGET_VMID} network-get-interfaces${CL}"
            echo -e "${YW}Then use SSH:${CL}"
            echo -e "${GN}ssh ${TARGET_USERNAME}@<assigned-ip>${CL}"
        fi

        echo -e "${YW}Then run script 4-ubuntuVMsetup inside the Ubuntu VM.${CL}"
    else
        echo -e "${YW}Start the VM manually when ready with:${CL} ${GN}qm start ${TARGET_VMID}${CL}"
    fi

    echo ""
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

main() {
    local start_yn=""
    local attach_yn=""

    init_script

    check_previous_marker
    show_start_warning
    start_yn="$(timed_yes_no "Start Ubuntu Auto Install ISO Creator?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    collect_early_cleanup_preferences

    select_vm
    detect_vm_mac
    collect_user_locale_inputs
    detect_ssh_keys
    collect_network_inputs
    collect_post_install_options
    select_ubuntu_iso
    show_ubuntu_pro_note

    precheck_generated_iso_reuse

    if [ "$REUSE_EXISTING_AUTOINSTALL_ISO" != "yes" ]; then
        ensure_tools
    fi

    generate_autoinstall_iso

    show_apply_summary
    attach_yn="$(timed_yes_no "Attach generated autoinstall ISO and start VM now?" "y")"

    if [[ "$attach_yn" =~ ^[Nn] ]]; then
        show_generated_iso_only_summary
        exit 0
    fi

    attach_iso_and_start_install
    post_install_cleanup
    start_installed_vm_and_detect_ip
    write_completion_marker
    create_host_verification_report
    show_final_output
}

main "$@"
