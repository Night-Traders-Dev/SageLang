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
#include <pthread.h>
#include <unistd.h>

#ifdef SAGE_HAS_VULKAN
#include "gpu_api.h"
#endif

// ============================================================================
// GPU compute state
// ============================================================================

static int g_gpu_initialized = 0;
static int g_gpu_available = 0;
static int g_gpu_matmul_shader = -1;
static int g_gpu_matmul_pipeline = -1;
static int g_gpu_matmul_layout = -1;
static int g_gpu_matmul_desc_layout = -1;
static int g_gpu_threshold = 8192;  // M*K threshold to offload to GPU

// GLSL compute shader source for matmul
static const char* g_matmul_shader_src =
    "#version 450\n"
    "layout(local_size_x = 16, local_size_y = 16) in;\n"
    "layout(set = 0, binding = 0) readonly buffer A { float a[]; };\n"
    "layout(set = 0, binding = 1) readonly buffer B { float b[]; };\n"
    "layout(set = 0, binding = 2) writeonly buffer C { float c[]; };\n"
    "layout(push_constant) uniform Params { uint M; uint K; uint N; } p;\n"
    "void main() {\n"
    "  uint row = gl_GlobalInvocationID.y;\n"
    "  uint col = gl_GlobalInvocationID.x;\n"
    "  if (row >= p.M || col >= p.N) return;\n"
    "  float sum = 0.0;\n"
    "  for (uint i = 0; i < p.K; i++) sum += a[row * p.K + i] * b[i * p.N + col];\n"
    "  c[row * p.N + col] = sum;\n"
    "}\n";

static void ml_gpu_init(void) {
#ifdef SAGE_HAS_VULKAN
    if (g_gpu_initialized) return;
    g_gpu_initialized = 1;
    if (sgpu_init("sage_ml", 0) == 0) {
        g_gpu_available = 1;
        // Create compute shader from embedded SPIR-V or GLSL
        // Note: sgpu_create_shader expects SPIR-V bytecode
        // For now, mark GPU as available but skip shader setup
        // (shader compilation needs offline SPIR-V compilation)
    }
#endif
    (void)g_matmul_shader_src;
}

// Forward declaration for CPU fallback
static void matmul_f64(const double* A, const double* B, double* C,
                       int m, int k, int n);

// GPU matmul: upload A,B to device, dispatch compute, download C
static void matmul_gpu(const double* A, const double* B, double* C,
                       int m, int k, int n) {
#ifdef SAGE_HAS_VULKAN
    if (!g_gpu_available) {
        matmul_f64(A, B, C, m, k, n);
        return;
    }

    // Convert double -> float for GPU (GPU uses fp32)
    int a_size = m * k;
    int b_size = k * n;
    int c_size = m * n;
    float* fA = (float*)malloc(sizeof(float) * (size_t)a_size);
    float* fB = (float*)malloc(sizeof(float) * (size_t)b_size);

    for (int i = 0; i < a_size; i++) fA[i] = (float)A[i];
    for (int i = 0; i < b_size; i++) fB[i] = (float)B[i];

    // Upload to GPU device-local storage
    int buf_a = sgpu_upload_device_local(fA, a_size, SGPU_BUFFER_STORAGE);
    int buf_b = sgpu_upload_device_local(fB, b_size, SGPU_BUFFER_STORAGE);
    int buf_c = sgpu_create_buffer(c_size * (int)sizeof(float),
                                   SGPU_BUFFER_STORAGE,
                                   SGPU_MEMORY_HOST_VISIBLE | SGPU_MEMORY_HOST_COHERENT);

    if (buf_a >= 0 && buf_b >= 0 && buf_c >= 0 && g_gpu_matmul_pipeline >= 0) {
        // Dispatch compute shader
        int pool = sgpu_create_command_pool(sgpu_compute_family());
        int cmd = sgpu_create_command_buffer(pool);
        sgpu_begin_commands(cmd);
        sgpu_cmd_bind_compute_pipeline(cmd, g_gpu_matmul_pipeline);
        int gx = (n + 15) / 16;
        int gy = (m + 15) / 16;
        sgpu_cmd_dispatch(cmd, gx, gy, 1);
        sgpu_end_commands(cmd);
        int fence = sgpu_create_fence(0);
        sgpu_submit_compute(cmd, fence);
        sgpu_wait_fence(fence, 5000);

        sgpu_destroy_fence(fence);
        sgpu_destroy_buffer(buf_c);
        sgpu_destroy_buffer(buf_b);
        sgpu_destroy_buffer(buf_a);
        // GPU compute pipeline not fully bootstrapped yet — fallback to CPU
        matmul_f64(A, B, C, m, k, n);
    } else {
        if (buf_a >= 0) sgpu_destroy_buffer(buf_a);
        if (buf_b >= 0) sgpu_destroy_buffer(buf_b);
        if (buf_c >= 0) sgpu_destroy_buffer(buf_c);
        // GPU not ready, fallback to CPU parallel
        matmul_f64(A, B, C, m, k, n);
    }

    free(fA); free(fB);
#else
    // No Vulkan, use CPU
    matmul_f64(A, B, C, m, k, n);
#endif
}

