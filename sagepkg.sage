#!/usr/bin/env sage
import sys
import io
import json
import string
import std.process as process

let REPO_URL = "https://raw.githubusercontent.com/Night-Traders-Dev/SagePkg/main"

let CONFIG_DIR = ".sagepkg"
let PKGS_DIR = CONFIG_DIR + "/pkgs"
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

proc cmd_update():
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
        print "  update       Sync package index"
        print "  list         List available packages"
        print "  install <p>  Install a package"
        print "  installed    List installed packages"
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
    else:
        print "Unknown command: " + cmd

main()
