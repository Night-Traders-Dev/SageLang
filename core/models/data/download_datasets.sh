#!/bin/bash
# ============================================================================
# Dataset Download Pipeline for SL-TQ-LLM Self-Evolving Model
#
# Downloads and prepares training datasets in phases:
#   Phase 1: TinyStories (natural language basics)
#   Phase 2: FineWeb-Edu sample (quality web text)
#   Phase 3: Code samples (The Stack subset)
#
# Usage: bash models/data/download_datasets.sh [phase]
#   phase 1: TinyStories only (~500MB)
#   phase 2: + FineWeb-Edu 10B sample (~2GB)
#   phase 3: + Code samples (~1GB)
#   all:     Download everything
# ============================================================================

set -euo pipefail

DATA_DIR="models/data"
PHASE="${1:-1}"

echo "============================================"
echo "  SL-TQ-LLM Dataset Download Pipeline"
echo "  Phase: $PHASE"
echo "============================================"
echo ""

# Check for required tools
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 required for HuggingFace downloads"
    echo "Install: apt install python3 python3-pip"
    exit 1
fi

# Phase 1: TinyStories — perfect for tiny models learning English
download_tinystories() {
    echo "=== Phase 1: TinyStories ==="
    echo "  Source: roneneldan/TinyStories (HuggingFace)"
    echo "  Size: ~500MB"
    echo "  Why: Proves tiny models (28M params) can speak coherent English"
    echo ""

    mkdir -p "$DATA_DIR/tinystories"

    if [ -f "$DATA_DIR/tinystories/train.txt" ]; then
        echo "  Already downloaded. Skipping."
        return
    fi

    # Try HuggingFace CLI first
    if command -v huggingface-cli &>/dev/null; then
        echo "  Downloading via huggingface-cli..."
        huggingface-cli download roneneldan/TinyStories --local-dir "$DATA_DIR/tinystories" --include "*.txt" || true
    else
        # Fallback: direct download
        echo "  Downloading via curl..."
        curl -L -o "$DATA_DIR/tinystories/TinyStoriesV2-GPT4-train.txt" \
            "https://huggingface.co/datasets/roneneldan/TinyStories/resolve/main/TinyStoriesV2-GPT4-train.txt" 2>/dev/null || true
        curl -L -o "$DATA_DIR/tinystories/TinyStoriesV2-GPT4-valid.txt" \
            "https://huggingface.co/datasets/roneneldan/TinyStories/resolve/main/TinyStoriesV2-GPT4-valid.txt" 2>/dev/null || true

        # Combine into single file
        if [ -f "$DATA_DIR/tinystories/TinyStoriesV2-GPT4-train.txt" ]; then
            cat "$DATA_DIR/tinystories/TinyStoriesV2-GPT4-train.txt" > "$DATA_DIR/tinystories/train.txt"
            echo "  Downloaded TinyStories train set"
        else
            echo "  Download failed — generating synthetic TinyStories locally"
            generate_synthetic_stories
        fi
    fi
}

# Generate synthetic tiny stories if download fails
generate_synthetic_stories() {
    echo "  Generating synthetic training stories..."
    cat > "$DATA_DIR/tinystories/train.txt" << 'STORIES'
Once upon a time, there was a little cat named Luna. Luna liked to play in the garden. She would chase butterflies and roll in the grass. One day, Luna found a shiny red ball. She batted it with her paw and it rolled away. Luna chased the ball all around the yard. When she was tired, she curled up in the sun and fell asleep. Luna had a wonderful day.

Tom was a small robot who lived in a workshop. Every morning, Tom would help the inventor build new things. Today they were building a birdhouse. Tom held the pieces while the inventor hammered nails. When the birdhouse was done, they hung it in the tree. A blue bird came and looked inside. The bird liked it! Tom was happy he could help make a home for the bird.

Sara loved to read books. Her favorite book was about a dragon who could cook. The dragon made pancakes for all the village children. Sara wished she could visit the dragon. One night, she dreamed she flew on the dragon's back. They soared over mountains and rivers. When she woke up, Sara smiled and opened her book again.

The sun was shining bright. A puppy named Max ran through the park. He saw a squirrel and tried to catch it. The squirrel ran up a tree. Max barked and wagged his tail. A little girl came and petted Max. She gave him a treat. Max licked her hand. They became best friends and played together every day.

In a small pond, a frog named Fred sat on a lily pad. Fred liked to sing songs. He sang in the morning and he sang at night. The other frogs listened and clapped. One day, a bird heard Fred singing. The bird started to sing along. Together they made beautiful music. All the animals in the forest came to listen.
STORIES
    echo "  Generated 5 synthetic stories for initial training"
}

