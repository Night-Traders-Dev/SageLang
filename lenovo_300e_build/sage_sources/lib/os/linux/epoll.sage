gc_disable()

# epoll.sage — Linux epoll event loop interface
#
# Build epoll-based event loops for high-performance I/O multiplexing.
# Generates C code for integration with kernel modules or userspace programs.

# ----- Epoll events -----
let EPOLLIN = 1
let EPOLLOUT = 4
let EPOLLRDHUP = 8192
let EPOLLPRI = 2
let EPOLLERR = 8
let EPOLLHUP = 16
let EPOLLET = 2147483648
let EPOLLONESHOT = 1073741824

# ----- Epoll operations -----
let EPOLL_CTL_ADD = 1
let EPOLL_CTL_DEL = 2
let EPOLL_CTL_MOD = 3

# ========== Event loop descriptor ==========

proc create_event_loop(name, max_events):
    let ev = {}
    ev["name"] = name
    ev["max_events"] = max_events
    ev["fds"] = []
    ev["handlers"] = []
    ev["timeout_ms"] = -1
    return ev
end

proc evloop_set_timeout(ev, ms):
    ev["timeout_ms"] = ms
    return ev
end

proc evloop_add_fd(ev, fd, events, handler_name):
    let entry = {}
    entry["fd"] = fd
    entry["events"] = events
    entry["handler"] = handler_name
    append(ev["fds"], entry)
    return ev
end

# ========== Event descriptor ==========

proc create_event(fd, event_mask):
    let e = {}
    e["fd"] = fd
    e["events"] = event_mask
    e["readable"] = false
    e["writable"] = false
    e["error"] = false
    e["hangup"] = false
    # Check flags using integer division for bit checking
    if event_mask % 2 == 1:
        e["readable"] = true
    end
    if (event_mask / 4) % 2 == 1:
        e["writable"] = true
    end
    if (event_mask / 8) % 2 == 1:
        e["error"] = true
    end
    if (event_mask / 16) % 2 == 1:
        e["hangup"] = true
    end
    return e
end

# ========== C code generation ==========

proc emit_event_loop_c(ev):
    let nl = chr(10)
    let q = chr(34)
    let name = ev["name"]
    let code = ""

    code = code + "#include <sys/epoll.h>" + nl
    code = code + "#include <stdio.h>" + nl
    code = code + "#include <unistd.h>" + nl
    code = code + "#include <errno.h>" + nl
    code = code + nl

    # Handler prototypes
    let hi = 0
    while hi < len(ev["fds"]):
        code = code + "static void " + ev["fds"][hi]["handler"] + "(int fd, uint32_t events);" + nl
        hi = hi + 1
    end
    code = code + nl

    # Event loop function
    code = code + "int " + name + "_run(void) {" + nl
    code = code + "    int epfd = epoll_create1(0);" + nl
    code = code + "    if (epfd < 0) { perror(" + q + "epoll_create1" + q + "); return -1; }" + nl
    code = code + nl
    code = code + "    struct epoll_event ev, events[" + str(ev["max_events"]) + "];" + nl
    code = code + nl

    # Register file descriptors
    let fi = 0
    while fi < len(ev["fds"]):
        let entry = ev["fds"][fi]
        code = code + "    ev.events = " + str(entry["events"]) + ";" + nl
        code = code + "    ev.data.fd = " + str(entry["fd"]) + ";" + nl
        code = code + "    epoll_ctl(epfd, EPOLL_CTL_ADD, " + str(entry["fd"]) + ", &ev);" + nl
        fi = fi + 1
    end
    code = code + nl

    # Event loop
    code = code + "    int running = 1;" + nl
    code = code + "    while (running) {" + nl
    code = code + "        int nfds = epoll_wait(epfd, events, " + str(ev["max_events"]) + ", " + str(ev["timeout_ms"]) + ");" + nl
    code = code + "        if (nfds < 0) {" + nl
    code = code + "            if (errno == EINTR) continue;" + nl
    code = code + "            break;" + nl
    code = code + "        }" + nl
    code = code + "        for (int i = 0; i < nfds; i++) {" + nl

    # Dispatch to handlers
    let di = 0
    while di < len(ev["fds"]):
        let entry2 = ev["fds"][di]
        if di == 0:
            code = code + "            if (events[i].data.fd == " + str(entry2["fd"]) + ") " + entry2["handler"] + "(events[i].data.fd, events[i].events);" + nl
        else:
            code = code + "            else if (events[i].data.fd == " + str(entry2["fd"]) + ") " + entry2["handler"] + "(events[i].data.fd, events[i].events);" + nl
        end
        di = di + 1
    end

    code = code + "        }" + nl
    code = code + "    }" + nl
    code = code + "    close(epfd);" + nl
    code = code + "    return 0;" + nl
    code = code + "}" + nl

    return code
end

# ========== Convenience ==========

proc tcp_server_loop(name, listen_fd, max_clients):
    let ev = create_event_loop(name, max_clients + 1)
    ev = evloop_add_fd(ev, listen_fd, EPOLLIN, "handle_accept")
    return ev
end
