// src/ml_backend.c - Native ML training backend for SageLang
// Provides optimized C matrix operations exposed as a native Sage module.
// Uses direct C loops (optionally linkable against BLAS/OpenBLAS for production).
// Registered as `import ml_native` in the module system.

#include "module.h"
#include "value.h"
#include "env.h"
#include "gc.h"
#include "interpreter.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// ============================================================================
// Internal tensor representation (flat float array)
// ============================================================================

typedef struct {
    double* data;
    int* shape;
    int ndim;
    int size;
} NativeTensor;

static NativeTensor* tensor_create(int ndim, int* shape) {
    NativeTensor* t = (NativeTensor*)malloc(sizeof(NativeTensor));
    t->ndim = ndim;
    t->shape = (int*)malloc(sizeof(int) * ndim);
    t->size = 1;
    for (int i = 0; i < ndim; i++) {
        t->shape[i] = shape[i];
        t->size *= shape[i];
    }
    t->data = (double*)calloc(t->size, sizeof(double));
    return t;
}

static void tensor_free(NativeTensor* t) {
    if (t) {
        free(t->data);
        free(t->shape);
        free(t);
    }
}

// ============================================================================
// Core math operations (optimized C, no interpreter overhead)
// ============================================================================

// C = A @ B  (m x k) @ (k x n) -> (m x n)
static void matmul_f64(const double* A, const double* B, double* C,
                       int m, int k, int n) {
    // Zero output
    memset(C, 0, sizeof(double) * m * n);
    // Standard triple-loop (row-major, k-loop inner for cache locality)
    for (int i = 0; i < m; i++) {
        for (int p = 0; p < k; p++) {
            double a_ip = A[i * k + p];
            for (int j = 0; j < n; j++) {
                C[i * n + j] += a_ip * B[p * n + j];
            }
        }
    }
}

// Element-wise add: C = A + B
static void add_f64(const double* A, const double* B, double* C, int n) {
    for (int i = 0; i < n; i++) C[i] = A[i] + B[i];
}

// Element-wise multiply: C = A * B
static void mul_f64(const double* A, const double* B, double* C, int n) {
    for (int i = 0; i < n; i++) C[i] = A[i] * B[i];
}

// Scalar multiply: C = A * s
static void scale_f64(const double* A, double s, double* C, int n) {
    for (int i = 0; i < n; i++) C[i] = A[i] * s;
}

// ReLU: C[i] = max(0, A[i])
static void relu_f64(const double* A, double* C, int n) {
    for (int i = 0; i < n; i++) C[i] = A[i] > 0 ? A[i] : 0;
}

// GELU: C[i] = 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715 * x^3)))
static void gelu_f64(const double* A, double* C, int n) {
    const double c = 0.7978845608028654; // sqrt(2/pi)
    for (int i = 0; i < n; i++) {
        double x = A[i];
        C[i] = 0.5 * x * (1.0 + tanh(c * (x + 0.044715 * x * x * x)));
    }
}

// SiLU (Swish): C[i] = x / (1 + exp(-x))
static void silu_f64(const double* A, double* C, int n) {
    for (int i = 0; i < n; i++) {
        C[i] = A[i] / (1.0 + exp(-A[i]));
    }
}

// Sigmoid: C[i] = 1 / (1 + exp(-A[i]))
static void sigmoid_f64(const double* A, double* C, int n) {
    for (int i = 0; i < n; i++) {
        C[i] = 1.0 / (1.0 + exp(-A[i]));
    }
}

// Softmax (in-place, over last dimension)
static void softmax_f64(double* data, int rows, int cols) {
    for (int i = 0; i < rows; i++) {
        double max_val = data[i * cols];
        for (int j = 1; j < cols; j++) {
            if (data[i * cols + j] > max_val) max_val = data[i * cols + j];
        }
        double sum = 0;
        for (int j = 0; j < cols; j++) {
            data[i * cols + j] = exp(data[i * cols + j] - max_val);
            sum += data[i * cols + j];
        }
        for (int j = 0; j < cols; j++) {
            data[i * cols + j] /= sum;
        }
    }
}

