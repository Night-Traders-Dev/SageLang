# SageLang Transpiler Library

The `transpiler` library provides a robust framework for creating language-to-SageLang transpilers. It follows a modular architecture where each supported language has its own dedicated directory.

## Structure
- `base.sage`: Defines the base `Transpiler` interface.
- `python/`: Contains Python-to-SageLang parser backends, factory, and emitter.
- `docs/`: Library documentation (SPEC, SECURITY, LANGUAGES).

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
