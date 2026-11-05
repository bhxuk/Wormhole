#!/usr/bin/env bash
# =============================================================================
#  Wormhole installer - Windows 11 in Docker, with RDP and browser access
#  Created by bhxuk.com  -  https://github.com/bhxuk/Wormhole
#
#  curl -fsSL https://raw.githubusercontent.com/bhxuk/Wormhole/main/install.sh | sudo bash
#
#  Options:  -y / --yes   accept every default (needs an ISO the script can find)
# =============================================================================
set -Eeuo pipefail

REPO="bhxuk/Wormhole"
RAW="https://raw.githubusercontent.com/${REPO}/main"
IMAGE="${WORMHOLE_IMAGE:-ghcr.io/bhxuk/wormhole:latest}"
ISO_URL="https://www.microsoft.com/en-gb/software-download/windows11"
CONF=/etc/wormhole.conf
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  esac
done

# ------------------------------------------------------------------- output ---
if [ -t 1 ]; then
  B=$'\e[1m'; D=$'\e[2m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'
else
  B=""; D=""; R=""; G=""; Y=""; C=""; N=""
fi
say()   { printf '%s\n' "$*"; }
info()  { printf '%s>%s %s\n' "$C" "$N" "$*"; }
ok()    { printf '%s✔%s %s\n' "$G" "$N" "$*"; }
warn()  { printf '%s!%s %s\n' "$Y" "$N" "$*"; }
fail()  { printf '%s✖ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
step()  { printf '\n%s%s[%s/9] %s%s\n' "$B" "$C" "$1" "$2" "$N"; }

# Read answers from the terminal even when the script is piped into bash.
TTY=/dev/tty
if ! { [ -r "$TTY" ] && : <"$TTY"; } 2>/dev/null; then
  TTY=""
  [ "$ASSUME_YES" = 1 ] || fail "No terminal available for questions. Re-run with --yes to accept the defaults."
fi

# ask VAR "Question" "default"
ask() {
  local __var=$1 __q=$2 __def=${3:-} __ans=""
  if [ "$ASSUME_YES" = 1 ]; then
    __ans=$__def
  else
    printf '  %s%s%s' "$B" "$__q" "$N"
    [ -n "$__def" ] && printf ' %s[%s]%s' "$D" "$__def" "$N"
    printf ': '
    IFS= read -r __ans <"$TTY" || true
    [ -z "$__ans" ] && __ans=$__def
  fi
  printf -v "$__var" '%s' "$__ans"
}

# ask_secret VAR "Question"
ask_secret() {
  local __var=$1 __q=$2 __ans=""
  if [ "$ASSUME_YES" = 0 ]; then
    printf '  %s%s%s: ' "$B" "$__q" "$N"
    IFS= read -rs __ans <"$TTY" || true
    printf '\n'
  fi
  printf -v "$__var" '%s' "$__ans"
}

# confirm "Question" [Y|N]  -> returns 0 for yes
confirm() {
  local q=$1 def=${2:-Y} ans="" hint="Y/n"
  [ "$def" = "N" ] && hint="y/N"
  if [ "$ASSUME_YES" = 1 ]; then ans=$def; else
    printf '  %s%s%s %s(%s)%s: ' "$B" "$q" "$N" "$D" "$hint" "$N"
    IFS= read -r ans <"$TTY" || true
    [ -z "$ans" ] && ans=$def
  fi
  [[ "$ans" =~ ^[Yy] ]]
}

port_free() {
  local p=$1
  if command -v ss >/dev/null 2>&1; then
    ! ss -Hltun 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]${p}\$"
  elif command -v netstat >/dev/null 2>&1; then
    ! netstat -ltun 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${p}\$"
  else
    ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null
  fi
}