// Layer normalization
static void layer_norm_f64(const double* input, const double* gamma,
                           const double* beta, double* output,
                           int batch, int dim, double eps) {
    for (int i = 0; i < batch; i++) {
        double mean = 0;
        for (int j = 0; j < dim; j++) mean += input[i * dim + j];
        mean /= dim;
        double var = 0;
        for (int j = 0; j < dim; j++) {
            double d = input[i * dim + j] - mean;
            var += d * d;
        }
        var /= dim;
        double inv_std = 1.0 / sqrt(var + eps);
        for (int j = 0; j < dim; j++) {
            output[i * dim + j] = gamma[j] * (input[i * dim + j] - mean) * inv_std + beta[j];
        }
    }
}

// RMS normalization (Llama-style)
static void rms_norm_f64(const double* input, const double* weight,
                         double* output, int batch, int dim, double eps) {
    for (int i = 0; i < batch; i++) {
        double ss = 0;
        for (int j = 0; j < dim; j++) ss += input[i * dim + j] * input[i * dim + j];
        double rms = 1.0 / sqrt(ss / dim + eps);
        for (int j = 0; j < dim; j++) {
            output[i * dim + j] = input[i * dim + j] * rms * weight[j];
        }
    }
}

// Cross-entropy loss
static double cross_entropy_f64(const double* logits, const int* targets,
                                int batch, int vocab_size) {
    double loss = 0;
    for (int i = 0; i < batch; i++) {
        double max_val = logits[i * vocab_size];
        for (int j = 1; j < vocab_size; j++) {
            if (logits[i * vocab_size + j] > max_val) max_val = logits[i * vocab_size + j];
        }
        double log_sum = 0;
        for (int j = 0; j < vocab_size; j++) {
            log_sum += exp(logits[i * vocab_size + j] - max_val);
        }
        log_sum = max_val + log(log_sum);
        loss += log_sum - logits[i * vocab_size + targets[i]];
    }
    return loss / batch;
}

// Adam optimizer step (in-place)
static void adam_step_f64(double* param, const double* grad,
                          double* m, double* v,
                          int n, double lr, double beta1, double beta2,
                          double eps, int t) {
    double bc1 = 1.0 - pow(beta1, t);
    double bc2 = 1.0 - pow(beta2, t);
    for (int i = 0; i < n; i++) {
        m[i] = beta1 * m[i] + (1 - beta1) * grad[i];
        v[i] = beta2 * v[i] + (1 - beta2) * grad[i] * grad[i];
        double m_hat = m[i] / bc1;
        double v_hat = v[i] / bc2;
        param[i] -= lr * m_hat / (sqrt(v_hat) + eps);
    }
}

// Gradient clipping by norm
static double clip_grad_norm_f64(double* grad, int n, double max_norm) {
    double total = 0;
    for (int i = 0; i < n; i++) total += grad[i] * grad[i];
    total = sqrt(total);
    if (total > max_norm) {
        double scale = max_norm / total;
        for (int i = 0; i < n; i++) grad[i] *= scale;
    }
    return total;
}

// ============================================================================
// Helper: extract double array from Sage Value array
// ============================================================================

static double* value_array_to_doubles(Value arr, int* out_count) {
    if (arr.type != VAL_ARRAY) { *out_count = 0; return NULL; }
    ArrayValue* a = arr.as.array;
    *out_count = a->count;
    double* data = (double*)malloc(sizeof(double) * a->count);
    for (int i = 0; i < a->count; i++) {
        data[i] = IS_NUMBER(a->elements[i]) ? AS_NUMBER(a->elements[i]) : 0.0;
    }
    return data;
}

