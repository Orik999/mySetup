#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker ENV Setup Crea
# =========================================================

# --- 1. COLOR VARIABLES (KEEP ALL FOR FUTURE MODIFICATIONS) ---
# Central visual theme for Docker ENV Setup.
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

# --- 2. GLOBAL VARIABLES ---
# Stores timers, defaults, paths, secret values, state flags and final result values.
T=15

LOG_FILE="/var/log/docker-env-setup.log"
RUNTIME_LOG_FILE=""
VERIFY_LOG="/var/log/docker-env-setup-verify.log"
COMPLETED_MARKER="/root/.docker-env-setup-completed"

DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-${USER:-dockeradmin}}}"
DEFAULT_TZ="Europe/London"
DEFAULT_DOMAIN="${DEFAULT_DOMAIN:-example.com}"
DEFAULT_CF_API_EMAIL="${DEFAULT_CF_API_EMAIL:-}"
DEFAULT_CF_ZONE_ID=""
DEFAULT_HTPASSWD_USER="admin"

SUDO_CMD=""
LOGGING_ENABLED="no"

DOCKER_USER=""
USERDIR=""
DOCKER_DIR=""
DOCKER_SECRETS_DIR=""
CF_API_TOKEN_FILE=""

PUID_VALUE=""
PGID_VALUE=""
TZ_VALUE=""
DOMAIN_VALUE=""
CF_API_EMAIL_VALUE=""
CF_ZONE_ID_VALUE=""
CF_API_TOKEN_VALUE=""

EXISTING_SETUP="no"
REGENERATE_SECRETS="n"
DOCKER_READY="unknown"
DOCKER_COMPOSE_READY="unknown"
DOCKER_USER_IN_DOCKER_GROUP="unknown"

POSTGRES_PASSWORD=""
REDIS_PASSWORD=""
AUTHENTIK_SECRET_KEY=""
AUTHENTIK_POSTGRES_PASSWORD=""
AUTHENTIK_HOST_VALUE=""
AUTHENTIK_HOST_BROWSER_VALUE=""
AUTHENTIK_BOOTSTRAP_EMAIL_VALUE=""
AUTHENTIK_BOOTSTRAP_PASSWORD=""
AUTHENTIK_BOOTSTRAP_TOKEN=""
POSTIZ_POSTGRES_PASSWORD=""
POSTIZ_JWT_SECRET=""
TEMPORAL_POSTGRES_PASSWORD=""

HTPASSWD_MODE="empty"
HTPASSWD_USER_VALUE=""
HTPASSWD_PASSWORD_VALUE=""
HTPASSWD_HASH_VALUE=""
HTPASSWD_LINE_VALUE=""

SECRET_DISPLAY_WAS_SHOWN="no"
SECRET_SCREEN_CLEARED="no"

# Traefik template download defaults. These contain no secrets and can safely live in a public GitHub repo.
TRAEFIK_TEMPLATE_RAW_BASE="${TRAEFIK_TEMPLATE_RAW_BASE:-https://raw.githubusercontent.com/Orik999/mySetup/main/docker/traefik}"
TRAEFIK_STATIC_TEMPLATE_URL="${TRAEFIK_STATIC_TEMPLATE_URL:-${TRAEFIK_TEMPLATE_RAW_BASE}/traefik.yml.template}"
TRAEFIK_DYNAMIC_TEMPLATE_URL="${TRAEFIK_DYNAMIC_TEMPLATE_URL:-${TRAEFIK_TEMPLATE_RAW_BASE}/dynamic-config.yml.template}"

TRAEFIK_DIR=""
TRAEFIK_ACME_DIR=""
TRAEFIK_STATIC_CONFIG_FILE=""
TRAEFIK_DYNAMIC_CONFIG_FILE=""
TRAEFIK_TEMPLATE_TMP_DIR=""

TRAEFIK_DASHBOARD_HOST=""
PROXMOX_ROUTE_ENABLED="n"
PROXMOX_HOST=""
PROXMOX_URL=""

TEMP_FILES=()
TEMP_DIRS=()

# =========================================================
#  OUTPUT / LOGGING FUNCTIONS
# =========================================================

# --- 3. HEADER FUNCTION ---
# Displays the Docker ENV Setup banner.
function header_info {
echo -e "${BL}
██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗     ███████╗███╗   ██╗██╗   ██╗    ███████╗███████╗████████╗██╗   ██╗██████╗ 
██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗    ██╔════╝████╗  ██║██║   ██║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗
██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝    █████╗  ██╔██╗ ██║██║   ██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝
██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗    ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ 
██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║    ███████╗██║ ╚████║ ╚████╔╝     ███████║███████╗   ██║   ╚██████╔╝██║     
╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═══╝  ╚═══╝      ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     
${CL}"
}

# --- 4. MESSAGE HELPER FUNCTIONS ---
# Provides consistent display -> apply -> success output style.
function msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
function msg_warn() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_skip() { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
function msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; exit 1; }

# --- 5. SECTION HEADER HELPER ---
# Keeps terminal output clean and grouped by stage.
function section() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${BL}$1${CL}"
    echo -e "${BORDER}"
}

# --- 5A. FLASHING SUCCESS SECTION HEADER HELPER ---
# Uses the script 1-style final success section with bold flashing green text.
function section_flash_success() {
    echo ""
    echo -e "${BORDER}"
    echo -e "${GN}${CLF}$1${CL}"
    echo -e "${BORDER}"
}

# --- 5B. DETAIL LINE HELPER ---
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

# --- 7A. INPUT BUFFER FLUSH HELPER ---
# Clears only a small bounded amount of already-buffered terminal input.
# Important: this never reads from stdin, because streamed scripts may use stdin for the script body.
function flush_input_buffer() {
    local junk=""
    local i=""

    if [ ! -r /dev/tty ]; then
        return 0
    fi

    for i in {1..20}; do
        if ! IFS= read -rsn1 -t 0.02 junk < /dev/tty; then
            break
        fi
    done

    return 0
}

# =========================================================
#  CLEANUP / ERROR HANDLING
# =========================================================

# --- 8. CLEANUP FUNCTION ---
# Removes temporary files created during execution.
function cleanup() {
    local exit_code="$?"
    local file=""

    # When running as a non-root user, logging is written to a temporary user-writable file first.
    # Copy it to /var/log at exit using sudo, then remove the temporary copy.
    if [ -n "${SUDO_CMD:-}" ] && [ -n "${RUNTIME_LOG_FILE:-}" ] && [ -s "$RUNTIME_LOG_FILE" ]; then
        "$SUDO_CMD" cp "$RUNTIME_LOG_FILE" "$LOG_FILE" 2>/dev/null || true
        "$SUDO_CMD" chmod 0644 "$LOG_FILE" 2>/dev/null || true
    fi

    for file in "${TEMP_FILES[@]:-}"; do
        [ -n "$file" ] && [ -f "$file" ] && rm -f "$file" 2>/dev/null || true
    done

    for file in "${TEMP_DIRS[@]:-}"; do
        [ -n "$file" ] && [ -d "$file" ] && rm -rf "$file" 2>/dev/null || true
    done

    exit "$exit_code"
}

# --- 9. ERROR TRAP HELPER ---
# Shows failing line number and points to the log file.
function on_error() {
    local line_no="$1"
    echo -e "${RD}ERROR:${CL} Script failed at line ${line_no}. Check ${LOG_FILE}"
}

# --- 10. COMMAND RUNNER ---
# Runs privileged commands quietly, but shows real stderr if they fail.
# Do not use this to print secret values.
function run_cmd() {
    local description="$1"
    shift

    local err_file=""
    err_file="$(mktemp)"
    TEMP_FILES+=("$err_file")

    if [ -n "$SUDO_CMD" ]; then
        if ! "$SUDO_CMD" "$@" > /dev/null 2> "$err_file"; then
            echo ""
            echo -e "${RD}Command failed during:${CL} ${description}"
            echo -e "${YW}Command:${CL} sudo $*"
            echo ""
            echo -e "${RD}Real error:${CL}"
            cat "$err_file"
            rm -f "$err_file"
            exit 1
        fi
    else
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
    fi

    rm -f "$err_file"
}

# --- 11. OPTIONAL COMMAND RUNNER ---
# Runs non-critical privileged commands quietly and does not stop the script.
function run_optional() {
    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" "$@" >/dev/null 2>&1 || true
    else
        "$@" >/dev/null 2>&1 || true
    fi
}

# --- 12. ROOT FILE WRITE HELPER ---
# Writes stdin to a privileged path with sudo when required.
# Heredoc content is not echoed to terminal, so this is safe for .env secret writing.
function write_root_file() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" tee "$path" >/dev/null
    else
        cat > "$path"
    fi
}

# --- 13. ROOT PATH EXISTS HELPER ---
# Checks whether a root-owned path exists.
function root_path_exists() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -e "$path"
    else
        test -e "$path"
    fi
}

# --- 14. ROOT FILE NOT EMPTY HELPER ---
# Checks whether a root-owned file exists and has content.
function root_file_not_empty() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" test -s "$path"
    else
        test -s "$path"
    fi
}

# --- 15. ROOT FILE READ HELPER ---
# Reads root-owned file content for secret reuse.
# Do not call this unless assigning output into a variable.
function root_read_file() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" cat "$path"
    else
        cat "$path"
    fi
}

# --- 16. ROOT STAT MODE HELPER ---
# Returns octal file mode for verification.
function root_stat_mode() {
    local path="$1"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" stat -c '%a' "$path" 2>/dev/null || true
    else
        stat -c '%a' "$path" 2>/dev/null || true
    fi
}

