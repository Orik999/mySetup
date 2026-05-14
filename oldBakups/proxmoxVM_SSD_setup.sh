#!/usr/bin/env bash -ex
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# --- COLOR VARIABLES ---
YW=`echo "\033[33m"`
BL=`echo "\033[36m"`
RD=`echo "\033[01;31m"`
GN=`echo "\033[1;92m"`
DGN=`echo "\033[32m"`
CL=`echo "\033[m"`
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# --- SYSTEM AUDIT ---
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
TOTAL_CORES=$(nproc)
GPU_FOUND=$(lspci | grep -Ei "vga|3d" | grep -Ei "nvidia|amd|ati" | head -n 1 || true)
T=15 # Global Timer

# Adaptive Defaults (75% RAM, 50% CPU CORES)
DEFAULT_RAM_GB=$(( TOTAL_RAM_GB * 75 / 100 ))
[ "$DEFAULT_RAM_GB" -lt 1 ] && DEFAULT_RAM_GB=1
DEFAULT_CORES=$(( TOTAL_CORES / 2 ))
[ "$DEFAULT_CORES" -lt 1 ] && DEFAULT_CORES=1

function header_info {
echo -e "${BL}
███████╗███████╗██████╗      ███████╗███████╗████████╗██╗   ██╗██████╗ 
██╔════╝██╔════╝██╔══██╗     ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
███████╗███████╗██║  ██║     ███████╗█████╗     ██║   ██║   ██║██████╔╝
╚════██║╚════██║██║  ██║     ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
███████║███████║██████╔╝     ███████║███████╗   ██║   ╚██████╔╝██║     
╚══════╝╚══════╝╚═════╝      ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
${CL}"
}

function msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

clear
header_info

# --- TIMED START ---
echo -e "${YW}PROXMOX 9 STORAGE & VM PROVISIONING${CL}"
read -t $T -p "Start the SSD Storage Initialization (Y/n)? " yn || yn="y"
echo ""
[[ "$yn" =~ ^[Nn] ]] && exit

# Check Version
PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)
[ "$PVE_MAJOR" -lt 9 ] && msg_error "Requires Proxmox 9+"

# --- CLEAN DISK SELECTION ---
echo -e "${BL}SELECT TARGET DISK:${CL}"
mapfile -t DISKS < <(lsblk -dno NAME,SIZE,MODEL | grep -v "boot" | grep -v "pve")
for i in "${!DISKS[@]}"; do
    echo -e "$((i+1))) ${DISKS[$i]}"
done

read -t $T -p "Select Disk [1-${#DISKS[@]}] (Default 1): " DISK_IDX || DISK_IDX=1
SELECTED_DISK=$(echo "${DISKS[$((DISK_IDX-1))]}" | awk '{print $1}')
DISK="/dev/$SELECTED_DISK"
[ ! -b "$DISK" ] && msg_error "Invalid Selection"

# Background SSD/TRIM Audit
IS_SSD=$(lsblk -dno ROTA "$DISK" | xargs)
TRIM_SETTING=$([ "$IS_SSD" -eq 0 ] && echo "on" || echo "off")

# --- VM CONFIGURATION ---
echo -e "\n${BL}VM SETTINGS (Defaults adjust to system size):${CL}"
read -t $T -p "VM ID (Default 100): " VMID || VMID="100"
read -t $T -p "CPU CORES (Default $DEFAULT_CORES): " CPU_INPUT || CPU_INPUT=$DEFAULT_CORES
read -t $T -p "RAM GB (Default $DEFAULT_RAM_GB): " RAM_GB_INPUT || RAM_GB_INPUT=$DEFAULT_RAM_GB
RAM_MB=$(( RAM_GB_INPUT * 1024 ))

