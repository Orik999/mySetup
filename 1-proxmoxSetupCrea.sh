#!/usr/bin/env bash
set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1
shopt -s inherit_errexit nullglob

# =========================================================
#  PVE9 Post Install
# =========================================================

# --- 1. COLOR VARIABLES ---
# Provides consistent terminal colours, success/error icons, flashing text, and reusable clear-line control.
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
FLASH_ON=$'\033[5m'
FLASH_OFF=$'\033[25m'
BORDER="${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"

SCRIPT_SOURCE="1-proxmoxSetupCrea.sh"
SCRIPT_VERSION="v1.2.0"
SCRIPT_UPDATED="2026-05-22"
SCRIPT_BUILD="audit-untimed-inputs-snapshot-storage"

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
DGPU_VENDOR_IDS=""
GPU_SUMMARY=""

STORAGE_SUMMARY=""
ROOT_FS_TYPE=""
ROOT_SOURCE=""

ENABLE_PASSTHROUGH="n"
ENABLE_PERFORMANCE="n"
ENABLE_CROWDSEC="y"
ALLOW_PUBLIC_WEB="n"

SSH_HARDENING_APPLIED="no"
SSH_ROOT_KEY_FILE=""
SSH_EFFECTIVE_AUTHORIZED_KEYS=""
SSH_EFFECTIVE_PERMIT_ROOT=""
SSH_EFFECTIVE_PASSWORD_AUTH=""
SSH_EFFECTIVE_PUBKEY_AUTH=""
SSH_EFFECTIVE_KBD_AUTH=""
PVE_FIREWALL_APPLIED="no"
CROWDSEC_BOUNCER_PACKAGE="none"
NUMLOCK_CONFIGURED="no"

STORAGE_LAYOUT_MODE="merge_all"
ROOT_DISK_SIZE_GB="0"
LOCAL_LVM_EXISTS="no"

TEMP_FILES=()

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

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
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- SCRIPT VERSION DISPLAY ---
# Prints the currently running script version immediately under the ASCII banner.
function show_script_version() {
    echo -e "${GN}SCRIPT VERSION: ${SCRIPT_VERSION} | UPDATED: ${SCRIPT_UPDATED} | BUILD: ${SCRIPT_BUILD}${CL}"
    echo -e "${BL}SOURCE: ${SCRIPT_SOURCE}${CL}"
}

# --- 5. SECTION HEADER HELPER ---
# Prevents messy repeated msg_info output by giving each major stage a clean heading.
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

# --- FLASHING SUCCESS SECTION HEADER HELPER ---
# Uses the standard final success layout with bold flashing green text.
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
# Prints directly to the active terminal even when a function returns a value through stdout.
# This prevents command substitution from hiding countdown prompts and Y/n questions.
function tty_print() {
    if [ -w /dev/tty ]; then
        echo -ne "$*" > /dev/tty
    else
        echo -ne "$*" >&2
    fi
}

# --- 7. TTY PRINTLN HELPER ---
# Prints a full line directly to the active terminal.
# Used for visible final answers and clean user-facing messages.
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
# Removes temporary files created by run_cmd error capture.
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
}

# --- 10. COMMAND RUNNER ---
# Runs critical commands quietly, but shows real stderr if they fail.
# Use this for boot-critical or host-critical commands that must not silently fail.
function run_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    if ! "$@" > /dev/null 2> "$err_file"; then
        echo ""
        echo -e "${RD}Command failed during:${CL} ${description}"
        echo -e "${YW}Command:${CL} $*"
        echo ""
        echo -e "${RD}Real error:${CL}"
        cat "$err_file"
        rm -f "$err_file"
        exit 1
    fi

    rm -f "$err_file"
}

# --- 11. OPTIONAL COMMAND RUNNER ---
# Runs non-critical commands quietly and never stops the script.
function run_optional() {
    "$@" > /dev/null 2>&1 || true
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 12. YES/NO LABEL HELPER ---
# Converts raw Y/N input into clean visible yes/no wording.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 13. BLOCKING YES/NO HELPER ---
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

# --- 14. TIMED YES/NO PROMPT HELPER ---
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

# --- 15. REBOOT COUNTDOWN HELPER ---
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

        tty_print "${BL}${CLF}REBOOTING IN ${remaining} SECONDS...${CL}\n${YW}(ENTER/Y = Reboot Now, SPACE/N = Cancel)${CL}\n"

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

# =========================================================
#  CONFIG HELPERS
# =========================================================

# --- 16. SPACE CONFIG HELPER ---
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

# --- 17. EQUALS CONFIG HELPER ---
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

# --- 18. GRUB ARGUMENT HELPER ---
# Safely appends a kernel argument to GRUB_CMDLINE_LINUX_DEFAULT without removing existing arguments.
function append_grub_arg() {
    local arg="$1"
    local grub_file="/etc/default/grub"

    grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" || echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >> "$grub_file"

    if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_file" | grep -qw "$arg"; then
        sed -i -E "s|^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"|\1 ${arg}\"|" "$grub_file"
    fi
}

# --- 19. COUNTDOWN EXIT HELPER ---
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

# =========================================================
#  HARDWARE DETECTION HELPERS
# =========================================================

# --- 20. PCI VENDOR NAME HELPER ---
# Converts PCI vendor IDs into readable vendor names without using lspci.
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

# --- 21. GPU TYPE CLASSIFIER ---
# Classifies GPUs using sysfs vendor/class/boot_vga instead of fragile lspci text matching.
# This avoids misclassifying AMD APUs as passthrough dGPUs on laptops.
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

# --- 22. SYSFS GPU DETECTION HELPER ---
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
    local gpu_slot=""
    local func=""
    local func_vendor=""
    local func_device=""
    local id=""

    GPU_ALL=""
    IGPU_LINES=""
    DGPU_LINES=""
    IGPU_FOUND="no"
    DGPU_FOUND="no"
    DGPU_IDS=""
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
            DGPU_FOUND="yes"
            DGPU_VENDOR_IDS+="${vendor} "

            gpu_slot="${bdf%.*}"

            for func in /sys/bus/pci/devices/${gpu_slot}.*; do
                [ -e "$func/vendor" ] || continue
                [ -e "$func/device" ] || continue

                func_vendor="$(cat "$func/vendor" 2>/dev/null || true)"
                func_device="$(cat "$func/device" 2>/dev/null || true)"
                id="${func_vendor#0x}:${func_device#0x}"

                if [[ "$id" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$ ]]; then
                    if [[ ",${DGPU_IDS}," != *",${id},"* ]]; then
                        DGPU_IDS+="${id},"
                    fi
                fi
            done
        fi
    done <<< "$gpu_records"

    DGPU_IDS="${DGPU_IDS%,}"
}

# --- 23. GPU SUMMARY HELPER ---
# Builds a user-friendly integrated/discrete GPU summary from detected sysfs records.
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

# --- 24. STORAGE SUMMARY HELPER ---
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

# --- 25. MACHINE/GPU LABEL HELPER ---
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

# --- 26. REALTEK NIC DETECTION HELPER ---
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

# =========================================================
#  VALIDATION / INITIALIZATION
# =========================================================

