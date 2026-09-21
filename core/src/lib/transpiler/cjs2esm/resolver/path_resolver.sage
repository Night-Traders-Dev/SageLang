# -----------------------------------------
# resolver/path_resolver.sage - Path & Directory Resolution
# Resolves relative paths, extensionless imports, directory indexes
# -----------------------------------------

import os
from os import path

# --- Resolve relative path to JS file ---
proc resolve_relative_path(commandsPath, filePath):
    """Resolve a relative import path to an actual .js file."""
    
    # If already has .js extension, return as-is
    if filePath.endswith(".js"):
        return filePath
    
    # If it's a directory (no extension), append index.js
    if not filePath.endswith("/") and "." not in filePath.split("/")[-1]:
        # Check if directory exists with index.js
        index_path = path.join(commandsPath, filePath, "index.js")
        if os.path.exists(index_path):
            return filePath + "/index.js"
        # Check if directory exists
        if os.path.isdir(path.join(commandsPath, filePath)):
            return filePath + "/index.js"
    
    # Add .js extension
    return filePath + ".js"

# --- Resolve extensionless import ---
proc resolve_extensionless(relative_path, cwd):
    """Resolve ./utils or ./commands to actual file path."""
    
    # Try with .js extension first
    js_path = path.join(cwd, relative_path.replace("./", "")) + ".js"
    if os.path.exists(js_path):
        return relative_path + ".js"
    
    # Try as directory with index.js
    dir_path = path.join(cwd, relative_path.replace("./", ""))
    if os.path.isdir(dir_path):
        index_js = path.join(dir_path, "index.js")
        if os.path.exists(index_js):
            return relative_path + "/index.js"
    
    # Return as-is (resolution failed - caller's responsibility)
    return relative_path

# --- Resolve package main entry ---
proc resolve_package_main(package_json_path):
    """Resolve the main entry point from package.json."""
    
    package_data = read_package_json(package_json_path)
    if package_data == nil:
        return nil
    
    main_entry = package_data.get("main", nil)
    if main_entry:
        return main_entry
    
    # Default to index.js
    return "index.js"

# --- Resolve conditional exports ---
proc resolve_conditional_exports(package_json_path, import_type):
    """Resolve exports based on import type (import vs require)."""
    
    package_data = read_package_json(package_json_path)
    if package_data == nil:
        return nil
    
    exports = package_data.get("exports", nil)
    if exports == nil:
        # Fallback to "main"
        return resolve_package_main(package_json_path)
    
    # Check for import condition
    if import_type == "import":
        import_condition = exports.get(".import", nil)
        if import_condition:
            return import_condition
    
    # Check for require condition  
    require_condition = exports.get(".require", nil)
    if require_condition:
        return require_condition
    
    # Fallback to default export
    default_export = exports.get(".", nil)
    if default_export:
        return default_export
    
    return nil

# --- Main resolution entry point ---
proc resolve_import_path(relative_path, cwd, package_json_path = nil, import_type = "require"):
    """Resolve a CJS import path to its actual file location."""
    
    # First try conditional exports from package.json
    if package_json_path and os.path.exists(package_json_path):
        resolved = resolve_conditional_exports(package_json_path, import_type)
        if resolved:
            # Now resolve the relative path within the package
            return resolve_relative_path(cwd, resolved, relative_path)
    
    # Fallback to simple resolution
    return resolve_extensionless(relative_path, cwd)