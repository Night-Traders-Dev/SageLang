// src/net.c - Networking modules for SageLang
//
// Provides: socket, tcp, http, ssl
// Dependencies: POSIX sockets, libcurl, OpenSSL

#define _DEFAULT_SOURCE
#include "module.h"
#include "value.h"
#include "env.h"
#include "gc.h"
#include "interpreter.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <math.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <poll.h>
#include <pthread.h>

// Networking headers
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>

#ifndef SAGE_NO_NET
#include <curl/curl.h>
#if LIBCURL_VERSION_NUM >= 0x073E00
#include <curl/urlapi.h>
#endif
#endif

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

static int net_sandbox_denied(void) {
    if (!interpreter_sandbox_mode()) return 0;
    fprintf(stderr, "Sandbox denied capability: network\n");
    return 1;
}

static int valid_port(int port) {
    return port >= 0 && port <= 65535;
}

static int checked_int(double value, int minimum, int maximum, int* out) {
    if (!isfinite(value) || floor(value) != value ||
        value < (double)minimum || value > (double)maximum) return 0;
    if (out != NULL) *out = (int)value;
    return 1;
}

static int resolve_endpoint(const char* host, int port, int socktype, int passive,
                            struct sockaddr_storage* address, socklen_t* address_len) {
    if (net_sandbox_denied()) return -1;
    if (!host || !valid_port(port) || !address || !address_len) return -1;
    char service[16];
    snprintf(service, sizeof(service), "%d", port);

    const char* node = host;
    if (passive && (strcmp(host, "*") == 0 || host[0] == '\0')) node = NULL;

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = socktype;
    hints.ai_flags = passive ? AI_PASSIVE : 0;

    struct addrinfo* results = NULL;
    if (getaddrinfo(node, service, &hints, &results) != 0 || !results) return -1;

    memcpy(address, results->ai_addr, results->ai_addrlen);
    *address_len = results->ai_addrlen;
    freeaddrinfo(results);
    return 0;
}

// ========== SOCKET MODULE - Raw POSIX Sockets ==========

static Value socket_create_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_number(-1);
    if (argc < 3 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1]) || !IS_NUMBER(args[2]))
        return val_number(-1);
    int domain;
    int type;
    int protocol;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &domain) ||
        !checked_int(AS_NUMBER(args[1]), 0, INT_MAX, &type) ||
        !checked_int(AS_NUMBER(args[2]), 0, INT_MAX, &protocol))
        return val_number(-1);
    int fd = socket(domain, type, protocol);
    return val_number(fd);
}

static Value socket_bind_native(int argc, Value* args) {
    if (argc < 3 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]) || !IS_NUMBER(args[2]))
        return val_bool(0);

    int fd;
    int port;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &fd) ||
        !checked_int(AS_NUMBER(args[2]), 0, 65535, &port)) return val_bool(0);
    struct sockaddr_storage address;
    socklen_t address_len = 0;
    if (resolve_endpoint(AS_STRING(args[1]), port, SOCK_STREAM, 1, &address, &address_len) < 0)
        return val_bool(0);

    int result;
    do {
        result = bind(fd, (struct sockaddr*)&address, address_len);
    } while (result < 0 && errno == EINTR);
    return val_bool(result == 0);
}

static Value socket_listen_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_bool(0);
    if (argc < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    int fd;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &fd)) return val_bool(0);
    int backlog = 128;
    if (argc >= 2 && IS_NUMBER(args[1]) &&
        !checked_int(AS_NUMBER(args[1]), 0, INT_MAX, &backlog)) return val_bool(0);
    int result;
    do {
        result = listen(fd, backlog);
    } while (result < 0 && errno == EINTR);
    return val_bool(result == 0);
}

static Value socket_accept_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_number(-1);
    if (argc < 1 || !IS_NUMBER(args[0])) return val_number(-1);
    int fd;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &fd)) return val_number(-1);
    int client;
    do {
        client = accept(fd, NULL, NULL);
    } while (client < 0 && errno == EINTR);
    return val_number(client);
}

static Value socket_connect_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_bool(0);
    if (argc < 3 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]) || !IS_NUMBER(args[2]))
        return val_bool(0);

    int fd;
    int port;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &fd) ||
        !checked_int(AS_NUMBER(args[2]), 0, 65535, &port)) return val_bool(0);
    struct sockaddr_storage address;
    socklen_t address_len = 0;
    if (resolve_endpoint(AS_STRING(args[1]), port, SOCK_STREAM, 0,
                         &address, &address_len) < 0)
        return val_bool(0);

    int result;
    do {
        result = connect(fd, (struct sockaddr*)&address, address_len);
    } while (result < 0 && errno == EINTR);
    return val_bool(result == 0);
}

static Value socket_send_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_number(-1);
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_STRING(args[1])) return val_number(-1);
    int fd;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &fd)) return val_number(-1);
    ssize_t sent;
    do {
        sent = send(fd, AS_STRING(args[1]), SAGE_STRING_LEN(args[1]), MSG_NOSIGNAL);
    } while (sent < 0 && errno == EINTR);
    return val_number((double)sent);
}

static Value socket_recv_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_nil();
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    int fd;
    int length;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &fd) ||
        !checked_int(AS_NUMBER(args[1]), 1, SAGE_MAX_READ_SIZE, &length)) return val_nil();

    char* buffer = SAGE_ALLOC((size_t)length + 1);
    ssize_t received;
    do {
        received = recv(fd, buffer, (size_t)length, 0);
    } while (received < 0 && errno == EINTR);
    if (received <= 0) {
        free(buffer);
        return val_nil();
    }
    buffer[received] = '\0';
    return val_string_take_len(buffer, (int)received);
}

static Value socket_sendto_native(int argc, Value* args) {
    if (argc < 4 || !IS_NUMBER(args[0]) || !IS_STRING(args[1]) || !IS_STRING(args[2]) || !IS_NUMBER(args[3]))
        return val_number(-1);

    struct sockaddr_storage address;
    socklen_t address_len = 0;
    if (resolve_endpoint(AS_STRING(args[2]), (int)AS_NUMBER(args[3]), SOCK_DGRAM, 0,
                         &address, &address_len) < 0)
        return val_number(-1);

    ssize_t sent;
    do {
        sent = sendto((int)AS_NUMBER(args[0]), AS_STRING(args[1]), SAGE_STRING_LEN(args[1]),
                      MSG_NOSIGNAL, (struct sockaddr*)&address, address_len);
    } while (sent < 0 && errno == EINTR);
    return val_number((double)sent);
}

static Value socket_recvfrom_native(int argc, Value* args) {
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    int length = (int)AS_NUMBER(args[1]);
    if (length <= 0 || length > SAGE_MAX_READ_SIZE) return val_nil();

    char* buffer = SAGE_ALLOC((size_t)length + 1);
    struct sockaddr_storage address;
    socklen_t address_len = sizeof(address);
    ssize_t received;
    do {
        received = recvfrom((int)AS_NUMBER(args[0]), buffer, (size_t)length, 0,
                            (struct sockaddr*)&address, &address_len);
    } while (received < 0 && errno == EINTR);
    if (received < 0) {
        free(buffer);
        return val_nil();
    }

    buffer[received] = '\0';
    char host[NI_MAXHOST];
    char service[NI_MAXSERV];
    memset(host, 0, sizeof(host));
    memset(service, 0, sizeof(service));
    int port = 0;
    if (getnameinfo((struct sockaddr*)&address, address_len, host, sizeof(host),
                    service, sizeof(service), NI_NUMERICHOST | NI_NUMERICSERV) == 0) {
        port = atoi(service);
    }

    gc_pin();
    Value result = val_dict();
    dict_set(&result, "data", val_string_len(buffer, (int)received));
    dict_set(&result, "host", val_string(host));
    dict_set(&result, "port", val_number(port));
    gc_unpin();
    free(buffer);
    return result;
}

