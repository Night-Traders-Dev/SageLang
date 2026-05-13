import io
import sys
import string
import std.fmt as fmt
import std.process as process

# ANSI Colors
let ESC = chr(27)
let RESET = ESC + "[0m"
let BOLD = ESC + "[1m"
let GREEN = ESC + "[32m"
let BLUE = ESC + "[34m"
let CYAN = ESC + "[36m"
let RED = ESC + "[31m"
let MAGENTA = ESC + "[35m"
let YELLOW = ESC + "[33m"

proc trim(s):
    if s == nil:
        return ""
    let start_idx = 0
    while start_idx < len(s) and (s[start_idx] == " " or s[start_idx] == "\n" or s[start_idx] == "\r" or s[start_idx] == "\t"):
        start_idx = start_idx + 1
    let end_idx = len(s) - 1
    while end_idx >= start_idx and (s[end_idx] == " " or s[end_idx] == "\n" or s[end_idx] == "\r" or s[end_idx] == "\t"):
        end_idx = end_idx - 1
    if end_idx < start_idx:
        return ""
    let result = ""
    for i in range(end_idx - start_idx + 1):
        result = result + s[start_idx + i]
    return result

proc split_lines(s):
    let lines = []
    if s == nil:
        return lines
    let current = ""
    for i in range(len(s)):
        if s[i] == "\n":
            push(lines, current)
            current = ""
        else:
            current = current + s[i]
    if len(current) > 0:
        push(lines, current)
    return lines

proc read_proc_file(path):
    let tmp = "/tmp/sage_proc_tmp"
    sys.exec("cat " + path + " > " + tmp + " 2>/dev/null")
    let content = io.readfile(tmp)
    return content

proc get_os_info():
    let content = io.readfile("/etc/os-release")
    if content == nil:
        return "Linux"
    let lines = split_lines(content)
    for line in lines:
        if len(line) > 12:
            if string.substr(line, 0, 12) == "PRETTY_NAME=":
                let name = string.substr(line, 12, len(line) - 12)
                # Remove quotes
                if len(name) > 1 and name[0] == "\"":
                    return string.substr(name, 1, len(name) - 2)
                return name
    return "Linux"

proc get_kernel_info():
    let content = read_proc_file("/proc/version")
    if content == nil or len(content) == 0:
        return sys.platform
    let parts = []
    let current = ""
    for i in range(len(content)):
        if content[i] == " ":
            if len(current) > 0:
                push(parts, current)
            current = ""
        else:
            current = current + content[i]
    if len(current) > 0:
        push(parts, current)
    
    if len(parts) > 2:
        return parts[2]
    return sys.platform

proc get_uptime_info():
    let content = read_proc_file("/proc/uptime")
    if content == nil or len(content) == 0:
        return "unknown"
    let i = 0
    let seconds_str = ""
    while i < len(content) and content[i] != " ":
        seconds_str = seconds_str + content[i]
        i = i + 1
    
    let dot = -1
    for j in range(len(seconds_str)):
        if seconds_str[j] == ".":
            dot = j
    
    let int_part = seconds_str
    if dot != -1:
        int_part = string.substr(seconds_str, 0, dot)
    
    let total_seconds = tonumber(int_part)
    if total_seconds == nil:
        return "unknown"

    let hours = (total_seconds / 3600) | 0
    let minutes = ((total_seconds - hours * 3600) / 60) | 0
    
    let result = ""
    if hours > 0:
        result = str(hours) + " hours, "
    result = result + str(minutes) + " mins"
    return result

proc get_cpu_info():
    let content = read_proc_file("/proc/cpuinfo")
    if content == nil or len(content) == 0:
        return "unknown"
    let lines = split_lines(content)
    for line in lines:
        if len(line) > 13:
            if string.substr(line, 0, 13) == "model name\t: ":
                return string.substr(line, 13, len(line) - 13)
        if len(line) > 11:
            if string.substr(line, 0, 11) == "Model\t\t: ":
                return string.substr(line, 11, len(line) - 11)
    return "Generic CPU"

