#!/usr/bin/env bash
set -Eeuo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  PVE9 Post Install
#  Fresh Proxmox VE 9 post-install automation
# =========================================================

# --- 1. COLOR VARIABLES AND GLOBAL DEFAULTS ---
# Defines terminal colours, status symbols, timers, logs, and install-state variables.
YW=$'\033[33m'
BL=$'\033[36m'
RD=$'\033[01;31m'
BGN=$'\033[4;92m'
GN=$'\033[1;92m'
DGN=$'\033[32m'
CL=$'\033[m'
BFR=$'\r\033[K'
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
FLASH_ON=$'\033[5m'
FLASH_OFF=$'\033[25m'

T=15
LOG_FILE="/var/log/pve9-postinstall.log"
VERIFY_LOG="/var/log/pve9-postinstall-verify.log"

HOSTNAME_SHORT="$(hostname -s)"
SYSTEM_TYPE="Unknown"
CHASSIS="Unknown"
IS_VM="no"
IS_SSD="no"
IS_FRESH="yes"

CPU_TYPE=""
IOMMU_FLAG=""

DEFAULT_IFACE=""
LAN_CIDR=""
REALTEK_IFACE=""
REALTEK_OPTIMIZED="no"

GPU_ALL=""
IGPU_LINES=""
DGPU_LINES=""
GPU_DETAILS_ONE_LINE="unknown"
IGPU_FOUND="no"
DGPU_FOUND="no"
DGPU_IDS=""
DGPU_BDFS=""
GPU_DETECTION_MESSAGE=""
ENABLE_PASSTHROUGH="n"

STORAGE_DETAILS="unknown"
STORAGE_TYPE_SUMMARY="unknown"

ENABLE_PERFORMANCE="n"
ENABLE_CROWDSEC="y"
SSH_HARDENING_APPLIED="no"
PVE_FIREWALL_APPLIED="no"
CROWDSEC_BOUNCER_PACKAGE="none"

# --- 2. HEADER AND MESSAGE HELPERS ---
# Shows the PVE9 Post Install ASCII banner and provides reusable status helpers.
function header_info() {
cat <<'EOF'
[01;31m
██████╗ ██╗   ██╗███████╗ █████╗     ██████╗  ██████╗ ███████╗████████╗    ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     
██╔══██╗██║   ██║██╔════╝██╔══██╗    ██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     
██████╔╝██║   ██║█████╗  ╚██████║    ██████╔╝██║   ██║███████╗   ██║       ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     
██╔═══╝ ╚██╗ ██╔╝██╔══╝   ╚═══██║    ██╔═══╝ ██║   ██║╚════██║   ██║       ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     
██║      ╚████╔╝ ███████╗ █████╔╝    ██║     ╚██████╔╝███████║   ██║       ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
╚═╝       ╚═══╝  ╚══════╝ ╚════╝     ╚═╝      ╚═════╝ ╚══════╝   ╚═╝       ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
[m
EOF
}

function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }
function flash_yellow() { echo -e "${FLASH_ON}${YW}$1${FLASH_OFF}${CL}"; }
function flash_red() { echo -e "${FLASH_ON}${RD}$1${FLASH_OFF}${CL}"; }

# --- 3. LOGGING AND ERROR HANDLING ---
# Logs all output and reports line number on failure.
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 4. ROOT CHECK ---
# Ensures the script runs as root.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

clear
header_info

# --- 5. GENERAL HELPER FUNCTIONS ---
# Reusable helpers for config edits, countdown prompts, GRUB args, storage/GPU formatting, and NIC detection.
function set_or_append_space_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    touch "$file"
    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$file"; then
        sed -i -E "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
    else
        echo "${key} ${value}" >> "$file"
    fi
}

function set_or_append_equals_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    touch "$file"
    if grep -Eq "^[#[:space:]]*${key}=.*" "$file"; then
        sed -i -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

function append_grub_arg() {
    local arg="$1"
    local grub_file="/etc/default/grub"
    grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> "$grub_file"
    if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" | grep -qw "$arg"; then
        sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 ${arg}\"|" "$grub_file"
    fi
}

function prompt_countdown() {
    local prompt="$1"
    local default_answer="$2"
    local seconds="${3:-$T}"
    local answer=""
    local key=""
    local remaining="$seconds"

    while [ "$remaining" -gt 0 ]; do
        printf "\r\033[K${YW}%s [%ss]${CL} " "$prompt" "$remaining" >/dev/tty
        if IFS= read -rsn1 -t 1 key </dev/tty; then
            case "$key" in
                "")
                    answer="$default_answer"
                    break
                    ;;
                $'\177'|$'\010')
                    answer=""
                    ;;
                *)
                    answer+="$key"
                    printf "%s" "$key" >/dev/tty
                    while IFS= read -rsn1 -t 0.05 key </dev/tty; do
                        [ -z "$key" ] && break
                        answer+="$key"
                        printf "%s" "$key" >/dev/tty
                    done
                    break
                    ;;
            esac
        fi
        remaining=$((remaining - 1))
    done

    if [ -z "$answer" ]; then
        answer="$default_answer"
    fi

    printf "\r\033[K" >/dev/tty
    echo "$answer"
}

function countdown_exit() {
    local seconds="$1"
    local reason="$2"
    echo ""
    echo -e "${RD}${reason}${CL}"
    echo -e "${YW}Exiting in ${seconds} seconds...${CL}"
    sleep "$seconds"
    exit 1
}

