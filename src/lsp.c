/*
 * SageLang LSP Server
 *
 * A basic Language Server Protocol implementation for Sage.
 * Communicates over stdin/stdout using LSP JSON-RPC wire protocol.
 * Debug/log output goes to stderr only.
 *
 * Supported features:
 *   - textDocument/didOpen, didChange, didClose
 *   - textDocument/publishDiagnostics (via linter)
 *   - textDocument/completion (keywords + builtins)
 *   - textDocument/hover (keyword/builtin docs)
 *   - textDocument/formatting (via formatter)
 *   - initialize / initialized / shutdown / exit
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "lsp.h"
#include "linter.h"
#include "formatter.h"

/* ========================================================================
 * Logging (stderr only -- stdout is the LSP channel)
 * ======================================================================== */

static void lsp_log(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[sage-lsp] ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    fflush(stderr);
    va_end(ap);
}

/* ========================================================================
 * Minimal JSON helpers (no external dependency)
 * ======================================================================== */

/*
 * json_get_string: extract the string value for "key" from a JSON blob.
 * Returns a malloc'd string or NULL.  Handles escaped \" within values and
 * JSON escape sequences (\n, \t, \\, \/).
 */
static char* json_get_string(const char* json, const char* key) {
    if (!json || !key) return NULL;

    /* Build search pattern: "key" */
    size_t klen = strlen(key);
    char* pattern = malloc(klen + 4);
    snprintf(pattern, klen + 4, "\"%s\"", key);

    const char* p = strstr(json, pattern);
    free(pattern);
    if (!p) return NULL;

    /* Advance past "key" */
    p += klen + 2;

    /* Skip whitespace and colon */
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;

    if (*p != '"') return NULL;
    p++;  /* skip opening quote */

    /* Collect characters, handling escapes */
    size_t cap = 256;
    size_t len = 0;
    char* result = malloc(cap);

    while (*p && !(*p == '"' && (len == 0 || result[len-1] != '\\'))) {
        if (*p == '\\' && *(p+1)) {
            p++;  /* skip backslash */
            switch (*p) {
                case '"':  result[len++] = '"'; break;
                case '\\': result[len++] = '\\'; break;
                case '/':  result[len++] = '/'; break;
                case 'n':  result[len++] = '\n'; break;
                case 't':  result[len++] = '\t'; break;
                case 'r':  result[len++] = '\r'; break;
                default:   result[len++] = *p; break;
            }
        } else {
            result[len++] = *p;
        }
        p++;
        if (len + 2 >= cap) {
            cap *= 2;
            result = realloc(result, cap);
        }
    }

    result[len] = '\0';
    return result;
}

/*
 * json_get_int: extract an integer value for "key".
 * Returns the value, or default_val if not found.
 */
static int json_get_int(const char* json, const char* key, int default_val) {
    if (!json || !key) return default_val;

    size_t klen = strlen(key);
    char* pattern = malloc(klen + 4);
    snprintf(pattern, klen + 4, "\"%s\"", key);

    const char* p = strstr(json, pattern);
    free(pattern);
    if (!p) return default_val;

    p += klen + 2;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;

    return atoi(p);
}

/*
 * json_get_object: extract a nested object {...} for "key".
 * Returns malloc'd string with balanced braces, or NULL.
 */
static char* json_get_object(const char* json, const char* key) {
    if (!json || !key) return NULL;

    size_t klen = strlen(key);
    char* pattern = malloc(klen + 4);
    snprintf(pattern, klen + 4, "\"%s\"", key);

    const char* p = strstr(json, pattern);
    free(pattern);
    if (!p) return NULL;

    p += klen + 2;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;

    if (*p != '{') return NULL;

    int depth = 0;
    const char* start = p;
    int in_string = 0;

    while (*p) {
        if (*p == '\\' && in_string) {
            p++;  /* skip escaped char */
        } else if (*p == '"') {
            in_string = !in_string;
        } else if (!in_string) {
            if (*p == '{') depth++;
            else if (*p == '}') {
                depth--;
                if (depth == 0) {
                    p++;
                    size_t len = (size_t)(p - start);
                    char* result = malloc(len + 1);
                    memcpy(result, start, len);
                    result[len] = '\0';
                    return result;
                }
            }
        }
        p++;
    }

    return NULL;
}

/*
 * json_get_bool: extract a boolean for "key". Returns default_val if not found.
 */
