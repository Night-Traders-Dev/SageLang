import io
import sys
import parser
import codegen

# Differential harness: emit rv64 assembly from the Sage codegen for one program
# and write it where the caller can build and run it.
#
# parse_source_file takes the file's contents, not its path, so read it here.
#
# The caller diffs this against the C backend's output for the same source, so
# the two native emitters are each compared against an independent reference
# rather than against each other.
let argv = sys.args()
let path = argv[2]
let out_path = argv[3]

let src = io.readfile(path)
let stmts = parser.parse_source_file(src, path)
io.writefile(out_path, codegen.compile_to_asm(stmts, codegen.TARGET_RV64))
print("wrote", out_path)
