#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit nullglob

# =========================================================
#  Docker Stack Deploy + Verify
# =========================================================
# Deploys Crea stacks hands-free from GitHub into admin-UI-compatible stack folders.
# Scripts deploy first; Dockge/Dockhand/Portainer/Komodo manage afterwards.

YW="$(printf '\033[33m')"; BL="$(printf '\033[36m')"; RD="$(printf '\033[01;31m')"; GN="$(printf '\033[1;92m')"; CL="$(printf '\033[m')"; CLF="$(printf '\033[5m')"; BFR="\\r\\033[K"
HOLD="-"; CM="${GN}✓${CL}"; WARN="${YW}!${CL}"; CROSS="${RD}✗${CL}"; BORDER="${BL}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${CL}"
T=15
LOG_FILE="/var/log/docker-stack-deploy-verify.log"; RUNTIME_LOG_FILE=""; VERIFY_LOG="/var/log/docker-stack-deploy-verify-report.log"; COMPLETED_MARKER="/root/.docker-stack-deploy-verify-completed"
DEFAULT_DOCKER_USER="${SUDO_USER:-orik}"; DOCKER_USER="${DOCKER_USER:-$DEFAULT_DOCKER_USER}"; DOCKER_DIR="${DOCKER_DIR:-/home/${DOCKER_USER}/docker}"; COMPOSE_DIR="${COMPOSE_DIR:-${DOCKER_DIR}/compose}"; ENV_FILE="${ENV_FILE:-${DOCKER_DIR}/.env}"
GITHUB_RAW_BASE="${GITHUB_RAW_BASE:-https://raw.githubusercontent.com/Orik999/mySetup/main/docker}"
GITHUB_API_TREE_URL="${GITHUB_API_TREE_URL:-https://api.github.com/repos/Orik999/mySetup/git/trees/main?recursive=1}"
SUDO_CMD=""; DOCKER_NEEDS_SUDO="no"; DOMAIN=""; ADMIN_UI="dockge"; ADMIN_UI_DISPLAY_NAME="Dockge"; ADMIN_UI_PROJECT="dockge"; ADMIN_UI_SERVICE="dockge"; ADMIN_UI_BOOTSTRAP_PORT="5001"; ADMIN_UI_INTERNAL_PORT="5001"; ADMIN_UI_BOOTSTRAP_SCHEME="http"
SELECT_CF_DDNS="n"; SELECT_CF_COMPANION="y"; SELECT_VSCODE="n"; SELECT_FILEBROWSER="n"; SELECT_EXTRA_STACKS="n"
DEPLOYED_STACKS=(); TEMP_FILES=(); EXTRA_STACK_PATHS=(); EXTRA_STACK_NAMES=()