__attribute__((unused))
static int json_get_bool(const char* json, const char* key, int default_val) {
    if (!json || !key) return default_val;

    size_t klen = strlen(key);
    char* pattern = malloc(klen + 4);
    snprintf(pattern, klen + 4, "\"%s\"", key);

    const char* p = strstr(json, pattern);
    free(pattern);
    if (!p) return default_val;

    p += klen + 2;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;

    if (strncmp(p, "true", 4) == 0) return 1;
    if (strncmp(p, "false", 5) == 0) return 0;
    return default_val;
}

/* ========================================================================
 * JSON string escaping
 * ======================================================================== */

static char* json_escape(const char* raw) {
    if (!raw) {
        char* empty = malloc(1);
        empty[0] = '\0';
        return empty;
    }

    size_t cap = strlen(raw) * 2 + 1;
    char* out = malloc(cap);
    size_t j = 0;

    for (size_t i = 0; raw[i]; i++) {
        if (j + 8 >= cap) {
            cap *= 2;
            out = realloc(out, cap);
        }
        switch (raw[i]) {
            case '"':  out[j++] = '\\'; out[j++] = '"'; break;
            case '\\': out[j++] = '\\'; out[j++] = '\\'; break;
            case '\n': out[j++] = '\\'; out[j++] = 'n'; break;
            case '\r': out[j++] = '\\'; out[j++] = 'r'; break;
            case '\t': out[j++] = '\\'; out[j++] = 't'; break;
            default:
                if ((unsigned char)raw[i] < 0x20) {
                    j += (size_t)snprintf(out + j, cap - j, "\\u%04x", (unsigned char)raw[i]);
                } else {
                    out[j++] = raw[i];
                }
                break;
        }
    }
    out[j] = '\0';
    return out;
}

/* ========================================================================
 * LSP Wire Protocol I/O
 * ======================================================================== */

/* Read a full LSP message from stdin. Returns malloc'd JSON body or NULL on EOF. */
static char* lsp_read_message(void) {
    /* Read headers */
    int content_length = -1;
    char header_line[512];

    while (1) {
        if (!fgets(header_line, sizeof(header_line), stdin)) {
            return NULL;  /* EOF */
        }

        /* Empty line (just \r\n) terminates headers */
        if (strcmp(header_line, "\r\n") == 0 || strcmp(header_line, "\n") == 0) {
            break;
        }

        if (strncmp(header_line, "Content-Length:", 15) == 0) {
            content_length = atoi(header_line + 15);
        }
        /* Ignore other headers (Content-Type, etc.) */
    }

    if (content_length <= 0) {
        lsp_log("Invalid or missing Content-Length");
        return NULL;
    }

    char* body = malloc((size_t)content_length + 1);
    size_t total_read = 0;
    while ((int)total_read < content_length) {
        size_t n = fread(body + total_read, 1, (size_t)(content_length - (int)total_read), stdin);
        if (n == 0) {
            free(body);
            return NULL;  /* EOF */
        }
        total_read += n;
    }
    body[content_length] = '\0';

    return body;
}

/* Send a JSON-RPC response/notification over stdout with Content-Length header. */
static void lsp_send(const char* json) {
    size_t len = strlen(json);
    fprintf(stdout, "Content-Length: %zu\r\n\r\n%s", len, json);
    fflush(stdout);
}

/* Send a JSON-RPC response with a given id and result body. */
static void lsp_send_response(const char* id_str, int id_is_string, const char* result_json) {
    size_t cap = strlen(result_json) + 256;
    char* msg = malloc(cap);

    if (id_is_string) {
        snprintf(msg, cap,
            "{\"jsonrpc\":\"2.0\",\"id\":\"%s\",\"result\":%s}",
            id_str, result_json);
    } else {
        snprintf(msg, cap,
            "{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":%s}",
            id_str, result_json);
    }

    lsp_send(msg);
    free(msg);
}

/* Send a JSON-RPC notification (no id). */
static void lsp_send_notification(const char* method, const char* params_json) {
    size_t cap = strlen(method) + strlen(params_json) + 128;
    char* msg = malloc(cap);
    snprintf(msg, cap,
        "{\"jsonrpc\":\"2.0\",\"method\":\"%s\",\"params\":%s}",
        method, params_json);
    lsp_send(msg);
    free(msg);
}

/* ========================================================================
 * Document storage
 * ======================================================================== */