static Value socket_close_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_nil();
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    close((int)AS_NUMBER(args[0]));
    return val_nil();
}

static Value socket_setopt_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_bool(0);
    if (argc < 4 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1]) || !IS_NUMBER(args[2]))
        return val_bool(0);
    int value = 0;
    if (IS_NUMBER(args[3])) value = (int)AS_NUMBER(args[3]);
    else if (IS_BOOL(args[3])) value = AS_BOOL(args[3]) ? 1 : 0;
    else return val_bool(0);
    int result = setsockopt((int)AS_NUMBER(args[0]), (int)AS_NUMBER(args[1]),
                            (int)AS_NUMBER(args[2]), &value, sizeof(value));
    return val_bool(result == 0);
}

static Value socket_poll_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_nil();
    if (argc < 1 || !IS_ARRAY(args[0])) return val_nil();
    ArrayValue* input = AS_ARRAY(args[0]);
    if (input->count < 0 || input->count > 65536) return val_nil();

    struct pollfd* descriptors = SAGE_ALLOC(sizeof(struct pollfd) * (size_t)(input->count > 0 ? input->count : 1));
    Value* inputs = input->count > 0 ? SAGE_ALLOC(sizeof(Value) * (size_t)input->count) : NULL;
    int valid = 1;
    int index = 0;
    while (index < input->count) {
        Value item = input->elements[index];
        Value fd_value = IS_DICT(item) ? dict_get(&item, "fd") : item;
        if (!IS_NUMBER(fd_value)) {
            valid = 0;
            break;
        }
        short events = POLLIN;
        if (IS_DICT(item) && dict_has(&item, "events")) {
            Value requested = dict_get(&item, "events");
            if (!IS_NUMBER(requested)) {
                valid = 0;
                break;
            }
            events = (short)AS_NUMBER(requested);
        }
        descriptors[index].fd = (int)AS_NUMBER(fd_value);
        descriptors[index].events = events;
        descriptors[index].revents = 0;
        if (inputs) inputs[index] = item;
        index++;
    }

    int timeout_ms = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : 0;
    int result = valid ? poll(descriptors, (nfds_t)input->count, timeout_ms) : -1;
    if (result < 0) {
        free(descriptors);
        free(inputs);
        return val_nil();
    }

    gc_pin();
    Value output = val_array();
    index = 0;
    while (index < input->count) {
        Value item = val_dict();
        Value original = inputs[index];
        dict_set(&item, "fd", IS_DICT(original) ? dict_get(&original, "fd") : original);
        int revents = descriptors[index].revents;
        dict_set(&item, "events", val_number(revents));
        dict_set(&item, "readable", val_bool((revents & POLLIN) != 0));
        dict_set(&item, "writable", val_bool((revents & POLLOUT) != 0));
        dict_set(&item, "error", val_bool((revents & (POLLERR | POLLNVAL)) != 0));
        dict_set(&item, "hangup", val_bool((revents & POLLHUP) != 0));
        array_push(&output, item);
        index++;
    }
    gc_unpin();
    free(descriptors);
    free(inputs);
    return output;
}

static Value socket_resolve_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo* results = NULL;
    if (getaddrinfo(AS_STRING(args[0]), NULL, &hints, &results) != 0 || !results)
        return val_nil();

    char host[NI_MAXHOST];
    memset(host, 0, sizeof(host));
    int result = getnameinfo(results->ai_addr, results->ai_addrlen, host, sizeof(host),
                             NULL, 0, NI_NUMERICHOST);
    freeaddrinfo(results);
    if (result != 0) return val_nil();
    return val_string(host);
}

static Value socket_getpeername_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_nil();
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    struct sockaddr_storage address;
    socklen_t address_len = sizeof(address);
    if (getpeername((int)AS_NUMBER(args[0]), (struct sockaddr*)&address, &address_len) < 0)
        return val_nil();

    char host[NI_MAXHOST];
    char service[NI_MAXSERV];
    memset(host, 0, sizeof(host));
    memset(service, 0, sizeof(service));
    if (getnameinfo((struct sockaddr*)&address, address_len, host, sizeof(host),
                    service, sizeof(service), NI_NUMERICHOST | NI_NUMERICSERV) != 0)
        return val_nil();

    gc_pin();
    Value result = val_dict();
    dict_set(&result, "host", val_string(host));
    dict_set(&result, "port", val_number(atoi(service)));
    gc_unpin();
    return result;
}

static Value socket_nonblock_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_bool(0);
    if (argc < 1 || !IS_NUMBER(args[0])) return val_bool(0);
    int fd;
    if (!checked_int(AS_NUMBER(args[0]), 0, INT_MAX, &fd)) return val_bool(0);
    int enable = 1;
    if (argc >= 2) {
        if (IS_BOOL(args[1])) enable = AS_BOOL(args[1]) ? 1 : 0;
        else if (IS_NUMBER(args[1])) enable = AS_NUMBER(args[1]) != 0.0;
        else return val_bool(0);
    }
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return val_bool(0);
    int updated = enable ? (flags | O_NONBLOCK) : (flags & ~O_NONBLOCK);
    return val_bool(fcntl(fd, F_SETFL, updated) == 0);
}

static Value socket_strerror_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_string(strerror(errno));
}

// ========== TCP MODULE - High-level TCP client/server ==========

static Value tcp_connect_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_NUMBER(args[1])) return val_number(-1);

    struct sockaddr_storage address;
    socklen_t address_len = 0;
    if (resolve_endpoint(AS_STRING(args[0]), (int)AS_NUMBER(args[1]), SOCK_STREAM, 0,
                         &address, &address_len) < 0)
        return val_number(-1);

    int fd = socket(address.ss_family, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) return val_number(-1);

    int result;
    do {
        result = connect(fd, (struct sockaddr*)&address, address_len);
    } while (result < 0 && errno == EINTR);
    if (result < 0) {
        close(fd);
        return val_number(-1);
    }
    return val_number(fd);
}

static Value tcp_listen_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_NUMBER(args[1])) return val_number(-1);

    int backlog = (argc >= 3 && IS_NUMBER(args[2])) ? (int)AS_NUMBER(args[2]) : 128;
    if (backlog < 0) backlog = 0;
    struct sockaddr_storage address;
    socklen_t address_len = 0;
    if (resolve_endpoint(AS_STRING(args[0]), (int)AS_NUMBER(args[1]), SOCK_STREAM, 1,
                         &address, &address_len) < 0)
        return val_number(-1);

    int fd = socket(address.ss_family, SOCK_STREAM, IPPROTO_TCP);
    if (fd < 0) return val_number(-1);

    int option = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &option, sizeof(option));
    if (bind(fd, (struct sockaddr*)&address, address_len) < 0 || listen(fd, backlog) < 0) {
        close(fd);
        return val_number(-1);
    }
    return val_number(fd);
}

static Value tcp_accept_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_number(-1);
    if (argc < 1 || !IS_NUMBER(args[0])) return val_number(-1);
    int client;
    do {
        client = accept((int)AS_NUMBER(args[0]), NULL, NULL);
    } while (client < 0 && errno == EINTR);
    return val_number(client);
}

