# Minimal UEFI Kernel + Limine Setup

This repository contains a very small freestanding x86_64 kernel built as an ELF and booted via a GPT/FAT EFI System Partition using the Limine boot components (`BOOTX64.EFI`). Helper scripts create a disk image, run it under QEMU with OVMF, and provide debugging conveniences.

## 1. Host Requirements

You need a Linux host with the following packages/tools (Debian/Ubuntu names shown):

- Build toolchain: `build-essential` (gcc, ld, make) or equivalent cross compiler
- NASM (for any future assembly files) `nasm`
- QEMU system emulator: `qemu-system-x86` (package name may vary)
- OVMF firmware: `ovmf` (provides `OVMF_CODE*.fd`, `OVMF_VARS*.fd`)
- Disk utilities: `parted`, `losetup`, `util-linux` (losetup/mount), `dosfstools` (mkfs.vfat)
- GDB: `gdb` (for debugging)
- Sudo rights (image creation uses loop devices & formatting)

Example install (Debian/Ubuntu):
```bash
sudo apt update
sudo apt install build-essential nasm qemu-system-x86 ovmf parted dosfstools gdb
```

Fedora/RHEL:
```bash
sudo dnf install @development-tools nasm qemu-system-x86 ovmf parted dosfstools gdb
```

Arch:
```bash
sudo pacman -S base-devel nasm qemu-full ovmf parted dosfstools gdb
```

## 2. Repository Layout

```
GNUmakefile          # Build rules
src/                 # Kernel sources
linker.ld            # Linker script
limine/              # Limine-provided EFI binaries & helpers
startup.nsh          # Optional EFI shell script
limine.conf          # Limine configuration file
scripts/             # Helper scripts
  make-efi-img.sh    # Build GPT/FAT EFI image with kernel + limine
  run-qemu.sh        # Run the built image under QEMU + OVMF
  debug-qemu.sh      # Run QEMU + GDB (gdb stub + auto attach)
  cleanup-loops.sh   # Clean up stale loop devices/mounts
build/               # Output directory (kernel.elf, disk.img, etc.)
```

## 3. Make Targets

| Target  | Description |
|---------|-------------|
| `kernel` | Compiles sources & links `build/kernel.elf`. Implicit prerequisite for others. |
| `image`  | Builds `build/disk.img` (GPT + FAT32 ESP) and populates: `EFI/BOOT/BOOTX64.EFI`, `kernel.elf`, `startup.nsh`, `limine.conf`. |
| `run`    | Builds image (if needed) then launches QEMU using `scripts/run-qemu.sh`. |
| `debug`  | Builds image (if needed) then starts QEMU paused with gdb attached using `scripts/debug-qemu.sh`. |
| `clean`  | Remove build artifacts (build directory, images, logs). |
| `distclean` | More thorough clean (same as clean; pass DIST_EXTRAS=yes to script to also remove firmware/limine). |

### Environment Overrides
Most scripts honor environment variables. Examples:
```bash
IMG=build/custom.img IMG_SIZE_MB=128 make image   # Larger image
RAM=1024 SMP=2 make run                           # More RAM & vCPUs
GDB=yes make run                                  # Start QEMU waiting for gdb (manual attach)
NO_GDB=yes make debug                             # Launch only QEMU gdb stub
make clean                                        # Remove build/ and generated images
make distclean                                   # Deeper clean (keeps firmware by default)
```

## 4. Building & Running

Warning, make sure all scripts inside the `scripts/` directory are executable (`chmod +x scripts/*.sh`).

Build the kernel and disk image:
```bash
make image
```
Run it:
```bash
make run
```

Direct script usage:
```bash
scripts/make-efi-img.sh --force
scripts/run-qemu.sh
```

## 5. Debugging

Start QEMU with gdb auto-attached and a breakpoint at `_start`:
```bash
make debug
```
The GDB initialization file `debug.gdb` will:
- Connect to `:1234`
- Set `break _start`
- Continue execution
- Show registers each stop

Manual attach example (if you used `NO_GDB=yes`):
```bash
gdb -ex 'target remote :1234' build/kernel.elf
```

Common helpful GDB commands:
```
disassemble _start
info registers
x/16gx $rsp
bt
```

## 6. Disk Image Details

The image layout (single EFI System Partition):
```
/EFI/BOOT/BOOTX64.EFI
/kernel.elf
/startup.nsh
/limine.conf
```
Created via loop device + `parted` + `mkfs.vfat`. Script: `scripts/make-efi-img.sh`.

Adjust size:
```bash
IMG_SIZE_MB=128 make image
```

## 7. Cleanup Script (Loop Device Recovery)

If image creation was interrupted (Ctrl+C) you may end up with:
- Mounted `mnt-esp` directory that wasn't unmounted
- A loop device still attached to `build/disk.img`

Symptoms:
- `losetup -a` still lists `/dev/loopX` referencing your image
- `mount` shows a lingering mount at `.../mnt-esp`
- Subsequent `make image` fails or hangs

Run the cleanup tool:
```bash
scripts/cleanup-loops.sh
```
Dry run (preview actions):
```bash
DRY_RUN=yes scripts/cleanup-loops.sh
```
Force detach (only if you are sure nothing is using the device):
```bash
FORCE=yes scripts/cleanup-loops.sh
```
Specify a pattern of images:
```bash
IMG_PATTERN='build/disk*.img' scripts/cleanup-loops.sh
```

What it does:
1. Unmounts stale `mnt-esp` if mounted
2. Removes the directory if empty
3. Scans `losetup -a` for loop devices whose backing file matches `IMG_PATTERN`
4. Detaches them if safe (or if `FORCE=yes`)

WARNING: Using `FORCE=yes` can detach loop devices in use; always run a dry run first if unsure.

## 8. Customization Ideas
- Add additional kernel source files under `src/`
- Introduce a paging/long mode setup stub (if expanding beyond stub kernel)
- Extend `limine.conf` for additional menu entries
- Add `make iso` target using `xorriso` for hybrid boot

## 9. Troubleshooting
| Issue | Resolution |
|-------|------------|
| `Permission denied` during image build | Ensure you have sudo rights; the script uses loop + mount. |
| `mkfs.vfat: command not found` | Install `dosfstools`. |
| QEMU very slow | Try `ACCEL=kvm make run` (ensure `/dev/kvm` exists). |
| Breakpoint not hit | Confirm symbol `_start` exists (use `nm build/kernel.elf | grep _start`). |
| Loop device busy | Run `scripts/cleanup-loops.sh` (try `DRY_RUN=yes` first). |

## 10. License
This repository bundles Limine binaries in `limine/` which are licensed under their respective terms (see `limine/LICENSE`). Your own code here is currently unlicensed; consider adding a license file.

---
Happy hacking! Open to extending with more features (paging, memory map parsing, higher half, etc.).