#define MAX_DOCUMENTS 64

typedef struct {
    char* uri;
    char* content;
} Document;

static Document g_documents[MAX_DOCUMENTS];
static int g_document_count = 0;

static Document* doc_find(const char* uri) {
    for (int i = 0; i < g_document_count; i++) {
        if (g_documents[i].uri && strcmp(g_documents[i].uri, uri) == 0) {
            return &g_documents[i];
        }
    }
    return NULL;
}

static Document* doc_open(const char* uri, const char* content) {
    Document* existing = doc_find(uri);
    if (existing) {
        free(existing->content);
        existing->content = strdup(content);
        return existing;
    }

    if (g_document_count >= MAX_DOCUMENTS) {
        lsp_log("Maximum open documents reached (%d)", MAX_DOCUMENTS);
        return NULL;
    }

    Document* doc = &g_documents[g_document_count++];
    doc->uri = strdup(uri);
    doc->content = strdup(content);
    return doc;
}

static void doc_update(const char* uri, const char* content) {
    Document* doc = doc_find(uri);
    if (doc) {
        free(doc->content);
        doc->content = strdup(content);
    }
}

static void doc_close(const char* uri) {
    for (int i = 0; i < g_document_count; i++) {
        if (g_documents[i].uri && strcmp(g_documents[i].uri, uri) == 0) {
            free(g_documents[i].uri);
            free(g_documents[i].content);
            /* Move last element into this slot */
            if (i < g_document_count - 1) {
                g_documents[i] = g_documents[g_document_count - 1];
            }
            g_document_count--;
            return;
        }
    }
}

/* ========================================================================
 * ID extraction helper
 * ======================================================================== */

typedef struct {
    char str[128];
    int is_string;
} RequestId;

static RequestId extract_id(const char* json) {
    RequestId rid;
    rid.str[0] = '\0';
    rid.is_string = 0;

    /* Find "id" field */
    const char* p = strstr(json, "\"id\"");
    if (!p) return rid;

    p += 4;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' || *p == ':') p++;

    if (*p == '"') {
        /* String id */
        rid.is_string = 1;
        p++;
        size_t i = 0;
        while (*p && *p != '"' && i < sizeof(rid.str) - 1) {
            rid.str[i++] = *p++;
        }
        rid.str[i] = '\0';
    } else if (*p == '-' || (*p >= '0' && *p <= '9')) {
        /* Numeric id */
        rid.is_string = 0;
        size_t i = 0;
        while (*p && ((*p >= '0' && *p <= '9') || *p == '-') && i < sizeof(rid.str) - 1) {
            rid.str[i++] = *p++;
        }
        rid.str[i] = '\0';
    }

    return rid;
}

/* ========================================================================
 * Diagnostics (via linter)
 * ======================================================================== */

static void publish_diagnostics(const char* uri, const char* content) {
    LintOptions opts = lint_default_options();
    LintMessage* msgs = lint_source(content, "buffer", opts);

    /* Build diagnostics JSON array */
    size_t cap = 4096;
    char* diags = malloc(cap);
    size_t len = 0;

    diags[len++] = '[';

    int first = 1;
    for (LintMessage* m = msgs; m; m = m->next) {
        /* Map severity */
        int sev;
        switch (m->severity) {
            case LINT_ERROR:   sev = 1; break;
            case LINT_WARNING: sev = 2; break;
            case LINT_STYLE:   sev = 4; break; /* Hint */
            default:           sev = 3; break; /* Information */
        }

        char* esc_msg = json_escape(m->message);
        char* esc_rule = json_escape(m->rule ? m->rule : "");

        char diag_buf[1024];
        int diag_len = snprintf(diag_buf, sizeof(diag_buf),
            "%s{\"range\":{\"start\":{\"line\":%d,\"character\":%d},"
            "\"end\":{\"line\":%d,\"character\":%d}},"
            "\"severity\":%d,"
            "\"source\":\"sage-lint\","
            "\"code\":\"%s\","
            "\"message\":\"%s\"}",
            first ? "" : ",",
            m->line > 0 ? m->line - 1 : 0,    /* LSP lines are 0-based */
            m->column > 0 ? m->column - 1 : 0, /* LSP columns are 0-based */
            m->line > 0 ? m->line - 1 : 0,
            m->column > 0 ? m->column - 1 + 1 : 1, /* end 1 char further */
            sev, esc_rule, esc_msg);

        free(esc_msg);
        free(esc_rule);

        while (len + (size_t)diag_len + 2 >= cap) {
            cap *= 2;
            diags = realloc(diags, cap);
        }
        memcpy(diags + len, diag_buf, (size_t)diag_len);
        len += (size_t)diag_len;
        first = 0;
    }

    diags[len++] = ']';
    diags[len] = '\0';

    free_lint_messages(msgs);

    /* Build notification params */
    char* esc_uri = json_escape(uri);
    size_t params_cap = len + strlen(esc_uri) + 64;
    char* params = malloc(params_cap);
    snprintf(params, params_cap,
        "{\"uri\":\"%s\",\"diagnostics\":%s}",
        esc_uri, diags);
    free(esc_uri);
    free(diags);

    lsp_send_notification("textDocument/publishDiagnostics", params);
    free(params);
}

