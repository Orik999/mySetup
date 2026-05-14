#!/usr/bin/env bash -ex
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  PVE9 New Storage Setup
#  Creates adaptive LVM-Thin storage from a selected disk.
#  Supports SSD/HDD/NVMe/SATA/USB detection, TRIM, scheduler,
#  thinpool reserve logic, metadata sizing, and auto-verification.
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
LOG_FILE="/var/log/pve9-storage-setup.log"
VERIFY_LOG="/var/log/pve9-storage-verify.log"

# --- 2. GLOBAL VARIABLES ---
# Runtime values populated during audit and user input.
PVE_MAJOR=""
ROOT_DISK=""
SELECTED_DISK=""
DISK=""
DISK_SIZE_BYTES=0
DISK_SIZE_GB=0
DISK_MODEL=""
DISK_TRAN=""
DISK_ROTA=""
DISK_TYPE="UNKNOWN"
DISK_MEDIA="UNKNOWN"
DISK_BUS="UNKNOWN"
DISK_HAS_DATA="no"
DISK_HAS_MOUNT="no"
DISK_HAS_LVM="no"
DISK_HAS_ZFS="no"
DISK_HAS_MDRAID="no"
DISK_HAS_SIGNATURES="no"
DISK_FILESYSTEMS=""
DISK_MOUNTPOINTS=""
DISK_PARTITIONS=""
SMART_STATUS="UNKNOWN"

VG_NAME=""
THINPOOL_NAME=""
STORAGE_ID=""
STORAGE_CONTENT=""
DISCARD_FLAG="0"
SAFEREMOVE_FLAG="1"
THINPOOL_PERCENT="95"
METADATA_SIZE="1G"
IO_SCHEDULER=""
ENABLE_TRIM="no"
ENABLE_ZFS_TUNING="no"
ENABLE_SWAPPINESS_TUNING="yes"

# --- 3. HEADER & MESSAGING FUNCTIONS ---
# Shows the New Storage Setup ASCII banner and reusable status output helpers.
function header_info {
echo -e "${BL}
 ███╗   ██╗███████╗██╗    ██╗    ███████╗████████╗ ██████╗ ██████╗  █████╗  ██████╗ ███████╗    ███████╗███████╗████████╗██╗   ██╗██████╗ 
 ████╗  ██║██╔════╝██║    ██║    ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝ ██╔════╝    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
 ██╔██╗ ██║█████╗  ██║ █╗ ██║    ███████╗   ██║   ██║   ██║██████╔╝███████║██║  ███╗█████╗      ███████╗█████╗     ██║   ██║   ██║██████╔╝
 ██║╚██╗██║██╔══╝  ██║███╗██║    ╚════██║   ██║   ██║   ██║██╔══██╗██╔══██║██║   ██║██╔══╝      ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
 ██║ ╚████║███████╗╚███╔███╔╝    ███████║   ██║   ╚██████╔╝██║  ██║██║  ██║╚██████╔╝███████╗    ███████║███████╗   ██║   ╚██████╔╝██║     
 ╚═╝  ╚═══╝╚══════╝ ╚══╝╚══╝     ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝    ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
${CL}"
}

function msg_info() { echo -ne " ${HOLD} ${YW}$1..."; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 4. LOGGING & ERROR HANDLING ---
# Logs all output and prints line number on failure.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 5. ROOT / PROXMOX CHECKS ---
# Ensures script runs as root on a Proxmox host.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

if ! command -v pveversion >/dev/null 2>&1 || ! command -v pvesm >/dev/null 2>&1; then
    echo -e "${RD}This must be run on a Proxmox host.${CL}"
    exit 1
fi

clear
header_info

# --- 6. HELPER FUNCTIONS ---
# Provides timed prompts, safe names, size conversion, and adaptive defaults.
function timed_prompt() {
    local prompt="$1"
    local default="$2"
    local input=""
    read -t "$T" -p "$prompt" input || input="$default"
    [ -z "$input" ] && input="$default"
    echo "$input"
}

function is_positive_int() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]
}

function safe_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'
}

function bytes_to_gb() {
    awk -v bytes="$1" 'BEGIN { printf "%d", bytes / 1024 / 1024 / 1024 }'
}

