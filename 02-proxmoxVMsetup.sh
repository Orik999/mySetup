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

DEFAULT_VM_NAME="ct-crea"
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

STORAGE_ID=""
ISO_PATH=""
ENABLE_GPU="n"

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

# --- 12. BLOCKING TEXT INPUT HELPER ---
# Used when SPACE pauses a timed text/numeric prompt.
# After SPACE, the user can type a value and press ENTER, or press ENTER for default.
function tty_read_text_blocking() {
    local prompt="$1"
    local default="$2"
    local answer=""

    tty_print "${BFR}${YW}${prompt} [default: ${default}] [timer stopped - type value or ENTER for default]: ${CL}"

    if [ -r /dev/tty ]; then
        IFS= read -r answer < /dev/tty || true
    else
        IFS= read -r answer || true
    fi

    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    echo "$answer"
}

# --- 13. BLOCKING TEXT INPUT WITH INITIAL KEY HELPER ---
# Used when the user starts typing during countdown.
# The first typed key pauses the countdown and becomes the first character of the answer.
function tty_read_text_with_initial_key() {
    local prompt="$1"
    local default="$2"
    local initial_key="$3"
    local rest=""
    local answer=""

    answer="$initial_key"

    tty_print "${BFR}${YW}${prompt} [default: ${default}] [typing - countdown paused]: ${CL}${answer}"

    if [ -r /dev/tty ]; then
        IFS= read -r rest < /dev/tty || true
    else
        IFS= read -r rest || true
    fi

    answer="${answer}${rest}"
    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    echo "$answer"
}

# --- 14. TIMED TEXT INPUT HELPER ---
# Shows a live wall-clock countdown for text input.
# SPACE pauses the timer and waits for typed input.
# Any typed character pauses the timer and waits for the rest of the input.
# Timeout accepts default.
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
                    answer="$(tty_read_text_blocking "$prompt" "$default")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(tty_read_text_with_initial_key "$prompt" "$default" "$key")"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(tty_read_text_blocking "$prompt" "$default")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    break
                else
                    answer="$(tty_read_text_with_initial_key "$prompt" "$default" "$key")"
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

# --- 15. NUMERIC VALIDATION HELPER ---
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

# --- 16. NUMERIC ERROR HELPER ---
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

# --- 17. BLOCKING NUMERIC INPUT HELPER ---
# Used when SPACE pauses a numeric prompt.
# Waits for number input and validates after ENTER.
function tty_read_number_blocking() {
    local prompt="$1"
    local default="$2"
    local min_value="${3:-1}"
    local max_value="${4:-}"
    local answer=""

    while true; do
        tty_print "${BFR}${YW}${prompt} [default: ${default}] [timer stopped - type number or ENTER for default]: ${CL}"

        if [ -r /dev/tty ]; then
            IFS= read -r answer < /dev/tty || true
        else
            IFS= read -r answer || true
        fi

        [ -z "$answer" ] && answer="$default"

        if validate_number "$answer" "$min_value" "$max_value"; then
            tty_print "${BFR}"
            echo "$answer"
            return 0
        fi

        tty_print "${BFR}"
        print_number_error "$min_value" "$max_value"
    done
}

# --- 18. BLOCKING NUMERIC INPUT WITH INITIAL KEY HELPER ---
# Used when the user starts typing during numeric countdown.
# The first typed digit pauses the countdown and becomes the first digit.
function tty_read_number_with_initial_key() {
    local prompt="$1"
    local default="$2"
    local initial_key="$3"
    local min_value="${4:-1}"
    local max_value="${5:-}"
    local rest=""
    local answer=""

    if ! [[ "$initial_key" =~ ^[0-9]$ ]]; then
        print_number_error "$min_value" "$max_value"
        echo "INVALID"
        return 0
    fi

    while true; do
        answer="$initial_key"

        tty_print "${BFR}${YW}${prompt} [default: ${default}] [typing - countdown paused]: ${CL}${answer}"

        if [ -r /dev/tty ]; then
            IFS= read -r rest < /dev/tty || true
        else
            IFS= read -r rest || true
        fi

        answer="${answer}${rest}"
        [ -z "$answer" ] && answer="$default"

        if validate_number "$answer" "$min_value" "$max_value"; then
            tty_print "${BFR}"
            echo "$answer"
            return 0
        fi

        tty_print "${BFR}"
        print_number_error "$min_value" "$max_value"
        echo "INVALID"
        return 0
    done
}

