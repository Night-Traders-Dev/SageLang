// src/net.c - Networking modules for SageLang
//
// Provides: socket, tcp, http, ssl
// Dependencies: POSIX sockets, libcurl, OpenSSL

#define _DEFAULT_SOURCE
#include "module.h"
#include "value.h"
#include "env.h"
#include "gc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>

// Networking headers
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <poll.h>

// Raw sockets
#include <net/if.h>
#include <linux/if_ether.h>

// libcurl for HTTP/HTTPS
#include <curl/curl.h>

// OpenSSL for SSL/TLS
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/bio.h>

// ============================================================================
// SOCKET MODULE - Raw POSIX sockets
// ============================================================================

// socket.create(domain, type, protocol) -> fd
// domain: "inet" | "inet6" | "unix" | "raw"
// type: "stream" | "dgram" | "raw"
// protocol: number (0 for default, IPPROTO_TCP=6, IPPROTO_UDP=17, etc.)
static Value socket_create_native(int argc, Value* args) {
    if (argc < 2) return val_number(-1);

    int domain = AF_INET;
    int type = SOCK_STREAM;
    int protocol = 0;

    if (IS_STRING(args[0])) {
        const char* d = AS_STRING(args[0]);
        if (strcmp(d, "inet6") == 0) domain = AF_INET6;
        else if (strcmp(d, "unix") == 0) domain = AF_UNIX;
        else if (strcmp(d, "raw") == 0 || strcmp(d, "packet") == 0) domain = AF_PACKET;
    }

    if (IS_STRING(args[1])) {
        const char* t = AS_STRING(args[1]);
        if (strcmp(t, "dgram") == 0) type = SOCK_DGRAM;
        else if (strcmp(t, "raw") == 0) type = SOCK_RAW;
    }

    if (argc >= 3 && IS_NUMBER(args[2]))
        protocol = (int)AS_NUMBER(args[2]);

    int fd = socket(domain, type, protocol);
    if (fd < 0) {
        fprintf(stderr, "socket.create: %s\n", strerror(errno));
        return val_number(-1);
    }
    return val_number(fd);
}

// socket.bind(fd, host, port) -> bool
static Value socket_bind_native(int argc, Value* args) {
    if (argc < 3 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]) || !IS_NUMBER(args[2]))
        return val_bool(false);

    int fd = (int)AS_NUMBER(args[0]);
    const char* host = AS_STRING(args[1]);
    int port = (int)AS_NUMBER(args[2]);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);

    if (strcmp(host, "0.0.0.0") == 0 || strcmp(host, "") == 0)
        addr.sin_addr.s_addr = INADDR_ANY;
    else
        inet_pton(AF_INET, host, &addr.sin_addr);

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "socket.bind: %s\n", strerror(errno));
        return val_bool(false);
    }
    return val_bool(true);
}

// socket.listen(fd, backlog) -> bool
static Value socket_listen_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_bool(false);
    int fd = (int)AS_NUMBER(args[0]);
    int backlog = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : 128;

    if (listen(fd, backlog) < 0) {
        fprintf(stderr, "socket.listen: %s\n", strerror(errno));
        return val_bool(false);
    }
    return val_bool(true);
}

// socket.accept(fd) -> dict {fd, host, port} or nil
static Value socket_accept_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);

    struct sockaddr_in client_addr;
    socklen_t client_len = sizeof(client_addr);
    int client_fd = accept(fd, (struct sockaddr*)&client_addr, &client_len);
    if (client_fd < 0) return val_nil();

    char ip[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &client_addr.sin_addr, ip, sizeof(ip));

    Value result = val_dict();
    dict_set(&result, "fd", val_number(client_fd));
    dict_set(&result, "host", val_string(ip));
    dict_set(&result, "port", val_number(ntohs(client_addr.sin_port)));
    return result;
}

// socket.connect(fd, host, port) -> bool
static Value socket_connect_native(int argc, Value* args) {
    if (argc < 3 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]) || !IS_NUMBER(args[2]))
        return val_bool(false);

    int fd = (int)AS_NUMBER(args[0]);
    const char* host = AS_STRING(args[1]);
    int port = (int)AS_NUMBER(args[2]);

    // Resolve hostname
    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    if (getaddrinfo(host, port_str, &hints, &res) != 0) {
        fprintf(stderr, "socket.connect: cannot resolve '%s'\n", host);
        return val_bool(false);
    }

    int r = connect(fd, res->ai_addr, res->ai_addrlen);
    freeaddrinfo(res);

    if (r < 0) {
        fprintf(stderr, "socket.connect: %s\n", strerror(errno));
        return val_bool(false);
    }
    return val_bool(true);
}

