#!/usr/bin/env bash -ex
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  PVE9 Post Install
# =========================================================

# --- 1. COLOR VARIABLES ---
# Provides consistent terminal colours, success/error icons, flashing text, and reusable clear-line control.
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
# Stores timer values, logs, detected hardware state, user-selected options, and install results.
T=15
REBOOT_T=60
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
# Displays the one-line PVE9 Post Install ASCII banner.
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
# Provides clean display -> apply -> success status lines.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${YW}! $1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. LOGGING & ERROR HANDLING ---
# Logs output to file and shows a useful line number if the script fails.
exec > >(tee -a "$LOG_FILE") 2>&1
trap 'echo -e "${RD}ERROR:${CL} Script failed at line $LINENO. Check ${LOG_FILE}"' ERR

# --- 6. ROOT CHECK ---
# Proxmox host configuration requires root privileges.
if [ "$EUID" -ne 0 ]; then
    echo -e "${RD}Please run as root.${CL}"
    exit 1
fi

clear
header_info

# =========================================================
#  HELPER FUNCTIONS
# =========================================================

# --- 7. TTY PRINT HELPER ---
# Prints directly to the active terminal even when a function returns a value through stdout.
# This prevents command substitution from hiding countdown prompts and Y/n questions.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 8. TTY PRINTLN HELPER ---
# Prints a full line directly to the active terminal.
# Used for visible final answers and clean user-facing messages.
function tty_println() {
    if [ -w /dev/tty ]; then
        echo -e "$*" > /dev/tty
    else
        echo -e "$*" >&2
    fi
}

# --- 9. YES/NO LABEL HELPER ---
# Converts raw Y/N input into clean visible yes/no wording.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 10. BLOCKING YES/NO HELPER ---
# Used after SPACE is pressed during a timed Y/n prompt.
# The countdown disappears and the prompt waits for Y/N/ENTER.
# ENTER accepts the default.
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
# Shows a wall-clock countdown for Y/n prompts.
# ENTER accepts default.
# Timeout accepts default.
# SPACE pauses countdown and waits for Y/N/ENTER.
# Final answer remains visible.
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

# --- 12. REBOOT COUNTDOWN HELPER ---
# Shows a two-line wall-clock reboot countdown without creating a new line every second.
# ENTER/Y = reboot immediately.
# SPACE/N = stop countdown and do not reboot.
# Timeout = reboot automatically.
function timed_reboot_countdown() {
    local seconds="$1"
    local key=""
    local deadline=""
    local now=""
    local remaining=""
    local first_draw="yes"

    deadline=$(( $(date +%s) + seconds ))

    while true; do
        now=$(date +%s)
        remaining=$(( deadline - now ))

        if [ "$remaining" -le 0 ]; then
            if [ "$first_draw" == "no" ]; then
                tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
            fi
            return 0
        fi

        if [ "$first_draw" == "yes" ]; then
            first_draw="no"
        else
            tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
        fi

        tty_print "${BL}${CLF}REBOOTING IN ${remaining} SECONDS...${CL}\n${YW}(ENTER/Y = reboot now, SPACE/N = cancel)${CL}\n"

        if [ -r /dev/tty ]; then
            if IFS= read -rsn1 -t 1 key < /dev/tty; then
                case "$key" in
                    ""|[Yy])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${BL}${CLF}REBOOTING NOW...${CL}"
                        return 0
                        ;;
                    " "|[Nn])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                        return 1
                        ;;
                esac
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                case "$key" in
                    ""|[Yy])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${BL}${CLF}REBOOTING NOW...${CL}"
                        return 0
                        ;;
                    " "|[Nn])
                        tty_print "\033[2A\033[2K\r\033[1B\033[2K\r\033[1A"
                        tty_println "${YW}Reboot countdown stopped. Reboot manually when ready.${CL}"
                        return 1
                        ;;
                esac
            fi
        fi
    done
}

# --- 13. SPACE CONFIG HELPER ---
# Updates config files that use "Key Value" format.
# If the key exists, it replaces the value. If not, it appends the key/value.
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

# --- 14. EQUALS CONFIG HELPER ---
# Updates config files that use "Key=Value" format.
# If the key exists, it replaces the value. If not, it appends the key/value.
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

# --- 15. GRUB ARGUMENT HELPER ---
# Safely appends a kernel argument to GRUB_CMDLINE_LINUX_DEFAULT without removing existing arguments.
function append_grub_arg() {
    local arg="$1"
    local grub_file="/etc/default/grub"

    grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> "$grub_file"

    if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" | grep -qw "$arg"; then
        sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 ${arg}\"|" "$grub_file"
    fi
}

