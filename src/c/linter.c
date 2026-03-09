#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "linter.h"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

LintOptions lint_default_options(void) {
    LintOptions opts;
    opts.check_unused_vars = 1;
    opts.check_naming = 1;
    opts.check_style = 1;
    opts.check_complexity = 1;
    return opts;
}

static LintMessage* make_msg(int line, int col, LintSeverity sev,
                              const char* rule, const char* message) {
    LintMessage* m = calloc(1, sizeof(LintMessage));
    m->line = line;
    m->column = col;
    m->severity = sev;
    m->rule = strdup(rule);
    m->message = strdup(message);
    m->next = NULL;
    return m;
}

static void append_msg(LintMessage** head, LintMessage** tail, LintMessage* m) {
    if (*head == NULL) {
        *head = m;
    } else {
        (*tail)->next = m;
    }
    *tail = m;
}

// Split source into lines.  Returns malloc'd array of line pointers (into src)
// and sets *count.  Caller must free the array (not the strings).
static char** split_lines(const char* src, int* count) {
    int cap = 256;
    int n = 0;
    char** lines = malloc(sizeof(char*) * (size_t)cap);

    const char* p = src;
    while (*p) {
        if (n >= cap) {
            cap *= 2;
            lines = realloc(lines, sizeof(char*) * (size_t)cap);
        }
        lines[n++] = (char*)p;
        const char* eol = strchr(p, '\n');
        if (eol) {
            p = eol + 1;
        } else {
            break;
        }
    }
    *count = n;
    return lines;
}

// Return the length of a line (excluding newline).
static int line_len(const char* line) {
    int len = 0;
    while (line[len] != '\0' && line[len] != '\n') {
        len++;
    }
    return len;
}

// Copy a line into a NUL-terminated buffer (up to max-1 chars).
static void copy_line(char* dst, const char* line, int max) {
    int len = line_len(line);
    if (len >= max) len = max - 1;
    memcpy(dst, line, (size_t)len);
    dst[len] = '\0';
}

// Check if line is inside a multi-line string (very rough).
// We just count unescaped quotes from the start of the file.
// Returns 1 if inside a string at the START of this line.
// NOTE: This is approximate.
static int* compute_in_string_map(char** lines, int nlines) {
    int* map = calloc((size_t)nlines, sizeof(int));
    int in_string = 0;
    char quote_char = 0;

    for (int i = 0; i < nlines; i++) {
        map[i] = in_string;
        int ll = line_len(lines[i]);
        for (int j = 0; j < ll; j++) {
            char c = lines[i][j];
            if (in_string) {
                if (c == '\\') {
                    j++; // skip escaped char
                } else if (c == quote_char) {
                    in_string = 0;
                }
            } else {
                if (c == '#') break; // rest is comment
                if (c == '"' || c == '\'') {
                    // Check for triple quotes
                    if (j + 2 < ll && lines[i][j+1] == c && lines[i][j+2] == c) {
                        // Triple quote -- toggle multi-line string
                        in_string = 1;
                        quote_char = c;
                        j += 2;
                    } else {
                        // Single-line string -- scan to end
                        char q = c;
                        j++;
                        while (j < ll) {
                            if (lines[i][j] == '\\') { j++; }
                            else if (lines[i][j] == q) break;
                            j++;
                        }
                    }
                }
            }
        }
    }
    return map;
}

// Return indentation width of a line (number of leading spaces/tabs).
// Sets *has_tab and *has_space.
static int measure_indent(const char* line, int* has_tab, int* has_space) {
    int w = 0;
    *has_tab = 0;
    *has_space = 0;
    for (int i = 0; line[i] != '\0' && line[i] != '\n'; i++) {
        if (line[i] == ' ') { w++; *has_space = 1; }
        else if (line[i] == '\t') { w += 4; *has_tab = 1; }
        else break;
    }
    return w;
}