function detect_root_disk() {
    local root_src root_pk
    root_src=$(findmnt -n -o SOURCE / || true)
    root_pk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n1 || true)
    if [ -n "$root_pk" ]; then
        echo "/dev/$root_pk"
    else
        lsblk -no NAME,MOUNTPOINT | awk '$2=="/"{print "/dev/"$1; exit}'
    fi
}

function storage_exists() {
    local sid="$1"
    pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "$sid"
}

function make_unique_storage_id() {
    local base="$1"
    local candidate="$base"
    local n=2
    while storage_exists "$candidate" || vgs "$candidate" >/dev/null 2>&1; do
        candidate="${base}-${n}"
        n=$((n+1))
    done
    echo "$candidate"
}

function detect_disk_has_data() {
    local disk="$1"
    local result="no"
    if lsblk -nr "$disk" | awk 'NR>1{found=1} END{exit !found}'; then result="yes"; fi
    if wipefs -n "$disk" 2>/dev/null | awk 'NR>1{found=1} END{exit !found}'; then result="yes"; fi
    if blkid "$disk"* >/dev/null 2>&1; then result="yes"; fi
    echo "$result"
}

function detect_disk_mounts() {
    local disk="$1"
    if lsblk -nr -o MOUNTPOINT "$disk" | grep -q "/"; then
        echo "yes"
    else
        echo "no"
    fi
}

function detect_disk_lvm() {
    local disk="$1"
    if pvs --noheadings -o pv_name 2>/dev/null | awk '{print $1}' | grep -q "^${disk}"; then
        echo "yes"
    else
        echo "no"
    fi
}

function detect_disk_zfs() {
    local disk="$1"
    if command -v zpool >/dev/null 2>&1 && zpool status 2>/dev/null | grep -q "$(basename "$disk")"; then
        echo "yes"
    else
        echo "no"
    fi
}

function detect_disk_mdraid() {
    local disk="$1"
    if grep -q "$(basename "$disk")" /proc/mdstat 2>/dev/null; then
        echo "yes"
    else
        echo "no"
    fi
}

function get_smart_status() {
    local disk="$1"
    if command -v smartctl >/dev/null 2>&1; then
        smartctl -H "$disk" 2>/dev/null | awk -F: '/overall-health|SMART Health Status/ {gsub(/^[ \t]+/,"",$2); print $2; found=1} END{if(!found) print "UNKNOWN"}'
    else
        echo "smartctl not installed"
    fi
}

function set_scheduler_rule() {
    local disk_name="$1"
    local scheduler="$2"
    cat <<EOF > "/etc/udev/rules.d/60-${disk_name}-scheduler.rules"
# PVE9 adaptive disk scheduler for ${disk_name}
ACTION=="add|change", KERNEL=="${disk_name}", ATTR{queue/scheduler}="${scheduler}"
EOF
    udevadm control --reload-rules >/dev/null 2>&1 || true
    udevadm trigger "/sys/block/${disk_name}" >/dev/null 2>&1 || true
    if [ -w "/sys/block/${disk_name}/queue/scheduler" ]; then
        echo "$scheduler" > "/sys/block/${disk_name}/queue/scheduler" 2>/dev/null || true
    fi
}

# --- 7. VERSION CHECK ---
# Confirms the host is Proxmox VE 9 or newer.
echo -e "${YW} This script will initialize a selected disk as adaptive LVM-Thin storage. PVE9 ONLY ${CL}"

PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)
[ "$PVE_MAJOR" -lt 9 ] && msg_error "Requires Proxmox 9+"

# --- 8. TIMED START ---
# Starts the script with default YES after timer.
yn=$(timed_prompt "Start the Storage Setup (Y/n)? " "y")
echo ""
[[ "$yn" =~ ^[Nn] ]] && exit

# --- 9. DISK DISCOVERY ---
# Lists physical disks including USB/external disks, excluding the active Proxmox root disk.
msg_info "Discovering physical disks"

ROOT_DISK=$(detect_root_disk)
mapfile -t RAW_DISKS < <(lsblk -bdn -o NAME,SIZE,MODEL,TRAN,ROTA,RM,TYPE | awk '$7=="disk"{print}' || true)

DISKS=()
for line in "${RAW_DISKS[@]}"; do
    name=$(echo "$line" | awk '{print $1}')
    dev="/dev/$name"
    [ "$dev" == "$ROOT_DISK" ] && continue
    DISKS+=("$line")
