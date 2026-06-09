# Python-to-SageLang Transpiler Roadmap

This document outlines the development trajectory for the Python-to-SageLang transpiler.

## Status
- **Foundation**: Complete (Pipeline infrastructure, Backend Factory, `SageEmitter` basics).

## Phase 1: Core Emission Support (In Progress)
- [x] Basic statement support (`Assign`, `Pass`).
- [x] Basic block support (`FunctionDef`, `If`).
- [x] Expression support (`Call`, `Name`, `Constant`).
- [ ] Implement support for `For` and `While` loops.
- [ ] Implement support for `List`, `Dict`, and `Tuple` literals.
- [ ] Implement support for `ClassDef` and method emission.

## Phase 2: Native Parsing (Immediate Goal)
- [ ] Develop `SageNativeParser` to parse a subset of Python syntax (core expressions and statements) into the same AST structure as the Python `ast` module.
- [ ] Achieve feature parity between the Python-AST and Native parsers.

## Phase 3: Advanced Features
- [ ] Implement type inference to map Python's dynamic typing to SageLang's optional static typing.
- [ ] Map `asyncio` to SageLang generators/threads.
- [ ] Automated mapping of Python standard library calls to SageLang modules (`core/lib/`).

## Phase 4: Production Readiness
- [ ] Comprehensive test suite covering edge cases (closures, decorators, nested structures).
- [ ] Performance optimization of the emission pipeline.
- [ ] Full documentation on transpiler limitations (Python features that cannot be safely transpiled).