static int is_blank_line(const char* line) {
    int ll = line_len(line);
    for (int i = 0; i < ll; i++) {
        if (line[i] != ' ' && line[i] != '\t' && line[i] != '\r') return 0;
    }
    return 1;
}

// Check if a name is snake_case: lowercase letters, digits, underscores.
static int is_snake_case(const char* name) {
    if (!name || !*name) return 1;
    for (int i = 0; name[i]; i++) {
        char c = name[i];
        if (!islower(c) && !isdigit(c) && c != '_') return 0;
    }
    return 1;
}

// Check if a name is PascalCase: starts with uppercase.
static int is_pascal_case(const char* name) {
    if (!name || !*name) return 0;
    return isupper(name[0]);
}

// Extract an identifier after a keyword at position `start` in line buf.
// Returns a malloc'd string or NULL.
static char* extract_ident_after(const char* buf, int start) {
    int i = start;
    while (buf[i] == ' ' || buf[i] == '\t') i++;
    if (!isalpha(buf[i]) && buf[i] != '_') return NULL;
    int begin = i;
    while (isalnum(buf[i]) || buf[i] == '_') i++;
    int len = i - begin;
    char* name = malloc((size_t)len + 1);
    memcpy(name, buf + begin, (size_t)len);
    name[len] = '\0';
    return name;
}

// ---------------------------------------------------------------------------
// Variable tracking (for unused-var and shadow detection)
// ---------------------------------------------------------------------------

typedef struct VarEntry {
    char* name;
    int decl_line;
    int indent;
    int used;
    struct VarEntry* next;
} VarEntry;

static VarEntry* var_new(const char* name, int line, int indent) {
    VarEntry* v = calloc(1, sizeof(VarEntry));
    v->name = strdup(name);
    v->decl_line = line;
    v->indent = indent;
    v->used = 0;
    v->next = NULL;
    return v;
}

static void var_free_list(VarEntry* list) {
    while (list) {
        VarEntry* next = list->next;
        free(list->name);
        free(list);
        list = next;
    }
}

