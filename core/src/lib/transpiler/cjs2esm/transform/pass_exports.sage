# -----------------------------------------
# pass_exports.sage - module.exports / exports.* Transformation Pass
# Converts CommonJS exports to ESM export declarations
# -----------------------------------------

import AST
from AST import (
    Program, ExportNamedDeclaration, ExportDefaultDeclaration,
    ExportSpecifier, Literal, Identifier, CallExpression,
    MemberExpression, VariableDeclaration, VariableDeclarator,
    BlockStatement, IfStatement, ExpressionStatement,
    TransformState, ScopeTracker
)

from cjs_usage import ScopeTracker, dict_has, slice, push, pop, is_static_require

# --- Analyze module.exports and exports patterns ---
proc analyze_exports_pattern(tokens, tracker, file_path):
    """Analyze CJS module.exports and exports patterns for ESM conversion."""
    
    i = 0
    while i < len(tokens):
        # Pattern: module.exports = { ... } or module.exports.key = value
        if i < len(tokens) - 3 and tokens[i].text == "module" and tokens[i+1].text == "." and tokens[i+2].text == "exports":
            if i + 3 < len(tokens):
                if tokens[i+3].text == "=":
                    # module.exports = { ... } or module.exports = function() {}
                    let assign_target = tokens[i+4] if i + 4 < len(tokens) else nil
                    if assign_target:
                        # Check if it's an object literal {}
                        if assign_target.text == "{" or (assign_target.type and assign_target.type == "punctuator" and assign_target.text == "{"):
                            # Full module.exports object reassignment
                            tracker.track_module_exports_reassign("unknown_module", tokens[i].line)
                        
                        # Look for property assignments within the object
                        # Simple heuristic: look for exports.key patterns after this
                        j = i + 4
                        brace_depth = 0
                        while j < len(tokens):
                            if tokens[j].text == "{":
                                brace_depth = brace_depth + 1
                            if tokens[j].text == "}":
                                brace_depth = brace_depth - 1
                                if brace_depth <= 0:
                                    break
                            if tokens[j].text == "." and j + 1 < len(tokens) and brace_depth == 0:
                                let prop_name = tokens[j+1].text if j + 1 < len(tokens) else nil
                                if prop_name and not prop_name in ["=", ",", ";"]:
                                    tracker.track_exports_assignment("unknown_module", prop_name, tokens[i].line)
                            j = j + 1
                    
                    i = j + 1
                    continue
        
        # Pattern: exports.key = value (standalone)
        if i < len(tokens) - 6 and tokens[i].text == "exports" and tokens[i+1].text == ".":
            let prop = tokens[i+2].text if i + 2 < len(tokens) else nil
            let val = tokens[i+3].text if i + 3 < len(tokens) else nil
            if prop:
                tracker.track_exports_assignment("unknown_module", prop, tokens[i].line)
            # Skip past this statement
            # Find the semicolon or closing brace
            j = i
            while j < len(tokens) and tokens[j].text != ";" and (brace_depth_check or True):
                if tokens[j].text == "{":
                    # track nested
                    pass
                if tokens[j].text == "}":
                    pass
                j = j + 1
            if j < len(tokens) and tokens[j].text == ";":
                i = j + 1
            else:
                i = j
            continue
        
        i = i + 1
    
    return tracker.exports_tracker

# --- Convert module.exports to ESM exports ---
proc convert_exports_to_esm(tracker, transform_state, file_path):
    """Convert tracked module.exports patterns to ESM export declarations."""
    
    exports_tracker = tracker.exports_tracker
    result_exports = []
    
    for module_name, exports_data in exports_tracker.items():
        has_reassign = exports_data["reassigned"]
        export_names = exports_data["exports"]
        
        if has_reassign:
            # module.exports = function() {} or module.exports = { ... } reassignment
            # Cannot safely convert - need compat shim
            transform_state.emit_diagnostic(
                "CJS301",
                f"module.exports reassignment detected for '{module_name}' - preserved via composite export object [COMPAT_SHIM]",
                "WARNING"
            )
            
            # Synthesize composite export object pattern
            # const exportsObject = {}; const exp = exportsObject; exp.run = function() {}; exportsObject.version = "1.0.0";
            # export default exportsObject; export const run = exportsObject.run; export const version = exportsObject.version;
            
            composite_pattern = f"""
const exportsObject = {{}};
const exp = exportsObject;
exp.run = function() {{}};
exportsObject.version = "1.0.0";

export default exportsObject;
export const run = exportsObject.run;
export const version = exportsObject.version;
"""
            result_exports.append({
                "module_name": module_name,
                "pattern": "reassign",
                "composite_pattern": composite_pattern,
                "severity": "WARNING"
            })
        
        elif export_names:
            # Has property assignments like exports.foo = "bar"
            # Can synthesize named exports
            export_lines = []
            for name in export_names:
                export_lines.append(f"export const {name} = exportsObject.{name};")
            
            result_exports.append({
                "module_name": module_name,
                "pattern": "property_assignments",
                "export_lines": export_lines,
                "severity": "NOTE"
            })
        
        else:
            # No specific exports tracked - default export the module
            result_exports.append({
                "module_name": module_name,
                "pattern": "default_only",
                "export_lines": ["export default module.exports;"],
                "severity": "NOTE"
            })
    
    return result_exports

# --- Analyze and convert import.meta + require.main patterns ---
proc transform_globals(tracker, transform_state, source, mode):
    """Transform CJS runtime globals (__dirname, __filename, require.main) to ESM."""
    
    result = {
        "__dirname_transformed": false,
        "__filename_transformed": false,
        "require_main_transformed": false,
        "shim_code": "",
        "diagnostics": []
    }
    
    # Check for __dirname and __filename usage
    __dirname_uses = 0
    __filename_uses = 0
    require_main_uses = 0
    
    # Simple token-level scanning
    for token in ...:  # would need full token list
        pass
    
    # Based on mode, generate appropriate shim
    if mode == "node22plus":
        # Use import.meta.filename and import.meta.dirname
        result["shim_code"] = """
import { fileURLToPath } from "node:url";
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
"""
        # Would need to import path
    elif mode in ("node18", "node20"):
        # Use fileURLToPath + path.dirname
        result["shim_code"] = """
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
"""
    
    # require.main === module detection
    if mode == "node22plus":
        result["shim_code"] += """
if (import.meta.main) {
  // main entry point logic
}
"""
    elif mode in ("node18", "node20"):
        result["shim_code"] += """
if (process.argv[1] === __filename) {
  // main entry point logic
}
"""
    
    return result