done

[ "${#DISKS[@]}" -eq 0 ] && msg_error "No selectable secondary disks found"

msg_ok "DISK DISCOVERY COMPLETE"

# --- 10. HUMAN-FRIENDLY DISK AUDIT SCREEN ---
# Shows disk type, size, bus, media, signatures, mounts, LVM/ZFS/RAID usage, and SMART info before selection.
echo ""
echo -e "${BL}AVAILABLE PHYSICAL DISKS:${CL}"
echo "Root disk excluded: ${ROOT_DISK:-unknown}"
echo "------------------------------------------------------"

for i in "${!DISKS[@]}"; do
    line="${DISKS[$i]}"
    name=$(echo "$line" | awk '{print $1}')
    size_bytes=$(echo "$line" | awk '{print $2}')
    rota=$(echo "$line" | awk '{print $(NF-2)}')
    rmdev=$(echo "$line" | awk '{print $(NF-1)}')
    tran=$(echo "$line" | awk '{print $(NF-3)}')
    model=$(echo "$line" | awk '{$1="";$2="";$(NF-3)="";$(NF-2)="";$(NF-1)="";$NF=""; gsub(/^ +| +$/,""); print}')
    dev="/dev/$name"
    size_gb=$(bytes_to_gb "$size_bytes")

    media="HDD"
    [ "$rota" == "0" ] && media="SSD"
    bus="${tran:-unknown}"
    [[ "$name" == nvme* ]] && bus="nvme"
    [ "$rmdev" == "1" ] && bus="${bus}/removable"

    has_data=$(detect_disk_has_data "$dev")
    has_mount=$(detect_disk_mounts "$dev")
    has_lvm=$(detect_disk_lvm "$dev")
    has_zfs=$(detect_disk_zfs "$dev")
    has_mdraid=$(detect_disk_mdraid "$dev")
    fs_list=$(lsblk -nr -o FSTYPE "$dev" | grep -v '^$' | sort -u | paste -sd "," - || true)

    echo "$((i+1))) $dev"
    echo "    SIZE: ${size_gb}GB | MEDIA: ${media} | BUS: ${bus} | MODEL: ${model:-unknown}"
    echo "    DATA: ${has_data} | FS: ${fs_list:-none} | MOUNTED: ${has_mount} | LVM: ${has_lvm} | ZFS: ${has_zfs} | MDRAID: ${has_mdraid}"
done

echo "------------------------------------------------------"

# --- 11. DISK SELECTION ---
# Lets user select a disk by number with timed default.
DISK_IDX=$(timed_prompt "Select DISK [1-${#DISKS[@]}] (Default 1): " "1")

if ! is_positive_int "$DISK_IDX"; then
    msg_error "Disk selection must be a positive number"
fi

if [ "$DISK_IDX" -lt 1 ] || [ "$DISK_IDX" -gt "${#DISKS[@]}" ]; then
    msg_error "Invalid disk selection"
fi

SELECTED_LINE="${DISKS[$((DISK_IDX-1))]}"
SELECTED_DISK=$(echo "$SELECTED_LINE" | awk '{print $1}')
DISK="/dev/$SELECTED_DISK"
[ ! -b "$DISK" ] && msg_error "Invalid disk device"

# --- 12. SELECTED DISK FULL AUDIT ---
# Performs deeper audit of the selected disk before destructive actions.
msg_info "Auditing selected disk"

DISK_SIZE_BYTES=$(lsblk -bdn -o SIZE "$DISK")
DISK_SIZE_GB=$(bytes_to_gb "$DISK_SIZE_BYTES")
DISK_MODEL=$(lsblk -bdn -o MODEL "$DISK" | sed 's/^[ \t]*//;s/[ \t]*$//')
DISK_TRAN=$(lsblk -bdn -o TRAN "$DISK" | xargs || true)
DISK_ROTA=$(lsblk -bdn -o ROTA "$DISK" | xargs || true)

DISK_MEDIA="HDD"
[ "$DISK_ROTA" == "0" ] && DISK_MEDIA="SSD"

DISK_BUS="${DISK_TRAN:-unknown}"
[[ "$SELECTED_DISK" == nvme* ]] && DISK_BUS="nvme"

