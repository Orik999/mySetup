#!/usr/bin/env bash -ex
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  PVE9 VM Setup
#  Template style based on PVE9 Post Install.
#  Creates an Ubuntu Server VM for Docker / Traefik / Authentik / Postgres / Apps.
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

# --- 2. GLOBAL DEFAULTS ---
# These are the base recommendations from your Gemini-created data.
VM_NAME_DEFAULT="ct-crea"
VMID_DEFAULT="100"
BASE_RAM_PERCENT=75
BASE_CPU_PERCENT=50
BASE_OS_DISK_GB=40
BASE_DATA_DISK_GB=0
DEFAULT_STORAGE=""
DEFAULT_ISO=""
LOG_FILE="/var/log/pve9-vm-setup.log"

# --- 3. RUNTIME VARIABLES ---
# These are filled during the audit and user option sections.
TOTAL_RAM_GB=0
TOTAL_RAM_MB=0
TOTAL_CORES=0
TOTAL_DISK_GB=0
DEFAULT_RAM_GB=0
DEFAULT_CORES=0
DEFAULT_OS_DISK_GB=40
DEFAULT_DATA_DISK_GB=0
VMID=""
VM_NAME=""
CPU_INPUT=""
RAM_GB_INPUT=""
RAM_MB=""
OS_DISK_GB=""
DATA_DISK_GB=""
ISO_PATH=""
SELECTED_STORAGE=""
SELECTED_STORAGE_TYPE=""
SELECTED_STORAGE_FREE_GB=0
STORAGE_IS_SSD="unknown"
STORAGE_IS_NVME="unknown"
STORAGE_IS_ZFS="no"
STORAGE_IS_LVM="no"
STORAGE_IS_DIR="no"
ENABLE_GPU="n"
GPU_FOUND=""
DGPU_LINES=""
DGPU_BDF=""
DGPU_SLOT=""
DGPU_AUDIO_BDF=""
DGPU_IDS=""
BOOT_ORDER="scsi0;ide2"

# --- 4. LOGGING ---
# Saves output to a log file while still showing it on screen.
exec > >(tee -a "$LOG_FILE") 2>&1

# --- 5. HEADER & MESSAGING FUNCTIONS ---
# Shows the ASCII banner and gives reusable status output helpers.
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

function msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 6. ROOT / PROXMOX CHECKS ---
# Ensures the script is being run as root on a Proxmox host with qm available.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

if ! command -v qm >/dev/null 2>&1; then
    echo -e "${RD}qm command not found. This must be run on a Proxmox host.${CL}"
    exit 1
fi

clear
header_info

# --- 7. HELPER FUNCTIONS ---
# Provides input validation, timed prompts, GB calculations, and safe default handling.
function timed_prompt() {
    local prompt="$1"
    local default="$2"
    local input=""
    read -t "$T" -p "$prompt" input || input="$default"
    if [ -z "$input" ]; then
        input="$default"
    fi
    echo "$input"
}

function is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

function clamp_int() {
    local value="$1"
    local min="$2"
    local max="$3"
    if [ "$value" -lt "$min" ]; then
        echo "$min"
    elif [ "$value" -gt "$max" ]; then
        echo "$max"
    else
        echo "$value"
    fi
}

function bytes_to_gb() {
    awk -v bytes="$1" 'BEGIN { printf "%d", bytes / 1024 / 1024 / 1024 }'
}

# --- 8. SYSTEM AUDIT ---
# Reads host RAM, CPU cores, total disk space, and calculates adaptive defaults.
msg_info "Running system audit"

TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_MB / 1024 ))
[ "$TOTAL_RAM_GB" -lt 1 ] && TOTAL_RAM_GB=1

TOTAL_CORES=$(nproc)
[ "$TOTAL_CORES" -lt 1 ] && TOTAL_CORES=1