# --- 19. TIMED NUMERIC INPUT HELPER ---
# Shows a live wall-clock countdown for numeric input.
# SPACE pauses and waits.
# Any digit pauses countdown and waits for ENTER.
# Timeout accepts default.
# Letters/symbols are rejected and the prompt repeats.
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
        answer=""
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
                        answer="$(tty_read_number_blocking "$prompt" "$default" "$min_value" "$max_value")"
                        break
                    elif [[ -z "$key" ]]; then
                        answer="$default"
                        break
                    elif [[ "$key" =~ ^[0-9]$ ]]; then
                        answer="$(tty_read_number_with_initial_key "$prompt" "$default" "$key" "$min_value" "$max_value")"
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
                        answer="$(tty_read_number_blocking "$prompt" "$default" "$min_value" "$max_value")"
                        break
                    elif [[ -z "$key" ]]; then
                        answer="$default"
                        break
                    elif [[ "$key" =~ ^[0-9]$ ]]; then
                        answer="$(tty_read_number_with_initial_key "$prompt" "$default" "$key" "$min_value" "$max_value")"
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

# --- 20. GPU NAME CLEANUP HELPER ---
# Removes PCI IDs and extra text to make GPU display readable.
function clean_gpu_name() {
    echo "$1" | sed -E 's/^[0-9a-fA-F:.]+[[:space:]]+//; s/\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]//g; s/\(rev [^)]+\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//'
}

# --- 21. GPU SUMMARY HELPER ---
# Creates readable integrated/discrete GPU summary for the audit screen.
function build_gpu_summary() {
    local out=""

    if [ -n "$IGPU_LINES" ]; then
        while read -r line; do
            [ -z "$line" ] && continue
            out+="Integrated: $(clean_gpu_name "$line"); "
        done <<< "$IGPU_LINES"
    fi

    if [ -n "$DGPU_LINES" ]; then
        while read -r line; do
            [ -z "$line" ] && continue
            out+="Discrete: $(clean_gpu_name "$line"); "
        done <<< "$DGPU_LINES"
    fi

    echo "${out%; }"
}

# --- 22. PHYSICAL RAM DETECTION HELPER ---
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

# --- 23. PROXMOX VALIDATION ---
# Confirms the script is being run on Proxmox VE 9 or newer.
if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This system is not Proxmox VE. Script cancelled."
fi

PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)

if ! [[ "$PVE_MAJOR" =~ ^[0-9]+$ ]] || [ "$PVE_MAJOR" -lt 9 ]; then
    msg_error "Requires Proxmox VE 9+."
fi

# --- 24. SYSTEM RESOURCE AUDIT ---
# Detects RAM, CPU cores and calculates adaptive default VM resources.
msg_info "Auditing system resources"

TOTAL_RAM_GB=$(detect_total_ram_gb)
TOTAL_CORES=$(nproc)

DEFAULT_RAM_GB=$(( TOTAL_RAM_GB * DEFAULT_RAM_PERCENT / 100 ))
[ "$DEFAULT_RAM_GB" -lt 1 ] && DEFAULT_RAM_GB=1

DEFAULT_CORES=$(( TOTAL_CORES * DEFAULT_CPU_PERCENT / 100 ))
[ "$DEFAULT_CORES" -lt 1 ] && DEFAULT_CORES=1

msg_ok "SYSTEM RESOURCES DETECTED"

