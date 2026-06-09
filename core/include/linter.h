#ifndef SAGE_LINTER_H
#define SAGE_LINTER_H

typedef enum {
    LINT_WARNING,
    LINT_ERROR,
    LINT_STYLE
} LintSeverity;

typedef struct LintMessage {
    int line;
    int column;
    LintSeverity severity;
    char* rule;      // e.g., "W001", "E001", "S001"
    char* message;
    struct LintMessage* next;
} LintMessage;

typedef struct {
    int check_unused_vars;    // default 1
    int check_naming;         // default 1
    int check_style;          // default 1
    int check_complexity;     // default 1
} LintOptions;

LintOptions lint_default_options(void);
LintMessage* lint_source(const char* source, const char* filename, LintOptions opts);
int lint_file(const char* path, LintOptions opts);  // returns number of issues
void free_lint_messages(LintMessage* msgs);

#endif
