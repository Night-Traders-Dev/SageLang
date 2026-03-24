# Bare-Metal / OSdev / UEFI Guide (Initial Support)

This guide describes the first implementation stage for non-hosted native targets in SageLang.

## Target Syntax

Use `--target <arch[-profile]>` on native backend commands.

Base architectures:

- `x86-64` / `x86_64`
- `aarch64` / `arm64`
- `rv64` / `riscv64`

Profile suffixes:

- `-baremetal`
- `-osdev`
- `-uefi`

Examples:

```bash
# Emit assembly for x86_64 bare-metal entry
sage --emit-asm kernel.sage --target x86_64-baremetal -o kernel.s

# Build freestanding object for OSdev flow
sage --compile-native kernel.sage --target x86_64-osdev -o kernel.o

# Emit UEFI-oriented entry symbol
sage --emit-asm boot.sage --target x86_64-uefi -o boot_uefi.s
```

## Current Profile Behavior

### Hosted (default)

- No profile suffix.
- Uses normal hosted assumptions and executable-oriented flow.

### `-baremetal` and `-osdev`

- Assembly entry symbol switches to `sage_entry`.
- `--compile-native` currently emits a freestanding object (`.o`) as the initial support step.

### `-uefi`

- Assembly entry symbol switches to `efi_main`.
- `--compile-native` currently emits a freestanding object (`.o`).
- Full PE/COFF EFI image linking is planned as a follow-up step.
- `rv64-uefi` is currently rejected (x86_64/aarch64 only).

## What This Enables Today

- Early kernel/boot pipeline integration via generated assembly/object artifacts.
- Stable entry symbol selection per target profile.
- A clear bridge to external link scripts and custom boot chain tooling.

## Current Limitations

- Non-hosted targets are currently object-oriented output only (no final bootable image linker flow yet).
- UEFI output is not yet a finalized `.efi` artifact in this stage.
- Native backend coverage is still evolving; some language constructs remain unsupported in this backend path.

## Recommended Next Steps

1. Add profile-aware linker script integration for bare-metal and OSdev targets.
2. Add PE/COFF image emission/link path for UEFI (`.efi` output).
3. Expand native backend construct coverage and runtime surface for non-hosted use cases.