DISK_HAS_DATA=$(detect_disk_has_data "$DISK")
DISK_HAS_MOUNT=$(detect_disk_mounts "$DISK")
DISK_HAS_LVM=$(detect_disk_lvm "$DISK")
DISK_HAS_ZFS=$(detect_disk_zfs "$DISK")
DISK_HAS_MDRAID=$(detect_disk_mdraid "$DISK")
DISK_FILESYSTEMS=$(lsblk -nr -o FSTYPE "$DISK" | grep -v '^$' | sort -u | paste -sd "," - || true)
DISK_MOUNTPOINTS=$(lsblk -nr -o MOUNTPOINT "$DISK" | grep -v '^$' | paste -sd "," - || true)
DISK_PARTITIONS=$(lsblk -nr -o NAME,SIZE,FSTYPE,MOUNTPOINT "$DISK" | awk 'NR>1{print}' || true)
SMART_STATUS=$(get_smart_status "$DISK")

if [ "$DISK_HAS_MOUNT" == "yes" ]; then
    msg_error "$DISK has mounted partitions. Unmount/remove usage before running this script."
fi

if [ "$DISK_HAS_ZFS" == "yes" ]; then
    msg_error "$DISK appears to be part of a ZFS pool. Refusing to continue."
fi

if [ "$DISK_HAS_MDRAID" == "yes" ]; then
    msg_error "$DISK appears to be part of mdraid. Refusing to continue."
fi

msg_ok "SELECTED DISK AUDIT COMPLETE"

# --- 13. SELECTED DISK AUDIT DISPLAY ---
# Displays detailed selected disk information before any wipe happens.
echo ""
echo -e "${BL}SELECTED DISK AUDIT:${CL}"
echo "DISK: $DISK"
echo "SIZE: ${DISK_SIZE_GB}GB"
echo "MODEL: ${DISK_MODEL:-unknown}"
echo "MEDIA: $DISK_MEDIA"
echo "BUS: $DISK_BUS"
echo "FILESYSTEMS: ${DISK_FILESYSTEMS:-none}"
echo "MOUNTPOINTS: ${DISK_MOUNTPOINTS:-none}"
echo "HAS DATA/SIGNATURES: $DISK_HAS_DATA"
echo "LVM MEMBER: $DISK_HAS_LVM"
echo "ZFS MEMBER: $DISK_HAS_ZFS"
echo "MDRAID MEMBER: $DISK_HAS_MDRAID"
echo "SMART STATUS: $SMART_STATUS"

if [ -n "$DISK_PARTITIONS" ]; then
    echo ""
    echo "PARTITIONS:"
    echo "$DISK_PARTITIONS"
fi

echo "------------------------------------------------------"

# --- 14. DATA WARNING / CONFIRMATION LOGIC ---
# If disk has data, default is NO. If no data, default is YES. Both use 15 second timer.
if [ "$DISK_HAS_DATA" == "yes" ] || [ "$DISK_HAS_LVM" == "yes" ]; then
    echo -e "${RD}WARNING: $DISK contains old data/signatures and will be completely erased.${CL}"
    proceed=$(timed_prompt "Proceed with destructive wipe? (y/N): " "n")
    [[ "$proceed" =~ ^[Yy] ]] || msg_error "Aborted by user or default safety choice"
else
    echo -e "${GN}$DISK appears empty/unused. Storage creation can proceed.${CL}"
    proceed=$(timed_prompt "Proceed with storage creation? (Y/n): " "y")
    [[ "$proceed" =~ ^[Nn] ]] && msg_error "Aborted"
fi

# --- 15. ADAPTIVE STORAGE NAMING ---
# Suggests storage names based on media/bus and lets user customize them.
if [[ "$DISK_BUS" == "nvme" ]]; then
    DEFAULT_BASE_ID="nvme-fast"
elif [ "$DISK_MEDIA" == "SSD" ]; then
    DEFAULT_BASE_ID="ssd-fast"
else
    DEFAULT_BASE_ID="hdd-bulk"
fi

DEFAULT_STORAGE_ID=$(make_unique_storage_id "$DEFAULT_BASE_ID")
STORAGE_ID=$(timed_prompt "Enter Proxmox STORAGE ID (Default ${DEFAULT_STORAGE_ID}): " "$DEFAULT_STORAGE_ID")
STORAGE_ID=$(safe_name "$STORAGE_ID")
[ -z "$STORAGE_ID" ] && STORAGE_ID="$DEFAULT_STORAGE_ID"