// ============================================================================
// Parallel matmul configuration
// ============================================================================

static int g_ml_num_threads = 1;
static int g_ml_parallel_threshold = 4096; // M*K threshold to trigger parallel

typedef struct {
    const double* A;
    const double* B;
    double* C;
    int m_start, m_end;
    int k, n;
} MatmulWorker;

static void* matmul_worker_fn(void* arg) {
    MatmulWorker* w = (MatmulWorker*)arg;
    for (int i = w->m_start; i < w->m_end; i++) {
        for (int p = 0; p < w->k; p++) {
            double a_ip = w->A[i * w->k + p];
            for (int j = 0; j < w->n; j++) {
                w->C[i * w->n + j] += a_ip * w->B[p * w->n + j];
            }
        }
    }
    return NULL;
}

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
// Uses pthread parallelism when m*k > threshold and g_ml_num_threads > 1
static void matmul_f64(const double* A, const double* B, double* C,
                       int m, int k, int n) {
    memset(C, 0, sizeof(double) * (size_t)m * (size_t)n);

    // Parallel path: split rows across threads
    if (g_ml_num_threads > 1 && m > 1 && m * k >= g_ml_parallel_threshold) {
        int nt = g_ml_num_threads;
        if (nt > m) nt = m;
        pthread_t* threads = (pthread_t*)malloc(sizeof(pthread_t) * (size_t)nt);
        MatmulWorker* workers = (MatmulWorker*)malloc(sizeof(MatmulWorker) * (size_t)nt);
        int rows_per = m / nt;
        for (int t = 0; t < nt; t++) {
            workers[t].A = A;
            workers[t].B = B;
            workers[t].C = C;
            workers[t].k = k;
            workers[t].n = n;
            workers[t].m_start = t * rows_per;
            workers[t].m_end = (t == nt - 1) ? m : (t + 1) * rows_per;
            pthread_create(&threads[t], NULL, matmul_worker_fn, &workers[t]);
        }
        for (int t = 0; t < nt; t++) {
            pthread_join(threads[t], NULL);
        }
        free(threads);
        free(workers);
        return;
    }

    // Serial path
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
    // Try GPU for large matrices, fallback to CPU (parallel or serial)
    if (g_gpu_available && m * k >= g_gpu_threshold) {
        matmul_gpu(A, B, C, m, k, n);
    } else {
        matmul_f64(A, B, C, m, k, n);
    }
    Value result = doubles_to_value_array(C, m * n);
    free(A); free(B); free(C);
    return result;
}

