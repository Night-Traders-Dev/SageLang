class _Io:
    proc readfile(p):
        return io_readfile(p)
    proc writefile(p, c):
        return io_writefile(p, c)
    proc exists(p):
        return io_exists(p)
let io = _Io()
