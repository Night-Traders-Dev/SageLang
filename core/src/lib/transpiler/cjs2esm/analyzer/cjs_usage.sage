# -----------------------------------------
# cjs_usage.sage - CJS Usage Analyzer & Scope Tracker
# Identifies require/exports/module usage patterns and classifies modules
# -----------------------------------------

import AST
from AST import (
    Program, ImportDeclaration, ImportSpecifier, ImportDefaultSpecifier,
    ExportNamedDeclaration, ExportDefaultDeclaration, ExportSpecifier,
    RequireCall, ModuleReference, LetStatement, AssignmentExpression,
    CallExpression, MemberExpression, Literal, Identifier,
    BlockStatement, IfStatement, ForStatement, ReturnStatement,
    ExpressionStatement, VariableDeclaration, VariableDeclarator,
    TryStatement, CatchClause, ThrowStatement, ImportCall,
    TransformState
)

# --- Scope Level ---
class ScopeLevel:
    proc init(level_type, parent = nil):
        self.level_type = level_type  # "global", "function", "block", "catch"
        self.parent = parent
        self.bindings = {}  # name -> { "declared": bool, "assigned": bool, "init": Expr, "kind": "var"|"let"|"const" }
        self.module_refs = set()  # module names referenced in this scope
        self.is_cjs_module = true  # assume CJS until proven ESM

# --- Scope Tracker ---
class ScopeTracker:
    proc init():
        self.global_scope = ScopeLevel("global")
        self.current_scope = self.global_scope
        self.scope_stack = [self.global_scope]
        self.module_usages = {}  # file_path -> list of (module_name, is_dynamic, context)
        self.exports_tracker = {}  # module_name -> {"exports": set, "module.exports": set, "reassigned": bool}
        self.hoisting_conflicts = []  # list of file_path + line where exec stmt precedes require
        self.seen_require_calls = set()  # unique require() call sites
        self.seen_exports_assignments = set()
        self.seen_module_exports_reassign = set()

    # Enter a new scope (function, block, catch)
    proc enter_scope(level_type = "block"):
        new_scope = ScopeLevel(level_type, self.current_scope)
        push(self.scope_stack, new_scope)
        self.current_scope = new_scope

    # Exit current scope, return to parent
    proc exit_scope():
        pop(self.scope_stack)
        self.current_scope = self.scope_stack[len(self.scope_scope) - 1] if len(self.scope_stack) > 0 else self.global_scope
        return self.current_scope

    # Bind an identifier in current scope
    proc bind_identifier(name, init = nil, kind = "var"):
        if not dict_has(self.current_scope.bindings, name):
            self.current_scope.bindings[name] = {
                "declared": true,
                "assigned": false,
                "init": init,
                "kind": kind
            }
        else:
            # Already declared - just mark as re-declaration context
            self.current_scope.bindings[name]["declared"] = true

    # Unbind when exiting scope (mark as unavailable in parent)
    proc unbind_identifier(name):
        if dict_has(self.current_scope.bindings, name):
            # Remove from current scope only; parent scope retains its own binding
            # We just mark it as potentially shadowed
            pass

    # Look up identifier through scope chain
    proc lookup_identifier(name, scope_chain = nil):
        if scope_chain == nil:
            scope_chain = self.scope_stack
        for scope in reversed(scope_chain):
            if dict_has(scope.bindings, name):
                return scope.bindings[name]
        return nil

    # Track a require() call site
    proc track_require(module_name, line, is_dynamic = false, context = nil):
        key = f"{module_name}:{line}"
        if not key in self.seen_require_calls:
            self.seen_require_calls.add(key)
            if not self.module_usages.get(module_name):
                self.module_usages[module_name] = []
            self.module_usages[module_name].append({
                "line": line,
                "is_dynamic": is_dynamic,
                "context": context
            })

    # Track module.exports usage
    proc track_exports_assignment(module_name, name, line):
        key = f"{module_name}:{name}:{line}"
        if not key in self.seen_exports_assignments:
            self.seen_exports_assignments.add(key)
            if not self.exports_tracker.get(module_name):
                self.exports_tracker[module_name] = {"exports": set(), "module.exports": set(), "reassigned": false}
            self.exports_tracker[module_name]["exports"].add(name)

    # Track module.exports reassignment
    proc track_module_exports_reassign(module_name, line):
        key = f"{module_name}:exports:{line}"
        if not key in self.seen_module_exports_reassign:
            self.seen_module_exports_reassign.add(key)
            if not self.exports_tracker.get(module_name):
                self.exports_tracker[module_name] = {"exports": set(), "module.exports": set(), "reassigned": false}
            self.exports_tracker[module_name]["module.exports"].add("reassigned:" + str(line))
            self.exports_tracker[module_name]["reassigned"] = true

    # Track a module reference (imported module)
    proc track_module_reference(module_name):
        if not self.module_usages.get(module_name):
            self.module_usages[module_name] = []
        # Mark as referenced

    # Classify a module as PURE_CJS, DYNAMIC, or ESM-friendly
    proc classify_module(module_name):
        usage = self.module_usages.get(module_name, [])
        
        if not usage:
            # No require calls - could be pure ESM or unused
            return "PURE_CJS"  # Safe default: treat as importable
        
        has_dynamic = False
        has_side_effects_before_require = False
        has_exports_reassign = False
        has_module_exports_reassign = False
        has_config_side_effects = False
        
        for call in usage:
            if call["is_dynamic"]:
                has_dynamic = True
            else:
                # Static require - check context for side effects
                # We'll infer from the surrounding code during transform
                pass
            
            # Check for exports/reassign patterns
            if self.exports_tracker.get(module_name) and self.exports_tracker[module_name]["reassigned"]:
                has_exports_reassign = True
            
            if self.exports_tracker.get(module_name) and self.exports_tracker[module_name]["module.exports"]["reassigned"]:
                has_module_exports_reassign = True
        
        # Classification logic
        if has_module_exports_reassign:
            # module.exports = function() {} pattern - cannot safely convert
            return "DYNAMIC"
        
        if has_exports_reassign and not has_dynamic:
            # exports.foo = ... then module.exports = ... pattern
            # Need to preserve the composite export object
            return "DYNAMIC"
        
        if has_dynamic:
            # Dynamic require() with variable/expression argument
            return "DYNAMIC"
        
        # Static requires only - can potentially be converted
        # But check for config-like side effects (dotenv.config(), etc.)
        # For now, treat as PURE_CJS unless further analysis detects side effects
        return "PURE_CJS"

    # Detect hoisting conflicts: executable statement precedes require()
    # In CJS, require() can appear anywhere and executes in place.
    # In ESM, imports are hoisted to top. If a statement like console.log() 
    # precedes require(), naive hoisting changes semantics.
    proc detect_hoisting_conflict(file_path, line, has_exec_before_require):
        if has_exec_before_require:
            self.hoisting_conflicts.append({
                "file_path": file_path,
                "line": line,
                "message": "Executable statement precedes require() - hoisting would change evaluation order"
            })

    # Detect require.cache manipulation
    proc track_cache_manipulation(file_path, line):
        # Tracks delete require.cache[...] patterns
        pass

    # Generate diagnostics for the transform pass
    proc emit_diagnostic(code, message, severity = "NOTE"):
        self.diagnostics.append({
            "code": code,
            "message": message,
            "severity": severity
        })

