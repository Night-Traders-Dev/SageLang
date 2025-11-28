# Phase 7 Implementation Status

> **Date**: November 28, 2025, 9:25 AM EST
> **Status**: IN PROGRESS

## ✅ Completed

### Part 1: Tokens & Lexer (DONE)
- ✅ Added 9 new tokens:
  - `TOKEN_MATCH`, `TOKEN_CASE`, `TOKEN_DEFAULT`
  - `TOKEN_TRY`, `TOKEN_CATCH`, `TOKEN_FINALLY`, `TOKEN_RAISE`
  - `TOKEN_DEFER`, `TOKEN_YIELD`
- ✅ Updated lexer to recognize all new keywords
- ✅ All keywords properly handled in `identifier_type()`

**Commit**: c9394f5 - "feat: Phase 7 Part 1 - Add new tokens for advanced control flow"

---

## 🚧 In Progress

The remaining work is substantial - approximately 2000-3000 lines of code across multiple files.

### Part 2: AST Nodes (TODO)

Need to add to `include/ast.h`:

```c
// Match expression
typedef struct {
    Expr* pattern;
    Stmt* body;
} CaseClause;

typedef struct {
    Expr* value;
    CaseClause** cases;
    int case_count;
    Stmt* default_case;
} MatchStmt;

// Exception handling
typedef struct {
    Stmt* try_block;
    Token error_var;
    Stmt* catch_block;
    Stmt* finally_block;
} TryStmt;

typedef struct {
    Expr* error_value;
} RaiseStmt;

// Defer
typedef struct {
    Stmt* statement;
} DeferStmt;

// Yield
typedef struct {
    Expr* value;
} YieldStmt;
```

Add to `Stmt` enum:
```c
STMT_MATCH,
STMT_TRY,
STMT_RAISE,
STMT_DEFER,
STMT_YIELD
```

### Part 3: Parser (TODO - ~800 lines)

Need to implement in `src/parser.c`:

1. **`match_statement()`** - Parse match/case/default
2. **`try_statement()`** - Parse try/catch/finally
3. **`raise_statement()`** - Parse raise expressions
4. **`defer_statement()`** - Parse defer
5. **`yield_statement()`** - Parse yield

Each requires:
- Token consumption
- Block parsing
- AST construction
- Error handling

### Part 4: Interpreter (TODO - ~1000 lines)

Need to implement in `src/interpreter.c`:

1. **Match Evaluation**:
   - Evaluate match value
   - Compare against each case
   - Execute matching case body
   - Handle default case

2. **Exception Handling**:
   - Exception value type
   - Exception stack/unwinding
   - Try block execution
   - Catch block on error
   - Finally block always executes
   - Raise statement throws

3. **Defer Execution**:
   - Defer stack per scope
   - LIFO execution on scope exit
   - Execute on return/break/continue/exception

4. **Generator Support**:
   - Generator value type
   - Yield statement suspends execution
   - Save/restore execution state
   - `next()` native function
   - Generator iteration in for loops

### Part 5: Value Types (TODO - `include/value.h`)

Need to add:
```c
typedef struct {
    char* message;
    int line;
} ExceptionValue;

typedef struct {
    ProcStmt* function;
    Env* env;
    Stmt* resume_point;
    int is_done;
} GeneratorValue;
```

Add to `ValueType` enum:
```c
VAL_EXCEPTION,
VAL_GENERATOR
```

---

## 📋 Implementation Strategy

Due to the size and complexity, we should implement Phase 7 in stages:

### Option A: Feature-by-Feature (Recommended)
1. **Week 1**: Match expressions only (simplest)
2. **Week 2**: Defer statements (moderate)
3. **Week 3**: Exception handling (complex)
4. **Week 4**: Generators (most complex)

### Option B: Layer-by-Layer
1. **Step 1**: All AST nodes
2. **Step 2**: All parser functions
3. **Step 3**: All interpreter logic
4. **Step 4**: All value types and GC support

### Option C: MVP First
1. Implement basic versions of all 4 features
2. Add advanced features incrementally
3. Refine and optimize

---

## 🎯 Estimated Effort

| Feature | Lines of Code | Complexity | Time Estimate |
|---------|--------------|------------|---------------|
| Match | ~400 lines | Low | 1-2 days |
| Defer | ~300 lines | Medium | 1-2 days |
| Try/Catch | ~600 lines | High | 3-4 days |
| Generators | ~800 lines | Very High | 4-5 days |
| **Total** | **~2100 lines** | - | **9-13 days** |

---

## ❓ Questions

1. **Should we implement all at once or incrementally?**
   - All at once = 1 large PR, harder to review
   - Incremental = 4 smaller PRs, easier to test

2. **Priority order?**
   - By difficulty (easiest first): match, defer, try/catch, yield
   - By usefulness (most useful first): try/catch, match, defer, yield
   - By dependency (least dependent first): defer, match, try/catch, yield

3. **Testing strategy?**
   - Write tests per feature
   - Write comprehensive test suite at end
   - Both?

---

## 💡 Recommendation

I recommend **Option A (Feature-by-Feature)** because:

1. Each feature can be tested independently
2. Easier to review and debug
3. Allows for incremental progress tracking
4. Reduces risk of introducing bugs
5. Can release working features sooner

We've completed the foundation (tokens/lexer). 

**Next Step**: Should we:
- a) Implement Match expressions first (simplest, ~2 days)
- b) Continue with all AST nodes for all features
- c) Create simplified "MVP" versions of all 4 features

Which approach would you prefer?