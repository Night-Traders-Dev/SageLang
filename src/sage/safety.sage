gc_disable()
# -----------------------------------------
# safety.sage - Self-hosted safety analyzer for SageLang
# Ownership tracking, borrow checking, lifetime analysis.
#
# This is a static analysis pass that walks the AST after parsing
# and before code generation. It detects ownership violations,
# use-after-move, borrow conflicts, and dangling references.
#
# Mirrors the C implementation in src/c/safety.c.
# -----------------------------------------

from ast import EXPR_NUMBER, EXPR_STRING, EXPR_BOOL, EXPR_NIL
from ast import EXPR_BINARY, EXPR_VARIABLE, EXPR_CALL, EXPR_ARRAY
from ast import EXPR_INDEX, EXPR_DICT, EXPR_TUPLE, EXPR_SLICE
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC, STMT_DEFER, STMT_MATCH

# ============================================================================
# Safety Mode Constants
# ============================================================================

let MODE_OFF = 0         # Classic SageLang: no safety checks
let MODE_ANNOTATED = 1   # Only check @safe-annotated procs/blocks
let MODE_STRICT = 2      # Enforce everything globally

# ============================================================================
# Ownership State Constants
# ============================================================================

let OWN_OWNED = 0        # Variable owns its data
let OWN_MOVED = 1        # Ownership transferred; variable is dead
let OWN_BORROWED = 2     # Immutable borrow active
let OWN_MUT_BORROW = 3   # Mutable borrow active
let OWN_PARTIAL = 4      # Partially moved (field moved out)
let OWN_UNINITIALIZED = 5 # Declared but not yet assigned

# ============================================================================
# Diagnostic Kind Constants
# ============================================================================

let DIAG_USE_AFTER_MOVE = 0
let DIAG_DOUBLE_MOVE = 1
let DIAG_BORROW_WHILE_MUT_BORROWED = 2
let DIAG_MUT_BORROW_WHILE_BORROWED = 3
let DIAG_MULTIPLE_MUT_BORROWS = 4
let DIAG_DANGLING_REFERENCE = 5
let DIAG_LIFETIME_EXPIRED = 6
let DIAG_NIL_IN_SAFE = 7
let DIAG_UNWRAP_WITHOUT_CHECK = 8
let DIAG_UNSAFE_IN_SAFE = 9
let DIAG_NOT_SEND = 10
let DIAG_NOT_SYNC = 11
let DIAG_UNINITIALIZED_USE = 12
let DIAG_PARTIAL_MOVE = 13

# Diagnostic level constants
let LEVEL_ERROR = 0
let LEVEL_WARNING = 1

# Primitive type names that are implicitly Copy
let COPY_TYPES = ["Int", "Float", "Bool", "String", "Num"]

# ============================================================================
# Diagnostic Kind -> String
# ============================================================================

proc diag_kind_str(kind):
    if kind == DIAG_USE_AFTER_MOVE:
        return "use-after-move"
    end
    if kind == DIAG_DOUBLE_MOVE:
        return "double-move"
    end
    if kind == DIAG_BORROW_WHILE_MUT_BORROWED:
        return "borrow-conflict"
    end
    if kind == DIAG_MUT_BORROW_WHILE_BORROWED:
        return "borrow-conflict"
    end
    if kind == DIAG_MULTIPLE_MUT_BORROWS:
        return "multiple-mut-borrow"
    end
    if kind == DIAG_DANGLING_REFERENCE:
        return "dangling-ref"
    end
    if kind == DIAG_LIFETIME_EXPIRED:
        return "lifetime"
    end
    if kind == DIAG_NIL_IN_SAFE:
        return "no-nil"
    end
    if kind == DIAG_UNWRAP_WITHOUT_CHECK:
        return "unwrap"
    end
    if kind == DIAG_UNSAFE_IN_SAFE:
        return "unsafe-in-safe"
    end
    if kind == DIAG_NOT_SEND:
        return "not-send"
    end
    if kind == DIAG_NOT_SYNC:
        return "not-sync"
    end
    if kind == DIAG_UNINITIALIZED_USE:
        return "uninitialized"
    end
    if kind == DIAG_PARTIAL_MOVE:
        return "partial-move"
    end
    return "unknown"