if storage_exists "$STORAGE_ID"; then
    msg_error "Proxmox storage ID '$STORAGE_ID' already exists"
fi

VG_NAME="vg_${STORAGE_ID//-/_}"
THINPOOL_NAME="thin_${STORAGE_ID//-/_}"

if vgs "$VG_NAME" >/dev/null 2>&1; then
    msg_error "Volume group '$VG_NAME' already exists"
fi

# --- 16. ADAPTIVE CONTENT SELECTION ---
# Defaults content based on disk type. SSD/NVMe defaults to VM images/rootdir. HDD includes backups/ISO/templates.
if [ "$DISK_MEDIA" == "SSD" ]; then
    DEFAULT_CONTENT="images,rootdir"
else
    DEFAULT_CONTENT="images,rootdir,backup,iso,vztmpl"
fi

echo ""
echo -e "${BL}STORAGE CONTENT OPTIONS:${CL}"
echo "1) VM/LXC only: images,rootdir"
echo "2) Bulk mixed: images,rootdir,backup,iso,vztmpl"
echo "3) Backup/media only: backup,iso,vztmpl"
echo "4) Custom"

if [ "$DEFAULT_CONTENT" == "images,rootdir" ]; then
    DEFAULT_CONTENT_IDX="1"
else
    DEFAULT_CONTENT_IDX="2"
fi

CONTENT_IDX=$(timed_prompt "Select content profile (Default ${DEFAULT_CONTENT_IDX}): " "$DEFAULT_CONTENT_IDX")

case "$CONTENT_IDX" in
    1) STORAGE_CONTENT="images,rootdir" ;;
    2) STORAGE_CONTENT="images,rootdir,backup,iso,vztmpl" ;;
    3) STORAGE_CONTENT="backup,iso,vztmpl" ;;
    4) STORAGE_CONTENT=$(timed_prompt "Enter custom content list: " "$DEFAULT_CONTENT") ;;
    *) STORAGE_CONTENT="$DEFAULT_CONTENT" ;;
esac

# --- 17. ADAPTIVE THINPOOL SIZE / METADATA LOGIC ---
# Leaves free VG space for LVM-thin metadata growth, snapshots, repair operations, and safety.
if [ "$DISK_SIZE_GB" -lt 256 ]; then
    THINPOOL_PERCENT="90"
elif [ "$DISK_SIZE_GB" -lt 1024 ]; then
    THINPOOL_PERCENT="95"
elif [ "$DISK_SIZE_GB" -lt 2048 ]; then
    THINPOOL_PERCENT="95"
else
    THINPOOL_PERCENT="97"
fi

if [ "$DISK_SIZE_GB" -lt 256 ]; then
    METADATA_SIZE="1G"
elif [ "$DISK_SIZE_GB" -lt 1024 ]; then
    METADATA_SIZE="4G"
elif [ "$DISK_SIZE_GB" -lt 2048 ]; then
    METADATA_SIZE="8G"
else
    METADATA_SIZE="16G"
fi

echo ""
echo -e "${BL}ADAPTIVE LVM-THIN PLAN:${CL}"
echo "STORAGE ID: $STORAGE_ID"
echo "VG NAME: $VG_NAME"
echo "THINPOOL: $THINPOOL_NAME"
echo "THINPOOL SIZE: ${THINPOOL_PERCENT}%FREE"
echo "METADATA SIZE: $METADATA_SIZE"
echo "CONTENT: $STORAGE_CONTENT"

# --- 18. TRIM / DISCARD / SCHEDULER / HOST TUNING LOGIC ---
# Applies SSD/NVMe TRIM and scheduler logic, HDD scheduler logic, swappiness, and optional ZFS ARC tuning if ZFS exists.
if [ "$DISK_MEDIA" == "SSD" ]; then
    ENABLE_TRIM="yes"
    DISCARD_FLAG="1"
else
    ENABLE_TRIM="no"
    DISCARD_FLAG="0"
fi

if [[ "$DISK_BUS" == "nvme" ]]; then
    IO_SCHEDULER="none"
elif [ "$DISK_MEDIA" == "SSD" ]; then
    IO_SCHEDULER="mq-deadline"
else
    IO_SCHEDULER="bfq"
fi