// socket.send(fd, data) -> bytes_sent
static Value socket_send_native(int argc, Value* args) {
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]))
        return val_number(-1);
    int fd = (int)AS_NUMBER(args[0]);
    const char* data = AS_STRING(args[1]);
    ssize_t sent = send(fd, data, strlen(data), 0);
    return val_number((double)sent);
}

// socket.recv(fd, maxlen) -> string or nil
static Value socket_recv_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);
    int maxlen = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : 4096;
    if (maxlen <= 0 || maxlen > 10 * 1024 * 1024) maxlen = 4096;

    char* buf = SAGE_ALLOC(maxlen + 1);
    ssize_t n = recv(fd, buf, maxlen, 0);
    if (n <= 0) {
        free(buf);
        return val_nil();
    }
    buf[n] = '\0';
    return val_string_take(buf);
}

// socket.sendto(fd, data, host, port) -> bytes_sent
static Value socket_sendto_native(int argc, Value* args) {
    if (argc < 4 || !IS_NUMBER(args[0]) || !IS_STRING(args[1])
        || !IS_STRING(args[2]) || !IS_NUMBER(args[3]))
        return val_number(-1);

    int fd = (int)AS_NUMBER(args[0]);
    const char* data = AS_STRING(args[1]);
    const char* host = AS_STRING(args[2]);
    int port = (int)AS_NUMBER(args[3]);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, host, &addr.sin_addr);

    ssize_t sent = sendto(fd, data, strlen(data), 0,
                          (struct sockaddr*)&addr, sizeof(addr));
    return val_number((double)sent);
}

// socket.recvfrom(fd, maxlen) -> dict {data, host, port} or nil
static Value socket_recvfrom_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);
    int maxlen = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : 4096;
    if (maxlen <= 0 || maxlen > 10 * 1024 * 1024) maxlen = 4096;

    char* buf = SAGE_ALLOC(maxlen + 1);
    struct sockaddr_in from_addr;
    socklen_t from_len = sizeof(from_addr);
    ssize_t n = recvfrom(fd, buf, maxlen, 0,
                         (struct sockaddr*)&from_addr, &from_len);
    if (n <= 0) { free(buf); return val_nil(); }
    buf[n] = '\0';

    char ip[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &from_addr.sin_addr, ip, sizeof(ip));

    Value result = val_dict();
    dict_set(&result, "data", val_string_take(buf));
    dict_set(&result, "host", val_string(ip));
    dict_set(&result, "port", val_number(ntohs(from_addr.sin_port)));
    return result;
}

// socket.close(fd) -> bool
static Value socket_close_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_bool(false);
    int fd = (int)AS_NUMBER(args[0]);
    return val_bool(close(fd) == 0);
}

// socket.setsockopt(fd, option, value) -> bool
// Options: "reuseaddr", "keepalive", "nodelay", "broadcast", "rcvbuf", "sndbuf", "timeout"
static Value socket_setopt_native(int argc, Value* args) {
    if (argc < 3 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]))
        return val_bool(false);

    int fd = (int)AS_NUMBER(args[0]);
    const char* opt = AS_STRING(args[1]);
    int val = IS_NUMBER(args[2]) ? (int)AS_NUMBER(args[2])
            : IS_BOOL(args[2]) ? (AS_BOOL(args[2]) ? 1 : 0) : 0;

    int level = SOL_SOCKET;
    int optname = 0;

    if (strcmp(opt, "reuseaddr") == 0) optname = SO_REUSEADDR;
    else if (strcmp(opt, "keepalive") == 0) optname = SO_KEEPALIVE;
    else if (strcmp(opt, "broadcast") == 0) optname = SO_BROADCAST;
    else if (strcmp(opt, "rcvbuf") == 0) optname = SO_RCVBUF;
    else if (strcmp(opt, "sndbuf") == 0) optname = SO_SNDBUF;
    else if (strcmp(opt, "nodelay") == 0) { level = IPPROTO_TCP; optname = TCP_NODELAY; }
    else if (strcmp(opt, "timeout") == 0) {
        struct timeval tv;
        tv.tv_sec = val / 1000;
        tv.tv_usec = (val % 1000) * 1000;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        return val_bool(true);
    }
    else return val_bool(false);

    int r = setsockopt(fd, level, optname, &val, sizeof(val));
    return val_bool(r == 0);
}

