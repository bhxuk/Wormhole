#!/usr/bin/env bash
# Wormhole container entrypoint - created by bhxuk.com
# shellcheck disable=SC2054  # QEMU options use commas inside single arguments
# Boots Windows 11 in QEMU/KVM, serves the desktop in a browser (noVNC on 8006)
# and forwards RDP (3389). Everything persistent lives in /storage.
set -Eeuo pipefail

APP=/opt/wormhole
RUN=/run/wormhole
STORAGE=/storage
DISK="$STORAGE/windows.qcow2"
VARS="$STORAGE/windows.vars"
TPM_DIR="$STORAGE/tpm"
INSTALLED="$STORAGE/wormhole.installed"
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd
VERSION="$(cat "$APP/VERSION" 2>/dev/null || echo dev)"

log() { printf '[wormhole] %s\n' "$*"; }
die() {
  log "ERROR: $*"
  python3 "$APP/helper.py" status error "$*" || true
  sleep 30
  exit 1
}
helper() { python3 "$APP/helper.py" "$@"; }

mkdir -p "$RUN" "$STORAGE"

cat <<EOF

  ##      ##  #######  ########  ##     ## ##     ##  #######  ##       ########
  ##  ##  ## ##     ## ##     ## ###   ### ##     ## ##     ## ##       ##
  ##  ##  ## ##     ## ########  ## ### ## ######### ##     ## ##       ######
  ##  ##  ## ##     ## ##   ##   ##     ## ##     ## ##     ## ##       ##
   ###  ###   #######  ##     ## ##     ## ##     ##  #######  ######## ########

  Windows 11 in Docker  -  v${VERSION}  -  created by bhxuk.com
  https://github.com/bhxuk/Wormhole

EOF

# ---------------------------------------------------------------- settings ---
RAM_SIZE="$(echo "${RAM_SIZE:-8G}" | tr '[:lower:]' '[:upper:]' | sed 's/B$//')"
CPU_CORES="${CPU_CORES:-4}"
DISK_SIZE="$(echo "${DISK_SIZE:-64G}" | tr '[:lower:]' '[:upper:]' | sed 's/B$//')"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-110}"
[[ "$CPU_CORES" =~ ^[0-9]+$ ]] || die "CPU_CORES must be a number (got '$CPU_CORES')"
[[ "$RAM_SIZE" =~ ^[0-9]+[MG]$ ]] || die "RAM_SIZE must look like 8G or 8192M (got '$RAM_SIZE')"
[[ "$DISK_SIZE" =~ ^[0-9]+[GT]$ ]] || die "DISK_SIZE must look like 64G or 1T (got '$DISK_SIZE')"

# --------------------------------------------------------------------- KVM ---
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  ACCEL=(-machine q35,accel=kvm -cpu "host,kvm=on,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time,hv_vpindex,hv_synic,hv_stimer,hv_reset,hv_runtime,hv_frequencies")
elif [ "${KVM:-Y}" = "N" ]; then
  log "WARNING: KVM disabled - Windows will be extremely slow."
  ACCEL=(-machine q35,accel=tcg -cpu max)
else
  die "/dev/kvm is not available. Enable virtualization (VT-x/AMD-V) in the BIOS or use a server that supports nested virtualization, and pass --device /dev/kvm."
fi

# -------------------------------------------------------------------- disk ---
if [ ! -f "$DISK" ]; then
  log "Creating a ${DISK_SIZE} virtual disk at $DISK (grows as needed)..."
  qemu-img create -q -f qcow2 "$DISK" "$DISK_SIZE"
else
  want=$(numfmt --from=iec "$DISK_SIZE")
  have=$(qemu-img info --output=json "$DISK" | python3 -c 'import json,sys;print(json.load(sys.stdin)["virtual-size"])')
  if [ "$want" -gt "$have" ]; then
    log "Growing virtual disk to ${DISK_SIZE} (extend the C: partition in Windows Disk Management)."
    qemu-img resize -q "$DISK" "$DISK_SIZE"
  fi
  log "Using existing Windows disk - nothing will be reset."
fi
[ -f "$VARS" ] || cp "$OVMF_VARS" "$VARS"