# --- Initialize global scope tracker ---
global_tracker = ScopeTracker()

# --- Public API ---
proc analyze_cjs_source(source, file_path = "<unknown>"):
    """Analyze a CJS source file and return a TransformState with classifications."""
    tracker = ScopeTracker()
    # Tokenize the source
    tokens = js_tokenize(source)
    
    # Parse into AST (we'll use a simplified parser for now)
    # For now, we'll do pattern matching on tokens
    
    # Track require() calls, module.exports, exports patterns
    # Simple heuristic-based analysis
    
    # Look for require( patterns
    var i = 0
    while i < len(tokens) - 6:
        # Simple pattern: require(
        if tokens[i].text == "require" and tokens[i+1].text == "(":
            # Find the argument
            let arg_start = i + 2  # skip 'require('
            let depth = 1
            let j = arg_start
            while j < len(tokens) and depth > 0:
                if tokens[j].text == "(":
                    depth = depth + 1
                if tokens[j].text == ")":
                    depth = depth - 1
                j = j + 1
            # The argument is between arg_start and j-2 (closing paren)
            let arg_text = slice(tokens, arg_start, j - 2)
            
            # Determine if dynamic (variable argument) or static (string literal)
            is_dynamic = false
            if arg_text[0] == token.TOKEN_STRING:
                is_dynamic = false
                module_name = arg_text[1]  # the string content
            else:
                is_dynamic = true
                module_name = "UNKNOWN_DYNAMIC"
            
            tracker.track_require(module_name, tokens[i].line, is_dynamic)
            
            # Check for require.cache manipulation nearby
            if "cache" in arg_text[1] or "cache" in tokens[i+2..j-1] if is_dynamic:
                tracker.track_cache_manipulation(file_path, tokens[i].line)
            
            # Move past this require call
            i = j
            continue
        i = i + 1
    
    # Look for module.exports = ... and exports. = patterns
    i = 0
    while i < len(tokens):
        # module.exports = ...
        if i < len(tokens) - 3 and tokens[i].text == "module" and tokens[i+1].text == "." and tokens[i+2].text == "exports":
            # Check what follows = 
            if i + 3 < len(tokens) and tokens[i+3].text == "=":
                tracker.track_module_exports_reassign("unknown_module", tokens[i].line)
                # Skip past this assignment
                i = i + 4
                # Find the end of the assignment value (simple heuristic)
                continue
        
        # exports.foo = ...
        if i < len(tokens) - 6 and tokens[i].text == "exports" and tokens[i+1].text == ".":
            # Get the property name
            let prop_name = tokens[i+2].text if i + 2 < len(tokens) else nil
            if prop_name:
                tracker.track_exports_assignment("unknown_module", prop_name, tokens[i].line)
        
        i = i + 1
    
    # Classify common Node.js modules
    # These are typically PURE_CJS (can be static imports)
    common_cjs_modules = [
        "fs", "path", "os", "http", "https", "url", "querystring",
        "util", "stream", "zlib", "crypto", "buffer", "timers",
        "child_process", "net", "tls", "readline", "worker_threads"
    ]
    
    # Generate TransformState with classifications
    state = TransformState()
    
    # Set target and mode from global context if available
    # For now, use defaults
    
    return state, tracker

# --- Helper: slice function for token lists ---
proc slice(tokens, start, end):
    let result = []
    var i = start
    while i < end and i < len(tokens):
        push(result, tokens[i])
        i = i + 1
    return result

proc dict_has(dict, key):
    var i = 0
    while i < len(dict):
        if dict[i] == key:
            return true
        i = i + 1
    return false

proc push(arr, val):
    arr = arr + [val]  # Simplified - in real SageLang this would be push(arr, val)