end

# ============================================================================
# Safety Context Creation
# ============================================================================

proc make_context(mode, filename):
    # The context holds all analysis state as a dict.
    let ctx = {}
    ctx["mode"] = mode
    ctx["scopes"] = []       # Stack of scope dicts
    ctx["diagnostics"] = []  # List of diagnostic dicts
    ctx["error_count"] = 0
    ctx["warning_count"] = 0
    ctx["filename"] = filename
    ctx["in_proc"] = false
    ctx["current_proc"] = nil
    ctx["next_lifetime_id"] = 1
    # Push global scope
    let is_safe = 0
    if mode == MODE_STRICT:
        is_safe = 1
    end
    push_scope(ctx, false, is_safe)
    return ctx
end

# ============================================================================
# Scope Management
# ============================================================================

proc push_scope(ctx, is_unsafe, is_safe):
    # Inherit unsafe/safe from parent scope
    let parent_unsafe = false
    let parent_safe = false
    let parent_depth = -1
    if len(ctx["scopes"]) > 0:
        let parent = ctx["scopes"][len(ctx["scopes"]) - 1]
        parent_unsafe = parent["is_unsafe"]
        parent_safe = parent["is_safe"]
        parent_depth = parent["depth"]
    end
    let scope = {}
    scope["vars"] = {}         # name -> var dict
    scope["borrows"] = []      # list of borrow dicts
    scope["depth"] = parent_depth + 1
    scope["is_unsafe"] = is_unsafe or parent_unsafe
    scope["is_safe"] = is_safe or parent_safe
    push(ctx["scopes"], scope)
    return scope
end

proc pop_scope(ctx):
    if len(ctx["scopes"]) == 0:
        return nil
    end
    let scope = ctx["scopes"][len(ctx["scopes"]) - 1]

    # Check for dangling references: borrows whose source is local
    let bi = 0
    while bi < len(scope["borrows"]):
        let b = scope["borrows"][bi]
        let src = lookup_var(ctx, b["source"])
        if src != nil:
            if src["scope_depth"] >= scope["depth"]:
                # Source is local to this scope -- reference will dangle
                emit_diag(ctx, LEVEL_ERROR, DIAG_DANGLING_REFERENCE, "reference outlives the data it borrows", "the borrowed value is destroyed at end of this scope", b["line"])
            end
        end
        bi = bi + 1
    end

    # Pop the scope off the stack
    pop(ctx["scopes"])
    return scope
end

proc current_scope(ctx):
    if len(ctx["scopes"]) == 0:
        return nil
    end
    return ctx["scopes"][len(ctx["scopes"]) - 1]
end

# ============================================================================
# Variable Tracking
# ============================================================================

proc declare_var(ctx, name, line):
    # Declare a new variable in the current scope.
    let scope = current_scope(ctx)
    if scope == nil:
        return nil
    end
    let var = {}
    var["name"] = name
    var["state"] = OWN_UNINITIALIZED
    var["is_option"] = false
    var["is_send"] = true
    var["is_sync"] = false
    var["is_copy"] = false
    var["decl_line"] = line
    var["moved_line"] = 0
    var["moved_to"] = nil
    var["borrow_count"] = 0
    var["mut_borrow_count"] = 0
    var["scope_depth"] = scope["depth"]
    var["lifetime_id"] = ctx["next_lifetime_id"]
    ctx["next_lifetime_id"] = ctx["next_lifetime_id"] + 1
    scope["vars"][name] = var
    return var
end