TOTAL_DISK_GB=$(lsblk -b -dn -o SIZE,TYPE | awk '$2=="disk"{sum+=$1} END{printf "%d", sum/1024/1024/1024}')
[ "$TOTAL_DISK_GB" -lt 1 ] && TOTAL_DISK_GB=1

DEFAULT_RAM_GB=$(( TOTAL_RAM_GB * BASE_RAM_PERCENT / 100 ))
DEFAULT_RAM_GB=$(clamp_int "$DEFAULT_RAM_GB" 1 "$TOTAL_RAM_GB")

DEFAULT_CORES=$(( TOTAL_CORES * BASE_CPU_PERCENT / 100 ))
DEFAULT_CORES=$(clamp_int "$DEFAULT_CORES" 1 "$TOTAL_CORES")

DEFAULT_OS_DISK_GB="$BASE_OS_DISK_GB"
if [ "$TOTAL_DISK_GB" -lt 120 ]; then
    DEFAULT_OS_DISK_GB=$(( TOTAL_DISK_GB * 25 / 100 ))
    DEFAULT_OS_DISK_GB=$(clamp_int "$DEFAULT_OS_DISK_GB" 20 "$BASE_OS_DISK_GB")
fi

msg_ok "SYSTEM AUDIT COMPLETE"

# --- 9. GPU AUDIT ---
# Detects only discrete GPUs for passthrough and avoids selecting Intel integrated graphics.
msg_info "Detecting discrete GPU"

GPU_FOUND=$(lspci -Dnn | grep -Ei "VGA compatible controller|3D controller|Display controller" || true)
DGPU_LINES=$(echo "$GPU_FOUND" | grep -Eiv "Intel|Integrated|UHD|Iris" | grep -Ei "NVIDIA|AMD|ATI|Radeon|GeForce|RTX|GTX|Quadro|Tesla|FirePro|Arc" || true)

if [ -n "$DGPU_LINES" ]; then
    DGPU_BDF=$(echo "$DGPU_LINES" | head -n 1 | awk '{print $1}')
    DGPU_SLOT="${DGPU_BDF%.*}"

    while read -r func_line; do
        [ -z "$func_line" ] && continue
        func_id=$(echo "$func_line" | grep -Po '\[\K[0-9a-fA-F]{4}:[0-9a-fA-F]{4}' | tail -n1 || true)
        [ -n "$func_id" ] && DGPU_IDS+="${func_id},"
    done < <(lspci -Dnn -s "$DGPU_SLOT" || true)

    DGPU_IDS="${DGPU_IDS%,}"
fi

msg_ok "GPU AUDIT COMPLETE"

# --- 10. STORAGE AUDIT ---
# Detects Proxmox storages suitable for VM disks and determines type, free space, SSD/HDD, NVMe/SATA, ZFS/LVM/DIR.
msg_info "Auditing Proxmox storage"

mapfile -t STORAGE_LIST < <(pvesm status --content images 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}' || true)

if [ "${#STORAGE_LIST[@]}" -eq 0 ]; then
    mapfile -t STORAGE_LIST < <(pvesm status 2>/dev/null | awk 'NR>1 && $3=="active"{print $1}' || true)
fi

if [ "${#STORAGE_LIST[@]}" -eq 0 ]; then
    msg_error "No active Proxmox storage found for VM images"
fi

for storage in "${STORAGE_LIST[@]}"; do
    if [ "$storage" == "local-lvm" ]; then
        DEFAULT_STORAGE="$storage"
        break
    fi
done

if [ -z "$DEFAULT_STORAGE" ]; then
    for storage in "${STORAGE_LIST[@]}"; do
        if [ "$storage" == "local-zfs" ]; then
            DEFAULT_STORAGE="$storage"
            break
        fi
    done
fi

if [ -z "$DEFAULT_STORAGE" ]; then
    DEFAULT_STORAGE="${STORAGE_LIST[0]}"
fi