# --- ISO SELECTION ---
echo -e "\n${BL}SELECT ISO:${CL}"
mapfile -t ISOS < <(pveam list local | grep ".iso" | awk '{print $2}')
if [ ${#ISOS[@]} -eq 0 ]; then
    ISO_PATH=""
    echo "No ISOs found."
else
    for i in "${!ISOS[@]}"; do echo -e "$((i+1))) ${ISOS[$i]}"; done
    read -t $T -p "Select ISO [1-${#ISOS[@]}] (Default 1): " ISO_IDX || ISO_IDX=1
    ISO_PATH="local:iso/$(basename "${ISOS[$((ISO_IDX-1))]}")"
fi

# --- GPU & STORAGE SIZING ---
ENABLE_GPU="n"
if [ -n "$GPU_FOUND" ]; then
    read -t $T -p "GPU Detected. Enable Passthrough? (Y/n): " gpu_yn || gpu_yn="y"
    [[ "$gpu_yn" =~ ^[Yy] ]] && ENABLE_GPU="y"
fi

read -t $T -p "OS DISK SIZE GB (Default 40): " OS_SIZE || OS_SIZE="40"
read -t $T -p "DATA DISK SIZE GB (Default 180): " DATA_SIZE || DATA_SIZE="180"

# Final Wipe Warning
echo -e "\n${RD}!!! WARNING: $DISK WILL BE WIPED !!!${CL}"
read -t $T -p "Type 'CONFIRM' to proceed: " FINAL_CHECK || FINAL_CHECK="CONFIRM"
[ "$FINAL_CHECK" != "CONFIRM" ] && msg_error "Aborted"

# --- EXECUTION ---
VG_NAME="vg_data_ssd"
THINPOOL_NAME="data-ssd"
STORAGE_ID="data-ssd"

msg_info "Initializing STORAGE"
wipefs -a "$DISK" &>/dev/null
sgdisk --zap-all "$DISK" &>/dev/null
pvcreate -y --force "$DISK" &>/dev/null
vgcreate -y "$VG_NAME" "$DISK" &>/dev/null
lvcreate -y -l 100%FREE --thinpool "$THINPOOL_NAME" "$VG_NAME" &>/dev/null
pvesm add lvmthin "$STORAGE_ID" --vgname "$VG_NAME" --thinpool "$THINPOOL_NAME" --content rootdir,images &>/dev/null
msg_ok "STORAGE READY"

msg_info "Creating VM $VMID"
qm create "$VMID" --name "ct-crea" --machine q35 --bios ovmf --ostype l26 \
    --cpu host --cores "$CPU_INPUT" --memory "$RAM_MB" --balloon 0 \
    --net0 virtio,bridge=vmbr0 &>/dev/null

# Storage Fallback
EFI_STORAGE="local-lvm"; pvesm status "$EFI_STORAGE" &>/dev/null || EFI_STORAGE="local"
qm set "$VMID" --efidisk0 "${EFI_STORAGE}:0,format=qcow2" &>/dev/null
qm set "$VMID" --scsi0 "${EFI_STORAGE}:${OS_SIZE},discard=on" &>/dev/null
qm set "$VMID" --virtio0 "${STORAGE_ID}:${DATA_SIZE},discard=${TRIM_SETTING}" &>/dev/null

[ -n "$ISO_PATH" ] && qm set "$VMID" --cdrom "$ISO_PATH" &>/dev/null
qm set "$VMID" --boot order=scsi0;cdrom &>/dev/null
msg_ok "VM $VMID CONFIGURED"

if [ "$ENABLE_GPU" == "y" ]; then
    msg_info "Mapping GPU"
    GPU_PCI_ID=$(lspci -nn | grep -Ei "vga|3d" | grep -Ei "nvidia|amd|ati" | awk '{print $1}' | head -n 1)
    qm set "$VMID" --hostpci0 "${GPU_PCI_ID},x-vga=on,pcie=1" &>/dev/null
    msg_ok "GPU ATTACHED"
fi

echo -e "\n${GN}FINISHED! DISK: $SELECTED_DISK | RAM: ${RAM_GB_INPUT}GB | CPU: $CPU_INPUT | SSD TRIM: ${TRIM_SETTING^^}${CL}"