static Value tcp_send_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_number(-1);
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_STRING(args[1])) return val_number(-1);
    ssize_t sent;
    do {
        sent = send((int)AS_NUMBER(args[0]), AS_STRING(args[1]), SAGE_STRING_LEN(args[1]), MSG_NOSIGNAL);
    } while (sent < 0 && errno == EINTR);
    return val_number((double)sent);
}

static Value tcp_recv_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_nil();
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);
    int length = (int)AS_NUMBER(args[1]);
    if (length <= 0 || length > SAGE_MAX_READ_SIZE) return val_nil();

    char* buffer = SAGE_ALLOC((size_t)length + 1);
    ssize_t received;
    do {
        received = recv(fd, buffer, (size_t)length, 0);
    } while (received < 0 && errno == EINTR);
    if (received <= 0) {
        free(buffer);
        return val_nil();
    }
    buffer[received] = '\0';
    return val_string_take_len(buffer, (int)received);
}

static Value tcp_sendall_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_bool(0);
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    int fd = (int)AS_NUMBER(args[0]);
    const char* data = AS_STRING(args[1]);
    size_t length = (size_t)SAGE_STRING_LEN(args[1]);
    size_t sent = 0;
    while (sent < length) {
        ssize_t count;
        do {
            count = send(fd, data + sent, length - sent, MSG_NOSIGNAL);
        } while (count < 0 && errno == EINTR);
        if (count <= 0) return val_bool(0);
        sent += (size_t)count;
    }
    return val_bool(1);
}

static Value tcp_recvall_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_nil();
    if (argc < 2 || !IS_NUMBER(args[0]) || !IS_NUMBER(args[1])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);
    int length = (int)AS_NUMBER(args[1]);
    if (length <= 0 || length > SAGE_MAX_READ_SIZE) return val_nil();

    char* buffer = SAGE_ALLOC((size_t)length + 1);
    int received = 0;
    while (received < length) {
        ssize_t count;
        do {
            count = recv(fd, buffer + received, (size_t)(length - received), 0);
        } while (count < 0 && errno == EINTR);
        if (count <= 0) {
            free(buffer);
            return val_nil();
        }
        received += (int)count;
    }
    buffer[length] = '\0';
    return val_string_take_len(buffer, length);
}

static Value tcp_recvline_native(int argc, Value* args) {
    if (net_sandbox_denied()) return val_nil();
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    int fd = (int)AS_NUMBER(args[0]);
    int maxlen = (argc >= 2 && IS_NUMBER(args[1])) ? (int)AS_NUMBER(args[1]) : 4096;
    if (maxlen <= 0 || maxlen > SAGE_MAX_READ_SIZE) maxlen = 4096;

    char* buffer = SAGE_ALLOC((size_t)maxlen + 1);
    int position = 0;
    while (position < maxlen) {
        char byte;
        ssize_t count;
        do {
            count = recv(fd, &byte, 1, 0);
        } while (count < 0 && errno == EINTR);
        if (count <= 0) break;
        buffer[position++] = byte;
        if (byte == '\n') break;
    }
    if (position == 0) {
        free(buffer);
        return val_nil();
    }
    buffer[position] = '\0';
    return val_string_take_len(buffer, position);
}

static Value tcp_close_native(int argc, Value* args) {
    if (argc < 1 || !IS_NUMBER(args[0])) return val_nil();
    close((int)AS_NUMBER(args[0]));
    return val_nil();
}

// ========== HTTP MODULE - Client Patterns ==========

#ifndef SAGE_NO_NET
typedef struct {
    char* data;
    size_t length;
    size_t capacity;
    int overflow;
} HttpBuffer;

enum {
    HTTP_MAX_REDIRECTS = 10,
    HTTP_MAX_URL_LENGTH = 65536
};

typedef struct {
    char* url;
    char* scheme;
    char* host;
    int port;
} HttpUrl;

typedef struct {
    Value* headers;
    char* location;
    int location_seen;
    int location_invalid;
} HttpHeaderContext;

static char* http_copy_len(const char* value, size_t length) {
    if (length == (size_t)-1) return NULL;
    char* copy = SAGE_ALLOC(length + 1);
    if (length > 0) memcpy(copy, value, length);
    copy[length] = '\0';
    return copy;
}

static char* http_copy_string(const char* value) {
    return value ? http_copy_len(value, strlen(value)) : NULL;
}

static char http_lower_char(char value) {
    return value >= 'A' && value <= 'Z' ? (char)(value + ('a' - 'A')) : value;
}

static int http_ascii_equal_n(const char* left, size_t left_length,
                              const char* right, size_t right_length) {
    if (left_length != right_length) return 0;
    for (size_t i = 0; i < left_length; i++) {
        if (http_lower_char(left[i]) != http_lower_char(right[i])) return 0;
    }
    return 1;
}

