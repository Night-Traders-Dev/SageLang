proc exec(cmd):
    return sys_exec(cmd)
proc args():
    return sys_args_builtin()
proc getenv(name):
    return sys_getenv_native(name)
