class _Sys:
    proc exec(cmd):
        return sys_exec(cmd)
    proc args():
        return sys_args_builtin()
let sys = _Sys()
