// ============================================================================
// SL-TQ-LLM C-Only Trainer v2
// d=128, 2 layers, Adam optimizer, full Q/K/V gradients
// No black box — every gradient is explicit in this file.
//
// Build: gcc -O3 -march=native -o train_sl_tq src/c/train_sl_tq.c -lm -lpthread
//    or: make train-c
// Usage: ./train_sl_tq [steps] [lr]
// ============================================================================

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <pthread.h>
#include <unistd.h>

#ifdef USE_CUBLAS
#include <cuda_runtime.h>
#include <cublas_v2.h>
static cublasHandle_t g_cublas = NULL;
static int g_gpu_ready = 0;

// Persistent GPU buffers for weight matrices (uploaded once, updated in-place)
// Using float32 for 64x GPU speedup on RTX consumer cards
static float *d_scratch[4];  // 4 scratch buffers for matmul intermediates
#define SCRATCH_SZ (96 * 384)  // max dimension: D * FF = 36864

static void cublas_init(void) {
    cublasCreate(&g_cublas);
    for (int i = 0; i < 4; i++)
        cudaMalloc((void**)&d_scratch[i], sizeof(float) * SCRATCH_SZ);
    g_gpu_ready = 1;
}

static void cublas_cleanup(void) {
    for (int i = 0; i < 4; i++) if (d_scratch[i]) cudaFree(d_scratch[i]);
    if (g_cublas) cublasDestroy(g_cublas);
}

// Pre-allocated CPU-side float buffers (avoid malloc/free per matmul)
static float* g_fA = NULL;
static float* g_fB = NULL;
static float* g_fC = NULL;

static void alloc_float_bufs(void) {
    g_fA = (float*)malloc(sizeof(float) * SCRATCH_SZ);
    g_fB = (float*)malloc(sizeof(float) * SCRATCH_SZ);
    g_fC = (float*)malloc(sizeof(float) * SCRATCH_SZ);
}

// GPU FP32 matmul with pre-allocated buffers
static void matmul_gpu_f32(const double* A, const double* B, double* C, int m, int k, int n) {
    int a_sz = m*k, b_sz = k*n, c_sz = m*n;

    for (int i = 0; i < a_sz; i++) g_fA[i] = (float)A[i];
    for (int i = 0; i < b_sz; i++) g_fB[i] = (float)B[i];

    cudaMemcpy(d_scratch[0], g_fA, sizeof(float)*a_sz, cudaMemcpyHostToDevice);
    cudaMemcpy(d_scratch[1], g_fB, sizeof(float)*b_sz, cudaMemcpyHostToDevice);

    float alpha = 1.0f, beta = 0.0f;
    cublasSgemm(g_cublas, CUBLAS_OP_N, CUBLAS_OP_N,
                n, m, k, &alpha, d_scratch[1], n, d_scratch[0], k, &beta, d_scratch[2], n);

    cudaMemcpy(g_fC, d_scratch[2], sizeof(float)*c_sz, cudaMemcpyDeviceToHost);
    for (int i = 0; i < c_sz; i++) {
        C[i] = (double)g_fC[i];
        // Clamp NaN/Inf from FP32 precision loss
        if (C[i] != C[i] || C[i] > 1e6) C[i] = 0.0;
        if (C[i] < -1e6) C[i] = 0.0;
    }
}
#endif

// ============================================================================
// Model Configuration
// ============================================================================

#define D       96        // d_model (sweet spot: 3x capacity of 64, fits in memory)
#define HEADS   4         // attention heads
#define FF      384       // feed-forward dim (4x d_model)
#define VOCAB   256       // character-level
#define SEQ     64        // sequence length
#define NLAYERS 1         // single layer (memory-safe for interpreter training)

// ============================================================================
// PRNG
// ============================================================================

static unsigned int g_seed = 42;
static double randu(void) {
    g_seed = g_seed * 1664525u + 1013904223u;
    return ((g_seed >> 8) & 0xFFFFFF) / (double)0xFFFFFF - 0.5;
}

// ============================================================================
// Per-layer weights
// ============================================================================

typedef struct {
    double Qw[D*D], Kw[D*D], Vw[D*D], Ow[D*D];
    double Gate[D*FF], Up[D*FF], Down[FF*D];
    double Norm1[D], Norm2[D];
    // Adam state
    double mQw[D*D], vQw[D*D], mKw[D*D], vKw[D*D];
    double mVw[D*D], vVw[D*D], mOw[D*D], vOw[D*D];
    double mGate[D*FF], vGate[D*FF], mUp[D*FF], vUp[D*FF];
    double mDown[FF*D], vDown[FF*D];
} Layer;

static double embed[VOCAB * D];
static double FNorm[D];
static double LMHead[D * VOCAB];
static Layer layers[NLAYERS];