# --- 25. GPU AUDIT ---
# Detects integrated and discrete GPUs. Only discrete GPU is offered for passthrough.
msg_info "Detecting GPU hardware"

GPU_ALL=$(lspci -Dnn | grep -Ei "VGA compatible controller|3D controller|Display controller" || true)
IGPU_LINES=$(echo "$GPU_ALL" | grep -Ei "Intel|Integrated|UHD|Iris" || true)
DGPU_LINES=$(echo "$GPU_ALL" | grep -Eiv "Intel|Integrated|UHD|Iris" | grep -Ei "NVIDIA|AMD|ATI|Radeon|GeForce|RTX|GTX|Quadro|Tesla|FirePro|Arc" || true)

[ -n "$IGPU_LINES" ] && IGPU_FOUND="yes"
[ -n "$DGPU_LINES" ] && DGPU_FOUND="yes"

if [ "$DGPU_FOUND" == "yes" ]; then
    while read -r gpu_line; do
        [ -z "$gpu_line" ] && continue
        gpu_bdf=$(echo "$gpu_line" | awk '{print $1}')
        DGPU_BDFS+="${gpu_bdf} "
    done <<< "$DGPU_LINES"
fi

GPU_SUMMARY=$(build_gpu_summary)

msg_ok "GPU DETECTION COMPLETE"

# --- 26. SYSTEM AUDIT DISPLAY ---
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
    echo -e "GPU: ${YW}No passthrough target detected${CL}"
fi

echo "------------------------------------------------------"

# --- 27. FINAL START CONFIRMATION ---
# Starts VM setup after the audit screen.
start_yn=$(timed_yes_no "Start the Proxmox VM Setup Script?" "y")
[[ "$start_yn" =~ ^[Nn] ]] && exit 0

# --- 28. USER VM CONFIGURATION INPUTS ---
# Collects VM ID, name, CPU, RAM and OS disk size using adaptive defaults.
VMID=$(timed_number_input "Enter VM ID" "$DEFAULT_VMID" "1")
VM_NAME=$(timed_text_input "Enter VM Name" "$DEFAULT_VM_NAME")
CPU_INPUT=$(timed_number_input "Enter CPU CORES" "$DEFAULT_CORES" "1" "$TOTAL_CORES")
RAM_GB_INPUT=$(timed_number_input "Enter RAM in GB" "$DEFAULT_RAM_GB" "1" "$TOTAL_RAM_GB")
DISK_GB_INPUT=$(timed_number_input "Enter OS DISK SIZE in GB" "$DEFAULT_DISK_GB" "8")

RAM_MB=$(( RAM_GB_INPUT * 1024 ))

# --- 29. VM ID CONFLICT CHECK ---
# Prevents overwriting an existing VM ID.
if qm status "$VMID" >/dev/null 2>&1; then
    msg_error "VM ID ${VMID} already exists."
fi

# --- 30. ISO SELECTION ---
# Lists ISO files from local storage and lets the user choose one with numeric validation.
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

# --- 31. STORAGE SELECTION ---
# Lists Proxmox storage that supports images and lets the user choose where to place VM disks.
msg_info "Finding Proxmox storage"

mapfile -t STORAGE_LIST < <(pvesm status --content images 2>/dev/null | awk 'NR>1 {print $1}' | sort || true)

if [ "${#STORAGE_LIST[@]}" -eq 0 ]; then
    msg_error "No Proxmox storage found with images content."
fi

msg_ok "STORAGE FOUND"
echo ""
echo -e "${BL}SELECT VM STORAGE:${CL}"

for i in "${!STORAGE_LIST[@]}"; do
    echo "$((i+1))) ${STORAGE_LIST[$i]}"
done

STORAGE_IDX=$(timed_number_input "Select storage number" "1" "1" "${#STORAGE_LIST[@]}")
STORAGE_ID="${STORAGE_LIST[$((STORAGE_IDX-1))]}"

