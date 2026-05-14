#!/usr/bin/env bash -ex
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  PVE9 Post Install
# =========================================================

# --- 1. COLOR VARIABLES (RESTORED ALL) ---
# Keeps all colour variables intact for future UI/style changes, even if some are unused right now.
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
FLASH_ON=$'\033[5m'
FLASH_OFF=$'\033[25m'

# --- 2. GLOBAL VARIABLES ---
# Central runtime settings and state flags used throughout the script and later by the auto-verifier.
T=15
LOG_FILE="/var/log/pve9-postinstall.log"
VERIFY_LOG="/var/log/pve9-postinstall-verify.log"
COMPLETED_MARKER="/root/.pve9-postinstall-completed"

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
IGPU_FOUND="no"
DGPU_FOUND="no"
DGPU_IDS=""
DGPU_BDFS=""
GPU_SUMMARY=""

STORAGE_SUMMARY=""

ENABLE_PASSTHROUGH="n"
ENABLE_PERFORMANCE="n"
ENABLE_CROWDSEC="y"
SSH_HARDENING_APPLIED="no"
PVE_FIREWALL_APPLIED="no"
CROWDSEC_BOUNCER_PACKAGE="none"
NUMLOCK_CONFIGURED="no"

# --- 3. HEADER FUNCTION ---
# Prints the one-line PVE9 Post Install ASCII banner.
function header_info {
echo -e "${RD}
██████╗ ██╗   ██╗███████╗ █████╗     ██████╗  ██████╗ ███████╗████████╗    ██╗███╗   ██╗███████╗████████╗ █████╗ ██╗     ██╗     
██╔══██╗██║   ██║██╔════╝██╔══██╗    ██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝    ██║████╗  ██║██╔════╝╚══██╔══╝██╔══██╗██║     ██║     
██████╔╝██║   ██║█████╗  ╚██████║    ██████╔╝██║   ██║███████╗   ██║       ██║██╔██╗ ██║███████╗   ██║   ███████║██║     ██║     
██╔═══╝ ╚██╗ ██╔╝██╔══╝   ╚═══██║    ██╔═══╝ ██║   ██║╚════██║   ██║       ██║██║╚██╗██║╚════██║   ██║   ██╔══██║██║     ██║     
██║      ╚████╔╝ ███████╗ █████╔╝    ██║     ╚██████╔╝███████║   ██║       ██║██║ ╚████║███████║   ██║   ██║  ██║███████╗███████╗
╚═╝       ╚═══╝  ╚══════╝ ╚════╝     ╚═╝      ╚═════╝ ╚══════╝   ╚═╝       ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝
${CL}"
}

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Standardizes status output so every code batch follows clean "display/apply/success" flow.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. LOGGING & ERROR HANDLING ---
# Logs all output to /var/log/pve9-postinstall.log and reports the failure line if anything breaks.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 6. ROOT CHECK ---
# Proxmox host-level tasks require root. Exits immediately if not run as root.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

clear
header_info

# --- 7. TTY OUTPUT HELPER ---
# Prints text directly to the active terminal. This is required because prompts return only final answer on stdout.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 8. TTY OUTPUT WITH NEWLINE HELPER ---
# Same as tty_print, but appends a newline. Used by countdown stop messages and login-style notices.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 9. TTY BLOCKING YES/NO READER HELPER ---
# Used after SPACE is pressed on timed prompts.
# SPACE stops the countdown, then this helper waits for Y/N/ENTER instead of proceeding automatically.
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

# --- 10. SSHD SPACE-SEPARATED CONFIG HELPER ---
# Sets or appends SSH-style config lines such as "PasswordAuthentication no".
# It safely handles commented existing lines, existing active lines, or missing keys.
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

# --- 11. SYSTEMD EQUALS-STYLE CONFIG HELPER ---
# Sets or appends config lines such as "HandleLidSwitch=ignore".
# Used for logind/laptop lid settings where key=value syntax is expected.
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

# --- 12. GRUB ARGUMENT HELPER ---
# Adds a kernel argument to GRUB_CMDLINE_LINUX_DEFAULT without removing existing boot options.
function append_grub_arg() {
    local arg="$1"
    local grub_file="/etc/default/grub"
    grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> "$grub_file"
    if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" | grep -qw "$arg"; then
        sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 ${arg}\"|" "$grub_file"
    fi
}

# --- 13. SAFETY EXIT COUNTDOWN HELPER ---
# Displays a visible delay before exiting on unsafe/non-fresh installs so the user can read the reason.
function countdown_exit() {
    local seconds="$1"
    local reason="$2"
    echo ""
    echo -e "${RD}${reason}${CL}"
    echo -e "${YW}Exiting in ${seconds} seconds...${CL}"
    sleep "$seconds"
    exit 1
}