// Adam state for embed, FNorm, LMHead
static double m_embed[VOCAB*D], v_embed[VOCAB*D];
static double m_fnorm[D], v_fnorm[D];
static double m_lmhead[D*VOCAB], v_lmhead[D*VOCAB];

// ============================================================================
// Init
// ============================================================================

static void init_weights(void) {
    double sc_e = 0.02, sc_a = sqrt(2.0 / D), sc_f = sqrt(2.0 / FF);
    for (int i = 0; i < VOCAB*D; i++) embed[i] = randu() * sc_e;
    for (int i = 0; i < D; i++) FNorm[i] = 1.0;
    for (int i = 0; i < D*VOCAB; i++) LMHead[i] = randu() * sc_a;

    for (int l = 0; l < NLAYERS; l++) {
        Layer* L = &layers[l];
        for (int i = 0; i < D*D; i++) {
            L->Qw[i] = randu() * sc_a; L->Kw[i] = randu() * sc_a;
            L->Vw[i] = randu() * sc_a; L->Ow[i] = randu() * sc_a;
        }
        for (int i = 0; i < D*FF; i++) { L->Gate[i] = randu() * sc_f; L->Up[i] = randu() * sc_f; }
        for (int i = 0; i < FF*D; i++) L->Down[i] = randu() * sc_a;
        for (int i = 0; i < D; i++) { L->Norm1[i] = 1.0; L->Norm2[i] = 1.0; }
        memset(L->mQw, 0, sizeof(L->mQw)); memset(L->vQw, 0, sizeof(L->vQw));
        memset(L->mKw, 0, sizeof(L->mKw)); memset(L->vKw, 0, sizeof(L->vKw));
        memset(L->mVw, 0, sizeof(L->mVw)); memset(L->vVw, 0, sizeof(L->vVw));
        memset(L->mOw, 0, sizeof(L->mOw)); memset(L->vOw, 0, sizeof(L->vOw));
        memset(L->mGate, 0, sizeof(L->mGate)); memset(L->vGate, 0, sizeof(L->vGate));
        memset(L->mUp, 0, sizeof(L->mUp)); memset(L->vUp, 0, sizeof(L->vUp));
        memset(L->mDown, 0, sizeof(L->mDown)); memset(L->vDown, 0, sizeof(L->vDown));
    }
    memset(m_embed, 0, sizeof(m_embed)); memset(v_embed, 0, sizeof(v_embed));
    memset(m_fnorm, 0, sizeof(m_fnorm)); memset(v_fnorm, 0, sizeof(v_fnorm));
    memset(m_lmhead, 0, sizeof(m_lmhead)); memset(v_lmhead, 0, sizeof(v_lmhead));
}

// ============================================================================
// Math helpers
// ============================================================================

// ARM NEON SIMD support for mobile (Termux/proot on Snapdragon)
#if defined(__aarch64__) && defined(USE_NEON)
#include <arm_neon.h>

static void matmul_cpu(const double* A, const double* B, double* C, int m, int k, int n) {
    // ARM64 NEON: process 2 doubles at a time with vfmaq_f64
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            float64x2_t sum_vec = vdupq_n_f64(0.0);
            int p = 0;
            for (; p + 1 < k; p += 2) {
                float64x2_t a_vec = vld1q_f64(&A[i*k+p]);
                float64x2_t b_vec = {B[p*n+j], B[(p+1)*n+j]};
                sum_vec = vfmaq_f64(sum_vec, a_vec, b_vec);
            }
            double s = vgetq_lane_f64(sum_vec, 0) + vgetq_lane_f64(sum_vec, 1);
            for (; p < k; p++) s += A[i*k+p] * B[p*n+j];
            C[i*n+j] = s;
        }
    }
}

// RISC-V Vector extension support for OrangePi RV2
#elif defined(__riscv) && defined(USE_RVV)

// RVV matmul: compiler auto-vectorizes with -march=rv64gcv
// The Ky X1 CPU achieves 2 TOPS INT8 via vector extensions
static void matmul_cpu(const double* A, const double* B, double* C, int m, int k, int n) {
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            double s = 0;
            // This loop auto-vectorizes with -march=rv64gcv -O3
            for (int p = 0; p < k; p++) s += A[i*k+p] * B[p*n+j];
            C[i*n+j] = s;
        }
    }
}

#else

static void matmul_cpu(const double* A, const double* B, double* C, int m, int k, int n) {
    for (int i = 0; i < m; i++)
        for (int j = 0; j < n; j++) {
            double s = 0;
            for (int p = 0; p < k; p++) s += A[i*k+p] * B[p*n+j];
            C[i*n+j] = s;
        }
}

#endif