if command -v zfs >/dev/null 2>&1 && zpool list >/dev/null 2>&1; then
    ENABLE_ZFS_TUNING="yes"
fi

# --- 19. FINAL DESTRUCTIVE CONFIRMATION ---
# Final safety gate before wiping the selected disk.
echo ""
echo -e "${RD}!!! FINAL WARNING: ALL DATA ON $DISK WILL BE DESTROYED !!!${CL}"
FINAL_CHECK=$(timed_prompt "Type CONFIRM to proceed (Default abort): " "ABORT")
[ "$FINAL_CHECK" != "CONFIRM" ] && msg_error "Aborted"

# --- 20. DISK WIPE / SIGNATURE CLEANUP ---
# Wipes filesystem signatures, GPT/MBR metadata, and stale LVM metadata.
msg_info "Wiping disk signatures"

swapoff --all >/dev/null 2>&1 || true
wipefs -a "$DISK" &>/dev/null || true
sgdisk --zap-all "$DISK" &>/dev/null || true
dd if=/dev/zero of="$DISK" bs=1M count=16 conv=fsync &>/dev/null || true
blockdev --rereadpt "$DISK" >/dev/null 2>&1 || true
partprobe "$DISK" >/dev/null 2>&1 || true

msg_ok "DISK PREPARED"

# --- 21. OPTIMAL LVM-THIN CREATION ---
# Creates aligned PV, VG, thinpool with reserved free space, metadata sizing, and dmeventd monitoring.
msg_info "Creating LVM-Thin infrastructure"

pvcreate -y --force --dataalignment 1m "$DISK" &>/dev/null
vgcreate -y "$VG_NAME" "$DISK" &>/dev/null
lvcreate -y -l "${THINPOOL_PERCENT}%FREE" --poolmetadatasize "$METADATA_SIZE" --thinpool "$THINPOOL_NAME" "$VG_NAME" &>/dev/null
lvchange --monitor y "${VG_NAME}/${THINPOOL_NAME}" &>/dev/null || true

msg_ok "LVM-THIN INFRASTRUCTURE CREATED"

# --- 22. PROXMOX STORAGE REGISTRATION ---
# Registers storage in Proxmox with content profile, safe remove, and discard when SSD/NVMe.
msg_info "Registering storage in Proxmox"

if [ "$DISCARD_FLAG" == "1" ]; then
    pvesm add lvmthin "$STORAGE_ID" --vgname "$VG_NAME" --thinpool "$THINPOOL_NAME" --content "$STORAGE_CONTENT" --saferemove "$SAFEREMOVE_FLAG" --discard 1 &>/dev/null
else
    pvesm add lvmthin "$STORAGE_ID" --vgname "$VG_NAME" --thinpool "$THINPOOL_NAME" --content "$STORAGE_CONTENT" --saferemove "$SAFEREMOVE_FLAG" &>/dev/null
fi

msg_ok "STORAGE '$STORAGE_ID' REGISTERED"

# --- 23. TRIM / IO SCHEDULER / SYSCTL / ZFS TUNING ---
# Enables host TRIM for SSD/NVMe, applies persistent IO scheduler rule, swappiness tuning, and ZFS ARC tuning if needed.
msg_info "Applying host storage optimizations"

if [ "$ENABLE_TRIM" == "yes" ]; then
    systemctl enable --now fstrim.timer &>/dev/null || true
fi

if [ -n "$IO_SCHEDULER" ]; then
    set_scheduler_rule "$SELECTED_DISK" "$IO_SCHEDULER"
fi

if [ "$ENABLE_SWAPPINESS_TUNING" == "yes" ]; then
    cat <<EOF > /etc/sysctl.d/99-pve-storage-tuning.conf
# PVE9 storage tuning
vm.swappiness = 10
vm.vfs_cache_pressure = 50
EOF
    sysctl --system &>/dev/null || true
fi

if [ "$ENABLE_ZFS_TUNING" == "yes" ]; then
    TOTAL_RAM_BYTES=$(free -b | awk '/^Mem:/{print $2}')
    ARC_MAX=$(( TOTAL_RAM_BYTES / 4 ))
    ARC_MIN=$(( TOTAL_RAM_BYTES / 16 ))
    cat <<EOF > /etc/modprobe.d/zfs.conf
