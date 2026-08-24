# SageLang v4.1.16 — Cross-Build Artifacts

Prebuilt `sage` compiler binaries for Linux on three architectures, plus the
arch-independent self-hosted (Sage-written) toolchain sources.

## Contents

| Path | Description |
|------|-------------|
| `linux-x86_64/sage`   | C build, x86-64 (hosted: curl/openssl + Vulkan/GLFW enabled) |
| `linux-aarch64/sage`  | C build, ARM64 (no-net/no-gpu; POSIX sockets work) |
| `linux-riscv64/sage`  | C build, RISC-V RV64 (no-net/no-gpu; POSIX sockets work) |
| `selfhost/sagelang-selfhost-v4.1.16.tar.gz` | Self-hosted compiler sources (`src/sage`, `lib`, `VERSION`) — runs on ANY of the above binaries |

## Verify

```sh
sha256sum -c SHA256SUMS
```

## Quick start

```sh
# C interpreter
./sage program.sage

# Self-hosted (double-interpretation) CLI
./sage src/sage/sage.sage program.sage
```

For the self-hosted tarball: extract it inside a directory next to a `sage`
binary (module search paths resolve `src/sage` and `lib`), then run
`sage src/sage/sage.sage your_program.sage`.

## Notes

- Cross builds are statically configured without libcurl/OpenSSL (`SAGE_NO_NET`)
  and GPU backends (`SAGE_NO_GPU`) — plain POSIX sockets still function.
- aarch64/riscv64 binaries were smoke-tested under `qemu-user`
  (`fib(20) = 6765` via both the C and self-hosted stacks).
