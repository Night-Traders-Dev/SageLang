class _Io:
    proc readfile(p):
        return io_readfile(p)
    proc writefile(p, c):
        return io_writefile(p, c)
    proc writebytes(p, b):
        return io_writebytes(p, b)
    proc readbytes(p):
        return io_readbytes(p)
    proc exists(p):
        return io_exists(p)
let io = _Io()