static int http_hex_value(char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

static int http_url_characters_are_safe(const char* url, size_t length) {
    if (!url || length == 0 || length > HTTP_MAX_URL_LENGTH) return 0;
    for (size_t i = 0; i < length; i++) {
        unsigned char value = (unsigned char)url[i];
        if (value == 0 || value <= 0x20 || value == 0x7f || value == '\\' ||
            value == '<' || value == '>' || value == '"' || value == '{' ||
            value == '}' || value == '|' || value == '^' || value == '`')
            return 0;
        if (value == '%') {
            if (i + 2 >= length) return 0;
            int high = http_hex_value(url[i + 1]);
            int low = http_hex_value(url[i + 2]);
            if (high < 0 || low < 0) return 0;
            unsigned int decoded = (unsigned int)((high << 4) | low);
            if (decoded < 0x20 || decoded == 0x7f || decoded == '\\') return 0;
            i += 2;
        }
    }
    return 1;
}

static int http_get_scheme_length(const char* url, size_t length, size_t* scheme_length) {
    if (!url || length < 2) return 0;
    unsigned char first = (unsigned char)url[0];
    if (!((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z'))) return 0;
    size_t index = 1;
    while (index < length) {
        unsigned char value = (unsigned char)url[index];
        if (!((value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') ||
              (value >= '0' && value <= '9') || value == '+' || value == '-' || value == '.'))
            break;
        index++;
    }
    if (index >= length || url[index] != ':') return 0;
    *scheme_length = index;
    return 1;
}

static int http_is_http_scheme(const char* url, size_t length) {
    size_t scheme_length = 0;
    if (!http_get_scheme_length(url, length, &scheme_length)) return 0;
    return http_ascii_equal_n(url, scheme_length, "http", 4) ||
           http_ascii_equal_n(url, scheme_length, "https", 5);
}

static int http_url_authority_bounds(const char* url, size_t length,
                                     size_t* authority_start, size_t* authority_end) {
    size_t scheme_length = 0;
    if (!http_is_http_scheme(url, length) || !http_get_scheme_length(url, length, &scheme_length))
        return 0;
    if (scheme_length + 3 >= length || url[scheme_length] != ':' ||
        url[scheme_length + 1] != '/' || url[scheme_length + 2] != '/')
        return 0;

    size_t start = scheme_length + 3;
    if (start >= length || url[start] == '/' || url[start] == '?' || url[start] == '#')
        return 0;
    size_t end = start;
    while (end < length && url[end] != '/' && url[end] != '?' && url[end] != '#') end++;
    if (end == start) return 0;
    for (size_t i = start; i < end; i++) {
        if (url[i] == '@' || url[i] == '%' || url[i] == '\\') return 0;
    }
    *authority_start = start;
    *authority_end = end;
    return 1;
}

static int http_parse_port(const char* value, size_t length, int* port) {
    if (!value || length == 0 || !port) return 0;
    int parsed = 0;
    for (size_t i = 0; i < length; i++) {
        if (value[i] < '0' || value[i] > '9') return 0;
        int digit = value[i] - '0';
        if (parsed > (65535 - digit) / 10) return 0;
        parsed = parsed * 10 + digit;
    }
    if (parsed == 0) return 0;
    *port = parsed;
    return 1;
}

static int http_normalize_host(const char* host, char** normalized) {
    if (!host || !normalized) return 0;
    *normalized = NULL;
    size_t length = strlen(host);
    if (length == 0) return 0;

    if (host[0] == '[') {
        if (length < 3 || host[length - 1] != ']') return 0;
        size_t inner_length = length - 2;
        if (inner_length >= INET6_ADDRSTRLEN) return 0;
        char inner[INET6_ADDRSTRLEN];
        memcpy(inner, host + 1, inner_length);
        inner[inner_length] = '\0';
        struct in6_addr address;
        if (inet_pton(AF_INET6, inner, &address) != 1) return 0;
        char address_text[INET6_ADDRSTRLEN];
        if (!inet_ntop(AF_INET6, &address, address_text, sizeof(address_text))) return 0;
        size_t text_length = strlen(address_text);
        char* result = SAGE_ALLOC(text_length + 3);
        result[0] = '[';
        memcpy(result + 1, address_text, text_length);
        result[text_length + 1] = ']';
        result[text_length + 2] = '\0';
        *normalized = result;
        return 1;
    }

    if (strchr(host, ':') != NULL) return 0;
    size_t effective_length = length;
    if (effective_length > 0 && host[effective_length - 1] == '.') effective_length--;
    if (effective_length == 0 || effective_length > 253) return 0;

    char* result = SAGE_ALLOC(effective_length + 1);
    for (size_t i = 0; i < effective_length; i++) result[i] = http_lower_char(host[i]);
    result[effective_length] = '\0';

    struct in_addr address;
    if (inet_pton(AF_INET, result, &address) == 1) {
        char address_text[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &address, address_text, sizeof(address_text))) {
            free(result);
            *normalized = http_copy_string(address_text);
            return *normalized != NULL;
        }
    }

    int numeric_host = 1;
    int has_dot = 0;
    for (size_t i = 0; i < effective_length; i++) {
        unsigned char value = (unsigned char)result[i];
        if (value == '.') {
            has_dot = 1;
            continue;
        }
        if (value < '0' || value > '9') {
            numeric_host = 0;
            break;
        }
    }
    if (numeric_host && has_dot) {
        free(result);
        return 0;
    }

    size_t label_start = 0;
    for (size_t i = 0; i <= effective_length; i++) {
        if (i != effective_length && result[i] != '.') continue;
        size_t label_length = i - label_start;
        if (label_length == 0 || label_length > 63 ||
            result[label_start] == '-' || result[i - 1] == '-') {
            free(result);
            return 0;
        }
        for (size_t j = label_start; j < i; j++) {
            unsigned char value = (unsigned char)result[j];
            if (!((value >= 'a' && value <= 'z') || (value >= '0' && value <= '9') || value == '-')) {
                free(result);
                return 0;
            }
        }
        label_start = i + 1;
    }
    *normalized = result;
    return 1;
}

static void http_free_url(HttpUrl* url) {
    if (!url) return;
    free(url->url);
    free(url->scheme);
    free(url->host);
    memset(url, 0, sizeof(*url));
}

static int http_url_origin_equal(const HttpUrl* left, const HttpUrl* right) {
    return left && right && left->port == right->port &&
           strcmp(left->scheme, right->scheme) == 0 && strcmp(left->host, right->host) == 0;
}

static int http_url_is_downgrade(const HttpUrl* from, const HttpUrl* to) {
    return from && to && strcmp(from->scheme, "https") == 0 && strcmp(to->scheme, "http") == 0;
}

#if LIBCURL_VERSION_NUM < 0x073E00
static int http_parse_url_legacy(const char* url, size_t length, HttpUrl* parsed) {
    size_t authority_start = 0;
    size_t authority_end = 0;
    if (!http_url_characters_are_safe(url, length) ||
        !http_url_authority_bounds(url, length, &authority_start, &authority_end))
        return 0;

    size_t scheme_length = 0;
    http_get_scheme_length(url, length, &scheme_length);
    size_t host_start = authority_start;
    size_t host_end = authority_end;
    int port = http_ascii_equal_n(url, scheme_length, "http", 4) ? 80 : 443;

    if (url[host_start] == '[') {
        size_t close = host_start + 1;
        while (close < authority_end && url[close] != ']') close++;
        if (close >= authority_end) return 0;
        host_end = close + 1;
        if (host_end < authority_end) {
            if (url[host_end] != ':') return 0;
            if (!http_parse_port(url + host_end + 1, authority_end - host_end - 1, &port)) return 0;
        }
    } else {
        size_t colon = 0;
        int found_colon = 0;
        for (size_t i = authority_start; i < authority_end; i++) {
            if (url[i] == ':') {
                if (found_colon) return 0;
                found_colon = 1;
                colon = i;
            }
        }
        if (found_colon) {
            host_end = colon;
            if (!http_parse_port(url + colon + 1, authority_end - colon - 1, &port)) return 0;
        }
    }

    char* raw_host = http_copy_len(url + host_start, host_end - host_start);
    char* normalized_host = NULL;
    if (!raw_host || !http_normalize_host(raw_host, &normalized_host)) {
        free(raw_host);
        free(normalized_host);
        return 0;
    }
    free(raw_host);

    parsed->scheme = http_copy_len(url, scheme_length);
    if (!parsed->scheme) {
        free(normalized_host);
        return 0;
    }
    for (size_t i = 0; i < scheme_length; i++) parsed->scheme[i] = http_lower_char(parsed->scheme[i]);
    parsed->host = normalized_host;
    parsed->port = port;
    parsed->url = http_copy_len(url, length);
    if (!parsed->url) {
        http_free_url(parsed);
        return 0;
    }
    return 1;
}
#endif

#if LIBCURL_VERSION_NUM >= 0x073E00
static int http_parse_url_modern(const char* url, size_t length, HttpUrl* parsed) {
    (void)length;
    CURLU* handle = curl_url();
    if (!handle) return 0;

    char* raw_scheme = NULL;
    char* raw_host = NULL;
    char* raw_port = NULL;
    char* full_url = NULL;
    int success = 0;
    if (curl_url_set(handle, CURLUPART_URL, url, CURLU_DISALLOW_USER) != CURLUE_OK) goto done;
    if (curl_url_get(handle, CURLUPART_SCHEME, &raw_scheme, 0) != CURLUE_OK) goto done;
    if (curl_url_get(handle, CURLUPART_HOST, &raw_host, 0) != CURLUE_OK) goto done;
    if (curl_url_get(handle, CURLUPART_PORT, &raw_port, CURLU_DEFAULT_PORT) != CURLUE_OK) goto done;
    if (curl_url_get(handle, CURLUPART_URL, &full_url, 0) != CURLUE_OK) goto done;
    if (!raw_scheme || !raw_host || !raw_port || !full_url) goto done;
    if (!http_url_characters_are_safe(full_url, strlen(full_url))) goto done;
    if (!http_ascii_equal_n(raw_scheme, strlen(raw_scheme), "http", 4) &&
        !http_ascii_equal_n(raw_scheme, strlen(raw_scheme), "https", 5)) goto done;

    char* normalized_host = NULL;
    if (!http_normalize_host(raw_host, &normalized_host)) goto done;
    int port = 0;
    if (!http_parse_port(raw_port, strlen(raw_port), &port)) {
        free(normalized_host);
        goto done;
    }

    parsed->scheme = http_copy_string(raw_scheme);
    if (!parsed->scheme) {
        free(normalized_host);
        goto done;
    }
    for (size_t i = 0; parsed->scheme[i] != '\0'; i++)
        parsed->scheme[i] = http_lower_char(parsed->scheme[i]);
    parsed->host = normalized_host;
    parsed->port = port;
    parsed->url = http_copy_string(full_url);
    if (!parsed->url) goto done;
    curl_free(full_url);
    full_url = NULL;
    success = 1;

done:
    curl_free(raw_scheme);
    curl_free(raw_host);
    curl_free(raw_port);
    curl_free(full_url);
    curl_url_cleanup(handle);
    if (!success) http_free_url(parsed);
    return success;
}
#endif

static int http_parse_url(const char* url, HttpUrl* parsed) {
    if (!url || !parsed) return 0;
    memset(parsed, 0, sizeof(*parsed));
    size_t length = strlen(url);
    size_t authority_start = 0;
    size_t authority_end = 0;
    if (!http_url_characters_are_safe(url, length) ||
        !http_url_authority_bounds(url, length, &authority_start, &authority_end))
        return 0;
#if LIBCURL_VERSION_NUM >= 0x073E00
    (void)authority_start;
    (void)authority_end;
    return http_parse_url_modern(url, length, parsed);
#else
    return http_parse_url_legacy(url, length, parsed);
#endif
}

static int http_has_uri_scheme(const char* value, size_t length) {
    if (!value || length == 0) return 0;
    unsigned char first = (unsigned char)value[0];
    if (!((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z'))) return 0;
    for (size_t i = 1; i < length; i++) {
        unsigned char current = (unsigned char)value[i];
        if (!((current >= 'a' && current <= 'z') || (current >= 'A' && current <= 'Z') ||
              (current >= '0' && current <= '9') || current == '+' || current == '-' || current == '.'))
            return 0;
        if (current == ':') return 1;
    }
    return 0;
}

static char* http_concat_url_parts(const char* first, const char* second, const char* third) {
    size_t first_length = first ? strlen(first) : 0;
    size_t second_length = second ? strlen(second) : 0;
    size_t third_length = third ? strlen(third) : 0;
    if (first_length > HTTP_MAX_URL_LENGTH || second_length > HTTP_MAX_URL_LENGTH - first_length ||
        third_length > HTTP_MAX_URL_LENGTH - first_length - second_length)
        return NULL;
    size_t total = first_length + second_length + third_length;
    char* result = SAGE_ALLOC(total + 1);
    if (first_length > 0) memcpy(result, first, first_length);
    if (second_length > 0) memcpy(result + first_length, second, second_length);
    if (third_length > 0) memcpy(result + first_length + second_length, third, third_length);
    result[total] = '\0';
    return result;
}

static char* http_url_prefix(const HttpUrl* url) {
    if (!url) return NULL;
    char port[16] = {0};
    int default_port = strcmp(url->scheme, "http") == 0 ? 80 : 443;
    if (url->port != default_port) snprintf(port, sizeof(port), ":%d", url->port);
    char* authority = http_concat_url_parts(url->host, port, "");
    if (!authority) return NULL;
    char* result = http_concat_url_parts(url->scheme, "://", authority);
    free(authority);
    return result;
}

static char* http_url_base_path(const HttpUrl* url) {
    if (!url) return NULL;
    size_t length = strlen(url->url);
    size_t authority_start = 0;
    size_t authority_end = 0;
    if (!http_url_authority_bounds(url->url, length, &authority_start, &authority_end)) return NULL;
    (void)authority_start;
    size_t path_start = authority_end;
    if (path_start >= length || url->url[path_start] == '?' || url->url[path_start] == '#')
        return http_copy_string("/");
    size_t path_end = path_start;
    while (path_end < length && url->url[path_end] != '?' && url->url[path_end] != '#') path_end++;
    return http_copy_len(url->url + path_start, path_end - path_start);
}

static char* http_url_base_without(const HttpUrl* url, char delimiter) {
    if (!url) return NULL;
    size_t length = strlen(url->url);
    size_t authority_start = 0;
    size_t authority_end = 0;
    if (!http_url_authority_bounds(url->url, length, &authority_start, &authority_end)) return NULL;
    (void)authority_start;
    size_t end = authority_end;
    while (end < length) {
        if (delimiter == '?') {
            if (url->url[end] == '?' || url->url[end] == '#') break;
        } else if (url->url[end] == '#') {
            break;
        }
        end++;
    }
    return http_copy_len(url->url, end);
}

static char* http_normalize_redirect_path(const char* path) {
    if (!path || !http_url_characters_are_safe(path, strlen(path)) || path[0] != '/') return NULL;
    size_t length = strlen(path);
    char* result = SAGE_ALLOC(length + 2);
    size_t result_length = 0;
    size_t position = 0;
    while (position < length) {
        while (position < length && path[position] == '/') position++;
        size_t segment_start = position;
        while (position < length && path[position] != '/') position++;
        size_t segment_length = position - segment_start;
        if (segment_length == 0) continue;
        if (segment_length == 1 && path[segment_start] == '.') continue;
        if (segment_length == 2 && path[segment_start] == '.' && path[segment_start + 1] == '.') {
            if (result_length == 0) {
                free(result);
                return NULL;
            }
            size_t slash = result_length;
            while (slash > 0 && result[slash - 1] != '/') slash--;
            if (slash == 0) {
                free(result);
                return NULL;
            }
            result_length = slash - 1;
            continue;
        }
        if (result_length == 0) result[result_length++] = '/';
        else if (result[result_length - 1] != '/') result[result_length++] = '/';
        memcpy(result + result_length, path + segment_start, segment_length);
        result_length += segment_length;
    }
    if (result_length == 0) result[result_length++] = '/';
    else if (length > 1 && path[length - 1] == '/' && result[result_length - 1] != '/')
        result[result_length++] = '/';
    result[result_length] = '\0';
    return result;
}

static int http_resolve_redirect_url(const HttpUrl* base, const char* location, HttpUrl* parsed) {
    if (!base || !location || !parsed) return 0;
    size_t location_length = strlen(location);
    if (location_length == 0 || !http_url_characters_are_safe(location, location_length)) return 0;
    if (http_parse_url(location, parsed)) return 1;
    if (http_has_uri_scheme(location, location_length)) return 0;

    if (location_length >= 2 && location[0] == '/' && location[1] == '/') {
        char* absolute = http_concat_url_parts(base->scheme, ":", location);
        if (!absolute) return 0;
        int parsed_ok = http_parse_url(absolute, parsed);
        free(absolute);
        return parsed_ok;
    }

    size_t delimiter = location_length;
    for (size_t i = 0; i < location_length; i++) {
        if (location[i] == '?' || location[i] == '#') {
            delimiter = i;
            break;
        }
    }
    char* suffix = http_copy_len(location + delimiter, location_length - delimiter);
    char* result = NULL;
    if (location[0] == '#') {
        char* base_without_fragment = http_url_base_without(base, '#');
        if (base_without_fragment)
            result = http_concat_url_parts(base_without_fragment, location, "");
        free(base_without_fragment);
    } else if (location[0] == '?') {
        char* base_without_query = http_url_base_without(base, '?');
        if (base_without_query) result = http_concat_url_parts(base_without_query, location, "");
        free(base_without_query);
    } else {
        char* path = http_copy_len(location, delimiter);
        char* base_path = http_url_base_path(base);
        char* combined_path = NULL;
        if (path && base_path) {
            if (location[0] == '/') {
                combined_path = path;
                path = NULL;
            } else {
                char* last_slash = strrchr(base_path, '/');
                size_t directory_length = last_slash ? (size_t)(last_slash - base_path + 1) : 1;
                combined_path = http_concat_url_parts(base_path, "", "");
                if (combined_path) {
                    char* with_directory = http_copy_len(base_path, directory_length);
                    if (with_directory) {
                        char* joined = http_concat_url_parts(with_directory, path, "");
                        free(combined_path);
                        free(with_directory);
                        combined_path = joined;
                    } else {
                        free(combined_path);
                        combined_path = NULL;
                    }
                }
            }
        }
        free(path);
        free(base_path);
        char* normalized_path = http_normalize_redirect_path(combined_path);
        free(combined_path);
        char* prefix = http_url_prefix(base);
        if (normalized_path && prefix) result = http_concat_url_parts(prefix, normalized_path, suffix);
        free(normalized_path);
        free(prefix);
    }
    free(suffix);

    if (!result) return 0;
    int parsed_ok = http_parse_url(result, parsed);
    free(result);
    return parsed_ok;
}

static pthread_once_t curl_once = PTHREAD_ONCE_INIT;
static int curl_initialized = 0;

static void initialize_curl(void) {
    curl_initialized = curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK;
}

static size_t http_write_callback(char* data, size_t size, size_t count, void* userdata) {
    HttpBuffer* buffer = (HttpBuffer*)userdata;
    if (size != 0 && count > (size_t)-1 / size) {
        buffer->overflow = 1;
        return 0;
    }
    size_t bytes = size * count;
    if (bytes > (size_t)SAGE_MAX_READ_SIZE - buffer->length) {
        buffer->overflow = 1;
        return 0;
    }
    size_t required = buffer->length + bytes + 1;
    if (required > buffer->capacity) {
        size_t capacity = buffer->capacity > 0 ? buffer->capacity : 4096;
        while (capacity < required) {
            if (capacity > (size_t)SAGE_MAX_READ_SIZE / 2) {
                capacity = (size_t)SAGE_MAX_READ_SIZE + 1;
                break;
            }
            capacity *= 2;
        }
        char* resized = SAGE_REALLOC(buffer->data, capacity);
        if (!resized) {
            buffer->overflow = 1;
            return 0;
        }
        buffer->data = resized;
        buffer->capacity = capacity;
    }
    if (bytes > 0) memcpy(buffer->data + buffer->length, data, bytes);
    buffer->length += bytes;
    buffer->data[buffer->length] = '\0';
    return bytes;
}

static int header_has_forbidden_newline(const char* value, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if (value[i] == '\r' || value[i] == '\n') return 1;
    }
    return 0;
}

static size_t http_header_callback(char* data, size_t size, size_t count, void* userdata) {
    if (size != 0 && count > (size_t)-1 / size) return 0;
    size_t bytes = size * count;
    HttpHeaderContext* context = (HttpHeaderContext*)userdata;
    if (!context || !data || (bytes > 0 && memchr(data, '\0', bytes) != NULL)) return 0;
    if (bytes >= 5 && memcmp(data, "HTTP/", 5) == 0) {
        free(context->location);
        context->location = NULL;
        context->location_seen = 0;
        context->location_invalid = 0;
        return bytes;
    }
    if (bytes == 0) return 0;

    char* colon = memchr(data, ':', bytes);
    if (!colon) return bytes;
    size_t key_length = (size_t)(colon - data);
    while (key_length > 0 && (data[key_length - 1] == ' ' || data[key_length - 1] == '\t')) key_length--;
    if (key_length == 0) return bytes;

    size_t value_start = (size_t)(colon - data) + 1;
    while (value_start < bytes && (data[value_start] == ' ' || data[value_start] == '\t')) value_start++;
    size_t value_end = bytes;
    while (value_end > value_start && (data[value_end - 1] == '\r' || data[value_end - 1] == '\n' ||
                                       data[value_end - 1] == ' ' || data[value_end - 1] == '\t')) value_end--;

    if (http_ascii_equal_n(data, key_length, "Location", 8)) {
        size_t value_length = value_end - value_start;
        if (value_length > HTTP_MAX_URL_LENGTH) {
            context->location_invalid = 1;
            return 0;
        }
        free(context->location);
        context->location = http_copy_len(data + value_start, value_length);
        context->location_seen = 1;
    }

    char* key = SAGE_ALLOC(key_length + 1);
    char* lower_key = SAGE_ALLOC(key_length + 1);
    char* value = SAGE_ALLOC(value_end - value_start + 1);
    memcpy(key, data, key_length);
    key[key_length] = '\0';
    for (size_t i = 0; i < key_length; i++) {
        unsigned char byte = (unsigned char)key[i];
        lower_key[i] = (byte >= 'A' && byte <= 'Z') ? (char)(byte + ('a' - 'A')) : key[i];
    }
    lower_key[key_length] = '\0';
    memcpy(value, data + value_start, value_end - value_start);
    value[value_end - value_start] = '\0';
    Value header_value = val_string(value);
    dict_set(context->headers, key, header_value);
    dict_set(context->headers, lower_key, header_value);
    free(key);
    free(lower_key);
    free(value);
    return bytes;
}

static int http_option_bool(Value* options, const char* primary, const char* alias, int fallback) {
    if (!options || options->type != VAL_DICT) return fallback;
    if (dict_has(options, primary)) {
        Value value = dict_get(options, primary);
        if (IS_BOOL(value)) return AS_BOOL(value) ? 1 : 0;
        if (IS_NUMBER(value)) return AS_NUMBER(value) != 0.0;
    }
    if (alias && dict_has(options, alias)) {
        Value value = dict_get(options, alias);
        if (IS_BOOL(value)) return AS_BOOL(value) ? 1 : 0;
        if (IS_NUMBER(value)) return AS_NUMBER(value) != 0.0;
    }
    return fallback;
}

static int http_append_header(struct curl_slist** headers, const char* value) {
    if (!value || header_has_forbidden_newline(value, strlen(value))) return 0;
    struct curl_slist* appended = curl_slist_append(*headers, value);
    if (!appended) return 0;
    *headers = appended;
    return 1;
}

static int http_configure_headers(Value* options, struct curl_slist** headers) {
    if (!options || options->type != VAL_DICT || !dict_has(options, "headers")) return 1;
    Value configured = dict_get(options, "headers");
    if (IS_ARRAY(configured)) {
        ArrayValue* array = AS_ARRAY(configured);
        for (int i = 0; i < array->count; i++) {
            if (!IS_STRING(array->elements[i]) || !http_append_header(headers, AS_STRING(array->elements[i])))
                return 0;
        }
        return 1;
    }
    if (IS_DICT(configured)) {
        Value keys = dict_keys(&configured);
        ArrayValue* array = AS_ARRAY(keys);
        for (int i = 0; i < array->count; i++) {
            Value value = dict_get(&configured, AS_STRING(array->elements[i]));
            if (!IS_STRING(value)) return 0;
            size_t needed = strlen(AS_STRING(array->elements[i])) + strlen(AS_STRING(value)) + 3;
            char* header = SAGE_ALLOC(needed);
            snprintf(header, needed, "%s: %s", AS_STRING(array->elements[i]), AS_STRING(value));
            int valid = http_append_header(headers, header);
            free(header);
            if (!valid) return 0;
        }
        return 1;
    }
    return 0;
}

static int http_is_redirect_status(long status) {
    return status == 301 || status == 302 || status == 303 || status == 307 || status == 308;
}

static Value http_request_native(const char* method, const char* url, int url_length,
                                 const char* body, int body_length, Value* options) {
    if (net_sandbox_denied()) return val_nil();
    if (!method || !url || url_length <= 0 || url_length > HTTP_MAX_URL_LENGTH ||
        url[url_length] != '\0' || memchr(url, '\0', (size_t)url_length) != NULL)
        return val_nil();
    if (options && options->type != VAL_DICT) return val_nil();
    if (body_length < 0 || (!body && body_length != 0)) return val_nil();

    pthread_once(&curl_once, initialize_curl);
    if (!curl_initialized) return val_nil();

    long timeout_ms = 30000;
    if (options && dict_has(options, "timeout")) {
        Value timeout_value = dict_get(options, "timeout");
        if (IS_NUMBER(timeout_value)) {
            double timeout = AS_NUMBER(timeout_value);
            if (timeout <= 0.0 || timeout > 86400.0) return val_nil();
            timeout_ms = (long)(timeout * 1000.0);
        }
    }

    const char* user_agent = NULL;
    if (options && dict_has(options, "user_agent")) {
        Value user_agent_value = dict_get(options, "user_agent");
        if (IS_STRING(user_agent_value)) {
            int user_agent_length = SAGE_STRING_LEN(user_agent_value);
            if (user_agent_length < 0 || memchr(AS_STRING(user_agent_value), '\0', (size_t)user_agent_length) != NULL ||
                header_has_forbidden_newline(AS_STRING(user_agent_value), (size_t)user_agent_length))
                return val_nil();
            user_agent = AS_STRING(user_agent_value);
        }
    }

    const char* cainfo = NULL;
    if (options && dict_has(options, "cainfo")) {
        Value cainfo_value = dict_get(options, "cainfo");
        if (!IS_STRING(cainfo_value)) return val_nil();
        cainfo = AS_STRING(cainfo_value);
    }

    int follow_redirects = http_option_bool(options, "follow", "follow_redirects", 1);
    int verify_ssl = http_option_bool(options, "verify", "verify_ssl", 1);
    int credentials_allowed = 1;
    int redirect_count = 0;
    const char* active_method = method;
    int active_body = body != NULL && body_length > 0;

    HttpUrl current_url;
    memset(&current_url, 0, sizeof(current_url));
    if (!http_parse_url(url, &current_url)) return val_nil();

    int gc_pinned = 0;
    Value response = val_nil();
    Value response_headers = val_nil();
    gc_pin();
    gc_pinned = 1;
    response_headers = val_dict();

    struct curl_slist* request_headers = NULL;
    if (!http_configure_headers(options, &request_headers)) goto cleanup;

    for (;;) {
        CURL* curl = curl_easy_init();
        if (!curl) goto cleanup;

        HttpBuffer response_body;
        memset(&response_body, 0, sizeof(response_body));
        HttpHeaderContext header_context;
        memset(&header_context, 0, sizeof(header_context));
        header_context.headers = &response_headers;
        char curl_error[CURL_ERROR_SIZE];
        memset(curl_error, 0, sizeof(curl_error));

        curl_easy_setopt(curl, CURLOPT_URL, current_url.url);
        curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, curl_error);
        curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
        curl_easy_setopt(curl, CURLOPT_AUTOREFERER, 0L);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 0L);
        curl_easy_setopt(curl, CURLOPT_MAXREDIRS, (long)HTTP_MAX_REDIRECTS);
        curl_easy_setopt(curl, CURLOPT_UNRESTRICTED_AUTH, 0L);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, (long)verify_ssl);
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, verify_ssl ? 2L : 0L);
#if LIBCURL_VERSION_NUM >= 0x075500
        curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
        curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
#else
        curl_easy_setopt(curl, CURLOPT_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
        curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS, (long)(CURLPROTO_HTTP | CURLPROTO_HTTPS));
#endif
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, http_write_callback);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response_body);
        curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, http_header_callback);
        curl_easy_setopt(curl, CURLOPT_HEADERDATA, &header_context);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeout_ms);

        if (credentials_allowed) {
            if (request_headers) curl_easy_setopt(curl, CURLOPT_HTTPHEADER, request_headers);
            if (user_agent) curl_easy_setopt(curl, CURLOPT_USERAGENT, user_agent);
        }
        if (cainfo) curl_easy_setopt(curl, CURLOPT_CAINFO, cainfo);

        if (active_body) {
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
            curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, (curl_off_t)body_length);
        }
        if (strcmp(active_method, "HEAD") == 0) curl_easy_setopt(curl, CURLOPT_NOBODY, 1L);
        else if (strcmp(active_method, "GET") == 0 && !active_body)
            curl_easy_setopt(curl, CURLOPT_HTTPGET, 1L);
        else if (strcmp(active_method, "GET") != 0)
            curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, active_method);

        CURLcode result = curl_easy_perform(curl);
        long status = 0;
        char* effective_url = NULL;
        char* redirect_url = NULL;
        if (result == CURLE_OK) {
            if (curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status) != CURLE_OK)
                result = CURLE_FAILED_INIT;
            if (curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &effective_url) != CURLE_OK)
                effective_url = NULL;
            if (curl_easy_getinfo(curl, CURLINFO_REDIRECT_URL, &redirect_url) != CURLE_OK)
                redirect_url = NULL;
        }

        int redirect_response = result == CURLE_OK && http_is_redirect_status(status);
        const char* target_url = redirect_url ? redirect_url : header_context.location;
        int has_target = redirect_response && target_url && target_url[0] != '\0';
        if (redirect_response && header_context.location_seen && !has_target) {
            curl_easy_cleanup(curl);
            free(header_context.location);
            free(response_body.data);
            goto cleanup;
        }
        if (redirect_response && header_context.location_invalid) {
            curl_easy_cleanup(curl);
            free(header_context.location);
            free(response_body.data);
            goto cleanup;
        }

        HttpUrl next_url;
        memset(&next_url, 0, sizeof(next_url));
        if (has_target && !http_resolve_redirect_url(&current_url, target_url, &next_url)) {
            curl_easy_cleanup(curl);
            free(header_context.location);
            free(response_body.data);
            goto cleanup;
        }

        int follow_this_redirect = follow_redirects && has_target;
        if (follow_this_redirect) {
            if (redirect_count >= HTTP_MAX_REDIRECTS) {
                http_free_url(&next_url);
                curl_easy_cleanup(curl);
                free(header_context.location);
                free(response_body.data);
                goto cleanup;
            }

            int same_origin = http_url_origin_equal(&current_url, &next_url);
            int downgrade = http_url_is_downgrade(&current_url, &next_url);
            if (!same_origin || downgrade) credentials_allowed = 0;

            const char* next_method = active_method;
            int next_body = active_body;
            if ((status == 303 && strcmp(active_method, "HEAD") != 0) ||
                ((status == 301 || status == 302) && strcmp(active_method, "POST") == 0)) {
                next_method = "GET";
                next_body = 0;
            }
            if (!credentials_allowed && next_body) {
                http_free_url(&next_url);
                curl_easy_cleanup(curl);
                free(header_context.location);
                free(response_body.data);
                goto cleanup;
            }

            active_method = next_method;
            active_body = next_body;
            http_free_url(&current_url);
            current_url = next_url;
            redirect_count++;
            curl_easy_cleanup(curl);
            free(header_context.location);
            free(response_body.data);
            continue;
        }

        if (result == CURLE_OK && !response_body.overflow) {
            response = val_dict();
            dict_set(&response, "status", val_number((double)status));
            dict_set(&response, "body", val_string_len(response_body.data, (int)response_body.length));
            dict_set(&response, "headers", response_headers);
            dict_set(&response, "url", val_string(effective_url ? effective_url : current_url.url));
        }
        http_free_url(&next_url);
        curl_easy_cleanup(curl);
        free(header_context.location);
        free(response_body.data);
        break;
    }

