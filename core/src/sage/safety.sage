gc_disable()
# safety.sage - Self-hosted safety analyzer for SageLang
# Ownership tracking, borrow checking, lifetime analysis.
# Mirrors the C implementation in src/c/safety.c.

from ast import EXPR_NUMBER, EXPR_STRING, EXPR_BOOL, EXPR_NIL
from ast import EXPR_BINARY, EXPR_VARIABLE, EXPR_CALL, EXPR_ARRAY
from ast import EXPR_INDEX, EXPR_DICT, EXPR_TUPLE, EXPR_SLICE
from ast import EXPR_GET, EXPR_SET, EXPR_INDEX_SET, EXPR_AWAIT
from ast import STMT_PRINT, STMT_EXPRESSION, STMT_LET, STMT_IF
from ast import STMT_BLOCK, STMT_WHILE, STMT_PROC, STMT_FOR
from ast import STMT_RETURN, STMT_BREAK, STMT_CONTINUE, STMT_CLASS
from ast import STMT_TRY, STMT_RAISE, STMT_YIELD, STMT_IMPORT
from ast import STMT_ASYNC_PROC, STMT_DEFER, STMT_MATCH

# Safety modes
let MODE_OFF = 0
let MODE_ANNOTATED = 1
let MODE_STRICT = 2

# Ownership states
let OWN_OWNED = 0
let OWN_MOVED = 1
let OWN_BORROWED = 2
let OWN_MUT_BORROW = 3
let OWN_PARTIAL = 4
let OWN_UNINITIALIZED = 5

# Diagnostic kinds
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

# Diagnostic levels
let LEVEL_ERROR = 0
let LEVEL_WARNING = 1

# Kind -> display string mapping
let DIAG_NAMES = {}
DIAG_NAMES[0] = "use-after-move"
DIAG_NAMES[1] = "double-move"
DIAG_NAMES[2] = "borrow-conflict"
DIAG_NAMES[3] = "borrow-conflict"
DIAG_NAMES[4] = "multiple-mut-borrow"
DIAG_NAMES[5] = "dangling-ref"
DIAG_NAMES[6] = "lifetime"
DIAG_NAMES[7] = "no-nil"
DIAG_NAMES[8] = "unwrap"
DIAG_NAMES[9] = "unsafe-in-safe"
DIAG_NAMES[10] = "not-send"
DIAG_NAMES[11] = "not-sync"
DIAG_NAMES[12] = "uninitialized"
DIAG_NAMES[13] = "partial-move"

# --- Context ---

proc make_context(mode, filename):
    let ctx = {}
    ctx["mode"] = mode
    ctx["scopes"] = []
    ctx["diagnostics"] = []
    ctx["error_count"] = 0
    ctx["warning_count"] = 0
    ctx["filename"] = filename
    ctx["in_proc"] = false
    ctx["current_proc"] = nil
    ctx["next_lifetime_id"] = 1
    let is_safe = 0
    if mode == MODE_STRICT:
        is_safe = 1
    end
    push_scope(ctx, false, is_safe)
    return ctx
end

# --- Scope management ---

proc push_scope(ctx, is_unsafe, is_safe):
    let pu = false
    let ps = false
    let pd = -1
    if len(ctx["scopes"]) > 0:
        let p = ctx["scopes"][len(ctx["scopes"]) - 1]
        pu = p["is_unsafe"]
        ps = p["is_safe"]
        pd = p["depth"]
    end
    let s = {}
    s["vars"] = {}
    s["borrows"] = []
    s["depth"] = pd + 1
    s["is_unsafe"] = is_unsafe or pu
    s["is_safe"] = is_safe or ps
    push(ctx["scopes"], s)
    return s
end

proc pop_scope(ctx):
    if len(ctx["scopes"]) == 0:
        return nil
    end
    let scope = ctx["scopes"][len(ctx["scopes"]) - 1]
    # Check for dangling references
    let bi = 0
    while bi < len(scope["borrows"]):
        let b = scope["borrows"][bi]
        let src = lookup_var(ctx, b["source"])
        if src != nil:
            if src["scope_depth"] >= scope["depth"]:
                emit_diag(ctx, LEVEL_ERROR, DIAG_DANGLING_REFERENCE, "reference outlives the data it borrows", "the borrowed value is destroyed at end of this scope", b["line"])
            end
        end
        bi = bi + 1
    end
    pop(ctx["scopes"])
    return scope
