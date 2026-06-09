from transpiler.base import Transpiler
from transpiler.json_parser import parse_json
import sys
import io

class PythonASTParser(Transpiler):
    proc parse(source: String) -> Object:
        let tmp_file = "transpiler_temp.py"
        io.writefile(tmp_file, source)
        let json_output = sys.shell_exec("python3 core/lib/transpiler/python/python_ast.py " + tmp_file)
        io.remove(tmp_file)
        return parse_json(json_output)