/* ========================================================================
 * Completion (keywords + builtins)
 * ======================================================================== */

typedef struct {
    const char* label;
    int kind;          /* LSP CompletionItemKind */
    const char* detail;
} CompletionEntry;

/* CompletionItemKind: 14=Keyword, 3=Function, 6=Variable */
static const CompletionEntry g_completions[] = {
    /* Keywords */
    {"let",       14, "Variable declaration"},
    {"var",       14, "Mutable variable declaration"},
    {"proc",      14, "Function/procedure definition"},
    {"if",        14, "Conditional statement"},
    {"else",      14, "Else branch"},
    {"while",     14, "While loop"},
    {"for",       14, "For loop"},
    {"in",        14, "In operator / for-in"},
    {"return",    14, "Return from function"},
    {"print",     14, "Print statement"},
    {"and",       14, "Logical AND"},
    {"or",        14, "Logical OR"},
    {"not",       14, "Logical NOT"},
    {"true",      14, "Boolean true"},
    {"false",     14, "Boolean false"},
    {"nil",       14, "Nil value"},
    {"class",     14, "Class definition"},
    {"self",      14, "Self reference"},
    {"init",      14, "Constructor"},
    {"import",    14, "Module import"},
    {"from",      14, "Import from"},
    {"as",        14, "Import alias"},
    {"match",     14, "Pattern matching"},
    {"case",      14, "Match case"},
    {"try",       14, "Try block"},
    {"catch",     14, "Catch handler"},
    {"finally",   14, "Finally block"},
    {"raise",     14, "Raise exception"},
    {"break",     14, "Break loop"},
    {"continue",  14, "Continue loop"},
    {"defer",     14, "Deferred execution"},
    {"yield",     14, "Yield from generator"},
    {"async",     14, "Async function"},
    {"await",     14, "Await expression"},
    /* Builtin functions */
    {"str",       3, "Convert value to string"},
    {"len",       3, "Get length of string/array/dict"},
    {"tonumber",  3, "Convert string to number"},
    {"clock",     3, "Get current time in seconds"},
    {"input",     3, "Read a line from stdin"},
    {"asm_arch",  3, "Get host architecture string"},
    {"push",      3, "Append element to array"},
    {"pop",       3, "Remove and return last element"},
    {"range",     3, "Generate array of numbers"},
    {"slice",     3, "Slice array or string"},
    {"split",     3, "Split string by delimiter"},
    {"join",      3, "Join array into string"},
    {"replace",   3, "Replace substring"},
    {"upper",     3, "Convert string to uppercase"},
    {"lower",     3, "Convert string to lowercase"},
    {"strip",     3, "Strip whitespace from string"},
    {"dict_keys",    3, "Get dictionary keys as array"},
    {"dict_values",  3, "Get dictionary values as array"},
    {"dict_has",     3, "Check if dictionary has key"},
    {"dict_delete",  3, "Delete key from dictionary"},
    {"mem_alloc",    3, "Allocate raw memory"},
    {"mem_free",     3, "Free raw memory"},
    {"mem_read",     3, "Read byte from memory"},
    {"mem_write",    3, "Write byte to memory"},
    {"mem_size",     3, "Get memory block size"},
    {"struct_def",   3, "Define a struct type"},
    {"struct_new",   3, "Create struct instance"},
    {"struct_get",   3, "Get struct field"},
    {"struct_set",   3, "Set struct field"},
    {"struct_size",  3, "Get struct size in bytes"},
    {NULL, 0, NULL}
};

