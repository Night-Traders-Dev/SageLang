# Supported Languages

This document tracks languages supported for transpilation to SageLang.

## Active Projects
- **Python**: Located in `core/lib/transpiler/python/`.

## Planned Languages
- **JavaScript/TypeScript**: Web-frontend-to-SageLang.
- **C**: Lower-level system migration.

To add a new language, create a new directory (e.g., `core/lib/transpiler/<lang>/`) and implement the `Transpiler` interface in `base.sage`.
