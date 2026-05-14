#!/usr/bin/env bash -ex
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  Proxmox VM Setup
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
# Stores timer, log file, defaults, detected hardware and user choices.
T=15
LOG_FILE="/var/log/proxmox-vm-setup.log"
COMPLETED_MARKER="/root/.proxmox-vm-setup-completed"

DEFAULT_VM_NAME="crea-ubuntu"
DEFAULT_VMID="100"
DEFAULT_DISK_GB="40"
DEFAULT_RAM_PERCENT="75"
DEFAULT_CPU_PERCENT="50"

TOTAL_RAM_GB="0"
TOTAL_CORES="0"
DEFAULT_RAM_GB="1"
DEFAULT_CORES="1"

GPU_ALL=""
IGPU_LINES=""
DGPU_LINES=""
IGPU_FOUND="no"
DGPU_FOUND="no"
DGPU_BDFS=""
GPU_SUMMARY=""
GPU_DETECTION_STATUS="ok"

STORAGE_ID=""
STORAGE_TYPE=""
EFI_FORMAT="raw"
EFI_FORMAT_MODE="auto"
ISO_PATH=""
ENABLE_GPU="n"

VMID=""
VM_NAME=""
CPU_INPUT=""
RAM_GB_INPUT=""
RAM_MB=""
DISK_GB_INPUT=""

ADVANCED_SETTINGS="n"
MACHINE_TYPE="q35"
BIOS_TYPE="ovmf"
CPU_TYPE_VM="host"
BALLOONING_ENABLED="no"
BALLOON_VALUE="0"
NETWORK_MODEL="virtio"
QEMU_AGENT_ENABLED="yes"
QEMU_AGENT_VALUE="enabled=1"
DISK_CONTROLLER="virtio-scsi-single"
DISCARD_ENABLED="yes"
DISCARD_VALUE="on"

# --- 3. HEADER FUNCTION ---
# Displays the one-line Proxmox VM Setup banner.
function header_info {
echo -e "${BL}
██████╗ ██████╗  ██████╗ ██╗  ██╗███╗   ███╗ ██████╗ ██╗  ██╗    ██╗   ██╗███╗   ███╗    ███████╗███████╗████████╗██╗   ██╗██████╗ 
██╔══██╗██╔══██╗██╔═══██╗╚██╗██╔╝████╗ ████║██╔═══██╗╚██╗██╔╝    ██║   ██║████╗ ████║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██████╔╝██████╔╝██║   ██║ ╚███╔╝ ██╔████╔██║██║   ██║ ╚███╔╝     ██║   ██║██╔████╔██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝
██╔═══╝ ██╔══██╗██║   ██║ ██╔██╗ ██║╚██╔╝██║██║   ██║ ██╔██╗     ╚██╗ ██╔╝██║╚██╔╝██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
██║     ██║  ██║╚██████╔╝██╔╝ ██╗██║ ╚═╝ ██║╚██████╔╝██╔╝ ██╗     ╚████╔╝ ██║ ╚═╝ ██║    ███████║███████╗   ██║   ╚██████╔╝██║     
╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝      ╚═══╝  ╚═╝     ╚═╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
${CL}"
}

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent status messages for display -> apply -> success flow.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. LOGGING & ERROR HANDLING ---
# Logs script output and reports the line number if a command fails.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 6. ROOT CHECK ---
# Proxmox VM creation requires root privileges.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

clear
header_info