SELECTED_STORAGE_TYPE=$(pvesm status 2>/dev/null | awk -v s="$DEFAULT_STORAGE" '$1==s{print $2}')
SELECTED_STORAGE_FREE_GB=$(pvesm status 2>/dev/null | awk -v s="$DEFAULT_STORAGE" '$1==s{printf "%d", $6/1024/1024}')

if echo "$SELECTED_STORAGE_TYPE" | grep -qi "zfs"; then
    STORAGE_IS_ZFS="yes"
fi

if echo "$SELECTED_STORAGE_TYPE" | grep -qi "lvm"; then
    STORAGE_IS_LVM="yes"
fi

if echo "$SELECTED_STORAGE_TYPE" | grep -qi "dir"; then
    STORAGE_IS_DIR="yes"
fi

if lsblk -dn -o NAME,ROTA | awk '$2==0{found=1} END{exit !found}'; then
    STORAGE_IS_SSD="yes"
else
    STORAGE_IS_SSD="no"
fi

if lsblk -dn -o NAME | grep -q "^nvme"; then
    STORAGE_IS_NVME="yes"
else
    STORAGE_IS_NVME="no"
fi

if [ "$SELECTED_STORAGE_FREE_GB" -gt 0 ] && [ "$DEFAULT_OS_DISK_GB" -gt "$SELECTED_STORAGE_FREE_GB" ]; then
    DEFAULT_OS_DISK_GB=$(( SELECTED_STORAGE_FREE_GB * 50 / 100 ))
    DEFAULT_OS_DISK_GB=$(clamp_int "$DEFAULT_OS_DISK_GB" 20 "$SELECTED_STORAGE_FREE_GB")
fi

msg_ok "STORAGE AUDIT COMPLETE"

# --- 11. SYSTEM AUDIT DISPLAY ---
# Shows total system resources and detected GPU/storage status before asking for options.
echo ""
echo -e "${DGN}SYSTEM AUDIT:${CL}"
echo -e "TOTAL RAM: ${GN}${TOTAL_RAM_GB}GB${CL}"
echo -e "CPU CORES: ${GN}${TOTAL_CORES}${CL}"
echo -e "TOTAL DISK SPACE: ${GN}${TOTAL_DISK_GB}GB${CL}"
echo -e "DEFAULT VM RAM: ${GN}${DEFAULT_RAM_GB}GB${CL} (${BASE_RAM_PERCENT}% of TOTAL RAM)"
echo -e "DEFAULT VM CPU CORES: ${GN}${DEFAULT_CORES}${CL} (${BASE_CPU_PERCENT}% of CPU CORES)"
echo -e "DEFAULT OS DISK: ${GN}${DEFAULT_OS_DISK_GB}GB${CL}"
echo -e "DEFAULT STORAGE: ${GN}${DEFAULT_STORAGE}${CL} (${SELECTED_STORAGE_TYPE:-unknown})"
echo -e "STORAGE FREE: ${GN}${SELECTED_STORAGE_FREE_GB}GB${CL}"
echo -e "STORAGE MEDIA: SSD=${GN}${STORAGE_IS_SSD}${CL} | NVME=${GN}${STORAGE_IS_NVME}${CL} | ZFS=${GN}${STORAGE_IS_ZFS}${CL} | LVM=${GN}${STORAGE_IS_LVM}${CL} | DIR=${GN}${STORAGE_IS_DIR}${CL}"

if [ -n "$DGPU_LINES" ]; then
    echo -e "DISCRETE GPU: ${GN}DETECTED${CL}"
    echo "$DGPU_LINES"
else
    echo -e "DISCRETE GPU: ${RD}NOT FOUND${CL}"
fi

echo "------------------------------------------------------"

# --- 12. TIMED START ---
# Starts the VM creation flow. Defaults to YES after timer.
yn=$(timed_prompt "Start the Proxmox VM Setup (Y/n)? " "y")
echo ""
[[ "$yn" =~ ^[Nn] ]] && exit

