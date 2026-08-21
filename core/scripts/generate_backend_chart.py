#!/usr/bin/env python3
"""Generate backend comparison chart from benchmark results."""

import subprocess
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHART_PATH = REPO_ROOT / "assets" / "charts" / "backend-compare.svg"
SAGE = REPO_ROOT / "sage"
BENCH = REPO_ROOT.parent / "testsuite" / "benchmarks" / "backend_compare.sage"


def run_timed(cmd: list[str], cwd: Path = REPO_ROOT) -> tuple[float, str, bool]:
    """Run a command and return (seconds, stdout, success)."""
    start = time.monotonic()
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=900, cwd=cwd)
        elapsed = time.monotonic() - start
        return elapsed, result.stdout, result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        elapsed = time.monotonic() - start
        return elapsed, "", False


def collect_results() -> list[tuple[str, float, str, str]]:
    """Collect benchmark results. Returns [(name, seconds, color, kind)] where kind is
    "exec" (backend executed the workload) or "emit" (codegen/emit throughput
    only — no execution)."""
    import shutil
    results = []
    tmp = Path("/tmp/sage_backend_bench")
    tmp.mkdir(exist_ok=True)

    # AST interpreter
    t, _, ok = run_timed([str(SAGE), str(BENCH)])
    if ok:
        results.append(("AST Interpreter", t, "#3A86FF", "exec"))

    # Bytecode VM
    t, _, ok = run_timed([str(SAGE), "--runtime", "bytecode", str(BENCH)])
    if ok:
        results.append(("Bytecode VM", t, "#14B8A6", "exec"))

    # C compiled (build + run)
    c_bin = tmp / "bench_c"
    build_t, _, ok = run_timed([str(SAGE), "--compile", str(BENCH), "-o", str(c_bin)])
    if ok:
        run_t, _, ok2 = run_timed([str(c_bin)])
        if ok2:
            results.append(("C Backend (run)", run_t, "#F97316", "exec"))
            results.append(("C Backend (total)", build_t + run_t, "#FB923C", "exec"))

    # LLVM compiled
    llvm_bin = tmp / "bench_llvm"
    build_t, _, ok = run_timed([str(SAGE), "--compile-llvm", str(BENCH), "-o", str(llvm_bin)])
    if ok:
        run_t, _, ok2 = run_timed([str(llvm_bin)])
        if ok2:
            results.append(("LLVM Backend (run)", run_t, "#A855F7", "exec"))
            results.append(("LLVM Backend (total)", build_t + run_t, "#C084FC", "exec"))

    # C compiled -O3
    c_o3 = tmp / "bench_c_o3"
    build_t, _, ok = run_timed([str(SAGE), "--compile", str(BENCH), "-o", str(c_o3), "-O3"])
    if ok:
        run_t, _, ok2 = run_timed([str(c_o3)])
        if ok2:
            results.append(("C -O3 (run)", run_t, "#EF4444", "exec"))

    # JIT profiled
    t, _, ok = run_timed([str(SAGE), "--jit", str(BENCH)])
    if ok:
        results.append(("JIT Profiled", t, "#F59E0B", "exec"))

    # AOT compiled
    aot_bin = tmp / "bench_aot"
    build_t, _, ok = run_timed([str(SAGE), "--aot", str(BENCH), "-o", str(aot_bin)])
    if ok:
        run_t, _, ok2 = run_timed([str(aot_bin)])
        if ok2:
            results.append(("AOT (run)", run_t, "#10B981", "exec"))

    # JIT+AOT (profile-guided)
    jitaot_bin = tmp / "bench_jitaot"
    build_t, _, ok = run_timed([str(SAGE), "--aot", "--jit", str(BENCH), "-o", str(jitaot_bin)])
    if ok:
        run_t, _, ok2 = run_timed([str(jitaot_bin)])
        if ok2:
            results.append(("JIT+AOT (run)", run_t, "#84CC16", "exec"))

    # Kotlin transpile (emit only)
    kt_out = tmp / "bench.kt"
    t, _, ok = run_timed([str(SAGE), "--emit-kotlin", str(BENCH), "-o", str(kt_out)])
    if ok:
        results.append(("Kotlin Transpile", t, "#7C3AED", "emit"))

    # Self-Hosted Sage
    t, _, ok = run_timed([str(SAGE), str(REPO_ROOT / "src" / "sage" / "sage.sage"), str(BENCH)])
    if ok:
        results.append(("Self-Hosted Sage", t, "#EC4899", "exec"))

    # VM image (.svm): compile to bytecode file, run via the file VM
    svm = tmp / "bench.svm"
    build_t, _, ok = run_timed([str(SAGE), "--emit-vm", str(BENCH), "-o", str(svm)])
    if ok:
        run_t, _, ok2 = run_timed([str(SAGE), "--run-vm", str(svm)])
        if ok2:
            results.append(("VM Image .svm (run)", run_t, "#22D3EE", "exec"))
            results.append(("VM Image .svm (total)", build_t + run_t, "#67E8F9", "exec"))

    # SGVM metal binary: build; attempt run (honest skip when unsupported)
    sgvm = tmp / "bench.sgvm"
    build_t, _, ok = run_timed([str(SAGE), "--sgvm", str(BENCH), "-o", str(sgvm)])
    if ok:
        run_t, _, ok2 = run_timed([str(SAGE), str(sgvm)])
        if ok2:
            results.append(("SGVM Metal (run)", run_t, "#F472B6", "exec"))

    # Native assembly backends — emit + assemble-to-object validation.
    # Hosted native linking needs a sage_rt runtime still landing in codegen.c,
    # so these are timed as codegen+assemble throughput, not execution.
    native_targets = [
        ("Native x86-64 asm", "x86-64", "cc"),
        ("Native aarch64 asm", "aarch64", "aarch64-linux-gnu-as"),
        ("Native rv64 asm", "rv64", "riscv64-linux-gnu-as"),
        ("Native mips asm", "mips", "mips-linux-gnu-as"),
    ]
    for label, target, assembler in native_targets:
        asm_f = tmp / f"bench_{target.replace('-', '_')}.s"
        t, _, ok = run_timed([str(SAGE), "--emit-asm", str(BENCH), "-o", str(asm_f),
                              "--target", target])
        if not ok:
            continue
        total = t
        if shutil.which(assembler):
            extra = ["cc", "-c", "-ffreestanding", "-fPIC", str(asm_f),
                     "-o", str(tmp / "o.o")] if assembler == "cc" else                     [assembler, str(asm_f), "-o", str(tmp / "o.o")]
            at, _, aok = run_timed(extra)
            if aok:
                total += at
        results.append((label, total, "#94A3B8", "emit"))

    # Bare-metal freestanding object (x86-64-baremetal profile)
    bare_obj = tmp / "bench_bare.o"
    t, _, ok = run_timed([str(SAGE), "--compile-bare", str(BENCH), "-o", str(bare_obj)])
    if ok:
        results.append(("Bare-metal x86-64 obj", t, "#64748B", "emit"))

    # Android project generation (transpile-only timing)
    and_out = tmp / "android"
    and_out.mkdir(exist_ok=True)
    t, _, ok = run_timed([str(SAGE), "--compile-android", str(BENCH), "-o", str(and_out)])
    if ok:
        results.append(("Android Project Gen", t, "#8B5CF6", "emit"))

    # Pico-C emit
    pico_c = tmp / "bench_pico.c"
    t, _, ok = run_timed([str(SAGE), "--emit-pico-c", str(BENCH), "-o", str(pico_c)])
    if ok:
        results.append(("Pico-C Emit", t, "#A3E635", "emit"))

    # Cleanup
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


