# Transpiler Library Specification

## Core Concepts
1. **Source Language (SL)**: The input language to be transpiled.
2. **Intermediate Representation (IR/AST)**: The internal representation of the source code.
3. **Target Language (SageLang)**: The output language.

## Interface Definition (`base.sage`)
The `Transpiler` class enforces the following:

- `parse(source: String) -> Object`: Takes raw source code and returns an Abstract Syntax Tree (AST).
- `emit(ast: Object) -> String`: Takes the AST and returns valid SageLang source code.
- `transpile(source: String) -> String`: High-level wrapper that executes the pipeline.
