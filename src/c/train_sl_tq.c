// ============================================================================
// SL-TQ-LLM C-Only Trainer
// Pure C training binary — no interpreter overhead, maximum speed
// Reads training data, runs backprop, saves weights
//
// Build: gcc -O3 -march=native -o train_sl_tq src/c/train_sl_tq.c -lm -lpthread
// Usage: ./train_sl_tq [steps] [lr]
//   Default: 50000 steps, lr=0.002
//
// Philosophy: No black box — every gradient is computed explicitly.
// The entire forward pass, backward pass, and weight update is visible
// in this single file. No autograd, no frameworks, no magic.
// ============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <pthread.h>
#include <unistd.h>

// ============================================================================
// Model Configuration
// ============================================================================

#define D_MODEL  64
#define N_HEADS  4
#define D_FF     256
#define VOCAB    256
#define SEQ_LEN  64
#define D_HEAD   (D_MODEL / N_HEADS)

// Weight sizes
#define EMBED_SIZE  (VOCAB * D_MODEL)      // 16384
#define ATTN_SIZE   (D_MODEL * D_MODEL)    // 4096
#define GATE_SIZE   (D_MODEL * D_FF)       // 16384
#define DOWN_SIZE   (D_FF * D_MODEL)       // 16384
#define HEAD_SIZE   (D_MODEL * VOCAB)      // 16384
#define TOTAL_PARAMS (EMBED_SIZE + 4*ATTN_SIZE + 2*GATE_SIZE + DOWN_SIZE + 2*D_MODEL + D_MODEL + HEAD_SIZE)

// ============================================================================
// Weight arrays (global for simplicity)
// ============================================================================

static double embed[EMBED_SIZE];
static double Qw[ATTN_SIZE], Kw[ATTN_SIZE], Vw[ATTN_SIZE], Ow[ATTN_SIZE];
static double Gate[GATE_SIZE], Up[GATE_SIZE], Down[DOWN_SIZE];
static double Norm1[D_MODEL], Norm2[D_MODEL], FNorm[D_MODEL];
static double LMHead[HEAD_SIZE];

// ============================================================================
// PRNG
// ============================================================================

static unsigned int g_seed = 42;
static double rand_uniform(void) {
    g_seed = g_seed * 1664525u + 1013904223u;
    return ((g_seed >> 8) & 0xFFFFFF) / (double)0xFFFFFF - 0.5;
}

// ============================================================================
// Initialize weights (Xavier-like)
// ============================================================================

static void init_weights(void) {
    double sc_e = 0.01;
    double sc_a = 1.0 / D_MODEL;
    double sc_f = 1.0 / D_FF;

    for (int i = 0; i < EMBED_SIZE; i++) embed[i] = rand_uniform() * sc_e;
    for (int i = 0; i < ATTN_SIZE; i++) {
        Qw[i] = rand_uniform() * sc_a;
        Kw[i] = rand_uniform() * sc_a;
        Vw[i] = rand_uniform() * sc_a;
        Ow[i] = rand_uniform() * sc_a;
    }
    for (int i = 0; i < GATE_SIZE; i++) {
        Gate[i] = rand_uniform() * sc_f;
        Up[i] = rand_uniform() * sc_f;
    }
    for (int i = 0; i < DOWN_SIZE; i++) Down[i] = rand_uniform() * sc_a;
    for (int i = 0; i < D_MODEL; i++) { Norm1[i] = 1.0; Norm2[i] = 1.0; FNorm[i] = 1.0; }
    for (int i = 0; i < HEAD_SIZE; i++) LMHead[i] = rand_uniform() * sc_a;
}

// ============================================================================
// Matrix operations
// ============================================================================

// Parallel matmul using pthreads
typedef struct {
    const double* A; const double* B; double* C;
    int m, k, n, row_start, row_end;
} MatmulArgs;

static void* matmul_worker(void* arg) {
    MatmulArgs* a = (MatmulArgs*)arg;
    for (int i = a->row_start; i < a->row_end; i++) {
        for (int j = 0; j < a->n; j++) {
            double sum = 0;
            for (int p = 0; p < a->k; p++) sum += a->A[i*a->k+p] * a->B[p*a->n+j];
            a->C[i*a->n+j] = sum;
        }
    }
    return NULL;
}

