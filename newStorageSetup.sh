#!/usr/bin/env bash
set -euxo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  New Storage Setup
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
LOG_FILE="/var/log/new-storage-setup.log"
COMPLETED_MARKER="/root/.new-storage-setup-completed"

SELECTED_DISK=""
DISK_TYPE="unknown"
DISK_BUS="unknown"
DISK_SIZE_BYTES="0"
DISK_SIZE_GB="0"
HAS_DATA="no"

VG_NAME_DEFAULT="vg_data"
THINPOOL_NAME_DEFAULT="data-thin"
STORAGE_ID_DEFAULT="data-storage"

VG_NAME=""
THINPOOL_NAME=""
STORAGE_ID=""
CONTENT_TYPES="images,rootdir,backup"
THIN_PERCENT="95"

IS_SSD="no"
IS_NVME="no"
IO_SCHEDULER="none"

# --- 3. HEADER FUNCTION ---
# Displays the one-line New Storage Setup ASCII banner.
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

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent status messages for each code batch.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. LOGGING & ERROR HANDLING ---
# Logs output and reports the exact line if the script fails.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 6. ROOT CHECK ---
# Storage initialization requires root.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

clear
header_info

# --- 7. TTY OUTPUT HELPER ---
# Prints directly to terminal while prompt functions return final answers cleanly.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 8. TTY OUTPUT WITH NEWLINE HELPER ---
# Prints directly to terminal with newline.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 9. YES/NO LABEL HELPER ---
# Converts Y/N input into readable yes/no output.
function yes_no_label() {
    local value="$1"
    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 10. BLOCKING YES/NO HELPER ---
# Used when SPACE pauses a countdown and waits for Y/N/ENTER.
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
# SPACE pauses and waits. Timeout accepts default. Final answer remains visible.
function timed_yes_no() {
    local prompt="$1"
    local default="$2"
    local answer=""
    local key=""
    local default_label="Y/n"
    local final_label=""

    if [[ "$default" =~ ^[Nn]$ ]]; then
        default_label="y/N"
    fi

    for ((i=T; i>0; i--)); do
        tty_print "${BFR}${YW}${prompt} (${default_label}) [${i}s]${CL} "

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

# --- 12. TIMED TEXT INPUT HELPER ---
# Reads normal text with timeout. Empty input or timeout uses default.
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""

    tty_print "${YW}${prompt} [default: ${default}] (${T}s): ${CL}"

    if [ -r /dev/tty ]; then
        IFS= read -r -t "$T" answer < /dev/tty || true
    else
        IFS= read -r -t "$T" answer || true
    fi

    [ -z "$answer" ] && answer="$default"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
    echo "$answer"
}

# --- 13. PROXMOX VALIDATION ---
# Confirms this is Proxmox VE 9+ before touching storage.
if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This system is not Proxmox VE. Script cancelled."
fi

PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)

if ! [[ "$PVE_MAJOR" =~ ^[0-9]+$ ]] || [ "$PVE_MAJOR" -lt 9 ]; then
    msg_error "Requires Proxmox VE 9+."
fi

# --- 14. DEPENDENCY CHECK ---
# Ensures disk and LVM tools are available.
msg_info "Checking required tools"

for cmd in lsblk wipefs sgdisk pvcreate vgcreate lvcreate pvesm lvs vgs pvs; do
    command -v "$cmd" >/dev/null 2>&1 || msg_error "Missing required command: $cmd"
done

msg_ok "REQUIRED TOOLS FOUND"

# --- 15. DISK AUDIT BUILDER ---
# Lists candidate disks excluding obvious boot/root disks and already-mounted devices.
msg_info "Auditing available disks"

mapfile -t DISKS < <(
    lsblk -dn -o NAME,SIZE,MODEL,TYPE,TRAN,ROTA,MOUNTPOINTS |
    awk '$4=="disk" {print}'
)

if [ "${#DISKS[@]}" -eq 0 ]; then
    msg_error "No physical disks found."
fi

msg_ok "DISK AUDIT COMPLETE"

# --- 16. DISK SELECTION SCREEN ---
# Shows human-readable disk list and allows numbered selection.
echo ""
echo -e "${BL}AVAILABLE PHYSICAL DISKS:${CL}"
for i in "${!DISKS[@]}"; do
    name=$(echo "${DISKS[$i]}" | awk '{print $1}')
    size=$(echo "${DISKS[$i]}" | awk '{print $2}')
    model=$(echo "${DISKS[$i]}" | awk '{$1=$2=$3=$4=$5=$6=$7=""; print $0}' | xargs)
    tran=$(echo "${DISKS[$i]}" | awk '{print $5}')
    rota=$(echo "${DISKS[$i]}" | awk '{print $6}')

    if [ "$rota" == "0" ]; then
        dtype="SSD"
    else
        dtype="HDD"
    fi

    echo "$((i+1))) /dev/${name} | ${size} | ${dtype} | BUS=${tran:-unknown} | ${model:-unknown}"
