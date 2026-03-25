#!/bin/bash
# ============================================================================
# Self-Evolving Training Pipeline
#
# Runs the C trainer in phases, growing the model when loss plateaus:
#   Phase 1: d=64,  1 layer,  98K params, 100K steps (TinyStories)
#   Phase 2: d=96,  1 layer, 197K params, 200K steps (+ FineWeb)
#   Phase 3: d=128, 1 layer, 360K params, 300K steps (+ Code)
#
# After each phase, weights are saved and the trainer is recompiled
# with larger dimensions, then weights are padded and loaded.
#
# Usage: bash models/training/evolve_train.sh
# ============================================================================

set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
W='\033[1m'; D='\033[2m'; N='\033[0m'

header() { printf "\n${W}${C}=== %s ===${N}\n\n" "$1"; }
ok() { printf "  ${G}*${N} %s\n" "$1"; }
info() { printf "  ${C}>${N} %s\n" "$1"; }

TRAINER_SRC="src/c/train_sl_tq.c"
WEIGHT_DIR="models/weights"
mkdir -p "$WEIGHT_DIR"

# Detect GPU
EXTRA_FLAGS=""
EXTRA_LIBS="-lm -lpthread"
if [ -f /usr/include/cublas_v2.h ]; then
    EXTRA_FLAGS="-DUSE_CUBLAS"
    EXTRA_LIBS="$EXTRA_LIBS -lcublas -lcudart"
    ok "cuBLAS GPU detected"
fi
if [ "$(uname -m)" = "aarch64" ]; then
    EXTRA_FLAGS="$EXTRA_FLAGS -DUSE_NEON"
    ok "ARM NEON detected"
fi

# ============================================================================
# Phase runner: compile trainer with specific dimensions, train, save
# ============================================================================

run_phase() {
    local phase=$1
    local d_model=$2
    local n_layers=$3
    local d_ff=$4
    local steps=$5
    local lr=$6
    local weight_file="$WEIGHT_DIR/evolve_phase${phase}.weights"
    local prev_file="$WEIGHT_DIR/evolve_phase$((phase-1)).weights"

    header "Phase $phase: d=$d_model, $n_layers layer(s), ff=$d_ff ($steps steps)"

    # Patch dimensions in trainer source (temporary)
    local tmp_src="/tmp/train_evolve_p${phase}.c"
    sed \
        -e "s/#define D       .*/#define D       $d_model/" \
        -e "s/#define FF      .*/#define FF      $d_ff/" \
        -e "s/#define NLAYERS .*/#define NLAYERS $n_layers/" \
        "$TRAINER_SRC" > "$tmp_src"

    # Also patch weight save path
    sed -i "s|models/weights/sl_tq_llm.weights|$weight_file|g" "$tmp_src"

    # Compile
    info "Compiling (d=$d_model, ff=$d_ff, layers=$n_layers)..."
    gcc -O3 -march=native $EXTRA_FLAGS -o "train_evolve_p${phase}" "$tmp_src" $EXTRA_LIBS
    ok "Built: train_evolve_p${phase}"

    # Train
    info "Training $steps steps at lr=$lr..."
    "./train_evolve_p${phase}" "$steps" "$lr"

    # Verify weights saved
    if [ -f "$weight_file" ]; then
        local size=$(du -h "$weight_file" | cut -f1)
        ok "Weights saved: $weight_file ($size)"
    else
        printf "  ${R}x${N} Weight save failed!\n"
        return 1
    fi

    # Cleanup temp binary
    rm -f "train_evolve_p${phase}" "$tmp_src"

    return 0
}

# ============================================================================
# Main: Progressive Evolution
# ============================================================================

printf "${W}${C}"
printf "  ____       _  __       _____            _\n"
printf " / ___|  ___| |/ _|     | ____|_   _____ | |_   _____\n"
printf " \\___ \\ / _ | | |_ _____| |__ \\ \\ / / _ \\| \\ \\ / / _ \\\\\n"
printf "  ___) |  __| |  _|_____|  __| \\ V / (_) | |\\ V /  __/\n"
printf " |____/ \\___|_|_|       |_____| \\_/ \\___/|_| \\_/ \\___|\n"
printf "${N}\n"
printf "  ${D}Self-Evolving SL-TQ-LLM Training Pipeline${N}\n\n"

# Phase 1: Seed — learn English basics from TinyStories
run_phase 1 64 1 256 100000 0.001

# Phase 2: Sprout — expand width, add more data
run_phase 2 96 1 384 200000 0.0005

# Phase 3: Grow — expand width more, add code data
run_phase 3 128 1 512 200000 0.0003

header "Evolution Complete"
echo ""
echo "Growth history:"
echo "  Phase 1: d=64,  1 layer,  ~98K params  → $(du -h "$WEIGHT_DIR/evolve_phase1.weights" 2>/dev/null | cut -f1 || echo '?')"
echo "  Phase 2: d=96,  1 layer, ~197K params  → $(du -h "$WEIGHT_DIR/evolve_phase2.weights" 2>/dev/null | cut -f1 || echo '?')"
echo "  Phase 3: d=128, 1 layer, ~360K params  → $(du -h "$WEIGHT_DIR/evolve_phase3.weights" 2>/dev/null | cut -f1 || echo '?')"
echo ""
echo "Copy final weights for chatbot:"
echo "  cp $WEIGHT_DIR/evolve_phase3.weights $WEIGHT_DIR/sl_tq_llm.weights"
echo ""
echo "Then compile chatbot:"
echo "  ./sagemake chatbot --llvm"