proc lookup_var(ctx, name):
    # Walk scopes from innermost to outermost.
    let i = len(ctx["scopes"]) - 1
    while i >= 0:
        let scope = ctx["scopes"][i]
        if dict_has(scope["vars"], name):
            return scope["vars"][name]
        end
        i = i - 1
    end
    return nil
end

proc mark_moved(var, line, dest):
    # Mark a variable as moved.
    if var == nil:
        return nil
    end
    var["state"] = OWN_MOVED
    var["moved_line"] = line
    var["moved_to"] = dest
end

proc mark_borrowed(ctx, var, borrower, line, is_mutable):
    # Record a borrow on var in the current scope.
    if var == nil:
        return nil
    end
    let scope = current_scope(ctx)
    let b = {}
    b["borrower"] = borrower
    b["source"] = var["name"]
    b["is_mutable"] = is_mutable
    b["line"] = line
    b["lifetime_id"] = var["lifetime_id"]
    push(scope["borrows"], b)
    if is_mutable:
        var["mut_borrow_count"] = var["mut_borrow_count"] + 1
        var["state"] = OWN_MUT_BORROW
    else:
        var["borrow_count"] = var["borrow_count"] + 1
        if var["state"] == OWN_OWNED:
            var["state"] = OWN_BORROWED
        end
    end
end

# ============================================================================
# Ownership Checks
# ============================================================================

proc check_use(ctx, name, line):
    # Check whether a variable is safe to use.
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["state"] == OWN_MOVED:
        let dest = var["moved_to"]
        if dest == nil:
            dest = "?"
        end
        let msg = "use of moved value '" + name + "' (moved to '" + dest + "' at line " + str(var["moved_line"]) + ")"
        emit_diag(ctx, LEVEL_ERROR, DIAG_USE_AFTER_MOVE, msg, "value was moved because it does not implement Copy", line)
        return false
    end
    if var["state"] == OWN_UNINITIALIZED:
        let msg = "use of possibly uninitialized variable '" + name + "'"
        emit_diag(ctx, LEVEL_ERROR, DIAG_UNINITIALIZED_USE, msg, "assign a value before using this variable", line)
        return false
    end
    return true
end

proc check_move(ctx, name, line, dest):
    # Check whether a variable can be moved.
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    # Copy types never move
    if var["is_copy"]:
        return true
    end
    if var["state"] == OWN_MOVED:
        let msg = "cannot move '" + name + "': already moved at line " + str(var["moved_line"])
        emit_diag(ctx, LEVEL_ERROR, DIAG_DOUBLE_MOVE, msg, "each value can only be moved once", line)
        return false
    end
    if var["borrow_count"] > 0 or var["mut_borrow_count"] > 0:
        let msg = "cannot move '" + name + "': it is currently borrowed"
        emit_diag(ctx, LEVEL_ERROR, DIAG_BORROW_WHILE_MUT_BORROWED, msg, "wait until all borrows have ended before moving", line)
        return false
    end
    mark_moved(var, line, dest)
    return true
end

proc check_borrow(ctx, name, line, is_mutable):
    # Check whether a variable can be borrowed.
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["state"] == OWN_MOVED:
        let msg = "cannot borrow '" + name + "': value has been moved"
        emit_diag(ctx, LEVEL_ERROR, DIAG_USE_AFTER_MOVE, msg, "the value was moved and is no longer available", line)
        return false
    end
    if is_mutable:
        # Mutable borrow: no other borrows allowed
        if var["borrow_count"] > 0:
            let msg = "cannot borrow '" + name + "' as mutable: already borrowed as immutable"
            emit_diag(ctx, LEVEL_ERROR, DIAG_MUT_BORROW_WHILE_BORROWED, msg, "an immutable reference exists; cannot create mutable reference", line)
            return false
        end
        if var["mut_borrow_count"] > 0:
            let msg = "cannot borrow '" + name + "' as mutable: already mutably borrowed"
            emit_diag(ctx, LEVEL_ERROR, DIAG_MULTIPLE_MUT_BORROWS, msg, "only one mutable reference is allowed at a time", line)
            return false
        end
    else:
        # Immutable borrow: no mutable borrows allowed
        if var["mut_borrow_count"] > 0:
            let msg = "cannot borrow '" + name + "' as immutable: already mutably borrowed"
            emit_diag(ctx, LEVEL_ERROR, DIAG_BORROW_WHILE_MUT_BORROWED, msg, "a mutable reference exists; cannot create immutable reference", line)
            return false
        end
    end
    return true
