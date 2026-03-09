gc_disable()
# -----------------------------------------
# sage.sage - Bootstrap entry point for self-hosted SageLang interpreter
# Phase 13: Self-hosting
# -----------------------------------------

import io
import sys
from parser import parse_source
from interpreter import Interpreter

proc main():
    let argv = sys.args()
    if len(argv) < 2:
        print "Usage: sage <file.sage>"
        return
    let filename = argv[1]
    let source = io.readfile(filename)
    if source == nil:
        print "Error: Could not read file '" + filename + "'"
        return
    let interp = Interpreter()
    let stmts = parse_source(source)
    interp.exec_program(stmts)

main()
