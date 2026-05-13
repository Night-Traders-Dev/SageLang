#!/usr/bin/env sage
import sys
import io
import json
import string
import std.process as process

let REPO_URL = "https://raw.githubusercontent.com/Night-Traders-Dev/SagePkg/main"

let CONFIG_DIR = ".sagepkg"
let PKGS_DIR = CONFIG_DIR + "/pkgs"
let BIN_DIR = CONFIG_DIR + "/bin"
let INDEX_FILE = CONFIG_DIR + "/packages.json"
let INSTALLED_FILE = CONFIG_DIR + "/installed.json"

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

proc ensure_dir(dir):
    if not io.isdir(dir):
        io.mkdir(dir)

proc download_file(url, dest):
    let cmd = "curl -sL " + url + " -o " + dest
    let res = sys.exec(cmd)
    return res == 0

proc read_json(path):
    let content = io.readfile(path)
    if content == nil:
        return nil
    let cjson = json.cJSON_Parse(content)
    if cjson == nil:
        return nil
    let data = json.cJSON_ToSage(cjson)
    json.cJSON_Delete(cjson)
    return data

proc write_json(path, data):
    let cjson = json.cJSON_FromSage(data)
    let content = json.cJSON_Print(cjson)
    io.writefile(path, content)
    json.cJSON_Delete(cjson)

proc get_arch():
    let tmp = "/tmp/sage_arch"
    sys.exec("uname -m > " + tmp)
    let arch = trim(io.readfile(tmp))
    # io.remove(tmp)
    return arch

proc get_full_path(path):
    sys.exec("readlink -f " + path + " > /tmp/sage_fullpath")
    return trim(io.readfile("/tmp/sage_fullpath"))

proc cmd_init():
    let shell = sys.getenv("SHELL")
    if shell == nil:
        shell = "/bin/sh"
    
    let home = sys.getenv("HOME")
    if home == nil:
        return
        
    ensure_dir(CONFIG_DIR)
    ensure_dir(BIN_DIR)
    let full_bin_path = get_full_path(BIN_DIR)
    
    let config_file = nil
    let path_cmd = nil
    
    if string.contains(shell, "bash") or shell == "/bin/sh":
        config_file = home + "/.bashrc"
        path_cmd = "export PATH=" + chr(34) + full_bin_path + ":$PATH" + chr(34)
    elif string.contains(shell, "zsh"):
        config_file = home + "/.zshrc"
        path_cmd = "export PATH=" + chr(34) + full_bin_path + ":$PATH" + chr(34)
    elif string.contains(shell, "fish"):
        config_file = home + "/.config/fish/config.fish"
        path_cmd = "set -gx PATH " + full_bin_path + " $PATH"
    
    if config_file != nil:
        if io.exists(config_file):
            let content = io.readfile(config_file)
            if not string.contains(content, full_bin_path):
                print "Automatically adding " + full_bin_path + " to " + config_file + "..."
                io.appendfile(config_file, chr(10) + "# SagePkg PATH" + chr(10) + path_cmd + chr(10))
                print "Success: PATH initialized. Please restart your shell."
        else:
            # Only create for common shells if they are definitely being used
            if shell != "/bin/sh":
                print "Creating " + config_file + " and setting PATH..."
                io.writefile(config_file, "# SagePkg PATH" + chr(10) + path_cmd + chr(10))

proc cmd_update():
    cmd_init()
    print "Updating package index..."
    ensure_dir(CONFIG_DIR)
    let url = REPO_URL + "/packages.json"
    if download_file(url, INDEX_FILE):
        print "Success: Index updated."
    else:
        print "Error: Failed to download index from " + url

proc cmd_list():
    let data = read_json(INDEX_FILE)
    if data == nil:
        print "Error: No package index found. Run 'update' first."
        return
    
    print "Available packages:"
    print "-------------------"
    let pkgs = data["packages"]
    for i in range(len(pkgs)):
        let p = pkgs[i]
        print p["name"] + " (v" + p["version"] + ") - " + p["description"]