# PVE9 adaptive ZFS ARC tuning
options zfs zfs_arc_min=${ARC_MIN}
options zfs zfs_arc_max=${ARC_MAX}
EOF
fi

msg_ok "HOST STORAGE OPTIMIZATIONS APPLIED"

# --- 24. AUTO-VERIFY GHOST SCRIPT (SYSTEMD ONESHOT) ---
# Creates a one-time verifier that runs after reboot/next boot, checks storage health, then deletes itself.
msg_info "Creating Auto-Verify Ghost Script"

cat <<EOF > /root/pve_storage_verify.sh
#!/usr/bin/env bash
set +e

VERIFY_LOG="$VERIFY_LOG"
exec > >(tee -a "\$VERIFY_LOG") 2>&1

GN="\033[32m"
RD="\033[31m"
YW="\033[33m"
BL="\033[36m"
CL="\033[0m"

DISK="$DISK"
SELECTED_DISK="$SELECTED_DISK"
DISK_MEDIA="$DISK_MEDIA"
DISK_BUS="$DISK_BUS"
STORAGE_ID="$STORAGE_ID"
VG_NAME="$VG_NAME"
THINPOOL_NAME="$THINPOOL_NAME"
STORAGE_CONTENT="$STORAGE_CONTENT"
ENABLE_TRIM="$ENABLE_TRIM"
DISCARD_FLAG="$DISCARD_FLAG"
IO_SCHEDULER="$IO_SCHEDULER"
THINPOOL_PERCENT="$THINPOOL_PERCENT"
METADATA_SIZE="$METADATA_SIZE"

PASS() { echo -e "\${GN}✓ PASS\${CL} - \$1"; }
FAIL() { echo -e "\${RD}✗ FAIL\${CL} - \$1"; }
WARN() { echo -e "\${YW}! WARN\${CL} - \$1"; }
INFO() { echo -e "\${BL}- INFO\${CL} - \$1"; }

clear

echo ""
echo -e "\${BL}--- PVE9 STORAGE VERIFICATION REPORT ---\${CL}"
echo "Date: \$(date)"
echo "Host: \$(hostname)"
echo ""

INFO "Disk: \$DISK"
INFO "Media: \$DISK_MEDIA"
INFO "Bus: \$DISK_BUS"
INFO "Storage ID: \$STORAGE_ID"
INFO "VG: \$VG_NAME"
INFO "Thinpool: \$THINPOOL_NAME"
INFO "Thinpool allocation: \$THINPOOL_PERCENT%FREE"
INFO "Metadata size: \$METADATA_SIZE"
INFO "Content: \$STORAGE_CONTENT"
INFO "TRIM selected: \$ENABLE_TRIM"
INFO "Scheduler selected: \$IO_SCHEDULER"

echo ""

if pvesm status | awk '{print \$1}' | grep -qx "\$STORAGE_ID"; then PASS "Proxmox storage registered"; else FAIL "Proxmox storage not registered"; fi
if pvesm status | awk -v s="\$STORAGE_ID" '\$1==s && \$3=="active"{found=1} END{exit !found}'; then PASS "Proxmox storage is active"; else FAIL "Proxmox storage is not active"; fi
if vgs "\$VG_NAME" >/dev/null 2>&1; then PASS "Volume group exists"; else FAIL "Volume group missing"; fi
if lvs "\$VG_NAME/\$THINPOOL_NAME" >/dev/null 2>&1; then PASS "Thinpool exists"; else FAIL "Thinpool missing"; fi
if lvs -o lv_attr --noheadings "\$VG_NAME/\$THINPOOL_NAME" 2>/dev/null | grep -q "t"; then PASS "LV is a thinpool"; else FAIL "LV is not detected as thinpool"; fi
if lvs -o data_percent --noheadings "\$VG_NAME/\$THINPOOL_NAME" 2>/dev/null | grep -Eq "[0-9]"; then PASS "Thinpool data percent readable"; else WARN "Thinpool usage not readable"; fi
if lvs -o metadata_percent --noheadings "\$VG_NAME/\$THINPOOL_NAME" 2>/dev/null | grep -Eq "[0-9]"; then PASS "Thinpool metadata percent readable"; else WARN "Thinpool metadata usage not readable"; fi
if lvs -o seg_monitor --noheadings "\$VG_NAME/\$THINPOOL_NAME" 2>/dev/null | grep -qi "monitored"; then PASS "Thinpool dmeventd monitoring enabled"; else WARN "Thinpool monitoring not reported as enabled"; fi

