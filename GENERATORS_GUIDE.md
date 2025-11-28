# Generators and Yield - Implementation Guide

## Overview

Generators provide **lazy evaluation** - they produce values on-demand rather than computing everything upfront. This enables:
- Memory-efficient iteration over large sequences
- Infinite sequences without infinite memory
- Pipeline-style data processing
- Coroutine-like behavior

## Architecture

### Generator Lifecycle

```
1. Function with 'yield' → Creates generator object (suspended state)
2. First iteration → Execute until first yield
3. Each iteration → Resume, run until next yield
4. No more yields → Generator exhausted
```

### Key Components

#### 1. Generator Value Type
```c
// In include/value.h
typedef struct {
    Stmt* body;              // Function body containing yields
    Environment* closure;     // Captured environment
    int instruction_pointer;  // Resume point (which statement)
    int is_exhausted;         // No more values
    Value current_value;      // Last yielded value
} GeneratorValue;
```

#### 2. Yield Statement AST
```c
// In include/ast.h
typedef struct {
    Expr* value;  // Value to yield
} YieldStmt;

// Add to Stmt enum:
STMT_YIELD

// Add to Stmt union:
YieldStmt yield_stmt;
```

#### 3. Generator Detection
When parsing a `proc`, scan body for `yield` statements:
- If found → Mark as generator function
- Returns generator object instead of executing

## Implementation Steps

### Step 1: Lexer (Already Done)
`TOKEN_YIELD` already exists in token.h ✅

### Step 2: AST Updates

**include/ast.h:**
```c
// Add YieldStmt structure
typedef struct {
    Expr* value;  // Expression to yield
} YieldStmt;

// Add STMT_YIELD to enum
enum {
    // ... existing ...
    STMT_RAISE,
    STMT_YIELD  // NEW
} type;

// Add to union
union {
    // ... existing ...
    YieldStmt yield_stmt;  // NEW
} as;

// Add constructor
Stmt* new_yield_stmt(Expr* value);
```

**src/ast.c:**
```c
Stmt* new_yield_stmt(Expr* value) {
    Stmt* stmt = (Stmt*)malloc(sizeof(Stmt));
    stmt->type = STMT_YIELD;
    stmt->as.yield_stmt.value = value;
    stmt->next = NULL;
    return stmt;
}
```

### Step 3: Value System Updates

**include/value.h:**
```c
// Add to ValueType enum
typedef enum {
    // ... existing ...
    VAL_EXCEPTION,
    VAL_GENERATOR  // NEW
} ValueType;

// Add GeneratorValue structure
typedef struct {
    Stmt* body;              // Function body with yields
    Environment* closure;     // Captured environment
    Value* locals;            // Local variables state
    int locals_count;
    int next_stmt_index;      // Which statement to execute next
    int is_exhausted;         // No more values
} GeneratorValue;

// Update Value union
union {
    // ... existing ...
    GeneratorValue* generator;  // NEW
} as;

// Add macros
#define IS_GENERATOR(value) ((value).type == VAL_GENERATOR)
#define AS_GENERATOR(value) ((value).as.generator)

// Add constructor
Value val_generator(Stmt* body, Environment* closure);
```

**src/value.c:**
```c
Value val_generator(Stmt* body, Environment* closure) {
    Value val;
    val.type = VAL_GENERATOR;
    val.as.generator = (GeneratorValue*)malloc(sizeof(GeneratorValue));
    val.as.generator->body = body;
    val.as.generator->closure = closure;
    val.as.generator->locals = NULL;
    val.as.generator->locals_count = 0;
    val.as.generator->next_stmt_index = 0;
    val.as.generator->is_exhausted = 0;
    return val;
}

// Update print_value
void print_value(Value value) {
    switch (value.type) {
        // ... existing cases ...
        case VAL_GENERATOR:
            printf("<generator>");
            break;
    }
}
```

### Step 4: Parser Updates

**src/parser.c:**

```c
// Add yield_statement() function
static Stmt* yield_statement() {
    consume(TOKEN_YIELD, "Expect 'yield' keyword");
    
    Expr* value = NULL;
    // yield can be used without a value (yields nil)
    if (!check(TOKEN_NEWLINE) && !check(TOKEN_EOF)) {
        value = expression();
    }
    
    consume(TOKEN_NEWLINE, "Expect newline after yield");
    return new_yield_stmt(value);
}

// Update statement() to handle yield
static Stmt* statement() {
    // ... existing cases ...
    
    if (match(TOKEN_YIELD)) {
        return yield_statement();
    }
    
    // ... rest of cases ...
}

// Detect if function contains yields (helper)
static int contains_yield(Stmt* body) {
    Stmt* current = body;
    while (current != NULL) {
        if (current->type == STMT_YIELD) {
            return 1;
        }
        // Recursively check blocks
        if (current->type == STMT_BLOCK) {
            if (contains_yield(current->as.block.statements)) {
                return 1;
            }
        }
        if (current->type == STMT_IF) {
            if (contains_yield(current->as.if_stmt.then_branch) ||
                (current->as.if_stmt.else_branch && 
                 contains_yield(current->as.if_stmt.else_branch))) {
                return 1;
            }
        }
        // Check other compound statements...
        current = current->next;
    }
    return 0;
}
```