static Value doubles_to_value_array(const double* data, int count) {
    gc_pin();
    Value arr = val_array();
    for (int i = 0; i < count; i++) {
        array_push(&arr, val_number(data[i]));
    }
    gc_unpin();
    return arr;
}

static int* value_array_to_ints(Value arr, int* out_count) {
    if (arr.type != VAL_ARRAY) { *out_count = 0; return NULL; }
    ArrayValue* a = arr.as.array;
    *out_count = a->count;
    int* data = (int*)malloc(sizeof(int) * a->count);
    for (int i = 0; i < a->count; i++) {
        data[i] = IS_NUMBER(a->elements[i]) ? (int)AS_NUMBER(a->elements[i]) : 0;
    }
    return data;
}

// ============================================================================
// Native function wrappers (Sage API)
// ============================================================================

// ml_native.matmul(a, b, m, k, n) -> result array
static Value ml_matmul(int argc, Value* args) {
    if (argc < 5) return val_nil();
    int a_count, b_count;
    double* A = value_array_to_doubles(args[0], &a_count);
    double* B = value_array_to_doubles(args[1], &b_count);
    int m = (int)AS_NUMBER(args[2]);
    int k = (int)AS_NUMBER(args[3]);
    int n = (int)AS_NUMBER(args[4]);
    double* C = (double*)calloc(m * n, sizeof(double));
    matmul_f64(A, B, C, m, k, n);
    Value result = doubles_to_value_array(C, m * n);
    free(A); free(B); free(C);
    return result;
}

// ml_native.add(a, b) -> element-wise sum
static Value ml_add(int argc, Value* args) {
    if (argc < 2) return val_nil();
    int a_count, b_count;
    double* A = value_array_to_doubles(args[0], &a_count);
    double* B = value_array_to_doubles(args[1], &b_count);
    int n = a_count < b_count ? a_count : b_count;
    double* C = (double*)malloc(sizeof(double) * n);
    add_f64(A, B, C, n);
    Value result = doubles_to_value_array(C, n);
    free(A); free(B); free(C);
    return result;
}

// ml_native.relu(a) -> ReLU activation
static Value ml_relu(int argc, Value* args) {
    if (argc < 1) return val_nil();
    int count;
    double* A = value_array_to_doubles(args[0], &count);
    double* C = (double*)malloc(sizeof(double) * count);
    relu_f64(A, C, count);
    Value result = doubles_to_value_array(C, count);
    free(A); free(C);
    return result;
}

// ml_native.gelu(a) -> GELU activation
static Value ml_gelu(int argc, Value* args) {
    if (argc < 1) return val_nil();
    int count;
    double* A = value_array_to_doubles(args[0], &count);
    double* C = (double*)malloc(sizeof(double) * count);
    gelu_f64(A, C, count);
    Value result = doubles_to_value_array(C, count);
    free(A); free(C);
    return result;
}

// ml_native.silu(a) -> SiLU activation
static Value ml_silu(int argc, Value* args) {
    if (argc < 1) return val_nil();
    int count;
    double* A = value_array_to_doubles(args[0], &count);
    double* C = (double*)malloc(sizeof(double) * count);
    silu_f64(A, C, count);
    Value result = doubles_to_value_array(C, count);
    free(A); free(C);
    return result;
}

// ml_native.sigmoid(a) -> sigmoid
static Value ml_sigmoid(int argc, Value* args) {
    if (argc < 1) return val_nil();
    int count;
    double* A = value_array_to_doubles(args[0], &count);
    double* C = (double*)malloc(sizeof(double) * count);
    sigmoid_f64(A, C, count);
    Value result = doubles_to_value_array(C, count);
    free(A); free(C);
    return result;
}

// ml_native.softmax(a, rows, cols) -> softmax
static Value ml_softmax(int argc, Value* args) {
    if (argc < 3) return val_nil();
    int count;
    double* A = value_array_to_doubles(args[0], &count);
    int rows = (int)AS_NUMBER(args[1]);
    int cols = (int)AS_NUMBER(args[2]);
    softmax_f64(A, rows, cols);
    Value result = doubles_to_value_array(A, count);
    free(A);
    return result;
}