function clear_lines() {
    local lines="$1"
    local i
    for ((i=0; i<lines; i++)); do
        printf "\033[1A\r\033[K" >/dev/tty || true
    done
}

function detect_realtek_iface() {
    local iface iface_name
    for iface in /sys/class/net/*; do
        iface_name="$(basename "$iface")"
        [ "$iface_name" = "lo" ] && continue
        if ethtool -i "$iface_name" 2>/dev/null | grep -qiE "driver: r8169|driver: r8168|driver: r8125|driver: r8126"; then
            echo "$iface_name"
            return 0
        fi
    done
    return 1
}

function detect_storage_summary() {
    local line name rota type model item details=""
    while read -r name rota type model; do
        [ -z "$name" ] && continue
        [[ "$type" != "disk" ]] && continue
        if [ "$rota" = "0" ]; then
            item="ssd(${name})"
        elif [ "$rota" = "1" ]; then
            item="hdd(${name})"
        else
            item="disk(${name})"
        fi
        details+="${item} "
    done < <(lsblk -dn -o NAME,ROTA,TYPE,MODEL 2>/dev/null || true)

    details="${details%% }"
    echo "${details:-unknown}"
}

function enable_numlock_now_and_at_boot() {
    apt-get install -y numlockx kbd >/dev/null 2>&1 || true

    if command -v setleds >/dev/null 2>&1; then
        for tty in /dev/tty[1-6]; do
            setleds -D +num < "$tty" >/dev/null 2>&1 || true
        done
    fi

    if command -v numlockx >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
        numlockx on >/dev/null 2>&1 || true
    fi

    cat <<'EOF' > /usr/local/sbin/pve-enable-numlock.sh
#!/usr/bin/env bash
set +e
if command -v setleds >/dev/null 2>&1; then
    for tty in /dev/tty[1-6]; do
        setleds -D +num < "$tty" >/dev/null 2>&1 || true
    done
fi
if command -v numlockx >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    numlockx on >/dev/null 2>&1 || true
fi
exit 0
EOF
    chmod +x /usr/local/sbin/pve-enable-numlock.sh

    cat <<'EOF' > /etc/systemd/system/pve-enable-numlock.service
[Unit]
Description=Enable NumLock on boot
After=multi-user.target getty.target display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-enable-numlock.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable pve-enable-numlock.service >/dev/null 2>&1 || true
}

# --- 6. INTRODUCTION AND FRESH INSTALL WARNING ---
# Prints the initial purpose statement and flashing fresh-install warning.
echo -e "${YW} This script will Perform PVE9 Post Install Routines.${CL}"
flash_yellow " Intended for FRESH Proxmox VE 9 installs only."
echo ""

# --- 7. PRE-INSTALL AUDIT ---
# Checks Proxmox version and detects CPU, chassis, VM state, SSD state, network, GPU, and storage before the final start prompt.
msg_info "Running pre-install hardware and system audit"

PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)
[ "$PVE_MAJOR" -lt 9 ] && msg_error "Requires Proxmox 9+"

CPU_TYPE=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
if [ "$CPU_TYPE" = "GenuineIntel" ]; then
    IOMMU_FLAG="intel_iommu=on"
else
    IOMMU_FLAG="amd_iommu=on"
fi

if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet; then
    IS_VM="yes"
fi

if command -v dmidecode >/dev/null 2>&1; then
    CHASSIS=$(dmidecode -s chassis-type 2>/dev/null || echo "Unknown")
fi

if [[ "$CHASSIS" =~ (Laptop|Notebook|Portable) ]]; then
    SYSTEM_TYPE="Laptop"
elif [ "$IS_VM" = "yes" ]; then
    SYSTEM_TYPE="Virtual Machine"
else
    SYSTEM_TYPE="PC/Workstation"
fi

if lsblk -dn -o ROTA | grep -q "^0$"; then
    IS_SSD="yes"
fi

DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || true)
if [ -n "$DEFAULT_IFACE" ]; then
    LAN_CIDR=$(ip -o -4 addr show dev "$DEFAULT_IFACE" | awk '{print $4; exit}' || true)
fi

STORAGE_DETAILS=$(detect_storage_summary)
if echo "$STORAGE_DETAILS" | grep -q "ssd" && echo "$STORAGE_DETAILS" | grep -q "hdd"; then
    STORAGE_TYPE_SUMMARY="mixed SSD/HDD storage"
elif echo "$STORAGE_DETAILS" | grep -q "ssd"; then
    STORAGE_TYPE_SUMMARY="SSD storage"
elif echo "$STORAGE_DETAILS" | grep -q "hdd"; then
    STORAGE_TYPE_SUMMARY="HDD storage"
else
    STORAGE_TYPE_SUMMARY="storage"
fi

msg_ok "PRE-INSTALL AUDIT COMPLETE"

# --- 8. FRESH INSTALL DETECTION ---
# Detects existing VMs, containers, and additional bridges. If found, warns and exits.
msg_info "Checking for fresh install state"

VM_COUNT=$(qm list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')
CT_COUNT=$(pct list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')
CUSTOM_BRIDGES=$(grep -Ec "^auto vmbr[1-9]" /etc/network/interfaces 2>/dev/null || true)

if [ "$VM_COUNT" -gt 0 ] || [ "$CT_COUNT" -gt 0 ] || [ "$CUSTOM_BRIDGES" -gt 0 ]; then
    IS_FRESH="no"
fi

if [ "$IS_FRESH" = "no" ]; then
    echo ""
    echo -e "${RD}WARNING: This does not look like a fresh install.${CL}"
    echo -e "${YW}Detected VMs: ${VM_COUNT}, LXCs: ${CT_COUNT}, extra bridges: ${CUSTOM_BRIDGES}.${CL}"
    countdown_exit 30 "For safety this script will not continue on a non-fresh-looking node."
fi

msg_ok "FRESH INSTALL CHECK PASSED"

# --- 9. GPU DETECTION AND GPU PASSTHROUGH PROMPT ---
# Detects integrated/discrete GPUs immediately after fresh-install check and asks whether to isolate only the discrete GPU.
msg_info "Detecting integrated and discrete GPUs"

GPU_ALL=$(lspci -Dnn | grep -Ei "VGA compatible controller|3D controller|Display controller" || true)
IGPU_LINES=$(echo "$GPU_ALL" | grep -Ei "Intel|Integrated|UHD|Iris" || true)
DGPU_LINES=$(echo "$GPU_ALL" | grep -Eiv "Intel|Integrated|UHD|Iris" | grep -Ei "NVIDIA|AMD|ATI|Radeon|GeForce|RTX|GTX|Quadro|Tesla|FirePro|Arc" || true)
GPU_DETAILS_ONE_LINE=$(echo "$GPU_ALL" | sed 's/^[[:space:]]*//' | paste -sd ' | ' -)
GPU_DETAILS_ONE_LINE="${GPU_DETAILS_ONE_LINE:-unknown}"

[ -n "$IGPU_LINES" ] && IGPU_FOUND="yes"
[ -n "$DGPU_LINES" ] && DGPU_FOUND="yes"

if [ "$DGPU_FOUND" = "yes" ]; then
    while read -r gpu_line; do
        [ -z "$gpu_line" ] && continue
        gpu_bdf=$(echo "$gpu_line" | awk '{print $1}')
        gpu_slot="${gpu_bdf%.*}"
        DGPU_BDFS+="${gpu_bdf} "
        while read -r func_line; do
            [ -z "$func_line" ] && continue
            id=$(echo "$func_line" | grep -Po '\[\K[0-9a-fA-F]{4}:[0-9a-fA-F]{4}' | tail -n1 || true)
            [ -n "$id" ] && DGPU_IDS+="${id},"
        done < <(lspci -Dnn -s "$gpu_slot" || true)
    done <<< "$DGPU_LINES"
    DGPU_IDS="${DGPU_IDS%,}"
fi

if [ "$SYSTEM_TYPE" = "Laptop" ] && [ "$IGPU_FOUND" = "yes" ] && [ "$DGPU_FOUND" = "yes" ]; then
    GPU_DETECTION_MESSAGE="detected laptop with integrated + discrete gpu."
elif [ "$SYSTEM_TYPE" = "Laptop" ] && [ "$DGPU_FOUND" = "yes" ]; then
    GPU_DETECTION_MESSAGE="detected laptop with discrete gpu; integrated gpu not clearly detected."
elif [ "$DGPU_FOUND" = "yes" ]; then
    GPU_DETECTION_MESSAGE="detected ${SYSTEM_TYPE,,} with discrete gpu."
else
    GPU_DETECTION_MESSAGE="detected ${SYSTEM_TYPE,,}; no discrete gpu detected."
fi

msg_ok "$GPU_DETECTION_MESSAGE"
echo -e "${BL}━━━━━━▶${CL} ${GPU_DETAILS_ONE_LINE}"

if [ "$DGPU_FOUND" = "yes" ]; then
    if [ "$SYSTEM_TYPE" = "Laptop" ] && [ "$IGPU_FOUND" = "yes" ]; then
        echo -e "${YW}Integrated GPU will be kept for laptop screen. Only discrete GPU and same-slot function devices will be isolated.${CL}"
    elif [ "$SYSTEM_TYPE" = "Laptop" ]; then
        echo -e "${RD}WARNING:${CL} Laptop detected but integrated GPU was not clearly detected. Passthrough may affect display output."
    else
        echo -e "${YW}Only discrete GPU and same-slot function devices will be isolated.${CL}"
    fi

    gpu_yn=$(prompt_countdown "Isolate discrete GPU for VM passthrough? (Y/n):" "y" "$T")
    [[ "$gpu_yn" =~ ^[Yy]$|^$ ]] && ENABLE_PASSTHROUGH="y"

    if [ "$ENABLE_PASSTHROUGH" = "y" ]; then
        msg_ok "Discrete GPU passthrough activated; integrated GPU untouched"
    else
        msg_warn "Discrete GPU passthrough skipped; integrated GPU untouched"
    fi
else
    msg_warn "No discrete GPU detected. GPU passthrough will be skipped."
fi

# --- 10. STORAGE DETECTION DISPLAY ---
# Displays detected storage type and disk summary before the final start prompt.
msg_ok "detected ${STORAGE_TYPE_SUMMARY}"
echo -e "${BL}━━━━━━▶${CL} ${STORAGE_DETAILS}"

# --- 11. USER OPTIONS BEFORE START ---
# Displays system summary, flashes SSH lockdown warning, auto-detects SSH keys, and asks remaining timed options before the final start prompt.
echo -e "\n${BL}Detected system type:${CL} $SYSTEM_TYPE"
echo -e "${BL}Default network:${CL} ${DEFAULT_IFACE:-unknown} / ${LAN_CIDR:-unknown}"
echo -e "${BL}SSD detected:${CL} $IS_SSD"

echo ""
flash_red "!!! SSH LOCKDOWN WARNING !!!"
echo -e "${YW}Checking for SSH authorized keys. Root password login will only be disabled when keys exist.${CL}"

ROOT_KEYS="/root/.ssh/authorized_keys"
if [ -s "$ROOT_KEYS" ]; then
    echo -e "${GN}SSH keys detected. Root password login will be disabled.${CL}"
else
    echo -e "${YW}SSH keys not found. Root password login will not be disabled.${CL}"
fi

cpu_yn=$(prompt_countdown "Set CPU Governor to PERFORMANCE? (y/N):" "n" "$T")
[[ "$cpu_yn" =~ ^[Yy]$ ]] && ENABLE_PERFORMANCE="y"

crowdsec_yn=$(prompt_countdown "Install CrowdSec Security Suite? (Y/n):" "y" "$T")
[[ "$crowdsec_yn" =~ ^[Nn]$ ]] && ENABLE_CROWDSEC="n"

start_yn=$(prompt_countdown "Start the PVE9 Post Install Script? (Y/n):" "y" "$T")
[[ "$start_yn" =~ ^[Nn]$ ]] && exit 0
clear
header_info
msg_ok "PVE9 POST INSTALL STARTED"

# --- 12. STORAGE MERGE ---
# Removes local-lvm and expands root/local storage for fresh single-node use.
msg_info "Merging local-lvm into local storage"

if lvdisplay /dev/pve/data >/dev/null 2>&1; then
    pvesm freezefs local-lvm >/dev/null 2>&1 || true
    lvremove -fy /dev/pve/data >/dev/null 2>&1
    lvresize -l +100%FREE /dev/pve/root >/dev/null 2>&1
    resize2fs /dev/mapper/pve-root >/dev/null 2>&1 || xfs_growfs / >/dev/null 2>&1 || true
    pvesm remove local-lvm >/dev/null 2>&1 || true
    msg_ok "local-lvm storage successfully merged to OS"
else
    msg_ok "local-lvm storage successfully merged to OS"
fi

# --- 13. DNS REDUNDANCY ---
# Adds Cloudflare DNS redundancy before apt updates to make package operations more reliable.
msg_info "Configuring DNS resolvers"

cp -n /etc/resolv.conf /etc/resolv.conf.pve9-postinstall.bak >/dev/null 2>&1 || true
cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

msg_ok "DNS RESOLVERS CONFIGURED (dns1 = 1.1.1.1 dns2 = 1.0.0.1)"

# --- 14. REPOSITORIES AND QUIET SYSTEM UPDATES ---
# Removes enterprise repos, adds no-subscription repo, updates quietly, and suppresses known noisy warnings.
msg_info "Configuring repositories and running quiet updates"

rm -f /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources

cat <<EOF > /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

apt-get update >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade >/dev/null 2>&1
apt-get -y autoremove >/dev/null 2>&1

msg_ok "SYSTEM UPDATED"

# --- 15. UI NAG REMOVAL ---
# Installs persistent dpkg hook and helper script to patch the no-subscription popup after toolkit updates.
msg_info "Patching UI nag"

cat <<'EOF' > /usr/local/sbin/pve-no-nag-patch.sh
#!/usr/bin/env bash
set -euo pipefail
FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
[ -f "$FILE" ] || exit 0
cp -n "$FILE" "${FILE}.orig" 2>/dev/null || true
if grep -q "res.data.status.toLowerCase() !== 'active'" "$FILE"; then
    sed -i "s/if (res === null || res === undefined || !res || res.data.status.toLowerCase() !== 'active') {/if (false) {/" "$FILE"
fi
if ! grep -q "if (false)\|NoMoreNagging" "$FILE"; then
    sed -i "/res.data.status/{s/!//;s/active/NoMoreNagging/g;s/Active/NoMoreNagging/g}" "$FILE" || true
fi
EOF

chmod +x /usr/local/sbin/pve-no-nag-patch.sh

cat <<'EOF' > /etc/apt/apt.conf.d/no-nag-script
DPkg::Post-Invoke { "/usr/local/sbin/pve-no-nag-patch.sh && systemctl restart pveproxy >/dev/null 2>&1 || true"; };
EOF

apt-get --reinstall install -y proxmox-widget-toolkit >/dev/null 2>&1 || true
/usr/local/sbin/pve-no-nag-patch.sh || true
systemctl restart pveproxy >/dev/null 2>&1 || true

msg_ok "NAG REMOVED"

# --- 16. POWER AND CHASSIS OPTIMIZATION ---
# Masks sleep targets and ignores laptop lid close on laptop hardware.
msg_info "Optimizing power and sleep settings"

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

if [ "$SYSTEM_TYPE" = "Laptop" ]; then
    set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitch" "ignore"
    set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitchDocked" "ignore"
    set_or_append_equals_config /etc/systemd/logind.conf "LidSwitchIgnoreInhibited" "no"
    systemctl restart systemd-logind >/dev/null 2>&1 || true
fi

msg_ok "POWER OPTIMIZED"

# --- 17. GRUB AND IOMMU ---
# Adds IOMMU, passthrough mode, and console blanking without removing existing kernel args.
msg_info "Configuring GRUB and IOMMU"

append_grub_arg "$IOMMU_FLAG"
append_grub_arg "iommu=pt"
append_grub_arg "consoleblank=60"

update-grub >/dev/null 2>&1 || true

msg_ok "GRUB UPDATED"

# --- 18. GPU ISOLATION VFIO ---
# Loads VFIO modules and binds only discrete GPU plus same-slot function device IDs to vfio-pci.
if [ "$ENABLE_PASSTHROUGH" = "y" ]; then
    if [ -n "$DGPU_IDS" ]; then
        msg_info "Isolating discrete GPU for passthrough"
        for module in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
            grep -qxF "$module" /etc/modules || echo "$module" >> /etc/modules
        done

        cat <<EOF > /etc/modprobe.d/pve-blacklist.conf
blacklist nvidia
blacklist nouveau
blacklist nvidiafb
blacklist nvidia-gpu
blacklist radeon
blacklist amdgpu
EOF

        echo "options vfio-pci ids=$DGPU_IDS disable_vga=1" > /etc/modprobe.d/vfio.conf
        update-initramfs -u -k all >/dev/null 2>&1 || true
        msg_ok "DISCRETE GPU ISOLATED; INTEGRATED GPU UNTOUCHED"
    else
        msg_warn "Passthrough selected but no safe discrete GPU IDs were found. Skipping VFIO."
    fi
fi

# --- 19. SSH SECURITY ---
# Hardens SSH only if root SSH authorized keys already exist to avoid lockout. No yes/no prompt is used.
msg_info "Checking SSH authorized keys before securing SSH"

if [ -s "$ROOT_KEYS" ]; then
    chmod 700 /root/.ssh
    chmod 600 "$ROOT_KEYS"

    set_or_append_space_config /etc/ssh/sshd_config "AddressFamily" "inet"
    set_or_append_space_config /etc/ssh/sshd_config "PasswordAuthentication" "no"
    set_or_append_space_config /etc/ssh/sshd_config "PermitRootLogin" "prohibit-password"

    sshd -t >/dev/null 2>&1
    systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || true

    SSH_HARDENING_APPLIED="yes"
    msg_ok "SSH keys detected; root password login disabled"
else
    SSH_HARDENING_APPLIED="no"
    msg_warn "SSH keys not found; root password login not disabled"
fi

# --- 20. SYSCTL HARDENING AND NETWORK TUNING ---
# Adds kernel hardening and high-traffic tuning for reverse proxy / VM workloads.
msg_info "Applying sysctl hardening and network tuning"

cat <<EOF > /etc/sysctl.d/99-pve9-hardening-network.conf
# PVE9 security hardening
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1

# High traffic reverse proxy / upload-download tuning
fs.file-max = 2097152
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 250000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 5
net.netfilter.nf_conntrack_max = 1048576
EOF

sysctl --system >/dev/null 2>&1 || true

msg_ok "SYSCTL HARDENING APPLIED"

# --- 21. REALTEK NIC OPTIMIZATION ---
# Detects Realtek NIC drivers and disables problematic offloads persistently for Docker/reverse-proxy stability.
msg_info "Checking for Realtek NIC optimization"

apt-get install -y ethtool >/dev/null 2>&1 || true
REALTEK_IFACE=$(detect_realtek_iface || true)

if [ -n "$REALTEK_IFACE" ]; then
    ethtool -K "$REALTEK_IFACE" tso off gso off gro off >/dev/null 2>&1 || true

    cat <<EOF > /etc/systemd/system/realtek-optimize.service
[Unit]
Description=Realtek NIC Optimization for Docker/Reverse Proxy Stability
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -K ${REALTEK_IFACE} tso off gso off gro off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable realtek-optimize.service >/dev/null 2>&1
    REALTEK_OPTIMIZED="yes"
    msg_ok "REALTEK NIC OPTIMIZED ($REALTEK_IFACE)"
else
    REALTEK_OPTIMIZED="no"
    msg_ok "NO REALTEK NIC OPTIMIZATION NEEDED"
fi

# --- 22. PROXMOX FIREWALL BASELINE ---
# Enables Proxmox firewall with LAN-only SSH/WebUI access and public 80/443 allowance for reverse proxy use.
msg_info "Configuring Proxmox firewall"

mkdir -p "/etc/pve/nodes/${HOSTNAME_SHORT}"

if [ -n "$LAN_CIDR" ]; then
    if grep -q "^firewall:" /etc/pve/datacenter.cfg 2>/dev/null; then
        sed -i 's/^firewall:.*/firewall: 1/' /etc/pve/datacenter.cfg
    else
        echo "firewall: 1" >> /etc/pve/datacenter.cfg
    fi

    cat <<EOF > "/etc/pve/nodes/${HOSTNAME_SHORT}/host.fw"
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]
IN ACCEPT -source ${LAN_CIDR} -p tcp -dport 22 -log nolog
IN ACCEPT -source ${LAN_CIDR} -p tcp -dport 8006 -log nolog
IN ACCEPT -p tcp -dport 80 -log nolog
IN ACCEPT -p tcp -dport 443 -log nolog
IN ACCEPT -p icmp -log nolog
EOF

    systemctl enable --now pve-firewall >/dev/null 2>&1 || true
    systemctl restart pve-firewall >/dev/null 2>&1 || true

    PVE_FIREWALL_APPLIED="yes"
    msg_ok "PROXMOX FIREWALL ENABLED"