// socket.poll(fd, timeout_ms) -> "read" | "write" | "both" | "error" | "timeout"
static Value socket_poll_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_string("error");
    int fd = (int)AS_NUMBER(args[0]);
    int timeout = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : -1;

    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN | POLLOUT;
    pfd.revents = 0;

    int r = poll(&pfd, 1, timeout);
    if (r < 0) return val_string("error");
    if (r == 0) return val_string("timeout");
    if ((pfd.revents & POLLIN) && (pfd.revents & POLLOUT)) return val_string("both");
    if (pfd.revents & POLLIN) return val_string("read");
    if (pfd.revents & POLLOUT) return val_string("write");
    return val_string("error");
}

// socket.getpeername(fd) -> dict {host, port} or nil
static Value socket_getpeername_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);

    struct sockaddr_in addr;
    socklen_t len = sizeof(addr);
    if (getpeername(fd, (struct sockaddr*)&addr, &len) < 0) return val_nil();

    char ip[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &addr.sin_addr, ip, sizeof(ip));

    Value result = val_dict();
    dict_set(&result, "host", val_string(ip));
    dict_set(&result, "port", val_number(ntohs(addr.sin_port)));
    return result;
}

// socket.resolve(hostname) -> ip string or nil
static Value socket_resolve_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    const char* host = AS_STRING(args[0]);

    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    if (getaddrinfo(host, NULL, &hints, &res) != 0) return val_nil();

    char ip[INET_ADDRSTRLEN];
    struct sockaddr_in* addr = (struct sockaddr_in*)res->ai_addr;
    inet_ntop(AF_INET, &addr->sin_addr, ip, sizeof(ip));
    freeaddrinfo(res);

    return val_string(ip);
}

// socket.nonblock(fd, enable) -> bool
static Value socket_nonblock_native(int argc, Value* args) {
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_BOOL(args[1]))
        return val_bool(false);
    int fd = (int)AS_NUMBER(args[0]);
    bool enable = AS_BOOL(args[1]);

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return val_bool(false);

    if (enable) flags |= O_NONBLOCK;
    else flags &= ~O_NONBLOCK;

    return val_bool(fcntl(fd, F_SETFL, flags) == 0);
}

Module* create_socket_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "socket");
    Environment* e = m->env;

    env_define(e, "create", 6, val_native(socket_create_native));
    env_define(e, "bind", 4, val_native(socket_bind_native));
    env_define(e, "listen", 6, val_native(socket_listen_native));
    env_define(e, "accept", 6, val_native(socket_accept_native));
    env_define(e, "connect", 7, val_native(socket_connect_native));
    env_define(e, "send", 4, val_native(socket_send_native));
    env_define(e, "recv", 4, val_native(socket_recv_native));
    env_define(e, "sendto", 6, val_native(socket_sendto_native));
    env_define(e, "recvfrom", 8, val_native(socket_recvfrom_native));
    env_define(e, "close", 5, val_native(socket_close_native));
    env_define(e, "setopt", 6, val_native(socket_setopt_native));
    env_define(e, "poll", 4, val_native(socket_poll_native));
    env_define(e, "getpeername", 11, val_native(socket_getpeername_native));
    env_define(e, "resolve", 7, val_native(socket_resolve_native));
    env_define(e, "nonblock", 8, val_native(socket_nonblock_native));

    // Constants
    env_define(e, "AF_INET", 7, val_number(AF_INET));
    env_define(e, "AF_INET6", 8, val_number(AF_INET6));
    env_define(e, "SOCK_STREAM", 11, val_number(SOCK_STREAM));
    env_define(e, "SOCK_DGRAM", 10, val_number(SOCK_DGRAM));
    env_define(e, "SOCK_RAW", 8, val_number(SOCK_RAW));
    env_define(e, "IPPROTO_TCP", 11, val_number(IPPROTO_TCP));
    env_define(e, "IPPROTO_UDP", 11, val_number(IPPROTO_UDP));

    return m;
}

// ============================================================================
// TCP MODULE - High-level TCP client/server
// ============================================================================

// tcp.connect(host, port) -> fd or -1
static Value tcp_connect_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_NUMBER(args[1]))
        return val_number(-1);

    const char* host = AS_STRING(args[0]);
    int port = (int)AS_NUMBER(args[1]);

    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    if (getaddrinfo(host, port_str, &hints, &res) != 0) {
        fprintf(stderr, "tcp.connect: cannot resolve '%s'\n", host);
        return val_number(-1);
    }

    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) { freeaddrinfo(res); return val_number(-1); }

    if (connect(fd, res->ai_addr, res->ai_addrlen) < 0) {
        fprintf(stderr, "tcp.connect: %s\n", strerror(errno));
        close(fd);
        freeaddrinfo(res);
        return val_number(-1);
    }

    freeaddrinfo(res);
    return val_number(fd);
}