static int g_num_threads = 1;

static void matmul(const double* A, const double* B, double* C, int m, int k, int n) {
    if (m < 4 || g_num_threads <= 1) {
        // Serial for small matrices
        for (int i = 0; i < m; i++)
            for (int j = 0; j < n; j++) {
                double sum = 0;
                for (int p = 0; p < k; p++) sum += A[i*k+p] * B[p*n+j];
                C[i*n+j] = sum;
            }
        return;
    }
    int nt = g_num_threads;
    if (nt > m) nt = m;
    pthread_t threads[64];
    MatmulArgs args[64];
    int rows_per = m / nt;
    for (int t = 0; t < nt; t++) {
        args[t] = (MatmulArgs){A, B, C, m, k, n, t*rows_per, (t==nt-1)?m:(t+1)*rows_per};
        pthread_create(&threads[t], NULL, matmul_worker, &args[t]);
    }
    for (int t = 0; t < nt; t++) pthread_join(threads[t], NULL);
}

static void softmax(double* x, int n) {
    double mx = x[0];
    for (int i = 1; i < n; i++) if (x[i] > mx) mx = x[i];
    double s = 0;
    for (int i = 0; i < n; i++) { x[i] = exp(x[i] - mx); s += x[i]; }
    for (int i = 0; i < n; i++) x[i] /= s;
}

static double silu(double x) { return x / (1.0 + exp(-x)); }
static double silu_grad(double x) {
    double s = 1.0 / (1.0 + exp(-x));
    return s * (1.0 + x * (1.0 - s));
}