else
    PVE_FIREWALL_APPLIED="no"
    msg_warn "Could not detect LAN CIDR. Proxmox firewall rules skipped to avoid lockout."
fi

# --- 23. CROWDSEC AND AUTO UPDATES ---
# Installs CrowdSec, firewall bouncer, collections, and unattended upgrades.
if [ "$ENABLE_CROWDSEC" = "y" ]; then
    msg_info "Installing security suite"

    apt-get install -y curl gnupg ca-certificates >/dev/null 2>&1 || true

    if command -v curl >/dev/null 2>&1; then
        curl -s https://install.crowdsec.net | sh >/dev/null 2>&1 || true
    fi

    apt-get update >/dev/null 2>&1 || true
    apt-get install -y crowdsec unattended-upgrades >/dev/null 2>&1 || true

    if apt-cache show crowdsec-firewall-bouncer-nftables >/dev/null 2>&1; then
        apt-get install -y crowdsec-firewall-bouncer-nftables >/dev/null 2>&1 || true
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-nftables"
    elif apt-cache show crowdsec-firewall-bouncer-iptables >/dev/null 2>&1; then
        apt-get install -y crowdsec-firewall-bouncer-iptables >/dev/null 2>&1 || true
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-iptables"
    else
        CROWDSEC_BOUNCER_PACKAGE="none"
    fi

    cscli collections install crowdsecurity/linux >/dev/null 2>&1 || true
    cscli collections install crowdsecurity/sshd >/dev/null 2>&1 || true
    cscli collections install crowdsecurity/proxmox >/dev/null 2>&1 || true
    cscli collections install crowdsecurity/http-cve >/dev/null 2>&1 || true

    systemctl enable --now crowdsec >/dev/null 2>&1 || true
    systemctl restart crowdsec >/dev/null 2>&1 || true

    if systemctl list-unit-files | grep -q "crowdsec-firewall-bouncer"; then
        systemctl enable --now crowdsec-firewall-bouncer >/dev/null 2>&1 || true
        systemctl restart crowdsec-firewall-bouncer >/dev/null 2>&1 || true
    fi

    cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    msg_ok "SECURITY INSTALLED"
