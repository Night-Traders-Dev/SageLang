# SageLang Transpiler Library

The `transpiler` library provides a robust framework for creating language-to-SageLang transpilers. It follows a modular architecture separating parsing logic from SageLang emission.

## Structure
- `base.sage`: Defines the base `Transpiler` interface.
- `parsers/`: Language-specific parsing logic.
- `emitters/`: Language-specific SageLang code emission.

## Quick Start
To create a new transpiler, inherit from `Transpiler` and implement `parse` and `emit`.

```sage
import transpiler.base

class MyLangTranspiler(Transpiler):
    proc parse(source: String) -> Object:
        # Parse MyLang to an internal AST representation
        ...
    
    proc emit(ast: Object) -> String:
        # Convert internal AST to SageLang code
        ...
```
