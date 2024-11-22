// src/lib/utils.c

#include "utils.h"

#ifndef HAVE_STRDUP
char *strdup(const char *s) {
    size_t len = strlen(s) + 1;
    char *copy = malloc(len);
    if (copy) {
        memcpy(copy, s, len);
    }
    return copy;
}
#endif

#ifndef HAVE_STRNDUP
char *strndup(const char *s, size_t n) {
    size_t len = strnlen(s, n);
    char *result = malloc(len + 1);
    if (!result) return NULL;
    strncpy(result, s, len);
    result[len] = '\0';
    return result;
}
#endif