# --- 14. YES/NO ANSWER LABEL HELPER ---
# Converts Y/N input into a readable final answer line shown after every timed prompt.
function yes_no_label() {
    local value="$1"
    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 15. TIMED YES/NO PROMPT HELPER ---
# Shows a 15-second countdown for Y/n prompts.
# SPACE stops the countdown and waits for Y/N/ENTER instead of accepting default.
# Y or N explicitly selects a value. Timeout accepts the default.
# After each prompt resolves, it prints a visible final answer line and keeps it on screen.
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

# --- 16. TIMED REBOOT COUNTDOWN HELPER ---
# Shows a blue flashing reboot countdown.
# SPACE stops the countdown and prevents reboot. Timeout triggers reboot.
function timed_reboot_countdown() {
    local seconds="$1"
    local key=""

    for ((i=seconds; i>0; i--)); do
        tty_print "${BFR}${BL}${CLF}REBOOTING IN ${i} SECONDS...${CL} ${YW}(press SPACE to stop countdown)${CL}"

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                if [[ "$key" == " " ]]; then
                    tty_print "${BFR}"
                    tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                    return 1
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    tty_print "${BFR}"
                    tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                    return 1
                fi
            fi
        fi
    done

    tty_print "${BFR}"
    return 0
}

# --- 17. REALTEK NIC DETECTION HELPER ---
# Finds the active Realtek Ethernet interface by checking kernel driver names through ethtool.
function detect_realtek_iface() {
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

# --- 18. GPU NAME CLEANUP HELPER ---
# Removes PCI IDs, revision markers, and extra whitespace so GPU display messages stay readable.
function clean_gpu_name() {
    echo "$1" | sed -E 's/^[0-9a-fA-F:.]+[[:space:]]+//; s/\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]//g; s/\(rev [^)]+\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//'
}

# --- 19. GPU SUMMARY HELPER ---
# Builds a clean human-readable GPU summary line from integrated/discrete GPU detection results.
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

# --- 20. STORAGE SUMMARY HELPER ---
# Builds a simple disk summary such as "SSD(sda) SSD(sdb) HDD(sdc)" for the detection screen.
function build_storage_summary() {
    local out=""

    while read -r name rota type; do
        [ "$type" != "disk" ] && continue

        if [ "$rota" == "0" ]; then
            out+="SSD(${name}) "
        else
            out+="HDD(${name}) "
        fi
    done < <(lsblk -dn -o NAME,ROTA,TYPE)

    echo "$out" | xargs
}

# --- 21. ADAPTIVE GPU LABEL HELPER ---
# Creates a system-type-aware detection message for laptops, workstations, VMs and mixed GPU systems.
function detected_machine_gpu_label() {
    if [ "$IGPU_FOUND" == "yes" ] && [ "$DGPU_FOUND" == "yes" ]; then
        echo "DETECTED ${SYSTEM_TYPE^^} WITH INTEGRATED + DISCRETE GPU."
    elif [ "$IGPU_FOUND" == "yes" ]; then
        echo "DETECTED ${SYSTEM_TYPE^^} WITH INTEGRATED GPU."
    elif [ "$DGPU_FOUND" == "yes" ]; then
        echo "DETECTED ${SYSTEM_TYPE^^} WITH DISCRETE GPU."
    else
        echo "DETECTED ${SYSTEM_TYPE^^} WITH NO GPU PASSTHROUGH TARGET."
    fi
}

# --- 22. PROXMOX VERSION VALIDATION ---
# Validates this is Proxmox VE 9 before showing fresh-install warnings or making changes.
if ! command -v pveversion >/dev/null 2>&1; then
    msg_error "This system is not Proxmox VE. Script cancelled."
fi

PVE_MAJOR=$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)

if ! [[ "$PVE_MAJOR" =~ ^[0-9]+$ ]]; then
    msg_error "Could not detect Proxmox VE version. Script cancelled."
fi

if [ "$PVE_MAJOR" -lt 9 ]; then
    msg_error "Requires Proxmox VE 9+. Detected Proxmox VE ${PVE_MAJOR}. Script cancelled."
fi

# --- 23. FRESH INSTALL WARNING ---
# Shows only after confirming this is a valid Proxmox VE 9 system.
echo -e "${YW} This script will Perform PVE9 Post Install Routines.${CL}"
echo ""
echo -e "${YW}${CLF} Intended for FRESH Proxmox VE 9 installs only.${CL}"
echo ""

# --- 24. PRE-INSTALL SYSTEM AUDIT ---
# Detects CPU vendor, IOMMU flag, chassis type, virtual machine state, storage type, default route and LAN CIDR.
CPU_TYPE=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')

if [ "$CPU_TYPE" == "GenuineIntel" ]; then
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
elif [ "$IS_VM" == "yes" ]; then
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

STORAGE_SUMMARY=$(build_storage_summary)

# --- 25. FRESH INSTALL DETECTION ---
# Checks for existing VMs, LXCs, extra bridges and script-created artefacts from previous runs.
# This prevents rerunning after a previous successful post-install even if no VMs/containers exist yet.
msg_info "Checking for fresh install state"

VM_COUNT=$(qm list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')
CT_COUNT=$(pct list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')
CUSTOM_BRIDGES=$(grep -Ec "^auto vmbr[1-9]" /etc/network/interfaces 2>/dev/null || true)

PREVIOUS_RUN_ARTIFACTS=(
    "$COMPLETED_MARKER"
    "$VERIFY_LOG"
    "/usr/local/sbin/pve-no-nag-patch.sh"
    "/etc/apt/apt.conf.d/no-nag-script"
    "/etc/sysctl.d/99-pve9-hardening-network.conf"
    "/etc/systemd/system/pve-numlock.service"
    "/etc/systemd/system/realtek-optimize.service"
    "/etc/profile.d/pve-postinstall-verify-display.sh"
    "/root/.pve9-postinstall-verify-displayed"
)

PREVIOUS_RUN_HITS=()

for artifact in "${PREVIOUS_RUN_ARTIFACTS[@]}"; do
    if [ -e "$artifact" ]; then
        PREVIOUS_RUN_HITS+=("$artifact")
    fi
done

if [ "$VM_COUNT" -gt 0 ] || [ "$CT_COUNT" -gt 0 ] || [ "$CUSTOM_BRIDGES" -gt 0 ] || [ "${#PREVIOUS_RUN_HITS[@]}" -gt 0 ]; then
    IS_FRESH="no"
fi

if [ "$IS_FRESH" == "no" ]; then
    echo ""
    echo -e "${RD}WARNING: This does not look like a fresh install.${CL}"
    echo -e "${YW}Detected VMs: ${VM_COUNT}, LXCs: ${CT_COUNT}, extra bridges: ${CUSTOM_BRIDGES}.${CL}"

    if [ "${#PREVIOUS_RUN_HITS[@]}" -gt 0 ]; then
        echo -e "${YW}Previous post-install artefacts detected:${CL}"
        for hit in "${PREVIOUS_RUN_HITS[@]}"; do
            echo -e "${YW} - ${hit}${CL}"
        done
    fi

    countdown_exit 30 "For safety this script will not continue on a non-fresh-looking node."
fi

msg_ok "FRESH INSTALL CHECK PASSED"

# --- 26. GPU HARDWARE DETECTION ---
# Detects iGPU and dGPU before printing adaptive detection messages or asking passthrough questions.
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

GPU_SUMMARY=$(build_gpu_summary)

msg_ok "$(detected_machine_gpu_label)"
echo -e " ${BL}━━━━━▶${CL} ${GPU_SUMMARY:-No GPU details detected}"

# --- 27. GPU PASSTHROUGH USER OPTION ---
# If a discrete GPU exists, asks whether to isolate only the discrete GPU for VM passthrough.
ENABLE_PASSTHROUGH="n"

if [ "$DGPU_FOUND" == "yes" ]; then
    if [ "$SYSTEM_TYPE" == "Laptop" ] && [ "$IGPU_FOUND" == "yes" ]; then
        echo -e "${YW}Integrated GPU will be kept for laptop screen. Only discrete GPU and same-slot function devices will be isolated.${CL}"
    else
        echo -e "${YW}Only discrete GPU and same-slot function devices will be isolated.${CL}"
    fi

    gpu_yn=$(timed_yes_no "Isolate Discrete GPU for VM Passthrough?" "y")

    if [[ "$gpu_yn" =~ ^[Yy] ]]; then
        ENABLE_PASSTHROUGH="y"
        echo -e "${GN}Discrete GPU passthrough will be activated; Integrated GPU will be left untouched.${CL}"
    else
        ENABLE_PASSTHROUGH="n"
        echo -e "${YW}Discrete GPU passthrough will not be activated.${CL}"
    fi
else
    echo -e "${YW}No discrete GPU detected. GPU passthrough will be skipped.${CL}"
fi

# --- 28. STORAGE DETECTION DISPLAY ---
# Displays detected disk types before final confirmation.
msg_ok "DETECTED STORAGE TYPE"
echo -e " ${BL}━━━━━▶${CL} ${STORAGE_SUMMARY:-No disk summary detected}"

# --- 29. CPU PERFORMANCE OPTION ---
# Optional CPU performance governor. Default is no to avoid unnecessary heat on laptops.
cpu_yn=$(timed_yes_no "Set CPU Governor to PERFORMANCE?" "n")

if [[ "$cpu_yn" =~ ^[Yy] ]]; then
    ENABLE_PERFORMANCE="y"
else
    ENABLE_PERFORMANCE="n"
fi

# --- 30. CROWDSEC OPTION ---
# Optional CrowdSec security suite. Default is yes for your public-facing reverse-proxy/web workload.
crowdsec_yn=$(timed_yes_no "Install CrowdSec Security Suite?" "y")

if [[ "$crowdsec_yn" =~ ^[Nn] ]]; then
    ENABLE_CROWDSEC="n"
else
    ENABLE_CROWDSEC="y"
fi

# --- 31. FINAL START CONFIRMATION ---
# Last user checkpoint before changes are applied. Default is yes for unattended fresh install flow.
start_yn=$(timed_yes_no "Start the PVE9 Post Install Script?" "y")

if [[ "$start_yn" =~ ^[Nn] ]]; then
    exit 0
fi

sleep 1
clear
header_info

# --- 32. STORAGE MERGE ---
# Removes local-lvm if present and expands root/local storage for simple fresh-node usage.
msg_info "Merging local-lvm into local storage"

if lvdisplay /dev/pve/data >/dev/null 2>&1; then
    pvesm freezefs local-lvm &>/dev/null || true
    lvremove -fy /dev/pve/data &>/dev/null
    lvresize -l +100%FREE /dev/pve/root &>/dev/null
    resize2fs /dev/mapper/pve-root &>/dev/null
    pvesm remove local-lvm &>/dev/null || true
fi

msg_ok "local-lvm storage successfully merged to OS"

# --- 33. DNS REDUNDANCY ---
# Adds Cloudflare primary/secondary DNS before package operations.
msg_info "Configuring DNS resolvers"

cp -n /etc/resolv.conf /etc/resolv.conf.pve9-postinstall.bak 2>/dev/null || true

cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

msg_ok "DNS RESOLVERS CONFIGURED (DNS1 = 1.1.1.1, DNS2 = 1.0.0.1)"

# --- 34. REPOSITORIES & SYSTEM UPDATES ---
# Removes enterprise repo, adds no-subscription repo, upgrades packages, and hides apt output noise.
msg_info "Configuring Repositories & Running Updates"

rm -f /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources

cat <<EOF > /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

DEBIAN_FRONTEND=noninteractive apt-get update &>/dev/null
DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade &>/dev/null
DEBIAN_FRONTEND=noninteractive apt-get -y autoremove &>/dev/null

msg_ok "SYSTEM UPDATED"

# --- 35. SUBSCRIPTION NAG PATCH HELPER ---
# Creates a reusable patch script for proxmoxlib.js so the no-subscription popup stays removed after package updates.
msg_info "Patching UI Nag"

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

# --- 36. SUBSCRIPTION NAG DPKG HOOK ---
# Reapplies the nag patch automatically whenever proxmox-widget-toolkit is updated/reinstalled.
cat <<'EOF' > /etc/apt/apt.conf.d/no-nag-script
DPkg::Post-Invoke { "/usr/local/sbin/pve-no-nag-patch.sh && systemctl restart pveproxy >/dev/null 2>&1 || true"; };
EOF

DEBIAN_FRONTEND=noninteractive apt-get --reinstall install -y proxmox-widget-toolkit &>/dev/null
/usr/local/sbin/pve-no-nag-patch.sh &>/dev/null || true
systemctl restart pveproxy &>/dev/null || true

msg_ok "NAG REMOVED"

# --- 37. POWER TARGET MASKING ---
# Disables sleep/suspend/hibernate targets for always-on server behaviour.
msg_info "Optimizing Power/Sleep Settings"

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target &>/dev/null

# --- 38. LAPTOP LID BEHAVIOUR ---
# On laptops, ignores lid close so the node can run headless while closed.
if [ "$SYSTEM_TYPE" == "Laptop" ]; then
    set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitch" "ignore"
    set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitchDocked" "ignore"
    set_or_append_equals_config /etc/systemd/logind.conf "LidSwitchIgnoreInhibited" "no"
    systemctl restart systemd-logind &>/dev/null || true
fi

msg_ok "POWER OPTIMIZED"

# --- 39. GRUB IOMMU CONFIGURATION ---
# Enables CPU-specific IOMMU, passthrough mode, and screen blanking without overwriting existing GRUB args.
msg_info "Configuring GRUB & IOMMU"

append_grub_arg "$IOMMU_FLAG"
append_grub_arg "iommu=pt"
append_grub_arg "consoleblank=60"

update-grub &>/dev/null || true

msg_ok "GRUB UPDATED"

# --- 40. GPU VFIO MODULES AND BLACKLISTS ---
# If selected, loads VFIO modules and prevents host GPU drivers from claiming the discrete GPU.
if [ "$ENABLE_PASSTHROUGH" == "y" ]; then
    if [ -n "$DGPU_IDS" ]; then
        msg_info "Isolating discrete GPU for Passthrough"

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
        update-initramfs -u -k all &>/dev/null || true

        msg_ok "GPU ISOLATED"
    else
        msg_warn "Passthrough selected but no safe discrete GPU IDs were found. Skipping VFIO."
    fi
fi

# --- 41. SSH AUTHORIZED KEYS CHECK ---
# Checks whether root SSH keys exist before disabling password authentication to prevent lockout.
msg_info "Checking for SSH authorized keys"

ROOT_KEYS="/root/.ssh/authorized_keys"

if [ -s "$ROOT_KEYS" ]; then
    msg_ok "SSH KEYS DETECTED"

    # --- 42. SSH HARDENING ---
    # Uses root SSH keys as safety proof, then disables password auth and root password login.
    msg_info "Disabling root password login"

    chmod 700 /root/.ssh
    chmod 600 "$ROOT_KEYS"

    set_or_append_space_config /etc/ssh/sshd_config "AddressFamily" "inet"
    set_or_append_space_config /etc/ssh/sshd_config "PasswordAuthentication" "no"
    set_or_append_space_config /etc/ssh/sshd_config "PermitRootLogin" "prohibit-password"

    sshd -t &>/dev/null
    systemctl restart ssh.service &>/dev/null || true

    SSH_HARDENING_APPLIED="yes"

    msg_ok "ROOT PASSWORD LOGIN DISABLED"
else
    SSH_HARDENING_APPLIED="no"
    msg_warn "SSH keys not found; root password login not disabled"
fi

# --- 43. SYSCTL HARDENING AND NETWORK TUNING FILE ---
# Adds security hardening and higher connection/network limits for reverse-proxy and upload/download workloads.
msg_info "Applying Sysctl Hardening & Network Tuning"

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

# --- 44. SYSCTL APPLY ---
# Applies the new sysctl file immediately without requiring reboot.
sysctl --system &>/dev/null || true

msg_ok "SYSCTL HARDENING APPLIED"

# --- 45. REALTEK DRIVER PACKAGE PREP ---
# Installs ethtool so Realtek offload settings can be detected and changed.
msg_info "Checking for Realtek NIC optimization"

DEBIAN_FRONTEND=noninteractive apt-get install -y ethtool &>/dev/null || true
REALTEK_IFACE=$(detect_realtek_iface || true)

# --- 46. REALTEK OFFLOAD OPTIMIZATION ---
# For Realtek NICs, disables TSO/GSO/GRO to reduce Docker/reverse-proxy instability under traffic.
if [ -n "$REALTEK_IFACE" ]; then
    ethtool -K "$REALTEK_IFACE" tso off gso off gro off &>/dev/null || true

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

    systemctl daemon-reload &>/dev/null
    systemctl enable realtek-optimize.service &>/dev/null
    REALTEK_OPTIMIZED="yes"

    msg_ok "REALTEK NIC OPTIMIZED ($REALTEK_IFACE)"
else
    REALTEK_OPTIMIZED="no"
    msg_ok "NO REALTEK NIC OPTIMIZATION NEEDED"
fi

# --- 47. PROXMOX FIREWALL BASELINE ---
# Creates a LAN-safe host firewall: LAN SSH/WebUI, public 80/443, ICMP allowed, inbound default drop.
msg_info "Configuring Proxmox Firewall"

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

    systemctl enable --now pve-firewall &>/dev/null || true
    systemctl restart pve-firewall &>/dev/null || true

    PVE_FIREWALL_APPLIED="yes"

    msg_ok "PROXMOX FIREWALL ENABLED"
else
    PVE_FIREWALL_APPLIED="no"
    msg_warn "Could not detect LAN CIDR. Proxmox firewall rules skipped to avoid lockout."
fi

# --- 48. CROWDSEC INSTALLATION ---
# Installs CrowdSec and unattended-upgrades when selected.
if [ "$ENABLE_CROWDSEC" == "y" ]; then
    msg_info "Installing Security Suite"

    DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg ca-certificates &>/dev/null || true

    if command -v curl >/dev/null 2>&1; then
        curl -s https://install.crowdsec.net | sh &>/dev/null || true
    fi

    DEBIAN_FRONTEND=noninteractive apt-get update &>/dev/null || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec unattended-upgrades &>/dev/null || true

    # --- 49. CROWDSEC BOUNCER SELECTION ---
    # Prefers nftables bouncer on modern Proxmox, falls back to iptables if nftables package is unavailable.
    if apt-cache show crowdsec-firewall-bouncer-nftables &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec-firewall-bouncer-nftables &>/dev/null || true
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-nftables"
    elif apt-cache show crowdsec-firewall-bouncer-iptables &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec-firewall-bouncer-iptables &>/dev/null || true
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-iptables"
    else
        CROWDSEC_BOUNCER_PACKAGE="none"
    fi

    # --- 50. CROWDSEC COLLECTIONS ---
    # Adds Linux, SSH, Proxmox and HTTP-CVE collections for host and web-facing attack detection.
    cscli collections install crowdsecurity/linux &>/dev/null || true
    cscli collections install crowdsecurity/sshd &>/dev/null || true
    cscli collections install crowdsecurity/proxmox &>/dev/null || true
    cscli collections install crowdsecurity/http-cve &>/dev/null || true

    # --- 51. CROWDSEC SERVICE ENABLEMENT ---
    # Enables CrowdSec and bouncer services where available.
    systemctl enable --now crowdsec &>/dev/null || true
    systemctl restart crowdsec &>/dev/null || true

    if systemctl list-unit-files 'crowdsec-firewall-bouncer*' --no-pager --no-legend 2>/dev/null | grep -q "crowdsec-firewall-bouncer"; then
        systemctl enable --now crowdsec-firewall-bouncer &>/dev/null || true
        systemctl restart crowdsec-firewall-bouncer &>/dev/null || true
    fi

    # --- 52. UNATTENDED UPGRADES ---
    # Enables daily package list refresh and unattended security upgrades.
    cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    msg_ok "SECURITY INSTALLED"
fi

# --- 53. PROXMOX FIREWALL SERVICE REINFORCEMENT ---
# Ensures pve-firewall remains enabled after all firewall/security changes.
msg_info "Enabling Proxmox firewall service"

systemctl enable --now pve-firewall &>/dev/null || true
systemctl restart pve-firewall &>/dev/null || true

msg_ok "PROXMOX FIREWALL SERVICE ENABLED"

# --- 54. OPTIONAL CPU PERFORMANCE GOVERNOR ---
# Enables persistent CPU performance mode only if the user selected it.
if [ "$ENABLE_PERFORMANCE" == "y" ]; then
    msg_info "Setting Performance Governor"

    DEBIAN_FRONTEND=noninteractive apt-get install -y cpufrequtils &>/dev/null || true

    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils

    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        for r in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo "performance" > "$r" 2>/dev/null || true
        done
    fi

    systemctl restart cpufrequtils &>/dev/null || true

    msg_ok "CPU PERFORMANCE ACTIVE"
fi

# --- 55. SSD TRIM ---
# Enables fstrim timer automatically when SSD/NVMe storage is detected.
if [ "$IS_SSD" == "yes" ]; then
    msg_info "Enabling SSD TRIM"

    systemctl enable --now fstrim.timer &>/dev/null

    msg_ok "SSD TRIM ENABLED"
fi

# --- 56. NUMLOCK SCRIPT ---
# Creates a helper that enables NumLock on Linux console TTYs when possible.
msg_info "Configuring NumLock on boot"

DEBIAN_FRONTEND=noninteractive apt-get install -y kbd &>/dev/null || true

cat <<'EOF' > /usr/local/sbin/pve-numlock-on.sh
#!/usr/bin/env bash
set +e
for tty in /dev/tty1 /dev/tty2 /dev/tty3 /dev/tty4 /dev/tty5 /dev/tty6; do
    [ -w "$tty" ] && /usr/bin/setleds -D +num < "$tty" >/dev/null 2>&1 || true
done
exit 0
EOF

chmod +x /usr/local/sbin/pve-numlock-on.sh

# --- 57. NUMLOCK SYSTEMD SERVICE ---
# Persists NumLock activation across reboots using a simple oneshot service.
cat <<EOF > /etc/systemd/system/pve-numlock.service
[Unit]
Description=Enable NumLock on Linux Consoles
After=getty.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pve-numlock-on.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload &>/dev/null
systemctl enable pve-numlock.service &>/dev/null

NUMLOCK_CONFIGURED="yes"

msg_ok "NUMLOCK BOOT SERVICE CONFIGURED"

# --- 58. AUTO-VERIFY GHOST SCRIPT CREATION ---
# Creates the one-time verifier script that runs after reboot, writes a log, then deletes itself and its service.
msg_info "Creating Auto-Verify Ghost Script"

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
INSTALL_NUMLOCK_CONFIGURED="$NUMLOCK_CONFIGURED"

PASS() { echo -e "\${GN}✓ PASS\${CL} - \$1"; }
FAIL() { echo -e "\${RD}✗ FAIL\${CL} - \$1"; }
WARN() { echo -e "\${YW}! WARN\${CL} - \$1"; }
INFO() { echo -e "\${BL}- INFO\${CL} - \$1"; }

clear

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
INFO "NumLock service configured: \$INSTALL_NUMLOCK_CONFIGURED"

echo ""

sleep 5

# Core Proxmox services
if pveversion >/dev/null 2>&1; then PASS "Proxmox command tools available"; else FAIL "Proxmox command tools missing"; fi
if systemctl is-active --quiet pveproxy; then PASS "pveproxy active"; else FAIL "pveproxy inactive"; fi
if systemctl is-active --quiet pvedaemon; then PASS "pvedaemon active"; else FAIL "pvedaemon inactive"; fi
if systemctl is-active --quiet pvestatd; then PASS "pvestatd active"; else FAIL "pvestatd inactive"; fi
if systemctl is-active --quiet pve-cluster; then PASS "pve-cluster active"; else FAIL "pve-cluster inactive"; fi

# DNS
if grep -q "nameserver 1.1.1.1" /etc/resolv.conf && grep -q "nameserver 1.0.0.1" /etc/resolv.conf; then PASS "DNS redundancy configured"; else WARN "DNS redundancy not detected"; fi

# Repositories and package health
if grep -q "pve-no-subscription" /etc/apt/sources.list.d/proxmox.sources 2>/dev/null; then PASS "No-subscription repository configured"; else FAIL "No-subscription repository missing"; fi
if [ ! -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then PASS "Enterprise repository disabled"; else FAIL "Enterprise repository still present"; fi
if apt-get check >/dev/null 2>&1; then PASS "APT package database healthy"; else FAIL "APT package database has problems"; fi

# Storage merge
if grep -q "local-lvm" /etc/pve/storage.cfg 2>/dev/null; then WARN "local-lvm still exists in storage.cfg"; else PASS "local-lvm removed from Proxmox storage config"; fi
if lvdisplay /dev/pve/data >/dev/null 2>&1; then WARN "/dev/pve/data still exists"; else PASS "/dev/pve/data not present"; fi

# GRUB/IOMMU
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "\$INSTALL_IOMMU_FLAG"; then PASS "GRUB contains \$INSTALL_IOMMU_FLAG"; else FAIL "GRUB missing \$INSTALL_IOMMU_FLAG"; fi
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "iommu=pt"; then PASS "GRUB contains iommu=pt"; else FAIL "GRUB missing iommu=pt"; fi
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "consoleblank=60"; then PASS "GRUB contains consoleblank=60"; else WARN "GRUB missing consoleblank=60"; fi
if grep -q "consoleblank=60" /proc/cmdline; then PASS "Screen blanking active in running kernel"; else WARN "Screen blanking not visible in running kernel"; fi
if dmesg | grep -Ei "IOMMU|DMAR|AMD-Vi" | grep -qi "enabled"; then PASS "IOMMU appears enabled after reboot"; else WARN "IOMMU not clearly detected in dmesg"; fi

# GPU passthrough
if [ "\$INSTALL_DGPU_FOUND" == "yes" ]; then
    if [ "\$INSTALL_ENABLE_PASSTHROUGH" == "y" ]; then
        if [ -f /etc/modprobe.d/vfio.conf ] && grep -q "\$INSTALL_DGPU_IDS" /etc/modprobe.d/vfio.conf 2>/dev/null; then PASS "vfio.conf contains selected discrete GPU IDs"; else FAIL "vfio.conf missing selected discrete GPU IDs"; fi
    else
        WARN "Discrete GPU present but passthrough was not selected"
    fi
else
    INFO "No discrete GPU detected during install, GPU passthrough check skipped"
fi

# SSD TRIM
if [ "\$INSTALL_IS_SSD" == "yes" ]; then
    if systemctl is-enabled --quiet fstrim.timer && systemctl is-active --quiet fstrim.timer; then PASS "SSD TRIM timer enabled and active"; else FAIL "SSD TRIM timer not enabled/active"; fi
else
    INFO "No SSD detected during install, TRIM check skipped"
fi

# CPU governor
if [ "\$INSTALL_ENABLE_PERFORMANCE" == "y" ]; then
    if grep -q "performance" /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null; then PASS "CPU governor is performance"; else FAIL "CPU governor is not performance"; fi
else
    INFO "CPU performance governor was not selected, check skipped"
fi

# SSH hardening
if [ "\$INSTALL_SSH_HARDENING_APPLIED" == "yes" ]; then
    if sshd -T 2>/dev/null | grep -q "^passwordauthentication no"; then PASS "SSH password authentication disabled"; else FAIL "SSH password authentication still enabled"; fi
    if sshd -T 2>/dev/null | grep -Eq "^permitrootlogin (without-password|prohibit-password)"; then PASS "Root SSH password login disabled"; else FAIL "Root SSH password login not hardened"; fi
else
    WARN "SSH hardening was skipped because root SSH keys were missing"
fi

# Realtek NIC optimization
if [ "\$INSTALL_REALTEK_OPTIMIZED" == "yes" ]; then
    if systemctl is-enabled --quiet realtek-optimize.service; then PASS "Realtek optimization service enabled"; else WARN "Realtek optimization service not enabled"; fi
    if [ -n "\$INSTALL_REALTEK_IFACE" ] && [ -r "/sys/class/net/\$INSTALL_REALTEK_IFACE/statistics/rx_packets" ]; then PASS "Realtek interface still present"; else WARN "Realtek interface not found after reboot"; fi
else
    INFO "No Realtek optimization was applied"
fi

# Proxmox firewall
if systemctl is-active --quiet pve-firewall; then PASS "Proxmox firewall service active"; else FAIL "Proxmox firewall service inactive"; fi
if grep -q "firewall: 1" /etc/pve/datacenter.cfg 2>/dev/null; then PASS "Datacenter firewall enabled"; else FAIL "Datacenter firewall not enabled"; fi
if [ -f "/etc/pve/nodes/\$(hostname -s)/host.fw" ]; then PASS "Node firewall file exists"; else WARN "Node firewall file missing"; fi

# CrowdSec
if [ "\$INSTALL_ENABLE_CROWDSEC" == "y" ]; then
    if systemctl is-active --quiet crowdsec; then PASS "CrowdSec active"; else FAIL "CrowdSec inactive"; fi
    if systemctl list-unit-files 'crowdsec-firewall-bouncer*' --no-pager --no-legend 2>/dev/null | grep -q "crowdsec-firewall-bouncer"; then
        if systemctl is-active --quiet crowdsec-firewall-bouncer; then PASS "CrowdSec firewall bouncer active"; else WARN "CrowdSec bouncer installed but inactive"; fi
    else
        WARN "CrowdSec firewall bouncer service not found"
    fi
else
    INFO "CrowdSec was not selected, check skipped"
fi

# NumLock
if [ "\$INSTALL_NUMLOCK_CONFIGURED" == "yes" ]; then
    if systemctl is-enabled --quiet pve-numlock.service; then PASS "NumLock boot service enabled"; else WARN "NumLock boot service not enabled"; fi
else
    INFO "NumLock was not configured"
fi

# UI nag and sysctl
if grep -q "if (false)\\|NoMoreNagging" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js 2>/dev/null; then PASS "Subscription nag patch detected"; else WARN "Subscription nag patch not detected"; fi
if [ -f /etc/sysctl.d/99-pve9-hardening-network.conf ]; then PASS "Sysctl hardening file present"; else FAIL "Sysctl hardening file missing"; fi
if sysctl net.ipv4.tcp_syncookies 2>/dev/null | grep -q "= 1"; then PASS "TCP SYN cookies enabled"; else FAIL "TCP SYN cookies not enabled"; fi
if sysctl net.core.somaxconn 2>/dev/null | awk '{print \$3}' | grep -Eq "^[0-9]+$"; then PASS "Network tuning sysctl readable"; else WARN "Network tuning sysctl not readable"; fi

echo ""
echo -e "\${YW}Verification complete. Log saved to \$VERIFY_LOG\${CL}"
echo -e "\${YW}Removing ghost verifier and systemd service...\${CL}"

systemctl disable pve-postinstall-verify.service >/dev/null 2>&1 || true
rm -f /etc/systemd/system/pve-postinstall-verify.service
rm -f /root/pve_verify.sh
systemctl daemon-reload >/dev/null 2>&1 || true

echo -e "\${GN}Ghost verifier deleted successfully.\${CL}"
EOF

chmod +x /root/pve_verify.sh

# --- 59. AUTO-VERIFY SYSTEMD SERVICE ---
# Runs the verifier once after reboot after network, SSH and Proxmox services are available.
cat <<EOF > /etc/systemd/system/pve-postinstall-verify.service
[Unit]
Description=PVE9 Post Install One-Time Verification
After=multi-user.target network-online.target pve-cluster.service pveproxy.service pvedaemon.service pvestatd.service ssh.service
Wants=network-online.target pve-cluster.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 45
ExecStart=/bin/bash /root/pve_verify.sh
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pve-postinstall-verify.service &>/dev/null

# --- 60. AUTO-VERIFY SSH LOGIN DISPLAY HELPER ---
# Displays the verification log once on SSH login only after the log exists.
# If the verifier has not finished yet, it stays installed and tries again on the next SSH login.
cat <<'EOF' > /etc/profile.d/pve-postinstall-verify-display.sh
#!/usr/bin/env bash

VERIFY_LOG="/var/log/pve9-postinstall-verify.log"
DISPLAY_HELPER="/etc/profile.d/pve-postinstall-verify-display.sh"
DISPLAY_MARKER="/root/.pve9-postinstall-verify-displayed"

if [ -z "${SSH_CONNECTION:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ -f "$DISPLAY_MARKER" ]; then
    rm -f "$DISPLAY_HELPER" 2>/dev/null || true
    return 0 2>/dev/null || exit 0
fi

if [ -s "$VERIFY_LOG" ]; then
    echo ""
    echo -e "\033[36m--- PVE9 POST-INSTALL VERIFICATION REPORT ---\033[0m"
    cat "$VERIFY_LOG"
    echo ""
    touch "$DISPLAY_MARKER" 2>/dev/null || true
    rm -f "$DISPLAY_HELPER" 2>/dev/null || true
    return 0 2>/dev/null || exit 0
fi

echo ""
echo -e "\033[33mPVE9 post-install verification report is not ready yet.\033[0m"
echo -e "\033[33mIt will be displayed automatically on your next SSH login.\033[0m"
echo -e "\033[33mManual check: cat /var/log/pve9-postinstall-verify.log\033[0m"
echo ""

return 0 2>/dev/null || exit 0
EOF

chmod +x /etc/profile.d/pve-postinstall-verify-display.sh

# --- 61. COMPLETION MARKER ---
# Creates a marker so future runs are detected as non-fresh and safely blocked.
cat <<EOF > "$COMPLETED_MARKER"
PVE9 Post Install completed on: $(date)
Hostname: $(hostname)
EOF

msg_ok "AUTO-VERIFY GHOST SCRIPT CREATED"

# --- 62. COMPLETE / SAFER REBOOT COUNTDOWN ---
# Shows blue flashing 30-second countdown. SPACE stops countdown and leaves reboot for manual action.
if timed_reboot_countdown 30; then
    reboot
fi

exit 0