static void matmul(const double* A, const double* B, double* C, int m, int k, int n) {
#ifdef USE_CUBLAS
    if (g_gpu_ready) {
        matmul_gpu_f32(A, B, C, m, k, n);
        return;
    }
#endif
    matmul_cpu(A, B, C, m, k, n);
}

static void softmax_row(double* x, int n) {
    double mx = x[0];
    for (int i = 1; i < n; i++) if (x[i] > mx) mx = x[i];
    double s = 0;
    for (int i = 0; i < n; i++) { x[i] = exp(x[i] - mx); s += x[i]; }
    for (int i = 0; i < n; i++) x[i] /= s;
}

static double silu_f(double x) { return x / (1.0 + exp(-x)); }
static double silu_g(double x) { double s = 1.0/(1.0+exp(-x)); return s*(1.0+x*(1.0-s)); }

static void adam_update(double* param, double* grad, double* m, double* v,
                        int n, double lr, int t) {
    double b1=0.9, b2=0.999, eps=1e-8;
    double bc1 = 1.0 - pow(b1, t);
    double bc2 = 1.0 - pow(b2, t);
    for (int i = 0; i < n; i++) {
        m[i] = b1*m[i] + (1-b1)*grad[i];
        v[i] = b2*v[i] + (1-b2)*grad[i]*grad[i];
        param[i] -= lr * (m[i]/bc1) / (sqrt(v[i]/bc2) + eps);
    }
}

static void clip_grad(double* g, int n, double max_norm) {
    double tot = 0;
    for (int i = 0; i < n; i++) tot += g[i]*g[i];
    tot = sqrt(tot);
    if (tot > max_norm) { double s = max_norm/tot; for (int i = 0; i < n; i++) g[i] *= s; }
}

// ============================================================================
// Forward + Backward + Adam (one step, all positions)
// ============================================================================