# =========================================================
#  PHASE 1: SAFE AUDIT + USER INPUT COLLECTION ONLY
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
# Converts Y/N answers to visible yes/no text.
function yes_no_label() {
    local value="$1"
    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 10. BLOCKING YES/NO HELPER ---
# Used when SPACE is pressed. SPACE pauses the timer and waits for Y/N/ENTER.
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
# Uses wall-clock countdown instead of loop-count countdown.
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
# The initial key is passed into the same editable buffer, so Backspace/Delete can delete it.
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
# Backspace/Delete can delete every typed character, including the first.
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
# Shows wall-clock countdown.
# SPACE pauses with empty editable numeric buffer.
# Any typed digit pauses with that digit already inside the editable buffer.
# Backspace/Delete can delete the first digit.
# Timeout accepts default.
# Letters/symbols are rejected.
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
# Important: menu text goes to /dev/tty, not stdout, so command substitution captures only the final selected option.
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

# --- 18. PHYSICAL RAM DETECTION HELPER ---
# Uses MemTotal and rounds up to physical GiB.
# This fixes 16GB systems being detected as 15GB and defaulting to 11GB RAM.
function detect_total_ram_gb() {
    local mem_kb=""
    local gib_kb="1048576"

    mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)

    if ! [[ "$mem_kb" =~ ^[0-9]+$ ]]; then
        echo "1"
        return 0
    fi

    echo $(( (mem_kb + gib_kb - 1) / gib_kb ))
}

# --- 19. PCI VENDOR NAME HELPER ---
# Converts PCI vendor IDs to readable GPU vendor names without calling lspci.
function pci_vendor_name() {
    local vendor="$1"

    case "$vendor" in
        0x8086) echo "Intel" ;;
        0x10de) echo "NVIDIA" ;;
        0x1002) echo "AMD" ;;
        0x1022) echo "AMD" ;;
        *) echo "Unknown" ;;
    esac
}

