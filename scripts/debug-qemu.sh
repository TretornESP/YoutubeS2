#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build"
OVMF_DIR="$ROOT_DIR/OVMFbin"
IMG="$BUILD_DIR/disk.img"
GDB_SCRIPT="$ROOT_DIR/debug.gdb"
KERNEL_ELF="$BUILD_DIR/kernel.elf"

: "${QEMU:=qemu-system-x86_64}"
: "${GDB_BIN:=gdb}"
: "${RAM:=512}"
: "${SMP:=1}"
: "${MACHINE:=q35}"
: "${ACCEL:=}"
: "${SERIAL:=stdio}"
: "${EXTRA_ARGS:=}"
: "${NO_GDB:=no}"   # If yes, only start QEMU waiting for gdb

usage() {
  cat <<EOF
Usage: $0 [--img path] [--no-gdb]

Starts QEMU with gdb stub (-s -S) and launches gdb preloaded with debug.gdb

Environment overrides:
  QEMU        QEMU system emulator (default qemu-system-x86_64)
  GDB_BIN     GDB executable (default gdb)
  RAM         Memory in MB (default 512)
  SMP         vCPU count (default 1)
  MACHINE     Machine type (default q35)
  ACCEL       kvm|tcg (auto-detect if unset)
  SERIAL      Serial backend (default stdio)
  EXTRA_ARGS  Extra QEMU arguments
  NO_GDB      yes to skip launching gdb automatically

Options:
  --img PATH  Use custom disk image (default build/disk.img)
  --no-gdb    Do not auto launch gdb (wait for manual attach)
  -h --help   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --img) IMG="$2"; shift 2;;
    --no-gdb) NO_GDB=yes; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

CODE_FD="$OVMF_DIR/OVMF_CODE-pure-efi.fd"
VARS_FD="$OVMF_DIR/OVMF_VARS-pure-efi.fd"

for f in "$IMG" "$CODE_FD" "$VARS_FD" "$KERNEL_ELF" "$GDB_SCRIPT"; do
  [[ -f $f ]] || { echo "Required file missing: $f" >&2; exit 1; }
done

ACCEL_ARG=()
if [[ -z "$ACCEL" ]]; then
  if [[ $(uname -s) == Linux && -r /dev/kvm ]]; then
    ACCEL_ARG+=( -accel kvm )
  else
    ACCEL_ARG+=( -accel tcg )
  fi
else
  ACCEL_ARG+=( -accel "$ACCEL" )
fi

# Launch QEMU paused, gdb stub on :1234
"$QEMU" \
  -machine "$MACHINE" \
  "${ACCEL_ARG[@]}" \
  -m "$RAM" \
  -smp "$SMP" \
  -drive if=pflash,format=raw,unit=0,readonly=on,file="$CODE_FD" \
  -drive if=pflash,format=raw,unit=1,file="$VARS_FD" \
  -drive file="$IMG",format=raw,if=virtio \
  -serial "$SERIAL" \
  -s -S \
  $EXTRA_ARGS &
QEMU_PID=$!

echo "QEMU started (pid=$QEMU_PID) with gdb stub on :1234 and is paused waiting for 'continue'"

cleanup() {
  if kill -0 $QEMU_PID 2>/dev/null; then
    echo "Stopping QEMU (pid=$QEMU_PID)" >&2
    kill $QEMU_PID
    wait $QEMU_PID || true
  fi
}
trap cleanup EXIT INT TERM

if [[ "$NO_GDB" == yes ]]; then
  echo "NO_GDB=yes: Not launching gdb. Attach manually with:"
  echo "  $GDB_BIN -ex 'target remote :1234' $KERNEL_ELF"
  wait $QEMU_PID
  exit 0
fi

# Launch gdb
exec "$GDB_BIN" -q -x "$GDB_SCRIPT" "$KERNEL_ELF"