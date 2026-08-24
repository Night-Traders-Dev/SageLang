# Library Support Matrix

Import/behavior status of every bundled library under both interpreters
(`sage` = self-hosted CLI, `sage-c` = C host), as of v4.2.2.
Verified by importing all 295 modules from a neutral working directory.

## Summary

| Interpreter | Modules importing cleanly | Notes |
|-------------|--------------------------:|-------|
| sage-c      | 281 / 295                 | remaining failures are contract payloads, osdev-experimental sources, and examples that intentionally shell out |
| sage        | 273 / 295                 | additionally lacks `enum`/`trait` keywords and some C-only natives |

## Fully supported under BOTH interpreters

arrays, assert, chat/*, crypto/*, dicts, iter, json, math, option, perf,
rich/*, stats, std/* (except std.enum / std.trait on `sage`), strings,
string, sys, utils, transpiler/lily/*, transpiler/base,
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

## Known broken sources (parse errors under BOTH hosts)

`os.boot.dtb`, `os.boot.elf_load`, `os.ext`,
`transpiler.json_parser`, `transpiler.python.{ast_parser,emitter,factory}`

These are experimental modules with syntax the current parser rejects;
they need source-level fixes rather than interpreter changes.

## Self-hosted (`sage`) feature gaps

- `enum` / `trait` declaration keywords are not parsed yet
  (`std.enum`, `std.trait` fail).
- Host-only native modules (`gpu`, `http`, `tcp`, `socket`, `thread`,
  `ssl`, `ffi`, `vm`, `ml_native`) import as empty stubs; calling into
  them raises a missing-attribute error.