static void handle_completion(const char* json, RequestId rid) {
    (void)json;

    /* Build items array */
    size_t cap = 8192;
    char* items = malloc(cap);
    size_t len = 0;
    items[len++] = '[';

    int first = 1;
    for (int i = 0; g_completions[i].label; i++) {
        char item_buf[512];
        char* esc_label = json_escape(g_completions[i].label);
        char* esc_detail = json_escape(g_completions[i].detail);
        int item_len = snprintf(item_buf, sizeof(item_buf),
            "%s{\"label\":\"%s\",\"kind\":%d,\"detail\":\"%s\"}",
            first ? "" : ",",
            esc_label, g_completions[i].kind, esc_detail);
        free(esc_label);
        free(esc_detail);

        while (len + (size_t)item_len + 2 >= cap) {
            cap *= 2;
            items = realloc(items, cap);
        }
        memcpy(items + len, item_buf, (size_t)item_len);
        len += (size_t)item_len;
        first = 0;
    }

    items[len++] = ']';
    items[len] = '\0';

    lsp_send_response(rid.str, rid.is_string, items);
    free(items);
}

/* ========================================================================
 * Hover (keyword/builtin documentation)
 * ======================================================================== */

typedef struct {
    const char* name;
    const char* doc;
} HoverEntry;

static const HoverEntry g_hover_docs[] = {
    {"let",    "**let** - Declare an immutable variable.\n\n```sage\nlet x = 42\n```"},
    {"var",    "**var** - Declare a mutable variable.\n\n```sage\nvar counter = 0\ncounter = counter + 1\n```"},
    {"proc",   "**proc** - Define a function/procedure.\n\n```sage\nproc greet(name):\n    print \"Hello, \" + name\n```"},
    {"if",     "**if** - Conditional statement.\n\n```sage\nif x > 0:\n    print \"positive\"\nelse:\n    print \"non-positive\"\n```"},
    {"while",  "**while** - Loop while condition is true.\n\n```sage\nwhile x > 0:\n    x = x - 1\n```"},
    {"for",    "**for** - Iterate over a range or collection.\n\n```sage\nfor i in range(10):\n    print i\n```"},
    {"class",  "**class** - Define a class.\n\n```sage\nclass Point:\n    init(self, x, y):\n        self.x = x\n        self.y = y\n```"},
    {"import", "**import** - Import a module.\n\n```sage\nimport math\n```"},
    {"match",  "**match** - Pattern matching.\n\n```sage\nmatch value:\n    case 1:\n        print \"one\"\n    case 2:\n        print \"two\"\n    default:\n        print \"other\"\n```"},
    {"try",    "**try** - Exception handling.\n\n```sage\ntry:\n    risky_operation()\ncatch e:\n    print \"Error: \" + str(e)\n```"},
    {"print",  "**print** - Print a value to stdout.\n\n```sage\nprint \"Hello, world!\"\nprint 42\n```"},
    {"return", "**return** - Return a value from a function.\n\n```sage\nproc add(a, b):\n    return a + b\n```"},
    {"str",       "**str(value)** - Convert any value to its string representation."},
    {"len",       "**len(value)** - Get the length of a string, array, or dictionary."},
    {"tonumber",  "**tonumber(s)** - Convert a string to a number."},
    {"clock",     "**clock()** - Returns current time in seconds (float)."},
    {"input",     "**input(prompt)** - Read a line from stdin with optional prompt."},
    {"push",      "**push(array, value)** - Append an element to an array."},
    {"pop",       "**pop(array)** - Remove and return the last element of an array."},
    {"range",     "**range(n)** or **range(start, end)** or **range(start, end, step)** - Generate an array of numbers."},
    {"slice",     "**slice(value, start, end)** - Slice an array or string."},
    {"split",     "**split(string, delimiter)** - Split a string by delimiter."},
    {"join",      "**join(array, separator)** - Join array elements into a string."},
    {"replace",   "**replace(string, old, new)** - Replace all occurrences of a substring."},
    {"upper",     "**upper(string)** - Convert string to uppercase."},
    {"lower",     "**lower(string)** - Convert string to lowercase."},
    {"strip",     "**strip(string)** - Remove leading/trailing whitespace."},
    {"dict_keys",    "**dict_keys(dict)** - Get all keys of a dictionary as an array."},
    {"dict_values",  "**dict_values(dict)** - Get all values of a dictionary as an array."},
    {"dict_has",     "**dict_has(dict, key)** - Check if dictionary contains a key."},
    {"dict_delete",  "**dict_delete(dict, key)** - Delete a key from a dictionary."},
    {"mem_alloc",    "**mem_alloc(size)** - Allocate a raw memory block of given size."},
    {"mem_free",     "**mem_free(ptr)** - Free a previously allocated memory block."},
    {"mem_read",     "**mem_read(ptr, offset)** - Read a byte from memory at offset."},
    {"mem_write",    "**mem_write(ptr, offset, value)** - Write a byte to memory at offset."},
    {"mem_size",     "**mem_size(ptr)** - Get the size of a memory block."},
    {"struct_def",   "**struct_def(name, fields)** - Define a struct type with named fields."},
    {"struct_new",   "**struct_new(type, ...)** - Create a new struct instance."},
    {"struct_get",   "**struct_get(instance, field)** - Get a field from a struct."},
    {"struct_set",   "**struct_set(instance, field, value)** - Set a field on a struct."},
    {"struct_size",  "**struct_size(type)** - Get the size of a struct type in bytes."},
    {"asm_arch",     "**asm_arch()** - Returns the host architecture as a string (e.g. \"x86-64\")."},
    {NULL, NULL}
};