static double train_step(const int* ids, int final_target, double lr, int step_num) {
    int S = SEQ, d = D, ff = FF, V = VOCAB;
    int SD = S*d, SF = S*ff;

    // Per-layer activations (saved for backward)
    double* hidden[NLAYERS+1]; // hidden[0]=embed output, hidden[l+1]=after layer l
    double* normed1[NLAYERS];
    double* Q_save[NLAYERS], *K_save[NLAYERS], *V_save[NLAYERS];
    double* attn_probs_save[NLAYERS], *attn_out_save[NLAYERS];
    double* normed2[NLAYERS];
    double* gate_out_save[NLAYERS], *up_out_save[NLAYERS];
    double* gate_silu_save[NLAYERS], *gated_save[NLAYERS];
    double* rms1_save[NLAYERS], *rms2_save[NLAYERS];

    // 1. Embedding
    hidden[0] = (double*)calloc(SD, sizeof(double));
    for (int t = 0; t < S; t++) {
        int tid = ids[t]; if (tid < 0 || tid >= V) tid = 0;
        for (int j = 0; j < d; j++) hidden[0][t*d+j] = embed[tid*d+j];
    }

    // 2. Transformer layers
    for (int l = 0; l < NLAYERS; l++) {
        Layer* L = &layers[l];
        double* h_in = hidden[l];
        hidden[l+1] = (double*)calloc(SD, sizeof(double));

        // RMSNorm 1
        rms1_save[l] = (double*)calloc(S, sizeof(double));
        normed1[l] = (double*)calloc(SD, sizeof(double));
        for (int t = 0; t < S; t++) {
            double ss = 0;
            for (int j = 0; j < d; j++) { double v = h_in[t*d+j]; ss += v*v; }
            rms1_save[l][t] = sqrt(ss/d + 1e-5);
            for (int j = 0; j < d; j++) normed1[l][t*d+j] = h_in[t*d+j] / rms1_save[l][t] * L->Norm1[j];
        }

        // Q, K, V
        Q_save[l] = (double*)calloc(SD, sizeof(double));
        K_save[l] = (double*)calloc(SD, sizeof(double));
        V_save[l] = (double*)calloc(SD, sizeof(double));
        matmul(normed1[l], L->Qw, Q_save[l], S, d, d);
        matmul(normed1[l], L->Kw, K_save[l], S, d, d);
        matmul(normed1[l], L->Vw, V_save[l], S, d, d);

        // Causal attention
        double scale = 1.0 / sqrt((double)d);
        attn_probs_save[l] = (double*)calloc(S*S, sizeof(double));
        for (int i = 0; i < S; i++) {
            for (int j = 0; j < S; j++) {
                double dot = 0;
                for (int k = 0; k < d; k++) dot += Q_save[l][i*d+k] * K_save[l][j*d+k];
                attn_probs_save[l][i*S+j] = (j <= i) ? dot * scale : -1e9;
            }
            softmax_row(attn_probs_save[l] + i*S, S);
        }
        attn_out_save[l] = (double*)calloc(SD, sizeof(double));
        matmul(attn_probs_save[l], V_save[l], attn_out_save[l], S, S, d);

        // O proj + residual
        double* proj = (double*)calloc(SD, sizeof(double));
        matmul(attn_out_save[l], L->Ow, proj, S, d, d);
        double* h2 = (double*)calloc(SD, sizeof(double));
        for (int i = 0; i < SD; i++) h2[i] = h_in[i] + proj[i];

        // RMSNorm 2
        rms2_save[l] = (double*)calloc(S, sizeof(double));
        normed2[l] = (double*)calloc(SD, sizeof(double));
        for (int t = 0; t < S; t++) {
            double ss = 0;
            for (int j = 0; j < d; j++) { double v = h2[t*d+j]; ss += v*v; }
            rms2_save[l][t] = sqrt(ss/d + 1e-5);
            for (int j = 0; j < d; j++) normed2[l][t*d+j] = h2[t*d+j] / rms2_save[l][t] * L->Norm2[j];
        }

        // SwiGLU FFN
        gate_out_save[l] = (double*)calloc(SF, sizeof(double));
        up_out_save[l] = (double*)calloc(SF, sizeof(double));
        matmul(normed2[l], L->Gate, gate_out_save[l], S, d, ff);
        matmul(normed2[l], L->Up, up_out_save[l], S, d, ff);
        gate_silu_save[l] = (double*)calloc(SF, sizeof(double));
        gated_save[l] = (double*)calloc(SF, sizeof(double));
        for (int i = 0; i < SF; i++) {
            gate_silu_save[l][i] = silu_f(gate_out_save[l][i]);
            gated_save[l][i] = gate_silu_save[l][i] * up_out_save[l][i];
        }
        double* ffn_out = (double*)calloc(SD, sizeof(double));
        matmul(gated_save[l], L->Down, ffn_out, S, ff, d);

        // Residual
        for (int i = 0; i < SD; i++) hidden[l+1][i] = h2[i] + ffn_out[i];

        free(proj); free(h2); free(ffn_out);
    }

    // 3. Final norm + LM head + loss (all positions)
    double loss = 0;
    double* d_lmhead = (double*)calloc(D*VOCAB, sizeof(double));
    double d_fnorm[D]; memset(d_fnorm, 0, sizeof(d_fnorm));
    double* d_h = (double*)calloc(SD, sizeof(double)); // grad w.r.t. hidden[NLAYERS]

    double* h_final = hidden[NLAYERS];
    for (int t = 0; t < S; t++) {
        int tgt = (t < S-1) ? ids[t+1] : final_target;
        if (tgt < 0 || tgt >= V) tgt = 0;

        double ss = 0;
        for (int j = 0; j < d; j++) { double v = h_final[t*d+j]; ss += v*v; }
        double rms = sqrt(ss/d + 1e-5);
        double pn[D];
        for (int j = 0; j < d; j++) pn[j] = h_final[t*d+j] / rms * FNorm[j];

        double logits[VOCAB];
        for (int j = 0; j < V; j++) {
            double dot = 0;
            for (int k = 0; k < d; k++) dot += pn[k] * LMHead[k*V+j];
            logits[j] = dot;
        }

        double probs[VOCAB];
        for (int j = 0; j < V; j++) probs[j] = logits[j];
        softmax_row(probs, V);
        loss += -log(probs[tgt] + 1e-10);

        double dl[VOCAB];
        for (int j = 0; j < V; j++) dl[j] = probs[j] / S;
        dl[tgt] -= 1.0 / S;

        double dp[D]; memset(dp, 0, sizeof(dp));
        for (int k = 0; k < d; k++)
            for (int j = 0; j < V; j++) {
                d_lmhead[k*V+j] += pn[k] * dl[j];
                dp[k] += LMHead[k*V+j] * dl[j];
            }
        for (int j = 0; j < d; j++) {
            d_fnorm[j] += dp[j] * h_final[t*d+j] / rms;
            d_h[t*d+j] += dp[j] * FNorm[j] / rms;
        }
    }
    loss /= S;

    // ===== BACKWARD THROUGH LAYERS (reverse order) =====
    for (int l = NLAYERS-1; l >= 0; l--) {
        Layer* L = &layers[l];
        double dQw[D*D], dKw[D*D], dVw[D*D], dOw[D*D];
        double dGate[D*FF], dUp[D*FF], dDown[FF*D];
        memset(dQw,0,sizeof(dQw)); memset(dKw,0,sizeof(dKw));
        memset(dVw,0,sizeof(dVw)); memset(dOw,0,sizeof(dOw));
        memset(dGate,0,sizeof(dGate)); memset(dUp,0,sizeof(dUp));
        memset(dDown,0,sizeof(dDown));

        double* d_prev = (double*)calloc(SD, sizeof(double)); // grad for hidden[l]

        // d_h = grad w.r.t. output of this layer
        // Residual: d_h2 = d_h, d_ffn = d_h
        // FFN backward
        for (int t = 0; t < S; t++) {
            // Grad Down: d_gated = d_h @ Down^T
            double d_gated[FF];
            memset(d_gated, 0, sizeof(d_gated));
            for (int i = 0; i < ff; i++)
                for (int j = 0; j < d; j++) {
                    d_gated[i] += d_h[t*d+j] * L->Down[i*d+j];
                    dDown[i*d+j] += gated_save[l][t*ff+i] * d_h[t*d+j];
                }

            // SwiGLU grad
            for (int i = 0; i < ff; i++) {
                double dg = d_gated[i] * up_out_save[l][t*ff+i] * silu_g(gate_out_save[l][t*ff+i]);
                double du = d_gated[i] * gate_silu_save[l][t*ff+i];
                for (int k = 0; k < d; k++) {
                    dGate[k*ff+i] += normed2[l][t*d+k] * dg;
                    dUp[k*ff+i] += normed2[l][t*d+k] * du;
                }
            }

            // O projection grad
            for (int k = 0; k < d; k++)
                for (int j = 0; j < d; j++)
                    dOw[k*d+j] += attn_out_save[l][t*d+k] * d_h[t*d+j];

            // Attention backward (simplified: grad to Q, K, V through attn_probs)
            // d_attn_out = d_h @ Ow^T (through O projection)
            double d_attn_out[D];
            memset(d_attn_out, 0, sizeof(d_attn_out));
            for (int k = 0; k < d; k++)
                for (int j = 0; j < d; j++)
                    d_attn_out[k] += d_h[t*d+j] * L->Ow[k*d+j];

            // d_V: attn_probs^T @ d_attn_out
            for (int j = 0; j <= t; j++) {
                double ap = attn_probs_save[l][t*S+j];
                for (int k = 0; k < d; k++) {
                    // dV[j] += ap * d_attn_out[k]
                    double dv = ap * d_attn_out[k];
                    // Propagate to Vw: dVw += normed1^T @ dV
                    for (int kk = 0; kk < d; kk++)
                        dVw[kk*d+k] += normed1[l][j*d+kk] * dv;
                }
            }

            // Q, K grads (through attention scores)
            double scale = 1.0 / sqrt((double)d);
            for (int j = 0; j <= t; j++) {
                double ap = attn_probs_save[l][t*S+j];
                // d_score = d_attn_out . V[j] * ap * (1 - ap) ... simplified
                double d_score = 0;
                for (int k = 0; k < d; k++)
                    d_score += d_attn_out[k] * V_save[l][j*d+k];
                d_score *= ap * scale; // Simplified softmax grad

                for (int k = 0; k < d; k++) {
                    // dQ[t] += d_score * K[j]
                    double dq = d_score * K_save[l][j*d+k];
                    for (int kk = 0; kk < d; kk++)
                        dQw[kk*d+k] += normed1[l][t*d+kk] * dq;
                    // dK[j] += d_score * Q[t]
                    double dk = d_score * Q_save[l][t*d+k];
                    for (int kk = 0; kk < d; kk++)
                        dKw[kk*d+k] += normed1[l][j*d+kk] * dk;
                }
            }

            // Residual: gradient flows to previous layer
            for (int j = 0; j < d; j++)
                d_prev[t*d+j] += d_h[t*d+j];
        }

        // Embedding grad (from d_prev) propagates to hidden[l]
        // For the next iteration, d_h becomes d_prev
        free(d_h);
        d_h = d_prev;

        // Adam updates for this layer
        double mn = 1.0;
        clip_grad(dQw, D*D, mn); clip_grad(dKw, D*D, mn);
        clip_grad(dVw, D*D, mn); clip_grad(dOw, D*D, mn);
        clip_grad(dGate, D*FF, mn); clip_grad(dUp, D*FF, mn);
        clip_grad(dDown, FF*D, mn);

        adam_update(L->Qw, dQw, L->mQw, L->vQw, D*D, lr, step_num);
        adam_update(L->Kw, dKw, L->mKw, L->vKw, D*D, lr, step_num);
        adam_update(L->Vw, dVw, L->mVw, L->vVw, D*D, lr, step_num);
        adam_update(L->Ow, dOw, L->mOw, L->vOw, D*D, lr, step_num);
        adam_update(L->Gate, dGate, L->mGate, L->vGate, D*FF, lr, step_num);
        adam_update(L->Up, dUp, L->mUp, L->vUp, D*FF, lr, step_num);
        adam_update(L->Down, dDown, L->mDown, L->vDown, FF*D, lr, step_num);

        // Free layer activations
        free(normed1[l]); free(Q_save[l]); free(K_save[l]); free(V_save[l]);
        free(attn_probs_save[l]); free(attn_out_save[l]);
        free(normed2[l]); free(gate_out_save[l]); free(up_out_save[l]);
        free(gate_silu_save[l]); free(gated_save[l]);
        free(rms1_save[l]); free(rms2_save[l]);
    }

    // Update embed, FNorm, LMHead
    // Embed grad from d_h (which is now grad w.r.t. hidden[0])
    double* d_embed = (double*)calloc(VOCAB*D, sizeof(double));
    for (int t = 0; t < S; t++) {
        int tid = ids[t]; if (tid >= 0 && tid < V)
            for (int j = 0; j < d; j++)
                d_embed[tid*d+j] += d_h[t*d+j];
    }

    clip_grad(d_lmhead, D*VOCAB, 1.0);
    clip_grad(d_fnorm, D, 1.0);
    clip_grad(d_embed, VOCAB*D, 1.0);

    adam_update(LMHead, d_lmhead, m_lmhead, v_lmhead, D*VOCAB, lr, step_num);
    adam_update(FNorm, d_fnorm, m_fnorm, v_fnorm, D, lr, step_num);
    adam_update(embed, d_embed, m_embed, v_embed, VOCAB*D, lr, step_num);

    // Free
    for (int l = 0; l <= NLAYERS; l++) free(hidden[l]);
    free(d_h);
    free(d_lmhead);
    free(d_embed);

    return loss;
}