# --- QEMU GUEST AGENT ENABLEMENT ---
# Enables Proxmox-side guest agent integration for IP reporting, clean shutdowns and backups.
msg_info "Enabling QEMU Guest Agent on VM"
qm set "$VMID" --agent enabled=1 &>/dev/null
msg_ok "QEMU GUEST AGENT ENABLED"

# --- 13. VM ID / NAME OPTIONS ---
# Lets user choose VM ID and name with timed defaults.
VMID=$(timed_prompt "Enter VM ID (Default ${VMID_DEFAULT}): " "$VMID_DEFAULT")

if ! is_positive_int "$VMID"; then
    msg_error "VM ID must be a positive number"
fi

if qm status "$VMID" &>/dev/null; then
    msg_error "VM ID $VMID already exists"
fi

VM_NAME=$(timed_prompt "Enter VM Name (Default ${VM_NAME_DEFAULT}): " "$VM_NAME_DEFAULT")

if [ -z "$VM_NAME" ]; then
    VM_NAME="$VM_NAME_DEFAULT"
fi

# --- 14. CPU / RAM OPTIONS ---
# RAM input is in GB to avoid MB confusion. Defaults adapt to host resources.
CPU_INPUT=$(timed_prompt "Enter CPU CORES (Default ${DEFAULT_CORES}): " "$DEFAULT_CORES")

if ! is_positive_int "$CPU_INPUT"; then
    msg_error "CPU CORES must be a positive number"
fi

CPU_INPUT=$(clamp_int "$CPU_INPUT" 1 "$TOTAL_CORES")

RAM_GB_INPUT=$(timed_prompt "Enter RAM in GB (Default ${DEFAULT_RAM_GB}GB): " "$DEFAULT_RAM_GB")

if ! is_positive_int "$RAM_GB_INPUT"; then
    msg_error "RAM must be entered as a positive number in GB"
fi

RAM_GB_INPUT=$(clamp_int "$RAM_GB_INPUT" 1 "$TOTAL_RAM_GB")
RAM_MB=$(( RAM_GB_INPUT * 1024 ))

# --- 15. DISK SIZE OPTIONS ---
# OS disk defaults to 40GB unless host storage is small. Optional DATA disk can be added.
OS_DISK_GB=$(timed_prompt "Enter OS DISK size in GB (Default ${DEFAULT_OS_DISK_GB}GB): " "$DEFAULT_OS_DISK_GB")

if ! is_positive_int "$OS_DISK_GB"; then
    msg_error "OS DISK size must be a positive number in GB"
fi

DATA_DISK_GB=$(timed_prompt "Enter optional DATA DISK size in GB (Default ${BASE_DATA_DISK_GB}GB = none): " "$BASE_DATA_DISK_GB")

if ! [[ "$DATA_DISK_GB" =~ ^[0-9]+$ ]]; then
    msg_error "DATA DISK size must be a number in GB"
fi

# --- 16. STORAGE SELECTION ---
# Lists available VM image storages and defaults to local-lvm, local-zfs, or first active storage.
echo ""
echo -e "${BL}AVAILABLE VM STORAGE:${CL}"

for i in "${!STORAGE_LIST[@]}"; do
    storage_name="${STORAGE_LIST[$i]}"
    storage_type=$(pvesm status | awk -v s="$storage_name" '$1==s{print $2}')
    storage_free=$(pvesm status | awk -v s="$storage_name" '$1==s{printf "%d", $6/1024/1024}')
    echo "$((i+1))) ${storage_name} (${storage_type}, FREE ${storage_free}GB)"
done

DEFAULT_STORAGE_INDEX=1

for i in "${!STORAGE_LIST[@]}"; do
    if [ "${STORAGE_LIST[$i]}" == "$DEFAULT_STORAGE" ]; then
        DEFAULT_STORAGE_INDEX=$((i+1))
        break
    fi
done

STORAGE_IDX=$(timed_prompt "Select STORAGE (Default ${DEFAULT_STORAGE_INDEX}: ${DEFAULT_STORAGE}): " "$DEFAULT_STORAGE_INDEX")