// ml_native.layer_norm(input, gamma, beta, batch, dim, eps) -> normalized
static Value ml_layer_norm(int argc, Value* args) {
    if (argc < 6) return val_nil();
    int in_count, g_count, b_count;
    double* input = value_array_to_doubles(args[0], &in_count);
    double* gamma = value_array_to_doubles(args[1], &g_count);
    double* beta = value_array_to_doubles(args[2], &b_count);
    int batch = (int)AS_NUMBER(args[3]);
    int dim = (int)AS_NUMBER(args[4]);
    double eps = AS_NUMBER(args[5]);
    double* output = (double*)malloc(sizeof(double) * in_count);
    layer_norm_f64(input, gamma, beta, output, batch, dim, eps);
    Value result = doubles_to_value_array(output, in_count);
    free(input); free(gamma); free(beta); free(output);
    return result;
}

// ml_native.rms_norm(input, weight, batch, dim, eps) -> normalized
static Value ml_rms_norm(int argc, Value* args) {
    if (argc < 5) return val_nil();
    int in_count, w_count;
    double* input = value_array_to_doubles(args[0], &in_count);
    double* weight = value_array_to_doubles(args[1], &w_count);
    int batch = (int)AS_NUMBER(args[2]);
    int dim = (int)AS_NUMBER(args[3]);
    double eps = AS_NUMBER(args[4]);
    double* output = (double*)malloc(sizeof(double) * in_count);
    rms_norm_f64(input, weight, output, batch, dim, eps);
    Value result = doubles_to_value_array(output, in_count);
    free(input); free(weight); free(output);
    return result;
}

// ml_native.cross_entropy(logits, targets, batch, vocab_size) -> loss
static Value ml_cross_entropy(int argc, Value* args) {
    if (argc < 4) return val_nil();
    int l_count, t_count;
    double* logits = value_array_to_doubles(args[0], &l_count);
    int* targets = value_array_to_ints(args[1], &t_count);
    int batch = (int)AS_NUMBER(args[2]);
    int vocab_size = (int)AS_NUMBER(args[3]);
    double loss = cross_entropy_f64(logits, targets, batch, vocab_size);
    free(logits); free(targets);
    return val_number(loss);
}

// ml_native.adam_update(param, grad, m, v, lr, beta1, beta2, eps, step) -> updated_param
static Value ml_adam_update(int argc, Value* args) {
    if (argc < 9) return val_nil();
    int p_count, g_count, m_count, v_count;
    double* param = value_array_to_doubles(args[0], &p_count);
    double* grad = value_array_to_doubles(args[1], &g_count);
    double* m = value_array_to_doubles(args[2], &m_count);
    double* v = value_array_to_doubles(args[3], &v_count);
    double lr = AS_NUMBER(args[4]);
    double beta1 = AS_NUMBER(args[5]);
    double beta2 = AS_NUMBER(args[6]);
    double eps = AS_NUMBER(args[7]);
    int step = (int)AS_NUMBER(args[8]);
    adam_step_f64(param, grad, m, v, p_count, lr, beta1, beta2, eps, step);
    // Return dict with updated param, m, v
    gc_pin();
    Value result = val_dict();
    dict_set(&result, "param", doubles_to_value_array(param, p_count));
    dict_set(&result, "m", doubles_to_value_array(m, m_count));
    dict_set(&result, "v", doubles_to_value_array(v, v_count));
    gc_unpin();
    free(param); free(grad); free(m); free(v);
    return result;
}

// ml_native.scale(a, s) -> a * s
static Value ml_scale(int argc, Value* args) {
    if (argc < 2) return val_nil();
    int count;
    double* A = value_array_to_doubles(args[0], &count);
    double s = AS_NUMBER(args[1]);
    double* C = (double*)malloc(sizeof(double) * count);
    scale_f64(A, s, C, count);
    Value result = doubles_to_value_array(C, count);
    free(A); free(C);
    return result;
}