/*
 * Get the word at a given line/character position in the document content.
 * Returns a malloc'd string or NULL.
 */
static char* get_word_at(const char* content, int line, int character) {
    if (!content) return NULL;

    /* Find the line */
    const char* p = content;
    for (int i = 0; i < line && *p; i++) {
        while (*p && *p != '\n') p++;
        if (*p == '\n') p++;
    }

    /* Now p points to the start of the target line */
    const char* line_start = p;
    int line_len = 0;
    while (line_start[line_len] && line_start[line_len] != '\n') line_len++;

    if (character >= line_len) return NULL;

    /* Find word boundaries */
    int start = character;
    int end = character;

    while (start > 0 && (line_start[start-1] == '_' ||
           (line_start[start-1] >= 'a' && line_start[start-1] <= 'z') ||
           (line_start[start-1] >= 'A' && line_start[start-1] <= 'Z') ||
           (line_start[start-1] >= '0' && line_start[start-1] <= '9'))) {
        start--;
    }

    while (end < line_len && (line_start[end] == '_' ||
           (line_start[end] >= 'a' && line_start[end] <= 'z') ||
           (line_start[end] >= 'A' && line_start[end] <= 'Z') ||
           (line_start[end] >= '0' && line_start[end] <= '9'))) {
        end++;
    }

    if (start == end) return NULL;

    int wlen = end - start;
    char* word = malloc((size_t)wlen + 1);
    memcpy(word, line_start + start, (size_t)wlen);
    word[wlen] = '\0';
    return word;
}

static void handle_hover(const char* json, RequestId rid) {
    /* Extract params */
    char* params = json_get_object(json, "params");
    if (!params) {
        lsp_send_response(rid.str, rid.is_string, "null");
        return;
    }

    char* td = json_get_object(params, "textDocument");
    char* pos = json_get_object(params, "position");

    char* uri = td ? json_get_string(td, "uri") : NULL;
    int line = pos ? json_get_int(pos, "line", 0) : 0;
    int character = pos ? json_get_int(pos, "character", 0) : 0;

    free(td);
    free(pos);
    free(params);

    if (!uri) {
        lsp_send_response(rid.str, rid.is_string, "null");
        return;
    }

    Document* doc = doc_find(uri);
    free(uri);

    if (!doc) {
        lsp_send_response(rid.str, rid.is_string, "null");
        return;
    }

    char* word = get_word_at(doc->content, line, character);
    if (!word) {
        lsp_send_response(rid.str, rid.is_string, "null");
        return;
    }

    /* Look up hover documentation */
    const char* hover_doc = NULL;
    for (int i = 0; g_hover_docs[i].name; i++) {
        if (strcmp(word, g_hover_docs[i].name) == 0) {
            hover_doc = g_hover_docs[i].doc;
            break;
        }
    }

    free(word);

    if (!hover_doc) {
        lsp_send_response(rid.str, rid.is_string, "null");
        return;
    }

    char* esc_doc = json_escape(hover_doc);
    size_t cap = strlen(esc_doc) + 128;
    char* result = malloc(cap);
    snprintf(result, cap,
        "{\"contents\":{\"kind\":\"markdown\",\"value\":\"%s\"}}",
        esc_doc);
    free(esc_doc);

    lsp_send_response(rid.str, rid.is_string, result);
    free(result);
}