# --- 27. DEPENDENCY VALIDATION ---
# Validates critical commands early so failures happen before changes are made.
function validate_dependencies() {
    local required_commands=(
        apt-cache
        apt-get
        awk
        basename
        cat
        chmod
        cp
        curl
        cut
        date
        df
        env
        findmnt
        grep
        hostname
        ip
        lsblk
        lvdisplay
        lvremove
        lvresize
        mkdir
        pct
        pvesm
        qm
        reboot
        resize2fs
        rm
        sed
        sleep
        sort
        sshd
        stat
        sysctl
        systemctl
        tee
        touch
        update-grub
        update-initramfs
        vgs
        xargs
    )

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done
}

# --- 28. PROXMOX VERSION VALIDATION ---
# Validates that this is a Proxmox VE 9+ host before showing fresh-install warnings.
function validate_proxmox() {
    local pve_major=""

    if ! command -v pveversion >/dev/null 2>&1; then
        msg_error "This system is not Proxmox VE. Script cancelled."
    fi

    pve_major="$(pveversion | cut -d'/' -f2 | cut -d'.' -f1)"

    if ! [[ "$pve_major" =~ ^[0-9]+$ ]]; then
        msg_error "Could not detect Proxmox VE version. Script cancelled."
    fi

    if [ "$pve_major" -lt 9 ]; then
        msg_error "Requires Proxmox VE 9+. Detected Proxmox VE ${pve_major}. Script Cancelled."
    fi
}

# --- 29. SCRIPT INITIALIZATION ---
# Starts logging, installs traps, clears screen and validates root/proxmox/dependencies.
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
}

# =========================================================
#  PRE-INSTALL VALIDATION AND AUDIT
# =========================================================

# --- 30. FRESH INSTALL WARNING ---
# Shows flashing warning only after confirming this is Proxmox VE 9+.
function show_fresh_install_warning() {
    echo -e "${YW} This script will Perform PVE9 Post Install Routines.${CL}"
    echo ""
    echo -e "${YW}${CLF} Intended for FRESH Proxmox VE 9 installs only.${CL}"
    echo ""
}

# --- 31. PRE-INSTALL HARDWARE AUDIT ---
# Detects CPU vendor, chassis/system type, virtual machine state, SSD presence, LAN CIDR and storage summary.
function audit_hardware() {
    section "PRE-INSTALL HARDWARE AUDIT"

    msg_info "Auditing host hardware"

    CPU_TYPE="$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}' || true)"

    if [ "$CPU_TYPE" == "GenuineIntel" ]; then
        IOMMU_FLAG="intel_iommu=on"
    else
        IOMMU_FLAG="amd_iommu=on"
    fi

    if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet; then
        IS_VM="yes"
    fi

    if command -v dmidecode >/dev/null 2>&1; then
        CHASSIS="$(dmidecode -s chassis-type 2>/dev/null || echo "Unknown")"
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

    DEFAULT_IFACE="$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}' || true)"

    if [ -n "$DEFAULT_IFACE" ]; then
        LAN_CIDR="$(ip -o -4 addr show dev "$DEFAULT_IFACE" | awk '{print $4; exit}' || true)"
    fi

    STORAGE_SUMMARY="$(build_storage_summary)"
    ROOT_FS_TYPE="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"
    ROOT_SOURCE="$(findmnt -n -o SOURCE / 2>/dev/null || true)"

    msg_ok "HOST HARDWARE AUDITED"
}

# --- 32. FRESH INSTALL DETECTION ---
# Blocks reruns on systems that already have VM/CT state or script artefacts from prior execution.
function check_fresh_install_state() {
    local vm_count=""
    local ct_count=""
    local custom_bridges=""
    local marker=""

    section "FRESH INSTALL SAFETY CHECK"

    msg_info "Checking for fresh install state"

    vm_count="$(qm list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')"
    ct_count="$(pct list 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')"
    custom_bridges="$(grep -Ec "^auto vmbr[1-9]" /etc/network/interfaces 2>/dev/null || true)"

    if [ "$vm_count" -gt 0 ] || [ "$ct_count" -gt 0 ] || [ "$custom_bridges" -gt 0 ]; then
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
        echo -e "${YW}Detected VMs: ${vm_count}, LXCs: ${ct_count}, extra bridges: ${custom_bridges}.${CL}"
        countdown_exit 30 "For safety this script will not continue on a non-fresh-looking node."
    fi

    msg_ok "FRESH INSTALL CHECK PASSED"
}

# --- 33. GPU DETECTION AND PROMPT ---
# Detects integrated and discrete GPUs before displaying adaptive GPU messages.
function detect_gpu_and_collect_choice() {
    local gpu_yn=""

    section "GPU DETECTION"

    msg_info "Detecting GPU hardware"
    detect_gpus_sysfs
    GPU_SUMMARY="$(build_gpu_summary)"
    msg_ok "$(detected_machine_gpu_label)"

    echo -e " ${BL}━━━━━▶${CL} ${GPU_SUMMARY:-No GPU details detected}"

    ENABLE_PASSTHROUGH="n"

    if [ "$DGPU_FOUND" == "yes" ]; then
        if [ "$SYSTEM_TYPE" == "Laptop" ] && [ "$IGPU_FOUND" == "yes" ]; then
            echo -e "${YW}Integrated GPU will be kept for laptop screen. Only discrete GPU and same-slot function devices will be isolated.${CL}"
        else
            echo -e "${YW}Only discrete GPU and same-slot function devices will be isolated.${CL}"
        fi

        gpu_yn="$(timed_yes_no "Isolate Discrete GPU for VM Passthrough?" "y")"

        if [[ "$gpu_yn" =~ ^[Yy] ]]; then
            ENABLE_PASSTHROUGH="y"
            echo -e "${GN}Discrete GPU passthrough will be activated; integrated GPU will be left untouched.${CL}"
        else
            ENABLE_PASSTHROUGH="n"
            echo -e "${YW}Discrete GPU passthrough will not be activated.${CL}"
        fi
    else
        echo -e "${YW}No discrete GPU detected. GPU passthrough will be skipped.${CL}"
    fi
}

# --- 34. STORAGE DETECTION DISPLAY ---
# Displays detected disk type summary before final start prompt.
function show_storage_detection() {
    section "STORAGE DETECTION"

    msg_ok "DETECTED STORAGE TYPE"
    echo -e " ${BL}━━━━━▶${CL} ${STORAGE_SUMMARY:-No disk summary detected}"
    echo -e " ${BL}━━━━━▶${CL} ROOT FILESYSTEM: ${ROOT_FS_TYPE:-unknown} (${ROOT_SOURCE:-unknown})"
}

# --- 35. USER OPTION COLLECTION ---
# Collects optional choices using timed prompts.