// ml_native.clip_grad(grad, max_norm) -> clipped grad
static Value ml_clip_grad(int argc, Value* args) {
    if (argc < 2) return val_nil();
    int count;
    double* grad = value_array_to_doubles(args[0], &count);
    double max_norm = AS_NUMBER(args[1]);
    double norm = clip_grad_norm_f64(grad, count, max_norm);
    gc_pin();
    Value result = val_dict();
    dict_set(&result, "grad", doubles_to_value_array(grad, count));
    dict_set(&result, "norm", val_number(norm));
    gc_unpin();
    free(grad);
    return result;
}

// ml_native.benchmark(size, iterations) -> ops/sec for matmul
static Value ml_benchmark(int argc, Value* args) {
    int size = argc >= 1 ? (int)AS_NUMBER(args[0]) : 128;
    int iters = argc >= 2 ? (int)AS_NUMBER(args[1]) : 10;
    double* A = (double*)malloc(sizeof(double) * size * size);
    double* B = (double*)malloc(sizeof(double) * size * size);
    double* C = (double*)malloc(sizeof(double) * size * size);
    // Fill with random data
    for (int i = 0; i < size * size; i++) {
        A[i] = (double)(rand() % 1000) / 1000.0;
        B[i] = (double)(rand() % 1000) / 1000.0;
    }
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (int iter = 0; iter < iters; iter++) {
        matmul_f64(A, B, C, size, size, size);
    }
    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
    double flops_per_matmul = 2.0 * size * size * size;
    double total_flops = flops_per_matmul * iters;
    free(A); free(B); free(C);
    gc_pin();
    Value result = val_dict();
    dict_set(&result, "elapsed_seconds", val_number(elapsed));
    dict_set(&result, "iterations", val_number(iters));
    dict_set(&result, "matrix_size", val_number(size));
    dict_set(&result, "gflops", val_number(total_flops / elapsed / 1e9));
    dict_set(&result, "ms_per_matmul", val_number(elapsed / iters * 1000));
    gc_unpin();
    return result;
}

// ============================================================================
// Module registration
// ============================================================================

Module* create_ml_native_module(ModuleCache* cache) {
    Module* module = SAGE_ALLOC(sizeof(Module));
    module->name = SAGE_STRDUP("ml_native");
    module->path = NULL;
    module->source = NULL;
    module->ast = NULL;
    module->ast_tail = NULL;
    module->env = env_create(NULL);
    module->is_loaded = true;
    module->is_loading = false;

    Environment* e = module->env;

    // Matrix operations
    env_define(e, "matmul", 6, val_native(ml_matmul));
    env_define(e, "add", 3, val_native(ml_add));
    env_define(e, "scale", 5, val_native(ml_scale));

    // Activations
    env_define(e, "relu", 4, val_native(ml_relu));
    env_define(e, "gelu", 4, val_native(ml_gelu));
    env_define(e, "silu", 4, val_native(ml_silu));
    env_define(e, "sigmoid", 7, val_native(ml_sigmoid));
    env_define(e, "softmax", 7, val_native(ml_softmax));

    // Normalization
    env_define(e, "layer_norm", 10, val_native(ml_layer_norm));
    env_define(e, "rms_norm", 8, val_native(ml_rms_norm));

    // Loss & optimization
    env_define(e, "cross_entropy", 13, val_native(ml_cross_entropy));
    env_define(e, "adam_update", 11, val_native(ml_adam_update));
    env_define(e, "clip_grad", 9, val_native(ml_clip_grad));

    // Benchmark
    env_define(e, "benchmark", 9, val_native(ml_benchmark));

    // Add to cache
    module->next = cache->modules;
    cache->modules = module;

    return module;
}