end

# ============================================================================
# Option / Nil Checks
# ============================================================================

proc check_nil_usage(ctx, line):
    # In strict or @safe context, nil usage is an error.
    let scope = current_scope(ctx)
    if ctx["mode"] == MODE_STRICT or (scope != nil and scope["is_safe"]):
        emit_diag(ctx, LEVEL_ERROR, DIAG_NIL_IN_SAFE, "nil is not allowed in safe context; use Option[T] instead", "wrap the value in Some(value) or use None", line)
        return false
    end
    return true
end

# ============================================================================
# Thread Safety Checks
# ============================================================================

proc check_send(ctx, name, line):
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["is_send"] == false:
        let msg = "'" + name + "' does not implement Send and cannot be transferred between threads"
        emit_diag(ctx, LEVEL_ERROR, DIAG_NOT_SEND, msg, "mark the type as Send or use a thread-safe wrapper", line)
        return false
    end
    return true
end

proc check_sync(ctx, name, line):
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["is_sync"] == false:
        let msg = "'" + name + "' does not implement Sync and cannot be shared between threads"
        emit_diag(ctx, LEVEL_ERROR, DIAG_NOT_SYNC, msg, "mark the type as Sync or use a Mutex wrapper", line)
        return false
    end
    return true
end

# ============================================================================
# Diagnostics
# ============================================================================

proc emit_diag(ctx, level, kind, message, hint, line):
    let d = {}
    d["level"] = level
    d["kind"] = kind
    d["message"] = message
    d["hint"] = hint
    d["filename"] = ctx["filename"]
    d["line"] = line
    push(ctx["diagnostics"], d)
    if level == LEVEL_ERROR:
        ctx["error_count"] = ctx["error_count"] + 1
    else:
        ctx["warning_count"] = ctx["warning_count"] + 1
    end
end

proc print_diagnostics(ctx):
    let i = 0
    while i < len(ctx["diagnostics"]):
        let d = ctx["diagnostics"][i]
        let level_str = "warning"
        if d["level"] == LEVEL_ERROR:
            level_str = "error"
        end
        let kind_str = diag_kind_str(d["kind"])
        print(level_str + "[" + kind_str + "]: " + d["message"])
        if d["filename"] != nil:
            print("  --> " + d["filename"] + ":" + str(d["line"]))
        end
        if d["hint"] != nil:
            print("  = help: " + d["hint"])
        end
        i = i + 1
    end
end

proc has_errors(ctx):
    return ctx["error_count"] > 0
end

# ============================================================================
# Helper: check if a type name is a Copy type
# ============================================================================

proc is_copy_type(type_name):
    let i = 0
    while i < len(COPY_TYPES):
        if COPY_TYPES[i] == type_name:
            return true
        end
        i = i + 1
    end
    return false
end

# ============================================================================
# Helper: extract variable name from expression node
# ============================================================================

proc get_var_name(expr):
    if expr == nil:
        return nil
    end
    if expr.type == EXPR_VARIABLE:
        return expr.name.text
    end
    return nil
end

proc get_expr_line(expr):
    if expr == nil:
        return 0
    end
    if expr.type == EXPR_VARIABLE:
        return expr.name.line
    end
    if expr.type == EXPR_BINARY:
        return expr.op.line
    end
    if expr.type == EXPR_GET:
        return expr.property.line
    end
    if expr.type == EXPR_CALL:
        return get_expr_line(expr.callee)
    end
    return 0