# pick_port VAR "label" "taken-port" candidates...
pick_port() {
  local __var=$1 label=$2 avoid=$3; shift 3
  local free=() p i choice
  for p in "$@"; do
    [ "$p" = "$avoid" ] && continue
    port_free "$p" && free+=("$p")
  done
  [ ${#free[@]} -gt 0 ] || free=(0)
  say "  Free ${label} ports on this server:"
  i=1
  for p in "${free[@]}"; do
    [ "$p" = 0 ] && break
    printf '    %s%d)%s %s\n' "$B" "$i" "$N" "$p"; i=$((i + 1))
  done
  printf '    %s%d)%s custom port\n' "$B" "$i" "$N"
  while true; do
    ask choice "Choose ${label} port" "1"
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
      printf -v "$__var" '%s' "${free[$((choice - 1))]}"; return
    fi
    if [ "$choice" = "$i" ] || [[ "$choice" =~ ^[0-9]{4,5}$ ]]; then
      [ "$choice" = "$i" ] && ask choice "Enter a port number (1024-65535)" ""
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1024 ] && [ "$choice" -le 65535 ] && [ "$choice" != "$avoid" ]; then
        port_free "$choice" || warn "Port $choice looks busy - make sure nothing else uses it."
        printf -v "$__var" '%s' "$choice"; return
      fi
    fi
    warn "Please choose one of the numbers above."
    [ "$ASSUME_YES" = 1 ] && fail "No free ${label} port found."
  done
}

human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "${1}B"; }

banner() {
  cat <<EOF
${C}${B}
   _      __                 __        __
  | | /| / /__  ______ _  __/ /  ___  / /__
  | |/ |/ / _ \\/ __/  ' \\/ _  _ \\/ _ \\/ / -_)
  |__/|__/\\___/_/ /_/_/_/_//_/ \\___/_/\\__/
${N}
  ${B}Windows 11 in Docker${N} - RDP + browser access
  Created by ${B}bhxuk.com${N}  -  https://github.com/${REPO}
EOF
}

# =============================================================================
banner

# ----------------------------------------------------------- 1. preflight ---
step 1 "Checking this server"
[ "$(id -u)" -eq 0 ] || fail "Please run as root (e.g. with sudo)."
[ "$(uname -s)" = "Linux" ] || fail "Wormhole runs on Linux servers."
case "$(uname -m)" in x86_64|amd64) ;; *) fail "Windows 11 x64 needs an x86_64 server (this is $(uname -m))." ;; esac

if [ -e /dev/kvm ]; then
  ok "Hardware virtualisation (KVM) is available"
else
  if grep -Eqw 'vmx|svm' /proc/cpuinfo; then
    warn "CPU supports virtualisation but /dev/kvm is missing - trying to load the kvm module."
    modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || true
  fi
  [ -e /dev/kvm ] || fail "/dev/kvm not found. Enable VT-x/AMD-V in the BIOS, or use a VPS that supports nested virtualisation."
  ok "KVM loaded"
fi

if ! command -v docker >/dev/null 2>&1; then
  warn "Docker is not installed."
  confirm "Install Docker now using the official script from get.docker.com?" Y || fail "Docker is required."
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version >/dev/null 2>&1; then
  warn "Docker Compose plugin is missing - installing it."
  if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq docker-compose-plugin
  elif command -v dnf >/dev/null; then dnf install -y -q docker-compose-plugin
  elif command -v yum >/dev/null; then yum install -y -q docker-compose-plugin
  else fail "Please install the Docker Compose plugin and re-run."; fi
fi
systemctl enable --now docker >/dev/null 2>&1 || true
ok "$(docker --version | cut -d, -f1) with $(docker compose version --short 2>/dev/null | sed 's/^/Compose /')"

CORES=$(nproc)
RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
CPU_MODEL=$(awk -F: '/model name/ {gsub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo)
OS_NAME=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Linux}" || echo Linux)
HOST_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)
[ -n "$HOST_IP" ] || HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
[ -n "$HOST_IP" ] || HOST_IP=127.0.0.1
ALL_IPS=$(hostname -I 2>/dev/null | xargs || echo "$HOST_IP")
ok "$OS_NAME - $CPU_MODEL - ${CORES} cores - ${RAM_GB} GB RAM"
[ "$RAM_GB" -ge 6 ] || warn "Less than 6 GB RAM - Windows 11 will be slow."

