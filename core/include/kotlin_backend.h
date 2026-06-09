#ifndef SAGE_KOTLIN_BACKEND_H
#define SAGE_KOTLIN_BACKEND_H

#include <stddef.h>

// ============================================================================
// Sage → Kotlin Transpiler Backend
// ============================================================================
// Transpiles Sage AST to Kotlin source code targeting Android (JVM/ART).
// The generated Kotlin integrates with a lightweight SageRuntime.kt library
// that provides the dynamic value system, built-in functions, and Android
// framework bindings.
//
// Usage:
//   sage --emit-kotlin <input.sage> [-o output.kt] [-O0..3]
//   sage --compile-android <input.sage> [-o output_dir] [--package com.example.app]
//
// The --compile-android mode generates a full Gradle project with:
//   - Transpiled Kotlin source
//   - SageRuntime.kt (dynamic value runtime)
//   - AndroidManifest.xml
//   - build.gradle.kts
//   - Ready-to-build with: cd output_dir && ./gradlew assembleDebug
// ============================================================================

// Transpile Sage source to a Kotlin source string (.kt file).
// Returns 1 on success, 0 on failure.
int compile_source_to_kotlin(const char* source, const char* input_path,
                             const char* output_path);

// Transpile with optimization level and debug info control.
int compile_source_to_kotlin_opt(const char* source, const char* input_path,
                                 const char* output_path,
                                 int opt_level, int debug_info);

// Generate a complete Android project directory from Sage source.
// package_name: e.g. "com.example.myapp" (NULL for default "com.sage.app")
// app_name: human-readable app name (NULL for input filename)
// min_sdk: minimum Android SDK version (0 for default 24)
// Returns 1 on success, 0 on failure.
int compile_source_to_android(const char* source, const char* input_path,
                              const char* output_dir,
                              const char* package_name,
                              const char* app_name,
                              int min_sdk,
                              int opt_level, int debug_info);

// Build the generated Android project to APK (requires Android SDK / Gradle).
// project_dir: path to the generated project directory
// apk_path_out: buffer to receive the path to the built APK
// apk_path_out_size: size of apk_path_out buffer
// Returns 1 on success, 0 on failure.
int build_android_apk(const char* project_dir,
                      char* apk_path_out, size_t apk_path_out_size);

#endif