end

# ============================================================================
# AST Walker - Expression Analysis
# ============================================================================

proc analyze_expr(ctx, expr):
    if expr == nil:
        return nil
    end

    let etype = expr.type

    # Variable reference: check for use-after-move
    if etype == EXPR_VARIABLE:
        let name = expr.name.text
        let line = expr.name.line
        check_use(ctx, name, line)
        return nil
    end

    # nil literal: check in safe context
    if etype == EXPR_NIL:
        let scope = current_scope(ctx)
        if scope != nil and scope["is_safe"]:
            check_nil_usage(ctx, 0)
        end
        return nil
    end

    # Binary expression: recurse into both sides
    if etype == EXPR_BINARY:
        analyze_expr(ctx, expr.left)
        analyze_expr(ctx, expr.right)
        return nil
    end

    # Function call: analyze callee and arguments
    if etype == EXPR_CALL:
        analyze_expr(ctx, expr.callee)
        let ai = 0
        while ai < len(expr.args):
            let arg = expr.args[ai]
            analyze_expr(ctx, arg)
            # If argument is a variable, it may be moved into the function
            if arg != nil and arg.type == EXPR_VARIABLE:
                let name = arg.name.text
                let line = arg.name.line
                let var = lookup_var(ctx, name)
                let scope = current_scope(ctx)
                if var != nil and var["is_copy"] == false and scope != nil and scope["is_safe"]:
                    check_move(ctx, name, line, "(function argument)")
                end
            end
            ai = ai + 1
        end
        # Check for thread_spawn -- enforces Send trait
        if expr.callee != nil and expr.callee.type == EXPR_VARIABLE:
            let fn_name = expr.callee.name.text
            if fn_name == "thread_spawn" or fn_name == "async":
                let ti = 0
                while ti < len(expr.args):
                    let targ = expr.args[ti]
                    if targ != nil and targ.type == EXPR_VARIABLE:
                        check_send(ctx, targ.name.text, targ.name.line)
                    end
                    ti = ti + 1
                end
            end
        end
        return nil
    end

    # Index expression
    if etype == EXPR_INDEX:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.index)
        return nil
    end

    # Index set expression
    if etype == EXPR_INDEX_SET:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.index)
        analyze_expr(ctx, expr.value)
        return nil
    end

    # Property get
    if etype == EXPR_GET:
        analyze_expr(ctx, expr.object)
        return nil
    end

    # Property set: assignment to a property may move the value
    if etype == EXPR_SET:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.value)
        if expr.value != nil and expr.value.type == EXPR_VARIABLE:
            let val_name = expr.value.name.text
            let val_line = expr.value.name.line
            let var = lookup_var(ctx, val_name)
            let scope = current_scope(ctx)
            if var != nil and var["is_copy"] == false and scope != nil and scope["is_safe"]:
                check_move(ctx, val_name, val_line, "(property assignment)")
            end
        end
        return nil
    end

    # Array literal: analyze each element
    if etype == EXPR_ARRAY:
        let ei = 0
        while ei < len(expr.elements):
            analyze_expr(ctx, expr.elements[ei])
            ei = ei + 1
        end
        return nil
    end

    # Dict literal: analyze values
    if etype == EXPR_DICT:
        let di = 0
        while di < len(expr.values):
            analyze_expr(ctx, expr.values[di])
            di = di + 1
        end
        return nil
    end

    # Tuple literal
    if etype == EXPR_TUPLE:
        let ti = 0
        while ti < len(expr.elements):
            analyze_expr(ctx, expr.elements[ti])
            ti = ti + 1
        end
        return nil
    end

    # Slice expression
    if etype == EXPR_SLICE:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.start)
        analyze_expr(ctx, expr.stop)
        return nil
    end

    # Await expression
    if etype == EXPR_AWAIT:
        analyze_expr(ctx, expr.expression)
        return nil
    end

    # Literals (number, string, bool) -- nothing to check
    return nil