done

DISK_IDX=$(timed_text_input "Select disk number to format" "1")

if ! [[ "$DISK_IDX" =~ ^[0-9]+$ ]] || [ "$DISK_IDX" -lt 1 ] || [ "$DISK_IDX" -gt "${#DISKS[@]}" ]; then
    msg_error "Invalid disk selection."
fi

SELECTED_DISK="/dev/$(echo "${DISKS[$((DISK_IDX-1))]}" | awk '{print $1}')"

if [ ! -b "$SELECTED_DISK" ]; then
    msg_error "Selected disk is not a block device."
fi

# --- 17. SELECTED DISK SMART DETECTION ---
# Detects SSD/HDD, NVMe/SATA/USB, disk size and existing signatures.
msg_info "Inspecting selected disk"

rota=$(lsblk -dn -o ROTA "$SELECTED_DISK" | xargs)
tran=$(lsblk -dn -o TRAN "$SELECTED_DISK" | xargs || true)
DISK_SIZE_BYTES=$(blockdev --getsize64 "$SELECTED_DISK")
DISK_SIZE_GB=$(( DISK_SIZE_BYTES / 1024 / 1024 / 1024 ))

if [ "$rota" == "0" ]; then
    IS_SSD="yes"
    DISK_TYPE="SSD"
else
    IS_SSD="no"
    DISK_TYPE="HDD"
fi

if [[ "$(basename "$SELECTED_DISK")" =~ ^nvme ]]; then
    IS_NVME="yes"
    DISK_BUS="NVME"
elif [ -n "$tran" ]; then
    DISK_BUS="${tran^^}"
else
    DISK_BUS="UNKNOWN"
fi

if wipefs -n "$SELECTED_DISK" 2>/dev/null | grep -q . || lsblk -nr "$SELECTED_DISK" | awk 'NR>1 {found=1} END {exit !found}'; then
    HAS_DATA="yes"
fi

msg_ok "SELECTED DISK INSPECTED"

# --- 18. SELECTED DISK SUMMARY ---
# Shows disk details and warns if data/signatures already exist.
echo ""
echo -e "${BL}SELECTED DISK:${CL} ${GN}${SELECTED_DISK}${CL}"
echo -e "TYPE: ${GN}${DISK_TYPE}${CL}"
echo -e "BUS: ${GN}${DISK_BUS}${CL}"
echo -e "SIZE: ${GN}${DISK_SIZE_GB}GB${CL}"
echo -e "EXISTING DATA/SIGNATURES: ${GN}${HAS_DATA}${CL}"

# --- 19. DATA DESTRUCTION CONFIRMATION ---
# If disk has data, default is NO. If disk looks empty, default is YES.
if [ "$HAS_DATA" == "yes" ]; then
    echo -e "${RD}WARNING: Existing data or filesystem signatures were detected on ${SELECTED_DISK}.${CL}"
    proceed_yn=$(timed_yes_no "Destroy all data on ${SELECTED_DISK} and create Proxmox storage?" "n")
else
    proceed_yn=$(timed_yes_no "Create Proxmox storage on empty disk ${SELECTED_DISK}?" "y")
fi

[[ "$proceed_yn" =~ ^[Nn] ]] && msg_error "Aborted by user."

# --- 20. ADAPTIVE STORAGE NAMING ---
# Generates defaults based on SSD/HDD/NVMe/SATA/USB, while allowing custom names.
if [ "$IS_SSD" == "yes" ]; then
    STORAGE_ID_DEFAULT="data-ssd"
    VG_NAME_DEFAULT="vg_data_ssd"
    THINPOOL_NAME_DEFAULT="data-ssd"
else
    STORAGE_ID_DEFAULT="data-hdd"
    VG_NAME_DEFAULT="vg_data_hdd"
    THINPOOL_NAME_DEFAULT="data-hdd"
fi

if [ "$IS_NVME" == "yes" ]; then
    STORAGE_ID_DEFAULT="data-nvme"
    VG_NAME_DEFAULT="vg_data_nvme"
    THINPOOL_NAME_DEFAULT="data-nvme"
fi

VG_NAME=$(timed_text_input "Enter VG name" "$VG_NAME_DEFAULT")
THINPOOL_NAME=$(timed_text_input "Enter thinpool name" "$THINPOOL_NAME_DEFAULT")
STORAGE_ID=$(timed_text_input "Enter Proxmox storage ID" "$STORAGE_ID_DEFAULT")

# --- 21. STORAGE CONFLICT CHECK ---
# Prevents naming collisions with existing Proxmox storage, VGs or LVs.
msg_info "Checking for storage conflicts"

