# Contributing to SageLang

First, thank you for taking the time to contribute to SageLang.

SageLang is more than a programming language—it is an entire systems programming ecosystem focused on performance, portability, readability, and long-term maintainability. Every contribution helps improve the language, compiler, virtual machine, tooling, documentation, and operating system.

We welcome contributors of every experience level.

---

# Table of Contents

- Philosophy
- Ways to Contribute
- Before You Begin
- Development Workflow
- Coding Standards
- Commit Message Guidelines
- Pull Request Guidelines
- Documentation Standards
- Testing Requirements
- Performance Expectations
- Security
- Project Structure
- Reporting Bugs
- Suggesting Features
- Good First Issues
- Code Review Process
- Contributor Recognition

---

# Philosophy

SageLang is designed around several core principles:

- Readability over cleverness
- Performance without sacrificing maintainability
- Cross-platform first
- Minimal dependencies
- Predictable behavior
- Strong documentation
- Stable APIs whenever possible

When contributing, always ask:

> "Will this make SageLang easier to understand, maintain, and extend five years from now?"

---

# Ways to Contribute

There are many ways to help.

## Language

- Parser improvements
- Lexer improvements
- AST optimizations
- Type checker
- Optimizer
- Compiler backend
- Runtime improvements

## Virtual Machine

- Performance
- Memory management
- Bytecode execution
- New instructions
- Debugging tools

## Standard Library

- Collections
- Math
- Filesystem
- Networking
- Cryptography
- Unicode
- Compression
- Concurrency

## SageOS

- Boot process
- Drivers
- Filesystems
- Shell
- Services
- Package manager

## Documentation

Documentation is considered first-class code.

Good documentation is just as valuable as good code.

Contributions include:

- Tutorials
- Examples
- API documentation
- Architecture documentation
- Design documents
- Diagrams
- Benchmarks

---

# Before You Begin

Before starting significant work:

1. Search existing Issues.
2. Search existing Pull Requests.
3. Open an Issue if your work changes language behavior.
4. Discuss major architectural changes before implementation.

Large pull requests without discussion may be closed.

---

# Development Workflow

1. Fork the repository.
2. Clone your fork.

```bash
git clone https://github.com/<your-username>/SageLang.git
```

3. Create a feature branch.

```bash
git checkout -b feature/my-feature
```

Never develop directly on `main`.

---

# Keep Your Branch Updated

```bash
git remote add upstream https://github.com/Night-Traders-Dev/SageLang.git

git fetch upstream

git rebase upstream/main
```

Keep pull requests focused on one feature or one bug fix.

---

# Coding Standards

## General

Write code for humans first.

Good code should be:

- obvious
- readable
- modular
- documented
- testable

Avoid unnecessary abstraction.

Avoid "magic."

If something needs a comment to explain what it does, consider rewriting it.

---

## Naming

Use descriptive names.

Good:

```
compile_expression()
```

Bad:

```
doStuff()
```

---

## Functions

Functions should perform one task.

Prefer small reusable functions.

Avoid giant functions that perform unrelated work.

---

## Comments

Explain **why**, not **what**.

Good:

```c
// Prevent stack corruption when recursion exceeds VM limits.
```

Bad:

```c
// Increment i
i++;
```

---

## Formatting

Maintain consistent formatting.

Use the project's formatter whenever available.

Do not reformat unrelated files.

---

# Performance Expectations

Performance is a major goal of SageLang.

Contributors should:

- avoid unnecessary allocations
- avoid unnecessary copies
- benchmark meaningful changes
- reduce compile times
- reduce runtime overhead

Never sacrifice correctness for speed.

Always measure before optimizing.

---

# Testing Requirements

Every bug fix should include a regression test whenever possible.

Every new language feature should include:

- parser tests
- compiler tests
- runtime tests
- documentation examples

Tests should be deterministic.

---

# Documentation Standards

Every user-facing feature should include documentation.

Documentation should answer:

- What does it do?
- Why does it exist?
- When should it be used?
- Examples
- Limitations
- Performance considerations

Examples should compile.

---

# Commit Message Guidelines

Use short, descriptive commit messages.

Examples:

```
compiler: improve constant folding

vm: fix stack overflow detection

runtime: optimize string allocation

parser: support trailing commas

docs: add pattern matching tutorial
```

Avoid messages like:

```
fix

update

changes

misc
```

---

# Pull Request Guidelines

A pull request should:

- solve one problem
- build successfully
- pass tests
- include documentation
- include benchmarks (when performance changes)
- include tests

Before opening a PR:

- build the project
- run tests
- review your own changes
- remove debug code
- remove commented-out code

---

# Security

Security issues should **not** be opened as public Issues.

Instead, privately contact the maintainers with:

- description
- impact
- proof of concept (if applicable)
- suggested mitigation

Responsible disclosure is appreciated.

---

# Project Structure

Typical project layout:

```
compiler/
runtime/
vm/
stdlib/
tools/
docs/
examples/
tests/
benchmarks/
```

Keep new files organized within the existing structure.

---

# Reporting Bugs

Please include:

- operating system
- architecture
- compiler version
- SageLang version
- expected behavior
- actual behavior
- reproduction steps
- sample code
- logs
- stack trace (if applicable)

Minimal reproducible examples are greatly appreciated.

---

# Suggesting Features

Feature requests should explain:

- the problem
- the proposed solution
- alternatives considered
- compatibility concerns
- performance implications

Language features should justify long-term maintenance costs.

---

# Good First Issues

New contributors may want to start with:

- documentation
- examples
- typo fixes
- test improvements
- benchmark additions
- standard library enhancements
- bug fixes labeled **good first issue**

---

# Code Review Process

Every pull request is reviewed for:

- correctness
- maintainability
- style
- architecture
- documentation
- performance
- security
- testing

Review feedback is intended to improve the project, not criticize contributors.

Discussion is encouraged.

---

# Contributor Recognition

Every contributor helps shape SageLang.

Whether you contribute:

- one typo fix
- one benchmark
- one bug fix
- one major subsystem

your work is appreciated.

Open source succeeds because of people willing to improve it.

Thank you for helping build SageLang.

---

# License

By submitting a contribution, you agree that your work will be licensed under the same license as the SageLang project unless explicitly stated otherwise.

---

Happy coding.

Welcome to SageLang.
