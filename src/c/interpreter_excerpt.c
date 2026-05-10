// src/c/interpreter.c (lines 2030-2070 excerpt)
static Value vm_get_gas_limit_native(int argCount, Value* args) {
    (void)argCount; (void)args;
    return val_number((double)g_gas_limit);
}
#include <openssl/sha.h>
static Value sha256_native(int argCount, Value* args) {
    if (argCount != 1 || !IS_STRING(args[0])) return val_nil();
    const char* input = AS_STRING(args[0]);
    unsigned char hash[32];
    SHA256((unsigned char*)input, strlen(input), hash);
    char hex[65];
    for (int i = 0; i < 32; i++) {
        sprintf(hex + (i * 2), "%02x", hash[i]);
    }
    hex[64] = '\0';
    return val_string(hex);
}

void init_stdlib(Env* env) {
    // Core functions
    env_define_const(env, "clock", 5, val_native(clock_native));
    env_define_const(env, "input", 5, val_native(input_native));
    env_define_const(env, "tonumber", 8, val_native(tonumber_native));
    env_define_const(env, "int", 3, val_native(int_native));
    env_define_const(env, "str", 3, val_native(str_native));
    env_define_const(env, "len", 3, val_native(len_native));
    env_define_const(env, "sha256", 6, val_native(sha256_native));
    
    // VM / Gas functions
    env_define_const(env, "vm_gas_limit_set", 16, val_native(vm_set_gas_limit_native));
    env_define_const(env, "vm_gas_used_get", 15, val_native(vm_get_gas_used_native));
    env_define_const(env, "vm_gas_limit_get", 16, val_native(vm_get_gas_limit_native));

    // Array functions
    env_define_const(env, "push", 4, val_native(push_native));
    env_define_const(env, "append", 6, val_native(push_native));
    env_define_const(env, "build_quad_verts", 16, val_native(build_quad_verts_native));
    env_define_const(env, "array_extend", 12, val_native(array_extend_native));
