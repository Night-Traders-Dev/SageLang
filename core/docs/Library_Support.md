# Library Support Matrix

Import/behavior status of every bundled library under both interpreters
(`sage` = self-hosted CLI, `sage-c` = C host), as of v4.2.10.
The C-host audit imports 331 non-executable library modules from a neutral working directory; executable examples and injected-state contract payloads are excluded.

## Summary

| Interpreter | Modules importing cleanly | Notes |
|-------------|--------------------------:|-------|
| sage-c      | 331 / 331                 | all non-executable library modules pass the import audit |
| sage        | not fully counted         | parser/runtime gaps remain; see the self-hosted section below |

## Fully supported under BOTH interpreters

arrays, assert, chat/*, crypto/*, dicts, iter, json, math, option, perf,
rich/*, stats, std/* (except std.enum / std.trait on `sage`), strings,
string, sys, utils, transpiler/lily/*, transpiler/cjs2esm/*, transpiler/base,
agent/*, blockchain/* (see exclusions), net/*, android/*, cuda/*,
discord/*, gc/*, llm/*, metal/*, mips/*

## C-host-only behavior

| Module | Reason |
|--------|--------|
| `ml.gpu_accel`, `ml` (import-time) | calls the `ml_native` C accelerator during import; `sage` provides an importable stub but top-level calls fail |
| `os.*`, `linux.syscalls` | use undefined `struct_def`/`struct_new` builtins; `sage-c` continues past these runtime errors, `sage` raises |
| `net.websocket` | parse error under both hosts (pre-existing) |

## Not importable by design

| Module | Reason |
|--------|--------|
| `blockchain.staking`, `blockchain.std.nft` | smart-contract payloads: they expect a `state` binding injected by the contract host |
| `os.examples.*` | demo programs that execute shell commands at import — blocked by the security sandbox |

## Source audit status

The C-host syntax check passes for all 342 tracked library `.sage` files.
The previously reported parse failures in `os.boot.dtb`, `os.boot.elf_load`,
`os.ext`, and the Python transpiler modules are repaired and importable.
The self-hosted interpreter still reports parser/runtime gaps for a small
number of C-oriented library features; those are listed below rather than
being treated as source syntax failures.

## Self-hosted (`sage`) feature gaps

- `enum` / `trait` declaration keywords are not parsed yet
  (`std.enum`, `std.trait` fail).
- Host-only native modules (`gpu`, `http`, `tcp`, `socket`, `thread`,
  `ssl`, `ffi`, `vm`, `ml_native`) import as empty stubs; calling into
  them raises a missing-attribute error.