cleanup:
    if (gc_pinned) gc_unpin();
    curl_slist_free_all(request_headers);
    http_free_url(&current_url);
    return response;
}
#else
static Value http_request_native(const char* method, const char* url, int url_length,
                                 const char* body, int body_length, Value* options) {
    (void)method;
    (void)url;
    (void)url_length;
    (void)body;
    (void)body_length;
    (void)options;
    return val_nil();
}
#endif

static Value http_get_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    return http_request_native("GET", AS_STRING(args[0]), SAGE_STRING_LEN(args[0]), NULL, 0, argc >= 2 ? &args[1] : NULL);
}

static Value http_body_native(int argc, Value* args, const char* method) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_nil();
    return http_request_native(method, AS_STRING(args[0]), SAGE_STRING_LEN(args[0]),
                               AS_STRING(args[1]), SAGE_STRING_LEN(args[1]), argc >= 3 ? &args[2] : NULL);
}

static Value http_post_native(int argc, Value* args) {
    return http_body_native(argc, args, "POST");
}

static Value http_put_native(int argc, Value* args) {
    return http_body_native(argc, args, "PUT");
}

static Value http_patch_native(int argc, Value* args) {
    return http_body_native(argc, args, "PATCH");
}

static Value http_delete_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    return http_request_native("DELETE", AS_STRING(args[0]), SAGE_STRING_LEN(args[0]), NULL, 0, argc >= 2 ? &args[1] : NULL);
}