end

# ============================================================================
# AST Walker - Statement Analysis
# ============================================================================

proc analyze_stmt(ctx, stmt):
    if stmt == nil:
        return nil
    end

    let stype = stmt.type

    # ----- let declaration -----
    if stype == STMT_LET:
        let name = stmt.name.text
        let line = stmt.name.line
        let var = declare_var(ctx, name, line)

        # Analyze initializer
        if stmt.initializer != nil:
            analyze_expr(ctx, stmt.initializer)
            var["state"] = OWN_OWNED

            # If initializer is a variable, it may be a move
            let init_expr = stmt.initializer
            if init_expr.type == EXPR_VARIABLE and var["is_copy"] == false:
                let scope = current_scope(ctx)
                if scope != nil and scope["is_safe"]:
                    check_move(ctx, init_expr.name.text, line, name)
                end
            end

            # Literals are implicitly Copy
            if init_expr.type == EXPR_NUMBER or init_expr.type == EXPR_BOOL or init_expr.type == EXPR_STRING:
                var["is_copy"] = true
            end
        end
        return nil
    end

    # ----- expression statement -----
    if stype == STMT_EXPRESSION:
        analyze_expr(ctx, stmt.expression)
        return nil
    end

    # ----- print statement -----
    if stype == STMT_PRINT:
        analyze_expr(ctx, stmt.expression)
        return nil
    end

    # ----- if statement -----
    if stype == STMT_IF:
        analyze_expr(ctx, stmt.condition)
        if stmt.then_branch != nil:
            push_scope(ctx, false, false)
            analyze_stmt(ctx, stmt.then_branch)
            pop_scope(ctx)
        end
        if stmt.else_branch != nil:
            push_scope(ctx, false, false)
            analyze_stmt(ctx, stmt.else_branch)
            pop_scope(ctx)
        end
        return nil
    end

    # ----- while loop -----
    if stype == STMT_WHILE:
        analyze_expr(ctx, stmt.condition)
        push_scope(ctx, false, false)
        analyze_stmt(ctx, stmt.body)
        pop_scope(ctx)
        return nil
    end

    # ----- for loop -----
    if stype == STMT_FOR:
        analyze_expr(ctx, stmt.iterable)
        push_scope(ctx, false, false)
        # Declare loop variable as owned Copy (rebound each iteration)
        let loop_var = declare_var(ctx, stmt.variable.text, stmt.variable.line)
        if loop_var != nil:
            loop_var["state"] = OWN_OWNED
            loop_var["is_copy"] = true
        end
        analyze_stmt(ctx, stmt.body)
        pop_scope(ctx)
        return nil
    end

    # ----- block statement -----
    if stype == STMT_BLOCK:
        push_scope(ctx, false, false)
        analyze_stmt_list(ctx, stmt.statements)
        pop_scope(ctx)
        return nil
    end

    # ----- proc / async proc -----
    if stype == STMT_PROC or stype == STMT_ASYNC_PROC:
        let was_in_proc = ctx["in_proc"]
        let was_proc = ctx["current_proc"]
        ctx["in_proc"] = true
        ctx["current_proc"] = stmt.name.text

        let proc_safe = false
        push_scope(ctx, false, proc_safe)

        # Declare parameters as owned
        let pi = 0
        while pi < len(stmt.params):
            let param = stmt.params[pi]
            let pvar = declare_var(ctx, param.text, param.line)
            if pvar != nil:
                pvar["state"] = OWN_OWNED
            end
            pi = pi + 1
        end

        analyze_stmt(ctx, stmt.body)
        pop_scope(ctx)

        ctx["in_proc"] = was_in_proc
        ctx["current_proc"] = was_proc
        return nil
    end

    # ----- class -----
    if stype == STMT_CLASS:
        # Analyze methods
        let mi = 0
        while mi < len(stmt.methods):
            analyze_stmt(ctx, stmt.methods[mi])
            mi = mi + 1
        end
        return nil
    end

    # ----- return -----
    if stype == STMT_RETURN:
        if stmt.value != nil:
            analyze_expr(ctx, stmt.value)
        end
        return nil
    end

    # ----- try/catch/finally -----
    if stype == STMT_TRY:
        push_scope(ctx, false, false)
        analyze_stmt(ctx, stmt.try_block)
        pop_scope(ctx)
        if stmt.catch_blocks != nil:
            let ci = 0
            while ci < len(stmt.catch_blocks):
                push_scope(ctx, false, false)
                let cb = stmt.catch_blocks[ci]
                if cb.var_name != nil:
                    let cv = declare_var(ctx, cb.var_name.text, cb.var_name.line)
                    if cv != nil:
                        cv["state"] = OWN_OWNED
                    end
                end
                analyze_stmt(ctx, cb.body)
                pop_scope(ctx)
                ci = ci + 1
            end
        end
        if stmt.finally_block != nil:
            push_scope(ctx, false, false)
            analyze_stmt(ctx, stmt.finally_block)
            pop_scope(ctx)
        end
        return nil
    end

    # ----- raise -----
    if stype == STMT_RAISE:
        analyze_expr(ctx, stmt.exception)
        return nil
    end

    # ----- defer -----
    if stype == STMT_DEFER:
        analyze_stmt(ctx, stmt.statement)
        return nil
    end

    # ----- match -----
    if stype == STMT_MATCH:
        analyze_expr(ctx, stmt.value)
        if stmt.cases != nil:
            let ci = 0
            while ci < len(stmt.cases):
                let c = stmt.cases[ci]
                push_scope(ctx, false, false)
                if c.guard != nil:
                    analyze_expr(ctx, c.guard)
                end
                analyze_stmt(ctx, c.body)
                pop_scope(ctx)
                ci = ci + 1
            end
        end
        if stmt.default_case != nil:
            push_scope(ctx, false, false)
            analyze_stmt(ctx, stmt.default_case)
            pop_scope(ctx)
        end
        return nil
    end

    # ----- yield -----
    if stype == STMT_YIELD:
        if stmt.value != nil:
            analyze_expr(ctx, stmt.value)
        end
        return nil
    end

    # import, break, continue -- nothing to analyze
    return nil
