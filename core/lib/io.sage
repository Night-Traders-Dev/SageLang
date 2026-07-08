class _Io:
    proc readfile(p):
        return io_readfile(p)
    proc writefile(p, c):
        return io_writefile(p, c)
    proc writebytes(p, b):
        return io_writebytes(p, b)
    proc appendbytes(p, b):
        return io_appendbytes(p, b)
    proc readbytes(p):
        return io_readbytes(p)
    proc exists(p):
        return io_exists(p)
    proc remove(p):
        return io_remove(p)
    proc isdir(p):
        return io_isdir(p)
    proc mkdir(p):
        return io_mkdir(p)
let io = _Io()