def render_chart(results: list[tuple[str, float, str, str]]) -> None:
    from xml.sax.saxutils import escape
    from datetime import datetime, timezone

    if not results:
        print("No results to chart")
        return

    exec_results = [(n, v, c) for (n, v, c, k) in results if k == "exec"]
    emit_results = [(n, v, c) for (n, v, c, k) in results if k == "emit"]

    width = 1600
    margin_left = 280
    margin_right = 180
    margin_top = 135
    bar_height = 44
    bar_gap = 22
    section_gap = 78          # extra space between the two sections
    footer_padding = 130
    plot_width = width - margin_left - margin_right

    def section_height(entries):
        if not entries:
            return 0
        return len(entries) * bar_height + max(0, len(entries) - 1) * bar_gap

    exec_h = section_height(exec_results)
    emit_h = section_height(emit_results)
    height = margin_top + exec_h + (section_gap if exec_results and emit_results else 0) + emit_h + footer_padding

    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img">',
        "<title>SageLang Backend Performance Comparison</title>",
        "<defs>",
    ]

    for i, (_, _, color, _) in enumerate(results):
        start_c = adjust_color(color, 1.2)
        end_c = adjust_color(color, 0.82)
        svg.append(f'<linearGradient id="bg-{i}" x1="0%" y1="0%" x2="100%" y2="0%">')
        svg.append(f'<stop offset="0%" stop-color="{start_c}"/>')
        svg.append(f'<stop offset="100%" stop-color="{end_c}"/>')
        svg.append("</linearGradient>")
    # Diagonal hatch for emit-only bars so they can never be read as runtimes
    svg.extend([
        '<pattern id="hatch" width="10" height="10" patternTransform="rotate(45)" '
        'patternUnits="userSpaceOnUse">',
        '<rect width="10" height="10" fill="#131D2A"/>',
        '<line x1="0" y1="0" x2="0" y2="10" stroke="#94A3B8" stroke-width="3" opacity="0.55"/>',
        "</pattern>",
    ])

    svg.extend([
        "</defs>",
        '<rect width="100%" height="100%" fill="#0B1118"/>',
        f'<rect x="12" y="12" width="1576" height="{height - 24}" rx="18" fill="#0F1722" stroke="#1F2937"/>',
        '<text x="44" y="62" fill="#F8FAFC" font-size="34" font-family="Segoe UI, Arial, sans-serif" font-weight="700">SageLang Backend Performance Comparison</text>',
        '<text x="44" y="95" fill="#94A3B8" font-size="18" font-family="Segoe UI, Arial, sans-serif">benchmarks/backend_compare.sage — 12 workloads (num, str, bool, nil, arr, dict, tup, bytes)</text>',
    ])

    max_bar_ratio = 0.80
    row_index = 0
    cursor_y = margin_top

    def render_section(y0, entries, title, subtitle, hatched):
        nonlocal row_index
        parts = []
        parts.append(f'<text x="44" y="{y0 + 4:.1f}" fill="#F8FAFC" font-size="22" '
                     f'font-family="Segoe UI, Arial, sans-serif" font-weight="700">{escape(title)}</text>')
        parts.append(f'<text x="44" y="{y0 + 30:.1f}" fill="#94A3B8" font-size="15" '
                     f'font-family="Segoe UI, Arial, sans-serif">{escape(subtitle)}</text>')
        y = y0 + 46
        if not entries:
            svg.extend(parts)
            return y
        max_value = max(v for _, v, _ in entries)
        for (name, value, color) in entries:
            i = row_index
            row_index += 1
            bar_w = max(6.0, plot_width * (value / max_value) * max_bar_ratio)
            badge_w = max(92, min(260, 34 + len(name) * 9))
            badge_fill = adjust_color(color, 0.9)
            count_text = fmt_duration(value)
            count_x = margin_left + bar_w + 14
            if count_x > width - 240:
                count_x = margin_left + bar_w - 14
                anchor = "end"
                tfill = "#0F1722"
            else:
                anchor = "start"
                tfill = "#E2E8F0"
            fill_attr = 'fill="url(#hatch)"' if hatched else f'fill="url(#bg-{i})"'
            stroke_extra = ' stroke-dasharray="6 4"' if hatched else ""
            parts.extend([
                f'<rect x="30" y="{y + 6:.1f}" width="{badge_w}" height="32" rx="10" fill="{badge_fill}" opacity="{0.75 if hatched else 0.95}"/>',
                f'<text x="{30 + badge_w/2:.1f}" y="{y + 28:.1f}" text-anchor="middle" fill="#E2E8F0" '
                f'font-size="13" font-family="Segoe UI, Arial, sans-serif" font-weight="700">{escape(name.upper())}</text>',
                f'<rect x="{margin_left}" y="{y}" width="{plot_width}" height="{bar_height}" rx="12" fill="#131D2A" stroke="#233041"/>',
                f'<rect x="{margin_left}" y="{y}" width="{bar_w:.1f}" height="{bar_height}" rx="12" {fill_attr}{stroke_extra}/>',
                f'<text x="{count_x:.1f}" y="{y + 29:.1f}" text-anchor="{anchor}" fill="{tfill}" font-size="18" '
                f'font-family="Segoe UI, Arial, sans-serif" font-weight="700">{escape(count_text)}</text>',
            ])
            y += bar_height + bar_gap
        svg.extend(parts)
        return y

    cursor_y = render_section(
        cursor_y, exec_results,
        "Execution — workload runtime",
        "Backend executed all 12 workloads; lower is better. Self-Hosted runs the workload through the Sage-written interpreter under the C interpreter (double interpretation).",
        hatched=False)

    if exec_results and emit_results:
        cursor_y += section_gap - bar_gap

    render_section(
        cursor_y, emit_results,
        "Codegen / emit throughput — generation time only",
        "These backends did NOT execute the workload; bars measure compiler emission (+ assemble where a toolchain exists), hatched so they are never read as runtimes.",
        hatched=True)

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    footer_y = height - footer_padding + 44
    svg.append(f'<text x="44" y="{footer_y}" fill="#94A3B8" font-size="16" font-family="Segoe UI, Arial, sans-serif">'
               f'Lower is better within each section. Sections use independent scales. Last refreshed: {generated}</text>')
    svg.append("</svg>")

    CHART_PATH.parent.mkdir(parents=True, exist_ok=True)
    CHART_PATH.write_text("\n".join(svg) + "\n", encoding="utf-8")
    print(f"Wrote {CHART_PATH.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    print("Running cross-backend benchmark...")
    results = collect_results()
    for name, t, _, kind in results:
        tag = "exec" if kind == "exec" else "emit"
        print(f"  {name:30s} {fmt_duration(t):>10s}  [{tag}]")
    render_chart(results)