if pvesm status "$STORAGE_ID" >/dev/null 2>&1; then
    msg_error "Proxmox storage ID ${STORAGE_ID} already exists."
fi

if vgs "$VG_NAME" >/dev/null 2>&1; then
    msg_error "Volume group ${VG_NAME} already exists."
fi

msg_ok "NO STORAGE CONFLICTS FOUND"

# --- 22. THINPOOL ALLOCATION LOGIC ---
# Uses adaptive allocation to leave free VG space for metadata growth and repair.
if [ "$DISK_SIZE_GB" -lt 256 ]; then
    THIN_PERCENT="95"
elif [ "$DISK_SIZE_GB" -lt 1024 ]; then
    THIN_PERCENT="92"
else
    THIN_PERCENT="90"
fi

THIN_PERCENT=$(timed_text_input "Enter thinpool allocation percent" "$THIN_PERCENT")

# --- 23. CONTENT TYPE SELECTION ---
# Sets storage content types. Defaults support VM images, containers and backups.
CONTENT_TYPES=$(timed_text_input "Enter Proxmox content types" "$CONTENT_TYPES")

# --- 24. FINAL CONFIRMATION ---
# Final destructive confirmation before wiping disk.
echo ""
echo -e "${RD}FINAL WARNING: ALL DATA ON ${SELECTED_DISK} WILL BE DESTROYED.${CL}"
echo -e "STORAGE ID: ${GN}${STORAGE_ID}${CL}"
echo -e "VG NAME: ${GN}${VG_NAME}${CL}"
echo -e "THINPOOL: ${GN}${THINPOOL_NAME}${CL}"
echo -e "THIN ALLOCATION: ${GN}${THIN_PERCENT}%FREE${CL}"
echo -e "CONTENT: ${GN}${CONTENT_TYPES}${CL}"

final_yn=$(timed_yes_no "Proceed with disk wipe and storage creation?" "n")
[[ "$final_yn" =~ ^[Nn] ]] && msg_error "Aborted by user."

# --- 25. DISK WIPE ---
# Clears old filesystem, partition and LVM signatures.
msg_info "Wiping disk signatures"

wipefs -a "$SELECTED_DISK" &>/dev/null || true
sgdisk --zap-all "$SELECTED_DISK" &>/dev/null || true

msg_ok "DISK PREPARED"

# --- 26. LVM PHYSICAL VOLUME ---
# Creates an aligned LVM physical volume on the whole disk.
msg_info "Creating LVM physical volume"

pvcreate -y --force "$SELECTED_DISK" &>/dev/null

msg_ok "PHYSICAL VOLUME CREATED"

# --- 27. LVM VOLUME GROUP ---
# Creates dedicated VG for this secondary storage device.
msg_info "Creating LVM volume group"

vgcreate -y "$VG_NAME" "$SELECTED_DISK" &>/dev/null

msg_ok "VOLUME GROUP CREATED"

# --- 28. LVM THINPOOL CREATION ---
# Creates thinpool with adaptive free-space reserve and automatic metadata sizing.
msg_info "Creating LVM thinpool"

lvcreate -y -l "${THIN_PERCENT}%FREE" --thinpool "$THINPOOL_NAME" "$VG_NAME" &>/dev/null
lvchange --monitor y "${VG_NAME}/${THINPOOL_NAME}" &>/dev/null || true

msg_ok "LVM THINPOOL CREATED"

# --- 29. PROXMOX STORAGE REGISTRATION ---
# Registers the thinpool in Proxmox with selected content types and discard support.
msg_info "Registering storage in Proxmox"

pvesm add lvmthin "$STORAGE_ID" \
    --vgname "$VG_NAME" \
    --thinpool "$THINPOOL_NAME" \
    --content "$CONTENT_TYPES" \
    --saferemove 1 \
    &>/dev/null

msg_ok "STORAGE REGISTERED"

# --- 30. SSD TRIM LOGIC ---
# Enables fstrim timer only for SSD/NVMe devices.
if [ "$IS_SSD" == "yes" ]; then
    msg_info "Enabling SSD TRIM"

    systemctl enable --now fstrim.timer &>/dev/null

    msg_ok "SSD TRIM ENABLED"
fi

# --- 31. IO SCHEDULER LOGIC ---
# Applies mq-deadline for SSD/NVMe and none/noop fallback where appropriate.
msg_info "Applying IO scheduler tuning"

dev_name="$(basename "$SELECTED_DISK")"

if [ -e "/sys/block/${dev_name}/queue/scheduler" ]; then
    if grep -q "mq-deadline" "/sys/block/${dev_name}/queue/scheduler"; then
        echo "mq-deadline" > "/sys/block/${dev_name}/queue/scheduler" 2>/dev/null || true
        IO_SCHEDULER="mq-deadline"
    elif grep -q "none" "/sys/block/${dev_name}/queue/scheduler"; then
        echo "none" > "/sys/block/${dev_name}/queue/scheduler" 2>/dev/null || true
        IO_SCHEDULER="none"
    fi
