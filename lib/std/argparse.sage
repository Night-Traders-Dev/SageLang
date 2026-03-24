gc_disable()
# CLI argument parser
# Supports flags (--verbose), options (--output file), positional args, subcommands

# Argument types
let ARG_FLAG = 1
let ARG_OPTION = 2
let ARG_POSITIONAL = 3

# Create an argument parser
proc create(prog_name, description):
    let parser = {}
    parser["name"] = prog_name
    parser["description"] = description
    parser["args"] = []
    parser["flags"] = {}
    parser["options"] = {}
    parser["positionals"] = []
    parser["subcommands"] = {}
    return parser

# Add a flag (--verbose, -v)
proc add_flag(parser, long_name, short_name, help_text):
    let arg = {}
    arg["type"] = 1
    arg["long"] = long_name
    arg["short"] = short_name
    arg["help"] = help_text
    arg["default"] = false
    push(parser["args"], arg)
    return parser

# Add an option (--output file, -o file)
proc add_option(parser, long_name, short_name, help_text, default_val):
    let arg = {}
    arg["type"] = 2
    arg["long"] = long_name
    arg["short"] = short_name
    arg["help"] = help_text
    arg["default"] = default_val
    arg["required"] = default_val == nil
    push(parser["args"], arg)
    return parser

# Add a positional argument
proc add_positional(parser, name, help_text, required):
    let arg = {}
    arg["type"] = 3
    arg["name"] = name
    arg["help"] = help_text
    arg["required"] = required
    push(parser["args"], arg)
    return parser

# Parse argv array (typically from sys.args())
proc parse(parser, argv):
    let result = {}
    result["flags"] = {}
    result["options"] = {}
    result["positionals"] = []
    result["errors"] = []
    result["rest"] = []
    # Set defaults
    let args = parser["args"]
    for i in range(len(args)):
        let a = args[i]
        if a["type"] == 1:
            result["flags"][a["long"]] = false
        if a["type"] == 2:
            result["options"][a["long"]] = a["default"]
    # Parse argv
    let pos_idx = 0
    let idx = 0
    while idx < len(argv):
        let token = argv[idx]
        let consumed = false
        # Check long flags/options (--name)
        if len(token) > 2 and token[0] == "-" and token[1] == "-":
            let name = ""
            for j in range(len(token) - 2):
                name = name + token[2 + j]
            # Check if it's a known flag
            let found_flag = false
            for i in range(len(args)):
                if not found_flag and args[i]["type"] == 1 and args[i]["long"] == name:
                    result["flags"][name] = true
                    found_flag = true
                    consumed = true
            if not found_flag:
                # Check if it's a known option
                let found_opt = false
                for i in range(len(args)):
                    if not found_opt and args[i]["type"] == 2 and args[i]["long"] == name:
                        if idx + 1 < len(argv):
                            idx = idx + 1
                            result["options"][name] = argv[idx]
                        else:
                            push(result["errors"], "Missing value for --" + name)
                        found_opt = true
                        consumed = true
                if not found_opt:
                    push(result["errors"], "Unknown option: --" + name)
                    consumed = true
        # Check short flags (-v)
        if not consumed and len(token) == 2 and token[0] == "-" and token[1] != "-":
            let short_ch = token[1]
            let found_short = false
            for i in range(len(args)):
                if not found_short:
                    if args[i]["type"] == 1 and args[i]["short"] == short_ch:
                        result["flags"][args[i]["long"]] = true
                        found_short = true
                        consumed = true
                    if args[i]["type"] == 2 and args[i]["short"] == short_ch:
                        if idx + 1 < len(argv):
                            idx = idx + 1
                            result["options"][args[i]["long"]] = argv[idx]
                        else:
                            push(result["errors"], "Missing value for -" + short_ch)
                        found_short = true
                        consumed = true
        if not consumed:
            # Positional argument
            push(result["positionals"], token)
            pos_idx = pos_idx + 1
        idx = idx + 1
    return result

# Get a flag value
proc get_flag(result, name):
    if dict_has(result["flags"], name):
        return result["flags"][name]
    return false

# Get an option value
proc get_option(result, name):
    if dict_has(result["options"], name):
        return result["options"][name]
    return nil

# Generate help text
proc help_text(parser):
    let nl = chr(10)
    let text = "Usage: " + parser["name"] + " [OPTIONS]"
    let args = parser["args"]
    for i in range(len(args)):
        if args[i]["type"] == 3:
            text = text + " <" + args[i]["name"] + ">"
    text = text + nl + nl
    if len(parser["description"]) > 0:
        text = text + parser["description"] + nl + nl
    text = text + "Options:" + nl
    for i in range(len(args)):
        let a = args[i]
        if a["type"] == 1:
            text = text + "  -" + a["short"] + ", --" + a["long"]
            text = text + "    " + a["help"] + nl
        if a["type"] == 2:
            text = text + "  -" + a["short"] + ", --" + a["long"] + " <value>"
            text = text + "    " + a["help"] + nl
    return text
