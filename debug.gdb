# GDB initialization script for kernel debugging with QEMU
# This file is auto-loaded by the debug script using: gdb -x debug.gdb build/kernel.elf

set pagination off
set confirm off

# Use Intel syntax if desired
set disassembly-flavor intel

# Load the symbol file explicitly (redundant when passing the elf on cmdline but explicit is fine)
file build/kernel.elf

# Connect to QEMU's gdb stub (started with -s -S -> localhost:1234)
target remote :1234

# Set a breakpoint at the kernel entry symbol
break _start

# Optionally stop on SIGSEGV instead of letting it pass
handle SIGSEGV stop print

# Display some useful registers each step
define hook-stop
    info registers rip rsp rbp rax rbx rcx rdx rsi rdi r8 r9 r10 r11 r12 r13 r14 r15
end

# Continue until breakpoint
continue