// tcp.listen(host, port) -> server_fd or -1
static Value tcp_listen_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_NUMBER(args[1]))
        return val_number(-1);

    const char* host = AS_STRING(args[0]);
    int port = (int)AS_NUMBER(args[1]);
    int backlog = (argc >= 3 && IS_NUMBER(args[2])) ? (int)AS_NUMBER(args[2]) : 128;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return val_number(-1);

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    if (strcmp(host, "0.0.0.0") == 0 || strcmp(host, "") == 0)
        addr.sin_addr.s_addr = INADDR_ANY;
    else
        inet_pton(AF_INET, host, &addr.sin_addr);

    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "tcp.listen: bind: %s\n", strerror(errno));
        close(fd);
        return val_number(-1);
    }

    if (listen(fd, backlog) < 0) {
        fprintf(stderr, "tcp.listen: listen: %s\n", strerror(errno));
        close(fd);
        return val_number(-1);
    }

    return val_number(fd);
}

// tcp.accept(server_fd) -> dict {fd, host, port} or nil
static Value tcp_accept_native(int argc, Value* args) {
    return socket_accept_native(argc, args);
}

// tcp.send(fd, data) -> bytes_sent
static Value tcp_send_native(int argc, Value* args) {
    return socket_send_native(argc, args);
}

// tcp.recv(fd, maxlen) -> string or nil
static Value tcp_recv_native(int argc, Value* args) {
    return socket_recv_native(argc, args);
}

// tcp.close(fd)
static Value tcp_close_native(int argc, Value* args) {
    return socket_close_native(argc, args);
}

// tcp.sendall(fd, data) -> bool (sends entire buffer, retrying as needed)
static Value tcp_sendall_native(int argc, Value* args) {
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]))
        return val_bool(false);

    int fd = (int)AS_NUMBER(args[0]);
    const char* data = AS_STRING(args[1]);
    size_t total = strlen(data);
    size_t sent = 0;

    while (sent < total) {
        ssize_t n = send(fd, data + sent, total - sent, 0);
        if (n <= 0) return val_bool(false);
        sent += n;
    }
    return val_bool(true);
}

// tcp.recvall(fd, length) -> string or nil (reads exactly length bytes)
static Value tcp_recvall_native(int argc, Value* args) {
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1]))
        return val_nil();

    int fd = (int)AS_NUMBER(args[0]);
    int length = (int)AS_NUMBER(args[1]);
    if (length <= 0 || length > 10 * 1024 * 1024) return val_nil();

    char* buf = SAGE_ALLOC(length + 1);
    int received = 0;

    while (received < length) {
        ssize_t n = recv(fd, buf + received, length - received, 0);
        if (n <= 0) { free(buf); return val_nil(); }
        received += n;
    }
    buf[length] = '\0';
    return val_string_take(buf);
}

// tcp.recvline(fd) -> string or nil (reads until \n)
static Value tcp_recvline_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);
    int maxlen = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : 4096;
    if (maxlen <= 0 || maxlen > 10 * 1024 * 1024) maxlen = 4096;

    char* buf = SAGE_ALLOC(maxlen + 1);
    int pos = 0;
    char c;

    while (pos < maxlen) {
        ssize_t n = recv(fd, &c, 1, 0);
        if (n <= 0) break;
        buf[pos++] = c;
        if (c == '\n') break;
    }

    if (pos == 0) { free(buf); return val_nil(); }
    buf[pos] = '\0';
    return val_string_take(buf);
}

Module* create_tcp_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "tcp");
    Environment* e = m->env;

    env_define(e, "connect", 7, val_native(tcp_connect_native));
    env_define(e, "listen", 6, val_native(tcp_listen_native));
    env_define(e, "accept", 6, val_native(tcp_accept_native));
    env_define(e, "send", 4, val_native(tcp_send_native));
    env_define(e, "recv", 4, val_native(tcp_recv_native));
    env_define(e, "sendall", 7, val_native(tcp_sendall_native));
    env_define(e, "recvall", 7, val_native(tcp_recvall_native));
    env_define(e, "recvline", 8, val_native(tcp_recvline_native));
    env_define(e, "close", 5, val_native(tcp_close_native));

    return m;
}

// ============================================================================
// HTTP MODULE - HTTP/HTTPS client via libcurl
// ============================================================================

static int s_curl_initialized = 0;

static void ensure_curl_init(void) {
    if (!s_curl_initialized) {
        curl_global_init(CURL_GLOBAL_ALL);
        s_curl_initialized = 1;
    }
}

// Write callback for libcurl
typedef struct {
    char* data;
    size_t size;
    size_t capacity;
} CurlBuffer;