proc cmd_install(pkg_name):
    let index_data = read_json(INDEX_FILE)
    if index_data == nil:
        print "Error: No package index found. Run 'update' first."
        return
    
    let pkg_info = nil
    let pkgs = index_data["packages"]
    for i in range(len(pkgs)):
        if pkgs[i]["name"] == pkg_name:
            pkg_info = pkgs[i]
    
    if pkg_info == nil:
        print "Error: Package '" + pkg_name + "' not found in index."
        return
    
    let arch = get_arch()
    let arch_supported = false
    let arches = pkg_info["architectures"]
    for i in range(len(arches)):
        if arches[i] == arch:
            arch_supported = true
    
    if not arch_supported:
        print "Error: Package '" + pkg_name + "' does not support architecture: " + arch
        return
    
    print "Installing " + pkg_name + " for " + arch + "..."
    ensure_dir(CONFIG_DIR)
    ensure_dir(PKGS_DIR)
    ensure_dir(BIN_DIR)
    let pkg_dir = PKGS_DIR + "/" + pkg_name
    ensure_dir(pkg_dir)
    
    # Download metadata
    let meta_url = REPO_URL + "/packages/" + pkg_name + "/metadata.json"
    let meta_file = pkg_dir + "/metadata.json"
    if not download_file(meta_url, meta_file):
        print "Error: Failed to download metadata for " + pkg_name
        return
    
    let meta = read_json(meta_file)
    if meta == nil:
        print "Error: Failed to parse metadata for " + pkg_name
        return
    
    # Download files
    let files = meta["files"]
    for i in range(len(files)):
        let fname = files[i]
        let f_url = REPO_URL + "/packages/" + pkg_name + "/" + arch + "/" + fname
        let f_dest = pkg_dir + "/" + fname
        if not download_file(f_url, f_dest):
            print "Error: Failed to download file: " + fname
            return
    
    # Create wrapper script in BIN_DIR
    let main_file = meta["main"]
    if main_file != nil:
        let bin_path = BIN_DIR + "/" + pkg_name
        let full_pkg_path = get_full_path(pkg_dir + "/" + main_file)
        let wrapper = "#!/bin/sh" + chr(10) + "exec sage " + full_pkg_path + " " + chr(34) + "$@" + chr(34) + chr(10)
        io.writefile(bin_path, wrapper)
        sys.exec("chmod +x " + bin_path)
        print "Created executable: " + bin_path

    # Record installation
    let installed = read_json(INSTALLED_FILE)
    if installed == nil:
        installed = {"packages": {}}
    
    installed["packages"][pkg_name] = {
        "version": meta["version"],
        "install_date": "2026-05-13", # Hardcoded for now
        "files": files
    }
    write_json(INSTALLED_FILE, installed)
    
    print "Success: " + pkg_name + " installed."
    
    # PATH check
    let full_bin_path = get_full_path(BIN_DIR)
    let path_env = sys.getenv("PATH")
    if string.find(path_env, full_bin_path) == -1:
        print ""
        print "NOTE: To run '" + pkg_name + "' by name, add this to your PATH:"
        print "  export PATH=" + chr(34) + full_bin_path + ":$PATH" + chr(34)

proc cmd_installed():
    let installed = read_json(INSTALLED_FILE)
    if installed == nil:
        print "No packages installed."
        return
    if len(installed["packages"]) == 0:
        print "No packages installed."
        return
    
    print "Installed packages:"
    print "-------------------"
    let names = dict_keys(installed["packages"])
    for i in range(len(names)):
        let name = names[i]
        let info = installed["packages"][name]
        print name + " (v" + info["version"] + ")"


proc main():
    let args = sys.args()
    # Skip interpreter and script name
    let cmd_idx = 2
    if len(args) < 3:
        print "Usage: sagepkg <command> [args]"
        print "Commands:"
        print "  update       Sync package index (auto-inits PATH)"
        print "  list         List available packages"
        print "  install <p>  Install a package"
        print "  installed    List installed packages"
        print "  init         Force initialize shell PATH"
        return

    let cmd = args[cmd_idx]
    if cmd == "update":
        cmd_update()
    elif cmd == "list":
        cmd_list()
    elif cmd == "install":
        if len(args) < 4:
            print "Error: Missing package name."
        else:
            cmd_install(args[3])
    elif cmd == "installed":
        cmd_installed()
    elif cmd == "init":
        cmd_init()
    else:
        print "Unknown command: " + cmd

main()
