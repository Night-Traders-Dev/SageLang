#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "formatter.h"
#include "gc.h"  // SAGE_ALLOC/SAGE_REALLOC for safe allocation

/* ========================================================================
 * SageLang Code Formatter (sage fmt)
 *
 * Works at the source text level to preserve comments.
 * Rules:
 *   1. Normalize indentation to multiples of indent_width spaces
 *   2. Remove trailing whitespace
 *   3. Single blank line between top-level proc/class definitions
 *   4. No more than max_blank_lines consecutive blank lines
 *   5. File ends with exactly one newline
 *   6. Normalize spaces around operators (outside strings)
 *   7. Normalize spaces after commas (outside strings)
 *   8. Remove spaces before colons at end of block headers
 *   9. Ensure space after # in comments (preserve #! shebangs)
 * ======================================================================== */

FormatOptions format_default_options(void) {
    FormatOptions opts;
    opts.indent_width = 4;
    opts.max_blank_lines = 2;
    opts.normalize_operators = 1;
    return opts;
}

/* ---------- dynamic string buffer ---------- */

typedef struct {
    char* data;
    size_t len;
    size_t cap;
} StrBuf;

static void sb_init(StrBuf* sb) {
    sb->cap = 4096;
    sb->data = SAGE_ALLOC(sb->cap);
    sb->len = 0;
    sb->data[0] = '\0';
}

static void sb_ensure(StrBuf* sb, size_t extra) {
    while (sb->len + extra + 1 > sb->cap) {
        sb->cap *= 2;
        sb->data = SAGE_REALLOC(sb->data, sb->cap);
    }
}

static void sb_append(StrBuf* sb, const char* s, size_t n) {
    sb_ensure(sb, n);
    memcpy(sb->data + sb->len, s, n);
    sb->len += n;
    sb->data[sb->len] = '\0';
}

static void sb_append_str(StrBuf* sb, const char* s) {
    sb_append(sb, s, strlen(s));
}

static void sb_append_char(StrBuf* sb, char c) {
    sb_ensure(sb, 1);
    sb->data[sb->len++] = c;
    sb->data[sb->len] = '\0';
}

static void sb_append_spaces(StrBuf* sb, int count) {
    sb_ensure(sb, (size_t)count);
    for (int i = 0; i < count; i++) {
        sb->data[sb->len++] = ' ';
    }
    sb->data[sb->len] = '\0';
}

/* ---------- helper: check if stripped line starts a top-level def ---------- */

static int is_toplevel_def(const char* stripped) {
    return (strncmp(stripped, "proc ", 5) == 0 ||
            strncmp(stripped, "async proc ", 11) == 0 ||
            strncmp(stripped, "class ", 6) == 0);
}

/* ---------- helper: check if line is a block header ending with : ---------- */

static int is_block_header(const char* stripped) {
    /* Check if line ends with ':' */
    size_t len = strlen(stripped);
    size_t end = len;
    while (end > 0 && (stripped[end - 1] == ' ' || stripped[end - 1] == ':')) {
        if (stripped[end - 1] == ':') {
            /* Found a colon -- now check if line starts with a block keyword */
            static const char* block_kw[] = {
                "proc ", "async proc ", "class ", "if ", "elif ", "else",
                "for ", "while ", "try", "catch ", "finally", "match ",
                "case ", NULL
            };
            for (int i = 0; block_kw[i]; i++) {
                size_t kwlen = strlen(block_kw[i]);
                if (len >= kwlen && strncmp(stripped, block_kw[i], kwlen) == 0) return 1;
            }
            return 0;
        }
        end--;
    }
    return 0;
}

/* ---------- operator normalization ---------- */

/* Check if character at pos is part of a two-char operator starting at pos */
static int is_two_char_op(const char* s, size_t pos, size_t len) {
    if (pos + 1 >= len) return 0;
    char c0 = s[pos], c1 = s[pos + 1];
    return (c0 == '=' && c1 == '=') ||
           (c0 == '!' && c1 == '=') ||
           (c0 == '<' && c1 == '=') ||
           (c0 == '>' && c1 == '=') ||
           (c0 == '+' && c1 == '=') ||
           (c0 == '-' && c1 == '=') ||
           (c0 == '*' && c1 == '=') ||
           (c0 == '/' && c1 == '=');
}

/* Check if this is a keyword operator: and, or, not */
static int is_keyword_op_at(const char* s, size_t pos, size_t len, const char* kw) {
    size_t kwlen = strlen(kw);
    if (pos + kwlen > len) return 0;
    if (strncmp(s + pos, kw, kwlen) != 0) return 0;
    /* Must be word boundary before */
    if (pos > 0 && (isalnum((unsigned char)s[pos - 1]) || s[pos - 1] == '_')) return 0;
    /* Must be word boundary after */
    if (pos + kwlen < len && (isalnum((unsigned char)s[pos + kwlen]) || s[pos + kwlen] == '_')) return 0;
    return 1;
}