# --------------------------------------------------- 2. Windows 11 ISO -------
step 2 "Windows 11 ISO"
say "  Wormhole installs Windows from your own official ISO."
say "  Download it from Microsoft: ${B}${ISO_URL}${N}"
say "  (\"Download Windows 11 Disk Image (ISO) for x64 devices\")"
say ""
info "Looking for files containing 'windows11' / 'win11'..."
mapfile -t FOUND < <(
  for d in "$PWD" "${SUDO_USER:+/home/$SUDO_USER}" /root /home /opt /srv /mnt /media /data /storage /iso /tmp /var/tmp; do
    [ -n "$d" ] && [ -d "$d" ] && find "$d" -maxdepth 4 -type f \( -iname '*windows11*.iso' -o -iname '*win11*.iso' \) 2>/dev/null
  done | awk '!seen[$0]++'
)
ISO=""; pick=""
if [ ${#FOUND[@]} -gt 0 ]; then
  i=1
  for f in "${FOUND[@]}"; do
    printf '    %s%d)%s %s %s(%s)%s\n' "$B" "$i" "$N" "$f" "$D" "$(human "$(stat -c %s "$f")")" "$N"
    i=$((i + 1))
  done
  printf '    %s%d)%s enter a different path\n' "$B" "$i" "$N"
  while [ -z "$ISO" ]; do
    ask pick "Which ISO should be used?" "1"
    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -lt "$i" ]; then ISO=${FOUND[$((pick - 1))]}
    elif [ -f "$pick" ]; then ISO=$pick
    elif [ "$pick" = "$i" ]; then ask ISO "Full path to the Windows 11 ISO" ""
    fi
    [ -n "$ISO" ] && [ ! -f "$ISO" ] && { warn "File not found: $ISO"; ISO=""; }
    [ -z "$ISO" ] && [ "$ASSUME_YES" = 1 ] && fail "No ISO selected."
  done
else
  warn "No Windows 11 ISO found automatically."
  [ "$ASSUME_YES" = 1 ] && fail "Download the ISO from $ISO_URL and re-run."
  while [ -z "$ISO" ]; do
    ask ISO "Full path to the Windows 11 ISO (or 'q' to quit)" ""
    [ "$ISO" = q ] && { say "  Download the ISO from $ISO_URL then run the installer again."; exit 0; }
    [ -f "$ISO" ] || { warn "File not found: $ISO"; ISO=""; }
  done
fi
ISO=$(readlink -f "$ISO")
ISO_NAME=$(basename "$ISO")
ok "Selected: $ISO_NAME ($(human "$(stat -c %s "$ISO")"))"
confirm "Use this ISO?" Y || fail "Cancelled - nothing was changed."
case "$(echo "$ISO_NAME" | tr '[:upper:]' '[:lower:]')" in
  *en-gb*) LANGUAGE=en-GB ;; *de-de*) LANGUAGE=de-DE ;; *fr-fr*) LANGUAGE=fr-FR ;;
  *es-es*) LANGUAGE=es-ES ;; *nl-nl*) LANGUAGE=nl-NL ;; *it-it*) LANGUAGE=it-IT ;;
  *) LANGUAGE=en-US ;;
esac

# ---------------------------------------------------- 3. install location ---
step 3 "Install location"
# shellcheck source=/dev/null
[ -f "$CONF" ] && . "$CONF"
DEFAULT_DIR=${WORMHOLE_DIR:-/opt/wormhole}
say "  Disks on this server:"
df -h -x tmpfs -x devtmpfs -x overlay -x squashfs --output=target,size,avail 2>/dev/null | sed 's/^/    /' | head -n 12
ask DIR "Where should Wormhole (and the Windows disk) live?" "$DEFAULT_DIR"
DIR=$(readlink -m "$DIR")
mkdir -p "$DIR"
AVAIL=$(df -B1 --output=avail "$DIR" | tail -n1 | tr -d ' ')
ok "$DIR ($(human "$AVAIL") free)"
EXISTING=0
if [ -f "$DIR/storage/windows.qcow2" ]; then
  EXISTING=1
  warn "An existing Windows install was found here - it will be kept, not reset."
fi
# shellcheck source=/dev/null
[ -f "$DIR/.env" ] && . "$DIR/.env"

say ""
say "  What should happen to the ISO?"
say "    ${B}1)${N} Copy it into $DIR/iso ${D}(recommended - safe to delete the original later)${N}"
say "    ${B}2)${N} Move it into $DIR/iso"
say "    ${B}3)${N} Leave it where it is ${D}(don't delete it until Windows has installed)${N}"
ask ISO_MODE "Choose" "1"