static Value http_head_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    return http_request_native("HEAD", AS_STRING(args[0]), SAGE_STRING_LEN(args[0]), NULL, 0, argc >= 2 ? &args[1] : NULL);
}

static Value http_download_native(int argc, Value* args) {
    if (argc < 2 || !IS_STRING(args[0]) || !IS_STRING(args[1])) return val_bool(0);
    Value response = http_request_native("GET", AS_STRING(args[0]), SAGE_STRING_LEN(args[0]), NULL, 0, argc >= 3 ? &args[2] : NULL);
    if (response.type != VAL_DICT || !dict_has(&response, "body")) return val_bool(0);
    Value body = dict_get(&response, "body");
    if (!IS_STRING(body)) return val_bool(0);

    FILE* output = fopen(AS_STRING(args[1]), "wb");
    if (!output) return val_bool(0);
    size_t length = (size_t)SAGE_STRING_LEN(body);
    size_t written = length == 0 ? 0 : fwrite(AS_STRING(body), 1, length, output);
    int close_result = fclose(output);
    return val_bool(written == length && close_result == 0);
}

#ifndef SAGE_NO_NET
static Value http_escape_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    pthread_once(&curl_once, initialize_curl);
    if (!curl_initialized) return val_nil();
    char* escaped = curl_easy_escape(NULL, AS_STRING(args[0]), (int)SAGE_STRING_LEN(args[0]));
    if (!escaped) return val_nil();
    Value result = val_string(escaped);
    curl_free(escaped);
    return result;
}