/* ========================================================================
 * Formatting (via formatter)
 * ======================================================================== */

static void handle_formatting(const char* json, RequestId rid) {
    char* params = json_get_object(json, "params");
    if (!params) {
        lsp_send_response(rid.str, rid.is_string, "[]");
        return;
    }

    char* td = json_get_object(params, "textDocument");
    char* uri = td ? json_get_string(td, "uri") : NULL;
    free(td);
    free(params);

    if (!uri) {
        lsp_send_response(rid.str, rid.is_string, "[]");
        return;
    }

    Document* doc = doc_find(uri);
    free(uri);

    if (!doc || !doc->content) {
        lsp_send_response(rid.str, rid.is_string, "[]");
        return;
    }

    FormatOptions fmt_opts = format_default_options();
    char* formatted = format_source(doc->content, fmt_opts);

    if (!formatted || strcmp(doc->content, formatted) == 0) {
        /* No changes needed */
        free(formatted);
        lsp_send_response(rid.str, rid.is_string, "[]");
        return;
    }

    /* Count lines in original content */
    int line_count = 1;
    for (const char* p = doc->content; *p; p++) {
        if (*p == '\n') line_count++;
    }

    /* Return a single TextEdit replacing the entire document */
    char* esc_text = json_escape(formatted);
    free(formatted);

    size_t cap = strlen(esc_text) + 256;
    char* result = malloc(cap);
    snprintf(result, cap,
        "[{\"range\":{\"start\":{\"line\":0,\"character\":0},"
        "\"end\":{\"line\":%d,\"character\":0}},"
        "\"newText\":\"%s\"}]",
        line_count, esc_text);
    free(esc_text);

    lsp_send_response(rid.str, rid.is_string, result);
    free(result);
}

/* ========================================================================
 * Lifecycle handlers
 * ======================================================================== */

static void handle_initialize(const char* json, RequestId rid) {
    (void)json;

    const char* result =
        "{"
        "\"capabilities\":{"
            "\"textDocumentSync\":{"
                "\"openClose\":true,"
                "\"change\":1"  /* Full sync */
            "},"
            "\"completionProvider\":{"
                "\"triggerCharacters\":[\".\"]},"
            "\"hoverProvider\":true,"
            "\"documentFormattingProvider\":true"
        "},"
        "\"serverInfo\":{"
            "\"name\":\"sage-lsp\","
            "\"version\":\"0.1.0\""
        "}"
        "}";

    lsp_send_response(rid.str, rid.is_string, result);
    lsp_log("Initialized");
}

/* ========================================================================
 * Main dispatch loop
 * ======================================================================== */