### Step 5: Interpreter - Generator Creation

**src/interpreter.c:**

```c
// When evaluating STMT_PROC, check for yields
case STMT_PROC: {
    Token name = stmt->as.proc.name;
    
    // Check if function body contains yield statements
    int is_generator = contains_yield(stmt->as.proc.body);
    
    Value func_val;
    if (is_generator) {
        // Create generator factory (returns generator on call)
        func_val = val_generator_factory(stmt->as.proc.body, 
                                         stmt->as.proc.params,
                                         stmt->as.proc.param_count,
                                         env);
    } else {
        // Regular function
        func_val = val_function(stmt->as.proc.name,
                               stmt->as.proc.params,
                               stmt->as.proc.param_count,
                               stmt->as.proc.body,
                               env);
    }
    
    env_define(env, name.start, name.length, func_val);
    return (ExecResult){.value = val_nil(), .is_returning = 0, .is_breaking = 0, .is_continuing = 0};
}
```

### Step 6: Interpreter - Yield Execution

```c
// Handle STMT_YIELD
case STMT_YIELD: {
    Value yield_value = val_nil();
    
    if (stmt->as.yield_stmt.value != NULL) {
        ExecResult result = eval_expr(stmt->as.yield_stmt.value, env);
        if (result.is_throwing) return result;
        yield_value = result.value;
    }
    
    // Return special "yielding" result
    ExecResult result = {0};
    result.value = yield_value;
    result.is_yielding = 1;  // NEW flag
    return result;
}
```

### Step 7: Iterator Protocol

**Native function: next(generator)**
```c
static Value native_next(int arg_count, Value* args) {
    if (arg_count != 1) {
        fprintf(stderr, "next() expects 1 argument\n");
        exit(1);
    }
    
    if (!IS_GENERATOR(args[0])) {
        fprintf(stderr, "next() expects a generator\n");
        exit(1);
    }
    
    GeneratorValue* gen = AS_GENERATOR(args[0]);
    
    if (gen->is_exhausted) {
        return val_nil();  // Or throw StopIteration
    }
    
    // Resume generator execution
    Environment* gen_env = gen->closure;
    ExecResult result = eval_stmt_from_index(gen->body, 
                                            gen->next_stmt_index,
                                            gen_env);
    
    if (result.is_yielding) {
        // Save state and return yielded value
        gen->next_stmt_index = result.next_index;
        return result.value;
    }
    
    // Generator finished
    gen->is_exhausted = 1;
    return val_nil();
}
```

## Usage Examples

### Example 1: Basic Generator
```sage
proc count_up_to(n):
    let i = 0
    while i < n:
        yield i
        i = i + 1

let gen = count_up_to(5)
let val = next(gen)  # 0
let val2 = next(gen) # 1
```

### Example 2: Infinite Sequence
```sage
proc fibonacci():
    let a = 0
    let b = 1
    while true:
        yield a
        let temp = a + b
        a = b
        b = temp

let fib = fibonacci()
let f1 = next(fib)  # 0
let f2 = next(fib)  # 1
let f3 = next(fib)  # 1
let f4 = next(fib)  # 2
```

### Example 3: For Loop Integration
```sage
proc range_gen(n):
    let i = 0
    while i < n:
        yield i
        i = i + 1

# Eventually support:
for i in range_gen(10):
    print i
```

### Example 4: Generator Pipeline
```sage
proc filter_even(gen):
    let val = next(gen)
    while val != nil:
        if val % 2 == 0:
            yield val
        val = next(gen)

let numbers = count_up_to(10)
let evens = filter_even(numbers)
```

## Testing Checklist

- [ ] Basic yield returns value
- [ ] Generator resumes at correct point
- [ ] Generator state persists between calls
- [ ] Generator exhaustion handled
- [ ] Nested generators work
- [ ] Generator with multiple yields
- [ ] Generator with conditionals
- [ ] Generator with loops
- [ ] Infinite generators
- [ ] Generator pipelines

## Implementation Priority

1. ✅ Token already exists
2. AST structures (YieldStmt)
3. Value type (VAL_GENERATOR)
4. Parser (yield_statement)
5. Basic interpreter (simple yield)
6. Generator state management
7. Iterator protocol (next function)
8. For-loop integration
9. Advanced features (send, throw)

## Next Steps After Generators

With Phase 7 complete:
- **Phase 8**: Module system and imports
- **Phase 9**: Low-level programming (inline assembly, FFI)
- **Phase 10**: Compiler development

---

**Status**: Ready for implementation
**Complexity**: Medium-High (requires state management)
**Impact**: High (enables functional programming patterns)