# --- STORAGE LAYOUT DETECTION HELPER ---
# Detects whether the default local-lvm exists and estimates the root disk size.
# This lets the script keep snapshot-capable local-lvm on larger installs instead of blindly merging it.
function detect_storage_layout_options() {
    local root_source=""
    local root_real=""
    local parent_disk=""
    local root_size_bytes="0"

    LOCAL_LVM_EXISTS="no"
    ROOT_DISK_SIZE_GB="0"

    if grep -q "^lvmthin: local-lvm" /etc/pve/storage.cfg 2>/dev/null || lvdisplay /dev/pve/data >/dev/null 2>&1; then
        LOCAL_LVM_EXISTS="yes"
    fi

    root_source="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    root_real="$(readlink -f "$root_source" 2>/dev/null || echo "$root_source")"

    parent_disk="$(lsblk -no PKNAME "$root_real" 2>/dev/null | head -n1 | xargs || true)"

    if [ -z "$parent_disk" ] && command -v pvs >/dev/null 2>&1; then
        parent_disk="$(pvs --noheadings -o pv_name,vg_name 2>/dev/null | awk '$2=="pve"{print $1; exit}' | xargs -r lsblk -no PKNAME 2>/dev/null | head -n1 | xargs || true)"
    fi

    if [ -n "$parent_disk" ] && [ -b "/dev/${parent_disk}" ]; then
        root_size_bytes="$(lsblk -b -dn -o SIZE "/dev/${parent_disk}" 2>/dev/null | head -n1 | xargs || echo 0)"
        if [[ "$root_size_bytes" =~ ^[0-9]+$ ]] && [ "$root_size_bytes" -gt 0 ]; then
            ROOT_DISK_SIZE_GB="$(( (root_size_bytes + 1073741823) / 1073741824 ))"
        fi
    fi

    [ -z "$ROOT_DISK_SIZE_GB" ] && ROOT_DISK_SIZE_GB="0"
}

# --- STORAGE LAYOUT OPTION COLLECTOR ---
# Collects the local-lvm/snapshot decision before system-changing actions begin.
function collect_storage_layout_option() {
    local keep_lvm_yn=""

    section "STORAGE LAYOUT OPTION"

    detect_storage_layout_options

    detail_line "Root disk size" "${ROOT_DISK_SIZE_GB}GB"
    detail_line "local-lvm detected" "$LOCAL_LVM_EXISTS"

    if [ "$LOCAL_LVM_EXISTS" != "yes" ]; then
        STORAGE_LAYOUT_MODE="merge_all"
        msg_ok "NO LOCAL-LVM SNAPSHOT STORAGE DETECTED"
        return 0
    fi

    if [[ "$ROOT_DISK_SIZE_GB" =~ ^[0-9]+$ ]] && [ "$ROOT_DISK_SIZE_GB" -gt 0 ] && [ "$ROOT_DISK_SIZE_GB" -le 128 ]; then
        STORAGE_LAYOUT_MODE="merge_all"
        echo -e "${YW}Root disk is 128GB or smaller. Keeping the simple layout and merging local-lvm into local is recommended.${CL}"
        msg_ok "SMALL ROOT DISK MODE SELECTED"
        return 0
    fi

    echo -e "${YW}A larger root disk with local-lvm was detected.${CL}"
    echo -e "${YW}Keeping local-lvm preserves Proxmox VM snapshots. Merging it gives more local/root space but removes snapshot-capable VM storage.${CL}"
    keep_lvm_yn="$(timed_yes_no "Keep local-lvm for VM snapshots instead of merging it into local?" "y")"

    if [[ "$keep_lvm_yn" =~ ^[Yy] ]]; then
        STORAGE_LAYOUT_MODE="keep_local_lvm"
    else
        STORAGE_LAYOUT_MODE="merge_all"
    fi

    detail_line "Storage layout mode" "$STORAGE_LAYOUT_MODE"
    return 0
}

function collect_user_options() {
    local cpu_yn=""
    local crowdsec_yn=""
    local public_web_yn=""

    section "POST-INSTALL OPTIONS"

    cpu_yn="$(timed_yes_no "Set CPU Governor to PERFORMANCE?" "n")"

    if [[ "$cpu_yn" =~ ^[Yy] ]]; then
        ENABLE_PERFORMANCE="y"
    else
        ENABLE_PERFORMANCE="n"
    fi

    crowdsec_yn="$(timed_yes_no "Install CrowdSec Security Suite?" "y")"

    if [[ "$crowdsec_yn" =~ ^[Nn] ]]; then
        ENABLE_CROWDSEC="n"
    else
        ENABLE_CROWDSEC="y"
    fi

    echo ""
    echo -e "${YW}Public 80/443 on the Proxmox host is usually not required when Traefik runs inside your Ubuntu VM.${CL}"
    echo -e "${YW}For your current architecture, router port-forwarding should normally point to the VM, not the Proxmox host.${CL}"
    public_web_yn="$(timed_yes_no "Allow public HTTP/HTTPS 80/443 on Proxmox host firewall?" "n")"

    if [[ "$public_web_yn" =~ ^[Yy] ]]; then
        ALLOW_PUBLIC_WEB="y"
    else
        ALLOW_PUBLIC_WEB="n"
    fi
}

# --- 36. FINAL START PROMPT ---
# Starts post-install only after detection and user choices are collected.
function final_start_prompt() {
    local start_yn=""

    section "READY TO APPLY"

    echo -e "SYSTEM TYPE: ${GN}${SYSTEM_TYPE}${CL}"
    echo -e "ROOT FS: ${GN}${ROOT_FS_TYPE:-unknown}${CL}"
    echo -e "STORAGE: ${GN}${STORAGE_SUMMARY:-unknown}${CL}"
    echo -e "STORAGE LAYOUT: ${GN}${STORAGE_LAYOUT_MODE:-merge_all}${CL}"
    echo -e "DEFAULT IFACE: ${GN}${DEFAULT_IFACE:-unknown}${CL}"
    echo -e "LAN CIDR ALLOWED FOR SSH/WEBUI: ${GN}${LAN_CIDR:-not-detected}${CL}"
    echo -e "GPU PASSTHROUGH: ${GN}${ENABLE_PASSTHROUGH}${CL}"
    echo -e "CPU PERFORMANCE: ${GN}${ENABLE_PERFORMANCE}${CL}"
    echo -e "CROWDSEC: ${GN}${ENABLE_CROWDSEC}${CL}"
    echo -e "PUBLIC HOST 80/443: ${GN}${ALLOW_PUBLIC_WEB}${CL}"
    echo ""

    start_yn="$(timed_yes_no "Start the PVE9 Post Install Script?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    clear
    header_info
    show_script_version

    return 0
}

# =========================================================
#  APPLY FUNCTIONS
# =========================================================