end

proc current_scope(ctx):
    if len(ctx["scopes"]) == 0:
        return nil
    end
    return ctx["scopes"][len(ctx["scopes"]) - 1]
end

# --- Variable tracking ---

proc declare_var(ctx, name, line):
    let scope = current_scope(ctx)
    if scope == nil:
        return nil
    end
    let v = {}
    v["name"] = name
    v["state"] = OWN_UNINITIALIZED
    v["is_copy"] = false
    v["is_send"] = true
    v["is_sync"] = false
    v["decl_line"] = line
    v["moved_line"] = 0
    v["moved_to"] = nil
    v["borrow_count"] = 0
    v["mut_borrow_count"] = 0
    v["scope_depth"] = scope["depth"]
    v["lifetime_id"] = ctx["next_lifetime_id"]
    ctx["next_lifetime_id"] = ctx["next_lifetime_id"] + 1
    scope["vars"][name] = v
    return v
end

proc lookup_var(ctx, name):
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
    if var == nil:
        return nil
    end
    var["state"] = OWN_MOVED
    var["moved_line"] = line
    var["moved_to"] = dest
end

proc mark_borrowed(ctx, var, borrower, line, is_mutable):
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

# --- Ownership checks ---

proc check_use(ctx, name, line):
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["state"] == OWN_MOVED:
        let dest = var["moved_to"]
        if dest == nil:
            dest = "?"
        end
        emit_diag(ctx, LEVEL_ERROR, DIAG_USE_AFTER_MOVE, "use of moved value '" + name + "' (moved to '" + dest + "' at line " + str(var["moved_line"]) + ")", "value was moved because it does not implement Copy", line)
        return false
    end
    if var["state"] == OWN_UNINITIALIZED:
        emit_diag(ctx, LEVEL_ERROR, DIAG_UNINITIALIZED_USE, "use of possibly uninitialized variable '" + name + "'", "assign a value before using this variable", line)
        return false
    end
    return true
end

proc check_move(ctx, name, line, dest):
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["is_copy"]:
        return true
    end
    if var["state"] == OWN_MOVED:
        emit_diag(ctx, LEVEL_ERROR, DIAG_DOUBLE_MOVE, "cannot move '" + name + "': already moved at line " + str(var["moved_line"]), "each value can only be moved once", line)
        return false
    end
    if var["borrow_count"] > 0 or var["mut_borrow_count"] > 0:
        emit_diag(ctx, LEVEL_ERROR, DIAG_BORROW_WHILE_MUT_BORROWED, "cannot move '" + name + "': it is currently borrowed", "wait until all borrows have ended before moving", line)
        return false
    end
    mark_moved(var, line, dest)
    return true
end

proc check_borrow(ctx, name, line, is_mutable):
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["state"] == OWN_MOVED:
        emit_diag(ctx, LEVEL_ERROR, DIAG_USE_AFTER_MOVE, "cannot borrow '" + name + "': value has been moved", "the value was moved and is no longer available", line)
        return false
    end
    if is_mutable:
        if var["borrow_count"] > 0:
            emit_diag(ctx, LEVEL_ERROR, DIAG_MUT_BORROW_WHILE_BORROWED, "cannot borrow '" + name + "' as mutable: already borrowed as immutable", "an immutable reference exists; cannot create mutable reference", line)
            return false
        end
        if var["mut_borrow_count"] > 0:
            emit_diag(ctx, LEVEL_ERROR, DIAG_MULTIPLE_MUT_BORROWS, "cannot borrow '" + name + "' as mutable: already mutably borrowed", "only one mutable reference is allowed at a time", line)
            return false
        end
    else:
        if var["mut_borrow_count"] > 0:
            emit_diag(ctx, LEVEL_ERROR, DIAG_BORROW_WHILE_MUT_BORROWED, "cannot borrow '" + name + "' as immutable: already mutably borrowed", "a mutable reference exists; cannot create immutable reference", line)
            return false
        end
    end
    return true