# ----------------------------------------------------------- 4. resources ---
step 4 "Windows resources"
DEF_CORES=$(( CORES / 2 )); [ "$DEF_CORES" -lt 2 ] && DEF_CORES=2; [ "$DEF_CORES" -gt 8 ] && DEF_CORES=8
DEF_RAM=$(( RAM_GB / 2 )); [ "$DEF_RAM" -lt 4 ] && DEF_RAM=4; [ "$DEF_RAM" -gt 16 ] && DEF_RAM=16
while true; do ask CPU_CORES "CPU cores (server has $CORES)" "${CPU_CORES:-$DEF_CORES}"; [[ "$CPU_CORES" =~ ^[0-9]+$ ]] && [ "$CPU_CORES" -ge 1 ] && [ "$CPU_CORES" -le "$CORES" ] && break; warn "Enter 1-$CORES"; CPU_CORES=""; done
RAM_SIZE=${RAM_SIZE:-${DEF_RAM}G}; DISK_SIZE=${DISK_SIZE:-64G}
while true; do ask RAM "RAM in GB (server has $RAM_GB)" "${RAM_SIZE%G}"; RAM=${RAM%[Gg]}; [[ "$RAM" =~ ^[0-9]+$ ]] && [ "$RAM" -ge 2 ] && break; warn "Enter a number of GB (minimum 2)"; done
while true; do ask DISK "Disk size in GB (only uses space as Windows fills it)" "${DISK_SIZE%G}"; DISK=${DISK%[Gg]}; [[ "$DISK" =~ ^[0-9]+$ ]] && [ "$DISK" -ge 40 ] && break; warn "Enter a number of GB (minimum 40)"; done
[ $(( DISK * 1024 * 1024 * 1024 )) -gt "$AVAIL" ] && warn "The disk is larger than the free space - fine to start, but don't let it fill up."
say "  Windows edition: ${B}1)${N} Pro  ${B}2)${N} Home  ${B}3)${N} Education"
ask ED "Edition" "1"
case "$ED" in 2|[Hh]*) EDITION=Home ;; 3|[Ee]*) EDITION=Education ;; *) EDITION=Pro ;; esac

# -------------------------------------------------------------- 5. ports ----
step 5 "Network ports"
if [ -f "$DIR/.env" ] && [ -n "${WEB_PORT:-}" ] && docker ps -a --format '{{.Names}}' | grep -qx wormhole; then
  info "Keeping existing ports: web ${WEB_PORT}, RDP ${RDP_PORT}"
  confirm "Keep these ports?" Y || { WEB_PORT=""; RDP_PORT=""; }
fi
if [ -z "${WEB_PORT:-}" ]; then
  pick_port WEB_PORT "web viewer" "" 8006 8080 8000 8888 9000 8001 8008 8800
  pick_port RDP_PORT "RDP" "$WEB_PORT" 3389 3390 3399 3333 33389 13389 4489 5000
fi
ok "Web viewer on port $WEB_PORT, RDP on port $RDP_PORT"

# -------------------------------------------------------------- 6. login ----
step 6 "Windows login"
while true; do
  ask COMPUTER_NAME "Computer / RDP name" "${COMPUTER_NAME:-WORMHOLE}"
  COMPUTER_NAME=$(echo "$COMPUTER_NAME" | tr -cd 'A-Za-z0-9-' | tr '[:lower:]' '[:upper:]' | cut -c1-15)
  [ -n "$COMPUTER_NAME" ] && break
done
while true; do
  ask USERNAME "Windows username" "${USERNAME:-wormhole}"
  [[ "$USERNAME" =~ ^[A-Za-z0-9._-]{1,20}$ ]] && [ "${USERNAME,,}" != administrator ] && break
  warn "Use 1-20 letters, numbers, dots, dashes or underscores (not 'Administrator')."
done
if [ "$EXISTING" = 1 ] && [ -n "${PASSWORD:-}" ]; then
  info "Keeping the existing password (change it inside Windows)."
else
  while true; do
    ask_secret PW "Windows password (Enter = generate a strong one)"
    case "$PW" in *\'*|*\"*) warn "Please don't use quote characters in the password." ;; *) break ;; esac
  done
  if [ -z "$PW" ]; then
    PW=$(tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c 14 || true)
    info "Generated a password - it is shown at the end and saved in $DIR/.env"
  fi
  PASSWORD=$PW