# --- 37. STORAGE MERGE ---
# Removes local-lvm and expands the OS/root storage for simple single-node fresh installs.
# Supports ext filesystems through resize2fs and XFS through xfs_growfs.
function apply_storage_merge() {
    local pve_free_extents=""

    section "STORAGE MERGE"

    if [ "${STORAGE_LAYOUT_MODE:-merge_all}" == "keep_local_lvm" ]; then
        msg_ok "STORAGE LAYOUT MODE: KEEP LOCAL-LVM FOR VM SNAPSHOTS"
        echo -e "${YW}local-lvm was preserved as snapshot-capable VM storage. Root/local merge skipped by user choice.${CL}"
        return 0
    fi

    msg_info "Checking Proxmox local-lvm storage configuration"
    if grep -q "^lvmthin: local-lvm" /etc/pve/storage.cfg 2>/dev/null; then
        run_optional pvesm remove local-lvm
        msg_ok "LOCAL-LVM REMOVED FROM PROXMOX STORAGE CONFIG"
    else
        msg_ok "LOCAL-LVM STORAGE CONFIG NOT PRESENT"
    fi

    msg_info "Checking whether local-lvm thin data volume exists"
    if lvdisplay /dev/pve/data >/dev/null 2>&1; then
        run_cmd "removing local-lvm thin data volume" lvremove -fy /dev/pve/data
        msg_ok "LOCAL-LVM THIN DATA VOLUME REMOVED"
    else
        msg_ok "LOCAL-LVM THIN DATA VOLUME NOT PRESENT"
    fi

    msg_info "Checking free space in pve volume group"
    pve_free_extents="$(vgs --noheadings -o vg_free_count pve 2>/dev/null | awk '{print $1}' || echo 0)"

    if [[ "$pve_free_extents" =~ ^[0-9]+$ ]] && [ "$pve_free_extents" -gt 0 ]; then
        msg_ok "FREE PVE VOLUME GROUP SPACE DETECTED"

        msg_info "Expanding root logical volume with all free pve space"
        run_cmd "expanding root logical volume" lvresize -l +100%FREE /dev/pve/root
        msg_ok "ROOT LOGICAL VOLUME EXPANDED WITH FREE SPACE"

        ROOT_FS_TYPE="$(findmnt -n -o FSTYPE / 2>/dev/null || true)"

        case "$ROOT_FS_TYPE" in
            ext2|ext3|ext4)
                msg_info "Resizing root ext filesystem"
                run_cmd "resizing ext root filesystem" resize2fs /dev/mapper/pve-root
                msg_ok "ROOT EXT FILESYSTEM RESIZED"
                ;;
            xfs)
                if command -v xfs_growfs >/dev/null 2>&1; then
                    msg_info "Resizing root XFS filesystem"
                    run_cmd "resizing XFS root filesystem" xfs_growfs /
                    msg_ok "ROOT XFS FILESYSTEM RESIZED"
                else
                    msg_warn "Root filesystem is XFS but xfs_growfs is unavailable; filesystem resize skipped"
                fi
                ;;
            *)
                msg_warn "Unknown root filesystem type (${ROOT_FS_TYPE:-unknown}); filesystem resize skipped"
                ;;
        esac
    else
        msg_ok "NO FREE PVE VOLUME GROUP SPACE FOUND TO MERGE"
    fi

    msg_info "Verifying local storage path after merge"
    if df -h /var/lib/vz &>/dev/null; then
        msg_ok "LOCAL STORAGE PATH VERIFIED (/var/lib/vz)"
    else
        msg_warn "Local storage path /var/lib/vz could not be verified"
    fi

    msg_ok "LOCAL-LVM STORAGE SUCCESSFULLY MERGED TO OS"
}

# --- 38. DNS REDUNDANCY ---
# Adds Cloudflare DNS redundancy before package updates.
# On standard Proxmox installs, /etc/resolv.conf is the persistent resolver file.
function apply_dns_redundancy() {
    section "DNS REDUNDANCY"

    msg_info "Backing up current DNS resolver config"
    cp -n /etc/resolv.conf /etc/resolv.conf.pve9-postinstall.bak 2>/dev/null || true
    msg_ok "DNS CONFIG BACKUP CREATED"

    if [ -L /etc/resolv.conf ]; then
        msg_warn "/etc/resolv.conf is a symlink; replacing it with static Proxmox resolver file"
        rm -f /etc/resolv.conf
    fi

    msg_info "Writing Cloudflare DNS resolver config"
    cat <<EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

    msg_ok "DNS RESOLVERS CONFIGURED (DNS1 = 1.1.1.1, DNS2 = 1.0.0.1)"
}

# --- 39. REPOSITORIES & UPDATES ---
# Removes enterprise repositories, enables no-subscription repo and updates packages with hidden output.
function apply_repositories_and_updates() {
    section "REPOSITORIES & UPDATES"

    msg_info "Removing enterprise repository files"
    rm -f /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/ceph.sources
    msg_ok "ENTERPRISE / CEPH ENTERPRISE REPOSITORY FILES REMOVED"

    msg_info "Writing Proxmox no-subscription repository"
    cat <<EOF > /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
    msg_ok "PROXMOX NO-SUBSCRIPTION REPOSITORY CONFIGURED"

    msg_info "Updating APT package lists"
    run_cmd "updating APT package lists" env DEBIAN_FRONTEND=noninteractive apt-get update
    msg_ok "APT PACKAGE LISTS UPDATED"

    msg_info "Upgrading system packages"
    run_cmd "upgrading system packages" env DEBIAN_FRONTEND=noninteractive apt-get -y dist-upgrade
    msg_ok "SYSTEM PACKAGES UPGRADED"

    msg_info "Cleaning unused packages"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
    msg_ok "UNUSED PACKAGES REMOVED"

    msg_ok "SYSTEM UPDATED & CLEANED"
}

# --- 40. UI NAG REMOVAL ---
# Installs a persistent helper and dpkg hook to remove the Proxmox no-subscription popup after toolkit updates.
function apply_no_nag_patch() {
    section "WEBUI NAG PATCH"

    msg_info "Writing no-nag patch helper"
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

    msg_info "Writing no-nag dpkg post-invoke hook"
    cat <<'EOF' > /etc/apt/apt.conf.d/no-nag-script
DPkg::Post-Invoke { "/usr/local/sbin/pve-no-nag-patch.sh && systemctl restart pveproxy >/dev/null 2>&1 || true"; };
EOF
    msg_ok "NO-NAG DPKG POST-INVOKE HOOK INSTALLED"

    msg_info "Reinstalling Proxmox widget toolkit"
    run_cmd "reinstalling proxmox-widget-toolkit" env DEBIAN_FRONTEND=noninteractive apt-get --reinstall install -y proxmox-widget-toolkit
    msg_ok "PROXMOX WIDGET TOOLKIT REINSTALLED"

    msg_info "Applying no-subscription nag patch"
    run_optional /usr/local/sbin/pve-no-nag-patch.sh
    msg_ok "NO-SUBSCRIPTION NAG PATCH APPLIED"

    msg_info "Restarting pveproxy"
    run_optional systemctl restart pveproxy
    msg_ok "PVEPROXY RESTARTED"

    msg_ok "WEBUI NAG REMOVED"
}

# --- 41. POWER & CHASSIS OPTIMIZATION ---
# Masks sleep states and ignores laptop lid close on laptop hardware.
function apply_power_settings() {
    section "POWER & CHASSIS OPTIMIZATION"

    msg_info "Masking sleep, suspend, hibernate and hybrid-sleep targets"
    run_optional systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    msg_ok "SLEEP / SUSPEND / HIBERNATE TARGETS MASKED"

    if [ "$SYSTEM_TYPE" == "Laptop" ]; then
        msg_info "Setting laptop lid close behaviour to ignore"
        set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitch" "ignore"
        set_or_append_equals_config /etc/systemd/logind.conf "HandleLidSwitchDocked" "ignore"
        set_or_append_equals_config /etc/systemd/logind.conf "LidSwitchIgnoreInhibited" "no"
        run_optional systemctl restart systemd-logind
        msg_ok "LAPTOP LID SETTINGS CONFIGURED"
    else
        msg_ok "LAPTOP LID SETTINGS NOT REQUIRED"
    fi

    msg_ok "POWER SETTINGS OPTIMIZED"
}