static Value http_unescape_native(int argc, Value* args) {
    if (argc < 1 || !IS_STRING(args[0])) return val_nil();
    pthread_once(&curl_once, initialize_curl);
    if (!curl_initialized) return val_nil();
    int length = 0;
    char* unescaped = curl_easy_unescape(NULL, AS_STRING(args[0]), (int)SAGE_STRING_LEN(args[0]), &length);
    if (!unescaped) return val_nil();
    Value result = val_string_len(unescaped, length);
    curl_free(unescaped);
    return result;
}
#else
static Value http_escape_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_nil();
}

static Value http_unescape_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_nil();
}
#endif

// ========== SSL MODULE Stub ==========

static Value ssl_available_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

static Value ssl_error_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_string("TLS operations are unavailable: direct SSL socket bindings are not implemented; use http for HTTPS");
}

static Value ssl_context_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_nil();
}

static Value ssl_load_cert_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

static Value ssl_wrap_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_nil();
}

static Value ssl_connect_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

static Value ssl_accept_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

static Value ssl_send_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_nil();
}

static Value ssl_recv_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_nil();
}

static Value ssl_shutdown_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

static Value ssl_free_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

static Value ssl_free_context_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

static Value ssl_peer_cert_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_nil();
}

static Value ssl_set_verify_native(int argc, Value* args) {
    (void)argc;
    (void)args;
    return val_bool(0);
}