static size_t curl_write_cb(void* ptr, size_t size, size_t nmemb, void* userp) {
    CurlBuffer* buf = (CurlBuffer*)userp;
    if (nmemb != 0 && size > SIZE_MAX / nmemb) return 0;  // overflow check
    size_t total = size * nmemb;

    if (buf->size + total >= buf->capacity) {
        buf->capacity = (buf->size + total) * 2 + 1;
        char* tmp = realloc(buf->data, buf->capacity);
        if (!tmp) return 0;
        buf->data = tmp;
    }

    memcpy(buf->data + buf->size, ptr, total);
    buf->size += total;
    buf->data[buf->size] = '\0';
    return total;
}

// Header callback for libcurl
static size_t curl_header_cb(void* ptr, size_t size, size_t nmemb, void* userp) {
    CurlBuffer* buf = (CurlBuffer*)userp;
    if (nmemb != 0 && size > SIZE_MAX / nmemb) return 0;
    size_t total = size * nmemb;

    if (buf->size + total >= buf->capacity) {
        buf->capacity = (buf->size + total) * 2 + 1;
        char* tmp = realloc(buf->data, buf->capacity);
        if (!tmp) return 0;
        buf->data = tmp;
    }

    memcpy(buf->data + buf->size, ptr, total);
    buf->size += total;
    buf->data[buf->size] = '\0';
    return total;
}

// Common curl setup: applies headers dict, timeout, etc.
static void curl_apply_options(CURL* curl, Value* options) {
    if (!options || !IS_DICT(*options)) return;

    Value timeout_val = dict_get(options, "timeout");
    if (IS_NUMBER(timeout_val))
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, (long)AS_NUMBER(timeout_val));

    Value follow_val = dict_get(options, "follow");
    if (IS_BOOL(follow_val) && AS_BOOL(follow_val))
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

    Value verify_val = dict_get(options, "verify");
    if (IS_BOOL(verify_val) && !AS_BOOL(verify_val)) {
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 0L);
    }

    Value useragent_val = dict_get(options, "user_agent");
    if (IS_STRING(useragent_val))
        curl_easy_setopt(curl, CURLOPT_USERAGENT, AS_STRING(useragent_val));

    Value cainfo_val = dict_get(options, "cainfo");
    if (IS_STRING(cainfo_val))
        curl_easy_setopt(curl, CURLOPT_CAINFO, AS_STRING(cainfo_val));
}

// Build curl headers from a dict
static struct curl_slist* curl_build_headers(Value* options) {
    if (!options || !IS_DICT(*options)) return NULL;

    Value headers_val = dict_get(options, "headers");
    if (!IS_DICT(headers_val)) return NULL;

    // Get keys from headers dict
    Value keys = dict_keys(&headers_val);
    if (!IS_ARRAY(keys)) return NULL;

    struct curl_slist* slist = NULL;
    ArrayValue* arr = AS_ARRAY(keys);
    for (int i = 0; i < arr->count; i++) {
        if (!IS_STRING(arr->elements[i])) continue;
        const char* key = AS_STRING(arr->elements[i]);
        Value val = dict_get(&headers_val, key);
        if (!IS_STRING(val)) continue;

        char header[1024];
        snprintf(header, sizeof(header), "%s: %s", key, AS_STRING(val));
        slist = curl_slist_append(slist, header);
    }
    return slist;
}

// Perform a curl request and return dict {status, body, headers}
static Value curl_perform_request(CURL* curl) {
    CurlBuffer body_buf = {SAGE_ALLOC(1024), 0, 1024};
    CurlBuffer header_buf = {SAGE_ALLOC(1024), 0, 1024};
    body_buf.data[0] = '\0';
    header_buf.data[0] = '\0';

    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &body_buf);
    curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, curl_header_cb);
    curl_easy_setopt(curl, CURLOPT_HEADERDATA, &header_buf);

    CURLcode res = curl_easy_perform(curl);

    Value result = val_dict();
    if (res != CURLE_OK) {
        dict_set(&result, "error", val_string(curl_easy_strerror(res)));
        dict_set(&result, "status", val_number(0));
        dict_set(&result, "body", val_string(""));
        free(body_buf.data);
        free(header_buf.data);
        return result;
    }

    long status_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status_code);

    dict_set(&result, "status", val_number((double)status_code));
    dict_set(&result, "body", val_string_take(body_buf.data));
    dict_set(&result, "headers", val_string_take(header_buf.data));
    return result;
}

// http.get(url, options?) -> dict {status, body, headers}
static Value http_get_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    curl_easy_setopt(curl, CURLOPT_URL, AS_STRING(args[0]));
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "SageLang/" SAGE_VERSION_STR);

    if (argc >= 2) curl_apply_options(curl, &args[1]);

    struct curl_slist* headers = NULL;
    if (argc >= 2) headers = curl_build_headers(&args[1]);
    if (headers) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    Value result = curl_perform_request(curl);

    if (headers) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
}