fi

# --- 24. PROXMOX FIREWALL SERVICE REINFORCEMENT ---
# Explicitly ensures pve-firewall is enabled now and at boot.
msg_info "Enabling Proxmox firewall service"

systemctl enable --now pve-firewall >/dev/null 2>&1 || true
systemctl restart pve-firewall >/dev/null 2>&1 || true

msg_ok "PROXMOX FIREWALL SERVICE ENABLED"

# --- 25. PERFORMANCE AND TRIM ---
# Optionally enables performance CPU governor and enables SSD TRIM when SSD is detected.
if [ "$ENABLE_PERFORMANCE" = "y" ]; then
    msg_info "Setting performance governor"

    apt-get install -y cpufrequtils >/dev/null 2>&1 || true
    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils

    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        for r in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo "performance" > "$r" 2>/dev/null || true
        done
    fi

    systemctl restart cpufrequtils >/dev/null 2>&1 || true
    msg_ok "CPU PERFORMANCE ACTIVE"
fi

if [ "$IS_SSD" = "yes" ]; then
    msg_info "Enabling SSD TRIM"
    systemctl enable --now fstrim.timer >/dev/null 2>&1 || true
    msg_ok "SSD TRIM ENABLED"
fi

# --- 26. NUMLOCK ENABLEMENT ---
# Enables NumLock now and creates a boot service so it stays enabled after reboot/login.
msg_info "Enabling NumLock now and at boot"