# --- 42. GRUB & IOMMU ---
# Adds IOMMU, passthrough mode and console blanking without removing existing kernel args.
function apply_grub_iommu() {
    section "GRUB & IOMMU"

    msg_info "Configuring CPU IOMMU flag"
    append_grub_arg "$IOMMU_FLAG"
    msg_ok "CPU IOMMU FLAG CONFIGURED (${IOMMU_FLAG})"

    msg_info "Configuring IOMMU passthrough mode"
    append_grub_arg "iommu=pt"
    msg_ok "IOMMU PASSTHROUGH MODE CONFIGURED"

    msg_info "Configuring console blanking"
    append_grub_arg "consoleblank=60"
    msg_ok "CONSOLE BLANKING CONFIGURED"

    msg_info "Updating GRUB configuration"
    run_cmd "updating GRUB configuration" update-grub
    msg_ok "GRUB CONFIG UPDATED"

    msg_ok "GRUB UPDATED"
}

# --- 43. GPU ISOLATION (VFIO) ---
# Loads VFIO modules and binds only discrete GPU IDs to vfio-pci.
# Driver blacklisting is vendor-aware to avoid breaking AMD APUs when only NVIDIA passthrough is selected.
function apply_gpu_isolation() {
    local module=""
    local vendor=""

    section "GPU ISOLATION"

    if [ "$ENABLE_PASSTHROUGH" != "y" ]; then
        msg_ok "GPU PASSTHROUGH NOT SELECTED"
        return 0
    fi

    if [ -z "$DGPU_IDS" ]; then
        msg_warn "Passthrough selected but no safe discrete GPU IDs were found. Skipping VFIO."
        return 0
    fi

    msg_info "Adding VFIO modules to /etc/modules"
    for module in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
        grep -qxF "$module" /etc/modules || echo "$module" >> /etc/modules
    done
    msg_ok "VFIO MODULES ADDED TO /ETC/MODULES"

    msg_info "Writing host GPU driver blacklist"
    : > /etc/modprobe.d/pve-blacklist.conf

    for vendor in $DGPU_VENDOR_IDS; do
        case "$vendor" in
            0x10de)
                cat <<EOF >> /etc/modprobe.d/pve-blacklist.conf
blacklist nvidia
blacklist nouveau
blacklist nvidiafb
blacklist nvidia-gpu
EOF
                ;;
            0x1002|0x1022)
                cat <<EOF >> /etc/modprobe.d/pve-blacklist.conf
blacklist radeon
blacklist amdgpu
EOF
                ;;
        esac
    done

    sort -u /etc/modprobe.d/pve-blacklist.conf -o /etc/modprobe.d/pve-blacklist.conf
    msg_ok "HOST GPU DRIVERS BLACKLISTED FOR SELECTED DGPU VENDOR"

    msg_info "Writing VFIO PCI device IDs"
    echo "options vfio-pci ids=$DGPU_IDS disable_vga=1" > /etc/modprobe.d/vfio.conf
    msg_ok "VFIO PCI DEVICE IDS CONFIGURED ($DGPU_IDS)"

    msg_info "Updating initramfs for VFIO"
    run_cmd "updating initramfs for VFIO" update-initramfs -u -k all
    msg_ok "INITRAMFS UPDATED FOR VFIO"

    msg_ok "GPU ISOLATED"
}

# --- 44. SSH SECURITY ---
# Performs a non-invasive SSH safety audit only.
#
# Root cause from fresh testing:
# SSH worked before script 1 and failed after every version that modified root SSH policy,
# AuthorizedKeysFile handling, PermitRootLogin, or root key permissions. Therefore script 1 must not
# touch SSH authentication policy during the base Proxmox post-install stage.
#
# This function intentionally does NOT modify:
# - /etc/ssh/sshd_config
# - /etc/ssh/sshd_config.d/*
# - AuthorizedKeysFile
# - PermitRootLogin
# - PasswordAuthentication
# - /root/.ssh permissions
# - /root/.ssh/authorized_keys permissions/ownership
# - ssh/sshd service state
#
# Security hardening for SSH can be revisited later as a separate, dedicated, testable script once
# the full build chain is stable. The priority here is zero SSH lockout risk on fresh Proxmox tests.
function apply_ssh_security() {
    local effective_config=""
    local effective_authorized_keys=""
    local effective_permit_root=""
    local effective_password_auth=""
    local effective_pubkey_auth=""
    local effective_kbd_auth=""

    section "SSH SECURITY"

    msg_info "Auditing SSH configuration without modifying it"

    run_cmd "validating current sshd config" sshd -t

    effective_config="$(sshd -T -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null || true)"
    effective_authorized_keys="$(awk '$1=="authorizedkeysfile" {for (i=2; i<=NF; i++) printf "%s ", $i}' <<< "$effective_config" | xargs 2>/dev/null || true)"
    effective_permit_root="$(awk '$1=="permitrootlogin" {print $2; exit}' <<< "$effective_config")"
    effective_password_auth="$(awk '$1=="passwordauthentication" {print $2; exit}' <<< "$effective_config")"
    effective_pubkey_auth="$(awk '$1=="pubkeyauthentication" {print $2; exit}' <<< "$effective_config")"
    effective_kbd_auth="$(awk '$1=="kbdinteractiveauthentication" {print $2; exit}' <<< "$effective_config")"

    SSH_ROOT_KEY_FILE="not-modified"
    SSH_EFFECTIVE_AUTHORIZED_KEYS="${effective_authorized_keys:-unknown}"
    SSH_EFFECTIVE_PERMIT_ROOT="${effective_permit_root:-unknown}"
    SSH_EFFECTIVE_PASSWORD_AUTH="${effective_password_auth:-unknown}"
    SSH_EFFECTIVE_PUBKEY_AUTH="${effective_pubkey_auth:-unknown}"
    SSH_EFFECTIVE_KBD_AUTH="${effective_kbd_auth:-unknown}"
    SSH_HARDENING_APPLIED="audit-only"

    msg_ok "SSH CONFIG VALIDATED"
    echo -e "  ${DGN}ROOT SSH CONFIG LEFT UNCHANGED${CL}"
    echo -e "  ${DGN}SSH LOCKOUT RISK AVOIDED${CL}"

    if [ "${effective_pubkey_auth:-unknown}" != "yes" ]; then
        msg_warn "PubkeyAuthentication is not currently yes; root key login may depend on existing Proxmox defaults"
    fi

    if [ "${effective_permit_root:-unknown}" == "no" ]; then
        msg_warn "Effective PermitRootLogin is no; root SSH login may already be disabled by existing config"
    fi

    msg_ok "SSH SECURITY AUDIT COMPLETE"
}

# --- 45. SYSCTL HARDENING & NETWORK TUNING ---
# Adds kernel hardening and high-traffic tuning for reverse proxy / VM workloads.
function apply_sysctl_tuning() {
    section "SYSCTL HARDENING & NETWORK TUNING"

    msg_info "Writing sysctl hardening and network tuning file"
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

    msg_info "Applying sysctl settings"
    run_optional sysctl --system
    msg_ok "SYSCTL SETTINGS APPLIED"

    msg_ok "SYSCTL HARDENING APPLIED"
}