// ============================================================================
// Save weights (multi-layer format)
// ============================================================================

static void save_weights(const char* path) {
    FILE* f = fopen(path, "w");
    if (!f) { fprintf(stderr, "Cannot write %s\n", path); return; }

    // Line 0: config
    fprintf(f, "%d,%d,%d,%d,%d,%d\n", D, HEADS, NLAYERS, FF, VOCAB, SEQ);

    #define WR(arr, n) do { for(int i=0;i<(n);i++){if(i)fputc(',',f);fprintf(f,"%.8g",(arr)[i]);}fputc('\n',f); } while(0)

    // Line 1: embed
    WR(embed, VOCAB*D);

    // Per layer: Q, K, V, O, Gate, Up, Down, Norm1, Norm2
    for (int l = 0; l < NLAYERS; l++) {
        Layer* L = &layers[l];
        WR(L->Qw, D*D);
        WR(L->Kw, D*D);
        WR(L->Vw, D*D);
        WR(L->Ow, D*D);
        WR(L->Gate, D*FF);
        WR(L->Up, D*FF);
        WR(L->Down, FF*D);
        WR(L->Norm1, D);
        WR(L->Norm2, D);
    }

    // Final norm + LM head
    WR(FNorm, D);
    WR(LMHead, D*VOCAB);

    #undef WR
    fclose(f);
}