// Check if `name` appears as a word in the line (not as part of let/var decl).
// Simple substring search with word-boundary checks.
static int name_appears_in_line(const char* line, int ll, const char* name) {
    int nlen = (int)strlen(name);
    for (int i = 0; i <= ll - nlen; i++) {
        if (memcmp(line + i, name, (size_t)nlen) == 0) {
            // Check word boundaries
            int before_ok = (i == 0 || (!isalnum(line[i-1]) && line[i-1] != '_'));
            int after_ok = (i + nlen >= ll || (!isalnum(line[i+nlen]) && line[i+nlen] != '_'));
            if (before_ok && after_ok) return 1;
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Core linting
// ---------------------------------------------------------------------------

LintMessage* lint_source(const char* source, const char* filename, LintOptions opts) {
    (void)filename;

    LintMessage* head = NULL;
    LintMessage* tail = NULL;

    int nlines = 0;
    char** lines = split_lines(source, &nlines);
    int* in_string = compute_in_string_map(lines, nlines);

    // Variable tracking
    VarEntry* vars = NULL;

    // Track control flow for unreachable code detection
    int prev_is_return = 0;
    int prev_indent = -1;

    char buf[2048];

    for (int i = 0; i < nlines; i++) {
        int lineno = i + 1;
        int ll = line_len(lines[i]);
        copy_line(buf, lines[i], (int)sizeof(buf));

        // Skip lines inside multi-line strings
        if (in_string[i]) {
            prev_is_return = 0;
            continue;
        }

        // Skip blank lines
        if (is_blank_line(lines[i])) {
            prev_is_return = 0;
            continue;
        }

        int has_tab = 0, has_space = 0;
        int indent = measure_indent(lines[i], &has_tab, &has_space);

        // ---------------------------------------------------------------
        // E001: Inconsistent indentation (not multiple of 4)
        // ---------------------------------------------------------------
        if (indent > 0 && (indent % 4) != 0) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "Indentation is %d spaces (should be a multiple of 4)", indent);
            append_msg(&head, &tail, make_msg(lineno, 1, LINT_ERROR, "E001", msg));
        }

        // ---------------------------------------------------------------
        // E002: Mixed tabs and spaces
        // ---------------------------------------------------------------
        if (has_tab && has_space) {
            append_msg(&head, &tail, make_msg(lineno, 1, LINT_ERROR, "E002",
                       "Mixed tabs and spaces in indentation"));
        }

        // ---------------------------------------------------------------
        // E003: Line too long (>120 characters)
        // ---------------------------------------------------------------
        if (ll > 120) {
            char msg[256];
            snprintf(msg, sizeof(msg),
                     "Line is %d characters long (maximum 120)", ll);
            append_msg(&head, &tail, make_msg(lineno, 121, LINT_ERROR, "E003", msg));
        }

        // ---------------------------------------------------------------
        // W003: Unreachable code after return/break/continue
        // ---------------------------------------------------------------
        if (opts.check_complexity && prev_is_return && indent > prev_indent) {
            // This line is indented deeper than the return/break/continue,
            // but at the same scope it would be unreachable.
            // Actually, check same indent level:
        }
        if (opts.check_complexity && prev_is_return && indent == prev_indent && indent >= 0) {
            // Same indentation as previous return/break/continue -> unreachable
            append_msg(&head, &tail, make_msg(lineno, indent + 1, LINT_WARNING, "W003",
                       "Unreachable code after return/break/continue"));
        }

        // Determine if this line is a return/break/continue (strip leading whitespace)
        {
            const char* trimmed = buf;
            while (*trimmed == ' ' || *trimmed == '\t') trimmed++;
            if (strncmp(trimmed, "return", 6) == 0 &&
                (trimmed[6] == '\0' || trimmed[6] == ' ' || trimmed[6] == '\n')) {
                prev_is_return = 1;
                prev_indent = indent;
            } else if (strncmp(trimmed, "break", 5) == 0 &&
                       (trimmed[5] == '\0' || trimmed[5] == ' ' || trimmed[5] == '\n')) {
                prev_is_return = 1;
                prev_indent = indent;
            } else if (strncmp(trimmed, "continue", 8) == 0 &&
                       (trimmed[8] == '\0' || trimmed[8] == ' ' || trimmed[8] == '\n')) {
                prev_is_return = 1;
                prev_indent = indent;
            } else {
                prev_is_return = 0;
            }
        }

        // Trimmed pointer for keyword checks
        const char* trimmed = buf;
        while (*trimmed == ' ' || *trimmed == '\t') trimmed++;
        int trim_offset = (int)(trimmed - buf);

        // ---------------------------------------------------------------
        // W001: Unused variables & W002: Shadowed variables
        // ---------------------------------------------------------------
        if (opts.check_unused_vars) {
            // Detect let/var declarations
            if (strncmp(trimmed, "let ", 4) == 0 || strncmp(trimmed, "var ", 4) == 0) {
                char* varname = extract_ident_after(buf, trim_offset + 4);
                if (varname) {
                    // W002: Check for shadow
                    for (VarEntry* v = vars; v; v = v->next) {
                        if (strcmp(v->name, varname) == 0) {
                            char msg[256];
                            snprintf(msg, sizeof(msg),
                                     "Variable '%s' shadows declaration on line %d",
                                     varname, v->decl_line);
                            append_msg(&head, &tail, make_msg(lineno, trim_offset + 5,
                                       LINT_WARNING, "W002", msg));
                            break;
                        }
                    }
                    VarEntry* nv = var_new(varname, lineno, indent);
                    nv->next = vars;
                    vars = nv;
                    free(varname);
                }
            }
        }

        // ---------------------------------------------------------------
        // W004: Empty block
        // ---------------------------------------------------------------
        if (opts.check_complexity) {
            // Line ends with ':' and next non-blank line has same or lower indent
            int buf_len = (int)strlen(buf);
            // strip trailing whitespace
            int end = buf_len - 1;
            while (end >= 0 && (buf[end] == ' ' || buf[end] == '\t' || buf[end] == '\r')) end--;
            if (end >= 0 && buf[end] == ':') {
                // Find next non-blank line
                int next = i + 1;
                while (next < nlines && is_blank_line(lines[next])) next++;
                if (next < nlines) {
                    int nt, ns;
                    int next_indent = measure_indent(lines[next], &nt, &ns);
                    if (next_indent <= indent && !in_string[next]) {
                        append_msg(&head, &tail, make_msg(lineno, buf_len, LINT_WARNING, "W004",
                                   "Empty block (no indented content after ':')"));
                    }
                } else {
                    // End of file after block header
                    append_msg(&head, &tail, make_msg(lineno, buf_len, LINT_WARNING, "W004",
                               "Empty block (no indented content after ':')"));
                }
            }
        }

        // ---------------------------------------------------------------
        // W005: Bare catch without variable
        // ---------------------------------------------------------------
        if (opts.check_complexity) {
            if (strncmp(trimmed, "catch:", 6) == 0 ||
                (strncmp(trimmed, "catch", 5) == 0 &&
                 (trimmed[5] == ':' || trimmed[5] == '\0' || trimmed[5] == '\n' || trimmed[5] == ' ') &&
                 trimmed[5] != ' ')) {
                // "catch:" with no variable name
                // Check more carefully: "catch" followed by ':'
                const char* after = trimmed + 5;
                while (*after == ' ' || *after == '\t') after++;
                if (*after == ':' || *after == '\0' || *after == '\n') {
                    append_msg(&head, &tail, make_msg(lineno, trim_offset + 1, LINT_WARNING, "W005",
                               "Bare 'catch' without exception variable (use 'catch e:')"));
                }
            }
        }

        // ---------------------------------------------------------------
        // S001: Proc name not snake_case
        // ---------------------------------------------------------------
        if (opts.check_naming) {
            if (strncmp(trimmed, "proc ", 5) == 0 ||
                strncmp(trimmed, "async proc ", 11) == 0) {
                int offset = (strncmp(trimmed, "async ", 6) == 0) ? 11 : 5;
                char* name = extract_ident_after(buf, trim_offset + offset);
                if (name && strcmp(name, "init") != 0) {
                    // init is special (constructor)
                    if (!is_snake_case(name)) {
                        char msg[256];
                        snprintf(msg, sizeof(msg),
                                 "Proc name '%s' should be snake_case", name);
                        append_msg(&head, &tail, make_msg(lineno, trim_offset + offset + 1,
                                   LINT_STYLE, "S001", msg));
                    }
                }
                free(name);
            }
        }

        // ---------------------------------------------------------------
        // S002: Class name not PascalCase
        // ---------------------------------------------------------------
        if (opts.check_naming) {
            if (strncmp(trimmed, "class ", 6) == 0) {
                char* name = extract_ident_after(buf, trim_offset + 6);
                if (name) {
                    if (!is_pascal_case(name)) {
                        char msg[256];
                        snprintf(msg, sizeof(msg),
                                 "Class name '%s' should be PascalCase (start with uppercase)",
                                 name);
                        append_msg(&head, &tail, make_msg(lineno, trim_offset + 7,
                                   LINT_STYLE, "S002", msg));
                    }
                    free(name);
                }
            }
        }

        // ---------------------------------------------------------------
        // S003: Missing docstring for top-level proc
        // ---------------------------------------------------------------
        if (opts.check_style) {
            if (indent == 0 &&
                (strncmp(trimmed, "proc ", 5) == 0 ||
                 strncmp(trimmed, "async proc ", 11) == 0)) {
                // Check if line before is a comment
                int has_doc = 0;
                if (i > 0) {
                    char prevbuf[2048];
                    copy_line(prevbuf, lines[i - 1], (int)sizeof(prevbuf));
                    const char* pt = prevbuf;
                    while (*pt == ' ' || *pt == '\t') pt++;
                    if (*pt == '#') has_doc = 1;
                }
                if (!has_doc) {
                    append_msg(&head, &tail, make_msg(lineno, 1, LINT_STYLE, "S003",
                               "Missing docstring (comment) for top-level proc"));
                }
            }
        }

        // ---------------------------------------------------------------
        // S004: Trailing semicolons
        // ---------------------------------------------------------------
        if (opts.check_style) {
            int end2 = ll - 1;
            while (end2 >= 0 && (buf[end2] == ' ' || buf[end2] == '\t' || buf[end2] == '\r')) end2--;
            if (end2 >= 0 && buf[end2] == ';') {
                append_msg(&head, &tail, make_msg(lineno, end2 + 1, LINT_STYLE, "S004",
                           "Trailing semicolon (not used in Sage)"));
            }
        }

        // ---------------------------------------------------------------
        // S005: Multiple statements on one line (detect via multiple keywords)
        // ---------------------------------------------------------------
        if (opts.check_style) {
            // Very rough: look for patterns like "let x = 1  let y = 2"
            // or "print x  print y" by finding a second keyword on the same line
            // after non-whitespace.
            // We look for "; " or "  let " / "  var " / "  print " mid-line
            // Skip string contents -- just a rough check.
            const char* kws[] = { " let ", " var ", " print ", " return ", NULL };
            // Find second occurrence of keyword
            for (int k = 0; kws[k]; k++) {
                // Already found first keyword at start (trimmed)
                const char* first = strstr(trimmed, kws[k] + 1);
                if (first) {
                    const char* second = strstr(first + 1, kws[k]);
                    if (second) {
                        int col = (int)(second - buf) + 1;
                        append_msg(&head, &tail, make_msg(lineno, col, LINT_STYLE, "S005",
                                   "Multiple statements on one line"));
                        break;
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------
    // W001: Unused variables (post-pass)
    // ---------------------------------------------------------------
    if (opts.check_unused_vars) {
        // For each declared variable, scan all lines after declaration
        for (VarEntry* v = vars; v; v = v->next) {
            int found = 0;
            for (int i = v->decl_line; i < nlines; i++) { // decl_line is 1-based, lines[decl_line] is line after
                if (in_string[i]) continue;
                int ll2 = line_len(lines[i]);
                if (name_appears_in_line(lines[i], ll2, v->name)) {
                    found = 1;
                    break;
                }
            }
            if (!found) {
                char msg[256];
                snprintf(msg, sizeof(msg), "Variable '%s' is declared but never used", v->name);
                append_msg(&head, &tail, make_msg(v->decl_line, 1, LINT_WARNING, "W001", msg));
            }
        }
    }

    var_free_list(vars);
    free(lines);
    free(in_string);
    return head;
}

// ---------------------------------------------------------------------------
// File-level interface
// ---------------------------------------------------------------------------

static const char* severity_str(LintSeverity sev) {
    switch (sev) {
        case LINT_ERROR:   return "error";
        case LINT_WARNING: return "warning";
        case LINT_STYLE:   return "style";
    }
    return "note";
}

int lint_file(const char* path, LintOptions opts) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "sage lint: cannot open '%s'\n", path);
        return -1;
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    rewind(f);
    char* source = malloc((size_t)sz + 1);
    size_t nread = fread(source, 1, (size_t)sz, f);
    source[nread] = '\0';
    fclose(f);

    LintMessage* msgs = lint_source(source, path, opts);
    free(source);

    int count = 0;
    for (LintMessage* m = msgs; m; m = m->next) {
        fprintf(stdout, "%s:%d:%d: %s: [%s] %s\n",
                path, m->line, m->column,
                severity_str(m->severity),
                m->rule, m->message);
        count++;
    }

    free_lint_messages(msgs);
    return count;
}

void free_lint_messages(LintMessage* msgs) {
    while (msgs) {
        LintMessage* next = msgs->next;
        free(msgs->rule);
        free(msgs->message);
        free(msgs);
        msgs = next;
    }
}
