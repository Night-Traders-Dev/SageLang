## os.errno — POSIX-style error codes for SageOS
##
## Provides a centralized set of error constants and utilities
## for error handling across the OS abstraction layer.

let OK = 0 # No error
let EPERM = 1 # Operation not permitted
let ENOENT = 2 # No such file or directory
let ESRCH = 3 # No such process
let EINTR = 4 # Interrupted system call
let EIO = 5 # I/O error
let ENXIO = 6 # No such device or address
let E2BIG = 7 # Argument list too long
let ENOEXEC = 8 # Exec format error
let EBADF = 9 # Bad file number
let ECHILD = 10 # No child processes
let EAGAIN = 11 # Try again
let ENOMEM = 12 # Out of memory
let EACCES = 13 # Permission denied
let EFAULT = 14 # Bad address
let ENOTBLK = 15 # Block device required
let EBUSY = 16 # Device or resource busy
let EEXIST = 17 # File exists
let EXDEV = 18 # Cross-device link
let ENODEV = 19 # No such device
let ENOTDIR = 20 # Not a directory
let EISDIR = 21 # Is a directory
let EINVAL = 22 # Invalid argument
let ENFILE = 23 # File table overflow
let EMFILE = 24 # Too many open files
let ENOTTY = 25 # Not a typewriter
let ETXTBSY = 26 # Text file busy
let EFBIG = 27 # File too large
let ENOSPC = 28 # No space left on device
let ESPIPE = 29 # Illegal seek
let EROFS = 30 # Read-only file system
let EMLINK = 31 # Too many links
let EPIPE = 32 # Broken pipe
let EDOM = 33 # Math argument out of domain of func
let ERANGE = 34 # Math result not representable

## Returns a human-readable string for the given error code.
proc strerror(err):
    if err == OK:
        return "Success"
    end
    if err == EPERM:
        return "Operation not permitted"
    end
    if err == ENOENT:
        return "No such file or directory"
    end
    if err == ESRCH:
        return "No such process"
    end
    if err == EINTR:
        return "Interrupted system call"
    end
    if err == EIO:
        return "I/O error"
    end
    if err == ENXIO:
        return "No such device or address"
    end
    if err == E2BIG:
        return "Argument list too long"
    end
    if err == ENOEXEC:
        return "Exec format error"
    end
    if err == EBADF:
        return "Bad file number"
    end
    if err == ECHILD:
        return "No child processes"
    end
    if err == EAGAIN:
        return "Try again"
    end
    if err == ENOMEM:
        return "Out of memory"
    end
    if err == EACCES:
        return "Permission denied"
    end
    if err == EFAULT:
        return "Bad address"
    end
    if err == ENOTBLK:
        return "Block device required"
    end
    if err == EBUSY:
        return "Device or resource busy"
    end
    if err == EEXIST:
        return "File exists"
    end
    if err == EXDEV:
        return "Cross-device link"
    end
    if err == ENODEV:
        return "No such device"
    end
    if err == ENOTDIR:
        return "Not a directory"
    end
    if err == EISDIR:
        return "Is a directory"
    end
    if err == EINVAL:
        return "Invalid argument"
    end
    if err == ENFILE:
        return "File table overflow"
    end
    if err == EMFILE:
        return "Too many open files"
    end
    if err == ENOTTY:
        return "Not a typewriter"
    end
    if err == ETXTBSY:
        return "Text file busy"
    end
    if err == EFBIG:
        return "File too large"
    end
    if err == ENOSPC:
        return "No space left on device"
    end
    if err == ESPIPE:
        return "Illegal seek"
    end
    if err == EROFS:
        return "Read-only file system"
    end
    if err == EMLINK:
        return "Too many links"
    end
    if err == EPIPE:
        return "Broken pipe"
    end
    if err == EDOM:
        return "Math argument out of domain of func"
    end
    if err == ERANGE:
        return "Math result not representable"
    end
    return "Unknown error " + str(err)