// http.post(url, body, options?) -> dict {status, body, headers}
static Value http_post_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    curl_easy_setopt(curl, CURLOPT_URL, AS_STRING(args[0]));
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, AS_STRING(args[1]));
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "SageLang/" SAGE_VERSION_STR);

    if (argc >= 3) curl_apply_options(curl, &args[2]);

    struct curl_slist* headers = NULL;
    if (argc >= 3) headers = curl_build_headers(&args[2]);
    if (headers) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    Value result = curl_perform_request(curl);

    if (headers) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
}

// http.put(url, body, options?) -> dict {status, body, headers}
static Value http_put_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    curl_easy_setopt(curl, CURLOPT_URL, AS_STRING(args[0]));
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PUT");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, AS_STRING(args[1]));
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "SageLang/" SAGE_VERSION_STR);

    if (argc >= 3) curl_apply_options(curl, &args[2]);

    struct curl_slist* headers = NULL;
    if (argc >= 3) headers = curl_build_headers(&args[2]);
    if (headers) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    Value result = curl_perform_request(curl);

    if (headers) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
}

// http.delete(url, options?) -> dict {status, body, headers}
static Value http_delete_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    curl_easy_setopt(curl, CURLOPT_URL, AS_STRING(args[0]));
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "SageLang/" SAGE_VERSION_STR);

    if (argc >= 2) curl_apply_options(curl, &args[1]);

    struct curl_slist* headers = NULL;
    if (argc >= 2) headers = curl_build_headers(&args[1]);
    if (headers) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    Value result = curl_perform_request(curl);

    if (headers) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
}

// http.patch(url, body, options?) -> dict {status, body, headers}
static Value http_patch_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    curl_easy_setopt(curl, CURLOPT_URL, AS_STRING(args[0]));
    curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "PATCH");
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, AS_STRING(args[1]));
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "SageLang/" SAGE_VERSION_STR);

    if (argc >= 3) curl_apply_options(curl, &args[2]);

    struct curl_slist* headers = NULL;
    if (argc >= 3) headers = curl_build_headers(&args[2]);
    if (headers) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    Value result = curl_perform_request(curl);

    if (headers) curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
    return result;
}

// http.head(url, options?) -> dict {status, headers}
static Value http_head_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    curl_easy_setopt(curl, CURLOPT_URL, AS_STRING(args[0]));
    curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "SageLang/" SAGE_VERSION_STR);

    if (argc >= 2) curl_apply_options(curl, &args[1]);

    Value result = curl_perform_request(curl);

    curl_easy_cleanup(curl);
    return result;
}

// http.download(url, filepath, options?) -> bool
static Value http_download_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1]))
        return val_bool(false);
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_bool(false);

    FILE* fp = fopen(AS_STRING(args[1]), "wb");
    if (!fp) { curl_easy_cleanup(curl); return val_bool(false); }

    curl_easy_setopt(curl, CURLOPT_URL, AS_STRING(args[0]));
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, fp);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "SageLang/" SAGE_VERSION_STR);

    if (argc >= 3) curl_apply_options(curl, &args[2]);

    CURLcode res = curl_easy_perform(curl);
    fclose(fp);
    curl_easy_cleanup(curl);

    return val_bool(res == CURLE_OK);
}

// http.escape(string) -> url-encoded string
static Value http_escape_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    char* escaped = curl_easy_escape(curl, AS_STRING(args[0]), 0);
    Value result = val_string(escaped);
    curl_free(escaped);
    curl_easy_cleanup(curl);
    return result;
}

// http.unescape(string) -> url-decoded string
static Value http_unescape_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    ensure_curl_init();

    CURL* curl = curl_easy_init();
    if (!curl) return val_nil();

    int decoded_len;
    char* decoded = curl_easy_unescape(curl, AS_STRING(args[0]), 0, &decoded_len);
    Value result = val_string(decoded);
    curl_free(decoded);
    curl_easy_cleanup(curl);
    return result;
}

Module* create_http_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "http");
    Environment* e = m->env;

    env_define(e, "get", 3, val_native(http_get_native));
    env_define(e, "post", 4, val_native(http_post_native));
    env_define(e, "put", 3, val_native(http_put_native));
    env_define(e, "delete", 6, val_native(http_delete_native));
    env_define(e, "patch", 5, val_native(http_patch_native));
    env_define(e, "head", 4, val_native(http_head_native));
    env_define(e, "download", 8, val_native(http_download_native));
    env_define(e, "escape", 6, val_native(http_escape_native));
    env_define(e, "unescape", 8, val_native(http_unescape_native));

    return m;
}

