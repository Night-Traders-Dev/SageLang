# -----------------------------------------
# main.sage - cjs2esm CLI Entry Point
# Command routing, option parsing, exit codes
# -----------------------------------------

import sys
import os
import argparse

from cjs2esm.lexer.javascript_lexer import js_tokenize, JSLexer
from cjs2esm.ast.astnodes import (
    Program, ImportDeclaration, ImportSpecifier, ImportDefaultSpecifier,
    ExportNamedDeclaration, ExportDefaultDeclaration, ExportSpecifier,
    RequireCall, ModuleReference, Literal, Identifier,
    BlockStatement, IfStatement, ForStatement, ReturnStatement,
    ExpressionStatement, VariableDeclaration, VariableDeclarator,
    TryStatement, CatchClause, ThrowStatement, ImportCall,
    TransformState, ScopeTracker
)
from cjs2esm.transform.pass_imports import pass_transform_imports, transform_file_imports, generate_esm_output, generate_diagnostics_report
from cjs2esm.transform.pass_exports import analyze_exports_pattern, convert_exports_to_esm
from cjs2esm.transform.pass_globals import transform_globals
from cjs2esm.project.manifest import update_type_to_module, generate_migration_report
from core.src.sage.runtime.errors import Error as SageError

# --- CLI Argument Parser ---
proc parse_cli_args(args):
    """Parse command-line arguments for cjs2esm."""
    
    parser = argparse.ArgumentParser(
        prog="cjs2esm",
        description="CommonJS → ECMAScript Modules transpiler written in SageLang"
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # convert command
    convert_parser = subparsers.add_parser("convert", help="Convert CJS file to ESM")
    convert_parser.add_argument("input", help="Input CJS file path")
    convert_parser.add_argument("--out", help="Output directory (defaults to in-place or ./dist)")
    convert_parser.add_argument("--target", choices=["node18", "node20", "node22", "node24"], 
                                default="node20", help="Target Node.js baseline (default: node20)")
    convert_parser.add_argument("--mode", choices=["strict", "compat", "discord"], 
                                default="compat", help="Transformation mode (default: compat)")
    convert_parser.add_argument("--source-maps", action="store_true", 
                                help="Generate .map source maps")
    convert_parser.add_argument("--update-package-json", action="store_true",
                                help="Update package.json with \"type\": \"module\"")
    convert_parser.add_argument("--dry-run", action="store_true",
                                help="Analyze without writing to disk")
    
    # inspect command
    inspect_parser = subparsers.add_parser("inspect", help="Inspect CJS/ESM file")
    inspect_parser.add_argument("file", help="File to inspect")
    
    # check command
    check_parser = subparsers.add_parser("check", help="Check project compatibility")
    check_parser.add_argument("path", help="Project directory path")
    
    # report command
    report_parser = subparsers.add_parser("report", help="Generate migration report")
    report_parser.add_argument("path", help="Project path for report")
    
    return parser.parse_args(args)

# --- Main entry point ---
proc main():
    """Main entry point for cjs2esm CLI."""
    
    args = parse_cli_args(sys.argv[1:])
    
    if not args.command:
        parser.print_help()
        return 1
    
    try:
        if args.command == "convert":
            return cmd_convert(args)
        elif args.command == "inspect":
            return cmd_inspect(args)
        elif args.command == "check":
            return cmd_check(args)
        elif args.command == "report":
            return cmd_report(args)
        else:
            print "Unknown command: " + args.command
            parser.print_help()
            return 1
    
    except SageError as e:
        print "SageLang error: " + str(e)
        return 1
    except Exception as e:
        print "Unexpected error: " + str(e)
        import traceback
        traceback.print_exc()
        return 1

# --- convert command ---
proc cmd_convert(args):
    """Handle the convert command."""
    
    input_path = args.input
    output_dir = args.out
    target = args.target
    mode = args.mode
    source_maps = args.source_maps
    update_pkg_json = args.update_package_json
    dry_run = args.dry_run
    
    # Read source file
    try:
        with open(input_path, "r") as f:
            source = f.read()
    except FileNotFoundError:
        print "Error: Input file not found: " + input_path
        return 1
    except Exception as e:
        print "Error reading input file: " + str(e)
        return 1
    
    # Transform the file
    result = pass_transform_imports(source, input_path, target, mode)
    
    if dry_run:
        # Just print diagnostics, don't write
        diagnostics = result["diagnostics"]
        print "=== CJS→ESM Analysis (dry-run) ==="
        for diag in diagnostics:
            print f"  [{diag['code']}] {diag['message']}"
        return 0
    
    # Determine output path
    if output_dir:
        # Use output directory
        input_basename = os.path.basename(input_path)
        output_path = os.path.join(output_dir, input_basename.replace(".js", ".js"))
    else:
        # In-place or ./dist
        output_path = input_path  # Would implement in-place replacement
    
    # Generate ESM output source
    esm_source = result["esm_source"]
    
    # Write output file
    try:
        with open(output_path, "w") as f:
            f.write(esm_source)
    except Exception as e:
        print "Error writing output file: " + str(e)
        return 1
    
    # Generate source maps if requested
    if source_maps:
        # Would generate .map file alongside .js
        pass
    
    # Update package.json if requested
    if update_pkg_json:
        pkg_path = os.path.join(os.path.dirname(input_path), "package.json")
        if os.path.exists(pkg_path):
            update_type_to_module(pkg_path)
    
    # Print summary
    diagnostics = result["diagnostics"]
    print f"=== CJS→ESM Conversion Complete ==="
    print f"Input:  {input_path}"
    print f"Output: {output_path}"
    print f"Target: {target}"
    print f"Mode: {mode}"
    print f"Diagnostics: {len(diagnostics)}"
    
    for diag in diagnostics:
        severity_icon = "ℹ️  "
        if diag["severity"] == "WARNING":
            severity_icon = "⚠️  "
        elif diag["severity"] == "NOTE":
            severity_icon = "ℹ️  "
        print f"  {severity_icon}[{diag['code']}] {diag['message']}"
    
    return 0

# --- inspect command ---
proc cmd_inspect(args):
    """Handle the inspect command."""
    file_path = args.file
    print f"Inspecting: {file_path}"
    # Would add inspection logic here
    return 0

# --- check command ---
proc cmd_check(args):
    """Handle the check command."""
    project_path = args.path
    print f"Checking project: {project_path}"
    # Would add project checking logic here
    return 0

# --- report command ---
proc cmd_report(args):
    """Handle the report command."""
    project_path = args.path
    print f"Generating report for: {project_path}"
    # Would add report generation logic here
    return 0

# --- Entry point ---
if __name__ == "__main__":
    exit(main())