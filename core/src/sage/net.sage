gc_disable()
# net.sage - Self-hosted stub for the net module
#
# The C backend (net.c) implements TCP/UDP sockets via POSIX BSD sockets.
# Pure Sage has no access to OS socket syscalls, so every function here
# delegates to the C host via ffi or returns a documented error value.
#
# Naming mirrors net.c exactly so that `import net` works identically
# on both the C backend and the self-hosted interpreter.

# Error sentinel returned when an operation cannot be performed
# in the pure-Sage context (no OS socket access).
let NET_UNAVAILABLE = -1
let NET_OK = 0

# Address-family constants (mirrors net.h)
let AF_INET  = 2
let AF_INET6 = 10

# Socket-type constants
let SOCK_STREAM = 1
let SOCK_DGRAM  = 2

# ---- Socket lifecycle ----

# Create a new TCP socket. Returns a socket handle (number) or NET_UNAVAILABLE.
proc net_socket(af, sock_type):
    return NET_UNAVAILABLE

# Connect an existing socket to (host, port).
# Returns NET_OK on success, NET_UNAVAILABLE otherwise.
proc net_connect(sock, host, port):
    return NET_UNAVAILABLE

# Bind a socket to (host, port).
proc net_bind(sock, host, port):
    return NET_UNAVAILABLE

# Start listening on a bound socket. backlog controls queue depth.
proc net_listen(sock, backlog):
    return NET_UNAVAILABLE

# Accept an incoming connection. Returns a new socket handle or NET_UNAVAILABLE.
proc net_accept(sock):
    return NET_UNAVAILABLE

# Close a socket.
proc net_close(sock):
    return NET_UNAVAILABLE

# ---- Data transfer ----

# Send bytes (array of numbers) on a socket.
# Returns the number of bytes sent, or NET_UNAVAILABLE on error.
proc net_send(sock, data):
    return NET_UNAVAILABLE

# Send a string on a socket (convenience wrapper).
proc net_send_string(sock, s):
    return NET_UNAVAILABLE

# Receive up to max_bytes bytes from a socket.
# Returns an array of byte values, or nil on error.
proc net_recv(sock, max_bytes):
    return nil

# Receive data as a string.
proc net_recv_string(sock, max_bytes):
    return nil

# ---- UDP datagram ----

# Send a datagram to (host, port) from an unconnected socket.
proc net_sendto(sock, data, host, port):
    return NET_UNAVAILABLE

# Receive a datagram. Returns {"data": [...], "host": "...", "port": N} or nil.
proc net_recvfrom(sock, max_bytes):
    return nil

# ---- Helpers ----

# Resolve a hostname to an IPv4 address string, or nil on failure.
proc net_resolve(host):
    return nil

# Return the last socket error as a human-readable string.
proc net_strerror():
    return "net module not available in self-hosted mode"

# Set socket to non-blocking mode. Returns NET_OK or NET_UNAVAILABLE.
proc net_set_nonblocking(sock, enable):
    return NET_UNAVAILABLE

# Set socket option SO_REUSEADDR.
proc net_set_reuseaddr(sock, enable):
    return NET_UNAVAILABLE

# ---- High-level convenience ----

# Open a TCP connection to host:port. Returns socket or NET_UNAVAILABLE.
proc net_tcp_connect(host, port):
    return NET_UNAVAILABLE

# Open a TCP server on port. Returns listening socket or NET_UNAVAILABLE.
proc net_tcp_listen(port, backlog):
    return NET_UNAVAILABLE

# ---- Module factory ----

proc create_net_module():
    let m = {}
    # Constants
    m["OK"]          = NET_OK
    m["UNAVAILABLE"] = NET_UNAVAILABLE
    m["AF_INET"]     = AF_INET
    m["AF_INET6"]    = AF_INET6
    m["SOCK_STREAM"] = SOCK_STREAM
    m["SOCK_DGRAM"]  = SOCK_DGRAM
    # Functions
    m["socket"]          = net_socket
    m["connect"]         = net_connect
    m["bind"]            = net_bind
    m["listen"]          = net_listen
    m["accept"]          = net_accept
    m["close"]           = net_close
    m["send"]            = net_send
    m["send_string"]     = net_send_string
    m["recv"]            = net_recv
    m["recv_string"]     = net_recv_string
    m["sendto"]          = net_sendto
    m["recvfrom"]        = net_recvfrom
    m["resolve"]         = net_resolve
    m["strerror"]        = net_strerror
    m["set_nonblocking"] = net_set_nonblocking
    m["set_reuseaddr"]   = net_set_reuseaddr
    m["tcp_connect"]     = net_tcp_connect
    m["tcp_listen"]      = net_tcp_listen
    return m