# --- 32. GPU PASSTHROUGH OPTION ---
# Offers discrete GPU passthrough only if a discrete GPU exists.
if [ "$DGPU_FOUND" == "yes" ]; then
    gpu_yn=$(timed_yes_no "Add DISCRETE GPU to VM?" "y")
    [[ "$gpu_yn" =~ ^[Yy] ]] && ENABLE_GPU="y"
fi

# --- 33. VM CREATE ---
# Creates Ubuntu/Linux VM with q35, OVMF, host CPU, fixed RAM and VirtIO network.
msg_info "Creating VM ${VMID} (${VM_NAME})"

qm create "$VMID" \
    --name "$VM_NAME" \
    --machine q35 \
    --bios ovmf \
    --ostype l26 \
    --cpu host \
    --cores "$CPU_INPUT" \
    --memory "$RAM_MB" \
    --balloon 0 \
    --net0 virtio,bridge=vmbr0 \
    --agent enabled=1 \
    &>/dev/null

msg_ok "VM CREATED"

# --- 34. VM DISK CONFIGURATION ---
# Adds EFI disk and main OS disk with discard enabled for SSD/LVM-thin friendly behaviour.
msg_info "Configuring VM disks"

qm set "$VMID" --efidisk0 "${STORAGE_ID}:0,format=qcow2,efitype=4m,pre-enrolled-keys=0" &>/dev/null
qm set "$VMID" --scsihw virtio-scsi-single &>/dev/null
qm set "$VMID" --scsi0 "${STORAGE_ID}:${DISK_GB_INPUT},discard=on,iothread=1" &>/dev/null

msg_ok "VM DISKS CONFIGURED"

# --- 35. ISO AND BOOT ORDER ---
# Attaches selected ISO if available and sets VM boot order.
msg_info "Configuring VM boot"

if [ -n "$ISO_PATH" ]; then
    qm set "$VMID" --cdrom "$ISO_PATH" &>/dev/null
fi

qm set "$VMID" --boot order=scsi0\;ide2 &>/dev/null

msg_ok "VM BOOT CONFIGURED"

# --- 36. GPU PASSTHROUGH ATTACHMENT ---
# Adds the first detected discrete GPU BDF to the VM.
if [ "$ENABLE_GPU" == "y" ]; then
    msg_info "Attaching discrete GPU to VM"

    GPU_PCI_ID=$(echo "$DGPU_BDFS" | awk '{print $1}')

    if [ -n "$GPU_PCI_ID" ]; then
        qm set "$VMID" --hostpci0 "${GPU_PCI_ID},pcie=1,x-vga=1" &>/dev/null
        msg_ok "GPU PASSTHROUGH ENABLED (${GPU_PCI_ID})"
    else
        msg_warn "GPU passthrough selected but no GPU PCI ID found."
    fi
fi

# --- 37. COMPLETION MARKER ---
# Creates marker file so future checks can identify that this setup was already run.
cat <<EOF > "$COMPLETED_MARKER"
Proxmox VM Setup completed on: $(date)
VMID: $VMID
Name: $VM_NAME
RAM: ${RAM_GB_INPUT}GB
CPU: ${CPU_INPUT}
Storage: ${STORAGE_ID}
EOF

# --- 38. FINAL SUMMARY ---
# Shows final VM configuration.
echo ""
echo -e "${GN}FINISHED!${CL}"
echo -e "VM ID: ${GN}${VMID}${CL}"
echo -e "VM NAME: ${GN}${VM_NAME}${CL}"
echo -e "RAM: ${GN}${RAM_GB_INPUT}GB${CL}"
echo -e "CPU CORES: ${GN}${CPU_INPUT}${CL}"
echo -e "OS DISK: ${GN}${DISK_GB_INPUT}GB${CL}"
echo -e "STORAGE: ${GN}${STORAGE_ID}${CL}"
echo -e "GPU PASSTHROUGH: ${GN}${ENABLE_GPU}${CL}"
echo ""

exit 0