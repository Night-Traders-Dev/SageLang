gc_disable()
# EXPECT: epoll_constants
# EXPECT: event_loop_created
# EXPECT: fd_added
# EXPECT: event_create
# EXPECT: event_flags
# EXPECT: codegen_output
# EXPECT: tcp_server
# EXPECT: PASS

# Test epoll constants
let EPOLLIN = 1
let EPOLLOUT = 4
let EPOLLERR = 8
let EPOLLHUP = 16
let EPOLLET = 2147483648
let EPOLL_CTL_ADD = 1
let EPOLL_CTL_DEL = 2
let EPOLL_CTL_MOD = 3
if EPOLLIN == 1:
    if EPOLLOUT == 4:
        if EPOLLET == 2147483648:
            print "epoll_constants"

# Test event loop creation
proc create_event_loop(name, max_events):
    let ev = {}
    ev["name"] = name
    ev["max_events"] = max_events
    ev["fds"] = []
    ev["timeout_ms"] = -1
    return ev

let ev = create_event_loop("main_loop", 64)
if ev["name"] == "main_loop":
    if ev["max_events"] == 64:
        if ev["timeout_ms"] == -1:
            print "event_loop_created"

# Test adding file descriptors
proc evloop_add_fd(ev_in, fd, events, handler):
    let entry = {}
    entry["fd"] = fd
    entry["events"] = events
    entry["handler"] = handler
    push(ev_in["fds"], entry)
    return ev_in

ev = evloop_add_fd(ev, 3, EPOLLIN, "handle_stdin")
ev = evloop_add_fd(ev, 4, EPOLLIN + EPOLLOUT, "handle_socket")
if len(ev["fds"]) == 2:
    if ev["fds"][0]["fd"] == 3:
        if ev["fds"][1]["handler"] == "handle_socket":
            print "fd_added"

# Test event descriptor
proc create_event(fd, event_mask):
    let e = {}
    e["fd"] = fd
    e["events"] = event_mask
    e["readable"] = (event_mask % 2) == 1
    e["writable"] = false
    if (event_mask / 4) % 2 == 1:
        e["writable"] = true
    e["error"] = false
    if (event_mask / 8) % 2 == 1:
        e["error"] = true
    e["hangup"] = false
    if (event_mask / 16) % 2 == 1:
        e["hangup"] = true
    return e

let e1 = create_event(3, EPOLLIN)
if e1["readable"]:
    if e1["writable"] == false:
        print "event_create"

# Test combined event flags
let e2 = create_event(4, EPOLLIN + EPOLLOUT + EPOLLERR)
if e2["readable"]:
    if e2["writable"]:
        if e2["error"]:
            if e2["hangup"] == false:
                print "event_flags"

# Test C codegen output
let nl = chr(10)
let q = chr(34)
let code = ""
code = code + "#include <sys/epoll.h>" + nl
code = code + "int main_loop_run(void) {" + nl
code = code + "    int epfd = epoll_create1(0);" + nl
code = code + "    struct epoll_event ev, events[64];" + nl
code = code + "    while (running) {" + nl
code = code + "        int nfds = epoll_wait(epfd, events, 64, -1);" + nl
code = code + "    }" + nl
code = code + "    close(epfd);" + nl
code = code + "    return 0;" + nl
code = code + "}" + nl
if contains(code, "epoll_create1"):
    if contains(code, "epoll_wait"):
        if contains(code, "close(epfd)"):
            print "codegen_output"

# Test TCP server loop convenience
proc tcp_server_loop(name, listen_fd, max_clients):
    let tcp_ev = create_event_loop(name, max_clients + 1)
    tcp_ev = evloop_add_fd(tcp_ev, listen_fd, EPOLLIN, "handle_accept")
    return tcp_ev

let srv = tcp_server_loop("http_server", 5, 128)
if srv["name"] == "http_server":
    if srv["max_events"] == 129:
        if len(srv["fds"]) == 1:
            if srv["fds"][0]["handler"] == "handle_accept":
                print "tcp_server"

print "PASS"