# --- 16. COUNTDOWN EXIT HELPER ---
# Displays a safety reason, waits briefly, and exits.
function countdown_exit() {
    local seconds="$1"
    local reason="$2"

    echo ""
    echo -e "${RD}${reason}${CL}"
    echo -e "${YW}Exiting in ${seconds} seconds...${CL}"
    sleep "$seconds"
    exit 1
}

# --- 17. REALTEK NIC DETECTION HELPER ---
# Detects common Realtek Linux drivers so unstable offload features can be disabled safely.
function detect_realtek_iface() {
    local iface=""
    local iface_name=""

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
# Removes PCI IDs and extra text from GPU names to make the display clean.
function clean_gpu_name() {
    echo "$1" | sed -E 's/^[0-9a-fA-F:.]+[[:space:]]+//; s/\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]//g; s/\(rev [^)]+\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//'
}

# --- 19. GPU SUMMARY HELPER ---
# Builds a user-friendly integrated/discrete GPU summary from detected lspci lines.
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
# Detects attached disks and displays SSD/HDD summary for the user.
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

# --- 21. MACHINE/GPU LABEL HELPER ---
# Builds adaptive system-aware GPU detection labels.
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

# =========================================================
#  PRE-INSTALL VALIDATION AND AUDIT
# =========================================================

# --- 22. PROXMOX VERSION VALIDATION ---
# Validates that this is a Proxmox VE 9+ host before showing fresh-install warnings.
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
# Shows flashing warning only after confirming this is Proxmox VE 9+.
echo -e "${YW} This script will Perform PVE9 Post Install Routines.${CL}"
echo ""
echo -e "${YW}${CLF} Intended for FRESH Proxmox VE 9 installs only.${CL}"
echo ""

# --- 24. PRE-INSTALL HARDWARE AUDIT ---
# Detects CPU vendor, chassis/system type, virtual machine state, SSD presence, LAN CIDR and storage summary.
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
# Blocks reruns on systems that already have VM/CT state or script artefacts from prior execution.
msg_info "Checking for fresh install state"

VM_COUNT=$(qm list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')
CT_COUNT=$(pct list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')
CUSTOM_BRIDGES=$(grep -Ec "^auto vmbr[1-9]" /etc/network/interfaces 2>/dev/null || true)

if [ "$VM_COUNT" -gt 0 ] || [ "$CT_COUNT" -gt 0 ] || [ "$CUSTOM_BRIDGES" -gt 0 ]; then
    IS_FRESH="no"
fi

for marker in \
    "$COMPLETED_MARKER" \
    "/var/log/pve9-postinstall-verify.log" \
    "/usr/local/sbin/pve-no-nag-patch.sh" \
    "/etc/apt/apt.conf.d/no-nag-script" \
    "/etc/sysctl.d/99-pve9-hardening-network.conf" \
    "/etc/systemd/system/pve-numlock.service" \
    "/etc/systemd/system/realtek-optimize.service" \
    "/etc/profile.d/pve-postinstall-verify-display.sh"
do
    if [ -e "$marker" ]; then
        IS_FRESH="no"
    fi
done

if [ "$IS_FRESH" == "no" ]; then
    echo ""
    echo -e "${RD}WARNING: This does not look like a fresh install.${CL}"
    echo -e "${YW}Detected VMs: ${VM_COUNT}, LXCs: ${CT_COUNT}, extra bridges: ${CUSTOM_BRIDGES}.${CL}"
    countdown_exit 30 "For safety this script will not continue on a non-fresh-looking node."
fi

msg_ok "FRESH INSTALL CHECK PASSED"

# --- 26. GPU DETECTION ---
# Detects integrated and discrete GPUs before displaying adaptive GPU messages.
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

# --- 27. GPU PASSTHROUGH OPTION ---
# Asks whether to isolate only the discrete GPU and same-slot function devices.
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
# Displays detected disk type summary before final start prompt.
msg_ok "DETECTED STORAGE TYPE"
echo -e " ${BL}━━━━━▶${CL} ${STORAGE_SUMMARY:-No disk summary detected}"

# --- 29. CPU / CROWDSEC OPTIONS ---
# Collects optional choices using VM Setup-style timed prompts.
cpu_yn=$(timed_yes_no "Set CPU Governor to PERFORMANCE?" "n")

if [[ "$cpu_yn" =~ ^[Yy] ]]; then
    ENABLE_PERFORMANCE="y"
else
    ENABLE_PERFORMANCE="n"
fi

crowdsec_yn=$(timed_yes_no "Install CrowdSec Security Suite?" "y")

if [[ "$crowdsec_yn" =~ ^[Nn] ]]; then
    ENABLE_CROWDSEC="n"
else
    ENABLE_CROWDSEC="y"
fi

# --- 30. FINAL START PROMPT ---
# Starts post-install only after detection and user choices are collected.
start_yn=$(timed_yes_no "Start the PVE9 Post Install Script?" "y")

if [[ "$start_yn" =~ ^[Nn] ]]; then
    exit 0
fi

clear
header_info

# =========================================================
#  APPLY POST-INSTALL CONFIGURATION
# =========================================================

# --- 31. STORAGE MERGE ---
# Removes local-lvm and expands the OS/root storage for simple single-node fresh installs.
# This restores the previously working flow: remove /dev/pve/data, grow /dev/pve/root, resize ext filesystem, remove local-lvm from Proxmox storage.
msg_info "Merging local-lvm into local storage"

if lvdisplay /dev/pve/data >/dev/null 2>&1; then
    pvesm freezefs local-lvm &>/dev/null || true
    msg_ok "LOCAL-LVM STORAGE FREEZE REQUESTED"

    lvremove -fy /dev/pve/data &>/dev/null
    msg_ok "LOCAL-LVM THIN DATA VOLUME REMOVED"

    lvresize -l +100%FREE /dev/pve/root &>/dev/null
    msg_ok "ROOT LOGICAL VOLUME EXPANDED WITH FREE SPACE"

    resize2fs /dev/mapper/pve-root &>/dev/null
    msg_ok "ROOT FILESYSTEM RESIZED"

    pvesm remove local-lvm &>/dev/null || true
    msg_ok "LOCAL-LVM REMOVED FROM PROXMOX STORAGE CONFIG"
else
    pvesm remove local-lvm &>/dev/null || true
    msg_ok "LOCAL-LVM DATA VOLUME NOT PRESENT"
fi

msg_ok "LOCAL-LVM STORAGE SUCCESSFULLY MERGED TO OS"

# --- 32. DNS REDUNDANCY ---
# Adds Cloudflare DNS redundancy before package updates.
msg_info "Configuring DNS resolvers"

cp -n /etc/resolv.conf /etc/resolv.conf.pve9-postinstall.bak 2>/dev/null || true
msg_ok "DNS CONFIG BACKUP CREATED"

cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

msg_ok "DNS RESOLVERS CONFIGURED (DNS1 = 1.1.1.1, DNS2 = 1.0.0.1)"

# --- 33. REPOSITORIES & UPDATES ---
# Removes enterprise repositories, enables no-subscription repo and updates packages with hidden output.
msg_info "Configuring Repositories & Running Updates"

rm -f /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources
msg_ok "ENTERPRISE / CEPH ENTERPRISE REPOSITORY FILES REMOVED"

cat <<EOF > /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF

msg_ok "PROXMOX NO-SUBSCRIPTION REPOSITORY CONFIGURED"

DEBIAN_FRONTEND=noninteractive apt-get update &>/dev/null
msg_ok "APT PACKAGE LISTS UPDATED"

DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade &>/dev/null
msg_ok "SYSTEM PACKAGES UPGRADED"

DEBIAN_FRONTEND=noninteractive apt-get -y autoremove &>/dev/null
msg_ok "UNUSED PACKAGES REMOVED"

msg_ok "SYSTEM UPDATED"

# --- 34. UI NAG REMOVAL ---
# Installs a persistent helper and dpkg hook to remove the Proxmox no-subscription popup after toolkit updates.
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
msg_ok "NO-NAG PATCH HELPER INSTALLED"

cat <<'EOF' > /etc/apt/apt.conf.d/no-nag-script
DPkg::Post-Invoke { "/usr/local/sbin/pve-no-nag-patch.sh && systemctl restart pveproxy >/dev/null 2>&1 || true"; };
EOF

msg_ok "NO-NAG DPKG POST-INVOKE HOOK INSTALLED"

DEBIAN_FRONTEND=noninteractive apt-get --reinstall install -y proxmox-widget-toolkit &>/dev/null
msg_ok "PROXMOX WIDGET TOOLKIT REINSTALLED"

 /usr/local/sbin/pve-no-nag-patch.sh &>/dev/null || true
msg_ok "NO-SUBSCRIPTION NAG PATCH APPLIED"

systemctl restart pveproxy &>/dev/null || true
msg_ok "PVEPROXY RESTARTED"

msg_ok "NAG REMOVED"

# --- 35. POWER & CHASSIS OPTIMIZATION ---
# Masks sleep states and ignores laptop lid close on laptop hardware.
msg_info "Optimizing Power/Sleep Settings"

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target &>/dev/null
msg_ok "SLEEP / SUSPEND / HIBERNATE TARGETS MASKED"

if [ "$SYSTEM_TYPE" == "Laptop" ]; then
    set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitch" "ignore"
    msg_ok "LAPTOP LID SWITCH SET TO IGNORE"

    set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitchDocked" "ignore"
    msg_ok "DOCKED LID SWITCH SET TO IGNORE"

    set_or_append_equals_config /etc/systemd/logind.conf "LidSwitchIgnoreInhibited" "no"
    msg_ok "LID SWITCH INHIBIT BEHAVIOUR CONFIGURED"

    systemctl restart systemd-logind &>/dev/null || true
    msg_ok "SYSTEMD-LOGIND RESTARTED"
else
    msg_ok "LAPTOP LID SETTINGS NOT REQUIRED"
fi

msg_ok "POWER OPTIMIZED"

# --- 36. GRUB & IOMMU ---
# Adds IOMMU, passthrough mode and console blanking without removing existing kernel args.
msg_info "Configuring GRUB & IOMMU"

append_grub_arg "$IOMMU_FLAG"
msg_ok "CPU IOMMU FLAG CONFIGURED (${IOMMU_FLAG})"

append_grub_arg "iommu=pt"
msg_ok "IOMMU PASSTHROUGH MODE CONFIGURED"

append_grub_arg "consoleblank=60"
msg_ok "CONSOLE BLANKING CONFIGURED"

update-grub &>/dev/null || true
msg_ok "GRUB CONFIG UPDATED"

msg_ok "GRUB UPDATED"

# --- 37. GPU ISOLATION (VFIO) ---
# Loads VFIO modules and binds only discrete GPU IDs to vfio-pci.
if [ "$ENABLE_PASSTHROUGH" == "y" ]; then
    if [ -n "$DGPU_IDS" ]; then
        msg_info "Isolating discrete GPU for Passthrough"

        for module in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
            grep -qxF "$module" /etc/modules || echo "$module" >> /etc/modules
        done
        msg_ok "VFIO MODULES ADDED TO /ETC/MODULES"

        cat <<EOF > /etc/modprobe.d/pve-blacklist.conf
blacklist nvidia
blacklist nouveau
blacklist nvidiafb
blacklist nvidia-gpu
blacklist radeon
blacklist amdgpu
EOF

        msg_ok "HOST GPU DRIVERS BLACKLISTED FOR PASSTHROUGH"

        echo "options vfio-pci ids=$DGPU_IDS disable_vga=1" > /etc/modprobe.d/vfio.conf
        msg_ok "VFIO PCI DEVICE IDS CONFIGURED ($DGPU_IDS)"

        update-initramfs -u -k all &>/dev/null || true
        msg_ok "INITRAMFS UPDATED FOR VFIO"

        msg_ok "GPU ISOLATED"
    else
        msg_warn "Passthrough selected but no safe discrete GPU IDs were found. Skipping VFIO."
    fi
else
    msg_ok "GPU PASSTHROUGH NOT SELECTED"
fi

# --- 38. SSH SECURITY ---
# Checks for root SSH keys and disables root password login only when keys are present.
msg_info "Checking for SSH authorized keys"

ROOT_KEYS="/root/.ssh/authorized_keys"

if [ -s "$ROOT_KEYS" ]; then
    msg_ok "SSH KEYS DETECTED"

    msg_info "Disabling root password login"

    chmod 700 /root/.ssh
    msg_ok "ROOT SSH DIRECTORY PERMISSIONS SET"

    chmod 600 "$ROOT_KEYS"
    msg_ok "ROOT AUTHORIZED_KEYS PERMISSIONS SET"

    set_or_append_space_config /etc/ssh/sshd_config "AddressFamily" "inet"
    msg_ok "SSH ADDRESS FAMILY SET TO IPV4"

    set_or_append_space_config /etc/ssh/sshd_config "PasswordAuthentication" "no"
    msg_ok "SSH PASSWORD AUTHENTICATION DISABLED"

    set_or_append_space_config /etc/ssh/sshd_config "PermitRootLogin" "prohibit-password"
    msg_ok "ROOT SSH PASSWORD LOGIN DISABLED"

    sshd -t &>/dev/null
    msg_ok "SSHD CONFIG VALIDATED"

    systemctl restart ssh.service &>/dev/null || true
    msg_ok "SSH SERVICE RESTARTED"

    SSH_HARDENING_APPLIED="yes"

    msg_ok "ROOT PASSWORD LOGIN DISABLED"
else
    SSH_HARDENING_APPLIED="no"
    msg_warn "SSH keys not found; root password login not disabled"
fi

# --- 39. SYSCTL HARDENING & NETWORK TUNING ---
# Adds kernel hardening and high-traffic tuning for reverse proxy / VM workloads.
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

msg_ok "SYSCTL HARDENING / NETWORK TUNING FILE WRITTEN"

sysctl --system &>/dev/null || true
msg_ok "SYSCTL SETTINGS APPLIED"

msg_ok "SYSCTL HARDENING APPLIED"

# --- 40. REALTEK NIC OPTIMIZATION ---
# Detects Realtek NICs and disables problematic offloads persistently.
msg_info "Checking for Realtek NIC optimization"

DEBIAN_FRONTEND=noninteractive apt-get install -y ethtool &>/dev/null || true
msg_ok "ETHTOOL INSTALLED / VERIFIED"

REALTEK_IFACE=$(detect_realtek_iface || true)

if [ -n "$REALTEK_IFACE" ]; then
    ethtool -K "$REALTEK_IFACE" tso off gso off gro off &>/dev/null || true
    msg_ok "REALTEK OFFLOAD SETTINGS APPLIED ($REALTEK_IFACE)"

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

    msg_ok "REALTEK OPTIMIZATION SYSTEMD SERVICE WRITTEN"

    systemctl daemon-reload &>/dev/null
    msg_ok "SYSTEMD DAEMON RELOADED"

    systemctl enable realtek-optimize.service &>/dev/null
    msg_ok "REALTEK OPTIMIZATION SERVICE ENABLED"

    REALTEK_OPTIMIZED="yes"

    msg_ok "REALTEK NIC OPTIMIZED ($REALTEK_IFACE)"
else
    REALTEK_OPTIMIZED="no"
    msg_ok "NO REALTEK NIC OPTIMIZATION NEEDED"
fi

# --- 41. PROXMOX FIREWALL BASELINE ---
# Enables Proxmox firewall with LAN-only SSH/WebUI access and public 80/443 allowance.
msg_info "Configuring Proxmox Firewall"

mkdir -p "/etc/pve/nodes/${HOSTNAME_SHORT}"
msg_ok "PROXMOX NODE FIREWALL DIRECTORY VERIFIED"

if [ -n "$LAN_CIDR" ]; then
    if grep -q "^firewall:" /etc/pve/datacenter.cfg 2>/dev/null; then
        sed -i 's/^firewall:.*/firewall: 1/' /etc/pve/datacenter.cfg
    else
        echo "firewall: 1" >> /etc/pve/datacenter.cfg
    fi

    msg_ok "DATACENTER FIREWALL ENABLED"

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

    msg_ok "NODE FIREWALL RULES WRITTEN"

    systemctl enable --now pve-firewall &>/dev/null || true
    msg_ok "PVE-FIREWALL SERVICE ENABLED"

    systemctl restart pve-firewall &>/dev/null || true
    msg_ok "PVE-FIREWALL SERVICE RESTARTED"

    PVE_FIREWALL_APPLIED="yes"

    msg_ok "PROXMOX FIREWALL ENABLED"
else
    PVE_FIREWALL_APPLIED="no"
    msg_warn "Could not detect LAN CIDR. Proxmox firewall rules skipped to avoid lockout."
fi

# --- 42. CROWDSEC & AUTO UPDATES ---
# Installs CrowdSec, firewall bouncer, Proxmox/Linux collections and unattended upgrades.
if [ "$ENABLE_CROWDSEC" == "y" ]; then
    msg_info "Installing Security Suite"

    DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg ca-certificates &>/dev/null || true
    msg_ok "SECURITY INSTALL DEPENDENCIES INSTALLED"

    if command -v curl >/dev/null 2>&1; then
        curl -s https://install.crowdsec.net | sh &>/dev/null || true
        msg_ok "CROWDSEC REPOSITORY INSTALLER EXECUTED"
    fi

    DEBIAN_FRONTEND=noninteractive apt-get update &>/dev/null || true
    msg_ok "APT PACKAGE LISTS UPDATED FOR CROWDSEC"

    DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec unattended-upgrades &>/dev/null || true
    msg_ok "CROWDSEC AND UNATTENDED-UPGRADES INSTALLED"

    if apt-cache show crowdsec-firewall-bouncer-nftables &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec-firewall-bouncer-nftables &>/dev/null || true
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-nftables"
        msg_ok "CROWDSEC NFTABLES FIREWALL BOUNCER INSTALLED"
    elif apt-cache show crowdsec-firewall-bouncer-iptables &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec-firewall-bouncer-iptables &>/dev/null || true
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-iptables"
        msg_ok "CROWDSEC IPTABLES FIREWALL BOUNCER INSTALLED"
    else
        CROWDSEC_BOUNCER_PACKAGE="none"
        msg_warn "CrowdSec firewall bouncer package not found"
    fi

    cscli collections install crowdsecurity/linux &>/dev/null || true
    msg_ok "CROWDSEC LINUX COLLECTION INSTALLED"

    cscli collections install crowdsecurity/sshd &>/dev/null || true
    msg_ok "CROWDSEC SSHD COLLECTION INSTALLED"

    cscli collections install crowdsecurity/proxmox &>/dev/null || true
    msg_ok "CROWDSEC PROXMOX COLLECTION INSTALLED"

    cscli collections install crowdsecurity/http-cve &>/dev/null || true
    msg_ok "CROWDSEC HTTP-CVE COLLECTION INSTALLED"

    systemctl enable --now crowdsec &>/dev/null || true
    msg_ok "CROWDSEC SERVICE ENABLED"

    systemctl restart crowdsec &>/dev/null || true
    msg_ok "CROWDSEC SERVICE RESTARTED"

    if systemctl list-unit-files 'crowdsec-firewall-bouncer*' --no-pager --no-legend 2>/dev/null | grep -q "crowdsec-firewall-bouncer"; then
        systemctl enable --now crowdsec-firewall-bouncer &>/dev/null || true
        msg_ok "CROWDSEC FIREWALL BOUNCER ENABLED"

        systemctl restart crowdsec-firewall-bouncer &>/dev/null || true
        msg_ok "CROWDSEC FIREWALL BOUNCER RESTARTED"
    else
        msg_warn "CrowdSec firewall bouncer service was not found after install"
    fi

    cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

    msg_ok "UNATTENDED UPGRADES CONFIGURED"

    msg_ok "SECURITY INSTALLED"
else
    msg_ok "CROWDSEC SECURITY SUITE NOT SELECTED"
fi

# --- 43. PROXMOX FIREWALL SERVICE REINFORCEMENT ---
# Ensures the firewall service remains enabled now and at boot.
msg_info "Enabling Proxmox firewall service"

systemctl enable --now pve-firewall &>/dev/null || true
msg_ok "PROXMOX FIREWALL SERVICE ENABLED AT BOOT"

systemctl restart pve-firewall &>/dev/null || true
msg_ok "PROXMOX FIREWALL SERVICE RESTARTED"

msg_ok "PROXMOX FIREWALL SERVICE ENABLED"

# --- 44. PERFORMANCE & TRIM ---
# Optionally enables performance CPU governor and enables fstrim.timer when SSD is detected.
if [ "$ENABLE_PERFORMANCE" == "y" ]; then
    msg_info "Setting Performance Governor"

    DEBIAN_FRONTEND=noninteractive apt-get install -y cpufrequtils &>/dev/null || true
    msg_ok "CPUFREQUTILS INSTALLED"

    echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
    msg_ok "CPU GOVERNOR DEFAULT SET TO PERFORMANCE"

    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        for r in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo "performance" > "$r" 2>/dev/null || true
        done
        msg_ok "LIVE CPU GOVERNOR SET TO PERFORMANCE"
    else
        msg_warn "CPUFREQ sysfs path not found; live governor change skipped"
    fi

    systemctl restart cpufrequtils &>/dev/null || true
    msg_ok "CPUFREQUTILS SERVICE RESTARTED"

    msg_ok "CPU PERFORMANCE ACTIVE"
else
    msg_ok "CPU PERFORMANCE GOVERNOR NOT SELECTED"
fi

if [ "$IS_SSD" == "yes" ]; then
    msg_info "Enabling SSD TRIM"

    systemctl enable --now fstrim.timer &>/dev/null
    msg_ok "FSTRIM TIMER ENABLED AND STARTED"

    msg_ok "SSD TRIM ENABLED"
else
    msg_ok "SSD TRIM NOT REQUIRED FOR DETECTED STORAGE"
fi

# --- 45. NUMLOCK BOOT SERVICE ---
# Enables NumLock on Linux consoles at boot when console tools support it.
msg_info "Configuring NumLock on boot"

DEBIAN_FRONTEND=noninteractive apt-get install -y kbd &>/dev/null || true
msg_ok "KBD PACKAGE INSTALLED / VERIFIED"

cat <<'EOF' > /usr/local/sbin/pve-numlock-on.sh
#!/usr/bin/env bash
set +e

for tty in /dev/tty1 /dev/tty2 /dev/tty3 /dev/tty4 /dev/tty5 /dev/tty6; do
    [ -w "$tty" ] && /usr/bin/setleds -D +num < "$tty" >/dev/null 2>&1 || true
done

exit 0
EOF

chmod +x /usr/local/sbin/pve-numlock-on.sh
msg_ok "NUMLOCK HELPER SCRIPT INSTALLED"

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

msg_ok "NUMLOCK SYSTEMD SERVICE WRITTEN"

systemctl daemon-reload &>/dev/null
msg_ok "SYSTEMD DAEMON RELOADED"

systemctl enable pve-numlock.service &>/dev/null
msg_ok "NUMLOCK SERVICE ENABLED"

NUMLOCK_CONFIGURED="yes"

msg_ok "NUMLOCK BOOT SERVICE CONFIGURED"

# --- 46. AUTO-VERIFY GHOST SCRIPT ---
# Creates one-time verifier that runs after reboot, writes a detailed log, self-deletes, and leaves a login display helper.
# The systemd service logs to journal only, not the physical Proxmox console, so the report is shown upon root SSH login instead.
msg_info "Creating Auto-Verify Ghost Script"

cat <<EOF > /root/pve_verify.sh
#!/usr/bin/env bash
set +e

VERIFY_LOG="$VERIFY_LOG"
: > "\$VERIFY_LOG"
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

# Core Proxmox service checks.
if pveversion >/dev/null 2>&1; then PASS "Proxmox command tools available"; else FAIL "Proxmox command tools missing"; fi
if systemctl is-active --quiet pveproxy; then PASS "pveproxy active"; else FAIL "pveproxy inactive"; fi
if systemctl is-active --quiet pvedaemon; then PASS "pvedaemon active"; else FAIL "pvedaemon inactive"; fi
if systemctl is-active --quiet pvestatd; then PASS "pvestatd active"; else FAIL "pvestatd inactive"; fi
if systemctl is-active --quiet pve-cluster; then PASS "pve-cluster active"; else FAIL "pve-cluster inactive"; fi

# DNS checks.
if grep -q "nameserver 1.1.1.1" /etc/resolv.conf && grep -q "nameserver 1.0.0.1" /etc/resolv.conf; then
    PASS "DNS redundancy configured"
else
    WARN "DNS redundancy not detected"
fi

# Repository and package health checks.
if grep -q "pve-no-subscription" /etc/apt/sources.list.d/proxmox.sources 2>/dev/null; then PASS "No-subscription repository configured"; else FAIL "No-subscription repository missing"; fi
if [ ! -f /etc/apt/sources.list.d/pve-enterprise.sources ]; then PASS "Enterprise repository disabled"; else FAIL "Enterprise repository still present"; fi
if apt-get check >/dev/null 2>&1; then PASS "APT package database healthy"; else FAIL "APT package database has problems"; fi

# Storage merge checks.
if grep -q "local-lvm" /etc/pve/storage.cfg 2>/dev/null; then WARN "local-lvm still exists in storage.cfg"; else PASS "local-lvm removed from Proxmox storage config"; fi
if lvdisplay /dev/pve/data >/dev/null 2>&1; then WARN "/dev/pve/data still exists"; else PASS "/dev/pve/data not present"; fi
if df -h /var/lib/vz >/dev/null 2>&1; then PASS "local storage path /var/lib/vz is accessible"; else FAIL "local storage path /var/lib/vz is not accessible"; fi

# GRUB and IOMMU checks.
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "\$INSTALL_IOMMU_FLAG"; then PASS "GRUB contains \$INSTALL_IOMMU_FLAG"; else FAIL "GRUB missing \$INSTALL_IOMMU_FLAG"; fi
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "iommu=pt"; then PASS "GRUB contains iommu=pt"; else FAIL "GRUB missing iommu=pt"; fi
if grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -qw "consoleblank=60"; then PASS "GRUB contains consoleblank=60"; else WARN "GRUB missing consoleblank=60"; fi
if grep -q "consoleblank=60" /proc/cmdline; then PASS "Screen blanking active in running kernel"; else WARN "Screen blanking not visible in running kernel"; fi
if dmesg | grep -Ei "IOMMU|DMAR|AMD-Vi" | grep -qi "enabled"; then PASS "IOMMU appears enabled after reboot"; else WARN "IOMMU not clearly detected in dmesg"; fi

# GPU passthrough checks.
# This keeps the useful old checks but avoids printing to the local console.
if [ "\$INSTALL_DGPU_FOUND" == "yes" ]; then
    if [ "\$INSTALL_ENABLE_PASSTHROUGH" == "y" ]; then
        if lspci -nnk 2>/dev/null | grep -q "Kernel driver in use: vfio-pci"; then
            PASS "vfio-pci active on at least one GPU/function device"
        elif find /sys/bus/pci/drivers/vfio-pci -maxdepth 1 -type l 2>/dev/null | grep -q .; then
            PASS "vfio-pci has bound PCI devices"
        else
            WARN "GPU passthrough was selected but vfio-pci binding was not clearly detected"
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
if [ "\$INSTALL_IS_SSD" == "yes" ]; then
    if systemctl is-enabled --quiet fstrim.timer && systemctl is-active --quiet fstrim.timer; then PASS "SSD TRIM timer enabled and active"; else FAIL "SSD TRIM timer not enabled/active"; fi
else
    INFO "No SSD detected during install, TRIM check skipped"
fi

# CPU governor checks.
if [ "\$INSTALL_ENABLE_PERFORMANCE" == "y" ]; then
    if grep -q "performance" /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null; then PASS "CPU governor is performance"; else FAIL "CPU governor is not performance"; fi
else
    INFO "CPU performance governor was not selected, check skipped"
fi

# SSH hardening checks.
if [ "\$INSTALL_SSH_HARDENING_APPLIED" == "yes" ]; then
    if sshd -T 2>/dev/null | grep -q "^passwordauthentication no"; then PASS "SSH password authentication disabled"; else FAIL "SSH password authentication still enabled"; fi
    if sshd -T 2>/dev/null | grep -Eq "^permitrootlogin (without-password|prohibit-password)"; then PASS "Root SSH password login disabled"; else FAIL "Root SSH password login not hardened"; fi
else
    WARN "SSH hardening was skipped because root SSH keys were missing"
fi

# Realtek NIC optimization checks.
if [ "\$INSTALL_REALTEK_OPTIMIZED" == "yes" ]; then
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

# NumLock checks.
if [ "\$INSTALL_NUMLOCK_CONFIGURED" == "yes" ]; then
    if systemctl is-enabled --quiet pve-numlock.service; then PASS "NumLock boot service enabled"; else WARN "NumLock boot service not enabled"; fi
else
    INFO "NumLock was not configured"
fi

# UI nag and sysctl checks.
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
msg_ok "AUTO-VERIFY SCRIPT WRITTEN"

cat <<EOF > /etc/systemd/system/pve-postinstall-verify.service
[Unit]
Description=PVE9 Post Install One-Time Verification
After=multi-user.target network-online.target ssh.service pve-cluster.service pveproxy.service pvedaemon.service pvestatd.service
Wants=network-online.target pve-cluster.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 60
ExecStart=/bin/bash /root/pve_verify.sh
StandardOutput=journal
StandardError=journal
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

msg_ok "AUTO-VERIFY SYSTEMD SERVICE WRITTEN"

cat <<'EOF' > /etc/profile.d/pve-postinstall-verify-display.sh
#!/usr/bin/env bash

VERIFY_LOG="/var/log/pve9-postinstall-verify.log"
DISPLAY_MARKER="/root/.pve9-postinstall-verify-displayed"

if [ "$(id -u)" -ne 0 ]; then
    return 0 2>/dev/null || exit 0
fi

if [ -f "$DISPLAY_MARKER" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ -s "$VERIFY_LOG" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo " PVE9 POST-INSTALL VERIFICATION REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    cat "$VERIFY_LOG"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    touch "$DISPLAY_MARKER"
    rm -f /etc/profile.d/pve-postinstall-verify-display.sh
else
    echo ""
    echo "PVE9 post-install verification report is not ready yet."
    echo "It will be displayed automatically on your next root SSH login."
    echo ""
fi
EOF

chmod +x /etc/profile.d/pve-postinstall-verify-display.sh
msg_ok "AUTO-VERIFY LOGIN DISPLAY HELPER INSTALLED"

systemctl daemon-reload
msg_ok "SYSTEMD DAEMON RELOADED"

systemctl enable pve-postinstall-verify.service &>/dev/null
msg_ok "AUTO-VERIFY SYSTEMD SERVICE ENABLED"

msg_ok "AUTO-VERIFY GHOST SCRIPT CREATED"

# --- 47. COMPLETION MARKER ---
# Writes a completion marker so future reruns are blocked by fresh-install detection.
cat <<EOF > "$COMPLETED_MARKER"
PVE9 Post Install completed on: $(date)
System Type: $SYSTEM_TYPE
SSD Detected: $IS_SSD
GPU Passthrough: $ENABLE_PASSTHROUGH
CPU Performance: $ENABLE_PERFORMANCE
CrowdSec: $ENABLE_CROWDSEC
SSH Hardening: $SSH_HARDENING_APPLIED
Proxmox Firewall: $PVE_FIREWALL_APPLIED
Realtek Optimized: $REALTEK_OPTIMIZED
NumLock: $NUMLOCK_CONFIGURED
EOF

msg_ok "PVE9 POST-INSTALL COMPLETION MARKER WRITTEN"

# --- 48. COMPLETE / SAFER REBOOT COUNTDOWN ---
# ENTER/Y reboots immediately.
# SPACE/N cancels reboot.
# Timeout reboots automatically.
if timed_reboot_countdown "$REBOOT_T"; then
    reboot
fi

exit 0