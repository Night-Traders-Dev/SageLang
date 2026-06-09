# # os.errno — POSIX-style error codes for SageOS
# #
# # Provides a centralized set of error constants and utilities
# # for error handling across the OS abstraction layer.

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
let EWOULDBLOCK = 11 # Operation would block
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
let EDEADLK = 35 # Resource deadlock avoided
let ENAMETOOLONG = 36 # File name too long
let ENOLCK = 37 # No locks available
let ENOSYS = 38 # Function not implemented
let ENOTEMPTY = 39 # Directory not empty
let ELOOP = 40 # Too many levels of symbolic links
let ENOTSOCK = 88 # Socket operation on non-socket
let EDESTADDRREQ = 89 # Destination address required
let EMSGSIZE = 90 # Message too long
let EPROTOTYPE = 91 # Protocol wrong type for socket
let ENOPROTOOPT = 92 # Protocol not available
let EPROTONOSUPPORT = 93 # Protocol not supported
let ESOCKTNOSUPPORT = 94 # Socket type not supported
let EOPNOTSUPP = 95 # Operation not supported on transport endpoint
let EPFNOSUPPORT = 96 # Protocol family not supported
let EAFNOSUPPORT = 97 # Address family not supported by protocol
let EADDRINUSE = 98 # Address already in use
let EADDRNOTAVAIL = 99 # Cannot assign requested address
let ENETDOWN = 100 # Network is down
let ENETUNREACH = 101 # Network is unreachable
let ENETRESET = 102 # Network dropped connection because of reset
let ECONNABORTED = 103 # Software caused connection abort
let ECONNRESET = 104 # Connection reset by peer
let ENOBUFS = 105 # No buffer space available
let EISCONN = 106 # Transport endpoint is already connected
let ENOTCONN = 107 # Transport endpoint is not connected
let ESHUTDOWN = 108 # Cannot send after transport endpoint shutdown
let ETOOMANYREFS = 109 # Too many references: cannot splice
let ETIMEDOUT = 110 # Connection timed out
let ECONNREFUSED = 111 # Connection refused
let EHOSTDOWN = 112 # Host is down
let EHOSTUNREACH = 113 # No route to host
let EALREADY = 114 # Operation already in progress
let EINPROGRESS = 115 # Operation now in progress

let _error_messages = {
    "0": "Success",
    "1": "Operation not permitted",
    "2": "No such file or directory",
    "3": "No such process",
    "4": "Interrupted system call",
    "5": "I/O error",
    "6": "No such device or address",
    "7": "Argument list too long",
    "8": "Exec format error",
    "9": "Bad file number",
    "10": "No child processes",
    "11": "Try again",
    "12": "Out of memory",
    "13": "Permission denied",
    "14": "Bad address",
    "15": "Block device required",
    "16": "Device or resource busy",
    "17": "File exists",
    "18": "Cross-device link",
    "19": "No such device",
    "20": "Not a directory",
    "21": "Is a directory",
    "22": "Invalid argument",
    "23": "File table overflow",
    "24": "Too many open files",
    "25": "Not a typewriter",
    "26": "Text file busy",
    "27": "File too large",
    "28": "No space left on device",
    "29": "Illegal seek",
    "30": "Read-only file system",
    "31": "Too many links",
    "32": "Broken pipe",
    "33": "Math argument out of domain of func",
    "34": "Math result not representable",
    "35": "Resource deadlock avoided",
    "36": "File name too long",
    "37": "No locks available",
    "38": "Function not implemented",
    "39": "Directory not empty",
    "40": "Too many levels of symbolic links",
    "88": "Socket operation on non-socket",
    "89": "Destination address required",
    "90": "Message too long",
    "91": "Protocol wrong type for socket",
    "92": "Protocol not available",
    "93": "Protocol not supported",
    "94": "Socket type not supported",
    "95": "Operation not supported on transport endpoint",
    "96": "Protocol family not supported",
    "97": "Address family not supported by protocol",
    "98": "Address already in use",
    "99": "Cannot assign requested address",
    "100": "Network is down",
    "101": "Network is unreachable",
    "102": "Network dropped connection because of reset",
    "103": "Software caused connection abort",
    "104": "Connection reset by peer",
    "105": "No buffer space available",
    "106": "Transport endpoint is already connected",
    "107": "Transport endpoint is not connected",
    "108": "Cannot send after transport endpoint shutdown",
    "109": "Too many references: cannot splice",
    "110": "Connection timed out",
    "111": "Connection refused",
    "112": "Host is down",
    "113": "No route to host",
    "114": "Operation already in progress",
    "115": "Operation now in progress"
}

## Returns a human-readable string for the given error code.
proc strerror(err):
    let key = str(err)
    if dict_has(_error_messages, key):
        return _error_messages[key]
    end
    return "Unknown error " + key