fi

cat <<EOF > /etc/systemd/system/storage-${STORAGE_ID}-scheduler.service
[Unit]
Description=Apply IO Scheduler for ${STORAGE_ID}
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '[ -e /sys/block/${dev_name}/queue/scheduler ] && grep -q "${IO_SCHEDULER}" /sys/block/${dev_name}/queue/scheduler && echo "${IO_SCHEDULER}" > /sys/block/${dev_name}/queue/scheduler || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload &>/dev/null
systemctl enable "storage-${STORAGE_ID}-scheduler.service" &>/dev/null

msg_ok "IO SCHEDULER TUNED (${IO_SCHEDULER})"

# --- 32. SWAPPINESS AND ZFS ARC TUNING ---
# Adds safe host-level memory defaults useful for VM/database workloads.
msg_info "Applying memory tuning"

cat <<EOF > /etc/sysctl.d/98-storage-memory-tuning.conf
vm.swappiness = 10
vm.vfs_cache_pressure = 100
EOF

if [ -f /sys/module/zfs/parameters/zfs_arc_max ]; then
    TOTAL_MEM_BYTES=$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)
    ARC_MAX=$(( TOTAL_MEM_BYTES / 4 ))

    cat <<EOF > /etc/modprobe.d/zfs-arc.conf
options zfs zfs_arc_max=${ARC_MAX}
EOF
fi

sysctl --system &>/dev/null || true

msg_ok "MEMORY TUNING APPLIED"

# --- 33. AUTO VERIFY SCRIPT ---
# Creates a one-time verification script and runs it immediately.
msg_info "Creating verification report"

VERIFY_FILE="/var/log/new-storage-setup-verify.log"

cat <<EOF > /root/new_storage_verify.sh
#!/usr/bin/env bash
set +e
exec > >(tee -a "$VERIFY_FILE") 2>&1

echo "--- NEW STORAGE SETUP VERIFICATION REPORT ---"
echo "Date: \$(date)"
echo "Disk: ${SELECTED_DISK}"
echo "Storage ID: ${STORAGE_ID}"
echo ""

if pvesm status "${STORAGE_ID}" >/dev/null 2>&1; then echo "✓ PASS - Proxmox storage exists"; else echo "✗ FAIL - Proxmox storage missing"; fi
if vgs "${VG_NAME}" >/dev/null 2>&1; then echo "✓ PASS - VG exists"; else echo "✗ FAIL - VG missing"; fi
if lvs "${VG_NAME}/${THINPOOL_NAME}" >/dev/null 2>&1; then echo "✓ PASS - Thinpool exists"; else echo "✗ FAIL - Thinpool missing"; fi
if lvs -o lv_monitor --noheadings "${VG_NAME}/${THINPOOL_NAME}" 2>/dev/null | grep -q monitored; then echo "✓ PASS - Thinpool monitoring enabled"; else echo "! WARN - Thinpool monitoring not confirmed"; fi
if [ "${IS_SSD}" == "yes" ]; then systemctl is-active --quiet fstrim.timer && echo "✓ PASS - SSD TRIM active" || echo "✗ FAIL - SSD TRIM inactive"; fi

echo ""
echo "Verification complete."
rm -f /root/new_storage_verify.sh
EOF

chmod +x /root/new_storage_verify.sh
/root/new_storage_verify.sh &>/dev/null || true

msg_ok "VERIFICATION REPORT CREATED"

# --- 34. COMPLETION MARKER ---
# Creates marker so later reruns can detect previous setup.
cat <<EOF > "$COMPLETED_MARKER"
New Storage Setup completed on: $(date)
Disk: $SELECTED_DISK
Storage ID: $STORAGE_ID
VG: $VG_NAME
Thinpool: $THINPOOL_NAME
EOF

# --- 35. FINAL SUMMARY ---
# Shows final storage details.
echo ""
echo -e "${GN}FINISHED!${CL}"
echo -e "DISK: ${GN}${SELECTED_DISK}${CL}"
echo -e "TYPE: ${GN}${DISK_TYPE}${CL}"
echo -e "BUS: ${GN}${DISK_BUS}${CL}"
echo -e "PROXMOX STORAGE ID: ${GN}${STORAGE_ID}${CL}"
echo -e "VG: ${GN}${VG_NAME}${CL}"
echo -e "THINPOOL: ${GN}${THINPOOL_NAME}${CL}"
echo -e "THIN ALLOCATION: ${GN}${THIN_PERCENT}%FREE${CL}"
echo -e "VERIFY LOG: ${GN}${VERIFY_FILE}${CL}"
echo ""

exit 0