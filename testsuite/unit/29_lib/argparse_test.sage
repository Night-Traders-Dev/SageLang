# EXPECT: true
# EXPECT: false
# EXPECT: out.txt
# EXPECT: config.json
# EXPECT: [input.txt]
# EXPECT: [Unknown option: --unknown]
# EXPECT: [Missing value for -o]
# EXPECT: Usage: myapp [OPTIONS] <input>
import std.argparse as argparse

let parser = argparse.create("myapp", "CLI App Description")
argparse.add_flag(parser, "verbose", "v", "Enable verbose mode")
argparse.add_flag(parser, "debug", "d", "Enable debug mode")
argparse.add_option(parser, "output", "o", "Output file", "out.txt")
argparse.add_option(parser, "config", "c", "Config file", "config.json")
argparse.add_positional(parser, "input", "Input file", true)

let argv = ["--verbose", "--output", "out.txt", "-c", "config.json", "input.txt"]
let res = argparse.parse(parser, argv)

print argparse.get_flag(res, "verbose")
print argparse.get_flag(res, "debug")
print argparse.get_option(res, "output")
print argparse.get_option(res, "config")
print res["positionals"]

let err_argv = ["--unknown"]
let err_res = argparse.parse(parser, err_argv)
print err_res["errors"]

let missing_argv = ["-o"]
let missing_res = argparse.parse(parser, missing_argv)
print missing_res["errors"]

let help = argparse.help_text(parser)
print split(help, chr(10))[0]