/*
 * Normalize operators in a line content (after indentation, before trailing
 * whitespace has been stripped). Preserves string literals.
 */
static char* normalize_operators(const char* content) {
    size_t len = strlen(content);
    /* Worst case: every char becomes " x ", so 3x + 1 */
    size_t cap = len * 3 + 64;
    char* out = SAGE_ALLOC(cap);
    size_t oi = 0;

    char in_string = 0;  /* 0, '\'', or '"' */
    size_t i = 0;

#define OUT(c) do { if (oi + 4 >= cap) { cap *= 2; out = SAGE_REALLOC(out, cap); } out[oi++] = (c); } while(0)

    while (i < len) {
        char c = content[i];

        /* Track string state */
        if (!in_string && (c == '\'' || c == '"')) {
            in_string = c;
            OUT(c);
            i++;
            continue;
        }
        if (in_string) {
            OUT(c);
            if (c == '\\' && i + 1 < len) {
                /* escaped char */
                i++;
                OUT(content[i]);
                i++;
                continue;
            }
            if (c == in_string) {
                in_string = 0;
            }
            i++;
            continue;
        }

        /* Comment: pass through rest of line as-is */
        if (c == '#') {
            while (i < len) {
                OUT(content[i]);
                i++;
            }
            break;
        }

        /* Keyword operators: and, or, not */
        if (is_keyword_op_at(content, i, len, "and")) {
            /* Ensure space before */
            if (oi > 0 && out[oi - 1] != ' ') OUT(' ');
            OUT('a'); OUT('n'); OUT('d');
            i += 3;
            /* Ensure space after */
            if (i < len && content[i] != ' ') OUT(' ');
            continue;
        }
        if (is_keyword_op_at(content, i, len, "or")) {
            if (oi > 0 && out[oi - 1] != ' ') OUT(' ');
            OUT('o'); OUT('r');
            i += 2;
            if (i < len && content[i] != ' ') OUT(' ');
            continue;
        }
        if (is_keyword_op_at(content, i, len, "not")) {
            if (oi > 0 && out[oi - 1] != ' ') OUT(' ');
            OUT('n'); OUT('o'); OUT('t');
            i += 3;
            if (i < len && content[i] != ' ') OUT(' ');
            continue;
        }

        /* Two-char operators */
        if (is_two_char_op(content, i, len)) {
            /* Remove any trailing spaces we just wrote */
            while (oi > 0 && out[oi - 1] == ' ') oi--;
            OUT(' ');
            OUT(content[i]);
            OUT(content[i + 1]);
            OUT(' ');
            i += 2;
            /* Skip any spaces after the operator in input */
            while (i < len && content[i] == ' ') i++;
            continue;
        }

        /* Single = (assignment), but not == (already handled) */
        if (c == '=' && (i + 1 >= len || content[i + 1] != '=') &&
            (i == 0 || (content[i - 1] != '!' && content[i - 1] != '<' &&
                        content[i - 1] != '>' && content[i - 1] != '+' &&
                        content[i - 1] != '-' && content[i - 1] != '*' &&
                        content[i - 1] != '/'))) {
            while (oi > 0 && out[oi - 1] == ' ') oi--;
            OUT(' ');
            OUT('=');
            OUT(' ');
            i++;
            while (i < len && content[i] == ' ') i++;
            continue;
        }

        /* Single-char comparison operators: < > */
        if ((c == '<' || c == '>') && (i + 1 >= len || (content[i + 1] != '='))) {
            while (oi > 0 && out[oi - 1] == ' ') oi--;
            OUT(' ');
            OUT(c);
            OUT(' ');
            i++;
            while (i < len && content[i] == ' ') i++;
            continue;
        }

        /* Arithmetic operators: + - * / %
         * Be careful with:
         *   - Unary minus/plus (after operator, open paren, comma, or at start)
         *   - ** (power, if supported) -- treat as two *
         *   - Negative numbers in contexts like range(-5, 5)
         */
        if ((c == '+' || c == '-' || c == '*' || c == '/' || c == '%') &&
            (i + 1 >= len || content[i + 1] != '=')) {

            /* Detect unary: after ( , = or at start of content, or after another operator */
            int is_unary = 0;
            if (c == '-' || c == '+') {
                /* Look back past spaces for context */
                size_t back = oi;
                while (back > 0 && out[back - 1] == ' ') back--;
                if (back == 0) {
                    is_unary = 1;
                } else {
                    char prev = out[back - 1];
                    if (prev == '(' || prev == '[' || prev == ',' ||
                        prev == '=' || prev == '<' || prev == '>' ||
                        prev == '+' || prev == '-' || prev == '*' ||
                        prev == '/' || prev == '%' || prev == ':') {
                        is_unary = 1;
                    }
                }
            }

            if (is_unary) {
                OUT(c);
                i++;
                continue;
            }

            /* Binary operator: ensure spaces around it */
            while (oi > 0 && out[oi - 1] == ' ') oi--;
            OUT(' ');
            OUT(c);
            OUT(' ');
            i++;
            while (i < len && content[i] == ' ') i++;
            continue;
        }

        /* Comma normalization: ensure exactly one space after comma */
        if (c == ',') {
            OUT(',');
            i++;
            /* Skip spaces after comma in input */
            while (i < len && content[i] == ' ') i++;
            /* Add exactly one space if not at end */
            if (i < len) OUT(' ');
            continue;
        }

        /* Collapse multiple spaces to one */
        if (c == ' ') {
            OUT(' ');
            i++;
            while (i < len && content[i] == ' ') i++;
            continue;
        }

        /* Default: pass through */
        OUT(c);
        i++;
    }

    out[oi] = '\0';
#undef OUT
    return out;
}

