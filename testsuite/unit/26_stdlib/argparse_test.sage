gc_disable()
# EXPECT: true
# EXPECT: out.txt
# EXPECT: 1
# EXPECT: true

import std.argparse

let parser = argparse.create("myapp", "A test app")
argparse.add_flag(parser, "verbose", "v", "Enable verbose output")
argparse.add_option(parser, "output", "o", "Output file", "default.txt")

let result = argparse.parse(parser, ["--verbose", "-o", "out.txt", "input.sage"])
print argparse.get_flag(result, "verbose")
print argparse.get_option(result, "output")
print len(result["positionals"])

# Help text
let help = argparse.help_text(parser)
print len(help) > 0