enable_numlock_now_and_at_boot

msg_ok "NUMLOCK ENABLED"

# --- 27. AUTO-VERIFY GHOST SCRIPT ---
# Creates a one-time root-login verifier using /etc/profile.d plus systemd fallback, so the report appears after reboot/login and then deletes itself.
msg_info "Creating auto-verify ghost script"

cat <<EOF > /root/pve_verify.sh
#!/usr/bin/env bash
set +e

VERIFY_LOG="$VERIFY_LOG"
exec > >(tee -a "\$VERIFY_LOG") 2>&1

GN="\033[32m"
RD="\033[31m"
YW="\033[33m"
BL="\033[36m"
CL="\033[0m"

INSTALL_SYSTEM_TYPE="$SYSTEM_TYPE"
INSTALL_IS_SSD="$IS_SSD"
INSTALL_IGPU_FOUND="$IGPU_FOUND"
INSTALL_DGPU_FOUND="$DGPU_FOUND"
INSTALL_DGPU_BDFS="$DGPU_BDFS"
INSTALL_DGPU_IDS="$DGPU_IDS"
INSTALL_ENABLE_PASSTHROUGH="$ENABLE_PASSTHROUGH"
INSTALL_ENABLE_PERFORMANCE="$ENABLE_PERFORMANCE"
INSTALL_ENABLE_CROWDSEC="$ENABLE_CROWDSEC"
INSTALL_SSH_HARDENING_APPLIED="$SSH_HARDENING_APPLIED"
INSTALL_PVE_FIREWALL_APPLIED="$PVE_FIREWALL_APPLIED"
INSTALL_IOMMU_FLAG="$IOMMU_FLAG"
INSTALL_CROWDSEC_BOUNCER_PACKAGE="$CROWDSEC_BOUNCER_PACKAGE"
INSTALL_REALTEK_IFACE="$REALTEK_IFACE"
INSTALL_REALTEK_OPTIMIZED="$REALTEK_OPTIMIZED"

