#!/usr/bin/env python3
"""Generate backend comparison chart from benchmark results."""

import subprocess
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHART_PATH = REPO_ROOT / "assets" / "charts" / "backend-compare.svg"
SAGE = REPO_ROOT / "sage"
BENCH = REPO_ROOT / "benchmarks" / "backend_compare.sage"


def run_timed(cmd: list[str], cwd: Path = REPO_ROOT) -> tuple[float, str, bool]:
    """Run a command and return (seconds, stdout, success)."""
    start = time.monotonic()
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd=cwd)
        elapsed = time.monotonic() - start
        return elapsed, result.stdout, result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        elapsed = time.monotonic() - start
        return elapsed, "", False


def collect_results() -> list[tuple[str, float, str]]:
    """Collect benchmark results for each backend. Returns [(name, seconds, color)]."""
    results = []
    tmp = Path("/tmp/sage_backend_bench")
    tmp.mkdir(exist_ok=True)

    # AST interpreter
    t, _, ok = run_timed([str(SAGE), str(BENCH)])
    if ok:
        results.append(("AST Interpreter", t, "#3A86FF"))

    # Bytecode VM
    t, _, ok = run_timed([str(SAGE), "--runtime", "bytecode", str(BENCH)])
    if ok:
        results.append(("Bytecode VM", t, "#14B8A6"))

    # C compiled (build + run)
    c_bin = tmp / "bench_c"
    build_t, _, ok = run_timed([str(SAGE), "--compile", str(BENCH), "-o", str(c_bin)])
    if ok:
        run_t, _, ok2 = run_timed([str(c_bin)])
        if ok2:
            results.append(("C Backend (run)", run_t, "#F97316"))
            results.append(("C Backend (total)", build_t + run_t, "#FB923C"))

    # LLVM compiled
    llvm_bin = tmp / "bench_llvm"
    build_t, _, ok = run_timed([str(SAGE), "--compile-llvm", str(BENCH), "-o", str(llvm_bin)])
    if ok:
        run_t, _, ok2 = run_timed([str(llvm_bin)])
        if ok2:
            results.append(("LLVM Backend (run)", run_t, "#A855F7"))
            results.append(("LLVM Backend (total)", build_t + run_t, "#C084FC"))

    # C compiled -O3
    c_o3 = tmp / "bench_c_o3"
    build_t, _, ok = run_timed([str(SAGE), "--compile", str(BENCH), "-o", str(c_o3), "-O3"])
    if ok:
        run_t, _, ok2 = run_timed([str(c_o3)])
        if ok2:
            results.append(("C -O3 (run)", run_t, "#EF4444"))

    # Kotlin transpile (emit only)
    kt_out = tmp / "bench.kt"
    t, _, ok = run_timed([str(SAGE), "--emit-kotlin", str(BENCH), "-o", str(kt_out)])
    if ok:
        results.append(("Kotlin Transpile", t, "#7C3AED"))

    # Cleanup
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)

    return results


def fmt_duration(value: float) -> str:
    if value >= 1.0:
        return f"{value:.2f}s"
    millis = value * 1000.0
    if millis >= 100:
        return f"{millis:.0f}ms"
    if millis >= 10:
        return f"{millis:.1f}ms"
    return f"{millis:.2f}ms"


def adjust_color(color: str, factor: float) -> str:
    color = color.lstrip("#")
    channels = []
    for i in (0, 2, 4):
        c = int(color[i:i+2], 16)
        if factor >= 1.0:
            c = c + (255 - c) * (factor - 1.0)
        else:
            c = c * factor
        channels.append(max(0, min(255, int(round(c)))))
    return "#{:02X}{:02X}{:02X}".format(*channels)