end

proc check_nil_usage(ctx, line):
    let scope = current_scope(ctx)
    if ctx["mode"] == MODE_STRICT or (scope != nil and scope["is_safe"]):
        emit_diag(ctx, LEVEL_ERROR, DIAG_NIL_IN_SAFE, "nil is not allowed in safe context; use Option[T] instead", "wrap the value in Some(value) or use None", line)
        return false
    end
    return true
end

proc check_send(ctx, name, line):
    let var = lookup_var(ctx, name)
    if var == nil:
        return true
    end
    if var["is_send"] == false:
        emit_diag(ctx, LEVEL_ERROR, DIAG_NOT_SEND, "'" + name + "' does not implement Send", "mark the type as Send or use a thread-safe wrapper", line)
        return false
    end
    return true
end

# --- Diagnostics ---

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
        let lv = "warning"
        if d["level"] == LEVEL_ERROR:
            lv = "error"
        end
        let ks = "unknown"
        if dict_has(DIAG_NAMES, d["kind"]):
            ks = DIAG_NAMES[d["kind"]]
        end
        print(lv + "[" + ks + "]: " + d["message"])
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

# --- Helpers ---

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

proc in_safe_scope(ctx):
    let s = current_scope(ctx)
    return s != nil and s["is_safe"]
end

# --- Expression analysis ---

proc analyze_expr(ctx, expr):
    if expr == nil:
        return nil
    end
    let et = expr.type

    if et == EXPR_VARIABLE:
        check_use(ctx, expr.name.text, expr.name.line)
        return nil
    end
    if et == EXPR_NIL:
        if in_safe_scope(ctx):
            check_nil_usage(ctx, 0)
        end
        return nil
    end
    if et == EXPR_BINARY:
        analyze_expr(ctx, expr.left)
        analyze_expr(ctx, expr.right)
        return nil
    end
    if et == EXPR_CALL:
        analyze_expr(ctx, expr.callee)
        let ai = 0
        while ai < len(expr.args):
            let arg = expr.args[ai]
            analyze_expr(ctx, arg)
            # Variable arguments may be moved in safe context
            if arg != nil and arg.type == EXPR_VARIABLE:
                let var = lookup_var(ctx, arg.name.text)
                if var != nil and var["is_copy"] == false and in_safe_scope(ctx):
                    check_move(ctx, arg.name.text, arg.name.line, "(function argument)")
                end
            end
            ai = ai + 1
        end
        # thread_spawn enforces Send trait
        if expr.callee != nil and expr.callee.type == EXPR_VARIABLE:
            let fn = expr.callee.name.text
            if fn == "thread_spawn" or fn == "async":
                let ti = 0
                while ti < len(expr.args):
                    let ta = expr.args[ti]
                    if ta != nil and ta.type == EXPR_VARIABLE:
                        check_send(ctx, ta.name.text, ta.name.line)
                    end
                    ti = ti + 1
                end
            end
        end
        return nil
    end
    if et == EXPR_INDEX:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.index)
        return nil
    end
    if et == EXPR_INDEX_SET:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.index)
        analyze_expr(ctx, expr.value)
        return nil
    end
    if et == EXPR_GET:
        analyze_expr(ctx, expr.object)
        return nil
    end
    if et == EXPR_SET:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.value)
        # Property assignment may move the value
        if expr.value != nil and expr.value.type == EXPR_VARIABLE:
            let var = lookup_var(ctx, expr.value.name.text)
            if var != nil and var["is_copy"] == false and in_safe_scope(ctx):
                check_move(ctx, expr.value.name.text, expr.value.name.line, "(property assignment)")
            end
        end
        return nil
    end
    if et == EXPR_ARRAY:
        let ei = 0
        while ei < len(expr.elements):
            analyze_expr(ctx, expr.elements[ei])
            ei = ei + 1
        end
        return nil
    end
    if et == EXPR_DICT:
        let di = 0
        while di < len(expr.values):
            analyze_expr(ctx, expr.values[di])
            di = di + 1
        end
        return nil
    end
    if et == EXPR_TUPLE:
        let ti = 0
        while ti < len(expr.elements):
            analyze_expr(ctx, expr.elements[ti])
            ti = ti + 1
        end
        return nil
    end
    if et == EXPR_SLICE:
        analyze_expr(ctx, expr.object)
        analyze_expr(ctx, expr.start)
        analyze_expr(ctx, expr.stop)
        return nil
    end
    if et == EXPR_AWAIT:
        analyze_expr(ctx, expr.expression)
        return nil
    end
    return nil
