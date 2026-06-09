#ifndef SAGE_FORMATTER_H
#define SAGE_FORMATTER_H

typedef struct {
    int indent_width;        // default 4
    int max_blank_lines;     // default 2
    int normalize_operators; // default 1
} FormatOptions;

FormatOptions format_default_options(void);
char* format_source(const char* source, FormatOptions opts);
int format_file(const char* input_path, const char* output_path, FormatOptions opts);

#endif