fi
say "  Keyboard / region: ${B}1)${N} English (US)  ${B}2)${N} English (UK)  ${B}3)${N} other"
ask KB "Choose" "$([ "$LANGUAGE" = en-GB ] && echo 2 || echo 1)"
case "$KB" in
  2) KEYBOARD=en-GB; REGION=en-GB ;;
  3) ask REGION "Locale code, e.g. de-DE" "$LANGUAGE"; KEYBOARD=$REGION ;;
  *) KEYBOARD=en-US; REGION=en-US ;;
esac
DEF_TZ=UTC
case "$(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value 2>/dev/null || true)" in
  Europe/London) DEF_TZ="GMT Standard Time" ;; Europe/Berlin|Europe/Paris|Europe/Amsterdam|Europe/Madrid|Europe/Rome) DEF_TZ="W. Europe Standard Time" ;;
  America/New_York) DEF_TZ="Eastern Standard Time" ;; America/Chicago) DEF_TZ="Central Standard Time" ;;
  America/Los_Angeles) DEF_TZ="Pacific Standard Time" ;;
esac
ask TIMEZONE "Windows time zone" "${TIMEZONE:-$DEF_TZ}"

# ------------------------------------------------------------ 7. confirm ----
step 7 "Confirm"
cat <<EOF
  ${B}Install on${N}     $(hostname) ($HOST_IP) - $OS_NAME
  ${B}Location${N}       $DIR
  ${B}ISO${N}            $ISO $( case "$ISO_MODE" in 2) echo "(move)";; 3) echo "(leave in place)";; *) echo "(copy)";; esac )
  ${B}Windows${N}        11 $EDITION, $CPU_CORES cores, ${RAM} GB RAM, ${DISK} GB disk
  ${B}Name / user${N}    $COMPUTER_NAME / $USERNAME
  ${B}Web viewer${N}     http://$HOST_IP:$WEB_PORT
  ${B}RDP${N}            $HOST_IP:$RDP_PORT
  ${B}Locale / TZ${N}    $LANGUAGE, keyboard $KEYBOARD, $TIMEZONE
  ${B}Image${N}          $IMAGE
EOF
say ""
confirm "Install Wormhole with these settings?" Y || fail "Cancelled - nothing was installed."

# -------------------------------------------------------------- 8. files ----
step 8 "Preparing files in $DIR"
mkdir -p "$DIR/storage" "$DIR/iso"
case "$ISO_MODE" in
  2) [ "$(dirname "$ISO")" = "$DIR/iso" ] || { mv -f "$ISO" "$DIR/iso/"; ISO="$DIR/iso/$ISO_NAME"; } ;;
  3) ;;
  *) if [ "$ISO" != "$DIR/iso/$ISO_NAME" ]; then
       info "Copying ISO (this can take a minute)..."
       cp -f "$ISO" "$DIR/iso/$ISO_NAME.part" && mv -f "$DIR/iso/$ISO_NAME.part" "$DIR/iso/$ISO_NAME"
       ISO="$DIR/iso/$ISO_NAME"
     fi ;;
esac

if [ "$ISO_MODE" = 3 ]; then ISO_MOUNT="$ISO"; ISO_TARGET="/iso/$ISO_NAME"
else ISO_MOUNT="$DIR/iso"; ISO_TARGET="/iso"; fi
q() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
umask 077
cat >"$DIR/.env" <<EOF
# Wormhole settings - created by bhxuk.com
# Change these and run 'wormhole restart'. Login/region values only apply to a fresh install.
WEB_PORT=$WEB_PORT
RDP_PORT=$RDP_PORT
CPU_CORES=$CPU_CORES
RAM_SIZE=${RAM}G
DISK_SIZE=${DISK}G
EDITION=$EDITION
COMPUTER_NAME=$COMPUTER_NAME
USERNAME=$USERNAME
PASSWORD='$(q "$PASSWORD")'
LANGUAGE=$LANGUAGE
REGION=$REGION
KEYBOARD=$KEYBOARD
TIMEZONE='$(q "$TIMEZONE")'
ISO_PATH='$(q "$ISO_MOUNT")'
EOF
umask 022