if ! is_positive_int "$STORAGE_IDX"; then
    msg_error "Storage selection must be a number"
fi

if [ "$STORAGE_IDX" -lt 1 ] || [ "$STORAGE_IDX" -gt "${#STORAGE_LIST[@]}" ]; then
    msg_error "Invalid storage selection"
fi

SELECTED_STORAGE="${STORAGE_LIST[$((STORAGE_IDX-1))]}"
SELECTED_STORAGE_TYPE=$(pvesm status | awk -v s="$SELECTED_STORAGE" '$1==s{print $2}')

# --- 17. ISO SELECTION ---
# Finds ISO images in Proxmox ISO storage and lets user select one. Uses ide2 cdrom attachment.
echo ""
echo -e "${BL}SELECT ISO:${CL}"

mapfile -t ISOS < <(pvesm list local --content iso 2>/dev/null | awk 'NR>1 {print $1}' || true)

if [ "${#ISOS[@]}" -eq 0 ]; then
    mapfile -t ISOS < <(find /var/lib/vz/template/iso -maxdepth 1 -type f -iname "*.iso" 2>/dev/null | sed 's|/var/lib/vz/template/iso/|local:iso/|' || true)
fi

if [ "${#ISOS[@]}" -eq 0 ]; then
    msg_warn "No ISO found. VM will be created without ISO attached."
    ISO_PATH=""
else
    for i in "${!ISOS[@]}"; do
        echo "$((i+1))) ${ISOS[$i]}"
    done

    ISO_IDX=$(timed_prompt "Select ISO (Default 1): " "1")

    if ! is_positive_int "$ISO_IDX"; then
        msg_error "ISO selection must be a number"
    fi

    if [ "$ISO_IDX" -lt 1 ] || [ "$ISO_IDX" -gt "${#ISOS[@]}" ]; then
        msg_error "Invalid ISO selection"
    fi

    ISO_PATH="${ISOS[$((ISO_IDX-1))]}"
fi

# --- 18. GPU PASSTHROUGH OPTION ---
# Defaults to YES if a discrete GPU exists. Attaches only the detected discrete GPU, not Intel iGPU.
ENABLE_GPU="n"

if [ -n "$DGPU_BDF" ]; then
    echo ""
    echo -e "${BL}DISCRETE GPU AVAILABLE:${CL}"
    echo "$DGPU_LINES"
    gpu_yn=$(timed_prompt "Add DISCRETE GPU to VM? (Y/n): " "y")
    [[ "$gpu_yn" =~ ^[Yy] ]] && ENABLE_GPU="y"
fi

# --- 19. STORAGE OPTIMIZATION LOGIC ---
# Applies VM disk flags based on detected storage type/media: SSD/NVMe/ZFS/LVM/DIR.
msg_info "Calculating VM storage optimization"

DISCARD_OPT="discard=on"
SSD_OPT=""
IO_THREAD_OPT="iothread=1"
CACHE_OPT="cache=none"
OS_DISK_FORMAT=""
DATA_DISK_FORMAT=""

if [ "$STORAGE_IS_SSD" == "yes" ] || [ "$STORAGE_IS_NVME" == "yes" ]; then
    SSD_OPT=",ssd=1"
fi

if echo "$SELECTED_STORAGE_TYPE" | grep -qi "dir"; then
    OS_DISK_FORMAT=",format=qcow2"
    DATA_DISK_FORMAT=",format=qcow2"
fi

if echo "$SELECTED_STORAGE_TYPE" | grep -qi "zfspool"; then
    STORAGE_IS_ZFS="yes"
    CACHE_OPT="cache=none"
fi

if echo "$SELECTED_STORAGE_TYPE" | grep -qi "lvm"; then
    STORAGE_IS_LVM="yes"
    CACHE_OPT="cache=none"
fi