/* ---------- normalize comment: ensure space after # ---------- */

static void normalize_comment(const char* line, StrBuf* sb) {
    /* Find # that's not inside a string */
    char in_string = 0;
    size_t len = strlen(line);

    for (size_t i = 0; i < len; i++) {
        char c = line[i];

        if (!in_string && (c == '\'' || c == '"')) {
            in_string = c;
            sb_append_char(sb, c);
            continue;
        }
        if (in_string) {
            sb_append_char(sb, c);
            if (c == '\\' && i + 1 < len) {
                i++;
                sb_append_char(sb, line[i]);
                continue;
            }
            if (c == in_string) {
                in_string = 0;
            }
            continue;
        }

        if (c == '#') {
            sb_append_char(sb, '#');
            i++;
            /* Preserve #! shebangs */
            if (i < len && line[i] == '!') {
                sb_append(sb, line + i, len - i);
                return;
            }
            /* Ensure space after # */
            if (i < len && line[i] != ' ' && line[i] != '\t') {
                sb_append_char(sb, ' ');
            }
            /* Append rest */
            if (i < len) {
                sb_append(sb, line + i, len - i);
            }
            return;
        }

        sb_append_char(sb, c);
    }
}

/* ---------- remove space before colon at end of block header ---------- */

static char* strip_colon_space(const char* line) {
    size_t len = strlen(line);
    if (len == 0) return strdup(line);

    /* Check if line ends with ':' (possibly with spaces before it) */
    size_t end = len;
    /* Already trimmed trailing whitespace, so last char check */
    if (line[end - 1] != ':') return strdup(line);

    /* Walk backwards from the colon, past spaces */
    size_t colon_pos = end - 1;
    size_t space_start = colon_pos;
    while (space_start > 0 && line[space_start - 1] == ' ') {
        space_start--;
    }

    if (space_start == colon_pos) {
        /* No extra spaces before colon */
        return strdup(line);
    }

    /* Rebuild without the spaces before the colon */
    char* result = SAGE_ALLOC(space_start + 2);
    memcpy(result, line, space_start);
    result[space_start] = ':';
    result[space_start + 1] = '\0';
    return result;
}

/* ---------- split source into lines ---------- */

typedef struct {
    char** lines;
    int count;
} LineArray;

static LineArray split_lines(const char* source) {
    LineArray la;
    la.count = 0;
    int cap = 256;
    la.lines = SAGE_ALLOC(sizeof(char*) * (size_t)cap);

    const char* p = source;
    while (*p) {
        const char* eol = strchr(p, '\n');
        size_t line_len;
        if (eol) {
            line_len = (size_t)(eol - p);
        } else {
            line_len = strlen(p);
        }

        char* line = SAGE_ALLOC(line_len + 1);
        memcpy(line, p, line_len);
        line[line_len] = '\0';

        /* Strip \r */
        if (line_len > 0 && line[line_len - 1] == '\r') {
            line[line_len - 1] = '\0';
        }

        if (la.count >= cap) {
            cap *= 2;
            la.lines = SAGE_REALLOC(la.lines, sizeof(char*) * (size_t)cap);
        }
        la.lines[la.count++] = line;

        if (eol) {
            p = eol + 1;
        } else {
            break;
        }
    }

    return la;
}

static void free_line_array(LineArray* la) {
    for (int i = 0; i < la->count; i++) {
        free(la->lines[i]);
    }
    free(la->lines);
}

/* ---------- main formatting function ---------- */

