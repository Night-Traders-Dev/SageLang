#ifndef SAGE_COMPILER_H
#define SAGE_COMPILER_H

int compile_source_to_c(const char* source, const char* input_path, const char* output_path);
int compile_source_to_executable(const char* source, const char* input_path,
                                 const char* c_output_path, const char* exe_output_path,
                                 const char* cc_command);

#endif