// ============================================================================
// SSL MODULE - SSL/TLS via OpenSSL
// ============================================================================

static int s_ssl_initialized = 0;

static void ensure_ssl_init(void) {
    if (!s_ssl_initialized) {
        SSL_library_init();
        SSL_load_error_strings();
        OpenSSL_add_all_algorithms();
        s_ssl_initialized = 1;
    }
}

// SSL handles stored as VAL_POINTER to avoid 64-bit pointer truncation in double.

// Helper to extract a pointer from a VAL_POINTER arg, returns NULL on type mismatch.
static void* ssl_get_handle(Value v) {
    if (v.type == VAL_POINTER) return v.as.pointer->ptr;
    // Legacy fallback: accept number for backwards compatibility
    if (IS_NUMBER(v)) return (void*)(uintptr_t)AS_NUMBER(v);
    return NULL;
}

// ssl.context(method?) -> handle
// method: "tls" (default), "tls_client", "tls_server"
static Value ssl_context_native(int argc, Value* args) {
    ensure_ssl_init();

    const SSL_METHOD* method = TLS_method();
    if (argc >= 1 && IS_STRING(args[0])) {
        const char* m = AS_STRING(args[0]);
        if (strcmp(m, "tls_client") == 0) method = TLS_client_method();
        else if (strcmp(m, "tls_server") == 0) method = TLS_server_method();
    }

    SSL_CTX* ctx = SSL_CTX_new(method);
    if (!ctx) return val_nil();

    return val_pointer(ctx, 0, 0);
}

// ssl.load_cert(ctx_handle, certfile, keyfile) -> bool
static Value ssl_load_cert_native(int argc, Value* args) {
    if (argc < 3 || !IS_STRING(args[1]) || !IS_STRING(args[2]))
        return val_bool(false);

    SSL_CTX* ctx = (SSL_CTX*)ssl_get_handle(args[0]);
    if (!ctx) return val_bool(false);
    const char* certfile = AS_STRING(args[1]);
    const char* keyfile = AS_STRING(args[2]);

    if (SSL_CTX_use_certificate_file(ctx, certfile, SSL_FILETYPE_PEM) <= 0)
        return val_bool(false);
    if (SSL_CTX_use_PrivateKey_file(ctx, keyfile, SSL_FILETYPE_PEM) <= 0)
        return val_bool(false);
    if (!SSL_CTX_check_private_key(ctx))
        return val_bool(false);

    return val_bool(true);
}

// ssl.wrap(ctx_handle, fd) -> ssl_handle or nil
static Value ssl_wrap_native(int argc, Value* args) {
    if (argc < 2 || !IS_NUMBER(args[1]))
        return val_nil();

    SSL_CTX* ctx = (SSL_CTX*)ssl_get_handle(args[0]);
    if (!ctx) return val_nil();
    int fd = (int)AS_NUMBER(args[1]);

    SSL* ssl = SSL_new(ctx);
    if (!ssl) return val_nil();

    SSL_set_fd(ssl, fd);
    return val_pointer(ssl, 0, 0);
}

// ssl.connect(ssl_handle) -> bool (client handshake)
static Value ssl_connect_native(int argc, Value* args) {
    if (argc < 1) return val_bool(false);
    SSL* ssl = (SSL*)ssl_get_handle(args[0]);
    if (!ssl) return val_bool(false);

    // Set SNI hostname if provided
    if (argc >= 2 && IS_STRING(args[1]))
        SSL_set_tlsext_host_name(ssl, AS_STRING(args[1]));

    int r = SSL_connect(ssl);
    return val_bool(r == 1);
}

// ssl.accept(ssl_handle) -> bool (server handshake)
static Value ssl_accept_native(int argc, Value* args) {
    if (argc < 1) return val_bool(false);
    SSL* ssl = (SSL*)ssl_get_handle(args[0]);
    if (!ssl) return val_bool(false);
    return val_bool(SSL_accept(ssl) == 1);
}

// ssl.send(ssl_handle, data) -> bytes_sent
static Value ssl_send_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[1]))
        return val_number(-1);
    SSL* ssl = (SSL*)ssl_get_handle(args[0]);
    if (!ssl) return val_number(-1);
    const char* data = AS_STRING(args[1]);
    int n = SSL_write(ssl, data, strlen(data));
    return val_number((double)n);
}

