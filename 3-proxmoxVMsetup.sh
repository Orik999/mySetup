#!/usr/bin/env bash
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  Proxmox VM Setup
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Keeps all colour variables available for future visual changes.
YW="$(printf '\033[33m')"
BL="$(printf '\033[36m')"
RD="$(printf '\033[01;31m')"
BGN="$(printf '\033[4;92m')"
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

SCRIPT_SOURCE="3-proxmoxVMsetup.sh"
SCRIPT_VERSION="v1.2.0"
SCRIPT_UPDATED="2026-05-22"
SCRIPT_BUILD="audit-untimed-inputs-snapshot-aware-storage"

# --- 2. GLOBAL VARIABLES ---
# Stores timer, log file, defaults, detected hardware and user choices.
T=15
LOG_FILE="/var/log/proxmox-vm-setup.log"
VERIFY_LOG="/var/log/proxmox-vm-setup-verify.log"
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

SYSTEM_TYPE="Unknown"
CHASSIS="Unknown"
IS_VM="no"

GPU_ALL=""
IGPU_LINES=""
DGPU_LINES=""
IGPU_FOUND="no"
DGPU_FOUND="no"
DGPU_BDFS=""
DGPU_VENDOR_IDS=""
GPU_SUMMARY=""
GPU_DETECTION_STATUS="ok"

STORAGE_ID=""
STORAGE_TYPE=""
EFI_FORMAT="raw"
EFI_FORMAT_MODE="auto"
ISO_PATH=""
ENABLE_GPU="n"
GPU_SAME_SLOT_BDFS=""
GPU_FUNCTIONS_ATTACHED=""
BOOT_ORDER=""
VM_CREATED="no"

VMID=""
VM_NAME=""
CPU_INPUT=""
RAM_GB_INPUT=""
RAM_MB=""
DISK_GB_INPUT=""
VM_MAC_ADDRESS=""
SUGGESTED_MAC_ADDRESS=""
CUSTOM_MAC_SELECTED="no"

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

TEMP_FILES=()

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

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
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- SCRIPT VERSION DISPLAY ---
# Prints the currently running script version immediately under the ASCII banner.
function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

# --- 5. SECTION HEADER HELPER ---
# Keeps output readable and avoids repeated overwritten status messages.
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

# --- 5A. FLASHING SUCCESS SECTION HEADER HELPER ---
# Uses the same section layout as script 1, but renders final success headings in bold flashing green.
function section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

# --- DETAIL LINE HELPER ---
# Prints clean script 1-style detail lines for summaries and audit output.
function detail_line() {
    local label="$1"
    local value="$2"
    echo -e " ${BL}━━━━━▶${CL} ${label}: ${GN}${value}${CL}"
}

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

# =========================================================
#  CLEANUP / ERROR HANDLING
# =========================================================

# --- 8. CLEANUP FUNCTION ---
# Removes temporary files created by command runners.
function cleanup() {
    local exit_code="$?"

    for file in "${TEMP_FILES[@]:-}"; do
        [ -n "$file" ] && [ -f "$file" ] && rm -f "$file" 2>/dev/null || true
    done

    exit "$exit_code"
}

# --- 9. ERROR TRAP HELPER ---
# Shows the failing line number and points to the log file.
function on_error() {
    local line_no="$1"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"

    if [ "$VM_CREATED" == "yes" ] && [ -n "$VMID" ]; then
        print_partial_vm_recovery_hint
    fi
}

# --- 9A. PARTIAL VM RECOVERY HINT ---
# Prints safe inspection/removal commands if a failure occurs after qm create succeeds.
# It does not auto-destroy the VM because automatic rollback can be dangerous after disks are created.
function print_partial_vm_recovery_hint() {
    echo ""
    echo -e "${YW}A partial VM may have been created.${CL}"
    echo -e "${YW}Inspect before rerunning:${CL}"
    echo "  qm config ${VMID} 2>/dev/null || true"
    echo "  qm status ${VMID} 2>/dev/null || true"
    echo "  ls -l /etc/pve/qemu-server/${VMID}.conf 2>/dev/null || true"
    echo ""
    echo -e "${YW}If this was only a failed test VM and you want to remove it manually:${CL}"
    echo "  qm stop ${VMID} 2>/dev/null || true"
    echo "  qm destroy ${VMID} --purge"
    echo ""
}

# --- 10. PROXMOX COMMAND RUNNER ---
# Runs qm commands while hiding normal successful output.
# If a Proxmox command fails, it prints the real stderr so the problem can be fixed.
function run_proxmox_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

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

        if [ "$VM_CREATED" == "yes" ] && [ -n "$VMID" ]; then
            print_partial_vm_recovery_hint
        fi

        exit 1
    fi

    rm -f "$err_file"
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 11. YES/NO LABEL HELPER ---
# Converts Y/N answers to visible yes/no text.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 12. BLOCKING YES/NO HELPER ---
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

# --- 13. TIMED YES/NO PROMPT HELPER ---
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

# --- 14. NUMERIC VALIDATION HELPER ---
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

# --- 15. NUMERIC ERROR HELPER ---
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

# --- 16. EDITABLE INPUT LOOP HELPER ---
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

# --- 17. TIMED TEXT INPUT HELPER ---
# Shows wall-clock countdown.
# SPACE pauses with empty editable buffer.
# Any typed character pauses with that character already inside the editable buffer.
# Backspace/Delete can delete every typed character, including the first.
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

# --- 18. TIMED NUMERIC INPUT HELPER ---
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

# --- 19. MENU SELECTION HELPER ---
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

    idx="$(timed_number_input "Select ${title} option number" "$default_index" "1" "${#options[@]}")"
    selected="${options[$((idx-1))]}"

    echo "$selected"
}

# =========================================================
#  VALIDATION / GENERAL HELPERS
# =========================================================

