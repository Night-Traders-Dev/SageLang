# Phase 8: Module System - Implementation Guide

> **Started**: December 1, 2025
> **Status**: In Progress (Foundation Complete)
> **Branch**: `phase8-modules`

## Overview

Phase 8 adds a complete module and package system to Sage, enabling code organization, reusability, and standard library development.

## Goals

1. **Import Syntax**: Support `import`, `from`, and `as` keywords
2. **Module Loading**: Load and execute external `.sage` files
3. **Module Cache**: Prevent duplicate loading and handle circular dependencies
4. **Standard Library**: Create foundation for stdlib modules (math, io, string)
5. **Package Support**: Enable package directories with `__init__.sage`

---

## Implementation Progress

### ✅ Phase 8.1: Foundation (Complete)

- [x] Create `include/module.h` - Module system header
- [x] Create `src/module.c` - Module loading implementation
- [x] Add `TOKEN_IMPORT`, `TOKEN_FROM`, `TOKEN_AS` to `token.h`
- [x] Add `STMT_IMPORT` and `ImportStmt` to `ast.h`
- [x] Create example modules: `lib/math.sage`, `lib/utils.sage`
- [x] Create import demonstration: `examples/phase8_imports.sage`
- [x] Module cache with circular dependency detection
- [x] File path resolution with search paths

### 🔄 Phase 8.2: Lexer Updates (In Progress)

**File**: `src/lexer.c`

- [ ] Add keyword recognition for `import`, `from`, `as`
- [ ] Update keyword table in `check_keyword()` function
- [ ] Test lexer with import statements

**Changes needed**:
```c
// In check_keyword(), add:
case 'i': return check_rest(1, 5, "mport", TOKEN_IMPORT);
case 'f': 
    if (length == 4 && memcmp(start, "from", 4) == 0) {
        return TOKEN_FROM;
    }
    // ... existing 'for' check
case 'a':
    if (length == 2 && memcmp(start, "as", 2) == 0) {
        return TOKEN_AS;
    }
    // ... existing 'and' check
```

### 📋 Phase 8.3: Parser Updates (Next)

**File**: `src/parser.c`

- [ ] Implement `parse_import_statement()`
- [ ] Handle three import syntaxes:
  - `import module`
  - `from module import item1, item2`
  - `import module as alias`
- [ ] Add to statement parsing in `parse_statement()`
- [ ] Create import AST nodes

**Parser Functions to Add**:
```c
Stmt* parse_import_statement() {
    // import module
    // from module import item1, item2
    // import module as alias
}
```

### 📋 Phase 8.4: AST Constructor (Next)

**File**: `src/ast.c`

- [ ] Implement `new_import_stmt()`
- [ ] Handle memory allocation for import data
- [ ] Support all import types

**Function to Add**:
```c
Stmt* new_import_stmt(char* module_name, char** items, 
                      int item_count, char* alias, int import_all) {
    Stmt* stmt = malloc(sizeof(Stmt));
    stmt->type = STMT_IMPORT;
    stmt->as.import.module_name = strdup(module_name);
    stmt->as.import.items = items;
    stmt->as.import.item_count = item_count;
    stmt->as.import.alias = alias ? strdup(alias) : NULL;
    stmt->as.import.import_all = import_all;
    stmt->next = NULL;
    return stmt;
}
```

### 📋 Phase 8.5: Interpreter Updates (Next)

**File**: `src/interpreter.c`

- [ ] Add `STMT_IMPORT` case to `execute_statement()`
- [ ] Call module system functions
- [ ] Handle import errors
- [ ] Initialize module system on startup

**Interpreter Changes**:
```c
case STMT_IMPORT: {
    ImportData import_data;
    import_data.module_name = stmt->as.import.module_name;
    import_data.items = // convert to ImportItem array
    import_data.item_count = stmt->as.import.item_count;
    import_data.alias = stmt->as.import.alias;
    import_data.type = stmt->as.import.import_all ? IMPORT_ALL : IMPORT_FROM;
    
    if (!import_module(env, &import_data)) {
        // Handle error
    }
    break;
}
```

### 📋 Phase 8.6: Main Integration

**File**: `src/main.c`

- [ ] Call `init_module_system()` on startup
- [ ] Call `cleanup_module_system()` on exit
- [ ] Add module search path command-line options

### 📋 Phase 8.7: Build System

**File**: `Makefile`

- [ ] Add `src/module.c` to build
- [ ] Update dependencies
- [ ] Ensure proper linking order

**Makefile Update**:
```makefile
OBJS = src/main.o src/lexer.o src/parser.o src/ast.o \
       src/env.o src/value.o src/gc.o src/interpreter.o \
       src/module.o  # ADD THIS
```

---

## Import Syntax Specification

### 1. Simple Import
```sage
import math

let result = math.sqrt(16)
print result  # 4
```

### 2. From Import
```sage
from math import sqrt, abs

print sqrt(25)   # 5
print abs(-10)   # 10
```

### 3. Import with Alias
```sage
import math as m

let val = m.pow(2, 8)
print val  # 256
```