end

# ============================================================================
# Statement List Walker
# ============================================================================

proc analyze_stmt_list(ctx, stmts):
    if stmts == nil:
        return nil
    end
    let i = 0
    while i < len(stmts):
        analyze_stmt(ctx, stmts[i])
        i = i + 1
    end
end

# ============================================================================
# Public Entry Point
# ============================================================================

proc analyze(program, mode, filename):
    # Run safety analysis on a parsed program (list of statements).
    # Returns a result dict with error_count, warning_count, diagnostics, ok.
    if mode == MODE_OFF:
        let r = {}
        r["ok"] = true
        r["error_count"] = 0
        r["warning_count"] = 0
        r["diagnostics"] = []
        return r
    end

    let ctx = make_context(mode, filename)
    analyze_stmt_list(ctx, program)

    # Print diagnostics if any were emitted
    if ctx["error_count"] > 0 or ctx["warning_count"] > 0:
        print_diagnostics(ctx)
    end

    if ctx["error_count"] > 0:
        print("safety: " + str(ctx["error_count"]) + " error(s), " + str(ctx["warning_count"]) + " warning(s)")
    end

    let result = {}
    result["ok"] = ctx["error_count"] == 0
    result["error_count"] = ctx["error_count"]
    result["warning_count"] = ctx["warning_count"]
    result["diagnostics"] = ctx["diagnostics"]
    return result
end