# --- 46. REALTEK NIC OPTIMIZATION ---
# Detects Realtek NICs and disables problematic offloads persistently.
function apply_realtek_optimization() {
    section "REALTEK NIC OPTIMIZATION"

    msg_info "Installing or verifying ethtool"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y ethtool
    msg_ok "ETHTOOL INSTALLED / VERIFIED"

    msg_info "Detecting Realtek network interface"
    REALTEK_IFACE="$(detect_realtek_iface || true)"

    if [ -n "$REALTEK_IFACE" ]; then
        msg_info "Applying Realtek offload settings"
        run_optional ethtool -K "$REALTEK_IFACE" tso off gso off gro off
        msg_ok "REALTEK OFFLOAD SETTINGS APPLIED ($REALTEK_IFACE)"

        msg_info "Writing Realtek optimization systemd service"
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

        run_cmd "reloading systemd daemon" systemctl daemon-reload
        run_cmd "enabling Realtek optimization service" systemctl enable realtek-optimize.service

        REALTEK_OPTIMIZED="yes"

        msg_ok "REALTEK NIC OPTIMIZED ($REALTEK_IFACE)"
    else
        REALTEK_OPTIMIZED="no"
        msg_ok "NO REALTEK NIC OPTIMIZATION NEEDED"
    fi
}

# --- 47. PROXMOX FIREWALL BASELINE ---
# Enables Proxmox firewall with LAN-only SSH/WebUI access.
# Public 80/443 is optional and disabled by default for VM-reverse-proxy architecture.
function apply_proxmox_firewall() {
    section "PROXMOX FIREWALL BASELINE"

    msg_info "Creating or verifying Proxmox node firewall directory"
    mkdir -p "/etc/pve/nodes/${HOSTNAME_SHORT}"
    msg_ok "PROXMOX NODE FIREWALL DIRECTORY VERIFIED"

    if [ -z "$LAN_CIDR" ]; then
        PVE_FIREWALL_APPLIED="no"
        msg_warn "Could not detect LAN CIDR. Proxmox firewall rules skipped to avoid lockout."
        return 0
    fi

    msg_info "Enabling datacenter firewall"
    if grep -q "^firewall:" /etc/pve/datacenter.cfg 2>/dev/null; then
        sed -i 's/^firewall:.*/firewall: 1/' /etc/pve/datacenter.cfg
    else
        echo "firewall: 1" >> /etc/pve/datacenter.cfg
    fi
    msg_ok "DATACENTER FIREWALL ENABLED"

    msg_info "Writing node firewall rules"
    cat <<EOF > "/etc/pve/nodes/${HOSTNAME_SHORT}/host.fw"
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]
IN ACCEPT -source ${LAN_CIDR} -p tcp -dport 22 -log nolog
IN ACCEPT -source ${LAN_CIDR} -p tcp -dport 8006 -log nolog
IN ACCEPT -p icmp -log nolog
EOF

    if [ "$ALLOW_PUBLIC_WEB" == "y" ]; then
        cat <<EOF >> "/etc/pve/nodes/${HOSTNAME_SHORT}/host.fw"
IN ACCEPT -p tcp -dport 80 -log nolog
IN ACCEPT -p tcp -dport 443 -log nolog
EOF
        msg_ok "NODE FIREWALL RULES WRITTEN WITH PUBLIC 80/443"
    else
        msg_ok "NODE FIREWALL RULES WRITTEN WITHOUT PUBLIC 80/443"
    fi

    msg_info "Enabling and restarting pve-firewall"
    run_optional systemctl enable --now pve-firewall
    run_optional systemctl restart pve-firewall
    msg_ok "PVE-FIREWALL SERVICE ENABLED"

    PVE_FIREWALL_APPLIED="yes"

    msg_ok "PROXMOX FIREWALL ENABLED"
}

# --- 48. CROWDSEC & AUTO UPDATES ---
# Installs CrowdSec, firewall bouncer, Proxmox/Linux collections and unattended upgrades.
function apply_crowdsec_security() {
    section "CROWDSEC & AUTO UPDATES"

    if [ "$ENABLE_CROWDSEC" != "y" ]; then
        msg_ok "CROWDSEC SECURITY SUITE NOT SELECTED"
        return 0
    fi

    msg_info "Installing CrowdSec dependency packages"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg ca-certificates
    msg_ok "SECURITY INSTALL DEPENDENCIES INSTALLED"

    if command -v curl >/dev/null 2>&1; then
        msg_info "Running CrowdSec repository installer"
        curl -fsSL https://install.crowdsec.net | sh &>/dev/null || true
        msg_ok "CROWDSEC REPOSITORY INSTALLER EXECUTED"
    fi

    msg_info "Updating APT package lists for CrowdSec"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get update
    msg_ok "APT PACKAGE LISTS UPDATED FOR CROWDSEC"

    msg_info "Installing CrowdSec and unattended-upgrades"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec unattended-upgrades
    msg_ok "CROWDSEC AND UNATTENDED-UPGRADES INSTALLED"

    msg_info "Checking available CrowdSec firewall bouncer package"
    if apt-cache show crowdsec-firewall-bouncer-nftables &>/dev/null; then
        run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec-firewall-bouncer-nftables
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-nftables"
        msg_ok "CROWDSEC NFTABLES FIREWALL BOUNCER INSTALLED"
    elif apt-cache show crowdsec-firewall-bouncer-iptables &>/dev/null; then
        run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y crowdsec-firewall-bouncer-iptables
        CROWDSEC_BOUNCER_PACKAGE="crowdsec-firewall-bouncer-iptables"
        msg_ok "CROWDSEC IPTABLES FIREWALL BOUNCER INSTALLED"
    else
        CROWDSEC_BOUNCER_PACKAGE="none"
        msg_warn "CrowdSec firewall bouncer package not found"
    fi

    if command -v cscli >/dev/null 2>&1; then
        msg_info "Installing CrowdSec collections"
        run_optional cscli collections install crowdsecurity/linux
        run_optional cscli collections install crowdsecurity/sshd
        run_optional cscli collections install crowdsecurity/proxmox
        run_optional cscli collections install crowdsecurity/http-cve
        msg_ok "CROWDSEC COLLECTIONS INSTALLED"
    else
        msg_warn "cscli not found after install; CrowdSec collection install skipped"
    fi

    msg_info "Enabling CrowdSec service"
    run_optional systemctl enable --now crowdsec
    run_optional systemctl restart crowdsec
    msg_ok "CROWDSEC SERVICE ENABLED"

    msg_info "Checking CrowdSec firewall bouncer service"
    if systemctl list-unit-files 'crowdsec-firewall-bouncer*' --no-pager --no-legend 2>/dev/null | grep -q "crowdsec-firewall-bouncer"; then
        run_optional systemctl enable --now crowdsec-firewall-bouncer
        run_optional systemctl restart crowdsec-firewall-bouncer
        msg_ok "CROWDSEC FIREWALL BOUNCER ENABLED"
    else
        msg_warn "CrowdSec firewall bouncer service was not found after install"
    fi

    msg_info "Writing unattended-upgrades config"
    cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    msg_ok "UNATTENDED UPGRADES CONFIGURED"

    msg_ok "SECURITY INSTALLED"
}