# ---------------------------------------------------------- install media ---
MEDIA=()
if [ ! -f "$INSTALLED" ]; then
  ISO="${BOOT_ISO:-}"
  if [ -z "$ISO" ]; then
    ISO=$(find /iso "$STORAGE" -maxdepth 2 -type f -iname '*windows11*.iso' 2>/dev/null | sort | head -n1 || true)
  fi
  if [ -z "$ISO" ]; then
    ISO=$(find /iso -maxdepth 2 -type f -iname '*.iso' 2>/dev/null | sort | head -n1 || true)
  fi
  [ -n "$ISO" ] && [ -f "$ISO" ] || die "No Windows 11 ISO found. Mount a folder containing it at /iso (download: https://www.microsoft.com/en-gb/software-download/windows11)."
  log "Installing from ISO: $ISO"

  helper unattend "$APP/autounattend.xml" "$RUN/unattend/autounattend.xml"
  genisoimage -quiet -J -r -V WORMHOLE -o "$RUN/unattend.iso" "$RUN/unattend"

  MEDIA=(
    -drive "file=$ISO,if=none,id=cd0,media=cdrom,readonly=on"
    -device ide-cd,drive=cd0,bus=ahci.1,bootindex=2
    -drive "file=$RUN/unattend.iso,if=none,id=cd1,media=cdrom,readonly=on"
    -device ide-cd,drive=cd1,bus=ahci.2
  )
  helper status installing "Windows is installing..."
else
  log "Windows already installed on $(cat "$INSTALLED") - booting from disk."
  helper status starting "Windows is starting up..."
fi

# --------------------------------------------------------------------- TPM ---
TPM=()
mkdir -p "$TPM_DIR"
if swtpm socket --tpm2 --tpmstate "dir=$TPM_DIR" --ctrl "type=unixio,path=$RUN/swtpm.sock" \
     --daemon --log "file=$RUN/swtpm.log" 2>/dev/null; then
  for _ in $(seq 1 20); do [ -S "$RUN/swtpm.sock" ] && break; sleep 0.1; done
  TPM=(-chardev "socket,id=chrtpm,path=$RUN/swtpm.sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0)
else
  log "WARNING: software TPM failed to start - continuing without TPM."
fi

# -------------------------------------------------------------------- QEMU ---
ARGS=(
  -name "${COMPUTER_NAME:-WORMHOLE},process=wormhole"
  "${ACCEL[@]}"
  -smp "$CPU_CORES"
  -m "$RAM_SIZE"
  -rtc base=localtime
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
  -drive "if=pflash,format=raw,file=$VARS"
  -device ahci,id=ahci
  -drive "file=$DISK,if=none,id=disk0,format=qcow2,cache=writeback,discard=unmap,detect-zeroes=unmap"
  -device ide-hd,drive=disk0,bus=ahci.0,bootindex=1,rotation_rate=1
  "${MEDIA[@]}"
  "${TPM[@]}"
  -netdev "user,id=net0,hostname=${COMPUTER_NAME:-WORMHOLE},hostfwd=tcp::3389-:3389,hostfwd=udp::3389-:3389"
  -device e1000e,netdev=net0,romfile=
  -device qemu-xhci,id=xhci
  -device usb-tablet,bus=xhci.0
  -device VGA,vgamem_mb=64
  -vnc 127.0.0.1:0
  -monitor "unix:$RUN/monitor.sock,server,nowait"
  -serial none
)
# shellcheck disable=SC2206
[ -n "${EXTRA_ARGS:-}" ] && ARGS+=(${EXTRA_ARGS})

log "Starting Windows: ${CPU_CORES} cores, ${RAM_SIZE} RAM, ${DISK_SIZE} disk"
qemu-system-x86_64 "${ARGS[@]}" &
QEMU_PID=$!

shutdown() {
  trap - TERM INT
  log "Stop requested - asking Windows to shut down cleanly (up to ${SHUTDOWN_TIMEOUT}s)..."
  helper status stopping "Windows is shutting down..." || true
  helper monitor system_powerdown >/dev/null 2>&1 || true
  for _ in $(seq 1 "$SHUTDOWN_TIMEOUT"); do
    kill -0 "$QEMU_PID" 2>/dev/null || { log "Windows shut down cleanly."; exit 0; }
    sleep 1
  done
  log "Windows did not shut down in time - powering off."
  helper monitor quit >/dev/null 2>&1 || kill "$QEMU_PID" 2>/dev/null || true
  wait "$QEMU_PID" 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

# Web viewer (noVNC) on port 8006
websockify --web "$APP/web" 8006 127.0.0.1:5900 >"$RUN/websockify.log" 2>&1 &
helper status-loop &

# The Windows ISO asks "Press any key to boot from CD" - press it for us while
# the disk is still empty. Once installed, the disk boots first and the ISO is
# no longer attached at all.
if [ ! -f "$INSTALLED" ]; then
  (
    sleep 2
    for _ in $(seq 1 20); do helper monitor "sendkey ret" >/dev/null 2>&1 || true; sleep 1; done
  ) &
fi

log "Web viewer : http://<server-ip>:<web-port>  (container port 8006)"
log "RDP        : <server-ip>:<rdp-port>        (container port 3389)"

set +e
wait "$QEMU_PID"
status=$?
log "Windows powered off (exit $status)."
exit 0
