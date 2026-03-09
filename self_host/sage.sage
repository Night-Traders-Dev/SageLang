gc_disable()
# -----------------------------------------
# sage.sage - Bootstrap entry point for self-hosted SageLang interpreter
# Phase 13: Self-hosting
# -----------------------------------------

import io
import sys
from parser import parse_source
from interpreter import new_interpreter, exec_program

proc main():
    let argv = sys.args()
    # argv[0] = host sage, argv[1] = sage.sage, argv[2] = target file
    if len(argv) < 3:
        print "Usage: sage sage.sage <file.sage>"
        return
    let filename = argv[2]
    let source = io.readfile(filename)
    if source == nil:
        print "Error: Could not read file '" + filename + "'"
        return
    let genv = new_interpreter()
    let stmts = parse_source(source)
    exec_program(genv, stmts)

main()
