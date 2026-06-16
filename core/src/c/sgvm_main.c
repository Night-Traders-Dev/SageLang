#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "metal_vm.h"
#include "metal_rv64_vm.h"

static void write_char(char c) {
    putchar(c);
}

int main(int argc, char** argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <file.sgvm|file.sgrv>\n", argv[0]);
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

    if (size >= 4 && data[0] == 'S' && data[1] == 'G' && data[2] == 'R' && data[3] == 'V') {
        // RISC-V register-based VM path
        MetalRV64VM vm;
        metal_rv64_vm_init(&vm);
        vm.write_char = write_char;

        int err = metal_rv64_vm_load_binary(&vm, data, (int)size);
        if (err < 0) {
            fprintf(stderr, "Error loading SGRV binary: %d\n", err);
            free(data);
            return 1;
        }

        // The SGRV compiler generates chunks, chunk 0 is usually entry or they are executed as we invoke.
        // Actually, the main chunk in SGRV is chunk 0. Let's load the main chunk first.
        for (int i = 0; i < vm.chunk_count; i++) {
            vm.current_chunk_idx = i;
            vm.bytecode = vm.chunks[i];
            vm.bytecode_length = vm.chunk_lengths[i];
            vm.pc = 0;
            if (metal_rv64_vm_run(&vm) < 0) {
                fprintf(stderr, "Runtime error in chunk %d: %s\n", i, vm.error_msg ? vm.error_msg : "unknown");
                free(data);
                return 1;
            }
        }
    } else if (size >= 4 && data[0] == 'S' && data[1] == 'G' && data[2] == 'V' && data[3] == 'M') {
        // Stack-based VM path
        MetalVM vm;
        metal_vm_init(&vm);
        vm.write_char = write_char;

        int err = metal_vm_load_binary(&vm, data, (int)size);
        if (err < 0) {
            fprintf(stderr, "Error loading SGVM binary: %d\n", err);
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
    } else {
        fprintf(stderr, "Error: Unknown binary format (magic check failed)\n");
        free(data);
        return 1;
    }

    free(data);
    return 0;
}
