#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char** argv) {
    FILE* f = fopen(argv[0], "rb");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    
    // search backwards for "\n__SAGE_EMBEDDED_START__\n"
    const char* magic = "\n__SAGE_EMBEDDED_START__\n";
    int magic_len = strlen(magic);
    
    long search_start = size - 100000;
    if (search_start < 0) search_start = 0;
    
    fseek(f, search_start, SEEK_SET);
    char* buf = malloc(size - search_start);
    fread(buf, 1, size - search_start, f);
    
    // find magic
    char* found = NULL;
    for (long i = (size - search_start) - magic_len; i >= 0; i--) {
        if (memcmp(buf + i, magic, magic_len) == 0) {
            found = buf + i;
            break;
        }
    }
    
    if (found) {
        printf("Found embedded payload: %s\n", found + magic_len);
    } else {
        printf("No embedded payload.\n");
    }
    
    free(buf);
    fclose(f);
    return 0;
}