PASS() { echo -e "\${GN}✓ PASS\${CL} - \$1"; }
FAIL() { echo -e "\${RD}✗ FAIL\${CL} - \$1"; }
WARN() { echo -e "\${YW}! WARN\${CL} - \$1"; }
INFO() { echo -e "\${BL}- INFO\${CL} - \$1"; }

clear 2>/dev/null || true

echo ""
echo -e "\${BL}--- PVE9 POST-INSTALL VERIFICATION REPORT ---\${CL}"
echo "Date: \$(date)"
echo "Host: \$(hostname)"
echo ""

INFO "System type detected during install: \$INSTALL_SYSTEM_TYPE"
INFO "SSD detected during install: \$INSTALL_IS_SSD"
INFO "Integrated GPU detected during install: \$INSTALL_IGPU_FOUND"
INFO "Discrete GPU detected during install: \$INSTALL_DGPU_FOUND"
INFO "Discrete GPU passthrough selected: \$INSTALL_ENABLE_PASSTHROUGH"
INFO "CPU performance selected: \$INSTALL_ENABLE_PERFORMANCE"
INFO "SSH hardening applied during install: \$INSTALL_SSH_HARDENING_APPLIED"
INFO "CrowdSec selected during install: \$INSTALL_ENABLE_CROWDSEC"
INFO "CrowdSec bouncer package: \$INSTALL_CROWDSEC_BOUNCER_PACKAGE"
INFO "Proxmox firewall applied during install: \$INSTALL_PVE_FIREWALL_APPLIED"
INFO "Realtek NIC optimized during install: \$INSTALL_REALTEK_OPTIMIZED"
INFO "Realtek interface: \$INSTALL_REALTEK_IFACE"