cat >"$DIR/docker-compose.yml" <<EOF
# Wormhole - Windows 11 in Docker - created by bhxuk.com
# https://github.com/${REPO}
name: wormhole
services:
  windows:
    image: ${IMAGE}
    container_name: wormhole
    hostname: wormhole
    env_file: .env
    devices:
      - /dev/kvm
    ports:
      - "\${WEB_PORT}:8006"
      - "\${RDP_PORT}:3389/tcp"
      - "\${RDP_PORT}:3389/udp"
    volumes:
      - ./storage:/storage
      - "\${ISO_PATH}:${ISO_TARGET}:ro"
    restart: unless-stopped
    stop_grace_period: 2m
EOF

cat >"$DIR/$COMPUTER_NAME.rdp" <<EOF
full address:s:$HOST_IP:$RDP_PORT
username:s:$COMPUTER_NAME\\$USERNAME
screen mode id:i:2
use multimon:i:0
session bpp:i:32
audiomode:i:0
redirectclipboard:i:1
prompt for credentials:i:1
EOF

# Management command
SCRIPT_DIR=""
if [ -f "${BASH_SOURCE[0]:-}" ]; then SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); fi
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/wormhole" ]; then
  install -m 755 "$SCRIPT_DIR/wormhole" /usr/local/bin/wormhole
else
  curl -fsSL "$RAW/wormhole" -o /usr/local/bin/wormhole && chmod 755 /usr/local/bin/wormhole
fi
echo "WORMHOLE_DIR=$DIR" >"$CONF"

say ""
say "  Files in ${B}$DIR${N}:"
(cd "$DIR" && find . -maxdepth 2 -not -name '.' -printf '    %-40p %10s bytes\n' 2>/dev/null | sed 's#\./##' | sort)
say ""
confirm "These files look right - start Windows now?" Y || { say "  Start later with: ${B}wormhole start${N}"; exit 0; }

# ------------------------------------------------------------- 9. launch ----
step 9 "Starting Wormhole"
cd "$DIR"
if ! docker compose pull -q 2>/dev/null; then
  warn "Could not pull $IMAGE - building it from source instead (one-off, a few minutes)."
  SRC="$DIR/src"; rm -rf "$SRC"; mkdir -p "$SRC"
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/Dockerfile" ]; then cp -r "$SCRIPT_DIR/." "$SRC/"
  else curl -fsSL "https://github.com/${REPO}/archive/refs/heads/main.tar.gz" | tar xz -C "$SRC" --strip-components=1; fi
  docker build --build-arg "VERSION=$(cat "$SRC/VERSION" 2>/dev/null || echo dev)" -t "$IMAGE" "$SRC"
fi
docker compose up -d
info "Waiting for the web viewer..."
for _ in $(seq 1 60); do
  curl -fs -o /dev/null "http://127.0.0.1:$WEB_PORT/" && break
  sleep 2
done

W=62
line() { printf '  %s│%s %-*s %s│%s\n' "$G" "$N" "$W" "$1" "$G" "$N"; }
bar()  { printf '  %s%s%s\n' "$G" "$1$(printf '─%.0s' $(seq 1 $((W + 2))))$2" "$N"; }
say ""
bar "┌" "┐"
line "WORMHOLE - Windows 11 is installing        created by bhxuk.com"
bar "├" "┤"
line "Browser    http://$HOST_IP:$WEB_PORT"
line "RDP        $HOST_IP:$RDP_PORT"
line "RDP name   $COMPUTER_NAME"
line "Username   $USERNAME"
line "Password   $PASSWORD"
line "RDP file   $DIR/$COMPUTER_NAME.rdp"
[ "$ALL_IPS" != "$HOST_IP" ] && line "Other IPs  $ALL_IPS"
bar "├" "┤"
line "Open the browser link to watch setup (10-30 minutes)."
line "RDP works once Windows reaches the desktop."
line "Windows is kept on disk - restarts never reset it."
bar "└" "┘"
say ""
say "  Manage it with: ${B}wormhole status | info | logs | stop | start | restart | update${N}"
say "  Docs & changelog: https://bhxuk.github.io/Wormhole/"
say ""
