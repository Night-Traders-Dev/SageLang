#ifndef SAGE_LLVM_BACKEND_H
#define SAGE_LLVM_BACKEND_H

#include <stddef.h>

// Emit LLVM IR text to a .ll file
int compile_source_to_llvm_ir(const char* source, const char* input_path,
                              const char* output_path, int opt_level, int debug_info);

// Emit LLVM IR then compile with llc + cc to produce executable
int compile_source_to_llvm_executable(const char* source, const char* input_path,
                                      const char* ll_output_path, const char* exe_output_path,
                                      int opt_level, int debug_info);

#endif
