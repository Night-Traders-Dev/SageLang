// src/lib/utils.h

#ifndef UTILS_H
#define UTILS_H

#include <stdlib.h>
#include <string.h>

// Provide a safe alternative for strdup
#ifndef HAVE_STRDUP
#define HAVE_STRDUP
char *strdup(const char *s);
#endif
#ifndef HAVE_STRNDUP
#define HAVE_STRNDUP
char *strndup(const char *s, size_t n);
#endif


#endif // UTILS_H