static double clip_grad_norm(double* grad, int n, double max_norm) {
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
// Single training step: forward + backward + SGD
// Returns loss
// ============================================================================

static double train_step(const int* input_ids, int target, double lr) {
    int S = SEQ_LEN, d = D_MODEL, ff = D_FF, V = VOCAB;
    int SD = S * d, SF = S * ff;

    // ===== FORWARD =====

    // 1. Embedding
    double* hidden = (double*)calloc(SD, sizeof(double));
    for (int t = 0; t < S; t++) {
        int tid = input_ids[t];
        if (tid < 0 || tid >= V) tid = 0;
        for (int j = 0; j < d; j++) hidden[t*d+j] = embed[tid*d+j];
    }

    // 2. RMSNorm 1
    double rms1[SEQ_LEN];
    double* normed1 = (double*)calloc(SD, sizeof(double));
    for (int t = 0; t < S; t++) {
        double ss = 0;
        for (int j = 0; j < d; j++) { double v = hidden[t*d+j]; ss += v*v; }
        rms1[t] = sqrt(ss / d + 1e-5);
        for (int j = 0; j < d; j++) normed1[t*d+j] = hidden[t*d+j] / rms1[t] * Norm1[j];
    }

    // 3. Q, K, V projections
    double* Q = (double*)calloc(SD, sizeof(double));
    double* K = (double*)calloc(SD, sizeof(double));
    double* Vm = (double*)calloc(SD, sizeof(double));
    matmul(normed1, Qw, Q, S, d, d);
    matmul(normed1, Kw, K, S, d, d);
    matmul(normed1, Vw, Vm, S, d, d);

    // 4. Causal attention
    double scale = 1.0 / sqrt((double)d);
    double* attn_probs = (double*)calloc(S * S, sizeof(double));
    for (int i = 0; i < S; i++) {
        for (int j = 0; j < S; j++) {
            double dot = 0;
            for (int k = 0; k < d; k++) dot += Q[i*d+k] * K[j*d+k];
            attn_probs[i*S+j] = (j <= i) ? dot * scale : -1e9;
        }
        softmax(attn_probs + i*S, S);
    }
    double* attn_out = (double*)calloc(SD, sizeof(double));
    matmul(attn_probs, Vm, attn_out, S, S, d);

    // 5. O projection + residual
    double* proj = (double*)calloc(SD, sizeof(double));
    matmul(attn_out, Ow, proj, S, d, d);
    double* h2 = (double*)calloc(SD, sizeof(double));
    for (int i = 0; i < SD; i++) h2[i] = hidden[i] + proj[i];

    // 6. RMSNorm 2
    double rms2[SEQ_LEN];
    double* normed2 = (double*)calloc(SD, sizeof(double));
    for (int t = 0; t < S; t++) {
        double ss = 0;
        for (int j = 0; j < d; j++) { double v = h2[t*d+j]; ss += v*v; }
        rms2[t] = sqrt(ss / d + 1e-5);
        for (int j = 0; j < d; j++) normed2[t*d+j] = h2[t*d+j] / rms2[t] * Norm2[j];
    }

    // 7. SwiGLU FFN
    double* gate_out = (double*)calloc(SF, sizeof(double));
    double* up_out = (double*)calloc(SF, sizeof(double));
    matmul(normed2, Gate, gate_out, S, d, ff);
    matmul(normed2, Up, up_out, S, d, ff);
    double* gate_silu = (double*)calloc(SF, sizeof(double));
    double* gated = (double*)calloc(SF, sizeof(double));
    for (int i = 0; i < SF; i++) {
        gate_silu[i] = silu(gate_out[i]);
        gated[i] = gate_silu[i] * up_out[i];
    }
    double* ffn_out = (double*)calloc(SD, sizeof(double));
    matmul(gated, Down, ffn_out, S, ff, d);

    // 8. Residual
    double* h3 = (double*)calloc(SD, sizeof(double));
    for (int i = 0; i < SD; i++) h3[i] = h2[i] + ffn_out[i];

    // 9-11. Compute loss and gradients at ALL positions (not just last)
    // This is critical for generation quality — every position learns to predict next token
    double loss = 0;
    double d_lm_head[HEAD_SIZE]; memset(d_lm_head, 0, sizeof(d_lm_head));
    double d_fnorm[D_MODEL]; memset(d_fnorm, 0, sizeof(d_fnorm));
    double* d_h3 = (double*)calloc(SD, sizeof(double));

    // For each position, compute logits -> loss -> gradient
    for (int t = 0; t < S; t++) {
        // Target is the next character (input shifted by 1)
        int tgt = (t < S - 1) ? input_ids[t + 1] : target;
        if (tgt < 0 || tgt >= V) tgt = 0;

        // RMSNorm at position t
        double ss = 0;
        for (int j = 0; j < d; j++) { double v = h3[t*d+j]; ss += v*v; }
        double rms = sqrt(ss / d + 1e-5);
        double pos_normed[D_MODEL];
        for (int j = 0; j < d; j++) pos_normed[j] = h3[t*d+j] / rms * FNorm[j];

        // Logits = pos_normed @ LMHead
        double logits[VOCAB];
        for (int j = 0; j < V; j++) {
            double dot = 0;
            for (int k = 0; k < d; k++) dot += pos_normed[k] * LMHead[k*V+j];
            logits[j] = dot;
        }

        // Softmax + CE loss
        double probs[VOCAB];
        for (int j = 0; j < V; j++) probs[j] = logits[j];
        softmax(probs, V);
        loss += -log(probs[tgt] + 1e-10);

        // Backward through this position
        double d_logits[VOCAB];
        for (int j = 0; j < V; j++) d_logits[j] = probs[j] / S;  // Scale by 1/S for avg
        d_logits[tgt] -= 1.0 / S;

        // Grad LM head (accumulate across positions)
        double d_pos[D_MODEL]; memset(d_pos, 0, sizeof(d_pos));
        for (int k = 0; k < d; k++)
            for (int j = 0; j < V; j++) {
                d_lm_head[k*V+j] += pos_normed[k] * d_logits[j];
                d_pos[k] += LMHead[k*V+j] * d_logits[j];
            }

        // Grad FNorm + propagate to h3
        for (int j = 0; j < d; j++) {
            d_fnorm[j] += d_pos[j] * h3[t*d+j] / rms;
            d_h3[t*d+j] += d_pos[j] * FNorm[j] / rms;
        }
    }
    loss /= S;

    // Grad FFN + residual (all positions)
    double* d_h2 = (double*)calloc(SD, sizeof(double));
    for (int i = 0; i < SD; i++) d_h2[i] = d_h3[i]; // residual

    double d_Down[DOWN_SIZE]; memset(d_Down, 0, sizeof(d_Down));
    double* d_gated = (double*)calloc(SF, sizeof(double));
    for (int t = 0; t < S; t++) {
        for (int i = 0; i < ff; i++) {
            for (int j = 0; j < d; j++) {
                d_gated[t*ff+i] += d_h3[t*d+j] * Down[i*d+j];
                d_Down[i*d+j] += gated[t*ff+i] * d_h3[t*d+j];
            }
        }
    }

    // Grad SwiGLU (all positions)
    double d_Gate[GATE_SIZE], d_Up[GATE_SIZE];
    memset(d_Gate, 0, sizeof(d_Gate));
    memset(d_Up, 0, sizeof(d_Up));
    for (int t = 0; t < S; t++) {
        for (int i = 0; i < ff; i++) {
            int idx = t*ff+i;
            double dg = d_gated[idx] * up_out[idx] * silu_grad(gate_out[idx]);
            double du = d_gated[idx] * gate_silu[idx];
            for (int k = 0; k < d; k++) {
                d_Gate[k*ff+i] += normed2[t*d+k] * dg;
                d_Up[k*ff+i] += normed2[t*d+k] * du;
            }
        }
    }

    // Grad O projection (all positions)
    double d_Ow[ATTN_SIZE]; memset(d_Ow, 0, sizeof(d_Ow));
    for (int t = 0; t < S; t++)
        for (int k = 0; k < d; k++)
            for (int j = 0; j < d; j++)
                d_Ow[k*d+j] += attn_out[t*d+k] * d_h2[t*d+j];

    // Grad embedding (all positions)
    double d_embed[EMBED_SIZE]; memset(d_embed, 0, sizeof(d_embed));
    for (int t = 0; t < S; t++) {
        int tid = input_ids[t];
        if (tid >= 0 && tid < V)
            for (int j = 0; j < d; j++)
                d_embed[tid*d+j] += d_h2[t*d+j];
    }

    // ===== SGD UPDATE WITH GRADIENT CLIPPING =====
    double max_norm = 1.0;
    clip_grad_norm(d_lm_head, HEAD_SIZE, max_norm);
    clip_grad_norm(d_Down, DOWN_SIZE, max_norm);
    clip_grad_norm(d_Gate, GATE_SIZE, max_norm);
    clip_grad_norm(d_Up, GATE_SIZE, max_norm);
    clip_grad_norm(d_Ow, ATTN_SIZE, max_norm);
    clip_grad_norm(d_embed, EMBED_SIZE, max_norm);
    clip_grad_norm(d_fnorm, D_MODEL, max_norm);

    for (int i = 0; i < HEAD_SIZE; i++) LMHead[i] -= lr * d_lm_head[i];
    for (int i = 0; i < DOWN_SIZE; i++) Down[i] -= lr * d_Down[i];
    for (int i = 0; i < GATE_SIZE; i++) { Gate[i] -= lr * d_Gate[i]; Up[i] -= lr * d_Up[i]; }
    for (int i = 0; i < ATTN_SIZE; i++) Ow[i] -= lr * d_Ow[i];
    for (int i = 0; i < EMBED_SIZE; i++) embed[i] -= lr * d_embed[i];
    for (int i = 0; i < D_MODEL; i++) FNorm[i] -= lr * d_fnorm[i];

    // Cleanup
    free(hidden); free(normed1); free(Q); free(K); free(Vm);
    free(attn_probs); free(attn_out); free(proj); free(h2);
    free(normed2); free(gate_out); free(up_out); free(gate_silu);
    free(gated); free(ffn_out); free(h3);
    free(d_h3); free(d_h2); free(d_gated);

    return loss;
}

// ============================================================================
// Load training data from text files
// ============================================================================

static char* load_file(const char* path, long* out_size) {
    FILE* f = fopen(path, "r");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(sz + 1);
    size_t rd = fread(buf, 1, sz, f);
    fclose(f);
    buf[rd] = '\0';
    *out_size = (long)rd;
    return buf;
}

// ============================================================================
// Save weights in CSV format (compatible with ml_native.load_weights)
// ============================================================================

static void save_weights(const char* path) {
    FILE* f = fopen(path, "w");
    if (!f) { fprintf(stderr, "Cannot write to %s\n", path); return; }

    // Line 0: config
    fprintf(f, "%d,%d,1,%d,%d,%d\n", D_MODEL, N_HEADS, D_FF, VOCAB, SEQ_LEN);

    // Helper macro
    #define WRITE_ARRAY(arr, n) do { \
        for (int i = 0; i < (n); i++) { \
            if (i > 0) fputc(',', f); \
            fprintf(f, "%.8g", (arr)[i]); \
        } \
        fputc('\n', f); \
    } while(0)

    WRITE_ARRAY(embed, EMBED_SIZE);     // Line 1
    WRITE_ARRAY(Qw, ATTN_SIZE);        // Line 2
    WRITE_ARRAY(Kw, ATTN_SIZE);        // Line 3
    WRITE_ARRAY(Vw, ATTN_SIZE);        // Line 4
    WRITE_ARRAY(Ow, ATTN_SIZE);        // Line 5
    WRITE_ARRAY(Gate, GATE_SIZE);       // Line 6
    WRITE_ARRAY(Up, GATE_SIZE);         // Line 7
    WRITE_ARRAY(Down, DOWN_SIZE);       // Line 8
    WRITE_ARRAY(Norm1, D_MODEL);        // Line 9
    WRITE_ARRAY(Norm2, D_MODEL);        // Line 10
    WRITE_ARRAY(FNorm, D_MODEL);        // Line 11
    WRITE_ARRAY(LMHead, HEAD_SIZE);     // Line 12

    #undef WRITE_ARRAY
    fclose(f);
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char** argv) {
    int total_steps = 50000;
    double lr = 0.002;

    if (argc > 1) total_steps = atoi(argv[1]);
    if (argc > 2) lr = atof(argv[2]);

    // Auto-detect CPU cores
    g_num_threads = (int)sysconf(_SC_NPROCESSORS_ONLN);
    if (g_num_threads < 1) g_num_threads = 1;
    if (g_num_threads > 64) g_num_threads = 64;

    printf("================================================================\n");
    printf("  SL-TQ-LLM C-Only Trainer\n");
    printf("  No black box. Every gradient is explicit.\n");
    printf("================================================================\n\n");

    printf("CPU cores: %d (parallel matmul)\n", g_num_threads);
    printf("Model: d=%d heads=%d ff=%d vocab=%d seq=%d\n", D_MODEL, N_HEADS, D_FF, VOCAB, SEQ_LEN);
    printf("Params: %d\n", TOTAL_PARAMS);
    printf("Steps: %d  LR: %.6f\n\n", total_steps, lr);

    // Load training data
    printf("Loading training data...\n");

    long corpus_size = 0;
    char* corpus = NULL;

    const char* data_files[] = {
        "models/data/programming_languages.txt",
        "models/data/multilang_examples.txt",
        "models/data/natural_language.txt",
        NULL
    };

    // Concatenate all data files
    long total_data = 0;
    char* all_data = (char*)malloc(1);
    all_data[0] = '\0';

    for (int f = 0; data_files[f] != NULL; f++) {
        long sz;
        char* content = load_file(data_files[f], &sz);
        if (content) {
            all_data = (char*)realloc(all_data, total_data + sz + 1);
            memcpy(all_data + total_data, content, sz);
            total_data += sz;
            all_data[total_data] = '\0';
            printf("  %s: %ld chars\n", data_files[f], sz);
            free(content);
        }
    }

    // Also load Sage source files
    const char* sage_files[] = {
        "src/sage/lexer.sage", "src/sage/parser.sage", "src/sage/interpreter.sage",
        "src/sage/compiler.sage", "src/sage/sage.sage", "src/sage/value.sage",
        "lib/arrays.sage", "lib/strings.sage", "lib/json.sage", "lib/math.sage",
        "lib/llm/config.sage", "lib/llm/tokenizer.sage", "lib/llm/train.sage",
        "lib/llm/attention.sage", "lib/llm/turboquant.sage",
        "lib/agent/core.sage", "lib/agent/planner.sage",
        "lib/chat/bot.sage", "lib/chat/persona.sage",
        "lib/std/regex.sage", "lib/std/fmt.sage",
        NULL
    };

    for (int f = 0; sage_files[f] != NULL; f++) {
        long sz;
        char* content = load_file(sage_files[f], &sz);
        if (content) {
            all_data = (char*)realloc(all_data, total_data + sz + 2);
            all_data[total_data] = '\n';
            memcpy(all_data + total_data + 1, content, sz);
            total_data += sz + 1;
            all_data[total_data] = '\0';
            free(content);
        }
    }

    corpus = all_data;
    corpus_size = total_data;
    printf("Total corpus: %ld chars\n\n", corpus_size);

    if (corpus_size < SEQ_LEN + 1) {
        fprintf(stderr, "ERROR: corpus too small (need at least %d chars)\n", SEQ_LEN + 1);
        return 1;
    }

    // Create training examples (character-level tokenization)
    int num_examples = (int)(corpus_size - SEQ_LEN);
    if (num_examples > 100000) num_examples = 100000;

    printf("Training examples: %d\n", num_examples);

    // Initialize weights
    printf("Initializing weights...\n");
    init_weights();

    // Training loop
    printf("\nTraining with backpropagation...\n");
    printf("%-8s  %-12s  %-12s  %-12s\n", "Step", "Loss", "PPL", "LR");
    printf("------  ----------  ----------  ----------\n");

    clock_t start = clock();
    double total_loss = 0;
    double best_loss = 999;
    int log_interval = total_steps / 20;
    if (log_interval < 100) log_interval = 100;

    for (int step = 0; step < total_steps; step++) {
        // Random position in corpus for maximum data diversity
        g_seed = g_seed * 1664525u + 1013904223u;
        int pos = (int)(g_seed % (unsigned int)num_examples);

        // Character-level tokenization
        int input_ids[SEQ_LEN];
        for (int t = 0; t < SEQ_LEN; t++) {
            input_ids[t] = (unsigned char)corpus[pos + t];
        }
        int target = (unsigned char)corpus[pos + SEQ_LEN];

        // Cosine learning rate schedule
        double progress = (double)step / total_steps;
        double cos_lr = lr * 0.5 * (1.0 + cos(M_PI * progress));
        if (step < total_steps / 20) {
            cos_lr = lr * (double)step / (total_steps / 20);  // warmup
        }

        double loss = train_step(input_ids, target, cos_lr);
        total_loss += loss;
        if (loss < best_loss) best_loss = loss;

        if ((step + 1) % log_interval == 0 || step == 0) {
            double avg = total_loss / (step + 1);
            double ppl = exp(avg);
            printf("%-8d  %-12.6f  %-12.2f  %-12.8f\n", step + 1, loss, ppl, cos_lr);
            fflush(stdout);
        }
    }

    clock_t end = clock();
    double elapsed = (double)(end - start) / CLOCKS_PER_SEC;

    printf("\n");
    printf("================================================================\n");
    printf("  Training Complete\n");
    printf("================================================================\n");
    printf("Steps: %d\n", total_steps);
    printf("Avg loss: %.6f\n", total_loss / total_steps);
    printf("Best loss: %.6f\n", best_loss);
    printf("PPL: %.2f\n", exp(total_loss / total_steps));
    printf("Time: %.1f seconds (%.0f steps/sec)\n", elapsed, total_steps / elapsed);
    printf("\n");

    // Save weights
    const char* weight_path = "models/sl_tq_llm.weights";
    printf("Saving weights to %s...\n", weight_path);
    save_weights(weight_path);
    printf("Done.\n\n");

    printf("Next steps:\n");
    printf("  Run chatbot:    ./sage models/sl_tq_llm_chat.sage\n");
    printf("  Compile chatbot: ./sage --compile-llvm models/sl_tq_llm_chat.sage -o sl_tq_chat\n");
    printf("  Run compiled:   ./sl_tq_chat\n");

    free(corpus);
    return 0;
}