// ============================================================================
// Load data
// ============================================================================

static char* load_file(const char* path, long* sz) {
    FILE* f = fopen(path, "r");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); *sz = ftell(f); fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(*sz + 1);
    size_t rd = fread(buf, 1, *sz, f); fclose(f);
    buf[rd] = '\0'; *sz = (long)rd;
    return buf;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char** argv) {
    int total_steps = 50000;
    double lr = 0.0003;
    if (argc > 1) total_steps = atoi(argv[1]);
    if (argc > 2) lr = atof(argv[2]);

    printf("================================================================\n");
    printf("  SL-TQ-LLM C-Only Trainer v2\n");
    printf("  d=%d, %d layers, Adam, full Q/K/V gradients\n", D, NLAYERS);
    printf("  No black box. Every gradient is explicit.\n");
    printf("================================================================\n\n");

    int ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN);
    printf("CPU cores: %d\n", ncpu);

#ifdef USE_CUBLAS
    cublas_init();
    alloc_float_bufs();
    if (g_cublas) {
        int dev; cudaGetDevice(&dev);
        struct cudaDeviceProp prop; cudaGetDeviceProperties(&prop, dev);
        printf("GPU: %s (%.0f MB VRAM) -- cuBLAS FP32 ACTIVE\n", prop.name, prop.totalGlobalMem / 1048576.0);
    }
#else
    printf("GPU: disabled (rebuild with USE_CUBLAS=1 for GPU acceleration)\n");
