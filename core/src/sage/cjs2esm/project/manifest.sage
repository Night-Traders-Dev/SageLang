# -----------------------------------------
# manifest.sage - package.json handling for cjs2esm
# Updates "type": "module" and handles ESM migration
# -----------------------------------------

import json
import os

proc read_package_json(file_path):
    """Read and parse package.json file."""
    try:
        with open(file_path, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return nil
    except json.JSONDecodeError as e:
        print "Error parsing package.json: " + str(e)
        return nil

proc write_package_json(file_path, data):
    """Write package.json file with proper formatting."""
    with open(file_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

proc update_type_to_module(file_path):
    """Update or inject "type": "module" in package.json."""
    data = read_package_json(file_path)
    if data == nil:
        # Create new package.json with type: module
        data = {"type": "module", "name": "migrated-project", "version": "1.0.0"}
        write_package_json(file_path, data)
        return true
    
    if not dict_has(data, "type"):
        data["type"] = "module"
        write_package_json(file_path, data)
        return true
    
    if data["type"] != "module":
        data["type"] = "module"
        write_package_json(file_path, data)
        return true
    
    return false  # already type: module

# --- Generate migration report ---
proc generate_migration_report(tracker, transform_state, project_path):
    """Generate a JSON/Markdown migration report."""
    
    report = {
        "source_project": project_path,
        "transformations": {
            "static_imports_converted": len([k for k in tracker.module_usages.keys() 
                                              if tracker.classify_module(k) == "PURE_CJS"]),
            "dynamic_requires_preserved": len([k for k in tracker.module_usages.keys() 
                                                if tracker.classify_module(k) == "DYNAMIC"]),
            "hoisting_conflicts": len(transform_state.hoisting_conflicts),
            "module_classifications": {k: tracker.classify_module(k) for k in tracker.module_usages.keys()}
        },
        "diagnostics": [{"code": d["code"], "message": d["message"]} for d in transform_state.diagnostics],
        "recommendations": []
    }
    
    # Add recommendations based on findings
    for module_name, classification in report["transformations"]["module_classifications"].items():
        if classification == "DYNAMIC":
            report["recommendations"].append(
                f"Module '{module_name}' has dynamic/Complex CJS patterns - manual review recommended"
            )
    
    if report["transformations"]["hoisting_conflicts"] > 0:
        report["recommendations"].append(
            f"{report['transformations']['hoisting_conflicts']} hoisting conflict(s) detected - review evaluation order"
        )
    
    return report