void lsp_run(void) {
    lsp_log("Starting Sage Language Server...");

    int shutdown_requested = 0;

    while (1) {
        char* body = lsp_read_message();
        if (!body) {
            lsp_log("EOF on stdin, exiting");
            break;
        }

        char* method = json_get_string(body, "method");
        if (!method) {
            /* Response or unknown message, ignore */
            free(body);
            continue;
        }

        RequestId rid = extract_id(body);

        lsp_log("Received: %s", method);

        /* ---- Lifecycle ---- */
        if (strcmp(method, "initialize") == 0) {
            handle_initialize(body, rid);
        }
        else if (strcmp(method, "initialized") == 0) {
            /* No-op notification */
        }
        else if (strcmp(method, "shutdown") == 0) {
            shutdown_requested = 1;
            lsp_send_response(rid.str, rid.is_string, "null");
            lsp_log("Shutdown requested");
        }
        else if (strcmp(method, "exit") == 0) {
            free(method);
            free(body);
            lsp_log("Exiting (code %d)", shutdown_requested ? 0 : 1);
            exit(shutdown_requested ? 0 : 1);
        }

        /* ---- Document sync ---- */
        else if (strcmp(method, "textDocument/didOpen") == 0) {
            char* params = json_get_object(body, "params");
            char* td = params ? json_get_object(params, "textDocument") : NULL;
            char* uri = td ? json_get_string(td, "uri") : NULL;
            char* text = td ? json_get_string(td, "text") : NULL;

            if (uri && text) {
                doc_open(uri, text);
                lsp_log("Opened: %s", uri);
                publish_diagnostics(uri, text);
            }

            free(uri);
            free(text);
            free(td);
            free(params);
        }
        else if (strcmp(method, "textDocument/didChange") == 0) {
            char* params = json_get_object(body, "params");
            char* td = params ? json_get_object(params, "textDocument") : NULL;
            char* uri = td ? json_get_string(td, "uri") : NULL;

            /* For full sync, the text is in contentChanges[0].text */
            /* Simple extraction: find "contentChanges" then find "text" */
            char* text = NULL;
            if (params) {
                const char* cc = strstr(params, "\"contentChanges\"");
                if (cc) {
                    /* Find the first "text" after contentChanges */
                    const char* text_key = strstr(cc, "\"text\"");
                    if (text_key) {
                        text_key += 6; /* skip "text" */
                        while (*text_key == ' ' || *text_key == '\t' ||
                               *text_key == '\n' || *text_key == '\r' ||
                               *text_key == ':') text_key++;
                        if (*text_key == '"') {
                            /* Extract the string value manually */
                            text_key++;
                            size_t cap = 4096;
                            size_t len = 0;
                            text = malloc(cap);
                            while (*text_key && !(*text_key == '"' &&
                                   (len == 0 || text[len-1] != '\\'))) {
                                if (*text_key == '\\' && *(text_key+1)) {
                                    text_key++;
                                    switch (*text_key) {
                                        case '"':  text[len++] = '"'; break;
                                        case '\\': text[len++] = '\\'; break;
                                        case 'n':  text[len++] = '\n'; break;
                                        case 'r':  text[len++] = '\r'; break;
                                        case 't':  text[len++] = '\t'; break;
                                        default:   text[len++] = *text_key; break;
                                    }
                                } else {
                                    text[len++] = *text_key;
                                }
                                text_key++;
                                if (len + 2 >= cap) {
                                    cap *= 2;
                                    text = realloc(text, cap);
                                }
                            }
                            text[len] = '\0';
                        }
                    }
                }
            }

            if (uri && text) {
                doc_update(uri, text);
                lsp_log("Changed: %s", uri);
                publish_diagnostics(uri, text);
            }

            free(uri);
            free(text);
            free(td);
            free(params);
        }
        else if (strcmp(method, "textDocument/didClose") == 0) {
            char* params = json_get_object(body, "params");
            char* td = params ? json_get_object(params, "textDocument") : NULL;
            char* uri = td ? json_get_string(td, "uri") : NULL;

            if (uri) {
                doc_close(uri);
                lsp_log("Closed: %s", uri);
                /* Publish empty diagnostics to clear them */
                char* esc_uri = json_escape(uri);
                size_t cap2 = strlen(esc_uri) + 64;
                char* clear_params = malloc(cap2);
                snprintf(clear_params, cap2,
                    "{\"uri\":\"%s\",\"diagnostics\":[]}", esc_uri);
                lsp_send_notification("textDocument/publishDiagnostics", clear_params);
                free(clear_params);
                free(esc_uri);
            }

            free(uri);
            free(td);
            free(params);
        }

        /* ---- Features ---- */
        else if (strcmp(method, "textDocument/completion") == 0) {
            handle_completion(body, rid);
        }
        else if (strcmp(method, "textDocument/hover") == 0) {
            handle_hover(body, rid);
        }
        else if (strcmp(method, "textDocument/formatting") == 0) {
            handle_formatting(body, rid);
        }

        /* ---- Unknown ---- */
        else {
            /* If it has an id, respond with MethodNotFound */
            if (rid.str[0] != '\0') {
                size_t errcap = 256 + strlen(method);
                char* errmsg = malloc(errcap);
                char* esc_method = json_escape(method);
                snprintf(errmsg, errcap,
                    "{\"jsonrpc\":\"2.0\",\"id\":%s%s%s,\"error\":"
                    "{\"code\":-32601,\"message\":\"Method not found: %s\"}}",
                    rid.is_string ? "\"" : "",
                    rid.str,
                    rid.is_string ? "\"" : "",
                    esc_method);
                free(esc_method);
                lsp_send(errmsg);
                free(errmsg);
            }
            lsp_log("Unhandled method: %s", method);
        }

        free(method);
        free(body);
    }

    /* Cleanup documents */
    for (int i = 0; i < g_document_count; i++) {
        free(g_documents[i].uri);
        free(g_documents[i].content);
    }
    g_document_count = 0;
}