# =========================================================
#  LOGGING CONTROL
# =========================================================

# --- 17. ROOT / SUDO DETECTION ---
# Uses sudo when not root.
function detect_root_or_sudo() {
    if [ "$EUID" -eq 0 ]; then
        SUDO_CMD=""
    else
        SUDO_CMD="sudo"
    fi
}

# --- 18. SUDO VALIDATION ---
# Validates sudo once near the start so authentication failures happen before changes.
function validate_sudo_access() {
    if [ -n "$SUDO_CMD" ]; then
        msg_info "Validating sudo access"

        # First test the automation path created by script 3.5.
        # The Ubuntu autoinstall user is intentionally SSH-key-only and may not have a password.
        # sudo -n true confirms NOPASSWD sudo without ever prompting for a password.
        if "$SUDO_CMD" -n true >/dev/null 2>&1; then
            msg_ok "PASSWORDLESS SUDO CONFIRMED"
            return 0
        fi

        # Fallback for manually-created Ubuntu users that do have a normal sudo password.
        if "$SUDO_CMD" -v; then
            msg_ok "SUDO ACCESS CONFIRMED"
            return 0
        fi

        msg_error "Sudo authentication failed. Script cancelled."
    fi
}

# --- 19. LOGGING INITIALIZATION ---
# Starts tee logging while keeping original terminal descriptors available.
# When not root, logging goes to a temporary user-writable file first and is copied to /var/log during cleanup.
function init_logging() {
    exec 3>&1
    exec 4>&2

    if [ -n "$SUDO_CMD" ]; then
        # Avoid piping all interactive output through sudo tee.
        # Direct sudo tee can reorder /dev/tty prompts and make Enter appear inconsistent.
        RUNTIME_LOG_FILE="$(mktemp /tmp/docker-env-setup-log.XXXXXX)"
        TEMP_FILES+=("$RUNTIME_LOG_FILE")
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        RUNTIME_LOG_FILE="$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    LOGGING_ENABLED="yes"
}

# --- 20. DISABLE LOGGING HELPER ---
# Sends output directly to the terminal, bypassing tee logging.
# Used for sensitive inputs and final secret display.
function disable_logging() {
    if [ -w /dev/tty ]; then
        exec > /dev/tty 2> /dev/tty
    else
        exec >&3 2>&4
    fi

    LOGGING_ENABLED="no"
}

# --- 21. ENABLE LOGGING HELPER ---
# Re-enables tee logging after sensitive terminal-only sections are complete.
function enable_logging() {
    if [ -n "$RUNTIME_LOG_FILE" ]; then
        exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1
    else
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi

    LOGGING_ENABLED="yes"
}

# --- 22. CLEAR TERMINAL AND SCROLLBACK HELPER ---
# Clears visible terminal and scrollback where supported.
# This reduces the chance that displayed secrets remain visible after the user saves them.
function clear_terminal_scrollback() {
    if [ -w /dev/tty ]; then
        printf '\033[2J\033[3J\033[H' > /dev/tty
    else
        printf '\033[2J\033[3J\033[H'
    fi

    SECRET_SCREEN_CLEARED="yes"
}

# =========================================================
#  PROMPT FUNCTIONS
# =========================================================

# --- 23. YES/NO LABEL HELPER ---
# Converts Y/N answers to readable yes/no output.
function yes_no_label() {
    local value="$1"

    if [[ "$value" =~ ^[Yy]$ ]]; then
        echo "yes"
    else
        echo "no"
    fi
}

# --- 24. BLOCKING YES/NO HELPER ---
# Used when SPACE pauses a countdown and waits for Y/N/ENTER.
function tty_read_yes_no_blocking() {
    local prompt="$1"
    local default="$2"
    local default_label="Y/n"
    local key=""

    if [[ "$default" =~ ^[Nn]$ ]]; then
        default_label="y/N"
    fi

    flush_input_buffer

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
            flush_input_buffer
            return 0
        elif [[ "$key" =~ ^[YyNn]$ ]]; then
            tty_print "${BFR}"
            echo "$key"
            flush_input_buffer
            return 0
        fi
    done
}

# --- 25. TIMED YES/NO PROMPT HELPER ---
# Uses wall-clock countdown.
# SPACE pauses and waits.
# Timeout accepts default.
# Final answer stays visible.
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

    flush_input_buffer
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
                    flush_input_buffer
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    flush_input_buffer
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
                    flush_input_buffer
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    flush_input_buffer
                    break
                fi
            fi
        fi
    done

    [ -z "$answer" ] && answer="$default"
    final_label="$(yes_no_label "$answer")"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${final_label}${CL}"
    flush_input_buffer

    echo "$answer"
}

# --- 26. EDITABLE INPUT LOOP HELPER ---
# Shared editable input system for text prompts.
function editable_input_loop() {
    local prompt="$1"
    local default="$2"
    local initial_value="${3:-}"
    local answer="$initial_value"
    local key=""

    flush_input_buffer

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
                tty_print "${BFR}"
                echo "$answer"
                flush_input_buffer
                return 0
                ;;
            $'\177'|$'\b')
                answer="${answer%?}"
                ;;
            *)
                answer+="$key"
                ;;
        esac
    done
}

# --- 27. TIMED TEXT INPUT HELPER ---
# Shows wall-clock countdown.
# SPACE pauses with empty editable buffer.
# Any typed character pauses with that character already inside the editable buffer.
function timed_text_input() {
    local prompt="$1"
    local default="$2"
    local answer=""
    local key=""
    local deadline=""
    local now=""
    local remaining=""

    flush_input_buffer
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
                    answer="$(editable_input_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    flush_input_buffer
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "$key")"
                    break
                fi
            fi
        else
            if IFS= read -rsn1 -t 1 key; then
                if [[ "$key" == " " ]]; then
                    answer="$(editable_input_loop "$prompt" "$default" "")"
                    break
                elif [[ -z "$key" ]]; then
                    answer="$default"
                    flush_input_buffer
                    break
                else
                    answer="$(editable_input_loop "$prompt" "$default" "$key")"
                    break
                fi
            fi
        fi
    done

    [ -z "$answer" ] && answer="$default"

    tty_print "${BFR}"
    tty_println "${CM} ${GN}${prompt} ${answer}${CL}"
    flush_input_buffer

    echo "$answer"
}

# --- 28. HIDDEN INPUT HELPER ---
# Reads sensitive input without echoing it to terminal.
# Call this while logging is disabled.
function hidden_input() {
    local prompt="$1"
    local answer=""

    tty_print "${YW}${prompt}: ${CL}"

    if [ -r /dev/tty ]; then
        IFS= read -rs answer < /dev/tty || true
    else
        IFS= read -rs answer || true
    fi

    tty_println ""

    echo "$answer"
}