// ssl.recv(ssl_handle, maxlen?) -> string or nil
static Value ssl_recv_native(int argc, Value* args) {
    if (argc < 1) return val_nil();
    SSL* ssl = (SSL*)ssl_get_handle(args[0]);
    if (!ssl) return val_nil();
    int maxlen = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : 4096;
    if (maxlen <= 0 || maxlen > 10 * 1024 * 1024) maxlen = 4096;

    char* buf = SAGE_ALLOC(maxlen + 1);
    int n = SSL_read(ssl, buf, maxlen);
    if (n <= 0) { free(buf); return val_nil(); }
    buf[n] = '\0';
    return val_string_take(buf);
}

// ssl.shutdown(ssl_handle) -> bool
static Value ssl_shutdown_native(int argc, Value* args) {
    if (argc < 1) return val_bool(false);
    SSL* ssl = (SSL*)ssl_get_handle(args[0]);
    if (!ssl) return val_bool(false);
    SSL_shutdown(ssl);
    return val_bool(true);
}

// ssl.free(ssl_handle) — nullifies the pointer to prevent double-free
static Value ssl_free_native(int argc, Value* args) {
    if (argc < 1) return val_nil();
    if (args[0].type == VAL_POINTER && args[0].as.pointer->ptr != NULL) {
        SSL_free((SSL*)args[0].as.pointer->ptr);
        args[0].as.pointer->ptr = NULL;  // Prevent double-free
    }
    return val_nil();
}

// ssl.free_context(ctx_handle) — nullifies the pointer to prevent double-free
static Value ssl_free_context_native(int argc, Value* args) {
    if (argc < 1) return val_nil();
    if (args[0].type == VAL_POINTER && args[0].as.pointer->ptr != NULL) {
        SSL_CTX_free((SSL_CTX*)args[0].as.pointer->ptr);
        args[0].as.pointer->ptr = NULL;  // Prevent double-free
    }
    return val_nil();
}

// ssl.error(ssl_handle) -> error string
static Value ssl_error_native(int argc, Value* args) {
    (void)argc; (void)args;
    unsigned long err = ERR_get_error();
    if (err == 0) return val_string("");
    char buf[256];
    ERR_error_string_n(err, buf, sizeof(buf));
    return val_string(buf);
}

// ssl.peer_cert(ssl_handle) -> dict {subject, issuer} or nil
static Value ssl_peer_cert_native(int argc, Value* args) {
    if (argc < 1) return val_nil();
    SSL* ssl = (SSL*)ssl_get_handle(args[0]);
    if (!ssl) return val_nil();

    X509* cert = SSL_get_peer_certificate(ssl);
    if (!cert) return val_nil();

    char subject[256], issuer[256];
    X509_NAME_oneline(X509_get_subject_name(cert), subject, sizeof(subject));
    X509_NAME_oneline(X509_get_issuer_name(cert), issuer, sizeof(issuer));
    X509_free(cert);

    Value result = val_dict();
    dict_set(&result, "subject", val_string(subject));
    dict_set(&result, "issuer", val_string(issuer));
    return result;
}

// ssl.set_verify(ctx_handle, mode) -> nil
// mode: "none", "peer", "fail_if_no_cert"
static Value ssl_set_verify_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[1]))
        return val_nil();

    SSL_CTX* ctx = (SSL_CTX*)ssl_get_handle(args[0]);
    if (!ctx) return val_nil();
    const char* mode = AS_STRING(args[1]);

    int verify_mode = SSL_VERIFY_NONE;
    if (strcmp(mode, "peer") == 0) verify_mode = SSL_VERIFY_PEER;
    else if (strcmp(mode, "fail_if_no_cert") == 0)
        verify_mode = SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT;

    SSL_CTX_set_verify(ctx, verify_mode, NULL);
    return val_nil();
}

Module* create_ssl_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "ssl");
    Environment* e = m->env;

    env_define(e, "context", 7, val_native(ssl_context_native));
    env_define(e, "load_cert", 9, val_native(ssl_load_cert_native));
    env_define(e, "wrap", 4, val_native(ssl_wrap_native));
    env_define(e, "connect", 7, val_native(ssl_connect_native));
    env_define(e, "accept", 6, val_native(ssl_accept_native));
    env_define(e, "send", 4, val_native(ssl_send_native));
    env_define(e, "recv", 4, val_native(ssl_recv_native));
    env_define(e, "shutdown", 8, val_native(ssl_shutdown_native));
    env_define(e, "free", 4, val_native(ssl_free_native));
    env_define(e, "free_context", 12, val_native(ssl_free_context_native));
    env_define(e, "error", 5, val_native(ssl_error_native));
    env_define(e, "peer_cert", 9, val_native(ssl_peer_cert_native));
    env_define(e, "set_verify", 10, val_native(ssl_set_verify_native));

    return m;
}