msg_ok "VM STORAGE OPTIMIZATION READY"

# --- 20. HOST STORAGE OPTIMIZATION LOGIC ---
# Enables fstrim for SSD/NVMe host storage and adds safe sysctl VM tuning for Docker/database workloads.
msg_info "Applying host storage optimization"

if [ "$STORAGE_IS_SSD" == "yes" ] || [ "$STORAGE_IS_NVME" == "yes" ]; then
    systemctl enable --now fstrim.timer &>/dev/null || true
fi

cat <<EOF > /etc/sysctl.d/99-pve-vm-storage-tuning.conf
# VM host storage and memory tuning for Docker/database workloads
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF

sysctl --system &>/dev/null || true

if [ "$STORAGE_IS_ZFS" == "yes" ] && command -v zfs >/dev/null 2>&1; then
    TOTAL_RAM_BYTES=$(free -b | awk '/^Mem:/{print $2}')
    ARC_MAX=$(( TOTAL_RAM_BYTES / 4 ))
    ARC_MIN=$(( TOTAL_RAM_BYTES / 16 ))

    cat <<EOF > /etc/modprobe.d/zfs.conf
# Limit ZFS ARC so VM RAM remains available
options zfs zfs_arc_min=${ARC_MIN}
options zfs zfs_arc_max=${ARC_MAX}
EOF
fi

msg_ok "HOST STORAGE OPTIMIZATION APPLIED"

# --- 21. VM CREATION ---
# Creates the VM using q35, OVMF, VirtIO network, host CPU, fixed RAM, and no ballooning.
msg_info "Creating VM $VMID ($VM_NAME)"

qm create "$VMID" \
    --agent enabled=1
    --name "$VM_NAME" \
    --machine q35 \
    --bios ovmf \
    --ostype l26 \
    --cpu host \
    --cores "$CPU_INPUT" \
    --memory "$RAM_MB" \
    --balloon 0 \
    --agent enabled=1 \
    --net0 virtio,bridge=vmbr0 \
    --scsihw virtio-scsi-single \
    --tablet 0 \
    --onboot 1 &>/dev/null

msg_ok "VM BASE CREATED"

# --- 22. EFI DISK CREATION ---
# Adds EFI disk required by OVMF/UEFI boot.
msg_info "Adding EFI disk"

qm set "$VMID" --efidisk0 "${SELECTED_STORAGE}:0,efitype=4m,pre-enrolled-keys=0" &>/dev/null

msg_ok "EFI DISK ADDED"

# --- 23. OS DISK CREATION ---
# Adds optimized OS disk with discard/TRIM, SSD flag where appropriate, and IO thread.
msg_info "Adding OS DISK"

qm set "$VMID" --scsi0 "${SELECTED_STORAGE}:${OS_DISK_GB}${OS_DISK_FORMAT},${DISCARD_OPT}${SSD_OPT},${IO_THREAD_OPT},${CACHE_OPT}" &>/dev/null

msg_ok "OS DISK ADDED"

# --- 24. OPTIONAL DATA DISK CREATION ---
# Adds a secondary DATA disk only if user entered a size greater than 0GB.
if [ "$DATA_DISK_GB" -gt 0 ]; then
    msg_info "Adding DATA DISK"

    qm set "$VMID" --scsi1 "${SELECTED_STORAGE}:${DATA_DISK_GB}${DATA_DISK_FORMAT},${DISCARD_OPT}${SSD_OPT},${IO_THREAD_OPT},${CACHE_OPT}" &>/dev/null

    msg_ok "DATA DISK ADDED"
fi

# --- 25. ISO / BOOT CONFIGURATION ---
# Attaches selected ISO to ide2 and configures boot order.
if [ -n "$ISO_PATH" ]; then
    msg_info "Attaching ISO"

    qm set "$VMID" --ide2 "$ISO_PATH,media=cdrom" &>/dev/null

    msg_ok "ISO ATTACHED"
fi

msg_info "Configuring boot order"