### 4. From Import with Alias
```sage
from utils import average as avg

let numbers = [1, 2, 3, 4, 5]
print avg(numbers)  # 3
```

### 5. Multiple Imports
```sage
import math
import utils
from string import upper, lower

print math.PI
print utils.is_even(10)
print upper("hello")
```

---

## Module Search Path

Modules are searched in the following order:

1. **Current directory**: `./`
2. **Local lib**: `./lib/`
3. **Local modules**: `./modules/`
4. **System lib**: `/usr/local/lib/sage/` (future)

### Module File Resolution

For `import math`, Sage looks for:
1. `./math.sage`
2. `./lib/math.sage`
3. `./modules/math.sage`
4. `./math/__init__.sage` (package support)
5. `./lib/math/__init__.sage`
6. `./modules/math/__init__.sage`

---

## Standard Library Modules

### lib/math.sage

Functions:
- `sqrt(n)` - Square root
- `abs(n)` - Absolute value
- `max(a, b)` - Maximum
- `min(a, b)` - Minimum
- `pow(base, exp)` - Power
- `factorial(n)` - Factorial

Constants:
- `PI = 3.14159265359`
- `E = 2.71828182846`

### lib/utils.sage

Functions:
- `is_even(n)` - Check if even
- `is_odd(n)` - Check if odd
- `clamp(val, min, max)` - Clamp value
- `sum_array(arr)` - Sum array elements
- `average(arr)` - Array average

### Future Modules

- **lib/io.sage**: File I/O, console operations
- **lib/string.sage**: Advanced string operations
- **lib/collections.sage**: Additional data structures
- **lib/random.sage**: Random number generation

---

## Testing Strategy

### Unit Tests

1. **Module Loading**
   - Load existing module
   - Load non-existent module (error)
   - Circular dependency detection

2. **Import Variants**
   - `import module`
   - `from module import item`
   - `import module as alias`
   - Multiple imports

3. **Module Cache**
   - Module loaded only once
   - Cache lookup performance
   - Module unloading

### Integration Tests

```sage
# test_imports.sage
import math
from utils import average

let nums = [1, 2, 3, 4, 5]
let avg = average(nums)
let sqrt_avg = math.sqrt(avg)

print "Average: " + str(avg)
print "Sqrt of average: " + str(sqrt_avg)
```

---

## Implementation Checklist

### Core Implementation
- [x] Module header file
- [x] Module implementation
- [x] Token additions
- [x] AST additions
- [ ] Lexer keyword recognition
- [ ] Parser import statement
- [ ] AST constructor
- [ ] Interpreter integration
- [ ] Main initialization
- [ ] Makefile updates

### Features
- [x] Module cache
- [x] Circular dependency detection
- [x] Search path resolution
- [ ] Import all (`import module`)
- [ ] Import from (`from module import item`)
- [ ] Import as (`import module as alias`)
- [ ] Package support (`__init__.sage`)

### Standard Library
- [x] math module (basic)
- [x] utils module (basic)
- [ ] io module
- [ ] string module
- [ ] collections module

### Documentation
- [x] Phase 8 guide
- [ ] Module authoring guide
- [ ] API documentation
- [ ] Example programs

### Testing
- [ ] Lexer tests
- [ ] Parser tests
- [ ] Module loading tests
- [ ] Import variant tests
- [ ] Error handling tests
- [ ] Integration tests

---

## Next Steps

1. **Update Lexer** (`src/lexer.c`)
   - Add `import`, `from`, `as` to keyword table
   - Test lexer output

2. **Update Parser** (`src/parser.c`)
   - Implement `parse_import_statement()`
   - Add to `parse_statement()` switch
   - Test AST generation

3. **Update AST** (`src/ast.c`)
   - Implement `new_import_stmt()`
   - Test AST node creation

4. **Update Interpreter** (`src/interpreter.c`)
   - Add `STMT_IMPORT` case
   - Call module loading functions
   - Test import execution

5. **Update Makefile**
   - Add module.c to build
   - Test compilation

6. **Integration Testing**
   - Run `examples/phase8_imports.sage`
   - Test all import variants
   - Verify module caching

---

## Future Enhancements (Phase 8+)

### Package Manager (Phase 8.8)
- `sage.toml` package manifest
- Dependency resolution
- Package registry
- Version management
- Lock files

### Advanced Features
- Lazy module loading
- Module hot-reloading (development mode)
- Compiled module cache (.sagec files)
- Module introspection
- Module documentation extraction

### Native Modules
- C extension API
- Foreign Function Interface (FFI)
- Dynamic library loading
- Platform-specific modules

---

## Resources

- **Branch**: `phase8-modules`
- **Header**: `include/module.h`
- **Implementation**: `src/module.c`
- **Examples**: `lib/math.sage`, `lib/utils.sage`
- **Tests**: `examples/phase8_imports.sage`

---

**Last Updated**: December 1, 2025
**Next Milestone**: Lexer and Parser updates for import statement parsing