# --- 28A. SENSITIVE LINE INPUT HELPER ---
# Reads one sensitive pasted line directly from /dev/tty and clears the visible prompt/token line immediately after ENTER.
# The value is returned through stdout for command substitution only; prompt/token text is printed only to /dev/tty.
# Do not call flush_input_buffer here because it can consume pasted token characters.
function sensitive_line_input() {
    local prompt="$1"
    local answer=""
    local cols="80"
    local visible_len="0"
    local lines_to_clear="1"
    local i=""

    tty_print "${YW}${prompt}: ${CL}"

    if [ -r /dev/tty ]; then
        IFS= read -r answer < /dev/tty || answer=""
    else
        IFS= read -r answer || answer=""
    fi

    cols="$(tput cols 2>/dev/null || echo 80)"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols="80"
    [ "$cols" -lt 20 ] && cols="80"

    visible_len=$(( ${#prompt} + 2 + ${#answer} ))
    lines_to_clear=$(( (visible_len + cols - 1) / cols ))
    [ "$lines_to_clear" -lt 1 ] && lines_to_clear="1"

    for ((i=0; i<lines_to_clear; i++)); do
        tty_print "[1A
[2K"
    done

    printf '%s' "$answer"
}

# --- 29. SECRET SAVE CONFIRMATION HELPER ---
# Waits until the user confirms they saved displayed secrets, then clears terminal/scrollback.
function wait_then_clear_secret_display() {
    echo ""
    echo -e "${RD}${CLF}Save the secrets above now.${CL}"
    echo -e "${YW}After pressing ENTER, this screen and terminal scrollback will be cleared where supported.${CL}"
    echo ""

    if [ -r /dev/tty ]; then
        read -r -p "Press ENTER after you have saved the secrets securely..." _ < /dev/tty || true
    else
        read -r -p "Press ENTER after you have saved the secrets securely..." _ || true
    fi

    clear_terminal_scrollback
}

# =========================================================
#  VALIDATION HELPERS
# =========================================================

# --- 30. USERNAME VALIDATION HELPER ---
# Validates Linux username format.
function validate_linux_username() {
    local username="$1"

    if [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        return 0
    fi

    return 1
}

# --- 31. ABSOLUTE PATH VALIDATION HELPER ---
# Validates an absolute path and blocks unsafe top-level paths.
function validate_absolute_path() {
    local path="$1"

    if [[ "$path" != /* ]]; then
        return 1
    fi

    case "$path" in
        "/"|"/root"|"/etc"|"/usr"|"/var"|"/home")
            return 1
            ;;
    esac

    return 0
}

# --- 32. DOMAIN VALIDATION HELPER ---
# Validates domain-style value without protocol or slash.
function validate_domain() {
    local domain="$1"

    if [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
        return 0
    fi

    return 1
}

# --- 33. EMAIL VALIDATION HELPER ---
# Simple email format validation for Cloudflare email.
function validate_email() {
    local email="$1"

    if [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
        return 0
    fi

    return 1
}

# --- 34. CLOUDFLARE ZONE ID VALIDATION HELPER ---
# Allows empty value, otherwise expects a hex-like Cloudflare zone ID.
function validate_cf_zone_id() {
    local zone_id="$1"

    if [ -z "$zone_id" ]; then
        return 0
    fi

    if [[ "$zone_id" =~ ^[A-Fa-f0-9]{16,64}$ ]]; then
        return 0
    fi

    return 1
}

# --- 35. HTPASSWD LINE VALIDATION HELPER ---
# Validates that provided htpasswd line looks like username:hash.
function validate_htpasswd_line() {
    local line="$1"

    if [[ "$line" =~ ^[^:[:space:]]+:.+ ]]; then
        return 0
    fi

    return 1
}

# --- 36. DEPENDENCY VALIDATION ---
# Validates required commands early so failures happen before partial file creation.
function validate_dependencies() {
    local required_commands=(
        awk
        cat
        chmod
        clear
        chown
        command
        cut
        date
        grep
        id
        mkdir
        mktemp
        openssl
        rm
        sed
        stat
        tee
        test
        touch
        tput
        tr
        xargs
    )

    local cmd=""

    for cmd in "${required_commands[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || msg_error "Required command not found: ${cmd}"
    done

    if [ -n "$SUDO_CMD" ]; then
        command -v sudo >/dev/null 2>&1 || msg_error "sudo is required when not running as root."
    fi

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        msg_error "Either curl or wget is required to download Traefik template files."
    fi
}

# =========================================================
#  SECRET HELPERS
# =========================================================

# --- 37. SECRET GENERATOR HELPER ---
# Generates hex-only secrets. Hex avoids shell/YAML/SQL quoting problems.
function generate_secret() {
    openssl rand -hex 32 | cut -c1-48
}

# --- 38. SECRET REUSE / GENERATION HELPER ---
# Reuses existing secret files by default on reruns.
# Generates a new value only when missing or when regeneration is selected.
function get_or_generate_secret() {
    local file="$1"

    if [ "$REGENERATE_SECRETS" != "y" ] && root_file_not_empty "$file"; then
        root_read_file "$file"
    else
        generate_secret
    fi
}

# --- 39. NO-NEWLINE SECRET WRITE HELPER ---
# Writes secret files without trailing newline.
# This is intentional for file-based secrets.
function write_secret_file_no_newline() {
    local path="$1"
    local value="$2"

    if [ -n "$SUDO_CMD" ]; then
        printf '%s' "$value" | "$SUDO_CMD" tee "$path" >/dev/null
    else
        printf '%s' "$value" > "$path"
    fi
}

# --- 39A. DOWNLOAD FILE HELPER ---
# Downloads a public template file to a temporary path without printing its content.
# Uses curl when available and falls back to wget.
function download_file() {
    local url="$1"
    local dest="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    else
        wget -qO "$dest" "$url"
    fi
}

# --- 39B. TRAEFIK TEMPLATE RENDER HELPER ---
# Replaces public-safe placeholders in downloaded Traefik templates.
# Secret values are never embedded into Traefik config files.
# Cloudflare and htpasswd credentials remain file-based Docker secrets.
function render_traefik_template() {
    local src="$1"
    local dest="$2"
    local content=""
    local proxmox_block=""

    content="$(cat "$src")"
    proxmox_block="$(build_proxmox_route_block)"

    content="${content//\{\{DOCKER_DIR\}\}/$DOCKER_DIR}"
    content="${content//\{\{DOMAIN\}\}/$DOMAIN_VALUE}"
    content="${content//\{\{CF_API_EMAIL\}\}/$CF_API_EMAIL_VALUE}"
    content="${content//\{\{TRAEFIK_DASHBOARD_HOST\}\}/$TRAEFIK_DASHBOARD_HOST}"
    content="${content//\{\{TRAEFIK_ACME_EMAIL\}\}/$CF_API_EMAIL_VALUE}"
    content="${content//\{\{CF_API_TOKEN_SECRET_PATH\}\}//run/secrets/cf_api_token}"
    content="${content//\{\{HTPASSWD_SECRET_PATH\}\}//run/secrets/htpasswd}"
    content="${content//\{\{PROXMOX_ROUTE_BLOCK\}\}/$proxmox_block}"

    if grep -q '{{CF_API_TOKEN\|{{CLOUDFLARE_API_TOKEN' <<< "$content"; then
        msg_error "Traefik template contains a raw token placeholder. Use file-based token placeholders only."
    fi

    printf '%s\n' "$content" | write_root_file "$dest"
}

# --- 39C. TRAEFIK DYNAMIC ROUTER BLOCK HELPER ---
# Builds dynamic file-provider routers/services for Traefik itself and optional Proxmox routing.
# The Traefik dashboard router is always generated.
# Proxmox routing is disabled by default and only generated when explicitly selected.
function build_proxmox_route_block() {
    cat <<EOF
  # -------------------------------------------------------
  # FILE-PROVIDER ROUTERS
  # -------------------------------------------------------
  routers:
    traefik-dashboard:
      entryPoints:
        - https
      rule: Host(\`${TRAEFIK_DASHBOARD_HOST}\`)
      middlewares:
        - chain-authentik@file
      tls:
        certResolver: cloudflare
      service: api@internal
EOF

    if [ "$PROXMOX_ROUTE_ENABLED" != "y" ]; then
        cat <<'EOF'

  # Proxmox routing was disabled during setup.
EOF
        return 0
    fi

    cat <<EOF

    proxmox:
      entryPoints:
        - https
      rule: Host(\`${PROXMOX_HOST}\`)
      middlewares:
        - chain-authentik@file
      tls:
        certResolver: cloudflare
      service: proxmox

  # -------------------------------------------------------
  # FILE-PROVIDER SERVICES
  # -------------------------------------------------------
  services:
    proxmox:
      loadBalancer:
        serversTransport: proxmoxTransport
        passHostHeader: true
        servers:
          - url: "${PROXMOX_URL}"

  # -------------------------------------------------------
  # TARGETED SERVER TRANSPORTS
  # -------------------------------------------------------
  # Only Proxmox gets insecureSkipVerify because Proxmox commonly uses a self-signed local cert.
  # Do not use global insecureSkipVerify.
  serversTransports:
    proxmoxTransport:
      insecureSkipVerify: true
EOF
}

# =========================================================
#  INITIALIZATION
# =========================================================

# --- 40. SCRIPT INITIALIZATION ---
# Detects sudo, validates access, starts logging, installs traps, shows banner and validates dependencies.
function init_script() {
    detect_root_or_sudo
    validate_sudo_access
    init_logging

    trap 'on_error "$LINENO"' ERR
    trap cleanup EXIT

    clear
    header_info

    validate_dependencies
}

# --- 41. PREVIOUS MARKER CHECK ---
# Warns if Docker ENV setup was already completed before.
function check_previous_marker() {
    local continue_yn=""

    if root_path_exists "$COMPLETED_MARKER"; then
        section "PREVIOUS DOCKER ENV SETUP MARKER DETECTED"

        echo -e "${YW}A previous Docker ENV Setup marker exists:${CL} ${GN}${COMPLETED_MARKER}${CL}"
        echo ""
        root_read_file "$COMPLETED_MARKER" 2>/dev/null || true
        echo ""

        continue_yn="$(timed_yes_no "Continue anyway?" "n")"

        if [[ "$continue_yn" =~ ^[Nn] ]]; then
            exit 0
        fi
    fi
}

# =========================================================
#  INPUT COLLECTION
# =========================================================

# --- 42. START CONFIRMATION ---
# Starts Docker ENV setup after showing a clear description.
function start_confirmation() {
    local start_yn=""

    section "START"

    echo -e "${YW}This script creates Docker folders, .env and service secrets for the Home-Hosted Social Media SaaS project.${CL}"
    echo -e "${YW}Secrets are written to .env and ${DEFAULT_USER}'s Docker secrets folder.${CL}"
    echo -e "${YW}Sensitive input and final secret display bypass tee logging.${CL}"
    echo ""

    start_yn="$(timed_yes_no "Start the Docker ENV Setup Script?" "y")"

    if [[ "$start_yn" =~ ^[Nn] ]]; then
        exit 0
    fi

    return 0
}

# --- 43. DOCKER READINESS CHECK ---
# Checks that script 5 likely ran successfully before this script.
function check_docker_readiness() {
    section "DOCKER READINESS CHECK"

    msg_info "Checking Docker readiness"

    if command -v docker >/dev/null 2>&1 && docker --version >/dev/null 2>&1; then
        DOCKER_READY="yes"
    elif command -v docker >/dev/null 2>&1 && [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker --version >/dev/null 2>&1; then
        DOCKER_READY="yes"
    else
        DOCKER_READY="no"
    fi

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_READY="yes"
    elif command -v docker >/dev/null 2>&1 && [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_READY="yes"
    else
        DOCKER_COMPOSE_READY="no"
    fi

    msg_ok "DOCKER READINESS CHECK COMPLETE"

    echo ""
    detail_line "DOCKER CLI" "$DOCKER_READY"
    detail_line "DOCKER COMPOSE" "$DOCKER_COMPOSE_READY"

    if [ "$DOCKER_READY" != "yes" ] || [ "$DOCKER_COMPOSE_READY" != "yes" ]; then
        msg_warn "Docker or Docker Compose was not detected. Script 5 should normally run before this script."
    fi
}

# --- 44. USER AND PATH INPUTS ---
# Collects and validates Docker user, user home path and Docker project path.
function collect_user_and_path_inputs() {
    section "USER / PATH CONFIGURATION"

    while true; do
        DOCKER_USER="$(timed_text_input "Enter Linux username" "$DEFAULT_USER")"

        if validate_linux_username "$DOCKER_USER"; then
            break
        fi

        msg_warn "Invalid username. Use lowercase Linux username format, for example: dockeradmin"
    done

    if ! id "$DOCKER_USER" >/dev/null 2>&1; then
        msg_error "Linux user ${DOCKER_USER} does not exist. Run script 4 first or create the user."
    fi

    DEFAULT_USERDIR="/home/${DOCKER_USER}"
    DEFAULT_DOCKER_DIR="${DEFAULT_USERDIR}/docker"

    while true; do
        USERDIR="$(timed_text_input "Enter user home directory" "$DEFAULT_USERDIR")"

        if validate_absolute_path "$USERDIR"; then
            break
        fi

        msg_warn "Invalid user directory. Use a safe absolute path such as /home/${DOCKER_USER}"
    done

    DEFAULT_DOCKER_DIR="${USERDIR}/docker"

    while true; do
        DOCKER_DIR="$(timed_text_input "Enter Docker directory" "$DEFAULT_DOCKER_DIR")"

        if validate_absolute_path "$DOCKER_DIR"; then
            break
        fi

        msg_warn "Invalid Docker directory. Use a safe absolute path such as /home/${DOCKER_USER}/docker"
    done

    DOCKER_SECRETS_DIR="${DOCKER_DIR}/secrets"
    CF_API_TOKEN_FILE="${DOCKER_SECRETS_DIR}/cf_api_token"

    PUID_VALUE="$(id -u "$DOCKER_USER")"
    PGID_VALUE="$(id -g "$DOCKER_USER")"

    if id -nG "$DOCKER_USER" 2>/dev/null | grep -qw docker; then
        DOCKER_USER_IN_DOCKER_GROUP="yes"
    else
        DOCKER_USER_IN_DOCKER_GROUP="no"
        msg_warn "User ${DOCKER_USER} is not currently in docker group. Script 5 should add it; reboot/login may be needed."
    fi
}

# --- 45. EXISTING SETUP DETECTION ---
# Detects existing .env, secrets folder or marker to prevent accidental secret rotation.
function detect_existing_setup() {
    local continue_existing_yn=""
    local regenerate_yn=""

    section "EXISTING SETUP CHECK"

    msg_info "Checking for existing Docker ENV setup"

    if root_path_exists "$COMPLETED_MARKER" || root_path_exists "${DOCKER_DIR}/.env" || root_path_exists "${DOCKER_SECRETS_DIR}"; then
        EXISTING_SETUP="yes"
    else
        EXISTING_SETUP="no"
    fi

    if [ "$EXISTING_SETUP" == "yes" ]; then
        msg_warn "Existing Docker ENV setup detected"
        echo ""
        echo -e "${RD}WARNING: Existing Docker ENV setup detected.${CL}"
        echo -e "${YW}Re-running can overwrite .env and service secret files.${CL}"
        echo -e "${YW}Existing secrets will be reused unless you explicitly choose to regenerate them.${CL}"
        echo ""

        continue_existing_yn="$(timed_yes_no "Continue with existing Docker ENV setup?" "n")"

        if [[ "$continue_existing_yn" =~ ^[Nn] ]]; then
            echo -e "${YW}Docker ENV setup cancelled. Existing files were left untouched.${CL}"
            exit 0
        fi

        regenerate_yn="$(timed_yes_no "Regenerate all service secrets?" "n")"

        if [[ "$regenerate_yn" =~ ^[Yy] ]]; then
            REGENERATE_SECRETS="y"
            msg_warn "Secret regeneration selected. Existing deployed containers may need rebuilding."
        else
            REGENERATE_SECRETS="n"
            msg_ok "EXISTING SECRETS WILL BE REUSED WHERE PRESENT"
        fi
    else
        REGENERATE_SECRETS="n"
        msg_ok "NO EXISTING DOCKER ENV SETUP DETECTED"
    fi
}

# --- 46. DOMAIN / CLOUDFLARE INPUTS ---
# Collects and validates timezone, domain, Cloudflare email/zone ID and token.
function collect_domain_cloudflare_inputs() {
    section "DOMAIN / CLOUDFLARE"

    TZ_VALUE="$(timed_text_input "Enter timezone" "$DEFAULT_TZ")"

    while true; do
        DOMAIN_VALUE="$(timed_text_input "Enter domain" "$DEFAULT_DOMAIN")"

        if validate_domain "$DOMAIN_VALUE"; then
            break
        fi

        msg_warn "Invalid domain. Use a bare domain such as example.com, without https:// or slashes."
    done

    while true; do
        CF_API_EMAIL_VALUE="$(timed_text_input "Enter Cloudflare API Email" "$DEFAULT_CF_API_EMAIL")"

        if validate_email "$CF_API_EMAIL_VALUE"; then
            break
        fi

        msg_warn "Invalid email format."
    done

    while true; do
        CF_ZONE_ID_VALUE="$(timed_text_input "Enter Cloudflare Zone ID or leave empty" "$DEFAULT_CF_ZONE_ID")"

        if validate_cf_zone_id "$CF_ZONE_ID_VALUE"; then
            break
        fi

        msg_warn "Invalid Cloudflare Zone ID. Leave empty or enter the hex zone ID."
    done

    disable_logging
    CF_API_TOKEN_VALUE="$(sensitive_line_input "Enter Cloudflare API Token, or leave empty")"
    enable_logging

    CF_API_TOKEN_VALUE="$(printf '%s' "$CF_API_TOKEN_VALUE" | tr -d '\r\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ -z "$CF_API_TOKEN_VALUE" ] && root_file_not_empty "$CF_API_TOKEN_FILE"; then
        CF_API_TOKEN_VALUE="$(root_read_file "$CF_API_TOKEN_FILE")"
        msg_ok "EXISTING CLOUDFLARE API TOKEN WILL BE REUSED"
    elif [ -z "$CF_API_TOKEN_VALUE" ]; then
        msg_warn "Cloudflare API token left empty. Traefik DNS challenge, cf-ddns, and cf-companion will need this later."
    else
        msg_ok "CLOUDFLARE API TOKEN CAPTURED"
    fi
}

# --- 46A. TRAEFIK CONFIG INPUTS ---
# Collects non-secret Traefik values used to render template config files.
# Cloudflare token stays in ${CF_API_TOKEN_FILE}; it is never embedded into Traefik YAML.
function collect_traefik_inputs() {
    local default_traefik_host="traefik.${DOMAIN_VALUE}"
    local proxmox_yn=""
    local default_proxmox_host="proxmox.${DOMAIN_VALUE}"
    local default_proxmox_url="https://192.168.1.10:8006"

    section "TRAEFIK CONFIG"

    while true; do
        TRAEFIK_DASHBOARD_HOST="$(timed_text_input "Enter Traefik dashboard host" "$default_traefik_host")"

        if validate_domain "$TRAEFIK_DASHBOARD_HOST"; then
            break
        fi

        msg_warn "Invalid Traefik host. Use a bare hostname such as traefik.${DOMAIN_VALUE}."
    done

    proxmox_yn="$(timed_yes_no "Create optional Proxmox route in Traefik dynamic config?" "n")"

    if [[ "$proxmox_yn" =~ ^[Yy] ]]; then
        PROXMOX_ROUTE_ENABLED="y"

        while true; do
            PROXMOX_HOST="$(timed_text_input "Enter Proxmox hostname" "$default_proxmox_host")"

            if validate_domain "$PROXMOX_HOST"; then
                break
            fi

            msg_warn "Invalid Proxmox hostname. Use a bare hostname such as proxmox.${DOMAIN_VALUE}."
        done

        PROXMOX_URL="$(timed_text_input "Enter Proxmox internal URL" "$default_proxmox_url")"
        msg_ok "PROXMOX ROUTE WILL BE CREATED"
    else
        PROXMOX_ROUTE_ENABLED="n"
        PROXMOX_HOST=""
        PROXMOX_URL=""
        msg_ok "PROXMOX ROUTE SKIPPED"
    fi

    TRAEFIK_DIR="${DOCKER_DIR}/appdata/traefik"
    TRAEFIK_ACME_DIR="${TRAEFIK_DIR}/acme"
    TRAEFIK_STATIC_CONFIG_FILE="${TRAEFIK_DIR}/traefik.yml"
    TRAEFIK_DYNAMIC_CONFIG_FILE="${TRAEFIK_DIR}/dynamic-config.yml"
}

# --- 47. HTPASSWD OPTIONAL INPUT ---
# Handles optional Traefik basic-auth credentials without logging sensitive values.
# If username/password is entered, final output shows only the generated hashed htpasswd line.
# If full htpasswd line is provided, final output does not show the provided hash.
function collect_htpasswd_inputs() {
    local has_htpasswd_yn=""
    local create_htpasswd_yn=""

    section "OPTIONAL HTPASSWD"

    echo -e "${BL}Optional Traefik basic-auth htpasswd setup.${CL}"
    echo -e "${YW}Not required if you use Authentik, Authelia, or a similar SSO/auth gateway.${CL}"
    echo -e "${YW}If a password is entered, this script will generate a SHA-512 htpasswd hash.${CL}"
    echo -e "${YW}If a full htpasswd line is provided, it will be saved but not displayed in final output.${CL}"
    echo ""

    has_htpasswd_yn="$(timed_yes_no "Do you already have a hashed htpasswd line?" "n")"

    if [[ "$has_htpasswd_yn" =~ ^[Yy] ]]; then
        disable_logging
        HTPASSWD_LINE_VALUE="$(sensitive_line_input "Paste full htpasswd line username:hash")"
        enable_logging

        HTPASSWD_LINE_VALUE="$(printf '%s' "$HTPASSWD_LINE_VALUE" | tr -d '\r\n')"

        if [ -n "$HTPASSWD_LINE_VALUE" ]; then
            if validate_htpasswd_line "$HTPASSWD_LINE_VALUE"; then
                HTPASSWD_MODE="provided"
            else
                HTPASSWD_LINE_VALUE=""
                HTPASSWD_MODE="empty"
                msg_warn "Provided htpasswd line did not look valid. Empty placeholder will be used unless an existing file is present."
            fi
        fi
    else
        create_htpasswd_yn="$(timed_yes_no "Create htpasswd entry now?" "n")"

        if [[ "$create_htpasswd_yn" =~ ^[Yy] ]]; then
            HTPASSWD_USER_VALUE="$(timed_text_input "Enter htpasswd username" "$DEFAULT_HTPASSWD_USER")"

            disable_logging
            HTPASSWD_PASSWORD_VALUE="$(hidden_input "Enter htpasswd password")"
            enable_logging

            if [ -n "$HTPASSWD_PASSWORD_VALUE" ]; then
                HTPASSWD_HASH_VALUE="$(openssl passwd -6 "$HTPASSWD_PASSWORD_VALUE")"
                HTPASSWD_LINE_VALUE="${HTPASSWD_USER_VALUE}:${HTPASSWD_HASH_VALUE}"
                HTPASSWD_PASSWORD_VALUE=""
                HTPASSWD_MODE="generated"
            else
                HTPASSWD_MODE="empty"
                msg_warn "htpasswd password was empty. Empty placeholder will be used unless an existing file is present."
            fi
        else
            HTPASSWD_MODE="empty"
        fi
    fi
}


# --- 47B. AUTHENTIK BOOTSTRAP INPUTS ---
# Collects first-login Authentik bootstrap values and keeps them separate from Authentik API tokens.
# AUTHENTIK_BOOTSTRAP_TOKEN is not an API bearer token; Script 7 asks for a real API token later if automation is desired.
function collect_authentik_bootstrap_inputs() {
    local default_auth_host="https://auth.${DOMAIN_VALUE}"
    local use_cf_email=""
    local create_password=""
    local create_token=""

    section "AUTHENTIK BOOTSTRAP"

    echo -e "${BL}Authentik needs bootstrap admin values for the first fresh deployment.${CL}"
    echo -e "${YW}These are written to .env and displayed once with other secrets.${CL}"
    echo -e "${YW}Important: AUTHENTIK_BOOTSTRAP_TOKEN is NOT an Authentik API token.${CL}"
    echo ""

    AUTHENTIK_HOST_VALUE="$(timed_text_input "Enter Authentik external host, example https://auth.example.com" "$default_auth_host")"
    AUTHENTIK_HOST_BROWSER_VALUE="$(timed_text_input "Enter Authentik browser host, example https://auth.example.com" "$AUTHENTIK_HOST_VALUE")"

    use_cf_email="$(timed_yes_no "Use Cloudflare email as Authentik bootstrap admin email?" "y")"
    if [[ "$use_cf_email" =~ ^[Yy]$ ]]; then
        AUTHENTIK_BOOTSTRAP_EMAIL_VALUE="$CF_API_EMAIL_VALUE"
        msg_ok "AUTHENTIK BOOTSTRAP EMAIL SET FROM CLOUDFLARE EMAIL"
    else
        while true; do
            AUTHENTIK_BOOTSTRAP_EMAIL_VALUE="$(timed_text_input "Enter Authentik bootstrap admin email" "$CF_API_EMAIL_VALUE")"
            if validate_email "$AUTHENTIK_BOOTSTRAP_EMAIL_VALUE"; then
                break
            fi
            msg_warn "Invalid email format."
        done
    fi

    create_password="$(timed_yes_no "Auto-generate Authentik bootstrap password?" "y")"
    if [[ "$create_password" =~ ^[Yy]$ ]]; then
        AUTHENTIK_BOOTSTRAP_PASSWORD="$(generate_secret)"
        msg_ok "AUTHENTIK BOOTSTRAP PASSWORD GENERATED"
    else
        disable_logging
        AUTHENTIK_BOOTSTRAP_PASSWORD="$(sensitive_line_input "Enter Authentik bootstrap password")"
        enable_logging
        if [ -z "$AUTHENTIK_BOOTSTRAP_PASSWORD" ]; then
            AUTHENTIK_BOOTSTRAP_PASSWORD="$(generate_secret)"
            msg_warn "Empty password entered; generated one instead."
        fi
    fi

    create_token="$(timed_yes_no "Auto-generate Authentik bootstrap token?" "y")"
    if [[ "$create_token" =~ ^[Yy]$ ]]; then
        AUTHENTIK_BOOTSTRAP_TOKEN="$(generate_secret)"
        msg_ok "AUTHENTIK BOOTSTRAP TOKEN GENERATED"
    else
        disable_logging
        AUTHENTIK_BOOTSTRAP_TOKEN="$(sensitive_line_input "Enter Authentik bootstrap token")"
        enable_logging
        if [ -z "$AUTHENTIK_BOOTSTRAP_TOKEN" ]; then
            AUTHENTIK_BOOTSTRAP_TOKEN="$(generate_secret)"
            msg_warn "Empty token entered; generated one instead."
        fi
    fi

    detail_line "Authentik host" "$AUTHENTIK_HOST_VALUE"
    detail_line "Authentik bootstrap email" "$AUTHENTIK_BOOTSTRAP_EMAIL_VALUE"
    echo -e "${YW}Script 7 will ask separately for an Authentik API token if API automation is wanted.${CL}"
}

# =========================================================
#  FILE / SECRET CREATION
# =========================================================

# --- 48. DOCKER DIRECTORY CREATION ---
# Creates project folders for compose, appdata, backups, shared files and secrets.
function create_docker_directories() {
    section "DOCKER FOLDER STRUCTURE"

    msg_info "Creating Docker folder structure"

    run_cmd "creating Docker appdata directory" mkdir -p "${DOCKER_DIR}/appdata"
    run_cmd "creating Docker compose directory" mkdir -p "${DOCKER_DIR}/compose"
    run_cmd "creating Docker backups directory" mkdir -p "${DOCKER_DIR}/backups"
    run_cmd "creating Docker shared directory" mkdir -p "${DOCKER_DIR}/shared"
    run_cmd "creating Docker secrets directory" mkdir -p "${DOCKER_SECRETS_DIR}"

    run_cmd "creating PostgreSQL data directory" mkdir -p "${DOCKER_DIR}/appdata/postgres/data"
    run_cmd "creating PostgreSQL init directory" mkdir -p "${DOCKER_DIR}/appdata/postgres/init"
    run_cmd "creating Redis data directory" mkdir -p "${DOCKER_DIR}/appdata/redis"
    run_cmd "creating Postiz uploads directory" mkdir -p "${DOCKER_DIR}/appdata/postiz/uploads"

    run_cmd "creating Traefik config directory" mkdir -p "${TRAEFIK_DIR}"
    run_cmd "creating Traefik ACME directory" mkdir -p "${TRAEFIK_ACME_DIR}"
    run_cmd "creating Traefik ACME storage" touch "${TRAEFIK_ACME_DIR}/acme.json"

    msg_ok "DOCKER FOLDERS CREATED"
}

# --- 49. SECRET GENERATION / REUSE ---
# Generates service secrets on first run. On reruns, reuses existing secret files unless regeneration was explicitly selected.
function generate_or_reuse_secrets() {
    section "SECRET GENERATION / REUSE"

    msg_info "Generating or reusing secrets"

    POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/postgres_password")"
    REDIS_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/redis_password")"
    AUTHENTIK_SECRET_KEY="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/authentik_secret_key")"
    AUTHENTIK_POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/authentik_postgres_password")"
    POSTIZ_POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/postiz_postgres_password")"
    POSTIZ_JWT_SECRET="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/postiz_jwt_secret")"
    TEMPORAL_POSTGRES_PASSWORD="$(get_or_generate_secret "${DOCKER_SECRETS_DIR}/temporal_postgres_password")"

    msg_ok "SECRETS GENERATED / REUSED"
}

# --- 50. POSTGRES INIT SCRIPT CREATION ---
# Creates unattended PostgreSQL init script for app databases on first PostgreSQL container startup.
function create_postgres_init_script() {
    section "POSTGRES INIT SCRIPT"

    msg_info "Writing PostgreSQL unattended app database init script"

    write_root_file "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

create_user_and_db() {
    local app_user="$1"
    local app_db="$2"
    local app_password="$3"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT FROM pg_catalog.pg_roles
        WHERE rolname = '${app_user}'
    ) THEN
        CREATE USER ${app_user} WITH PASSWORD '${app_password}';
    ELSE
        ALTER USER ${app_user} WITH PASSWORD '${app_password}';
    END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${app_db} OWNER ${app_user}'
WHERE NOT EXISTS (
    SELECT FROM pg_database
    WHERE datname = '${app_db}'
)\gexec

GRANT ALL PRIVILEGES ON DATABASE ${app_db} TO ${app_user};
SQL
}

: "${AUTHENTIK_POSTGRES_PASSWORD:?AUTHENTIK_POSTGRES_PASSWORD is required}"
: "${POSTIZ_POSTGRES_PASSWORD:?POSTIZ_POSTGRES_PASSWORD is required}"
: "${TEMPORAL_POSTGRES_PASSWORD:?TEMPORAL_POSTGRES_PASSWORD is required}"

create_user_and_db "authentik" "authentik" "$AUTHENTIK_POSTGRES_PASSWORD"
create_user_and_db "postiz" "postiz" "$POSTIZ_POSTGRES_PASSWORD"
create_user_and_db "temporal" "temporal" "$TEMPORAL_POSTGRES_PASSWORD"
EOF

    run_cmd "making PostgreSQL init script executable" chmod 755 "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"

    msg_ok "POSTGRES INIT SCRIPT CREATED"
}

# --- 50A. TRAEFIK CONFIG TEMPLATE RENDERING ---
# Downloads public Traefik template files from GitHub and renders local config files.
# Only non-secret placeholders are replaced. Cloudflare token remains file-based via Docker secret.
function create_traefik_config_files() {
    local static_template=""
    local dynamic_template=""

    section "TRAEFIK CONFIG FILES"

    msg_info "Preparing temporary Traefik template workspace"
    TRAEFIK_TEMPLATE_TMP_DIR="$(mktemp -d /tmp/traefik-template-render.XXXXXX)"
    TEMP_DIRS+=("$TRAEFIK_TEMPLATE_TMP_DIR")
    static_template="${TRAEFIK_TEMPLATE_TMP_DIR}/traefik.yml.template"
    dynamic_template="${TRAEFIK_TEMPLATE_TMP_DIR}/dynamic-config.yml.template"
    msg_ok "TRAEFIK TEMPLATE WORKSPACE READY"

    msg_info "Downloading Traefik static template"
    download_file "$TRAEFIK_STATIC_TEMPLATE_URL" "$static_template" || msg_error "Failed to download Traefik template: ${TRAEFIK_STATIC_TEMPLATE_URL}"
    msg_ok "TRAEFIK STATIC TEMPLATE DOWNLOADED"

    msg_info "Downloading Traefik dynamic template"
    download_file "$TRAEFIK_DYNAMIC_TEMPLATE_URL" "$dynamic_template" || msg_error "Failed to download Traefik template: ${TRAEFIK_DYNAMIC_TEMPLATE_URL}"
    msg_ok "TRAEFIK DYNAMIC TEMPLATE DOWNLOADED"

    msg_info "Rendering Traefik static config"
    render_traefik_template "$static_template" "$TRAEFIK_STATIC_CONFIG_FILE"
    msg_ok "TRAEFIK STATIC CONFIG CREATED"

    msg_info "Rendering Traefik dynamic config"
    render_traefik_template "$dynamic_template" "$TRAEFIK_DYNAMIC_CONFIG_FILE"
    msg_ok "TRAEFIK DYNAMIC CONFIG CREATED"

    msg_info "Securing Traefik ACME storage"
    run_cmd "setting Traefik ACME storage permissions" chmod 600 "${TRAEFIK_ACME_DIR}/acme.json"
    msg_ok "TRAEFIK ACME STORAGE READY"
}

# --- 51. SECRET FILE CREATION ---
# Writes generated/reused secrets to individual secret files.
function write_secret_files() {
    section "SECRET FILES"

    msg_info "Writing secret files"

    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/postgres_password" "$POSTGRES_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/redis_password" "$REDIS_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/authentik_secret_key" "$AUTHENTIK_SECRET_KEY"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/authentik_postgres_password" "$AUTHENTIK_POSTGRES_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/postiz_postgres_password" "$POSTIZ_POSTGRES_PASSWORD"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/postiz_jwt_secret" "$POSTIZ_JWT_SECRET"
    write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/temporal_postgres_password" "$TEMPORAL_POSTGRES_PASSWORD"

    if [ -n "$CF_API_TOKEN_VALUE" ]; then
        write_secret_file_no_newline "$CF_API_TOKEN_FILE" "$CF_API_TOKEN_VALUE"
    elif root_file_not_empty "$CF_API_TOKEN_FILE"; then
        msg_ok "EXISTING CLOUDFLARE TOKEN FILE PRESERVED"
    else
        run_cmd "creating empty Cloudflare API token placeholder" touch "$CF_API_TOKEN_FILE"
    fi

    if [ -n "$HTPASSWD_LINE_VALUE" ]; then
        write_secret_file_no_newline "${DOCKER_SECRETS_DIR}/htpasswd" "$HTPASSWD_LINE_VALUE"
    elif root_file_not_empty "${DOCKER_SECRETS_DIR}/htpasswd"; then
        msg_ok "EXISTING HTPASSWD FILE PRESERVED"
    else
        run_cmd "creating empty htpasswd placeholder" touch "${DOCKER_SECRETS_DIR}/htpasswd"
    fi

    msg_ok "SECRET FILES WRITTEN"
}

# --- 52. ENV FILE CREATION ---
# Creates /updates Docker .env used by docker compose CLI and Portainer stacks.
# This file contains secrets and is locked down to 600 later.
function write_env_file() {
    section "DOCKER .ENV"

    msg_info "Creating Docker .env file"

    write_root_file "${DOCKER_DIR}/.env" <<EOF
# =========================================================
#  Project: Home-Hosted Social Media SaaS
# =========================================================

# --- Core paths ---
DOCKER_DIR="${DOCKER_DIR}"
DOCKER_SECRETS_DIR="${DOCKER_SECRETS_DIR}"
USERDIR="${USERDIR}"

# --- Linux user/container IDs ---
PUID="${PUID_VALUE}"
PGID="${PGID_VALUE}"

# --- Localisation ---
TZ="${TZ_VALUE}"

# --- Domain / Cloudflare ---
DOMAIN="${DOMAIN_VALUE}"
CF_API_EMAIL="${CF_API_EMAIL_VALUE}"
CF_ZONE_ID="${CF_ZONE_ID_VALUE}"
CF_API_TOKEN_FILE="${CF_API_TOKEN_FILE}"
CF_AUTH_METHOD="api_token"

# --- PostgreSQL root/admin password ---
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"

# --- Redis ---
REDIS_PASSWORD="${REDIS_PASSWORD}"

# --- Authentik ---
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY}"
AUTHENTIK_POSTGRES_PASSWORD="${AUTHENTIK_POSTGRES_PASSWORD}"
AUTHENTIK_HOST="${AUTHENTIK_HOST_VALUE}"
AUTHENTIK_HOST_BROWSER="${AUTHENTIK_HOST_BROWSER_VALUE}"
AUTHENTIK_BOOTSTRAP_EMAIL="${AUTHENTIK_BOOTSTRAP_EMAIL_VALUE}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD}"
AUTHENTIK_BOOTSTRAP_TOKEN="${AUTHENTIK_BOOTSTRAP_TOKEN}"

# --- Postiz ---
POSTIZ_POSTGRES_PASSWORD="${POSTIZ_POSTGRES_PASSWORD}"
POSTIZ_JWT_SECRET="${POSTIZ_JWT_SECRET}"

# --- Temporal ---
TEMPORAL_POSTGRES_PASSWORD="${TEMPORAL_POSTGRES_PASSWORD}"
EOF

    msg_ok "DOCKER .ENV CREATED"
}

# --- 53. PERMISSIONS ---
# Applies secure permissions without breaking PostgreSQL init script readability.
# .env and secret files are treated as high-value secret material.
function apply_permissions() {
    section "PERMISSIONS"

    msg_info "Applying service-specific ownership and permissions"

    # Base project ownership: keep only top-level project folders user-owned.
    # Do not recursively chown all appdata because database containers use service UIDs.
    run_cmd "setting Docker root ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "$DOCKER_DIR" "${DOCKER_DIR}/compose" "${DOCKER_DIR}/backups" "${DOCKER_DIR}/shared" "${DOCKER_SECRETS_DIR}"
    run_cmd "setting appdata root ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/appdata"

    # Database services: must be owned by the container UID, not by the login user.
    run_cmd "setting PostgreSQL data ownership" chown -R 999:999 "${DOCKER_DIR}/appdata/postgres/data"
    run_cmd "setting PostgreSQL data permissions" chmod 700 "${DOCKER_DIR}/appdata/postgres/data"
    run_cmd "setting PostgreSQL init ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/appdata/postgres/init"
    run_cmd "setting PostgreSQL init permissions" chmod 755 "${DOCKER_DIR}/appdata/postgres/init"
    run_cmd "setting PostgreSQL init script permissions" chmod 755 "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"

    run_cmd "setting Redis data ownership" chown -R 999:999 "${DOCKER_DIR}/appdata/redis"
    run_cmd "setting Redis writable permissions" chmod -R u+rwX,g-rwx,o-rwx "${DOCKER_DIR}/appdata/redis"

    # Authentik runs non-root and needs write access to media/templates/certs bind mounts.
    run_cmd "setting Authentik ownership" chown -R 1000:1000 "${DOCKER_DIR}/appdata/authentik"
    run_cmd "setting Authentik permissions" chmod -R u+rwX,g-rwx,o-rwx "${DOCKER_DIR}/appdata/authentik"

    # User-facing safe folders.
    run_cmd "setting compose/shared/backups ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/compose" "${DOCKER_DIR}/shared" "${DOCKER_DIR}/backups"
    run_cmd "setting compose/shared/backups permissions" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/compose" "${DOCKER_DIR}/shared" "${DOCKER_DIR}/backups"

    run_cmd "setting Filebrowser ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/filebrowser"
    run_cmd "setting Filebrowser permissions" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/filebrowser"

    run_cmd "setting Postiz uploads ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/postiz"
    run_cmd "setting Postiz uploads permissions" chmod -R u+rwX,g+rwX,o-rwx "${DOCKER_DIR}/appdata/postiz"

    # Traefik config and ACME.
    run_cmd "setting Traefik ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${TRAEFIK_DIR}"
    run_cmd "setting Traefik config directory permissions" chmod 750 "${TRAEFIK_DIR}"
    run_cmd "setting Traefik ACME directory permissions" chmod 700 "${TRAEFIK_ACME_DIR}"
    run_cmd "setting Traefik static config permissions" chmod 644 "${TRAEFIK_STATIC_CONFIG_FILE}"
    run_cmd "setting Traefik dynamic config permissions" chmod 644 "${TRAEFIK_DYNAMIC_CONFIG_FILE}"
    run_cmd "setting Traefik ACME storage permissions" chmod 600 "${TRAEFIK_ACME_DIR}/acme.json"

    # Optional admin UI data directories.
    case "$ADMIN_UI" in
        dockge) run_cmd "setting Dockge ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/dockge" ;;
        portainer) run_cmd "setting Portainer ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/portainer" ;;
        komodo) run_cmd "setting Komodo ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/komodo" ;;
        dockhand) run_cmd "setting Dockhand ownership" chown -R "${PUID_VALUE}:${PGID_VALUE}" "${DOCKER_DIR}/appdata/dockhand" ;;
    esac

    # Secrets and .env.
    run_cmd "setting .env ownership" chown "${DOCKER_USER}:${DOCKER_USER}" "${DOCKER_DIR}/.env"
    run_cmd "setting .env permissions" chmod 600 "${DOCKER_DIR}/.env"
    run_cmd "setting secrets directory ownership" chown -R "${DOCKER_USER}:${DOCKER_USER}" "$DOCKER_SECRETS_DIR"
    run_cmd "setting secrets directory permissions" chmod 700 "$DOCKER_SECRETS_DIR"

    if compgen -G "${DOCKER_SECRETS_DIR}/*" > /dev/null; then
        run_cmd "setting secret file permissions" chmod 600 "${DOCKER_SECRETS_DIR}"/*
    fi

    msg_ok "SERVICE-SPECIFIC PERMISSIONS SET"
}

# =========================================================
#  VERIFICATION / MARKER / SUMMARY
# =========================================================

# --- 54. VERIFICATION REPORT ---
# Creates a verification report without printing secret values.
function create_verification_report() {
    section "VERIFICATION"

    msg_info "Creating Docker ENV verification report"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$VERIFY_LOG'" <<EOF
--- DOCKER ENV SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE

Results:
EOF
    else
        cat > "$VERIFY_LOG" <<EOF
--- DOCKER ENV SETUP VERIFICATION REPORT ---
Date: $(date)
Docker user: $DOCKER_USER
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE

Results:
EOF
    fi

    {
        if id "$DOCKER_USER" >/dev/null 2>&1; then echo "✓ PASS - Docker user exists"; else echo "✗ FAIL - Docker user missing"; fi
        if [ -d "$DOCKER_DIR" ]; then echo "✓ PASS - Docker directory exists"; else echo "✗ FAIL - Docker directory missing"; fi
        if [ -f "${DOCKER_DIR}/.env" ]; then echo "✓ PASS - .env exists"; else echo "✗ FAIL - .env missing"; fi
        if [ "$(root_stat_mode "${DOCKER_DIR}/.env")" == "600" ]; then echo "✓ PASS - .env mode is 600"; else echo "! WARN - .env mode is not 600"; fi
        if [ -d "$DOCKER_SECRETS_DIR" ]; then echo "✓ PASS - secrets directory exists"; else echo "✗ FAIL - secrets directory missing"; fi
        if [ "$(root_stat_mode "$DOCKER_SECRETS_DIR")" == "700" ]; then echo "✓ PASS - secrets directory mode is 700"; else echo "! WARN - secrets directory mode is not 700"; fi

        for secret_file in \
            postgres_password \
            redis_password \
            authentik_secret_key \
            authentik_postgres_password \
            postiz_postgres_password \
            postiz_jwt_secret \
            temporal_postgres_password
        do
            if [ -s "${DOCKER_SECRETS_DIR}/${secret_file}" ]; then
                echo "✓ PASS - ${secret_file} exists and is non-empty"
            else
                echo "✗ FAIL - ${secret_file} missing or empty"
            fi

            if [ "$(root_stat_mode "${DOCKER_SECRETS_DIR}/${secret_file}")" == "600" ]; then
                echo "✓ PASS - ${secret_file} mode is 600"
            else
                echo "! WARN - ${secret_file} mode is not 600"
            fi
        done

        if [ -e "$CF_API_TOKEN_FILE" ]; then echo "✓ PASS - Cloudflare token file exists"; else echo "! WARN - Cloudflare token file missing"; fi
        if [ -e "${DOCKER_SECRETS_DIR}/htpasswd" ]; then echo "✓ PASS - htpasswd file exists"; else echo "! WARN - htpasswd file missing"; fi
        if [ -x "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh" ]; then echo "✓ PASS - PostgreSQL init script exists and is executable"; else echo "✗ FAIL - PostgreSQL init script missing or not executable"; fi
        if [ -f "$TRAEFIK_STATIC_CONFIG_FILE" ]; then echo "✓ PASS - Traefik static config exists"; else echo "✗ FAIL - Traefik static config missing"; fi
        if [ -f "$TRAEFIK_DYNAMIC_CONFIG_FILE" ]; then echo "✓ PASS - Traefik dynamic config exists"; else echo "✗ FAIL - Traefik dynamic config missing"; fi
        if [ -f "${TRAEFIK_ACME_DIR}/acme.json" ]; then echo "✓ PASS - Traefik acme.json exists"; else echo "✗ FAIL - Traefik acme.json missing"; fi
        if [ "$(root_stat_mode "${TRAEFIK_ACME_DIR}/acme.json")" == "600" ]; then echo "✓ PASS - Traefik acme.json mode is 600"; else echo "! WARN - Traefik acme.json mode is not 600"; fi
        if grep -q "POSTIZ_JWT_SECRET=" "${DOCKER_DIR}/.env"; then echo "✓ PASS - Postiz JWT secret env present"; else echo "✗ FAIL - Postiz JWT secret env missing"; fi
        if [ -s "${DOCKER_SECRETS_DIR}/postiz_jwt_secret" ]; then echo "✓ PASS - postiz_jwt_secret exists and is non-empty"; else echo "✗ FAIL - postiz_jwt_secret missing or empty"; fi

        if command -v docker >/dev/null 2>&1; then echo "✓ PASS - Docker CLI detected"; else echo "! WARN - Docker CLI not detected"; fi
        if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then echo "✓ PASS - Docker Compose plugin detected"; else echo "! WARN - Docker Compose plugin not detected for current shell"; fi
        if id -nG "$DOCKER_USER" 2>/dev/null | grep -qw docker; then echo "✓ PASS - Docker user is in docker group"; else echo "! WARN - Docker user is not currently in docker group"; fi

        if [ -f "$COMPLETED_MARKER" ]; then echo "✓ PASS - completion marker exists"; else echo "! WARN - completion marker not present yet at verification time"; fi
    } | if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee -a "$VERIFY_LOG" >/dev/null; else tee -a "$VERIFY_LOG" >/dev/null; fi

    msg_ok "DOCKER ENV VERIFICATION REPORT CREATED"
}

# --- 55. COMPLETION MARKER ---
# Creates marker showing ENV setup completed successfully.
# No secret values are stored in the marker.
function write_completion_marker() {
    section "COMPLETION MARKER"

    msg_info "Writing completion marker"

    if [ -n "$SUDO_CMD" ]; then
        "$SUDO_CMD" bash -c "cat > '$COMPLETED_MARKER'" <<EOF
Docker ENV Setup completed on: $(date)
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE
User: $DOCKER_USER
PUID: $PUID_VALUE
PGID: $PGID_VALUE
Timezone: $TZ_VALUE
Existing setup detected: $EXISTING_SETUP
Secrets regenerated: $REGENERATE_SECRETS
Cloudflare token file: $CF_API_TOKEN_FILE
Traefik static config: $TRAEFIK_STATIC_CONFIG_FILE
Traefik dynamic config: $TRAEFIK_DYNAMIC_CONFIG_FILE
Traefik ACME storage: ${TRAEFIK_ACME_DIR}/acme.json
Traefik dashboard host: $TRAEFIK_DASHBOARD_HOST
Proxmox route enabled: $PROXMOX_ROUTE_ENABLED
Htpasswd mode: $HTPASSWD_MODE
Docker ready: $DOCKER_READY
Docker Compose ready: $DOCKER_COMPOSE_READY
Docker user in docker group: $DOCKER_USER_IN_DOCKER_GROUP
Secret screen displayed: $SECRET_DISPLAY_WAS_SHOWN
Secret screen cleared: $SECRET_SCREEN_CLEARED
Verify log: $VERIFY_LOG
EOF
    else
        cat > "$COMPLETED_MARKER" <<EOF
Docker ENV Setup completed on: $(date)
Docker dir: $DOCKER_DIR
Secrets dir: $DOCKER_SECRETS_DIR
Domain: $DOMAIN_VALUE
User: $DOCKER_USER
PUID: $PUID_VALUE
PGID: $PGID_VALUE
Timezone: $TZ_VALUE
Existing setup detected: $EXISTING_SETUP
Secrets regenerated: $REGENERATE_SECRETS
Cloudflare token file: $CF_API_TOKEN_FILE
Traefik static config: $TRAEFIK_STATIC_CONFIG_FILE
Traefik dynamic config: $TRAEFIK_DYNAMIC_CONFIG_FILE
Traefik ACME storage: ${TRAEFIK_ACME_DIR}/acme.json
Traefik dashboard host: $TRAEFIK_DASHBOARD_HOST
Proxmox route enabled: $PROXMOX_ROUTE_ENABLED
Htpasswd mode: $HTPASSWD_MODE
Docker ready: $DOCKER_READY
Docker Compose ready: $DOCKER_COMPOSE_READY
Docker user in docker group: $DOCKER_USER_IN_DOCKER_GROUP
Secret screen displayed: $SECRET_DISPLAY_WAS_SHOWN
Secret screen cleared: $SECRET_SCREEN_CLEARED
Verify log: $VERIFY_LOG
EOF
    fi

    msg_ok "COMPLETION MARKER WRITTEN"
}

# --- 56. FINAL SECRET DISPLAY ---
# Shows generated/reused secret values once while logging is disabled.
# After user confirms they saved them, terminal and scrollback are cleared where supported.
function show_secrets_once_without_logging() {
    disable_logging

    SECRET_DISPLAY_WAS_SHOWN="yes"

    clear
    header_info

    echo -e "${RD}${CLF}SENSITIVE SECRET OUTPUT - NOT LOGGED${CL}"
    echo -e "${YW}Save these values now. This screen will be cleared after confirmation.${CL}"
    echo ""

    echo -e "${BL}CORE PATHS:${CL}"
    echo -e "DOCKER_DIR=${GN}${DOCKER_DIR}${CL}"
    echo -e "DOCKER_SECRETS_DIR=${GN}${DOCKER_SECRETS_DIR}${CL}"
    echo -e "USERDIR=${GN}${USERDIR}${CL}"
    echo ""

    echo -e "${BL}LINUX USER / IDS:${CL}"
    echo -e "DOCKER_USER=${GN}${DOCKER_USER}${CL}"
    echo -e "PUID=${GN}${PUID_VALUE}${CL}"
    echo -e "PGID=${GN}${PGID_VALUE}${CL}"
    echo ""

    echo -e "${BL}DOMAIN / CLOUDFLARE:${CL}"
    echo -e "DOMAIN=${GN}${DOMAIN_VALUE}${CL}"
    echo -e "CF_API_EMAIL=${GN}${CF_API_EMAIL_VALUE}${CL}"
    echo -e "CF_ZONE_ID=${GN}${CF_ZONE_ID_VALUE}${CL}"
    echo -e "CF_API_TOKEN_FILE=${GN}${CF_API_TOKEN_FILE}${CL}"
    echo -e "TRAEFIK_STATIC_CONFIG=${GN}${TRAEFIK_STATIC_CONFIG_FILE}${CL}"
    echo -e "TRAEFIK_DYNAMIC_CONFIG=${GN}${TRAEFIK_DYNAMIC_CONFIG_FILE}${CL}"
    echo -e "TRAEFIK_ACME_STORAGE=${GN}${TRAEFIK_ACME_DIR}/acme.json${CL}"

    if [ -n "$CF_API_TOKEN_VALUE" ]; then
        echo -e "CF_API_TOKEN=${GN}${CF_API_TOKEN_VALUE}${CL}"
    else
        echo -e "CF_API_TOKEN=${YW}<empty / not provided>${CL}"
    fi

    echo ""
    echo -e "${BL}SERVICE SECRETS:${CL}"
    echo -e "POSTGRES_PASSWORD=${GN}${POSTGRES_PASSWORD}${CL}"
    echo -e "REDIS_PASSWORD=${GN}${REDIS_PASSWORD}${CL}"
    echo -e "AUTHENTIK_SECRET_KEY=${GN}${AUTHENTIK_SECRET_KEY}${CL}"
    echo -e "AUTHENTIK_POSTGRES_PASSWORD=${GN}${AUTHENTIK_POSTGRES_PASSWORD}${CL}"
    echo -e "AUTHENTIK_HOST=${GN}${AUTHENTIK_HOST_VALUE}${CL}"
    echo -e "AUTHENTIK_HOST_BROWSER=${GN}${AUTHENTIK_HOST_BROWSER_VALUE}${CL}"
    echo -e "AUTHENTIK_BOOTSTRAP_EMAIL=${GN}${AUTHENTIK_BOOTSTRAP_EMAIL_VALUE}${CL}"
    echo -e "AUTHENTIK_BOOTSTRAP_PASSWORD=${GN}${AUTHENTIK_BOOTSTRAP_PASSWORD}${CL}"
    echo -e "AUTHENTIK_BOOTSTRAP_TOKEN=${GN}${AUTHENTIK_BOOTSTRAP_TOKEN}${CL}"
    echo -e "${YW}Reminder: AUTHENTIK_BOOTSTRAP_TOKEN is not an Authentik API token.${CL}"
    echo -e "POSTIZ_POSTGRES_PASSWORD=${GN}${POSTIZ_POSTGRES_PASSWORD}${CL}"
    echo -e "POSTIZ_JWT_SECRET=${GN}${POSTIZ_JWT_SECRET}${CL}"
    echo -e "TEMPORAL_POSTGRES_PASSWORD=${GN}${TEMPORAL_POSTGRES_PASSWORD}${CL}"
    echo ""

    echo -e "${BL}HTPASSWD:${CL}"

    if [ "$HTPASSWD_MODE" == "generated" ]; then
        echo -e "HTPASSWD_HASHED_LINE=${GN}${HTPASSWD_LINE_VALUE}${CL}"
        echo -e "${YW}Plain htpasswd password was not displayed or logged.${CL}"
    elif [ "$HTPASSWD_MODE" == "provided" ]; then
        echo -e "${GN}Provided htpasswd entry saved to:${CL} ${DOCKER_SECRETS_DIR}/htpasswd"
        echo -e "${YW}Provided htpasswd hash is intentionally not displayed or logged.${CL}"
    elif root_file_not_empty "${DOCKER_SECRETS_DIR}/htpasswd"; then
        echo -e "${GN}Existing htpasswd file preserved at:${CL} ${DOCKER_SECRETS_DIR}/htpasswd"
        echo -e "${YW}Existing htpasswd content is intentionally not displayed.${CL}"
    else
        echo -e "${YW}htpasswd file created empty:${CL} ${DOCKER_SECRETS_DIR}/htpasswd"
        echo -e "${YW}This is fine when Authentik/Authelia/SSO is used instead of Traefik basic-auth.${CL}"
    fi

    echo ""
    echo -e "${YW}Sensitive final output above was intentionally not written to ${LOG_FILE}.${CL}"

    wait_then_clear_secret_display

    enable_logging
}

# --- 57. CLEAN FINAL SUMMARY ---
# Prints non-sensitive final summary after secrets have been cleared from the terminal.
function show_clean_final_summary() {
    section_flash_success "     ━━━━━━━━━━━━━━━━━    FINISHED    ━━━━━━━━━━━━━━━━━"

    detail_line "DOCKER DIR" "$DOCKER_DIR"
    detail_line ".ENV FILE" "${DOCKER_DIR}/.env"
    detail_line "SECRETS DIR" "$DOCKER_SECRETS_DIR"
    detail_line "POSTGRES INIT" "${DOCKER_DIR}/appdata/postgres/init/01-create-app-databases.sh"
    detail_line "TRAEFIK STATIC CONFIG" "$TRAEFIK_STATIC_CONFIG_FILE"
    detail_line "TRAEFIK DYNAMIC CONFIG" "$TRAEFIK_DYNAMIC_CONFIG_FILE"
    detail_line "TRAEFIK ACME STORAGE" "${TRAEFIK_ACME_DIR}/acme.json"
    detail_line "TRAEFIK DASHBOARD HOST" "$TRAEFIK_DASHBOARD_HOST"
    detail_line "CLOUDFLARE TOKEN FILE" "$CF_API_TOKEN_FILE"
    detail_line "HTPASSWD FILE" "${DOCKER_SECRETS_DIR}/htpasswd"
    detail_line "DOMAIN" "$DOMAIN_VALUE"
    detail_line "DOCKER USER" "$DOCKER_USER"
    detail_line "PUID / PGID" "${PUID_VALUE}:${PGID_VALUE}"
    detail_line "EXISTING SETUP" "$EXISTING_SETUP"
    detail_line "SECRETS REGENERATED" "$REGENERATE_SECRETS"
    detail_line "SECRET SCREEN CLEARED" "$SECRET_SCREEN_CLEARED"
    detail_line "VERIFY LOG" "$VERIFY_LOG"
    echo ""
    echo -e "${YW}Sensitive values were displayed once, not logged, then terminal output was cleared where supported.${CL}"
    echo ""
    echo -e "${BL}NEXT STEP:${CL}"
    echo -e "${YW}Run Script 6.5 to deploy selected stacks hands-free from GitHub into admin-UI-compatible stack folders.${CL}"
    echo ""
}

# =========================================================
#  MAIN ORCHESTRATION
# =========================================================

# --- 58. MAIN FUNCTION ---
# Runs full setup in validation -> input -> file creation -> verify -> one-time secret display order.
function main() {
    init_script

    check_previous_marker
    start_confirmation
    check_docker_readiness
    collect_user_and_path_inputs
    detect_existing_setup
    collect_domain_cloudflare_inputs
    collect_traefik_inputs
    collect_htpasswd_inputs
    collect_admin_ui_selection
    collect_authentik_bootstrap_inputs

    create_docker_directories
    generate_or_reuse_secrets
    create_postgres_init_script
    create_traefik_config_files
    write_secret_files
    write_env_file
    apply_permissions

    show_secrets_once_without_logging

    write_completion_marker
    create_verification_report
    show_clean_final_summary

    exit 0
}

main "$@"