# --- 49. PROXMOX FIREWALL SERVICE REINFORCEMENT ---
# Ensures the firewall service remains enabled now and at boot.
function reinforce_pve_firewall_service() {
    section "PROXMOX FIREWALL SERVICE REINFORCEMENT"

    msg_info "Enabling and restarting Proxmox firewall service"
    run_optional systemctl enable --now pve-firewall
    run_optional systemctl restart pve-firewall
    msg_ok "PROXMOX FIREWALL SERVICE ENABLED"
}

# --- 50. PERFORMANCE & TRIM ---
# Optionally enables performance CPU governor and enables fstrim.timer when SSD is detected.
function apply_performance_and_trim() {
    section "PERFORMANCE & TRIM"

    if [ "$ENABLE_PERFORMANCE" == "y" ]; then
        msg_info "Installing cpufrequtils"
        run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y cpufrequtils
        msg_ok "CPUFREQUTILS INSTALLED"

        msg_info "Writing performance governor default"
        echo 'GOVERNOR="performance"' > /etc/default/cpufrequtils
        msg_ok "CPU GOVERNOR DEFAULT SET TO PERFORMANCE"

        if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
            msg_info "Applying live CPU performance governor"
            for r in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                echo "performance" > "$r" 2>/dev/null || true
            done
            msg_ok "LIVE CPU GOVERNOR SET TO PERFORMANCE"
        else
            msg_warn "CPUFREQ sysfs path not found; live governor change skipped"
        fi

        run_optional systemctl restart cpufrequtils
        msg_ok "CPU PERFORMANCE ACTIVE"
    else
        msg_ok "CPU PERFORMANCE GOVERNOR NOT SELECTED"
    fi

    if [ "$IS_SSD" == "yes" ]; then
        msg_info "Enabling and starting fstrim timer"
        run_cmd "enabling fstrim timer" systemctl enable --now fstrim.timer
        msg_ok "SSD TRIM ENABLED"
    else
        msg_ok "SSD TRIM NOT REQUIRED FOR DETECTED STORAGE"
    fi
}

# --- 51. NUMLOCK BOOT SERVICE ---
# Enables NumLock on Linux consoles at boot when console tools support it.
function apply_numlock_service() {
    section "NUMLOCK BOOT SERVICE"

    msg_info "Installing or verifying kbd package"
    run_optional env DEBIAN_FRONTEND=noninteractive apt-get install -y kbd
    msg_ok "KBD PACKAGE INSTALLED / VERIFIED"

    msg_info "Writing NumLock helper script"
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

    msg_info "Writing NumLock systemd service"
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

    run_cmd "reloading systemd daemon" systemctl daemon-reload
    run_cmd "enabling NumLock service" systemctl enable pve-numlock.service

    NUMLOCK_CONFIGURED="yes"

    msg_ok "NUMLOCK BOOT SERVICE CONFIGURED"
}

# --- 52. AUTO-VERIFY GHOST SCRIPT ---
# Creates one-time verifier that runs after reboot, writes a detailed log, self-deletes, and leaves a login display helper.
# The systemd service logs to journal only, not the physical Proxmox console, so the report is shown upon root SSH login instead.
function create_auto_verifier() {
    section "AUTO-VERIFY GHOST SCRIPT"

    msg_info "Writing auto-verify script"
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
INSTALL_ALLOW_PUBLIC_WEB="$ALLOW_PUBLIC_WEB"
INSTALL_SSH_HARDENING_APPLIED="$SSH_HARDENING_APPLIED"
INSTALL_PVE_FIREWALL_APPLIED="$PVE_FIREWALL_APPLIED"
INSTALL_IOMMU_FLAG="$IOMMU_FLAG"
INSTALL_CROWDSEC_BOUNCER_PACKAGE="$CROWDSEC_BOUNCER_PACKAGE"
INSTALL_REALTEK_IFACE="$REALTEK_IFACE"
INSTALL_REALTEK_OPTIMIZED="$REALTEK_OPTIMIZED"
INSTALL_NUMLOCK_CONFIGURED="$NUMLOCK_CONFIGURED"
INSTALL_DEFAULT_IFACE="$DEFAULT_IFACE"
INSTALL_LAN_CIDR="$LAN_CIDR"
INSTALL_SSH_ROOT_KEY_FILE="$SSH_ROOT_KEY_FILE"
INSTALL_SSH_EFFECTIVE_AUTHORIZED_KEYS="$SSH_EFFECTIVE_AUTHORIZED_KEYS"
INSTALL_SSH_EFFECTIVE_PERMIT_ROOT="$SSH_EFFECTIVE_PERMIT_ROOT"
INSTALL_SSH_EFFECTIVE_PASSWORD_AUTH="$SSH_EFFECTIVE_PASSWORD_AUTH"
INSTALL_SSH_EFFECTIVE_PUBKEY_AUTH="$SSH_EFFECTIVE_PUBKEY_AUTH"
INSTALL_SSH_EFFECTIVE_KBD_AUTH="$SSH_EFFECTIVE_KBD_AUTH"

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
INFO "Public host 80/443 selected: \$INSTALL_ALLOW_PUBLIC_WEB"
INFO "Realtek NIC optimized during install: \$INSTALL_REALTEK_OPTIMIZED"
INFO "Realtek interface: \$INSTALL_REALTEK_IFACE"
INFO "NumLock service configured: \$INSTALL_NUMLOCK_CONFIGURED"
INFO "Default network interface during install: \${INSTALL_DEFAULT_IFACE:-unknown}"
INFO "LAN CIDR allowed for SSH/WebUI during install: \${INSTALL_LAN_CIDR:-not-detected}"
INFO "Root SSH key file detected during install: \${INSTALL_SSH_ROOT_KEY_FILE:-not-detected}"
INFO "Effective AuthorizedKeysFile during install: \${INSTALL_SSH_EFFECTIVE_AUTHORIZED_KEYS:-unknown}"

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
if [ "\$INSTALL_DGPU_FOUND" == "yes" ]; then
    if [ "\$INSTALL_ENABLE_PASSTHROUGH" == "y" ]; then
        if find /sys/bus/pci/drivers/vfio-pci -maxdepth 1 -type l 2>/dev/null | grep -q .; then
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
    ROOT_SSHD_EFFECTIVE="\$(sshd -T -C user=root,host=localhost,addr=127.0.0.1 2>/dev/null || true)"
    ROOT_AUTH_KEYS="\$(echo "\$ROOT_SSHD_EFFECTIVE" | awk '\$1=="authorizedkeysfile" {for (i=2; i<=NF; i++) printf "%s ", \$i}')"

    if echo "\$ROOT_SSHD_EFFECTIVE" | grep -q "^passwordauthentication no"; then PASS "SSH password authentication disabled for root context"; else FAIL "SSH password authentication still enabled for root context"; fi
    if echo "\$ROOT_SSHD_EFFECTIVE" | grep -Eq "^permitrootlogin (without-password|prohibit-password)"; then PASS "Root SSH password login disabled while key login remains allowed"; else FAIL "Root SSH password login not hardened"; fi
    if echo "\$ROOT_SSHD_EFFECTIVE" | grep -q "^pubkeyauthentication yes"; then PASS "Root public-key authentication enabled"; else FAIL "Root public-key authentication not enabled"; fi
    if echo "\$ROOT_SSHD_EFFECTIVE" | grep -q "^kbdinteractiveauthentication no"; then PASS "Keyboard-interactive SSH authentication disabled"; else WARN "Keyboard-interactive SSH authentication not confirmed disabled"; fi
    if [ -n "\$ROOT_AUTH_KEYS" ]; then PASS "AuthorizedKeysFile effective path present: \$ROOT_AUTH_KEYS"; else FAIL "AuthorizedKeysFile effective path missing"; fi

    if [ -n "\$INSTALL_SSH_ROOT_KEY_FILE" ] && [ "\$INSTALL_SSH_ROOT_KEY_FILE" != "not-detected" ] && [ -s "\$INSTALL_SSH_ROOT_KEY_FILE" ]; then
        PASS "Detected root SSH key file still exists"
    else
        WARN "Detected root SSH key file not found after reboot: \${INSTALL_SSH_ROOT_KEY_FILE:-unknown}"
    fi
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

if [ "\$INSTALL_ALLOW_PUBLIC_WEB" == "y" ]; then
    if grep -q "dport 80" "/etc/pve/nodes/\$(hostname -s)/host.fw" 2>/dev/null && grep -q "dport 443" "/etc/pve/nodes/\$(hostname -s)/host.fw" 2>/dev/null; then
        PASS "Public 80/443 firewall rules present"
    else
        WARN "Public 80/443 was selected but rules were not detected"
    fi
else
    INFO "Public host 80/443 was not selected"
fi

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

    msg_info "Writing auto-verify systemd service"
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

    msg_info "Writing auto-verify login display helper"
    cat <<'EOF' > /etc/profile.d/pve-postinstall-verify-display.sh
#!/usr/bin/env bash

VERIFY_LOG="/var/log/pve9-postinstall-verify.log"
DISPLAY_MARKER="/root/.pve9-postinstall-verify-displayed"

YW=$'\033[33m'
BL=$'\033[36m'
GN=$'\033[1;92m'
CL=$'\033[m'

if [ "$(id -u)" -ne 0 ]; then
    return 0 2>/dev/null || exit 0
fi

if [ -f "$DISPLAY_MARKER" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ -s "$VERIFY_LOG" ]; then
    echo ""
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "${GN} PVE9 POST-INSTALL VERIFICATION REPORT${CL}"
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    cat "$VERIFY_LOG"
    echo -e "${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo ""

    touch "$DISPLAY_MARKER"
    rm -f /etc/profile.d/pve-postinstall-verify-display.sh
else
    echo ""
    echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "${YW} PVE9 POST-INSTALL VERIFICATION PENDING${CL}"
    echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo -e "${YW} PVE9 post-install verification report is not ready yet.${CL}"
    echo -e "${YW} It will be displayed automatically on your next root SSH login.${CL}"
    echo -e "${YW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
    echo ""
fi
EOF

    chmod +x /etc/profile.d/pve-postinstall-verify-display.sh
    msg_ok "AUTO-VERIFY LOGIN DISPLAY HELPER INSTALLED"

    run_cmd "reloading systemd daemon" systemctl daemon-reload
    run_cmd "enabling auto-verify systemd service" systemctl enable pve-postinstall-verify.service

    msg_ok "AUTO-VERIFY GHOST SCRIPT CREATED"
}