char* format_source(const char* source, FormatOptions opts) {
    if (!source) return NULL;

    LineArray la = split_lines(source);
    StrBuf result;
    sb_init(&result);

    int consecutive_blanks = 0;
    int prev_was_toplevel_def_body = 0;  /* last non-blank was inside a top-level def */
    int prev_indent_level = -1;          /* indent level of previous non-blank line */
    int prev_was_toplevel_def_start = 0; /* previous non-blank started a top-level def */

    for (int i = 0; i < la.count; i++) {
        char* raw = la.lines[i];

        /* Count leading whitespace (spaces and tabs) and get content */
        int leading_spaces = 0;
        const char* p = raw;
        while (*p == ' ' || *p == '\t') {
            if (*p == '\t') leading_spaces += opts.indent_width;
            else leading_spaces++;
            p++;
        }
        /* p now points to the content after leading whitespace */

        /* Trim trailing whitespace from content */
        size_t content_len = strlen(p);
        char* content = SAGE_ALLOC(content_len + 1);
        memcpy(content, p, content_len + 1);
        while (content_len > 0 && (content[content_len - 1] == ' ' ||
               content[content_len - 1] == '\t' || content[content_len - 1] == '\r')) {
            content_len--;
        }
        content[content_len] = '\0';

        /* Handle blank lines */
        if (content_len == 0) {
            consecutive_blanks++;
            free(content);

            /* Enforce max_blank_lines */
            if (consecutive_blanks <= opts.max_blank_lines) {
                sb_append_char(&result, '\n');
            }
            continue;
        }

        /* Non-blank line */
        int indent_level = leading_spaces / opts.indent_width;
        int is_top_def = (indent_level == 0 && is_toplevel_def(content));

        /* Insert blank line before top-level def if previous wasn't blank */
        if (is_top_def && i > 0 && consecutive_blanks == 0 &&
            prev_indent_level >= 0) {
            sb_append_char(&result, '\n');
        }

        consecutive_blanks = 0;

        /* Normalize indentation */
        int normalized_indent = indent_level * opts.indent_width;

        /* Process content */
        char* processed = content;

        /* Operator normalization */
        if (opts.normalize_operators) {
            char* norm = normalize_operators(processed);
            if (processed != content) free(processed);
            processed = norm;
        }

        /* Comment normalization: ensure space after # */
        {
            StrBuf comment_buf;
            sb_init(&comment_buf);
            normalize_comment(processed, &comment_buf);
            if (processed != content) free(processed);
            processed = comment_buf.data;
        }

        /* Strip space before colon at end of block headers */
        if (is_block_header(content)) {
            char* stripped = strip_colon_space(processed);
            if (processed != content) free(processed);
            processed = stripped;
        }

        /* Build the formatted line */
        sb_append_spaces(&result, normalized_indent);
        sb_append_str(&result, processed);
        sb_append_char(&result, '\n');

        prev_indent_level = indent_level;
        prev_was_toplevel_def_start = is_top_def;
        (void)prev_was_toplevel_def_body;
        (void)prev_was_toplevel_def_start;

        if (processed != content) free(processed);
        free(content);
    }

    free_line_array(&la);

    /* Ensure file ends with exactly one newline */
    /* Remove trailing blank lines (extra newlines) */
    while (result.len > 1 && result.data[result.len - 1] == '\n' &&
           result.data[result.len - 2] == '\n') {
        result.len--;
    }
    /* Ensure at least one newline at end */
    if (result.len == 0 || result.data[result.len - 1] != '\n') {
        sb_append_char(&result, '\n');
    }

    result.data[result.len] = '\0';
    return result.data;
}

/* ---------- file-level formatting ---------- */

int format_file(const char* input_path, const char* output_path, FormatOptions opts) {
    FILE* f = fopen(input_path, "rb");
    if (!f) {
        fprintf(stderr, "sage fmt: cannot open '%s'\n", input_path);
        return 0;
    }

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    rewind(f);

    if (sz < 0) {
        fclose(f);
        fprintf(stderr, "sage fmt: cannot determine size of '%s'\n", input_path);
        return 0;
    }

    char* source = SAGE_ALLOC((size_t)sz + 1);
    size_t nread = fread(source, 1, (size_t)sz, f);
    source[nread] = '\0';
    fclose(f);

    char* formatted = format_source(source, opts);
    free(source);

    if (!formatted) {
        fprintf(stderr, "sage fmt: formatting failed for '%s'\n", input_path);
        return 0;
    }

    /* If output_path is NULL, write back to input_path (in-place) */
    const char* dest = output_path ? output_path : input_path;

    FILE* out = fopen(dest, "wb");
    if (!out) {
        fprintf(stderr, "sage fmt: cannot write to '%s'\n", dest);
        free(formatted);
        return 0;
    }

    size_t flen = strlen(formatted);
    fwrite(formatted, 1, flen, out);
    fclose(out);
    free(formatted);
    return 1;
}