// ========== MODULE REGISTRATION ==========

Module* create_net_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "net");
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
    env_define(e, "resolve", 7, val_native(socket_resolve_native));
    env_define(e, "strerror", 8, val_native(socket_strerror_native));
    env_define(e, "http_get", 8, val_native(http_get_native));
    env_define(e, "http_post", 9, val_native(http_post_native));
    env_define(e, "http_put", 8, val_native(http_put_native));
    env_define(e, "http_delete", 11, val_native(http_delete_native));
    env_define(e, "http_patch", 10, val_native(http_patch_native));
    env_define(e, "http_head", 9, val_native(http_head_native));
    env_define(e, "http_download", 13, val_native(http_download_native));
    env_define(e, "http_escape", 11, val_native(http_escape_native));
    env_define(e, "http_unescape", 13, val_native(http_unescape_native));
    return m;
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
    env_define(e, "resolve", 7, val_native(socket_resolve_native));
    env_define(e, "getpeername", 11, val_native(socket_getpeername_native));
    env_define(e, "nonblock", 8, val_native(socket_nonblock_native));
    env_define(e, "strerror", 8, val_native(socket_strerror_native));
    env_define(e, "AF_INET", 7, val_number(AF_INET));
    env_define(e, "AF_INET6", 8, val_number(AF_INET6));
    env_define(e, "SOCK_STREAM", 11, val_number(SOCK_STREAM));
    env_define(e, "SOCK_DGRAM", 10, val_number(SOCK_DGRAM));
    env_define(e, "SOCK_RAW", 8, val_number(SOCK_RAW));
    env_define(e, "IPPROTO_TCP", 11, val_number(IPPROTO_TCP));
    env_define(e, "IPPROTO_UDP", 11, val_number(IPPROTO_UDP));
    env_define(e, "POLLIN", 6, val_number(POLLIN));
    env_define(e, "POLLOUT", 7, val_number(POLLOUT));
    env_define(e, "POLLERR", 7, val_number(POLLERR));
    env_define(e, "POLLHUP", 7, val_number(POLLHUP));
    env_define(e, "POLLNVAL", 8, val_number(POLLNVAL));
    return m;
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

Module* create_ssl_module(ModuleCache* cache) {
    Module* m = create_native_module(cache, "ssl");
    Environment* e = m->env;
    env_define(e, "available", 9, val_bool(0));
    env_define(e, "is_available", 12, val_native(ssl_available_native));
    env_define(e, "error", 5, val_native(ssl_error_native));
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
    env_define(e, "peer_cert", 9, val_native(ssl_peer_cert_native));
    env_define(e, "set_verify", 10, val_native(ssl_set_verify_native));
    return m;
}