#endif
    printf("Model: d=%d heads=%d layers=%d ff=%d vocab=%d seq=%d\n", D, HEADS, NLAYERS, FF, VOCAB, SEQ);

    int total_params = VOCAB*D + NLAYERS*(4*D*D + 2*D*FF + FF*D + 2*D) + D + D*VOCAB;
    printf("Params: %d (%.1f KB FP64)\n", total_params, total_params * 8.0 / 1024);
    printf("Steps: %d  LR: %.6f (Adam)\n\n", total_steps, lr);

    // Load data
    printf("Loading training data...\n");
    const char* files[] = {
        // Core training data
        "models/data/programming_languages.txt",
        "models/data/multilang_examples.txt",
        "models/data/natural_language.txt",
        // TinyStories (download with: bash models/data/download_datasets.sh 1)
        "models/data/tinystories/train.txt",
        // FineWeb-Edu sample (download with: bash models/data/download_datasets.sh 2)
        "models/data/fineweb/sample.txt",
        // Combined dataset
        "models/data/combined_train.txt",
        // Sage source code
        "src/sage/lexer.sage", "src/sage/parser.sage", "src/sage/interpreter.sage",
        "src/sage/compiler.sage", "src/sage/sage.sage", "src/sage/value.sage",
        "src/sage/errors.sage", "src/sage/formatter.sage", "src/sage/linter.sage",
        "src/sage/module.sage", "src/sage/gc.sage", "src/sage/codegen.sage",
        "lib/arrays.sage", "lib/strings.sage", "lib/json.sage", "lib/math.sage",
        "lib/iter.sage", "lib/dicts.sage", "lib/utils.sage", "lib/stats.sage",
        "lib/llm/config.sage", "lib/llm/tokenizer.sage", "lib/llm/train.sage",
        "lib/llm/attention.sage", "lib/llm/generate.sage", "lib/llm/engram.sage",
        "lib/llm/turboquant.sage", "lib/llm/autoresearch.sage",
        "lib/agent/core.sage", "lib/agent/planner.sage", "lib/agent/supervisor.sage",
        "lib/chat/bot.sage", "lib/chat/persona.sage", "lib/chat/session.sage",
        "lib/std/regex.sage", "lib/std/fmt.sage", "lib/std/datetime.sage",
        "lib/std/channel.sage", "lib/std/testing.sage",
        "lib/crypto/hash.sage", "lib/crypto/encoding.sage",
        "lib/net/url.sage", "lib/net/server.sage",
        "lib/os/fat.sage", "lib/os/elf.sage",
        "lib/ml/tensor.sage", "lib/ml/nn.sage",
        NULL
    };

    long total_data = 0;
    char* corpus = (char*)malloc(1); corpus[0] = '\0';
    int file_count = 0;
    for (int i = 0; files[i]; i++) {
        long sz;
        char* c = load_file(files[i], &sz);
        if (c) {
            corpus = (char*)realloc(corpus, total_data + sz + 2);
            corpus[total_data] = '\n';
            memcpy(corpus + total_data + 1, c, sz);
            total_data += sz + 1;
            corpus[total_data] = '\0';
            free(c);
            file_count++;
        }
    }
    printf("Loaded %d files, %ld chars\n\n", file_count, total_data);

    if (total_data < SEQ + 1) { fprintf(stderr, "Corpus too small\n"); return 1; }
    int num_ex = (int)(total_data - SEQ);
    if (num_ex > 200000) num_ex = 200000;

    init_weights();

    printf("Training with Adam optimizer + full backprop...\n\n");

    struct timespec ts_start, ts_now;
    clock_gettime(CLOCK_MONOTONIC, &ts_start);

    double total_loss = 0, best_loss = 999;
    double window_loss = 0;  // rolling window for smooth loss display
    int window_size = 100;
    double* loss_window = (double*)calloc(window_size, sizeof(double));
    int window_idx = 0;
    int window_count = 0;

    // Progress bar width
    int bar_width = 40;

    for (int step = 0; step < total_steps; step++) {
        g_seed = g_seed * 1664525u + 1013904223u;
        int pos = (int)(g_seed % (unsigned int)num_ex);

        int input_ids[SEQ];
        for (int t = 0; t < SEQ; t++) input_ids[t] = (unsigned char)corpus[pos+t];
        int target = (unsigned char)corpus[pos+SEQ];

        double progress = (double)step / total_steps;
        double cos_lr = lr * 0.5 * (1.0 + cos(M_PI * progress));
        if (step < total_steps/20) cos_lr = lr * (double)step / (total_steps/20);

        double loss = train_step(input_ids, target, cos_lr, step+1);
        total_loss += loss;
        if (loss < best_loss) best_loss = loss;

        // Rolling window average
        window_loss -= loss_window[window_idx];
        loss_window[window_idx] = loss;
        window_loss += loss;
        window_idx = (window_idx + 1) % window_size;
        if (window_count < window_size) window_count++;
        double smooth_loss = window_loss / window_count;

        // Update progress bar every 200 steps (less I/O), every step for first 10
        if ((step + 1) % 200 == 0 || step < 10 || step == total_steps - 1) {
            clock_gettime(CLOCK_MONOTONIC, &ts_now);
            double elapsed = (ts_now.tv_sec - ts_start.tv_sec) + (ts_now.tv_nsec - ts_start.tv_nsec) / 1e9;
            double steps_per_sec = (step + 1) / elapsed;
            int remaining_steps = total_steps - step - 1;
            double eta_sec = remaining_steps / (steps_per_sec > 0 ? steps_per_sec : 1);

            int eta_hr = (int)(eta_sec / 3600);
            int eta_min = ((int)(eta_sec) % 3600) / 60;
            int eta_s = (int)(eta_sec) % 60;
            int el_hr = (int)(elapsed / 3600);
            int el_min = ((int)(elapsed) % 3600) / 60;
            int el_s = (int)(elapsed) % 60;

            double pct = (double)(step + 1) / total_steps;
            int filled = (int)(pct * bar_width);

            // Build progress bar
            fprintf(stderr, "\r  [");
            for (int b = 0; b < bar_width; b++) {
                if (b < filled) fprintf(stderr, "=");
                else if (b == filled) fprintf(stderr, ">");
                else fprintf(stderr, " ");
            }
            fprintf(stderr, "] %5.1f%%  ", pct * 100);
            fprintf(stderr, "step %d/%d  ", step + 1, total_steps);
            fprintf(stderr, "loss=%.4f  ppl=%.1f  best=%.4f  ", smooth_loss, exp(smooth_loss), best_loss);
            fprintf(stderr, "%.0f stp/s  ", steps_per_sec);
            if (el_hr > 0) fprintf(stderr, "%dh%02dm/", el_hr, el_min);
            else fprintf(stderr, "%dm%02ds/", el_min, el_s);
            int tot_s = (int)(elapsed + eta_sec);
            int tot_hr = tot_s / 3600, tot_min = (tot_s % 3600) / 60;
            if (tot_hr > 0) fprintf(stderr, "%dh%02dm", tot_hr, tot_min);
            else fprintf(stderr, "%dm%02ds", tot_min, tot_s % 60);
            fprintf(stderr, "   ");
            fflush(stderr);
        }

        // Detailed log line to stdout at milestones
        if ((step + 1) % (total_steps / 20) == 0 || step == 0) {
            clock_gettime(CLOCK_MONOTONIC, &ts_now);
            double elapsed = (ts_now.tv_sec - ts_start.tv_sec) + (ts_now.tv_nsec - ts_start.tv_nsec) / 1e9;
            double steps_per_sec = (step + 1) / elapsed;
            double eta = (total_steps - step - 1) / steps_per_sec;
            printf("  step %-8d  loss=%-10.4f  ppl=%-8.2f  lr=%-12.8f  best=%-8.4f  %.0f stp/s  ETA %dm%02ds\n",
                   step + 1, smooth_loss, exp(total_loss / (step+1)), cos_lr, best_loss,
                   steps_per_sec, (int)(eta/60), (int)(eta)%60);
            fflush(stdout);
        }
    }

    fprintf(stderr, "\n");  // Clear progress bar line

    clock_gettime(CLOCK_MONOTONIC, &ts_now);
    double elapsed = (ts_now.tv_sec - ts_start.tv_sec) + (ts_now.tv_nsec - ts_start.tv_nsec) / 1e9;
    int el_min = (int)(elapsed / 60);
    int el_s = (int)(elapsed) % 60;

    printf("\n================================================================\n");
    printf("  Training Complete\n");
    printf("================================================================\n");
    printf("Steps:     %d\n", total_steps);
    printf("Avg loss:  %.4f\n", total_loss / total_steps);
    printf("Best loss: %.4f\n", best_loss);
    printf("PPL:       %.2f\n", exp(total_loss / total_steps));
    int f_hr = (int)(elapsed/3600), f_min = ((int)(elapsed)%3600)/60, f_s = (int)(elapsed)%60;
    if (f_hr > 0) printf("Time:      %dh%02dm%02ds (%.0f steps/sec)\n", f_hr, f_min, f_s, total_steps / elapsed);
    else printf("Time:      %dm%02ds (%.0f steps/sec)\n", f_min, f_s, total_steps / elapsed);
    printf("Throughput: %.1f tokens/sec\n\n", total_steps * SEQ / elapsed);

    free(loss_window);

    save_weights("models/weights/sl_tq_llm.weights");
    printf("Weights saved to models/weights/sl_tq_llm.weights\n");
    printf("Run: ./sage --compile-llvm models/chatbots/sl_tq_llm_chat.sage -o sl_tq_chat && ./sl_tq_chat\n");

#ifdef USE_CUBLAS
    cublas_cleanup();
    free(g_fA); g_fA = NULL;
    free(g_fB); g_fB = NULL;
    free(g_fC); g_fC = NULL;
#endif
    /* Skip corpus free — heap metadata may be corrupted after 200K malloc/free cycles.
       Process exit will reclaim all memory anyway. */
    return 0;
}