end

# --- Statement analysis ---

proc analyze_stmt(ctx, stmt):
    if stmt == nil:
        return nil
    end
    let st = stmt.type

    if st == STMT_LET:
        let name = stmt.name.text
        let line = stmt.name.line
        let var = declare_var(ctx, name, line)
        if stmt.initializer != nil:
            analyze_expr(ctx, stmt.initializer)
            var["state"] = OWN_OWNED
            let ie = stmt.initializer
            if ie.type == EXPR_VARIABLE and var["is_copy"] == false:
                if in_safe_scope(ctx):
                    check_move(ctx, ie.name.text, line, name)
                end
            end
            # Literals are implicitly Copy
            if ie.type == EXPR_NUMBER or ie.type == EXPR_BOOL or ie.type == EXPR_STRING:
                var["is_copy"] = true
            end
        end
        return nil
    end
    if st == STMT_EXPRESSION:
        analyze_expr(ctx, stmt.expression)
        return nil
    end
    if st == STMT_PRINT:
        analyze_expr(ctx, stmt.expression)
        return nil
    end
    if st == STMT_IF:
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
    if st == STMT_WHILE:
        analyze_expr(ctx, stmt.condition)
        push_scope(ctx, false, false)
        analyze_stmt(ctx, stmt.body)
        pop_scope(ctx)
        return nil
    end
    if st == STMT_FOR:
        analyze_expr(ctx, stmt.iterable)
        push_scope(ctx, false, false)
        let lv = declare_var(ctx, stmt.variable.text, stmt.variable.line)
        if lv != nil:
            lv["state"] = OWN_OWNED
            lv["is_copy"] = true
        end
        analyze_stmt(ctx, stmt.body)
        pop_scope(ctx)
        return nil
    end
    if st == STMT_BLOCK:
        push_scope(ctx, false, false)
        analyze_stmt_list(ctx, stmt.statements)
        pop_scope(ctx)
        return nil
    end
    if st == STMT_PROC or st == STMT_ASYNC_PROC:
        let was_in = ctx["in_proc"]
        let was_name = ctx["current_proc"]
        ctx["in_proc"] = true
        ctx["current_proc"] = stmt.name.text
        push_scope(ctx, false, false)
        # Declare parameters as owned
        let pi = 0
        while pi < len(stmt.params):
            let pv = declare_var(ctx, stmt.params[pi].text, stmt.params[pi].line)
            if pv != nil:
                pv["state"] = OWN_OWNED
            end
            pi = pi + 1
        end
        analyze_stmt(ctx, stmt.body)
        pop_scope(ctx)
        ctx["in_proc"] = was_in
        ctx["current_proc"] = was_name
        return nil
    end
    if st == STMT_CLASS:
        let mi = 0
        while mi < len(stmt.methods):
            analyze_stmt(ctx, stmt.methods[mi])
            mi = mi + 1
        end
        return nil
    end
    if st == STMT_RETURN:
        if stmt.value != nil:
            analyze_expr(ctx, stmt.value)
        end
        return nil
    end
    if st == STMT_TRY:
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
    if st == STMT_RAISE:
        analyze_expr(ctx, stmt.exception)
        return nil
    end
    if st == STMT_DEFER:
        analyze_stmt(ctx, stmt.statement)
        return nil
    end
    if st == STMT_MATCH:
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
    if st == STMT_YIELD:
        if stmt.value != nil:
            analyze_expr(ctx, stmt.value)
        end
        return nil
    end
    # STMT_IMPORT, STMT_BREAK, STMT_CONTINUE -- nothing to check
    return nil
end

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

# --- Public entry point ---

proc analyze(program, mode, filename):
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
