#ifndef SAGE_COMPILER_H
#define SAGE_COMPILER_H

#include <stddef.h>

int compile_source_to_c(const char* source, const char* input_path, const char* output_path);
int compile_source_to_executable(const char* source, const char* input_path,
                                 const char* c_output_path, const char* exe_output_path,
                                 const char* cc_command);
int compile_source_to_pico_c(const char* source, const char* input_path, const char* output_path);
int compile_source_to_pico_uf2(const char* source, const char* input_path,
                               const char* output_dir, const char* program_name,
                               const char* pico_board, const char* pico_sdk_path,
                               char* uf2_path_out, size_t uf2_path_out_size);

#endif