# --- 53. COMPLETION MARKER ---
# Writes a completion marker so future reruns are blocked by fresh-install detection.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing PVE9 post-install completion marker"
    cat <<EOF > "$COMPLETED_MARKER"
PVE9 Post Install completed on: $(date)
System Type: $SYSTEM_TYPE
SSD Detected: $IS_SSD
Root FS Type: $ROOT_FS_TYPE
GPU Passthrough: $ENABLE_PASSTHROUGH
CPU Performance: $ENABLE_PERFORMANCE
CrowdSec: $ENABLE_CROWDSEC
Allow Public Host 80/443: $ALLOW_PUBLIC_WEB
Default Interface: ${DEFAULT_IFACE:-unknown}
LAN CIDR Allowed For SSH/WebUI: ${LAN_CIDR:-not-detected}
SSH Hardening: $SSH_HARDENING_APPLIED
Root SSH Key File: ${SSH_ROOT_KEY_FILE:-not-detected}
Effective AuthorizedKeysFile: ${SSH_EFFECTIVE_AUTHORIZED_KEYS:-unknown}
Effective PermitRootLogin: ${SSH_EFFECTIVE_PERMIT_ROOT:-unknown}
Effective PasswordAuthentication: ${SSH_EFFECTIVE_PASSWORD_AUTH:-unknown}
Effective PubkeyAuthentication: ${SSH_EFFECTIVE_PUBKEY_AUTH:-unknown}
Effective KbdInteractiveAuthentication: ${SSH_EFFECTIVE_KBD_AUTH:-unknown}
Proxmox Firewall: $PVE_FIREWALL_APPLIED
Realtek Optimized: $REALTEK_OPTIMIZED
NumLock: $NUMLOCK_CONFIGURED
EOF

    msg_ok "PVE9 POST-INSTALL COMPLETION MARKER WRITTEN"
}


# --- FINAL SUMMARY ---
# Shows a visible finished marker before reboot so the user can confirm the script completed.
function show_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    detail_line "SYSTEM TYPE" "$SYSTEM_TYPE"
    detail_line "STORAGE LAYOUT MODE" "$STORAGE_LAYOUT_MODE"
    detail_line "GPU PASSTHROUGH" "$ENABLE_PASSTHROUGH"
    detail_line "CPU PERFORMANCE" "$ENABLE_PERFORMANCE"
    detail_line "CROWDSEC" "$ENABLE_CROWDSEC"
    detail_line "PROXMOX FIREWALL" "$PVE_FIREWALL_APPLIED"
    detail_line "SSH HARDENING" "$SSH_HARDENING_APPLIED"
    detail_line "REALTEK OPTIMIZED" "$REALTEK_OPTIMIZED"
    detail_line "NUMLOCK" "$NUMLOCK_CONFIGURED"
    detail_line "VERIFY LOG" "$VERIFY_LOG"
    echo ""
}

# --- 54. FINAL REBOOT COUNTDOWN ---
# ENTER/Y reboots immediately.
# SPACE/N cancels reboot.
# Timeout reboots automatically.
function final_reboot_prompt() {
    section "REBOOT"

    if timed_reboot_countdown "$REBOOT_T"; then
        reboot
    fi
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 55. MAIN FUNCTION ---
# Runs the full script in clear validation -> audit -> prompt -> apply order.
function main() {
    init_script

    show_fresh_install_warning
    audit_hardware
    check_fresh_install_state
    detect_gpu_and_collect_choice
    show_storage_detection
    collect_user_options
    final_start_prompt

    apply_storage_merge
    apply_dns_redundancy
    apply_repositories_and_updates
    apply_no_nag_patch
    apply_power_settings
    apply_grub_iommu
    apply_gpu_isolation
    apply_ssh_security
    apply_sysctl_tuning
    apply_realtek_optimization
    apply_proxmox_firewall
    apply_crowdsec_security
    reinforce_pve_firewall_service
    apply_performance_and_trim
    apply_numlock_service
    create_auto_verifier
    write_completion_marker
    show_final_summary
    final_reboot_prompt

    exit 0
}

main "$@"
