#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "metal_vm.h"

static void write_char(char c) {
    putchar(c);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file.sgvm>\n", argv[0]);
        return 1;
    }

    FILE* f = fopen(argv[1], "rb");
    if (!f) {
        perror("fopen");
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    unsigned char* data = malloc(size);
    if (fread(data, 1, size, f) != (size_t)size) {
        fprintf(stderr, "Read error\n");
        free(data);
        fclose(f);
        return 1;
    }
    fclose(f);

    MetalVM vm;
    metal_vm_init(&vm);
    vm.write_char = write_char;

    int err = metal_vm_load_binary(&vm, data, (int)size);
    if (err < 0) {
        fprintf(stderr, "Error loading binary: %d\n", err);
        free(data);
        return 1;
    }

    if (metal_vm_verify(&vm) < 0) {
        fprintf(stderr, "Verification failed\n");
        free(data);
        return 1;
    }

    for (int i = 0; i < vm.chunk_count; i++) {
        metal_vm_load(&vm, vm.chunks[i], vm.chunk_lengths[i]);
        if (metal_vm_run(&vm) < 0) {
            fprintf(stderr, "Runtime error in chunk %d: %s\n", i, vm.error_msg ? vm.error_msg : "unknown");
            free(data);
            return 1;
        }
    }

    free(data);
    return 0;
}
