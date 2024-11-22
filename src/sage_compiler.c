#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <dirent.h>
#include <unistd.h>
#include <limits.h>  // For PATH_MAX

#ifndef PATH_MAX
#define PATH_MAX 4096  // Fallback if PATH_MAX is undefined
#endif

#include "sage_arm/sage_arm.h"
#include "sage_risc/sage_risc.h"
#include "lib/tokenizer.h"
#include "lib/parser.h"

#define BUILD_DIR "build"

void ensure_build_dir() {
    struct stat st = {0};
    if (stat(BUILD_DIR, &st) == -1) {
        mkdir(BUILD_DIR, 0700);
    }
}

void clean_build_dir() {
    DIR *dir;
    struct dirent *entry;

    dir = opendir(BUILD_DIR);
    if (!dir) {
        printf("No build directory to clean.\n");
        return;
    }

    while ((entry = readdir(dir)) != NULL) {
        char path[PATH_MAX];
        snprintf(path, sizeof(path) - 1, "%s/%s", BUILD_DIR, entry->d_name);
        path[sizeof(path) - 1] = '\0';  // Ensure null-termination

        if (strstr(entry->d_name, ".s") || strstr(entry->d_name, ".elf")) {
            unlink(path);  // Remove file
        }
    }
    closedir(dir);
    printf("Cleaned %s/\n", BUILD_DIR);
}

char* read_file(const char *filename) {
    FILE *file = fopen(filename, "r");
    if (!file) {
        perror("Error opening file");
        exit(EXIT_FAILURE);
    }

    fseek(file, 0, SEEK_END);
    size_t length = ftell(file);
    fseek(file, 0, SEEK_SET);

    if (length == 0) {
        fprintf(stderr, "Error: Empty file.\n");
        fclose(file);
        exit(EXIT_FAILURE);
    }

    char *buffer = (char *)malloc(length + 1);
    if (!buffer) {
        perror("Memory allocation failed");
        fclose(file);
        exit(EXIT_FAILURE);
    }

    fread(buffer, 1, length, file);
    buffer[length] = '\0';

    fclose(file);
    return buffer;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        printf("Usage: %s <arch> [source_file]\n", argv[0]);
        printf("Supported architectures: arm, riscv\n");
        printf("Use '%s clean' to clean the build directory.\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *arch = argv[1];

    if (strcmp(arch, "clean") == 0) {
        clean_build_dir();
        return EXIT_SUCCESS;
    }

    if (argc < 3) {
        printf("Usage: %s <arch> <source_file>\n", argv[0]);
        return EXIT_FAILURE;
    }

    const char *source_file = argv[2];
    char *source_code = read_file(source_file);

    ensure_build_dir();

    char output_file[256];
    snprintf(output_file, sizeof(output_file), "%s/%s_%s.s", BUILD_DIR,
             strtok((char *)source_file, "."), arch);

    if (strcmp(arch, "arm") == 0) {
        compile_arm(source_code, output_file);
    } else if (strcmp(arch, "riscv") == 0) {
        compile_riscv(source_code, output_file);
    } else {
        printf("Unsupported architecture: %s\n", arch);
        free(source_code);
        return EXIT_FAILURE;
    }

    printf("Compiled to %s\n", output_file);

    free(source_code);
    return EXIT_SUCCESS;
}