# --- 20. SYSFS GPU DETECTION HELPER ---
# Detects GPUs through /sys/bus/pci/devices instead of lspci.
# This avoids lspci hangs on some fresh Proxmox/laptop PCI states.
function detect_gpus_sysfs() {
    local dev=""
    local bdf=""
    local class=""
    local vendor=""
    local device=""
    local vendor_name=""
    local line=""

    GPU_ALL=""
    IGPU_LINES=""
    DGPU_LINES=""
    IGPU_FOUND="no"
    DGPU_FOUND="no"
    DGPU_BDFS=""
    GPU_SUMMARY=""

    for dev in /sys/bus/pci/devices/*; do
        [ -e "$dev/class" ] || continue
        [ -e "$dev/vendor" ] || continue
        [ -e "$dev/device" ] || continue

        class="$(cat "$dev/class" 2>/dev/null || true)"

        case "$class" in
            0x030000|0x030200|0x038000)
                bdf="$(basename "$dev")"
                vendor="$(cat "$dev/vendor" 2>/dev/null || true)"
                device="$(cat "$dev/device" 2>/dev/null || true)"
                vendor_name="$(pci_vendor_name "$vendor")"
                line="${bdf} ${vendor_name} GPU [${vendor#0x}:${device#0x}]"

                GPU_ALL+="${line}"$'\n'

                if [ "$vendor" == "0x8086" ]; then
                    IGPU_LINES+="${line}"$'\n'
                    IGPU_FOUND="yes"
                elif [ "$vendor" == "0x10de" ] || [ "$vendor" == "0x1002" ] || [ "$vendor" == "0x1022" ]; then
                    DGPU_LINES+="${line}"$'\n'
                    DGPU_BDFS+="${bdf} "
                    DGPU_FOUND="yes"
                fi
                ;;
        esac
    done
}

# --- 21. GPU SUMMARY HELPER ---
# Creates readable integrated/discrete GPU summary for the audit screen.
function build_gpu_summary() {
    local out=""

    if [ -n "$IGPU_LINES" ]; then
        while read -r line; do
            [ -z "$line" ] && continue
            out+="Integrated: ${line}; "
        done <<< "$IGPU_LINES"
    fi

    if [ -n "$DGPU_LINES" ]; then
        while read -r line; do
            [ -z "$line" ] && continue
            out+="Discrete: ${line}; "
        done <<< "$DGPU_LINES"
    fi

    echo "${out%; }"
}

# --- 22. STORAGE LIST HELPER ---
# Finds Proxmox storage suitable for VM images.
# First tries content-aware pvesm status. If unsupported, safely falls back to all active storage.
function get_storage_list() {
    local list=""

    list=$(pvesm status --content images 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}' | sort || true)

    if [ -z "$list" ]; then
        list=$(pvesm status 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}' | sort || true)
    fi

    echo "$list"
}

# --- 23. STORAGE TYPE HELPER ---
# Detects selected Proxmox storage type from pvesm status.
function get_storage_type() {
    local storage="$1"

    pvesm status 2>/dev/null | awk -v s="$storage" 'NR>1 && $1==s {print $2; exit}'
}

# --- 24. EFI FORMAT HELPER ---
# Chooses correct EFI disk format for selected storage type.
# File-based storage supports qcow2; block/pool storage should use raw.
function get_efi_format_for_storage_type() {
    local type="$1"

    case "$type" in
        dir|nfs|cifs|glusterfs)
            echo "qcow2"
            ;;
        *)
            echo "raw"
            ;;
    esac
}

# --- 25. YES/NO VALUE HELPER ---
# Converts yes/no values into Proxmox qm values.
function apply_boolean_values() {
    if [ "$BALLOONING_ENABLED" == "yes" ]; then
        BALLOON_VALUE="$(( RAM_MB / 2 ))"
        [ "$BALLOON_VALUE" -lt 512 ] && BALLOON_VALUE="512"
    else
        BALLOON_VALUE="0"
    fi

    if [ "$QEMU_AGENT_ENABLED" == "yes" ]; then
        QEMU_AGENT_VALUE="enabled=1"
    else
        QEMU_AGENT_VALUE="enabled=0"
    fi

    if [ "$DISCARD_ENABLED" == "yes" ]; then
        DISCARD_VALUE="on"
    else
        DISCARD_VALUE="ignore"
    fi
}

# --- 26. PROXMOX COMMAND RUNNER ---
# Runs qm commands while hiding normal successful output.
# If a Proxmox command fails, it prints the real stderr so the problem can be fixed.
function run_proxmox_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"

    if ! "$@" > /dev/null 2> "$err_file"; then
        echo ""
        echo -e "${RD}Proxmox command failed during: ${description}${CL}"
        echo -e "${YW}Command:${CL} $*"
        echo ""
        echo -e "${RD}Real Proxmox error:${CL}"
        cat "$err_file"
        rm -f "$err_file"

        echo ""
        echo -e "${YW}Troubleshooting:${CL}"
        echo "qm list"
        echo "qm config ${VMID} 2>/dev/null || true"
        echo "ls -l /etc/pve/qemu-server/${VMID}.conf 2>/dev/null || true"
        exit 1
    fi

    rm -f "$err_file"
}

# --- 27. PROXMOX VALIDATION ---
# Confirms the script is being run on Proxmox VE 9 or newer.
if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This system is not Proxmox VE. Script cancelled."
fi

PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)

if ! [[ "$PVE_MAJOR" =~ ^[0-9]+$ ]] || [ "$PVE_MAJOR" -lt 9 ]; then
    msg_error "Requires Proxmox VE 9+."
fi

# --- 28. SYSTEM RESOURCE AUDIT ---
# Detects RAM, CPU cores and calculates adaptive default VM resources.
msg_info "Auditing system resources"

TOTAL_RAM_GB=$(detect_total_ram_gb)
TOTAL_CORES=$(nproc)

DEFAULT_RAM_GB=$(( TOTAL_RAM_GB * DEFAULT_RAM_PERCENT / 100 ))
[ "$DEFAULT_RAM_GB" -lt 1 ] && DEFAULT_RAM_GB=1

DEFAULT_CORES=$(( TOTAL_CORES * DEFAULT_CPU_PERCENT / 100 ))
[ "$DEFAULT_CORES" -lt 1 ] && DEFAULT_CORES=1

msg_ok "SYSTEM RESOURCES DETECTED"

# --- 29. SAFE SYSFS GPU AUDIT ---
# Detects GPU through sysfs only, avoiding lspci because lspci can hang on some fresh Proxmox/laptop systems.
msg_info "Detecting GPU hardware"

detect_gpus_sysfs
GPU_SUMMARY=$(build_gpu_summary)

if [ -n "$GPU_ALL" ]; then
    msg_ok "GPU DETECTION COMPLETE"
else
    GPU_DETECTION_STATUS="skipped"
    msg_ok "GPU DETECTION SKIPPED"
fi

# --- 30. SYSTEM AUDIT DISPLAY ---
# Shows available host resources and adaptive defaults before asking user inputs.
echo ""
echo -e "${DGN}SYSTEM AUDIT:${CL}"
echo -e "TOTAL RAM: ${GN}${TOTAL_RAM_GB}GB${CL}"
echo -e "CPU CORES: ${GN}${TOTAL_CORES}${CL}"
echo -e "DEFAULT VM RAM: ${GN}${DEFAULT_RAM_GB}GB${CL}"
echo -e "DEFAULT VM CPU CORES: ${GN}${DEFAULT_CORES}${CL}"

if [ -n "$GPU_SUMMARY" ]; then
    echo -e "GPU: ${GN}${GPU_SUMMARY}${CL}"
else
    echo -e "GPU: ${YW}No passthrough target detected or GPU detection skipped${CL}"
fi

echo "------------------------------------------------------"

# --- 31. FINAL START CONFIRMATION ---
# Starts input collection after audit. No VM changes happen yet.
start_yn=$(timed_yes_no "Start the Proxmox VM Setup Script?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 32. USER VM CONFIGURATION INPUTS ---
# Collects VM ID, name, CPU, RAM and OS disk size using adaptive defaults.
# This stage still does not create or modify any VM.
VMID=$(timed_number_input "Enter VM ID" "$DEFAULT_VMID" "1")
VM_NAME=$(timed_text_input "Enter VM Name" "$DEFAULT_VM_NAME")
CPU_INPUT=$(timed_number_input "Enter CPU CORES" "$DEFAULT_CORES" "1" "$TOTAL_CORES")
RAM_GB_INPUT=$(timed_number_input "Enter RAM in GB" "$DEFAULT_RAM_GB" "1" "$TOTAL_RAM_GB")
DISK_GB_INPUT=$(timed_number_input "Enter OS DISK SIZE in GB" "$DEFAULT_DISK_GB" "8")

RAM_MB=$(( RAM_GB_INPUT * 1024 ))

# --- 33. ISO SELECTION ---
# Lists ISO files from local storage and lets the user choose one with numeric validation.
# Still input-only; no VM changes are made here.
msg_info "Finding ISO images"

mapfile -t ISOS < <(find /var/lib/vz/template/iso -maxdepth 1 -type f -iname "*.iso" 2>/dev/null | sort || true)

if [ "${#ISOS[@]}" -eq 0 ]; then
    msg_warn "No ISO images found in /var/lib/vz/template/iso. VM will be created without ISO."
    ISO_PATH=""
else
    msg_ok "ISO IMAGES FOUND"
    echo ""
    echo -e "${BL}SELECT ISO:${CL}"

    for i in "${!ISOS[@]}"; do
        echo "$((i+1))) $(basename "${ISOS[$i]}")"
    done

    ISO_IDX=$(timed_number_input "Select ISO number" "1" "1" "${#ISOS[@]}")
    ISO_PATH="local:iso/$(basename "${ISOS[$((ISO_IDX-1))]}")"
fi

# --- 34. STORAGE SELECTION ---
# Lists Proxmox storage that supports images and lets the user choose where to place VM disks.
# Still input-only; no VM changes are made here.
msg_info "Finding Proxmox storage"

mapfile -t STORAGE_LIST < <(get_storage_list)

if [ "${#STORAGE_LIST[@]}" -eq 0 ]; then
    msg_error "No active Proxmox storage found for VM images."
fi

msg_ok "STORAGE FOUND"
echo ""
echo -e "${BL}SELECT VM STORAGE:${CL}"

for i in "${!STORAGE_LIST[@]}"; do
    storage_name="${STORAGE_LIST[$i]}"
    storage_type="$(get_storage_type "$storage_name")"
    echo "$((i+1))) ${storage_name} (${storage_type:-unknown})"
done

STORAGE_IDX=$(timed_number_input "Select storage number" "1" "1" "${#STORAGE_LIST[@]}")
STORAGE_ID="${STORAGE_LIST[$((STORAGE_IDX-1))]}"
STORAGE_TYPE="$(get_storage_type "$STORAGE_ID")"
EFI_FORMAT="$(get_efi_format_for_storage_type "$STORAGE_TYPE")"

# --- 35. GPU PASSTHROUGH OPTION ---
# Offers discrete GPU passthrough only if sysfs GPU detection found a discrete GPU.
# Default is no for first Crea Social test because Docker/Postgres/Postiz do not require GPU initially.
if [ "$DGPU_FOUND" == "yes" ] && [ -n "$DGPU_BDFS" ]; then
    gpu_yn=$(timed_yes_no "Add DISCRETE GPU to VM?" "y")
    [[ "$gpu_yn" =~ ^[Yy] ]] && ENABLE_GPU="y"
else
    ENABLE_GPU="n"
fi

# --- 36. ADVANCED SETTINGS PROMPT ---
# Keeps Crea Social recommended defaults unless user chooses to edit advanced VM options.
advanced_yn=$(timed_yes_no "Open Advanced VM Settings?" "n")

if [[ "$advanced_yn" =~ ^[Yy] ]]; then
    ADVANCED_SETTINGS="y"

    MACHINE_TYPE=$(timed_menu_select "Machine Type" "1" "q35" "i440fx")
    BIOS_TYPE=$(timed_menu_select "BIOS Type" "1" "ovmf" "seabios")
    CPU_TYPE_VM=$(timed_menu_select "CPU Type" "1" "host" "x86-64-v2-AES" "x86-64-v3" "kvm64" "max")

    balloon_yn=$(timed_yes_no "Enable RAM Ballooning?" "n")
    [[ "$balloon_yn" =~ ^[Yy] ]] && BALLOONING_ENABLED="yes" || BALLOONING_ENABLED="no"

    NETWORK_MODEL=$(timed_menu_select "Network Model" "1" "virtio" "e1000" "e1000e" "vmxnet3")

    agent_yn=$(timed_yes_no "Enable QEMU Guest Agent?" "y")
    [[ "$agent_yn" =~ ^[Nn] ]] && QEMU_AGENT_ENABLED="no" || QEMU_AGENT_ENABLED="yes"

    DISK_CONTROLLER=$(timed_menu_select "Disk Controller" "1" "virtio-scsi-single" "virtio-scsi-pci")

    discard_yn=$(timed_yes_no "Enable Discard/TRIM?" "y")
    [[ "$discard_yn" =~ ^[Nn] ]] && DISCARD_ENABLED="no" || DISCARD_ENABLED="yes"

    EFI_FORMAT_MODE=$(timed_menu_select "EFI Format Mode" "1" "auto" "raw" "qcow2")

    if [ "$EFI_FORMAT_MODE" == "raw" ] || [ "$EFI_FORMAT_MODE" == "qcow2" ]; then
        EFI_FORMAT="$EFI_FORMAT_MODE"
    fi
fi

apply_boolean_values

# --- 37. FINAL APPLY CONFIRMATION ---
# Last checkpoint before any Proxmox VM changes are made.
# Shows every setting, including safe defaults and advanced options, whether advanced mode was used or not.
echo ""
echo -e "${BL}READY TO CREATE VM WITH THESE SETTINGS:${CL}"
echo -e "VM ID: ${GN}${VMID}${CL}"
echo -e "VM NAME: ${GN}${VM_NAME}${CL}"
echo -e "CPU CORES: ${GN}${CPU_INPUT}${CL}"
echo -e "RAM: ${GN}${RAM_GB_INPUT}GB${CL}"
echo -e "OS DISK: ${GN}${DISK_GB_INPUT}GB${CL}"
echo -e "STORAGE: ${GN}${STORAGE_ID}${CL}"
echo -e "STORAGE TYPE: ${GN}${STORAGE_TYPE:-unknown}${CL}"
echo -e "ISO: ${GN}${ISO_PATH:-none}${CL}"
echo -e "GPU PASSTHROUGH: ${GN}${ENABLE_GPU}${CL}"
echo ""
echo -e "${BL}VM PLATFORM SETTINGS:${CL}"
echo -e "MACHINE TYPE: ${GN}${MACHINE_TYPE}${CL}"
echo -e "BIOS: ${GN}${BIOS_TYPE}${CL}"
echo -e "EFI FORMAT MODE: ${GN}${EFI_FORMAT_MODE}${CL}"
echo -e "EFI FORMAT: ${GN}${EFI_FORMAT}${CL}"
echo -e "CPU TYPE: ${GN}${CPU_TYPE_VM}${CL}"
echo -e "BALLOONING ENABLED: ${GN}${BALLOONING_ENABLED}${CL}"
echo -e "BALLOON VALUE: ${GN}${BALLOON_VALUE}${CL}"
echo -e "NETWORK MODEL: ${GN}${NETWORK_MODEL}${CL}"
echo -e "QEMU GUEST AGENT: ${GN}${QEMU_AGENT_ENABLED}${CL}"
echo -e "DISK CONTROLLER: ${GN}${DISK_CONTROLLER}${CL}"
echo -e "DISCARD/TRIM: ${GN}${DISCARD_ENABLED}${CL}"
echo -e "ADVANCED SETTINGS USED: ${GN}${ADVANCED_SETTINGS}${CL}"
echo ""

apply_yn=$(timed_yes_no "Create VM now?" "y")
[[ "$apply_yn" =~ ^[Nn] ]] && exit 0

# =========================================================
#  PHASE 2: APPLY / CREATE VM ONLY AFTER ALL INPUTS
# =========================================================

# --- 38. VM ID CONFLICT CHECK ---
# Checks conflict only after all input is collected, immediately before creation.
# Uses qm config because it catches partial/incomplete VM configs better than qm status.
if qm config "$VMID" >/dev/null 2>&1; then
    msg_error "VM ID ${VMID} already exists. Remove it first or choose another VM ID."
fi

# --- 39. VM CREATE ---
# Creates Ubuntu/Linux VM using selected standard and advanced settings.
# Proxmox errors are captured and displayed if qm create fails.
msg_info "Creating VM ${VMID} (${VM_NAME})"

run_proxmox_cmd "creating VM ${VMID}" \
    qm create "$VMID" \
    --name "$VM_NAME" \
    --machine "$MACHINE_TYPE" \
    --bios "$BIOS_TYPE" \
    --ostype l26 \
    --cpu "$CPU_TYPE_VM" \
    --cores "$CPU_INPUT" \
    --memory "$RAM_MB" \
    --balloon "$BALLOON_VALUE" \
    --net0 "${NETWORK_MODEL},bridge=vmbr0" \
    --agent "$QEMU_AGENT_VALUE"

msg_ok "VM CREATED"

# --- 40. EFI DISK CONFIGURATION ---
# Adds OVMF EFI disk only when OVMF BIOS is selected.
# SeaBIOS does not use an EFI disk.
if [ "$BIOS_TYPE" == "ovmf" ]; then
    msg_info "Configuring EFI disk"

    run_proxmox_cmd "configuring EFI disk" \
        qm set "$VMID" \
        --efidisk0 "${STORAGE_ID}:0,format=${EFI_FORMAT},efitype=4m,pre-enrolled-keys=0"

    msg_ok "EFI DISK CONFIGURED"
fi

# --- 41. MAIN VM DISK CONFIGURATION ---
# Adds main OS disk with selected disk controller, discard setting and iothread.
msg_info "Configuring VM OS disk"

run_proxmox_cmd "setting disk controller" \
    qm set "$VMID" \
    --scsihw "$DISK_CONTROLLER"

run_proxmox_cmd "creating VM OS disk" \
    qm set "$VMID" \
    --scsi0 "${STORAGE_ID}:${DISK_GB_INPUT},discard=${DISCARD_VALUE},iothread=1"

msg_ok "VM OS DISK CONFIGURED"

# --- 42. ISO AND BOOT ORDER ---
# Attaches selected ISO if available and sets VM boot order.
msg_info "Configuring VM boot"

if [ -n "$ISO_PATH" ]; then
    run_proxmox_cmd "attaching ISO" \
        qm set "$VMID" \
        --cdrom "$ISO_PATH"
fi

run_proxmox_cmd "setting VM boot order" \
    qm set "$VMID" \
    --boot "order=scsi0;ide2"

msg_ok "VM BOOT CONFIGURED"

# --- 43. GPU PASSTHROUGH ATTACHMENT ---
# Adds the first detected discrete GPU BDF to the VM after all other settings are applied.
if [ "$ENABLE_GPU" == "y" ]; then
    msg_info "Attaching discrete GPU to VM"

    GPU_PCI_ID=$(echo "$DGPU_BDFS" | awk '{print $1}')

    if [ -n "$GPU_PCI_ID" ]; then
        run_proxmox_cmd "attaching discrete GPU ${GPU_PCI_ID}" \
            qm set "$VMID" \
            --hostpci0 "${GPU_PCI_ID},pcie=1,x-vga=1"

        msg_ok "GPU PASSTHROUGH ENABLED (${GPU_PCI_ID})"
    else
        msg_warn "GPU passthrough selected but no GPU PCI ID found."
    fi
fi

# --- 44. COMPLETION MARKER ---
# Creates marker file so future checks can identify that this setup was already run.
cat <<EOF > "$COMPLETED_MARKER"
Proxmox VM Setup completed on: $(date)
VMID: $VMID
Name: $VM_NAME
RAM: ${RAM_GB_INPUT}GB
CPU Cores: ${CPU_INPUT}
OS Disk: ${DISK_GB_INPUT}GB
Storage: ${STORAGE_ID}
Storage Type: ${STORAGE_TYPE}
ISO: ${ISO_PATH:-none}
GPU Passthrough: ${ENABLE_GPU}
Machine Type: ${MACHINE_TYPE}
BIOS: ${BIOS_TYPE}
EFI Format Mode: ${EFI_FORMAT_MODE}
EFI Format: ${EFI_FORMAT}
CPU Type: ${CPU_TYPE_VM}
Ballooning Enabled: ${BALLOONING_ENABLED}
Balloon Value: ${BALLOON_VALUE}
Network Model: ${NETWORK_MODEL}
QEMU Guest Agent: ${QEMU_AGENT_ENABLED}
Disk Controller: ${DISK_CONTROLLER}
Discard/TRIM: ${DISCARD_ENABLED}
Advanced Settings Used: ${ADVANCED_SETTINGS}
EOF

# --- 45. FINAL SUMMARY ---
# Shows final VM configuration.
echo ""
echo -e "${GN}FINISHED!${CL}"
echo -e "VM ID: ${GN}${VMID}${CL}"
echo -e "VM NAME: ${GN}${VM_NAME}${CL}"
echo -e "RAM: ${GN}${RAM_GB_INPUT}GB${CL}"
echo -e "CPU CORES: ${GN}${CPU_INPUT}${CL}"
echo -e "OS DISK: ${GN}${DISK_GB_INPUT}GB${CL}"
echo -e "STORAGE: ${GN}${STORAGE_ID}${CL}"
echo -e "STORAGE TYPE: ${GN}${STORAGE_TYPE:-unknown}${CL}"
echo -e "ISO: ${GN}${ISO_PATH:-none}${CL}"
echo -e "GPU PASSTHROUGH: ${GN}${ENABLE_GPU}${CL}"
echo -e "MACHINE TYPE: ${GN}${MACHINE_TYPE}${CL}"
echo -e "BIOS: ${GN}${BIOS_TYPE}${CL}"
echo -e "EFI FORMAT: ${GN}${EFI_FORMAT}${CL}"
echo -e "CPU TYPE: ${GN}${CPU_TYPE_VM}${CL}"
echo -e "BALLOONING: ${GN}${BALLOONING_ENABLED}${CL}"
echo -e "NETWORK MODEL: ${GN}${NETWORK_MODEL}${CL}"
echo -e "QEMU GUEST AGENT: ${GN}${QEMU_AGENT_ENABLED}${CL}"
echo -e "DISK CONTROLLER: ${GN}${DISK_CONTROLLER}${CL}"
echo -e "DISCARD/TRIM: ${GN}${DISCARD_ENABLED}${CL}"
echo ""

exit 0