# Phase 2: FineWeb-Edu sample — high-quality educational text
download_fineweb_sample() {
    echo ""
    echo "=== Phase 2: FineWeb-Edu Sample ==="
    echo "  Source: HuggingFaceFW/fineweb-edu (sample)"
    echo "  Size: ~50MB (small sample for our model size)"
    echo ""

    mkdir -p "$DATA_DIR/fineweb"

    if [ -f "$DATA_DIR/fineweb/sample.txt" ]; then
        echo "  Already downloaded. Skipping."
        return
    fi

    # Download a small sample via Python
    python3 -c "
try:
    from datasets import load_dataset
    ds = load_dataset('HuggingFaceFW/fineweb-edu', split='train', streaming=True)
    with open('$DATA_DIR/fineweb/sample.txt', 'w') as f:
        count = 0
        for item in ds:
            f.write(item['text'] + '\n\n')
            count += 1
            if count >= 5000:  # 5000 documents
                break
    print(f'  Downloaded {count} FineWeb-Edu documents')
except Exception as e:
    print(f'  FineWeb download failed: {e}')
    print('  Install: pip install datasets')
" 2>/dev/null || echo "  Skipping FineWeb (install: pip install datasets)"
}

# Phase 3: Code samples from open sources
download_code_samples() {
    echo ""
    echo "=== Phase 3: Code Samples ==="
    echo "  Collecting code from open-source projects"
    echo ""

    mkdir -p "$DATA_DIR/code"

    if [ -f "$DATA_DIR/code/combined.txt" ]; then
        echo "  Already prepared. Skipping."
        return
    fi

    # Collect from our own codebase (already available)
    echo "  Collecting Sage source code..."
    local code_file="$DATA_DIR/code/combined.txt"
    > "$code_file"

    # Our Sage code
    for f in src/sage/*.sage lib/*.sage lib/*/*.sage; do
        [ -f "$f" ] || continue
        echo "# File: $f" >> "$code_file"
        cat "$f" >> "$code_file"
        echo "" >> "$code_file"
    done

    # Our C code
    for f in src/c/*.c include/*.h; do
        [ -f "$f" ] || continue
        echo "// File: $f" >> "$code_file"
        cat "$f" >> "$code_file"
        echo "" >> "$code_file"
    done

    local size=$(wc -c < "$code_file")
    echo "  Collected $(wc -l < "$code_file") lines ($size bytes) of code"
}

# Prepare combined training file
prepare_combined() {
    echo ""
    echo "=== Preparing Combined Training Data ==="

    local combined="$DATA_DIR/combined_train.txt"
    > "$combined"

    # Always include our existing data
    [ -f "$DATA_DIR/programming_languages.txt" ] && cat "$DATA_DIR/programming_languages.txt" >> "$combined"
    [ -f "$DATA_DIR/multilang_examples.txt" ] && cat "$DATA_DIR/multilang_examples.txt" >> "$combined"
    [ -f "$DATA_DIR/natural_language.txt" ] && cat "$DATA_DIR/natural_language.txt" >> "$combined"

    # Phase 1: TinyStories
    [ -f "$DATA_DIR/tinystories/train.txt" ] && cat "$DATA_DIR/tinystories/train.txt" >> "$combined"

    # Phase 2: FineWeb
    [ -f "$DATA_DIR/fineweb/sample.txt" ] && cat "$DATA_DIR/fineweb/sample.txt" >> "$combined"

    # Phase 3: Code
    [ -f "$DATA_DIR/code/combined.txt" ] && cat "$DATA_DIR/code/combined.txt" >> "$combined"

    local size=$(wc -c < "$combined")
    local lines=$(wc -l < "$combined")
    echo "  Combined: $lines lines, $size bytes"
    echo "  Output: $combined"
    echo ""
    echo "  Train with: ./train_sl_tq 200000 0.001"
    echo "  The C trainer reads from models/data/*.txt automatically"
}

# Execute phases
case "$PHASE" in
    1)
        download_tinystories
        prepare_combined
        ;;
    2)
        download_tinystories
        download_fineweb_sample
        prepare_combined
        ;;
    3|all)
        download_tinystories
        download_fineweb_sample
        download_code_samples
        prepare_combined
        ;;
    *)
        echo "Usage: bash models/data/download_datasets.sh [1|2|3|all]"
        exit 1
        ;;
esac

echo ""
echo "Done! Dataset preparation complete."
