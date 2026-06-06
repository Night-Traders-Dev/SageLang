# Import Resolution Fix Plan

## Objective
Enable the SageLang compiler to correctly resolve symbols imported from modules.

## Background
The compiler currently fails to resolve names from imported modules (`re`, `host_thread`, `math`) because the `resolve_slot_name` function only checks the `locals` and `globals` symbol tables and ignores `compiler->modules`.

## Proposed Solution
Modify `resolve_slot_name` in `.deps/SageLang/core/src/c/compiler.c` to traverse the `compiler->modules` linked list and check if the requested name exists within any of the imported modules.

## Implementation Steps
1. **Modify `resolve_slot_name`**:
   - Update `resolve_slot_name` to iterate through `compiler->modules`.
   - For each module, examine its `ast` (Stmt linked list) to find the procedure or variable definition matching `sage_name`.
   - If found, return the corresponding `c_name`.

2. **Update Symbol Lookup Logic**:
   - Ensure the `ImportedModule` structure or the module-level lookup provides a fast way to find symbols, perhaps by building a symbol table for each imported module.

3. **Testing**:
   - Verify that `sgvm_vm.sage` compiles correctly with the existing imports.
   - Run existing tests in `.deps/SageLang/tests/` to ensure no regression.

## Risks
- Modifying the compiler core may introduce regressions.
- Increased compilation time if module symbol lookup is inefficient.

## Verification
- Successful build of `sgvm`.
- Successful execution of example programs that use module imports.