# --- 20. DEPENDENCY VALIDATION ---
# Ensures required commands exist before user flow starts.
function validate_dependencies() {
    local required_commands=(
        awk
        basename
        cat
        chmod
        cut
        date
        env
        find
        grep
        head
        hostname
        mktemp
        nproc
        openssl
        pvesm
        qm
        sed
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

# --- 21. PROXMOX VALIDATION ---
# Confirms the script is being run on Proxmox VE 9 or newer.
function validate_proxmox() {
    local pve_major=""

    if ! command -v pveversion >/dev/null 2>&1; then
        msg_error "This system is not Proxmox VE. Script cancelled."
    fi

    pve_major="$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)"

    if ! [[ "$pve_major" =~ ^[0-9]+$ ]] || [ "$pve_major" -lt 9 ]; then
        msg_error "Requires Proxmox VE 9+."
    fi
}

# --- 22. PREVIOUS RUN MARKER CHECK ---
# Warns if a previous VM setup marker exists.
function check_previous_marker() {
    local continue_yn=""

    if [ -f "$COMPLETED_MARKER" ]; then
        section "PREVIOUS VM SETUP MARKER DETECTED"

        echo -e "${YW}A previous Proxmox VM Setup marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        cat "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi
}

# --- 23. VM NAME VALIDATION HELPER ---
# Validates Proxmox-friendly and hostname-friendly VM names.
function validate_vm_name() {
    local value="$1"

    if [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]; then
        return 0
    fi

    return 1
}

# --- 24. PHYSICAL RAM DETECTION HELPER ---
# Uses MemTotal and rounds up to physical GiB.
# This fixes 16GB systems being detected as 15GB and defaulting to 11GB RAM.
function detect_total_ram_gb() {
    local mem_kb=""
    local gib_kb="1048576"

    mem_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"

    if ! [[ "$mem_kb" =~ ^[0-9]+$ ]]; then
        echo "1"
        return 0
    fi

    echo $(( (mem_kb + gib_kb - 1) / gib_kb ))
}

# --- 25. SYSTEM TYPE AUDIT HELPER ---
# Detects laptop / VM / workstation for safer GPU classification.
function detect_system_type() {
    SYSTEM_TYPE="PC/Workstation"
    IS_VM="no"
    CHASSIS="Unknown"

    if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet; then
        IS_VM="yes"
        SYSTEM_TYPE="Virtual Machine"
        return 0
    fi

    if command -v dmidecode >/dev/null 2>&1; then
        CHASSIS="$(dmidecode -s chassis-type 2>/dev/null || echo "Unknown")"
    fi

    if [[ "$CHASSIS" =~ (Laptop|Notebook|Portable) ]]; then
        SYSTEM_TYPE="Laptop"
    fi
}

# --- 26. PCI VENDOR NAME HELPER ---
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

# --- 27. GPU TYPE CLASSIFIER ---
# Classifies GPUs using sysfs vendor/class/boot_vga instead of fragile lspci text matching.
# This avoids treating AMD APUs as safe dGPU passthrough targets on laptop-style systems.
function classify_gpu_type() {
    local vendor="$1"
    local class="$2"
    local boot_vga="$3"
    local gpu_count="$4"

    if [ "$vendor" == "0x10de" ]; then
        echo "discrete"
        return 0
    fi

    if [ "$vendor" == "0x8086" ]; then
        if [ "$gpu_count" -gt 1 ] && [ "$boot_vga" != "1" ] && [ "$class" != "0x030000" ]; then
            echo "discrete"
        else
            echo "integrated"
        fi
        return 0
    fi

    if [ "$vendor" == "0x1002" ] || [ "$vendor" == "0x1022" ]; then
        if [ "$gpu_count" -gt 1 ] && [ "$SYSTEM_TYPE" == "Laptop" ] && [ "$boot_vga" == "1" ]; then
            echo "integrated"
        else
            echo "discrete"
        fi
        return 0
    fi

    if [ "$boot_vga" == "1" ]; then
        echo "integrated"
    else
        echo "unknown"
    fi
}

# --- 28. SYSFS GPU DETECTION HELPER ---
# Detects GPUs through /sys/bus/pci/devices instead of lspci.
# This avoids lspci hangs on some fresh Proxmox/laptop PCI states.
function detect_gpus_sysfs() {
    local dev=""
    local bdf=""
    local class=""
    local vendor=""
    local device=""
    local boot_vga=""
    local vendor_name=""
    local gpu_type=""
    local line=""
    local gpu_records=""
    local gpu_count="0"

    GPU_ALL=""
    IGPU_LINES=""
    DGPU_LINES=""
    IGPU_FOUND="no"
    DGPU_FOUND="no"
    DGPU_BDFS=""
    DGPU_VENDOR_IDS=""
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
                boot_vga="0"

                if [ -r "$dev/boot_vga" ]; then
                    boot_vga="$(cat "$dev/boot_vga" 2>/dev/null || echo 0)"
                fi

                gpu_records+="${bdf}|${vendor}|${device}|${class}|${boot_vga}"$'\n'
                gpu_count=$((gpu_count + 1))
                ;;
        esac
    done

    while IFS='|' read -r bdf vendor device class boot_vga; do
        [ -z "$bdf" ] && continue

        vendor_name="$(pci_vendor_name "$vendor")"
        gpu_type="$(classify_gpu_type "$vendor" "$class" "$boot_vga" "$gpu_count")"
        line="${bdf} ${vendor_name} GPU [${vendor#0x}:${device#0x}] boot_vga=${boot_vga}"

        GPU_ALL+="${line}"$'\n'

        if [ "$gpu_type" == "integrated" ]; then
            IGPU_LINES+="${line}"$'\n'
            IGPU_FOUND="yes"
        elif [ "$gpu_type" == "discrete" ]; then
            DGPU_LINES+="${line}"$'\n'
            DGPU_BDFS+="${bdf} "
            DGPU_VENDOR_IDS+="${vendor} "
            DGPU_FOUND="yes"
        fi
    done <<< "$gpu_records"
}

# --- 29. GPU SUMMARY HELPER ---
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

# --- 30. SAME-SLOT GPU FUNCTION HELPER ---
# Returns every PCI function in the same slot as the selected GPU.
# Example: 0000:01:00.0 -> 0000:01:00.0 0000:01:00.1 ...
function get_same_slot_functions_for_bdf() {
    local bdf="$1"
    local slot=""
    local func=""
    local out=""

    slot="${bdf%.*}"

    for func in /sys/bus/pci/devices/${slot}.*; do
        [ -e "$func" ] || continue
        out+="$(basename "$func") "
    done

    echo "$out" | xargs
}

# --- 31. STORAGE CONTENT HELPER ---
# Reads the content line for a storage ID from /etc/pve/storage.cfg.
function get_storage_content() {
    local storage="$1"

    awk -v s="$storage" '
        $0 ~ "^[a-zA-Z0-9_-]+: "s"$" {inblock=1; next}
        inblock && /^[a-zA-Z0-9_-]+: / {exit}
        inblock && $1=="content" {
            for (i=2; i<=NF; i++) printf "%s", $i
            exit
        }
    ' /etc/pve/storage.cfg 2>/dev/null || true
}

# --- 32. STORAGE LIST HELPER ---
# Finds Proxmox storage suitable for VM images.
# First tries content-aware pvesm status. If unsupported, falls back to filtered active storage.
function get_storage_list() {
    local list=""
    local storage=""
    local storage_type=""
    local content=""

    list="$(pvesm status --content images 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}' | sort || true)"

    if [ -n "$list" ]; then
        echo "$list"
        return 0
    fi

    while read -r storage storage_type status rest; do
        [ -z "$storage" ] && continue
        [ "$status" != "active" ] && continue

        case "$storage_type" in
            dir|nfs|cifs|glusterfs|lvm|lvmthin|zfspool|btrfs)
                content="$(get_storage_content "$storage")"

                if [ -z "$content" ] || [[ ",${content}," == *",images,"* ]] || [[ "$content" == *"images"* ]]; then
                    echo "$storage"
                fi
                ;;
        esac
    done < <(pvesm status 2>/dev/null | awk 'NR>1 {print $1, $2, $3}')
}

# --- 33. STORAGE TYPE HELPER ---
# Detects selected Proxmox storage type from pvesm status.
function get_storage_type() {
    local storage="$1"

    pvesm status 2>/dev/null | awk -v s="$storage" 'NR>1 && $1==s {print $2; exit}'
}

# --- 34. EFI FORMAT HELPER ---
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

# --- 35. MAC ADDRESS VALIDATION HELPER ---
# Validates standard colon-separated MAC addresses.
function validate_mac_address() {
    local mac="$1"

    if [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        return 0
    fi

    return 1
}

# --- 36. MAC ADDRESS NORMALISATION HELPER ---
# Converts a valid MAC address to uppercase for consistent display and storage.
function normalize_mac_address() {
    local mac="$1"
    echo "$mac" | tr '[:lower:]' '[:upper:]'
}

# --- 37. MAC ADDRESS IN-USE CHECK HELPER ---
# Checks existing Proxmox VM config files for a MAC address to avoid duplicate network identities.
function mac_address_in_use() {
    local mac="$1"
    local normalized_mac=""

    normalized_mac="$(normalize_mac_address "$mac")"

    if grep -Riq "$normalized_mac" /etc/pve/qemu-server/*.conf 2>/dev/null; then
        return 0
    fi

    return 1
}

# --- 38. PROXMOX MAC GENERATOR HELPER ---
# Generates a Proxmox-style locally usable MAC address using the common BC:24:11 prefix.
# It retries if a generated MAC is already present in existing VM configs.
function generate_proxmox_mac() {
    local mac=""
    local suffix=""
    local attempt=""

    for attempt in {1..25}; do
        suffix="$(openssl rand -hex 3 | sed 's/../&:/g; s/:$//')"
        mac="BC:24:11:${suffix^^}"

        if ! mac_address_in_use "$mac"; then
            echo "$mac"
            return 0
        fi
    done

    msg_error "Could not generate a unique VM MAC address after multiple attempts."
}

# --- 39. VM MAC FROM CONFIG HELPER ---
# Reads the VM net0 MAC address from Proxmox config after VM creation.
function get_vm_mac_from_config() {
    local vmid="$1"

    qm config "$vmid" 2>/dev/null | awk -F'[=,]' '/^net0:/ {print $2; exit}' | tr '[:lower:]' '[:upper:]'
}

# --- 40. YES/NO VALUE HELPER ---
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

# =========================================================
#  INITIALIZATION
# =========================================================

# --- 41. SCRIPT INITIALIZATION ---
# Starts logging, installs traps, validates root/proxmox/dependencies and shows banner.
function init_script() {
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
    check_previous_marker
}

# =========================================================
#  PHASE 1: SAFE AUDIT + USER INPUT COLLECTION ONLY
# =========================================================

# --- 42. SYSTEM RESOURCE AUDIT ---
# Detects RAM, CPU cores and calculates adaptive default VM resources.
function audit_system_resources() {
    section "SYSTEM RESOURCE AUDIT"

    msg_info "Auditing system resources"

    detect_system_type

    TOTAL_RAM_GB="$(detect_total_ram_gb)"
    TOTAL_CORES="$(nproc)"

    DEFAULT_RAM_GB=$(( TOTAL_RAM_GB * DEFAULT_RAM_PERCENT / 100 ))
    [ "$DEFAULT_RAM_GB" -lt 1 ] && DEFAULT_RAM_GB=1

    DEFAULT_CORES=$(( TOTAL_CORES * DEFAULT_CPU_PERCENT / 100 ))
    [ "$DEFAULT_CORES" -lt 1 ] && DEFAULT_CORES=1

    msg_ok "SYSTEM RESOURCES DETECTED"
}

# --- 43. SAFE SYSFS GPU AUDIT ---
# Detects GPU through sysfs only, avoiding lspci because lspci can hang on some fresh Proxmox/laptop systems.
function audit_gpu_hardware() {
    section "GPU AUDIT"

    msg_info "Detecting GPU hardware"

    detect_gpus_sysfs
    GPU_SUMMARY="$(build_gpu_summary)"

    if [ -n "$GPU_ALL" ]; then
        msg_ok "GPU DETECTION COMPLETE"
    else
        GPU_DETECTION_STATUS="skipped"
        msg_ok "GPU DETECTION SKIPPED"
    fi
}

# --- 44. SYSTEM AUDIT DISPLAY ---
# Shows available host resources and adaptive defaults before asking user inputs.
function show_system_audit() {
    section "SYSTEM AUDIT"

    echo -e " ${BL}━━━━━▶${CL} SYSTEM TYPE: ${GN}${SYSTEM_TYPE}${CL}"
    echo -e " ${BL}━━━━━▶${CL} HOST RESOURCES: ${GN}${TOTAL_CORES} CPU cores / ${TOTAL_RAM_GB}GB RAM${CL}"
    echo -e " ${BL}━━━━━▶${CL} DEFAULT VM: ${GN}${DEFAULT_CORES} CPU cores / ${DEFAULT_RAM_GB}GB RAM${CL}"

    if [ -n "$GPU_SUMMARY" ]; then
        echo -e " ${BL}━━━━━▶${CL} GPU: ${GN}${GPU_SUMMARY}${CL}"
    else
        echo -e " ${BL}━━━━━▶${CL} GPU: ${YW}No passthrough target detected or GPU detection skipped${CL}"
    fi
}

# --- 45. START CONFIRMATION ---
# Starts input collection after audit. No VM changes happen yet.
function start_confirmation() {
    local start_yn=""

    echo ""
    start_yn="$(timed_yes_no "Start the Proxmox VM Setup Script?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    return 0

}

# --- 46. USER VM CONFIGURATION INPUTS ---
# Collects VM ID, name, CPU, RAM and OS disk size using adaptive defaults.
# This stage still does not create or modify any VM.
function collect_vm_configuration_inputs() {
    local valid_name="no"

    section "VM CONFIGURATION"

    VMID="$(timed_number_input "Enter VM ID" "$DEFAULT_VMID" "1")"

    while [ "$valid_name" != "yes" ]; do
        VM_NAME="$(timed_text_input "Enter VM Name" "$DEFAULT_VM_NAME")"

        if validate_vm_name "$VM_NAME"; then
            valid_name="yes"
        else
            msg_warn "Invalid VM name. Use letters, numbers and hyphens only. Must start with a letter or number. Max 63 characters."
        fi
    done

    CPU_INPUT="$(timed_number_input "Enter CPU CORES" "$DEFAULT_CORES" "1" "$TOTAL_CORES")"
    RAM_GB_INPUT="$(timed_number_input "Enter RAM in GB" "$DEFAULT_RAM_GB" "1" "$TOTAL_RAM_GB")"
    DISK_GB_INPUT="$(timed_number_input "Enter OS DISK SIZE in GB" "$DEFAULT_DISK_GB" "8")"

    RAM_MB=$(( RAM_GB_INPUT * 1024 ))
}

# --- 47. ISO SELECTION ---
# Lists ISO files from local storage and lets the user choose one with numeric validation.
# Still input-only; no VM changes are made here.
function select_iso_image() {
    section "ISO SELECTION"

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

        ISO_IDX="$(timed_number_input "Select ISO number" "1" "1" "${#ISOS[@]}")"
        ISO_PATH="local:iso/$(basename "${ISOS[$((ISO_IDX-1))]}")"
    fi
}

# --- 48. STORAGE SELECTION ---
# Lists Proxmox storage that supports VM images and lets the user choose where to place VM disks.
# Still input-only; no VM changes are made here.

# --- SNAPSHOT-CAPABLE STORAGE HELPER ---
# Returns yes for storage types that support VM snapshots in Proxmox.
function storage_supports_snapshots() {
    local type="$1"

    case "$type" in
        lvmthin|zfspool|btrfs|rbd)
            echo "yes"
            ;;
        *)
            echo "no"
            ;;
    esac
}

# --- STORAGE ROLE LABEL HELPER ---
# Provides a clear user-facing role for storage choices.
function storage_role_label() {
    local type="$1"

    case "$type" in
        lvmthin|zfspool|btrfs|rbd)
            echo "VM disks/snapshots recommended"
            ;;
        dir|nfs|cifs|glusterfs)
            echo "ISO/backups/file storage; VM snapshots may not work"
            ;;
        lvm)
            echo "block storage; snapshots not recommended"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

function select_vm_storage() {
    local storage_name=""
    local storage_type=""
    local snapshot_support=""
    local role=""
    local default_index="1"
    local selected_snapshot_support=""
    local continue_yn=""

    section "STORAGE SELECTION"

    msg_info "Finding Proxmox storage"

    mapfile -t STORAGE_LIST < <(get_storage_list | sort)

    if [ "${#STORAGE_LIST[@]}" -eq 0 ]; then
        msg_error "No active Proxmox storage found for VM images."
    fi

    # Prefer snapshot-capable VM storage by default.
    for i in "${!STORAGE_LIST[@]}"; do
        storage_name="${STORAGE_LIST[$i]}"
        storage_type="$(get_storage_type "$storage_name")"
        if [ "$(storage_supports_snapshots "$storage_type")" == "yes" ]; then
            default_index="$((i+1))"
            break
        fi
    done

    msg_ok "STORAGE FOUND"
    echo ""
    echo -e "${BL}SELECT VM STORAGE:${CL}"

    for i in "${!STORAGE_LIST[@]}"; do
        storage_name="${STORAGE_LIST[$i]}"
        storage_type="$(get_storage_type "$storage_name")"
        snapshot_support="$(storage_supports_snapshots "$storage_type")"
        role="$(storage_role_label "$storage_type")"
        echo "$((i+1))) ${storage_name} (${storage_type:-unknown}) | snapshots: ${snapshot_support} | ${role}"
    done

    if [ "$default_index" == "1" ]; then
        storage_type="$(get_storage_type "${STORAGE_LIST[0]}")"
        if [ "$(storage_supports_snapshots "$storage_type")" != "yes" ]; then
            echo ""
            echo -e "${YW}No snapshot-capable VM storage was found.${CL}"
            echo -e "${YW}Recommended fix: run Script 2 to create LVM-thin VM storage, or preserve local-lvm in Script 1.${CL}"
            continue_yn="$(timed_yes_no "Continue using non-snapshot storage anyway?" "n")"
            if [[ "$continue_yn" =~ ^[Nn] ]]; then
                exit 0
            fi
        fi
    fi

    STORAGE_IDX="$(timed_number_input "Select storage number" "$default_index" "1" "${#STORAGE_LIST[@]}")"
    STORAGE_ID="${STORAGE_LIST[$((STORAGE_IDX-1))]}"
    STORAGE_TYPE="$(get_storage_type "$STORAGE_ID")"
    selected_snapshot_support="$(storage_supports_snapshots "$STORAGE_TYPE")"

    if [ "$selected_snapshot_support" != "yes" ]; then
        echo ""
        echo -e "${RD}${CLF}WARNING:${CL} Selected storage '${STORAGE_ID}' is type '${STORAGE_TYPE}'. VM snapshots may not be available.${CL}"
        echo -e "${YW}Recommended storage types for VM snapshots: lvmthin, zfspool, btrfs, rbd.${CL}"
        continue_yn="$(timed_yes_no "Continue with non-snapshot storage?" "n")"
        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi

    EFI_FORMAT="$(get_efi_format_for_storage_type "$STORAGE_TYPE")"
    detail_line "Selected storage" "${STORAGE_ID} (${STORAGE_TYPE})"
    detail_line "Snapshot capable" "$selected_snapshot_support"
    return 0
}

# --- 49. GPU PASSTHROUGH OPTION ---
# Offers discrete GPU passthrough only if sysfs GPU detection found a discrete GPU.
# Default is no for first Crea Social test because Docker/Postgres/Postiz do not require GPU initially.
function collect_gpu_passthrough_option() {
    local gpu_yn=""
    local gpu_pci_id=""

    section "GPU OPTION"

    if [ "$DGPU_FOUND" == "yes" ] && [ -n "$DGPU_BDFS" ]; then
        gpu_pci_id="$(echo "$DGPU_BDFS" | awk '{print $1}')"
        GPU_SAME_SLOT_BDFS="$(get_same_slot_functions_for_bdf "$gpu_pci_id")"
        [ -z "$GPU_SAME_SLOT_BDFS" ] && GPU_SAME_SLOT_BDFS="$gpu_pci_id"

        echo -e " ${BL}━━━━━▶${CL} DISCRETE GPU: ${GN}${gpu_pci_id}${CL}"
        echo -e " ${BL}━━━━━▶${CL} SAME-SLOT FUNCTIONS: ${GN}${GPU_SAME_SLOT_BDFS}${CL}"
        echo -e " ${BL}━━━━━▶${CL} RECOMMENDATION: ${YW}Not required for Docker/Postgres/Postiz initially${CL}"

        gpu_yn="$(timed_yes_no "Add DISCRETE GPU to VM?" "n")"

        if [[ "$gpu_yn" =~ ^[Yy] ]]; then
            ENABLE_GPU="y"
        else
            ENABLE_GPU="n"
        fi
    else
        ENABLE_GPU="n"
        msg_ok "NO DISCRETE GPU PASSTHROUGH TARGET FOUND"
    fi

    return 0
}

# --- 50. ADVANCED SETTINGS PROMPT ---
# Keeps Crea Social recommended defaults unless user chooses to edit advanced VM options.
function collect_advanced_settings() {
    local advanced_yn=""
    local balloon_yn=""
    local agent_yn=""
    local discard_yn=""

    section "ADVANCED VM SETTINGS"

    advanced_yn="$(timed_yes_no "Open Advanced VM Settings?" "n")"

    if [[ "$advanced_yn" =~ ^[Yy] ]]; then
        ADVANCED_SETTINGS="y"

        MACHINE_TYPE="$(timed_menu_select "Machine Type" "1" "q35" "i440fx")"
        BIOS_TYPE="$(timed_menu_select "BIOS Type" "1" "ovmf" "seabios")"
        CPU_TYPE_VM="$(timed_menu_select "CPU Type" "1" "host" "x86-64-v2-AES" "x86-64-v3" "kvm64" "max")"

        balloon_yn="$(timed_yes_no "Enable RAM Ballooning?" "n")"
        [[ "$balloon_yn" =~ ^[Yy] ]] && BALLOONING_ENABLED="yes" || BALLOONING_ENABLED="no"

        NETWORK_MODEL="$(timed_menu_select "Network Model" "1" "virtio" "e1000" "e1000e" "vmxnet3")"

        agent_yn="$(timed_yes_no "Enable QEMU Guest Agent?" "y")"
        [[ "$agent_yn" =~ ^[Nn] ]] && QEMU_AGENT_ENABLED="no" || QEMU_AGENT_ENABLED="yes"

        DISK_CONTROLLER="$(timed_menu_select "Disk Controller" "1" "virtio-scsi-single" "virtio-scsi-pci")"

        discard_yn="$(timed_yes_no "Enable Discard/TRIM?" "y")"
        [[ "$discard_yn" =~ ^[Nn] ]] && DISCARD_ENABLED="no" || DISCARD_ENABLED="yes"

        EFI_FORMAT_MODE="$(timed_menu_select "EFI Format Mode" "1" "auto" "raw" "qcow2")"

        if [ "$EFI_FORMAT_MODE" == "raw" ] || [ "$EFI_FORMAT_MODE" == "qcow2" ]; then
            EFI_FORMAT="$EFI_FORMAT_MODE"
        fi
    else
        ADVANCED_SETTINGS="n"
    fi

    apply_boolean_values
}

# --- 51. VM MAC ADDRESS CONFIGURATION ---
# Generates a stable VM MAC by default and optionally accepts a custom router-reserved MAC.
# The selected MAC is explicitly written into net0 so router DHCP reservation remains stable.
function collect_mac_configuration() {
    local custom_mac_yn=""
    local entered_mac=""

    section "VM NETWORK / ROUTER DHCP RESERVATION"

    echo -e "${YW}Recommended: keep DHCP inside Ubuntu and reserve a static IP in your router using the VM MAC address.${CL}"
    echo -e "${YW}This script can auto-generate a stable MAC, or you can enter a custom MAC if your router reservation already exists.${CL}"
    echo ""

    msg_info "Generating suggested VM MAC address"
    SUGGESTED_MAC_ADDRESS="$(generate_proxmox_mac)"
    msg_ok "SUGGESTED VM MAC ADDRESS GENERATED (${SUGGESTED_MAC_ADDRESS})"

    custom_mac_yn="$(timed_yes_no "Use custom VM MAC address?" "n")"

    if [[ "$custom_mac_yn" =~ ^[Yy] ]]; then
        while true; do
            entered_mac="$(timed_text_input "Enter custom VM MAC address" "$SUGGESTED_MAC_ADDRESS")"
            entered_mac="$(normalize_mac_address "$entered_mac")"

            if ! validate_mac_address "$entered_mac"; then
                msg_warn "Invalid MAC address format. Use format AA:BB:CC:DD:EE:FF."
                continue
            fi

            if mac_address_in_use "$entered_mac"; then
                msg_warn "MAC address ${entered_mac} is already used by an existing Proxmox VM."
                continue
            fi

            VM_MAC_ADDRESS="$entered_mac"

            if [ "$VM_MAC_ADDRESS" == "$SUGGESTED_MAC_ADDRESS" ]; then
                CUSTOM_MAC_SELECTED="no"
            else
                CUSTOM_MAC_SELECTED="yes"
            fi

            break
        done
    else
        VM_MAC_ADDRESS="$SUGGESTED_MAC_ADDRESS"
        CUSTOM_MAC_SELECTED="no"
    fi

    echo -e "${GN}VM MAC ADDRESS:${CL} ${VM_MAC_ADDRESS}"
    echo -e "${YW}Use this MAC in your router DHCP reservation if you want the VM to always receive the same IP.${CL}"
}

# --- 52. FINAL APPLY CONFIRMATION ---
# Last checkpoint before any Proxmox VM changes are made.
# Shows every setting, including safe defaults and advanced options, whether advanced mode was used or not.
function final_apply_confirmation() {
    local apply_yn=""

    section "READY TO CREATE VM"

    echo -e "VM ID: ${GN}${VMID}${CL}"
    echo -e "VM NAME: ${GN}${VM_NAME}${CL}"
    echo -e "CPU CORES: ${GN}${CPU_INPUT}${CL}"
    echo -e "RAM: ${GN}${RAM_GB_INPUT}GB${CL}"
    echo -e "OS DISK: ${GN}${DISK_GB_INPUT}GB${CL}"
    echo -e "STORAGE: ${GN}${STORAGE_ID}${CL}"
    echo -e "STORAGE TYPE: ${GN}${STORAGE_TYPE:-unknown}${CL}"
    echo -e "ISO: ${GN}${ISO_PATH:-none}${CL}"
    echo -e "GPU PASSTHROUGH: ${GN}${ENABLE_GPU}${CL}"
    echo -e "GPU FUNCTIONS: ${GN}${GPU_SAME_SLOT_BDFS:-none}${CL}"
    echo -e "VM MAC ADDRESS: ${GN}${VM_MAC_ADDRESS}${CL}"
    echo -e "CUSTOM MAC SELECTED: ${GN}${CUSTOM_MAC_SELECTED}${CL}"
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

    apply_yn="$(timed_yes_no "Create VM now?" "y")"

    if [[ "$apply_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    return 0
}

# =========================================================
#  PHASE 2: APPLY / CREATE VM ONLY AFTER ALL INPUTS
# =========================================================

# --- 53. VM ID CONFLICT CHECK ---
# Checks conflict only after all input is collected, immediately before creation.
# Uses qm config because it catches partial/incomplete VM configs better than qm status.
function check_vm_id_conflict() {
    section "VM ID CONFLICT CHECK"

    msg_info "Checking VM ID availability"

    if qm config "$VMID" >/dev/null 2>&1; then
        msg_error "VM ID ${VMID} already exists. Remove it first or choose another VM ID."
    fi

    msg_ok "VM ID ${VMID} AVAILABLE"
}

# --- 54. VM CREATE ---
# Creates Ubuntu/Linux VM using selected standard and advanced settings.
# Proxmox errors are captured and displayed if qm create fails.
function create_vm() {
    section "VM CREATION"

    msg_info "Creating VM ${VMID} (${VM_NAME})"

    run_proxmox_cmd "creating VM ${VMID}" \
        qm create "$VMID" \
        --name "$VM_NAME" \
        --machine "$MACHINE_TYPE" \
        --bios "$BIOS_TYPE" \
        --vga std \
        --ostype l26 \
        --cpu "$CPU_TYPE_VM" \
        --cores "$CPU_INPUT" \
        --memory "$RAM_MB" \
        --balloon "$BALLOON_VALUE" \
        --net0 "${NETWORK_MODEL}=${VM_MAC_ADDRESS},bridge=vmbr0" \
        --agent "$QEMU_AGENT_VALUE"

    VM_CREATED="yes"

    msg_ok "VM CREATED"
}

# --- 55. EFI DISK CONFIGURATION ---
# Adds OVMF EFI disk only when OVMF BIOS is selected.
# SeaBIOS does not use an EFI disk.
function configure_efi_disk() {
    if [ "$BIOS_TYPE" != "ovmf" ]; then
        return 0
    fi

    section "EFI DISK CONFIGURATION"

    msg_info "Configuring EFI disk"

    run_proxmox_cmd "configuring EFI disk" \
        qm set "$VMID" \
        --efidisk0 "${STORAGE_ID}:0,format=${EFI_FORMAT},efitype=4m,pre-enrolled-keys=0"

    msg_ok "EFI DISK CONFIGURED"
}

# --- 56. MAIN VM DISK CONFIGURATION ---
# Adds main OS disk with selected disk controller, discard setting and iothread.
function configure_vm_disk() {
    section "VM OS DISK CONFIGURATION"

    msg_info "Configuring VM OS disk"

    run_proxmox_cmd "setting disk controller" \
        qm set "$VMID" \
        --scsihw "$DISK_CONTROLLER"

    run_proxmox_cmd "creating VM OS disk" \
        qm set "$VMID" \
        --scsi0 "${STORAGE_ID}:${DISK_GB_INPUT},discard=${DISCARD_VALUE},iothread=1"

    msg_ok "VM OS DISK CONFIGURED"
}

# --- 57. ISO AND BOOT ORDER ---
# Attaches selected ISO if available and sets ISO-first boot order.
# If no ISO is attached, boots from OS disk only.
function configure_vm_boot() {
    section "VM BOOT CONFIGURATION"

    msg_info "Configuring VM boot"

    if [ -n "$ISO_PATH" ]; then
        run_proxmox_cmd "attaching ISO" \
            qm set "$VMID" \
            --cdrom "$ISO_PATH"

        BOOT_ORDER="ide2;scsi0"

        run_proxmox_cmd "setting VM boot order to ISO first" \
            qm set "$VMID" \
            --boot "order=${BOOT_ORDER}"
    else
        BOOT_ORDER="scsi0"

        run_proxmox_cmd "setting VM boot order to disk first" \
            qm set "$VMID" \
            --boot "order=${BOOT_ORDER}"
    fi

    msg_ok "VM BOOT CONFIGURED"
}

# --- 58. VM MAC VERIFICATION ---
# Reads back the MAC address from Proxmox config to confirm the router-reservation identity.
function verify_vm_mac() {
    local configured_mac=""

    section "VM MAC VERIFICATION"

    msg_info "Verifying VM MAC address"

    configured_mac="$(get_vm_mac_from_config "$VMID" || true)"

    if [ -n "$configured_mac" ]; then
        VM_MAC_ADDRESS="$configured_mac"
        msg_ok "VM MAC ADDRESS VERIFIED (${VM_MAC_ADDRESS})"
    else
        msg_warn "Could not read VM MAC address from Proxmox config. Check with: qm config ${VMID} | grep net0"
    fi
}

# --- 59. GPU PASSTHROUGH ATTACHMENT ---
# Adds all same-slot GPU functions to the VM if GPU passthrough is selected.
# This handles common GPU audio / USB / USB-C side functions.
function attach_gpu_passthrough() {
    local gpu_pci_id=""
    local gpu_func=""
    local pci_index="0"

    if [ "$ENABLE_GPU" != "y" ]; then
        return 0
    fi

    section "GPU PASSTHROUGH ATTACHMENT"

    msg_info "Preparing discrete GPU passthrough"

    gpu_pci_id="$(echo "$DGPU_BDFS" | awk '{print $1}')"

    if [ -z "$gpu_pci_id" ]; then
        msg_warn "GPU passthrough selected but no GPU PCI ID found."
        return 0
    fi

    if [ -z "$GPU_SAME_SLOT_BDFS" ]; then
        GPU_SAME_SLOT_BDFS="$(get_same_slot_functions_for_bdf "$gpu_pci_id")"
        [ -z "$GPU_SAME_SLOT_BDFS" ] && GPU_SAME_SLOT_BDFS="$gpu_pci_id"
    fi

    msg_ok "GPU SAME-SLOT FUNCTIONS READY"
    echo -e " ${BL}━━━━━▶${CL} ${GPU_SAME_SLOT_BDFS}"

    for gpu_func in $GPU_SAME_SLOT_BDFS; do
        msg_info "Attaching GPU function ${gpu_func} to hostpci${pci_index}"

        run_proxmox_cmd "attaching GPU function ${gpu_func}" \
            qm set "$VMID" \
            --hostpci${pci_index} "${gpu_func},pcie=1"

        GPU_FUNCTIONS_ATTACHED+="${gpu_func} "
        msg_ok "GPU FUNCTION ATTACHED (${gpu_func} -> hostpci${pci_index})"

        pci_index=$((pci_index + 1))
    done

    GPU_FUNCTIONS_ATTACHED="$(echo "$GPU_FUNCTIONS_ATTACHED" | xargs)"
    msg_ok "GPU PASSTHROUGH ENABLED (${GPU_FUNCTIONS_ATTACHED})"
}

# --- 60. COMPLETION MARKER ---
# Creates marker file so future checks can identify that this setup was already run.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

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
GPU Functions Attached: ${GPU_FUNCTIONS_ATTACHED:-none}
VM MAC Address: ${VM_MAC_ADDRESS}
Custom MAC Selected: ${CUSTOM_MAC_SELECTED}
Boot Order: ${BOOT_ORDER:-unknown}
Verify Log: ${VERIFY_LOG}
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

    msg_ok "COMPLETION MARKER WRITTEN"
}


# --- 61. VERIFICATION REPORT ---
# Creates a detailed post-create verification report without changing the VM.
function create_verification_report() {
    section "VERIFICATION"

    msg_info "Creating VM verification report"

    cat <<EOF > "$VERIFY_LOG"
--- PROXMOX VM SETUP VERIFICATION REPORT ---
Date: $(date)
VMID: ${VMID}
Name: ${VM_NAME}
Verify Log: ${VERIFY_LOG}

Results:
EOF

    {
        local config=""
        config="$(qm config "$VMID" 2>/dev/null || true)"

        PASS() { echo "✓ PASS - $1"; }
        WARN() { echo "! WARN - $1"; }
        FAIL() { echo "✗ FAIL - $1"; }

        if [ -n "$config" ]; then PASS "VM config exists"; else FAIL "VM config missing"; fi
        if grep -q "^name: ${VM_NAME}$" <<< "$config"; then PASS "VM name matches"; else WARN "VM name not confirmed"; fi
        if grep -q "^cores: ${CPU_INPUT}$" <<< "$config"; then PASS "CPU core count matches"; else WARN "CPU core count not confirmed"; fi
        if grep -q "^memory: ${RAM_MB}$" <<< "$config"; then PASS "RAM value matches"; else WARN "RAM value not confirmed"; fi
        if grep -qi "${VM_MAC_ADDRESS}" <<< "$config"; then PASS "VM MAC address matches"; else FAIL "VM MAC address not found in config"; fi
        if grep -q "^boot: order=${BOOT_ORDER}" <<< "$config"; then PASS "Boot order matches"; else WARN "Boot order not confirmed"; fi

        if [ "$BIOS_TYPE" == "ovmf" ]; then
            if grep -q "^efidisk0:" <<< "$config"; then PASS "EFI disk exists"; else FAIL "EFI disk missing"; fi
        else
            WARN "EFI disk check skipped because BIOS is ${BIOS_TYPE}"
        fi

        if grep -q "^scsi0:" <<< "$config"; then PASS "OS disk exists"; else FAIL "OS disk missing"; fi

        if [ -n "$ISO_PATH" ]; then
            if grep -q "${ISO_PATH}" <<< "$config"; then PASS "ISO attached"; else WARN "ISO attachment not confirmed"; fi
        else
            WARN "ISO check skipped because no ISO was selected"
        fi

        if grep -q "^agent: ${QEMU_AGENT_VALUE}" <<< "$config"; then PASS "QEMU guest agent setting matches"; else WARN "QEMU guest agent setting not confirmed"; fi
        if grep -q "discard=${DISCARD_VALUE}" <<< "$config"; then PASS "Discard/TRIM setting matches"; else WARN "Discard/TRIM setting not confirmed"; fi

        if [ "$ENABLE_GPU" == "y" ]; then
            if grep -q "^hostpci" <<< "$config"; then PASS "GPU hostpci entries exist"; else FAIL "GPU hostpci entries missing"; fi
        else
            WARN "GPU passthrough not selected"
        fi

        if [ -f "$COMPLETED_MARKER" ]; then PASS "Completion marker exists"; else WARN "Completion marker missing at verification time"; fi

        echo ""
        echo "VM config summary:"
        qm config "$VMID" 2>/dev/null || true
    } | tee -a "$VERIFY_LOG" >/dev/null

    msg_ok "VM VERIFICATION REPORT CREATED"
}

# --- 62. FINAL SUMMARY ---
# Shows final VM configuration and the MAC address to reserve in the router.
function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    echo -e "VM ID: ${GN}${VMID}${CL}"
    echo -e "VM NAME: ${GN}${VM_NAME}${CL}"
    echo -e "RAM: ${GN}${RAM_GB_INPUT}GB${CL}"
    echo -e "CPU CORES: ${GN}${CPU_INPUT}${CL}"
    echo -e "OS DISK: ${GN}${DISK_GB_INPUT}GB${CL}"
    echo -e "STORAGE: ${GN}${STORAGE_ID}${CL}"
    echo -e "STORAGE TYPE: ${GN}${STORAGE_TYPE:-unknown}${CL}"
    echo -e "ISO: ${GN}${ISO_PATH:-none}${CL}"
    echo -e "GPU PASSTHROUGH: ${GN}${ENABLE_GPU}${CL}"
    echo -e "GPU FUNCTIONS ATTACHED: ${GN}${GPU_FUNCTIONS_ATTACHED:-none}${CL}"
    echo -e "VGA DISPLAY: ${GN}std${CL}"
    echo -e "MACHINE TYPE: ${GN}${MACHINE_TYPE}${CL}"
    echo -e "BIOS: ${GN}${BIOS_TYPE}${CL}"
    echo -e "EFI FORMAT: ${GN}${EFI_FORMAT}${CL}"
    echo -e "CPU TYPE: ${GN}${CPU_TYPE_VM}${CL}"
    echo -e "BALLOONING: ${GN}${BALLOONING_ENABLED}${CL}"
    echo -e "NETWORK MODEL: ${GN}${NETWORK_MODEL}${CL}"
    echo -e "QEMU GUEST AGENT: ${GN}${QEMU_AGENT_ENABLED}${CL}"
    echo -e "DISK CONTROLLER: ${GN}${DISK_CONTROLLER}${CL}"
    echo -e "DISCARD/TRIM: ${GN}${DISCARD_ENABLED}${CL}"
    echo -e "BOOT ORDER: ${GN}${BOOT_ORDER:-unknown}${CL}"
    echo -e "VERIFY LOG: ${GN}${VERIFY_LOG}${CL}"
    echo ""
    echo -e "${BL}NETWORK / ROUTER DHCP RESERVATION:${CL}"
    echo -e "VM MAC ADDRESS: ${GN}${VM_MAC_ADDRESS}${CL}"
    echo -e "CUSTOM MAC SELECTED: ${GN}${CUSTOM_MAC_SELECTED}${CL}"
    echo -e "${YW}Recommended: reserve this MAC address in your router so the VM always receives the same IP via DHCP.${CL}"
    echo -e "${YW}Check later with: qm config ${VMID} | grep net0${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"

    if [ -n "$ISO_PATH" ]; then
        echo -e "${YW}Manual install path:${CL} Start the VM and install Ubuntu from the Proxmox console."
    else
        echo -e "${YW}No ISO was attached. Attach/install media before starting the VM.${CL}"
    fi

    echo -e "${YW}Autoinstall path:${CL} Run script 3.5 next to generate and attach the Ubuntu autoinstall ISO."
    echo ""
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 62. MAIN FUNCTION ---
# Runs the full script in validation -> audit -> input -> final confirmation -> apply order.
function main() {
    init_script

    audit_system_resources
    audit_gpu_hardware
    show_system_audit
    start_confirmation

    collect_vm_configuration_inputs
    select_iso_image
    select_vm_storage
    collect_gpu_passthrough_option
    collect_advanced_settings
    collect_mac_configuration
    final_apply_confirmation

    check_vm_id_conflict
    create_vm
    configure_efi_disk
    configure_vm_disk
    configure_vm_boot
    verify_vm_mac
    attach_gpu_passthrough
    write_completion_marker
    create_verification_report
    show_final_summary

    exit 0
}

main "$@"