if [ "\$DISCARD_FLAG" == "1" ]; then
    if grep -A20 "lvmthin: \$STORAGE_ID" /etc/pve/storage.cfg 2>/dev/null | grep -q "discard 1"; then PASS "Discard enabled in Proxmox storage config"; else WARN "Discard not visible in storage config"; fi
else
    INFO "Discard skipped for HDD profile"
fi

if [ "\$ENABLE_TRIM" == "yes" ]; then
    if systemctl is-enabled --quiet fstrim.timer && systemctl is-active --quiet fstrim.timer; then PASS "fstrim.timer enabled and active"; else FAIL "fstrim.timer not enabled/active"; fi
else
    INFO "TRIM skipped for HDD profile"
fi

if [ -n "\$IO_SCHEDULER" ]; then
    if [ -f "/etc/udev/rules.d/60-\${SELECTED_DISK}-scheduler.rules" ]; then PASS "Persistent IO scheduler rule exists"; else WARN "Persistent IO scheduler rule missing"; fi
    if [ -r "/sys/block/\${SELECTED_DISK}/queue/scheduler" ]; then
        current_sched=\$(cat "/sys/block/\${SELECTED_DISK}/queue/scheduler")
        INFO "Current scheduler: \$current_sched"
    else
        WARN "Could not read current scheduler"
    fi
fi

if [ -f /etc/sysctl.d/99-pve-storage-tuning.conf ]; then PASS "Storage sysctl tuning file exists"; else WARN "Storage sysctl tuning file missing"; fi
if sysctl vm.swappiness 2>/dev/null | grep -q "= 10"; then PASS "Swappiness tuned to 10"; else WARN "Swappiness is not 10"; fi

echo ""
echo -e "\${YW}Verification complete. Log saved to \$VERIFY_LOG\${CL}"
echo -e "\${YW}Removing storage ghost verifier and systemd service...\${CL}"

systemctl disable pve-storage-verify.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/pve-storage-verify.service
rm -f /root/pve_storage_verify.sh
systemctl daemon-reload >/dev/null 2>&1 || true

echo -e "\${GN}Storage ghost verifier deleted successfully.\${CL}"
EOF

chmod +x /root/pve_storage_verify.sh

cat <<EOF > /etc/systemd/system/pve-storage-verify.service
[Unit]
Description=PVE9 Storage One-Time Verification
After=multi-user.target pve-cluster.service
Wants=pve-cluster.service

[Service]
Type=oneshot
ExecStart=/root/pve_storage_verify.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pve-storage-verify.service &>/dev/null

msg_ok "AUTO-VERIFY GHOST SCRIPT CREATED"

# --- 25. FINAL SUMMARY ---
# Shows created storage profile and next steps.
echo ""
echo -e "${GN}FINISHED!${CL}"
echo "------------------------------------------------------"
echo -e "DISK: ${GN}${DISK}${CL}"
echo -e "SIZE: ${GN}${DISK_SIZE_GB}GB${CL}"
echo -e "MEDIA: ${GN}${DISK_MEDIA}${CL}"
echo -e "BUS: ${GN}${DISK_BUS}${CL}"
echo -e "STORAGE ID: ${GN}${STORAGE_ID}${CL}"
echo -e "VG NAME: ${GN}${VG_NAME}${CL}"
echo -e "THINPOOL: ${GN}${THINPOOL_NAME}${CL}"
echo -e "THINPOOL SIZE: ${GN}${THINPOOL_PERCENT}%FREE${CL}"
echo -e "METADATA SIZE: ${GN}${METADATA_SIZE}${CL}"
echo -e "CONTENT: ${GN}${STORAGE_CONTENT}${CL}"
echo -e "TRIM: ${GN}${ENABLE_TRIM}${CL}"
echo -e "DISCARD: ${GN}${DISCARD_FLAG}${CL}"
echo -e "IO SCHEDULER: ${GN}${IO_SCHEDULER}${CL}"
echo "------------------------------------------------------"
echo -e "${YW}A one-time systemd verifier has been created and will run on next boot.${CL}"
echo -e "${YW}You can also run it manually now with: /root/pve_storage_verify.sh${CL}"