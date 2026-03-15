#!/usr/bin/env python3
"""Generate repository metric and benchmark charts for the SageLang README."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable
from xml.sax.saxutils import escape

from benchmark_recipes import (
    RecipeResult,
    collect_recipe_results,
    mean_or_none as recipe_mean_or_none,
    median_or_none as recipe_median_or_none,
    recipe_label,
    validate_recipe_checksums,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
CHART_DIR = REPO_ROOT / "assets" / "charts"
METRICS_JSON = CHART_DIR / "loc-metrics.json"
REPO_CHART = CHART_DIR / "repo-loc.svg"
COMPILER_CHART = CHART_DIR / "compiler-loc.svg"
BENCHMARK_TOTAL_CHART = CHART_DIR / "benchmark-recipes-total.svg"
BENCHMARK_RUN_CHART = CHART_DIR / "benchmark-recipes-run.svg"

BENCHMARK_WORKLOAD = REPO_ROOT / "benchmarks" / "runtime_compare.sage"
BENCHMARK_RUNS = 5
BENCHMARK_WARMUPS = 1
BENCHMARK_CC = "cc"

EXCLUDED_PREFIXES = (
    "editors/vscode/node_modules/",
    "build/",
    "build_sage/",
    "obj/",
    "obj_asan/",
    ".tmp/",
    "output/",
)

LANGUAGE_COLORS = {
    "C": "#3A86FF",
    "Sage": "#F97316",
    "JSON": "#FACC15",
    "Makefile": "#A78BFA",
    "Shell": "#84CC16",
    "CMake": "#EF4444",
    "Dockerfile": "#38BDF8",
    "YAML": "#10B981",
    "JavaScript": "#F59E0B",
    "TypeScript": "#0EA5E9",
    "C++": "#EC4899",
}

LANGUAGE_BADGE_TEXT = {
    "JSON": "#111827",
}

RECIPE_COLORS = {
    "sage-interpreted-c-ast": "#3A86FF",
    "sage-interpreted-vm": "#14B8A6",
    "sage-compiled-c": "#F97316",
    "sage-compiled-vm": "#94A3B8",
    "sage-compiled-sage": "#FACC15",
    "placeholder": "#64748B",
}

RECIPE_BADGES = {
    "sage-interpreted-c-ast": "AST",
    "sage-interpreted-vm": "VM",
    "sage-compiled-c": "C BIN",
    "sage-compiled-vm": "VM BIN",
    "sage-compiled-sage": "SAGE BIN",
    "placeholder": "N/A",
}


@dataclass
class Bar:
    label: str
    value: float
    color: str
    detail: str
    badge_label: str | None = None


def run_git_ls_files() -> list[str]:
    output = subprocess.check_output(
        ["git", "ls-files"],
        cwd=REPO_ROOT,
        text=True,
    )
    return [line for line in output.splitlines() if line]


def count_non_empty_lines(path: Path) -> int:
    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        return sum(1 for line in handle if line.strip())


def detect_language(path_str: str) -> str | None:
    path = Path(path_str)
    name = path.name
    ext = path.suffix.lower()

    if name.startswith("Dockerfile"):
        return "Dockerfile"
    if name == "CMakeLists.txt" or ext == ".cmake":
        return "CMake"
    if name == "Makefile" or name.endswith(".mk"):
        return "Makefile"
    if ext == ".sage":
        return "Sage"
    if ext in {".c", ".h"}:
        return "C"
    if ext in {".cpp", ".cc", ".cxx", ".hpp", ".hh", ".hxx"}:
        return "C++"
    if ext == ".json":
        return "JSON"
    if ext in {".yml", ".yaml"}:
        return "YAML"
    if ext in {".sh", ".bash"}:
        return "Shell"
    if ext == ".js":
        return "JavaScript"
    if ext == ".ts":
        return "TypeScript"
    return None


def authored_files() -> Iterable[str]:
    for path_str in run_git_ls_files():
        if any(path_str.startswith(prefix) for prefix in EXCLUDED_PREFIXES):
            continue
        yield path_str


def collect_repo_language_counts() -> list[tuple[str, int]]:
    counts: dict[str, int] = {}
    for path_str in authored_files():
        language = detect_language(path_str)
        if language is None:
            continue
        counts[language] = counts.get(language, 0) + count_non_empty_lines(REPO_ROOT / path_str)
    return sorted(counts.items(), key=lambda item: item[1], reverse=True)


def collect_compiler_counts() -> list[tuple[str, int]]:
    self_hosted = 0
    native_c = 0

    for path_str in run_git_ls_files():
        path = REPO_ROOT / path_str
        if path_str.startswith("src/sage/") and path.suffix == ".sage" and not path_str.startswith("src/sage/test/"):
            self_hosted += count_non_empty_lines(path)
        elif (path_str.startswith("src/c/") and path.suffix == ".c") or (
            path_str.startswith("include/") and path.suffix == ".h"
        ):
            native_c += count_non_empty_lines(path)

    return [
        ("Self-Hosted Sage Core", self_hosted),
        ("Native C Core", native_c),
    ]


def fmt_count(value: float) -> str:
    rounded = int(round(value))
    if rounded >= 1_000_000:
        return f"{rounded / 1_000_000:.1f}M"
    if rounded >= 1_000:
        return f"{rounded / 1_000:.1f}K"
    return str(rounded)


def fmt_duration(value: float) -> str:
    if value >= 1.0:
        return f"{value:.2f}s"
    millis = value * 1000.0
    if millis >= 100:
        return f"{millis:.0f}ms"
    if millis >= 10:
        return f"{millis:.1f}ms"
    return f"{millis:.2f}ms"


def hex_to_rgb(color: str) -> tuple[int, int, int]:
    color = color.lstrip("#")
    return tuple(int(color[index:index + 2], 16) for index in (0, 2, 4))


def adjust_color(color: str, factor: float) -> str:
    channels = []
    for channel in hex_to_rgb(color):
        if factor >= 1.0:
            adjusted = channel + (255 - channel) * (factor - 1.0)
        else:
            adjusted = channel * factor
        channels.append(max(0, min(255, int(round(adjusted)))))
    return "#{:02X}{:02X}{:02X}".format(*channels)


def render_horizontal_chart(
    title: str,
    subtitle: str,
    bars: list[Bar],
    output_path: Path,
    footer_lines: list[str] | None = None,
    value_formatter: Callable[[float], str] = fmt_count,
) -> None:
    if not bars:
        raise ValueError("Cannot render a chart without data")

    width = 1600
    margin_left = 240
    margin_right = 180
    margin_top = 135
    bar_height = 44
    bar_gap = 22
    footer_padding = 80 + max(0, (len(footer_lines or []) - 1) * 24)
    plot_width = width - margin_left - margin_right
    plot_height = len(bars) * bar_height + max(0, len(bars) - 1) * bar_gap
    height = margin_top + plot_height + footer_padding
    max_value = max(bar.value for bar in bars)
    total = sum(bar.value for bar in bars)

    svg: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
        f"<title>{escape(title)}</title>",
        f"<desc>{escape(subtitle)}</desc>",
        "<defs>",
    ]

    for index, bar in enumerate(bars):
        start = adjust_color(bar.color, 1.2)
        end = adjust_color(bar.color, 0.82)
        svg.extend(
            [
                f'<linearGradient id="bar-gradient-{index}" x1="0%" y1="0%" x2="100%" y2="0%">',
                f'<stop offset="0%" stop-color="{start}"/>',
                f'<stop offset="100%" stop-color="{end}"/>',
                "</linearGradient>",
            ]
        )

    svg.extend(
        [
            "</defs>",
            '<rect width="100%" height="100%" fill="#0B1118"/>',
            '<rect x="12" y="12" width="1576" height="{}" rx="18" fill="#0F1722" stroke="#1F2937"/>'.format(height - 24),
            f'<text x="44" y="62" fill="#F8FAFC" font-size="34" font-family="Segoe UI, Arial, sans-serif" font-weight="700">{escape(title)}</text>',
            f'<text x="44" y="95" fill="#94A3B8" font-size="18" font-family="Segoe UI, Arial, sans-serif">{escape(subtitle)}</text>',
        ]
    )

    grid_steps = 5
    for step in range(grid_steps + 1):
        ratio = step / grid_steps
        x = margin_left + plot_width * ratio
        value_label = value_formatter(max_value * ratio)
        svg.append(
            f'<line x1="{x:.1f}" y1="{margin_top - 20}" x2="{x:.1f}" y2="{margin_top + plot_height + 6}" '
            'stroke="#182231" stroke-width="1"/>'
        )
        svg.append(
            f'<text x="{x:.1f}" y="{margin_top + plot_height + 32}" text-anchor="middle" fill="#64748B" '
            'font-size="15" font-family="Segoe UI, Arial, sans-serif">'
            f"{escape(value_label)}</text>"
        )

    for index, bar in enumerate(bars):
        y = margin_top + index * (bar_height + bar_gap)
        badge_y = y + 6
        bar_width = plot_width * (bar.value / max_value if max_value else 0)
        badge = (bar.badge_label or bar.label).upper()
        badge_width = max(92, min(220, 34 + len(badge) * 10))
        badge_fill = adjust_color(bar.color, 0.9)
        badge_text = LANGUAGE_BADGE_TEXT.get(bar.label, "#E2E8F0")
        count_text = value_formatter(bar.value)
        share_text = f"{(bar.value / total) * 100:.1f}%" if total else "0.0%"

        svg.extend(
            [
                f'<rect x="30" y="{badge_y:.1f}" width="{badge_width}" height="32" rx="10" fill="{badge_fill}" opacity="0.95"/>',
                f'<text x="{30 + badge_width / 2:.1f}" y="{badge_y + 22:.1f}" text-anchor="middle" fill="{badge_text}" '
                'font-size="14" font-family="Segoe UI, Arial, sans-serif" font-weight="700" letter-spacing="1.1">'
                f"{escape(badge)}</text>",
                f'<rect x="{margin_left}" y="{y}" width="{plot_width}" height="{bar_height}" rx="12" fill="#131D2A" stroke="#233041"/>',
                f'<rect x="{margin_left}" y="{y}" width="{bar_width:.1f}" height="{bar_height}" rx="12" fill="url(#bar-gradient-{index})"/>',
                f'<line x1="{margin_left + 2:.1f}" y1="{y + 2:.1f}" x2="{margin_left + max(2, bar_width - 2):.1f}" y2="{y + 2:.1f}" stroke="#F8FAFC" stroke-opacity="0.18"/>',
                f'<text x="{margin_left + bar_width + 14:.1f}" y="{y + 29:.1f}" fill="#E2E8F0" font-size="18" '
                'font-family="Segoe UI, Arial, sans-serif" font-weight="700">'
                f"{escape(count_text)}</text>",
                f'<text x="{width - 44}" y="{y + 29:.1f}" text-anchor="end" fill="#64748B" font-size="15" '
                'font-family="Segoe UI, Arial, sans-serif">'
                f"{escape(share_text)} · {escape(bar.detail)}</text>",
            ]
        )

    if footer_lines:
        footer_y = margin_top + plot_height + 58
        for index, line in enumerate(footer_lines):
            svg.append(
                f'<text x="44" y="{footer_y + index * 24}" fill="#94A3B8" font-size="16" '
                'font-family="Segoe UI, Arial, sans-serif">'
                f"{escape(line)}</text>"
            )

    svg.append("</svg>")
    output_path.write_text("\n".join(svg) + "\n", encoding="utf-8")


def build_repo_bars(language_counts: list[tuple[str, int]]) -> list[Bar]:
    total = sum(count for _, count in language_counts)
    bars = []
    for language, count in language_counts:
        color = LANGUAGE_COLORS.get(language, "#94A3B8")
        detail = f"{count:,} non-empty lines"
        if total:
            detail = f"{count:,} of {total:,} lines"
        bars.append(Bar(language, count, color, detail))
    return bars


def build_compiler_bars(compiler_counts: list[tuple[str, int]]) -> list[Bar]:
    labels = {
        "Self-Hosted Sage Core": "#F97316",
        "Native C Core": "#3A86FF",
    }
    details = {
        "Self-Hosted Sage Core": "src/sage/*.sage (excluding src/sage/test)",
        "Native C Core": "src/c/*.c plus include/*.h",
    }
    return [
        Bar(label, count, labels[label], details[label])
        for label, count in compiler_counts
    ]


def summarize_benchmark_issue(result: RecipeResult, expected_output: str | None) -> str:
    label = recipe_label(result.name)
    if result.status == "unsupported":
        return f"{label}: no ahead-of-time VM compile target exists yet."
    if result.reason.startswith("checksum mismatch:"):
        expected = expected_output if expected_output is not None else "the baseline"
        return f"{label}: checksum validation failed against {expected}."
    if result.reason.startswith("build step failed\n") or result.reason.startswith("compiled program failed\n"):
        if "stderr:\n" in result.reason:
            detail = result.reason.split("stderr:\n", 1)[1].splitlines()[0].strip()
            if detail:
                return f"{label}: {detail}"
        if "stdout:\n" in result.reason:
            detail = result.reason.split("stdout:\n", 1)[1].splitlines()[0].strip()
            if detail:
                return f"{label}: {detail}"
        return f"{label}: build or execution failed."
    return f"{label}: {result.reason}"


def build_benchmark_bars(results: list[RecipeResult], metric: str) -> list[Bar]:
    valid_results = [result for result in results if result.status == "ok"]
    if not valid_results:
        return [
            Bar(
                label="Unavailable",
                value=1.0,
                color=RECIPE_COLORS["placeholder"],
                detail="Benchmark data unavailable",
                badge_label=RECIPE_BADGES["placeholder"],
            )
        ]

    baseline_result = next((result for result in valid_results if result.name == "sage-interpreted-c-ast"), valid_results[0])
    baseline_samples = baseline_result.total_samples if metric == "total" else baseline_result.run_samples
    baseline_value = recipe_median_or_none(baseline_samples) or 1.0

    bars: list[Bar] = []
    for result in valid_results:
        samples = result.total_samples if metric == "total" else result.run_samples
        value = recipe_median_or_none(samples)
        if value is None:
            continue
        relative = value / baseline_value if baseline_value else 0.0
        metric_text = "build + run" if metric == "total" else "execution only"
        bars.append(
            Bar(
                label=recipe_label(result.name),
                value=value,
                color=RECIPE_COLORS.get(result.name, RECIPE_COLORS["placeholder"]),
                detail=f"{recipe_label(result.name)} · {metric_text} · {relative:.2f}x vs AST",
                badge_label=RECIPE_BADGES.get(result.name),
            )
        )

    return bars


def serialize_benchmark_results(results: list[RecipeResult]) -> list[dict[str, object]]:
    payload = []
    for result in results:
        payload.append(
            {
                "name": result.name,
                "label": recipe_label(result.name),
                "status": result.status,
                "reason": result.reason,
                "output": result.output,
                "build_median_seconds": recipe_median_or_none(result.build_samples),
                "run_median_seconds": recipe_median_or_none(result.run_samples),
                "total_median_seconds": recipe_median_or_none(result.total_samples),
                "build_mean_seconds": recipe_mean_or_none(result.build_samples),
                "run_mean_seconds": recipe_mean_or_none(result.run_samples),
                "total_mean_seconds": recipe_mean_or_none(result.total_samples),
            }
        )
    return payload


def write_metrics_json(
    generated_at: str,
    repo_counts: list[tuple[str, int]],
    compiler_counts: list[tuple[str, int]],
    benchmark_results: list[RecipeResult],
    benchmark_checksum: str | None,
) -> None:
    payload = {
        "generated_at": generated_at,
        "repo_languages": [{"language": language, "lines": count} for language, count in repo_counts],
        "compiler_comparison": [{"label": label, "lines": count} for label, count in compiler_counts],
        "recipe_benchmark": {
            "workload": str(BENCHMARK_WORKLOAD.relative_to(REPO_ROOT)),
            "runs": BENCHMARK_RUNS,
            "warmups": BENCHMARK_WARMUPS,
            "checksum": benchmark_checksum,
            "results": serialize_benchmark_results(benchmark_results),
        },
    }
    METRICS_JSON.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    CHART_DIR.mkdir(parents=True, exist_ok=True)

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    repo_counts = collect_repo_language_counts()
    compiler_counts = collect_compiler_counts()
    benchmark_results = collect_recipe_results(
        REPO_ROOT,
        BENCHMARK_WORKLOAD,
        BENCHMARK_RUNS,
        BENCHMARK_WARMUPS,
        BENCHMARK_CC,
    )
    benchmark_checksum = validate_recipe_checksums(benchmark_results)

    repo_bars = build_repo_bars(repo_counts)
    compiler_bars = build_compiler_bars(compiler_counts)
    benchmark_total_bars = build_benchmark_bars(benchmark_results, "total")
    benchmark_run_bars = build_benchmark_bars(benchmark_results, "run")

    compiler_delta = compiler_counts[1][1] - compiler_counts[0][1]
    ratio = compiler_counts[0][1] / compiler_counts[1][1] if compiler_counts[1][1] else 0.0

    issue_lines = [summarize_benchmark_issue(result, benchmark_checksum) for result in benchmark_results if result.status != "ok"]
    benchmark_footer = [
        f"Settings: {BENCHMARK_RUNS} timed runs, {BENCHMARK_WARMUPS} warmup on {BENCHMARK_WORKLOAD.relative_to(REPO_ROOT)}.",
        "Totals include compile + link + execution; the run chart isolates execution-only cost.",
    ]
    if benchmark_checksum is not None:
        benchmark_footer.append(f"Checksum target: {benchmark_checksum}.")
    benchmark_footer.extend(issue_lines)
    benchmark_footer.append(f"Last refreshed: {generated_at}")

    render_horizontal_chart(
        title="SageLang Repository LOC by Language",
        subtitle="Authored, non-empty tracked lines. Vendored dependencies and build artifacts are excluded.",
        bars=repo_bars,
        output_path=REPO_CHART,
        footer_lines=[f"Last refreshed: {generated_at}"],
        value_formatter=fmt_count,
    )

    render_horizontal_chart(
        title="Compiler Core LOC: Self-Hosted Sage vs Native C",
        subtitle="Core implementation comparison for the two compiler/interpreter codepaths.",
        bars=compiler_bars,
        output_path=COMPILER_CHART,
        footer_lines=[
            f"Native C leads by {fmt_count(abs(compiler_delta))} non-empty lines.",
            f"Self-hosted Sage is {ratio:.1%} of the native C core today.",
            f"Last refreshed: {generated_at}",
        ],
        value_formatter=fmt_count,
    )

    render_horizontal_chart(
        title="Recipe Benchmark: Total Median Time",
        subtitle="End-to-end wall time for the default workload. Compiled recipes include code generation, host C compile, and execution.",
        bars=benchmark_total_bars,
        output_path=BENCHMARK_TOTAL_CHART,
        footer_lines=benchmark_footer,
        value_formatter=fmt_duration,
    )

    render_horizontal_chart(
        title="Recipe Benchmark: Execution-Only Median Time",
        subtitle="Steady-state runtime on the default workload for recipes that passed checksum validation.",
        bars=benchmark_run_bars,
        output_path=BENCHMARK_RUN_CHART,
        footer_lines=benchmark_footer,
        value_formatter=fmt_duration,
    )

    write_metrics_json(generated_at, repo_counts, compiler_counts, benchmark_results, benchmark_checksum)
    print(f"Wrote {REPO_CHART.relative_to(REPO_ROOT)}")
    print(f"Wrote {COMPILER_CHART.relative_to(REPO_ROOT)}")
    print(f"Wrote {BENCHMARK_TOTAL_CHART.relative_to(REPO_ROOT)}")
    print(f"Wrote {BENCHMARK_RUN_CHART.relative_to(REPO_ROOT)}")
    print(f"Wrote {METRICS_JSON.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