declare -A STACK_FILE STACK_FOLDER STACK_PROJECT STACK_SERVICE STACK_REQUIRED STACK_OPTIONAL STACK_DESC STACK_BOOTSTRAP_FILE
STACK_FILE[socket-proxy]="00-socket-proxy-compose.yml"; STACK_FOLDER[socket-proxy]="socket-proxy"; STACK_PROJECT[socket-proxy]="socket-proxy"; STACK_SERVICE[socket-proxy]="socket-proxy"; STACK_DESC[socket-proxy]="Docker socket proxy"
STACK_FILE[postgres]="02-postgres-compose.yml"; STACK_FOLDER[postgres]="postgres"; STACK_PROJECT[postgres]="postgres"; STACK_SERVICE[postgres]="postgres"; STACK_DESC[postgres]="Shared PostgreSQL"
STACK_FILE[redis]="03-redis-compose.yml"; STACK_FOLDER[redis]="redis"; STACK_PROJECT[redis]="redis"; STACK_SERVICE[redis]="redis"; STACK_DESC[redis]="Shared Redis"
STACK_FILE[traefik]="04-traefik-compose.yml"; STACK_FOLDER[traefik]="traefik"; STACK_PROJECT[traefik]="traefik"; STACK_SERVICE[traefik]="traefik"; STACK_DESC[traefik]="Traefik reverse proxy"
STACK_FILE[authentik]="05-authentik-compose.yml"; STACK_FOLDER[authentik]="authentik"; STACK_PROJECT[authentik]="authentik"; STACK_SERVICE[authentik]="authentik-server"; STACK_DESC[authentik]="Authentik SSO"
STACK_FILE[temporal]="06-temporal-compose.yml"; STACK_FOLDER[temporal]="temporal"; STACK_PROJECT[temporal]="temporal"; STACK_SERVICE[temporal]="temporal"; STACK_DESC[temporal]="Temporal workflow engine"
STACK_FILE[postiz-temporal-guard]="07-postiz-temporal-guard-compose.yml"; STACK_FOLDER[postiz-temporal-guard]="postiz-temporal-guard"; STACK_PROJECT[postiz-temporal-guard]="postiz-temporal-guard"; STACK_SERVICE[postiz-temporal-guard]="postiz-temporal-guard"; STACK_DESC[postiz-temporal-guard]="One-shot Temporal cleanup helper"
STACK_FILE[postiz]="08-postiz-compose.yml"; STACK_FOLDER[postiz]="postiz"; STACK_PROJECT[postiz]="postiz"; STACK_SERVICE[postiz]="postiz"; STACK_DESC[postiz]="Postiz application"
STACK_FILE[cf-ddns]="09-cf-ddns-compose.yml"; STACK_FOLDER[cf-ddns]="cf-ddns"; STACK_PROJECT[cf-ddns]="cf-ddns"; STACK_SERVICE[cf-ddns]="cf-ddns"; STACK_DESC[cf-ddns]="Cloudflare DDNS optional"
STACK_FILE[cf-companion]="10-cf-companion-compose.yml"; STACK_FOLDER[cf-companion]="cf-companion"; STACK_PROJECT[cf-companion]="cf-companion"; STACK_SERVICE[cf-companion]="cf-companion"; STACK_DESC[cf-companion]="Cloudflare DNS companion"
STACK_FILE[vscode]="11-vscode-compose.yml"; STACK_FOLDER[vscode]="vscode"; STACK_PROJECT[vscode]="vscode"; STACK_SERVICE[vscode]="vscode"; STACK_DESC[vscode]="VS Code Server optional"
STACK_FILE[filebrowser]="12-filebrowser-compose.yml"; STACK_FOLDER[filebrowser]="filebrowser"; STACK_PROJECT[filebrowser]="filebrowser"; STACK_SERVICE[filebrowser]="filebrowser"; STACK_DESC[filebrowser]="Filebrowser optional"
STACK_FILE[dockge]="01-[1]-dockge-compose.yml"; STACK_FOLDER[dockge]="dockge"; STACK_PROJECT[dockge]="dockge"; STACK_SERVICE[dockge]="dockge"; STACK_BOOTSTRAP_FILE[dockge]="01-[1]-dockge-bootstrap-override.yml"
STACK_FILE[dockhand]="01-[2]-dockhand-compose.yml"; STACK_FOLDER[dockhand]="dockhand"; STACK_PROJECT[dockhand]="dockhand"; STACK_SERVICE[dockhand]="dockhand"; STACK_BOOTSTRAP_FILE[dockhand]="01-[2]-dockhand-bootstrap-override.yml"
STACK_FILE[komodo]="01-[3]-komodo-compose.yml"; STACK_FOLDER[komodo]="komodo"; STACK_PROJECT[komodo]="komodo"; STACK_SERVICE[komodo]="komodo-core"; STACK_BOOTSTRAP_FILE[komodo]="01-[3]-komodo-bootstrap-override.yml"
STACK_FILE[portainer]="01-[4]-portainer-compose.yml"; STACK_FOLDER[portainer]="portainer"; STACK_PROJECT[portainer]="portainer"; STACK_SERVICE[portainer]="portainer"; STACK_BOOTSTRAP_FILE[portainer]="01-[4]-portainer-bootstrap-override.yml"