def render_chart(results: list[tuple[str, float, str]]) -> None:
    from xml.sax.saxutils import escape
    from datetime import datetime, timezone

    if not results:
        print("No results to chart")
        return

    width = 1600
    margin_left = 280
    margin_right = 180
    margin_top = 135
    bar_height = 44
    bar_gap = 22
    footer_padding = 100
    plot_width = width - margin_left - margin_right
    plot_height = len(results) * bar_height + max(0, len(results) - 1) * bar_gap
    height = margin_top + plot_height + footer_padding
    max_value = max(v for _, v, _ in results)

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img">',
        "<title>SageLang Backend Performance Comparison</title>",
        "<defs>",
    ]

    for i, (_, _, color) in enumerate(results):
        start = adjust_color(color, 1.2)
        end = adjust_color(color, 0.82)
        svg.append(f'<linearGradient id="bg-{i}" x1="0%" y1="0%" x2="100%" y2="0%">')
        svg.append(f'<stop offset="0%" stop-color="{start}"/>')
        svg.append(f'<stop offset="100%" stop-color="{end}"/>')
        svg.append("</linearGradient>")

    svg.extend([
        "</defs>",
        '<rect width="100%" height="100%" fill="#0B1118"/>',
        f'<rect x="12" y="12" width="1576" height="{height - 24}" rx="18" fill="#0F1722" stroke="#1F2937"/>',
        '<text x="44" y="62" fill="#F8FAFC" font-size="34" font-family="Segoe UI, Arial, sans-serif" font-weight="700">SageLang Backend Performance Comparison</text>',
        '<text x="44" y="95" fill="#94A3B8" font-size="18" font-family="Segoe UI, Arial, sans-serif">benchmarks/backend_compare.sage — 8 workloads (fib, loops, arrays, strings, dicts, primes, nested, LCG)</text>',
    ])

    max_bar_ratio = 0.80

    for i, (name, value, color) in enumerate(results):
        y = margin_top + i * (bar_height + bar_gap)
        bar_w = max(6.0, plot_width * (value / max_value) * max_bar_ratio)
        badge_w = max(92, min(260, 34 + len(name) * 9))
        badge_fill = adjust_color(color, 0.9)
        count_text = fmt_duration(value)
        badge_y = y + 6

        count_x = margin_left + bar_w + 14
        if count_x > width - 240:
            count_x = margin_left + bar_w - 14
            anchor = "end"
            fill = "#0F1722"
        else:
            anchor = "start"
            fill = "#E2E8F0"

        svg.extend([
            f'<rect x="30" y="{badge_y:.1f}" width="{badge_w}" height="32" rx="10" fill="{badge_fill}" opacity="0.95"/>',
            f'<text x="{30 + badge_w/2:.1f}" y="{badge_y + 22:.1f}" text-anchor="middle" fill="#E2E8F0" '
            f'font-size="13" font-family="Segoe UI, Arial, sans-serif" font-weight="700">{escape(name.upper())}</text>',
            f'<rect x="{margin_left}" y="{y}" width="{plot_width}" height="{bar_height}" rx="12" fill="#131D2A" stroke="#233041"/>',
            f'<rect x="{margin_left}" y="{y}" width="{bar_w:.1f}" height="{bar_height}" rx="12" fill="url(#bg-{i})"/>',
            f'<text x="{count_x:.1f}" y="{y + 29:.1f}" text-anchor="{anchor}" fill="{fill}" font-size="18" '
            f'font-family="Segoe UI, Arial, sans-serif" font-weight="700">{escape(count_text)}</text>',
        ])

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    footer_y = margin_top + plot_height + 40
    svg.append(f'<text x="44" y="{footer_y}" fill="#94A3B8" font-size="16" font-family="Segoe UI, Arial, sans-serif">'
               f'Lower is better. Last refreshed: {generated}</text>')
    svg.append("</svg>")

    CHART_PATH.parent.mkdir(parents=True, exist_ok=True)
    CHART_PATH.write_text("\n".join(svg) + "\n", encoding="utf-8")
    print(f"Wrote {CHART_PATH.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    print("Running cross-backend benchmark...")
    results = collect_results()
    for name, t, _ in results:
        print(f"  {name:30s} {fmt_duration(t)}")
    render_chart(results)