qm set "$VMID" --boot order="$BOOT_ORDER" &>/dev/null

msg_ok "BOOT ORDER CONFIGURED"

# --- 26. GPU PASSTHROUGH ATTACHMENT ---
# Adds discrete GPU to VM if selected. Uses q35/OVMF compatible PCIe passthrough.
if [ "$ENABLE_GPU" == "y" ]; then
    msg_info "Attaching DISCRETE GPU"

    qm set "$VMID" --hostpci0 "${DGPU_BDF},pcie=1,x-vga=1" &>/dev/null

    msg_ok "GPU PASSTHROUGH ENABLED ($DGPU_BDF)"
fi

# --- 27. VM NOTES ---
# Adds VM notes explaining storage and guest-side optimization recommendations.
msg_info "Adding VM notes"

VM_NOTES="Created by PVE9 VM Setup.

Recommended VM purpose:
Ubuntu Server + Docker + Traefik + Authentik + Postgres + application stack.

Configured:
Machine: q35
BIOS: OVMF / UEFI
CPU Type: host
CPU CORES: ${CPU_INPUT}
RAM: ${RAM_GB_INPUT}GB fixed, ballooning disabled
OS DISK: ${OS_DISK_GB}GB
DATA DISK: ${DATA_DISK_GB}GB
Network: VirtIO
Storage: ${SELECTED_STORAGE}
Storage Type: ${SELECTED_STORAGE_TYPE}
SSD: ${STORAGE_IS_SSD}
NVME: ${STORAGE_IS_NVME}
ZFS: ${STORAGE_IS_ZFS}
LVM: ${STORAGE_IS_LVM}
GPU Passthrough: ${ENABLE_GPU}

Inside Ubuntu VM recommended:
sudo apt update
sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
sudo systemctl enable --now fstrim.timer
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-vm-swappiness.conf
sudo sysctl --system
"

qm set "$VMID" --description "$VM_NOTES" &>/dev/null

msg_ok "VM NOTES ADDED"

# --- 28. FINAL VALIDATION ---
# Checks VM config after creation and prints important summary.
msg_info "Validating VM configuration"

qm config "$VMID" &>/dev/null

msg_ok "VM CONFIG VALIDATED"

# --- 29. FINISH SUMMARY ---
# Shows final VM details and next steps.
echo ""
echo -e "${GN}FINISHED!${CL}"
echo "------------------------------------------------------"
echo -e "VM ID: ${GN}${VMID}${CL}"
echo -e "VM NAME: ${GN}${VM_NAME}${CL}"
echo -e "CPU CORES: ${GN}${CPU_INPUT}${CL}"
echo -e "RAM: ${GN}${RAM_GB_INPUT}GB${CL}"
echo -e "OS DISK: ${GN}${OS_DISK_GB}GB${CL}"
echo -e "DATA DISK: ${GN}${DATA_DISK_GB}GB${CL}"
echo -e "STORAGE: ${GN}${SELECTED_STORAGE}${CL}"
echo -e "STORAGE TYPE: ${GN}${SELECTED_STORAGE_TYPE}${CL}"
echo -e "SSD: ${GN}${STORAGE_IS_SSD}${CL}"
echo -e "NVME: ${GN}${STORAGE_IS_NVME}${CL}"
echo -e "ZFS: ${GN}${STORAGE_IS_ZFS}${CL}"
echo -e "LVM: ${GN}${STORAGE_IS_LVM}${CL}"
echo -e "GPU PASSTHROUGH: ${GN}${ENABLE_GPU}${CL}"
[ -n "$ISO_PATH" ] && echo -e "ISO: ${GN}${ISO_PATH}${CL}"
echo "------------------------------------------------------"
echo -e "${YW}Start the VM from Proxmox Web UI and install Ubuntu.${CL}"
echo -e "${YW}After Ubuntu install, install qemu-guest-agent and enable fstrim.timer inside the VM.${CL}"