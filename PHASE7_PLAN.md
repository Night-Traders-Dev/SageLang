# Phase 7: Advanced Control Flow - Implementation Plan

> **Start Date**: November 28, 2025
> **Target Completion**: December 2025

## Overview

Phase 7 completes the control flow features of SageLang by adding:
1. **Match expressions** - Pattern matching
2. **Exception handling** - try/catch/finally blocks  
3. **Defer statements** - Cleanup code
4. **Generator functions** - yield expressions

---

## 1. Match Expressions (Pattern Matching)

### Syntax Design

```sage
match value:
    case 0:
        print "Zero"
    case 1:
        print "One"
    case 2:
        print "Two"
    default:
        print "Other"
```

### Advanced Patterns

```sage
# With variables
match status:
    case "success":
        print "OK"
    case "error":
        print "Failed"
    default:
        print "Unknown"

# Range matching (future)
match age:
    case 0..12:
        print "Child"
    case 13..19:
        print "Teen"
    default:
        print "Adult"
```

### Implementation Plan

#### Tokens to Add
- `TOKEN_MATCH`
- `TOKEN_CASE`
- `TOKEN_DEFAULT`

#### AST Nodes

```c
typedef struct {
    Expr* pattern;  // Pattern to match (literal, variable, etc)
    Stmt* body;     // Code to execute
} CaseClause;

typedef struct {
    Expr* value;         // Value to match against
    CaseClause** cases;  // Array of case clauses
    int case_count;
    Stmt* default_case;  // Optional default clause
} MatchStmt;
```

#### Lexer Changes
- Add keywords: `match`, `case`, `default`

#### Parser Changes
- `match_statement()` function
- Parse `match value:` header
- Parse `case pattern:` clauses  
- Parse optional `default:` clause

#### Interpreter Changes
- Evaluate match value
- Compare against each case pattern
- Execute first matching case body
- Support fall-through prevention (auto-break)

---

## 2. Exception Handling (try/catch/finally)

### Syntax Design

```sage
try:
    let result = risky_operation()
    print result
catch error:
    print "Error occurred:"
    print error
finally:
    print "Cleanup"
```

### Raising Exceptions

```sage
proc divide(a, b):
    if b == 0:
        raise "Division by zero"
    return a / b

try:
    let result = divide(10, 0)
    print result
catch error:
    print "Caught:"
    print error
```

### Implementation Plan

#### Tokens to Add
- `TOKEN_TRY`
- `TOKEN_CATCH`
- `TOKEN_FINALLY`
- `TOKEN_RAISE`

#### AST Nodes

```c
typedef struct {
    Stmt* try_block;
    Token error_var;     // Variable to bind error to
    Stmt* catch_block;   // Optional
    Stmt* finally_block; // Optional
} TryStmt;

typedef struct {
    Expr* error_value;  // Error message/value to raise
} RaiseStmt;
```

#### Interpreter Changes
- Exception stack/unwinding mechanism
- Catch blocks catch exceptions in try block
- Finally blocks always execute (even with return/break)
- `raise` statement creates and throws exception

---

## 3. Defer Statements

### Syntax Design

```sage
proc open_file(path):
    let file = open(path)
    defer close(file)
    
    # Do work with file
    let data = read(file)
    return data
    # close(file) automatically called here
```

### Multiple Defers (LIFO order)

```sage
proc transaction():
    begin()
    defer commit()
    
    lock()
    defer unlock()
    
    # Work happens
    do_work()
    
    # Executes in reverse order:
    # 1. unlock()
    # 2. commit()
```

### Implementation Plan

#### Tokens to Add
- `TOKEN_DEFER`

#### AST Nodes

```c
typedef struct {
    Stmt* statement;  // Statement to defer
} DeferStmt;
```

#### Interpreter Changes
- Maintain defer stack per scope
- Push defer statements when encountered
- Execute defers in LIFO order when scope exits
- Execute defers even if return/break/continue/exception occurs

---

## 4. Generator Functions (yield)

### Syntax Design

```sage
proc fibonacci():
    let a = 0
    let b = 1
    while true:
        yield a
        let temp = a
        let a = b
        let b = temp + b

# Usage
let gen = fibonacci()
for i in range(10):
    let value = next(gen)
    print value
```

### Generator with Arguments

```sage
proc countdown(n):
    while n > 0:
        yield n
        let n = n - 1
    yield "Done!"

let gen = countdown(5)
for value in gen:
    print value
```

### Implementation Plan

#### Tokens to Add
- `TOKEN_YIELD`

#### AST Nodes

```c
typedef struct {
    Expr* value;  // Value to yield
} YieldStmt;
```

#### Value Types

```c
typedef struct {
    ProcStmt* function;  // Generator function
    Env* env;            // Captured environment
    Stmt* current_stmt;  // Resume point
    int is_done;         // Generator exhausted?
} GeneratorValue;
```

#### Interpreter Changes
- Detect `yield` in function body → mark as generator
- Generator calls create GeneratorValue instead of executing
- `next(gen)` resumes generator from last yield
- Save/restore execution state between yields
- Generators are iterable in for loops

---

## Implementation Order

### Week 1: Match Expressions
1. Add tokens (match, case, default)
2. Add AST nodes (MatchStmt, CaseClause)
3. Implement lexer keyword recognition
4. Implement parser for match statements
5. Implement interpreter evaluation
6. Add tests and examples

### Week 2: Exception Handling  
1. Add tokens (try, catch, finally, raise)
2. Add AST nodes (TryStmt, RaiseStmt)
3. Add exception value type
4. Implement exception stack/unwinding
5. Implement try/catch/finally interpreter logic
6. Add tests and examples

### Week 3: Defer Statements
1. Add token (defer)
2. Add AST node (DeferStmt)
3. Implement defer stack per scope
4. Implement LIFO defer execution
5. Ensure defers run on all exit paths
6. Add tests and examples

### Week 4: Generators (yield)
1. Add token (yield)
2. Add AST node (YieldStmt)
3. Add GeneratorValue type
4. Implement generator creation
5. Implement yield/resume mechanism
6. Implement next() and iteration
7. Add tests and examples

---

## Testing Plan

### Match Expression Tests
- Simple value matching
- String matching
- Default clause
- Nested matches
- Match in functions

### Exception Handling Tests
- Basic try/catch
- Try/finally without catch
- Try/catch/finally together
- Nested try blocks
- Raising exceptions
- Exception in catch block

### Defer Tests
- Single defer
- Multiple defers (LIFO)
- Defer with return
- Defer with break/continue
- Defer with exceptions

### Generator Tests
- Basic yield
- Yield in loops
- Generator with arguments
- Nested generators
- Generator exhaustion
- Generator in for loop

---

## Examples to Create

1. `match_demo.sage` - Pattern matching examples
2. `exception_demo.sage` - Error handling examples
3. `defer_demo.sage` - Resource cleanup examples
4. `generator_demo.sage` - Iterator patterns
5. `phase7_complete.sage` - All Phase 7 features together

---

## Success Criteria

✅ All 4 features implemented and tested
✅ Examples demonstrate all features
✅ Documentation updated
✅ ROADMAP.md marks Phase 7 complete
✅ No regressions in existing features
✅ Clean error messages for new syntax

---

## Notes

- Start with simpler features (match, defer) before complex ones (exceptions, generators)
- Ensure backward compatibility with all Phase 1-6 code
- Generators are the most complex - leave for last
- Consider performance impact of defer stacks
- Exception handling needs careful memory management (GC integration)