echo ""

# Core Proxmox service checks.
if pveversion >/dev/null 2>&1; then PASS "Proxmox command tools available"; else FAIL "Proxmox command tools missing"; fi
if systemctl is-active --quiet pveproxy; then PASS "pveproxy active"; else FAIL "pveproxy inactive"; fi
if systemctl is-active --quiet pvedaemon; then PASS "pvedaemon active"; else FAIL "pvedaemon inactive"; fi
if systemctl is-active --quiet pvestatd; then PASS "pvestatd active"; else FAIL "pvestatd inactive"; fi
if systemctl is-active --quiet pve-cluster; then PASS "pve-cluster active"; else FAIL "pve-cluster inactive"; fi

# DNS checks.
if grep -q "nameserver 1.1.1.1" /etc/resolv.conf && grep -q "nameserver 1.0.0.1" /etc/resolv.conf; then PASS "DNS redundancy configured"; else WARN "DNS redundancy not detected"; fi

# Repository and package health checks.
if grep -q "pve-no-subscription" /etc/apt/sources.list.d/proxmox.sources 2>/dev/null; then PASS "No-subscription repository configured"; else FAIL "No-subscription repository missing"; fi
if [ ! -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then PASS "Enterprise repository disabled"; else FAIL "Enterprise repository still present"; fi
if apt-get check >/dev/null 2>&1; then PASS "APT package database healthy"; else FAIL "APT package database has problems"; fi

# Storage merge checks.
if grep -q "local-lvm" /etc/pve/storage.cfg 2>/dev/null; then WARN "local-lvm still exists in storage.cfg"; else PASS "local-lvm removed from Proxmox storage config"; fi
if lvdisplay /dev/pve/data >/dev/null 2>&1; then WARN "/dev/pve/data still exists"; else PASS "/dev/pve/data not present"; fi

# GRUB and IOMMU checks.
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "\$INSTALL_IOMMU_FLAG"; then PASS "GRUB contains \$INSTALL_IOMMU_FLAG"; else FAIL "GRUB missing \$INSTALL_IOMMU_FLAG"; fi
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "iommu=pt"; then PASS "GRUB contains iommu=pt"; else FAIL "GRUB missing iommu=pt"; fi
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "consoleblank=60"; then PASS "GRUB contains consoleblank=60"; else WARN "GRUB missing consoleblank=60"; fi
if grep -q "consoleblank=60" /proc/cmdline; then PASS "Screen blanking active in running kernel"; else WARN "Screen blanking not visible in running kernel"; fi
if dmesg | grep -Ei "IOMMU|DMAR|AMD-Vi" | grep -qi "enabled"; then PASS "IOMMU appears enabled after reboot"; else WARN "IOMMU not clearly detected in dmesg"; fi

# GPU passthrough checks.
if [ "\$INSTALL_DGPU_FOUND" = "yes" ]; then
    if [ "\$INSTALL_ENABLE_PASSTHROUGH" = "y" ]; then
        if lspci -nnk | grep -q "Kernel driver in use: vfio-pci"; then
            PASS "vfio-pci active on at least one GPU/function device"
        else
            FAIL "GPU passthrough was selected but vfio-pci is not active"
        fi
        if [ -f /etc/modprobe.d/vfio.conf ] && grep -q "\$INSTALL_DGPU_IDS" /etc/modprobe.d/vfio.conf 2>/dev/null; then
            PASS "vfio.conf contains selected discrete GPU IDs"
        else
            FAIL "vfio.conf missing selected discrete GPU IDs"
        fi
    else
        WARN "Discrete GPU present but passthrough was not selected"
    fi
else
    INFO "No discrete GPU detected during install, GPU passthrough check skipped"
fi

# SSD TRIM checks.
if [ "\$INSTALL_IS_SSD" = "yes" ]; then
    if systemctl is-enabled --quiet fstrim.timer && systemctl is-active --quiet fstrim.timer; then PASS "SSD TRIM timer enabled and active"; else FAIL "SSD TRIM timer not enabled/active"; fi
else
    INFO "No SSD detected during install, TRIM check skipped"
fi

# CPU governor checks.
if [ "\$INSTALL_ENABLE_PERFORMANCE" = "y" ]; then
    if grep -q "performance" /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null; then PASS "CPU governor is performance"; else FAIL "CPU governor is not performance"; fi
else
    INFO "CPU performance governor was not selected, check skipped"
fi

# SSH hardening checks.
if [ "\$INSTALL_SSH_HARDENING_APPLIED" = "yes" ]; then
    if sshd -T 2>/dev/null | grep -q "^passwordauthentication no"; then PASS "SSH password authentication disabled"; else FAIL "SSH password authentication still enabled"; fi
    if sshd -T 2>/dev/null | grep -Eq "^permitrootlogin (without-password|prohibit-password)"; then PASS "Root SSH password login disabled"; else FAIL "Root SSH password login not hardened"; fi
else
    WARN "SSH hardening skipped because root SSH keys were missing"
fi

# Realtek NIC optimization checks.
if [ "\$INSTALL_REALTEK_OPTIMIZED" = "yes" ]; then
    if systemctl is-enabled --quiet realtek-optimize.service; then PASS "Realtek optimization service enabled"; else WARN "Realtek optimization service not enabled"; fi
    if [ -n "\$INSTALL_REALTEK_IFACE" ] && [ -r "/sys/class/net/\$INSTALL_REALTEK_IFACE/statistics/rx_packets" ]; then PASS "Realtek interface still present"; else WARN "Realtek interface not found after reboot"; fi
else
    INFO "No Realtek optimization was applied"
fi

# Proxmox firewall checks.
if systemctl is-active --quiet pve-firewall; then PASS "Proxmox firewall service active"; else FAIL "Proxmox firewall service inactive"; fi
if grep -q "firewall: 1" /etc/pve/datacenter.cfg 2>/dev/null; then PASS "Datacenter firewall enabled"; else FAIL "Datacenter firewall not enabled"; fi
if [ -f "/etc/pve/nodes/\$(hostname -s)/host.fw" ]; then PASS "Node firewall file exists"; else WARN "Node firewall file missing"; fi

# CrowdSec checks.
if [ "\$INSTALL_ENABLE_CROWDSEC" = "y" ]; then
    if systemctl is-active --quiet crowdsec; then PASS "CrowdSec active"; else FAIL "CrowdSec inactive"; fi
    if systemctl list-unit-files | grep -q "crowdsec-firewall-bouncer"; then
        if systemctl is-active --quiet crowdsec-firewall-bouncer; then PASS "CrowdSec firewall bouncer active"; else WARN "CrowdSec bouncer installed but inactive"; fi
    else
        WARN "CrowdSec firewall bouncer service not found"
    fi
else
    INFO "CrowdSec was not selected, check skipped"
fi

# UI nag, sysctl, and NumLock checks.
if grep -q "if (false)\|NoMoreNagging" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null; then PASS "Subscription nag patch detected"; else WARN "Subscription nag patch not detected"; fi
if [ -f /etc/sysctl.d/99-pve9-hardening-network.conf ]; then PASS "Sysctl hardening file present"; else FAIL "Sysctl hardening file missing"; fi
if sysctl net.ipv4.tcp_syncookies 2>/dev/null | grep -q "= 1"; then PASS "TCP SYN cookies enabled"; else FAIL "TCP SYN cookies not enabled"; fi
if systemctl is-enabled --quiet pve-enable-numlock.service; then PASS "NumLock boot service enabled"; else WARN "NumLock boot service not enabled"; fi

echo ""
echo -e "\${YW}Verification complete. Log saved to \$VERIFY_LOG\${CL}"
echo -e "\${YW}Removing ghost verifier and startup hooks...\${CL}"

systemctl disable pve-postinstall-verify.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/pve-postinstall-verify.service
rm -f /etc/profile.d/pve-postinstall-verify.sh
rm -f /root/pve_verify.sh
systemctl daemon-reload >/dev/null 2>&1 || true

echo -e "\${GN}Ghost verifier deleted successfully.\${CL}"
EOF

chmod +x /root/pve_verify.sh

cat <<'EOF' > /etc/profile.d/pve-postinstall-verify.sh
#!/usr/bin/env bash
if [ "$(id -u)" -eq 0 ] && [ -x /root/pve_verify.sh ] && [ ! -f /run/pve-postinstall-verify-ran ]; then
    touch /run/pve-postinstall-verify-ran 2>/dev/null || true
    /root/pve_verify.sh
fi
EOF
chmod +x /etc/profile.d/pve-postinstall-verify.sh

cat <<EOF > /etc/systemd/system/pve-postinstall-verify.service
[Unit]
Description=PVE9 Post Install One-Time Verification Fallback
After=multi-user.target network-online.target pveproxy.service pvedaemon.service pvestatd.service
Wants=network-online.target
ConditionPathExists=/root/pve_verify.sh

[Service]
Type=oneshot
ExecStart=/root/pve_verify.sh
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1
systemctl enable pve-postinstall-verify.service >/dev/null 2>&1

msg_ok "AUTO-VERIFY GHOST SCRIPT CREATED"

# --- 28. COMPLETE AND FLASHING REBOOT COUNTDOWN ---
# Gives a 30-second cancel window, then reboots. The verifier appears after reboot/login and also has a systemd fallback.
echo ""
flash_red "DONE. REBOOTING IN 30 SECONDS..."
echo -e "${YW}Press Ctrl+C now to cancel automatic reboot.${CL}"
sleep 30
reboot