header_info(){ echo -e "${BL}DOCKER STACK DEPLOY + VERIFY${CL}"; }
msg_info(){ echo -ne " ${HOLD} ${YW}${1:-}...${CL}"; }; msg_ok(){ echo -e "${BFR} ${CM} ${GN}${1:-}${CL}"; }; msg_warn(){ echo -e "${BFR} ${WARN} ${YW}${1:-}${CL}"; }; msg_skip(){ echo -e "${BFR} ${WARN} ${YW}${1:-}${CL}"; }; msg_error(){ echo -e "${BFR} ${CROSS} ${RD}${1:-Unknown error}${CL}"; exit 1; }
section(){ echo ""; echo -e "$BORDER"; echo -e "${BL}$1${CL}"; echo -e "$BORDER"; }
detail_line(){ echo -e " ${BL}━━━━━▶${CL} ${1:-}: ${GN}${2:-}${CL}"; }
tty_print(){ if [ -w /dev/tty ]; then echo -ne "$*" >/dev/tty; else echo -ne "$*" >&2; fi; }
tty_println(){ if [ -w /dev/tty ]; then echo -e "$*" >/dev/tty; else echo -e "$*" >&2; fi; }
flush_input_buffer(){ local junk="" i=""; [ -r /dev/tty ] || return 0; for i in {1..20}; do IFS= read -rsn1 -t 0.02 junk </dev/tty 2>/dev/null || break; done; }
yes_no_label(){ [[ "$1" =~ ^[Yy]$ ]] && echo yes || echo no; }
tty_read_yes_no_blocking(){ local prompt="$1" default="$2" key="" label="Y/n"; [[ "$default" =~ ^[Nn]$ ]] && label="y/N"; flush_input_buffer; while true; do tty_print "${BFR}${YW}${prompt} (${label}): ${CL}"; IFS= read -rsn1 key </dev/tty || true; if [[ -z "$key" ]]; then tty_print "$BFR"; echo "$default"; return; elif [[ "$key" =~ ^[YyNn]$ ]]; then tty_print "$BFR"; echo "$key"; return; fi; done; }
timed_yes_no(){ local prompt="$1" default="$2" answer="" key="" label="Y/n" deadline now remaining; [[ "$default" =~ ^[Nn]$ ]] && label="y/N"; flush_input_buffer; deadline=$(( $(date +%s)+T )); while true; do now=$(date +%s); remaining=$((deadline-now)); [ "$remaining" -le 0 ] && { answer="$default"; break; }; tty_print "${BFR}${YW}${prompt} (${label}) [${remaining}s]${CL} "; if IFS= read -rsn1 -t 1 key </dev/tty; then if [[ "$key" == " " ]]; then answer="$(tty_read_yes_no_blocking "$prompt" "$default")"; break; elif [[ "$key" =~ ^[YyNn]$ ]]; then answer="$key"; break; elif [[ -z "$key" ]]; then answer="$default"; break; fi; fi; done; tty_print "$BFR"; tty_println "${CM} ${GN}${prompt} $(yes_no_label "$answer")${CL}"; echo "$answer"; }
editable_input_loop(){ local prompt="$1" default="$2" answer="${3:-}" key=""; flush_input_buffer; while true; do tty_print "${BFR}${YW}${prompt} [default: ${default}]: ${CL}${answer}"; IFS= read -rsn1 key </dev/tty || true; case "$key" in "") [ -z "$answer" ] && answer="$default"; tty_print "$BFR"; echo "$answer"; return;; $'\177'|$'\b') answer="${answer%?}";; *) answer+="$key";; esac; done; }
timed_text_input(){ local prompt="$1" default="$2" answer="" key="" deadline now remaining; flush_input_buffer; deadline=$(( $(date +%s)+T )); while true; do now=$(date +%s); remaining=$((deadline-now)); [ "$remaining" -le 0 ] && { answer="$default"; break; }; tty_print "${BFR}${YW}${prompt} [default: ${default}] [${remaining}s]: ${CL}"; if IFS= read -rsn1 -t 1 key </dev/tty; then if [[ "$key" == " " ]]; then answer="$(editable_input_loop "$prompt" "$default" "")"; break; elif [[ -z "$key" ]]; then answer="$default"; break; else answer="$(editable_input_loop "$prompt" "$default" "$key")"; break; fi; fi; done; [ -z "$answer" ] && answer="$default"; tty_print "$BFR"; tty_println "${CM} ${GN}${prompt} ${answer}${CL}"; echo "$answer"; }
cleanup(){ local ec="$?" f=""; if [ -n "${SUDO_CMD:-}" ] && [ -n "${RUNTIME_LOG_FILE:-}" ] && [ -s "$RUNTIME_LOG_FILE" ]; then "$SUDO_CMD" cp "$RUNTIME_LOG_FILE" "$LOG_FILE" 2>/dev/null || true; "$SUDO_CMD" chmod 0644 "$LOG_FILE" 2>/dev/null || true; fi; for f in "${TEMP_FILES[@]:-}"; do [ -f "$f" ] && rm -f "$f"; done; exit "$ec"; }
on_error(){ echo -e "${RD}ERROR:${CL} Script failed at line $1. Check ${LOG_FILE}"; }
detect_root_or_sudo(){ [ "$EUID" -eq 0 ] && SUDO_CMD="" || SUDO_CMD="sudo"; }
validate_sudo_access(){ if [ -n "$SUDO_CMD" ]; then msg_info "Validating sudo access"; "$SUDO_CMD" -n true >/dev/null 2>&1 || "$SUDO_CMD" -v || msg_error "Sudo authentication failed"; msg_ok "SUDO ACCESS CONFIRMED"; fi; }
init_logging(){ if [ -n "$SUDO_CMD" ]; then RUNTIME_LOG_FILE="$(mktemp /tmp/docker-stack-deploy-log.XXXXXX)"; TEMP_FILES+=("$RUNTIME_LOG_FILE"); exec > >(tee -a "$RUNTIME_LOG_FILE") 2>&1; else RUNTIME_LOG_FILE="$LOG_FILE"; exec > >(tee -a "$LOG_FILE") 2>&1; fi; }
validate_dependencies(){ for c in awk cat chmod curl date docker grep head id mkdir mktemp python3 rm sed tee timeout; do command -v "$c" >/dev/null 2>&1 || msg_error "Required command not found: $c"; done; }
init_script(){ detect_root_or_sudo; validate_sudo_access; init_logging; trap 'on_error "$LINENO"' ERR; trap cleanup EXIT; clear; header_info; validate_dependencies; }
docker_cmd(){ if [ "$DOCKER_NEEDS_SUDO" = "yes" ]; then "$SUDO_CMD" docker "$@"; else docker "$@"; fi; }
run_cmd(){ local desc="$1"; shift; local err; err="$(mktemp)"; TEMP_FILES+=("$err"); if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" "$@" >/dev/null 2>"$err" || { echo; echo -e "${RD}Command failed:${CL} $desc"; cat "$err"; exit 1; }; else "$@" >/dev/null 2>"$err" || { echo; echo -e "${RD}Command failed:${CL} $desc"; cat "$err"; exit 1; }; fi; rm -f "$err"; }
run_docker(){ local desc="$1"; shift; local err; err="$(mktemp)"; TEMP_FILES+=("$err"); docker_cmd "$@" >/dev/null 2>"$err" || { echo; echo -e "${RD}Docker command failed:${CL} $desc"; cat "$err"; exit 1; }; rm -f "$err"; }
env_value(){ awk -F= -v k="$1" '$1==k {v=$0; sub("^[^=]*=","",v); gsub(/^"|"$/,"",v); print v; exit}' "$ENV_FILE" 2>/dev/null || true; }

detect_docker_access(){ section "DOCKER ACCESS"; if docker ps >/dev/null 2>&1; then DOCKER_NEEDS_SUDO="no"; msg_ok "DOCKER ACCESS CONFIRMED"; elif [ -n "$SUDO_CMD" ] && "$SUDO_CMD" docker ps >/dev/null 2>&1; then DOCKER_NEEDS_SUDO="yes"; msg_ok "DOCKER ACCESS CONFIRMED WITH SUDO"; else msg_error "Docker daemon not reachable. Run Script 5 first."; fi; }
load_project_inputs(){ section "PROJECT SETTINGS"; DOCKER_USER="$(timed_text_input "Enter Docker Linux user" "$DOCKER_USER")"; DOCKER_DIR="$(timed_text_input "Enter Docker directory" "$DOCKER_DIR")"; COMPOSE_DIR="$(timed_text_input "Enter Docker compose directory" "$COMPOSE_DIR")"; ENV_FILE="$(timed_text_input "Enter Docker .env path" "$ENV_FILE")"; GITHUB_RAW_BASE="$(timed_text_input "Enter GitHub raw compose base" "$GITHUB_RAW_BASE")"; [ -f "$ENV_FILE" ] || msg_error ".env missing: $ENV_FILE"; DOMAIN="$(env_value DOMAIN)"; ADMIN_UI="$(env_value ADMIN_UI)"; ADMIN_UI="${ADMIN_UI:-dockge}"; detail_line "Domain" "$DOMAIN"; detail_line "Selected admin UI" "$ADMIN_UI"; }
configure_admin_ui(){ case "$ADMIN_UI" in dockge) ADMIN_UI_DISPLAY_NAME="Dockge"; ADMIN_UI_PROJECT="dockge"; ADMIN_UI_SERVICE="dockge"; ADMIN_UI_BOOTSTRAP_PORT="${DOCKGE_BOOTSTRAP_PORT:-5001}"; ADMIN_UI_INTERNAL_PORT="5001"; ADMIN_UI_BOOTSTRAP_SCHEME="http";; dockhand) ADMIN_UI_DISPLAY_NAME="Dockhand"; ADMIN_UI_PROJECT="dockhand"; ADMIN_UI_SERVICE="dockhand"; ADMIN_UI_BOOTSTRAP_PORT="${DOCKHAND_BOOTSTRAP_PORT:-3000}"; ADMIN_UI_INTERNAL_PORT="3000"; ADMIN_UI_BOOTSTRAP_SCHEME="http";; komodo) ADMIN_UI_DISPLAY_NAME="Komodo"; ADMIN_UI_PROJECT="komodo"; ADMIN_UI_SERVICE="komodo-core"; ADMIN_UI_BOOTSTRAP_PORT="${KOMODO_BOOTSTRAP_PORT:-9120}"; ADMIN_UI_INTERNAL_PORT="9120"; ADMIN_UI_BOOTSTRAP_SCHEME="http";; portainer|portainer-ce) ADMIN_UI="portainer"; ADMIN_UI_DISPLAY_NAME="Portainer"; ADMIN_UI_PROJECT="portainer"; ADMIN_UI_SERVICE="portainer"; ADMIN_UI_BOOTSTRAP_PORT="${PORTAINER_BOOTSTRAP_PORT:-9443}"; ADMIN_UI_INTERNAL_PORT="9443"; ADMIN_UI_BOOTSTRAP_SCHEME="https";; *) msg_error "Unsupported ADMIN_UI in .env: $ADMIN_UI";; esac; detail_line "Admin UI" "$ADMIN_UI_DISPLAY_NAME"; }
preflight_permissions(){ section "PREFLIGHT PERMISSIONS"; [ -d "$DOCKER_DIR" ] || msg_error "Docker dir missing: $DOCKER_DIR"; [ -d "$COMPOSE_DIR" ] || run_cmd "creating compose dir" mkdir -p "$COMPOSE_DIR"; run_cmd "owning compose dir" chown -R "${DOCKER_USER}:${DOCKER_USER}" "$COMPOSE_DIR"; local pdir="${DOCKER_DIR}/appdata/postgres/data" rdir="${DOCKER_DIR}/appdata/redis"; [ -d "$pdir" ] || msg_error "PostgreSQL data dir missing. Run Script 6."; [ -d "$rdir" ] || msg_error "Redis data dir missing. Run Script 6."; local po ro; po="$(stat -c '%u:%g %a' "$pdir" 2>/dev/null || true)"; ro="$(stat -c '%u:%g %a' "$rdir" 2>/dev/null || true)"; detail_line "PostgreSQL data" "$po"; detail_line "Redis data" "$ro"; [[ "$po" == 999:999* ]] || msg_error "PostgreSQL data must be owned 999:999. Re-run fixed Script 6 permissions."; [[ "$ro" == 999:999* ]] || msg_error "Redis data must be owned 999:999. Re-run fixed Script 6 permissions."; msg_ok "PREFLIGHT PERMISSIONS PASSED"; }
collect_stack_choices(){ section "STACK SELECTION"; echo -e "${YW}Core deployment includes socket-proxy, ${ADMIN_UI_DISPLAY_NAME}, PostgreSQL, Redis, Traefik, Authentik, Temporal, Temporal Guard and Postiz.${CL}"; echo -e "${YW}Required dependencies are auto-selected when Postiz is selected.${CL}"; echo ""; local deploy_core; deploy_core="$(timed_yes_no "Deploy core Crea/Postiz stack?" "y")"; [[ "$deploy_core" =~ ^[Yy]$ ]] || msg_error "Core deployment is required for this project flow."; SELECT_CF_COMPANION="$(timed_yes_no "Deploy Cloudflare Companion DNS automation?" "y")"; SELECT_CF_DDNS="$(timed_yes_no "Deploy optional Cloudflare DDNS updater?" "n")"; SELECT_VSCODE="$(timed_yes_no "Deploy optional VS Code Server?" "n")"; SELECT_FILEBROWSER="$(timed_yes_no "Deploy optional Filebrowser?" "n")"; SELECT_EXTRA_STACKS="$(timed_yes_no "Scan GitHub for additional optional stack YMLs?" "n")"; }
stack_dir(){ echo "${COMPOSE_DIR}/${STACK_FOLDER[$1]}"; }
stack_compose(){ echo "$(stack_dir "$1")/compose.yaml"; }
stack_override(){ echo "$(stack_dir "$1")/bootstrap.override.yaml"; }
download_file(){ curl -fsSL "$1" -o "$2"; }
download_stack(){ local s="$1" dir file url; dir="$(stack_dir "$s")"; file="$(stack_compose "$s")"; url="${GITHUB_RAW_BASE}/${STACK_FILE[$s]}"; msg_info "Downloading ${STACK_DESC[$s]:-$s}"; mkdir -p "$dir"; download_file "$url" "$file"; chmod 640 "$file"; chown "${DOCKER_USER}:${DOCKER_USER}" "$file" 2>/dev/null || true; msg_ok "${s} COMPOSE READY"; if [ -n "${STACK_BOOTSTRAP_FILE[$s]:-}" ]; then url="${GITHUB_RAW_BASE}/${STACK_BOOTSTRAP_FILE[$s]}"; download_file "$url" "$(stack_override "$s")"; chmod 640 "$(stack_override "$s")"; chown "${DOCKER_USER}:${DOCKER_USER}" "$(stack_override "$s")" 2>/dev/null || true; msg_ok "${s} BOOTSTRAP OVERRIDE READY"; fi; }
download_selected_stacks(){ section "DOWNLOAD STACKS"; local stacks=(socket-proxy "$ADMIN_UI" postgres redis traefik authentik temporal postiz-temporal-guard postiz); [[ "$SELECT_CF_DDNS" =~ ^[Yy]$ ]] && stacks+=(cf-ddns); [[ "$SELECT_CF_COMPANION" =~ ^[Yy]$ ]] && stacks+=(cf-companion); [[ "$SELECT_VSCODE" =~ ^[Yy]$ ]] && stacks+=(vscode); [[ "$SELECT_FILEBROWSER" =~ ^[Yy]$ ]] && stacks+=(filebrowser); local s; for s in "${stacks[@]}"; do download_stack "$s"; done; }
validate_stack(){ local s="$1"; msg_info "Validating $s"; if [ "$s" = "$ADMIN_UI" ]; then run_docker "validating $s" compose --env-file "$ENV_FILE" -p "${STACK_PROJECT[$s]}" -f "$(stack_compose "$s")" -f "$(stack_override "$s")" config -q; else run_docker "validating $s" compose --env-file "$ENV_FILE" -p "${STACK_PROJECT[$s]}" -f "$(stack_compose "$s")" config -q; fi; msg_ok "$s VALID"; }
validate_selected_stacks(){ section "VALIDATE STACKS"; local stacks=(socket-proxy "$ADMIN_UI" postgres redis traefik authentik temporal postiz-temporal-guard postiz); [[ "$SELECT_CF_DDNS" =~ ^[Yy]$ ]] && stacks+=(cf-ddns); [[ "$SELECT_CF_COMPANION" =~ ^[Yy]$ ]] && stacks+=(cf-companion); [[ "$SELECT_VSCODE" =~ ^[Yy]$ ]] && stacks+=(vscode); [[ "$SELECT_FILEBROWSER" =~ ^[Yy]$ ]] && stacks+=(filebrowser); local s; for s in "${stacks[@]}"; do validate_stack "$s"; done; }
create_networks(){ section "DOCKER NETWORKS"; docker_cmd network create --driver bridge --subnet 192.168.91.0/24 socket_proxy >/dev/null 2>&1 || true; docker_cmd network create --driver bridge --subnet 192.168.90.0/24 t2_proxy >/dev/null 2>&1 || true; docker_cmd network create --driver bridge database >/dev/null 2>&1 || true; msg_ok "DOCKER NETWORKS READY"; }
deploy_stack(){ local s="$1"; section "DEPLOY STACK - ${s^^}"; if [ "$s" = "$ADMIN_UI" ]; then run_docker "deploying $s" compose --env-file "$ENV_FILE" -p "${STACK_PROJECT[$s]}" -f "$(stack_compose "$s")" -f "$(stack_override "$s")" up -d; else run_docker "deploying $s" compose --env-file "$ENV_FILE" -p "${STACK_PROJECT[$s]}" -f "$(stack_compose "$s")" up -d; fi; DEPLOYED_STACKS+=("$s"); msg_ok "${s^^} DEPLOYED"; }
wait_container(){ local name="$1" tries="${2:-60}" i status; msg_info "Waiting for $name"; for i in $(seq 1 "$tries"); do status="$(docker_cmd inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)"; [ "$status" = "running" ] && { msg_ok "$name RUNNING"; return 0; }; sleep 2; done; msg_error "$name did not start"; }
verify_postgres(){ wait_container postgres 45; docker_cmd exec postgres pg_isready -U postgres -d postgres >/dev/null 2>&1 || msg_error "PostgreSQL pg_isready failed"; if docker_cmd logs postgres --tail=60 2>&1 | grep -qi 'permission denied'; then msg_error "PostgreSQL logs contain permission denied"; fi; msg_ok "POSTGRESQL VERIFIED"; }
verify_redis(){ wait_container redis 45; docker_cmd exec redis redis-cli -a "$(env_value REDIS_PASSWORD)" ping 2>/dev/null | grep -q PONG || msg_error "Redis ping failed"; docker_cmd exec redis redis-cli -a "$(env_value REDIS_PASSWORD)" BGSAVE >/dev/null 2>&1 || msg_error "Redis BGSAVE failed"; if docker_cmd logs redis --tail=60 2>&1 | grep -qi 'permission denied\|MISCONF'; then msg_error "Redis logs contain persistence/permission errors"; fi; msg_ok "REDIS VERIFIED"; }
verify_traefik(){ wait_container traefik 45; docker_cmd logs traefik --tail=100 2>&1 | grep -Eiq 'ERR|error|failed|authentik@docker' && msg_error "Traefik logs contain errors" || msg_ok "TRAEFIK VERIFIED"; }
verify_authentik(){ wait_container authentik-server 90; wait_container authentik-worker 90; if docker_cmd logs authentik-server --tail=120 2>&1 | grep -Eiq 'Permission denied|MISCONF|FATAL|Traceback'; then msg_error "Authentik logs contain startup errors"; fi; msg_ok "AUTHENTIK VERIFIED"; }
wait_temporal(){ wait_container temporal 90; local i; msg_info "Waiting for Temporal API"; for i in $(seq 1 90); do if docker_cmd run --rm --network database --entrypoint /bin/sh temporalio/admin-tools:latest -lc 'temporal --address temporal:7233 operator namespace list >/dev/null 2>&1 || temporal --address temporal:7233 operator search-attribute list >/dev/null 2>&1' >/dev/null 2>&1; then msg_ok "TEMPORAL API READY"; return 0; fi; sleep 2; done; msg_error "Temporal API did not become ready"; }
run_postiz_guard(){ section "POSTIZ TEMPORAL GUARD"; run_docker "running Postiz Temporal Guard" compose --env-file "$ENV_FILE" -p postiz-temporal-guard -f "$(stack_compose postiz-temporal-guard)" up --force-recreate --abort-on-container-exit --exit-code-from postiz-temporal-guard; verify_temporal_guard; }
verify_temporal_guard(){ msg_info "Verifying Temporal search attributes"; local out; out="$(docker_cmd run --rm --network database --entrypoint /bin/sh temporalio/admin-tools:latest -lc 'temporal --address temporal:7233 operator search-attribute list' 2>/dev/null || true)"; if printf '%s' "$out" | grep -qE 'Custom(Text|String)Field[[:space:]]+Text'; then echo "$out"; msg_error "Temporal Text attributes still present after guard"; fi; msg_ok "TEMPORAL SEARCH ATTRIBUTES CLEAN"; }
verify_postiz(){ section "POSTIZ VERIFICATION"; wait_container postiz 90; local i ports code; msg_info "Waiting for Postiz backend :3000"; for i in $(seq 1 90); do ports="$(docker_cmd exec postiz sh -c "cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | grep -i ':0BB8' || true" 2>/dev/null || true)"; [ -n "$ports" ] && { msg_ok "POSTIZ BACKEND :3000 LISTENING"; break; }; sleep 2; done; [ -n "${ports:-}" ] || msg_error "Postiz backend :3000 is not listening"; code="$(curl -ksS -o /dev/null -w '%{http_code}' -I "https://postiz.${DOMAIN}/api/user/self" || true)"; [ "$code" = "502" ] && msg_error "Postiz API returned 502"; case "$code" in 200|301|302|307|308|401|403) msg_ok "POSTIZ API RESPONDED HTTP $code";; *) msg_warn "Postiz API returned HTTP ${code:-none}; check manually";; esac; }
scan_github_optional(){
    section "GITHUB OPTIONAL STACK SCAN"
    [[ "$SELECT_EXTRA_STACKS" =~ ^[Yy]$ ]] || { msg_skip "EXTRA GITHUB STACK SCAN SKIPPED"; return 0; }

    local tmp list_file path base stack_name answer
    tmp="$(mktemp)"; list_file="$(mktemp)"; TEMP_FILES+=("$tmp" "$list_file")

    if ! curl -fsSL "$GITHUB_API_TREE_URL" -o "$tmp"; then
        msg_warn "GitHub API scan failed; continuing with known stacks only"
        return 0
    fi

    python3 - "$tmp" > "$list_file" <<'PYSCAN'
import json,sys,os,re
known=set('00-socket-proxy-compose.yml 01-[1]-dockge-compose.yml 01-[1]-dockge-bootstrap-override.yml 01-[2]-dockhand-compose.yml 01-[2]-dockhand-bootstrap-override.yml 01-[3]-komodo-compose.yml 01-[3]-komodo-bootstrap-override.yml 01-[4]-portainer-compose.yml 01-[4]-portainer-bootstrap-override.yml 02-postgres-compose.yml 03-redis-compose.yml 04-traefik-compose.yml 05-authentik-compose.yml 06-temporal-compose.yml 07-postiz-temporal-guard-compose.yml 08-postiz-compose.yml 09-cf-ddns-compose.yml 10-cf-companion-compose.yml 11-vscode-compose.yml 12-filebrowser-compose.yml'.split())
data=json.load(open(sys.argv[1]))
for x in data.get('tree',[]):
    p=x.get('path','')
    b=os.path.basename(p)
    if p.startswith('docker/') and b.endswith(('.yml','.yaml')) and b not in known:
        print(p)
PYSCAN

    if [ ! -s "$list_file" ]; then
        msg_ok "NO ADDITIONAL OPTIONAL STACKS FOUND"
        return 0
    fi

    echo -e "${YW}Additional GitHub stack files found. Only select standalone optional services.${CL}"
    echo -e "${YW}Do not select unknown files that duplicate PostgreSQL, Redis, Traefik, Authentik, Temporal, or Postiz.${CL}"
    echo ""

    while IFS= read -r path; do
        [ -z "$path" ] && continue
        base="${path##*/}"
        answer="$(timed_yes_no "Download/deploy optional stack ${base}?" "n")"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            stack_name="${base%.yml}"; stack_name="${stack_name%.yaml}"; stack_name="$(printf '%s' "$stack_name" | sed -E 's/^[0-9]+-//; s/-compose$//; s/[^A-Za-z0-9_.-]+/-/g')"
            EXTRA_STACK_PATHS+=("${path#docker/}")
            EXTRA_STACK_NAMES+=("$stack_name")
            msg_ok "OPTIONAL STACK SELECTED: $stack_name"
        fi
    done < "$list_file"
}

download_extra_stacks(){
    [ "${#EXTRA_STACK_PATHS[@]}" -gt 0 ] || return 0
    section "DOWNLOAD EXTRA STACKS"
    local idx rel name dir file url
    for idx in "${!EXTRA_STACK_PATHS[@]}"; do
        rel="${EXTRA_STACK_PATHS[$idx]}"; name="${EXTRA_STACK_NAMES[$idx]}"; dir="${COMPOSE_DIR}/${name}"; file="${dir}/compose.yaml"; url="${GITHUB_RAW_BASE}/${rel}"
        msg_info "Downloading optional stack ${name}"
        mkdir -p "$dir"
        download_file "$url" "$file"
        chmod 640 "$file"; chown "${DOCKER_USER}:${DOCKER_USER}" "$file" 2>/dev/null || true
        msg_ok "OPTIONAL STACK READY: ${name}"
    done
}

validate_extra_stacks(){
    [ "${#EXTRA_STACK_PATHS[@]}" -gt 0 ] || return 0
    section "VALIDATE EXTRA STACKS"
    local idx name file
    for idx in "${!EXTRA_STACK_NAMES[@]}"; do
        name="${EXTRA_STACK_NAMES[$idx]}"; file="${COMPOSE_DIR}/${name}/compose.yaml"
        msg_info "Validating optional stack ${name}"
        run_docker "validating optional stack ${name}" compose --env-file "$ENV_FILE" -p "$name" -f "$file" config -q
        msg_ok "OPTIONAL STACK VALID: ${name}"
    done
}

deploy_extra_stacks(){
    [ "${#EXTRA_STACK_PATHS[@]}" -gt 0 ] || return 0
    section "DEPLOY EXTRA STACKS"
    local idx name file
    for idx in "${!EXTRA_STACK_NAMES[@]}"; do
        name="${EXTRA_STACK_NAMES[$idx]}"; file="${COMPOSE_DIR}/${name}/compose.yaml"
        msg_info "Deploying optional stack ${name}"
        run_docker "deploying optional stack ${name}" compose --env-file "$ENV_FILE" -p "$name" -f "$file" up -d
        DEPLOYED_STACKS+=("$name")
        msg_ok "OPTIONAL STACK DEPLOYED: ${name}"
    done
}
open_bootstrap_firewall(){ command -v ufw >/dev/null 2>&1 || return 0; ufw status 2>/dev/null | grep -qi 'Status: active' || { [ -n "$SUDO_CMD" ] && "$SUDO_CMD" ufw status 2>/dev/null | grep -qi 'Status: active'; } || return 0; run_cmd "allowing ${ADMIN_UI_DISPLAY_NAME} bootstrap port" ufw allow "${ADMIN_UI_BOOTSTRAP_PORT}/tcp" comment "temporary ${ADMIN_UI_DISPLAY_NAME} bootstrap" || true; }
detect_bootstrap_url(){ local ip; ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"; echo "${ADMIN_UI_BOOTSTRAP_SCHEME}://${ip:-127.0.0.1}:${ADMIN_UI_BOOTSTRAP_PORT}"; }
write_report(){ section "VERIFICATION REPORT"; { echo "Date: $(date)"; echo "Docker dir: $DOCKER_DIR"; echo "Compose dir: $COMPOSE_DIR"; echo "Admin UI: $ADMIN_UI_DISPLAY_NAME"; echo "Deployed stacks: ${DEPLOYED_STACKS[*]}"; echo "Bootstrap URL: $(detect_bootstrap_url)"; docker_cmd ps --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}' || true; } | { if [ -n "$SUDO_CMD" ]; then "$SUDO_CMD" tee "$VERIFY_LOG" >/dev/null; else tee "$VERIFY_LOG" >/dev/null; fi; }; msg_ok "REPORT WRITTEN"; }
summary(){ section "FINISHED"; detail_line "Admin UI" "$ADMIN_UI_DISPLAY_NAME"; detail_line "Temporary bootstrap URL" "$(detect_bootstrap_url)"; detail_line "Postiz" "backend :3000 verified and API non-502"; detail_line "Verify log" "$VERIFY_LOG"; echo -e "${YW}Next: use admin UI for management, then run Script 7 for SSO/bootstrap hardening after browser verification.${CL}"; }
main(){ init_script; detect_docker_access; load_project_inputs; configure_admin_ui; preflight_permissions; collect_stack_choices; scan_github_optional; create_networks; download_selected_stacks; download_extra_stacks; validate_selected_stacks; validate_extra_stacks; open_bootstrap_firewall; deploy_stack socket-proxy; wait_container socket-proxy 45; deploy_stack "$ADMIN_UI"; wait_container "$ADMIN_UI_SERVICE" 60; deploy_stack postgres; verify_postgres; deploy_stack redis; verify_redis; deploy_stack traefik; verify_traefik; deploy_stack authentik; verify_authentik; deploy_stack temporal; wait_temporal; run_postiz_guard; deploy_stack postiz; verify_postiz; [[ "$SELECT_CF_DDNS" =~ ^[Yy]$ ]] && deploy_stack cf-ddns; [[ "$SELECT_CF_COMPANION" =~ ^[Yy]$ ]] && deploy_stack cf-companion; [[ "$SELECT_VSCODE" =~ ^[Yy]$ ]] && deploy_stack vscode; [[ "$SELECT_FILEBROWSER" =~ ^[Yy]$ ]] && deploy_stack filebrowser; deploy_extra_stacks; write_report; summary; }
main "$@"