// ml_native.load_weights(path) -> array of arrays (one per line in CSV file)
// Parses a CSV weight file entirely in C to avoid OOM from Sage string parsing
static Value ml_load_weights(int argc, Value* args) {
    if (argc < 1 || args[0].type != VAL_STRING) return val_nil();
    const char* path = args[0].as.string;

    FILE* f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "ml_native.load_weights: cannot open %s\n", path);
        return val_nil();
    }

    // Read entire file
    fseek(f, 0, SEEK_END);
    long fsize = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(fsize + 1);
    if (!buf) { fclose(f); return val_nil(); }
    size_t read_sz = fread(buf, 1, fsize, f);
    fclose(f);
    buf[read_sz] = '\0';

    // Count lines
    int line_count = 0;
    for (long i = 0; i < (long)read_sz; i++) {
        if (buf[i] == '\n') line_count++;
    }
    if (read_sz > 0 && buf[read_sz - 1] != '\n') line_count++;

    // Parse each line as CSV floats
    Value result = val_array();
    char* pos = buf;
    for (int line = 0; line < line_count; line++) {
        // Find end of line
        char* eol = pos;
        while (*eol && *eol != '\n') eol++;

        // Count commas to pre-allocate
        int num_vals = 0;
        if (eol > pos) {
            num_vals = 1;
            for (char* p = pos; p < eol; p++) {
                if (*p == ',') num_vals++;
            }
        }

        // Parse floats
        double* vals = (double*)malloc(sizeof(double) * (num_vals > 0 ? num_vals : 1));
        int vi = 0;
        char* tok_start = pos;
        for (char* p = pos; p <= eol; p++) {
            if (*p == ',' || p == eol) {
                char saved = *p;
                *p = '\0';
                if (vi < num_vals) {
                    vals[vi++] = atof(tok_start);
                }
                *p = saved;
                tok_start = p + 1;
            }
        }

        Value arr = doubles_to_value_array(vals, vi);
        array_push(&result, arr);
        free(vals);

        pos = eol;
        if (*pos == '\n') pos++;
    }

    free(buf);
    return result;
}

// ml_native.gpu_available() -> true if Vulkan GPU compute is available
static Value ml_gpu_available(int argc, Value* args) {
    (void)argc; (void)args;
    ml_gpu_init();
    return val_bool(g_gpu_available);
}

// ml_native.set_gpu_threshold(n) -> min M*K to offload to GPU
static Value ml_set_gpu_threshold(int argc, Value* args) {
    if (argc < 1) return val_nil();
    g_gpu_threshold = (int)AS_NUMBER(args[0]);
    return val_number(g_gpu_threshold);
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

// ml_native.set_threads(n) -> set number of parallel threads for matmul
static Value ml_set_threads(int argc, Value* args) {
    if (argc < 1) return val_nil();
    int n = (int)AS_NUMBER(args[0]);
    if (n < 1) n = 1;
    if (n > 256) n = 256;
    g_ml_num_threads = n;
    return val_number(n);
}

// ml_native.set_parallel_threshold(n) -> min M*K to trigger parallel matmul
static Value ml_set_parallel_threshold(int argc, Value* args) {
    if (argc < 1) return val_nil();
    int n = (int)AS_NUMBER(args[0]);
    if (n < 1) n = 1;
    g_ml_parallel_threshold = n;
    return val_number(n);
}

// ml_native.get_threads() -> current thread count
static Value ml_get_threads(int argc, Value* args) {
    (void)argc; (void)args;
    return val_number(g_ml_num_threads);
}

// ml_native.cpu_count() -> number of available CPU cores/threads
static Value ml_cpu_count(int argc, Value* args) {
    (void)argc; (void)args;
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    if (n < 1) n = 1;
    return val_number((double)n);
}

// ml_native.auto_parallel() -> set threads to all available cores
static Value ml_auto_parallel(int argc, Value* args) {
    (void)argc; (void)args;
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    if (n < 1) n = 1;
    g_ml_num_threads = (int)n;
    g_ml_parallel_threshold = 1024;
    return val_number((double)n);
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

    // Parallel configuration
    env_define(e, "set_threads", 11, val_native(ml_set_threads));
    env_define(e, "set_parallel_threshold", 22, val_native(ml_set_parallel_threshold));
    env_define(e, "get_threads", 11, val_native(ml_get_threads));

    // Weight I/O
    env_define(e, "load_weights", 12, val_native(ml_load_weights));

    // GPU compute
    env_define(e, "gpu_available", 13, val_native(ml_gpu_available));
    env_define(e, "set_gpu_threshold", 17, val_native(ml_set_gpu_threshold));

    // CPU info
    env_define(e, "cpu_count", 9, val_native(ml_cpu_count));
    env_define(e, "auto_parallel", 13, val_native(ml_auto_parallel));

    // Add to cache
    module->next = cache->modules;
    cache->modules = module;

    return module;
}
