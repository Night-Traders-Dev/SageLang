#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char* left = "sage_eq(sage_index(s_raw, s_i), sage_string(\" \"))";
    char* right = "sage_eq(sage_index(s_raw, s_i), ({ SageValue _args[1]; _args[0] = sage_number(10); }))";
    
    char* result = malloc(strlen(left)*2 + strlen(right)*2 + 128);
    sprintf(result, "(sage_truthy(%s) ? %s : %s)", left, left, right);
    printf("%s\n", result);
    return 0;
}