proc get_mem_info():
    let content = read_proc_file("/proc/meminfo")
    if content == nil or len(content) == 0:
        return "unknown"
    let lines = split_lines(content)
    let total_kb = 0
    let available_kb = 0
    
    for line in lines:
        let t_line = trim(line)
        if len(t_line) > 9:
            if string.substr(t_line, 0, 9) == "MemTotal:":
                let parts = []
                let curr = ""
                for c in range(len(t_line)):
                    if t_line[c] == " " or t_line[c] == "\t":
                        if len(curr) > 0:
                            push(parts, curr)
                        curr = ""
                    else:
                        curr = curr + t_line[c]
                if len(curr) > 0:
                    push(parts, curr)
                if len(parts) > 1:
                    total_kb = tonumber(parts[1])
        
        if len(t_line) > 13:
            if string.substr(t_line, 0, 13) == "MemAvailable:":
                let parts = []
                let curr = ""
                for c in range(len(t_line)):
                    if t_line[c] == " " or t_line[c] == "\t":
                        if len(curr) > 0:
                            push(parts, curr)
                        curr = ""
                    else:
                        curr = curr + t_line[c]
                if len(curr) > 0:
                    push(parts, curr)
                if len(parts) > 1:
                    available_kb = tonumber(parts[1])

    if total_kb > 0:
        let used_kb = total_kb - available_kb
        return str(used_kb / 1024 | 0) + "MiB / " + str(total_kb / 1024 | 0) + "MiB"
    return "unknown"

proc get_user_host():
    let user = sys.getenv("USER")
    if user == nil:
        user = "user"
    let host = io.readfile("/etc/hostname")
    if host == nil:
        host = "sage"
    return GREEN + BOLD + user + RESET + "@" + GREEN + BOLD + trim(host) + RESET

# ASCII Art for Sage
let logo = [
    GREEN + "          ____          " + RESET,
    GREEN + "        /      \\        " + RESET,
    GREEN + "       |   " + YELLOW + "S" + GREEN + "    |       " + RESET,
    GREEN + "        \\  " + YELLOW + "A" + GREEN + "  /        " + RESET,
    GREEN + "         | " + YELLOW + "G" + GREEN + " |         " + RESET,
    GREEN + "         | " + YELLOW + "E" + GREEN + " |         " + RESET,
    GREEN + "         \\____/         " + RESET,
    GREEN + "           ||           " + RESET,
    GREEN + "           ||           " + RESET
]

let user_host_line = get_user_host()
let dash = "------------------------"

let info = [
    user_host_line,
    dash,
    CYAN + BOLD + "OS:      " + RESET + str(get_os_info()),
    CYAN + BOLD + "Kernel:  " + RESET + str(get_kernel_info()),
    CYAN + BOLD + "Uptime:  " + RESET + str(get_uptime_info()),
    CYAN + BOLD + "Shell:   " + RESET + str(process.get_env_or("SHELL", "/bin/sh")),
    CYAN + BOLD + "CPU:     " + RESET + str(get_cpu_info()),
    CYAN + BOLD + "Memory:  " + RESET + str(get_mem_info()),
    "",
    "   " + ESC + "[40m  " + ESC + "[41m  " + ESC + "[42m  " + ESC + "[43m  " + ESC + "[44m  " + ESC + "[45m  " + ESC + "[46m  " + ESC + "[47m  " + RESET
]

let max_lines = len(logo)
if len(info) > max_lines:
    max_lines = len(info)

for i in range(max_lines):
    let line = ""
    if i < len(logo):
        line = logo[i]
    else:
        line = "                        " # 24 spaces
    
    line = line + "   "
    
    if i < len(info):
        line = line + str(info[i])
    
    print line

print ""
