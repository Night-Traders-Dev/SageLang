#!/usr/bin/env python3
import json
import time
import subprocess
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HISTORY_FILE = REPO_ROOT / "benchmarks" / "metrics_history.json"
CHART_PATH = REPO_ROOT / "assets" / "runtime_history.svg"
SAGE = REPO_ROOT / "sage"
BENCH = REPO_ROOT / "benchmarks" / "backend_compare.sage"

def run_timed(cmd):
    start = time.perf_counter()
    try:
        subprocess.run(cmd, capture_output=True, check=True, timeout=300)
        return time.perf_counter() - start, True
    except:
        return 0, False

def collect_current():
    results = {}
    
    # 1. AST Interpreter
    t, ok = run_timed([str(SAGE), "--runtime", "ast", str(BENCH)])
    if ok: results["AST Interpreter"] = t
    
    # 2. Bytecode VM
    t, ok = run_timed([str(SAGE), "--runtime", "bytecode", str(BENCH)])
    if ok: results["Bytecode VM"] = t
    
    # 3. JIT (if available)
    t, ok = run_timed([str(SAGE), "--runtime", "jit", str(BENCH)])
    if ok: results["JIT Compiler"] = t

    # 4. AOT (if available)
    t, ok = run_timed([str(SAGE), "--runtime", "aot", str(BENCH)])
    if ok: results["AOT Compiler"] = t

    # 5. C Backend
    c_out = REPO_ROOT / "bench_c"
    t, ok = run_timed([str(SAGE), "--compile-c", str(BENCH), "-o", str(c_out)])
    if ok:
        t2, ok2 = run_timed([str(c_out)])
        if ok2: results["C Backend"] = t2
        if c_out.exists(): os.remove(c_out)

    return results

def update_history(current_results):
    history = []
    if HISTORY_FILE.exists():
        with open(HISTORY_FILE, "r") as f:
            history = json.load(f)
    
    entry = {
        "timestamp": int(time.time()),
        "date": time.strftime("%Y-%m-%d %H:%M"),
        "results": current_results
    }
    history.append(entry)
    
    # Keep last 20 entries
    if len(history) > 20:
        history = history[-20:]
        
    with open(HISTORY_FILE, "w") as f:
        json.dump(history, f, indent=2)
    return history

def render_line_chart(history):
    if not history: return
    
    width = 800
    height = 400
    padding = 60
    
    # Identify all unique backend names
    backends = set()
    for entry in history:
        backends.update(entry["results"].keys())
    backends = sorted(list(backends))
    
    colors = ["#3B82F6", "#EF4444", "#10B981", "#F59E0B", "#8B5CF6", "#EC4899", "#06B6D4"]
    backend_colors = {b: colors[i % len(colors)] for i, b in enumerate(backends)}
    
    max_time = 0
    for entry in history:
        for t in entry["results"].values():
            max_time = max(max_time, t)
    
    if max_time == 0: max_time = 1.0
    
    svg = [
        f'<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg">',
        '<rect width="100%" height="100%" fill="#0B1118"/>',
        f'<text x="{width/2}" y="30" fill="#F8FAFC" font-size="20" font-family="sans-serif" text-anchor="middle" font-weight="bold">SageLang Performance Over Time</text>',
    ]
    
    # Draw axes
    svg.append(f'<line x1="{padding}" y1="{height-padding}" x2="{width-padding}" y2="{height-padding}" stroke="#475569" stroke-width="2"/>')
    svg.append(f'<line x1="{padding}" y1="{padding}" x2="{padding}" y2="{height-padding}" stroke="#475569" stroke-width="2"/>')
    
    # X-axis scale
    num_points = len(history)
    x_step = (width - 2*padding) / (num_points - 1) if num_points > 1 else 0
    
    # Draw lines
    for b in backends:
        points = []
        for i, entry in enumerate(history):
            if b in entry["results"]:
                x = padding + i * x_step
                y = height - padding - (entry["results"][b] / max_time) * (height - 2*padding)
                points.append(f"{x},{y}")
        
        if len(points) > 1:
            svg.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="{backend_colors[b]}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>')
            # Draw dots
            for p in points:
                px, py = p.split(",")
                svg.append(f'<circle cx="{px}" cy="{py}" r="4" fill="{backend_colors[b]}"/>')

    # Legend
    leg_x = padding + 10
    leg_y = padding + 20
    for b in backends:
        svg.append(f'<rect x="{leg_x}" y="{leg_y}" width="12" height="12" fill="{backend_colors[b]}"/>')
        svg.append(f'<text x="{leg_x + 20}" y="{leg_y + 10}" fill="#94A3B8" font-size="12" font-family="sans-serif">{b}</text>')
        leg_y += 20

    svg.append('</svg>')
    
    with open(CHART_PATH, "w") as f:
        f.write("\n".join(svg))
    print(f"Chart saved to {CHART_PATH}")

if __name__ == "__main__":
    print("Collecting current performance metrics...")
    current = collect_current()
    if current:
        print(f"Collected {len(current)} backend results.")
        history = update_history(current)
        render_line_chart(history)
    else:
        print("Failed to collect any results.")
