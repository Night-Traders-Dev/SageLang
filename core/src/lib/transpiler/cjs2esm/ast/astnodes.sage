# -----------------------------------------
# ast.sage - CJS→ESM Transpiler AST Node Definitions
# -----------------------------------------

# --- Module unit: Program ---
class Program:
    proc init(body, source_type = "cjs", source_path = nil):
        self.body = body  # list of Stmt
        self.source_type = source_type  # "cjs" or "esm"
        self.source_path = source_path
        self.comments = []  # leading/trailing trivia
        self.error_count = 0

# --- Import Declaration (static ESM import) ---
class ImportDeclaration:
    proc init(specifiers, source, source_type = "static", import_attributes = nil):
        # specifiers: list of ImportSpecifier
        self.specifiers = specifiers  # e.g., [ImportDefaultSpecifier, ImportSpecifier]
        self.source = source  # e.g., "discord.js" or "./config.json"
        self.source_type = source_type  # "static", "dynamic", "json"
        self.import_attributes = import_attributes  # e.g., with { type: "json" }
        self.comments = []

class ImportSpecifier:
    proc init(imported, local, is_default = false):
        self.imported = imported  # name imported from module
        self.local = local  # local binding name
        self.is_default = is_default  # whether it's the default import

class ImportDefaultSpecifier:
    proc init(local):
        self.local = local  # name for default import binding

# --- Export Declaration ---
class ExportNamedDeclaration:
    proc init(exported_specifiers, source, is_default = false):
        self.exported_specifiers = exported_specifiers  # list of ExportSpecifier
        self.source = source  # module source for re-export, nil for "default"
        self.is_default = is_default  # whether "export default"
        self.comments = []

class ExportSpecifier:
    proc init(exported, local):
        self.exported = exported  # name exported
        self.local = local  # local name

class ExportDefaultDeclaration:
    proc init(expression):
        self.expression = expression  # the default export expression/object

# --- Require Call Expression ---
class RequireCall:
    proc init(argument, is_dynamic = false, arguments_list = nil):
        self.argument = argument  # the module name string or expression
        self.is_dynamic = is_dynamic  # whether it's dynamic require()
        self.arguments_list = arguments_list  # for dynamic require with args

# --- Module References ---
class ModuleReference:
    proc init(name, is_cjs_module = true):
        self.name = name  # "module", "exports", "require"
        self.is_cjs_module = is_cjs_module

# --- Variable / Let Statement ---
class LetStatement:
    proc init(name, initializer, kind = "var"):
        self.name = name  # variable name
        self.initializer = initializer  # initializer expression/nil
        self.kind = kind  # "var", "let", "const"

# --- Assignment Expression ---
class AssignmentExpression:
    proc init(left, operator, right):
        self.left = left
        self.operator = operator  # "=", "+=", etc.
        self.right = right

# --- Call Expression (for require(), module.exports = ..., etc.) ---
class CallExpression:
    proc init(callee, args, arg_count = 0):
        self.callee = callee  # Identifier or MemberExpression
        self.args = args  # list of arguments
        self.arg_count = arg_count

# --- Member Expression (e.g., module.exports, require.cache) ---
class MemberExpression:
    proc init(object, property, computed = false):
        self.object = object  # Identifier or another MemberExpression
        self.property = property  # Identifier
        self.computed = computed  # whether computed property access

# --- Literal Expression ---
class Literal:
    proc init(value, kind = "string"):
        self.value = value
        self.kind = kind  # "string", "number", "bool", "nil"

# --- Identifier ---
class Identifier:
    proc init(name):
        self.name = name

# --- Conditional Expression (ternary) ---
class ConditionalExpression:
    proc init(test, consequent, alternate):
        self.test = test
        self.consequent = consequent
        self.alternate = alternate

# --- Block Statement ---
class BlockStatement:
    proc init(statements):
        self.statements = statements

# --- If Statement ---
class IfStatement:
    proc init(condition, then_branch, else_branch = nil):
        self.condition = condition
        self.then_branch = then_branch
        self.else_branch = else_branch

# --- For Statement ---
class ForStatement:
    proc init(variable, iterable, body):
        self.variable = variable
        self.iterable = iterable
        self.body = body

# --- Return Statement ---
class ReturnStatement:
    proc init(value):
        self.value = value

# --- Expression Statement ---
class ExpressionStatement:
    proc init(expression):
        self.expression = expression

# --- Variable Declaration (const/let/var with possible initializer) ---
class VariableDeclaration:
    proc init(declarations, kind):
        self.declarations = declarations  # list of VariableDeclarator
        self.kind = kind  # "var", "let", "const"

class VariableDeclarator:
    proc init(id, init):
        self.id = id  # Identifier
        self.init = init  # Expression or nil

# --- Try-Catch-Finally ---
class TryStatement:
    proc init(block, handler, finalizer):
        self.block = block  # BlockStatement
        self.handler = handler  # CatchClause or nil
        self.finalizer = finalizer  # BlockStatement or nil

class CatchClause:
    proc init(exception_var, handler_body):
        self.exception_var = exception_var  # Identifier
        self.handler_body = handler_body  # BlockStatement

# --- Throw Statement ---
class ThrowStatement:
    proc init(argument):
        self.argument = argument

# --- Import Call (for dynamic import()) ---
class ImportCall:
    proc init(arguments_list = nil):
        self.arguments_list = arguments_list

# --- Program Transform State ---
class TransformState:
    proc init():
        self.module_classifications = {}  # module_name -> "PURE_CJS" | "DYNAMIC" | "ESM"
        self.cjs_usage = {}  # tracks require/exports/module usage per file
        self.diagnostics = []  # list of (code, message, severity)
        self.target = "node20"  # default target
        self.mode = "compat"  # default mode
        self.seen_runtime_globals = set()  # __dirname, __filename, etc.