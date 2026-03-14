#ifndef SAGE_DIAGNOSTIC_H
#define SAGE_DIAGNOSTIC_H

#include <stdarg.h>

#include "token.h"

const char* sage_token_type_name(TokenType type);
const char* sage_token_display_name(TokenType type);

void sage_vprint_token_diagnosticf(const char* severity, const Token* token,
                                   const char* fallback_filename, int span,
                                   const char* help, const char* fmt,
                                   va_list args);
void sage_print_token_diagnosticf(const char* severity, const Token* token,
                                  const char* fallback_filename, int span,
                                  const char* help, const char* fmt, ...);

#endif
