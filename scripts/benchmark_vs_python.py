#!/usr/bin/env python3
"""
Benchmark Sage implementations against Python 3.x

Runs each benchmark across:
  1. Python 3.x (CPython)
  2. Sage AST interpreter
  3. Sage bytecode VM
  4. Sage compiled (C backend)
  5. Sage compiled (LLVM backend)

Produces a markdown table and optional SVG chart.
"""

from __future__ import annotations

import argparse
import os
import statistics
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAGE = ROOT / "sage"
BENCHMARKS = ROOT / "benchmarks"

RECIPES = [
    ("Python 3", "python"),
    ("Sage AST", "sage-ast"),
    ("Sage VM", "sage-vm"),
    ("Sage C", "sage-c"),
    ("Sage LLVM", "sage-llvm"),
]


@dataclass
class RunResult:
    name: str
    recipe: str
    times: list[float] = field(default_factory=list)
    output: str = ""
    status: str = "ok"
    error: str = ""

    @property
    def median(self) -> float:
        return statistics.median(self.times) if self.times else 0.0

    @property
    def stdev(self) -> float:
        return statistics.stdev(self.times) if len(self.times) > 1 else 0.0


def run_timed(cmd: list[str], cwd: Path, timeout: int = 60) -> tuple[float, str, int]:
    start = time.perf_counter()
    try:
        result = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
        elapsed = time.perf_counter() - start
        return elapsed, result.stdout.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return timeout, "", -1
    except FileNotFoundError:
        return 0.0, "", -2


def detect_python() -> str:
    for name in ["python3", "python"]:
        try:
            result = subprocess.run(
                [name, "--version"], capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and "Python 3" in result.stdout:
                return name
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    return ""


def run_benchmark(
    bench_sage: Path,
    bench_py: Path,
    recipe: str,
    runs: int,
    warmups: int,
    python_cmd: str,
) -> RunResult:
    name = bench_sage.stem
    result = RunResult(name=name, recipe=recipe)

    if recipe == "python":
        if not bench_py.exists():
            result.status = "skip"
            result.error = "No Python file"
            return result
        if not python_cmd:
            result.status = "skip"
            result.error = "Python 3 not found"
            return result
        cmd = [python_cmd, str(bench_py)]
    elif recipe == "sage-ast":
        cmd = [str(SAGE), "--runtime", "ast", str(bench_sage)]
    elif recipe == "sage-vm":
        cmd = [str(SAGE), "--runtime", "bytecode", str(bench_sage)]
    elif recipe == "sage-c":
        with tempfile.NamedTemporaryFile(suffix="", delete=False) as f:
            out_path = f.name
        try:
            build = subprocess.run(
                [str(SAGE), "--compile", str(bench_sage), "-o", out_path],
                capture_output=True, text=True, timeout=30,
            )
            if build.returncode != 0:
                result.status = "fail"
                result.error = f"Compile failed: {build.stderr.strip()[:200]}"
                return result
            cmd = [out_path]
        except (subprocess.TimeoutExpired, FileNotFoundError):
            result.status = "fail"
            result.error = "Compile timeout or sage not found"
            return result
    elif recipe == "sage-llvm":
        with tempfile.NamedTemporaryFile(suffix="", delete=False) as f:
            out_path = f.name
        try:
            build = subprocess.run(
                [str(SAGE), "--compile-llvm", str(bench_sage), "-o", out_path],
                capture_output=True, text=True, timeout=30,
            )
            if build.returncode != 0:
                result.status = "fail"
                result.error = f"LLVM compile failed: {build.stderr.strip()[:200]}"
                return result
            cmd = [out_path]
        except (subprocess.TimeoutExpired, FileNotFoundError):
            result.status = "fail"
            result.error = "LLVM compile timeout or sage not found"
            return result
    else:
        result.status = "skip"
        result.error = f"Unknown recipe: {recipe}"
        return result

    # Warmup runs
    for _ in range(warmups):
        elapsed, output, rc = run_timed(cmd, ROOT)
        if rc != 0 and rc != -1:
            result.status = "fail"
            result.error = f"Warmup failed (rc={rc})"
            return result

    # Timed runs
    for _ in range(runs):
        elapsed, output, rc = run_timed(cmd, ROOT)
        if rc == -1:
            result.status = "timeout"
            result.error = "Timed out"
            return result
        if rc != 0:
            result.status = "fail"
            result.error = f"Run failed (rc={rc})"
            return result
        result.times.append(elapsed)
        result.output = output

    # Cleanup temp files for compiled recipes
    if recipe in ("sage-c", "sage-llvm"):
        try:
            os.unlink(out_path)
        except OSError:
            pass

    return result


def format_time(seconds: float) -> str:
    if seconds < 0.001:
        return f"{seconds * 1_000_000:.0f}us"
    if seconds < 1.0:
        return f"{seconds * 1000:.1f}ms"
    return f"{seconds:.3f}s"


def main():
    parser = argparse.ArgumentParser(description="Benchmark Sage vs Python 3")
    parser.add_argument("--runs", type=int, default=5, help="Timed runs per benchmark")
    parser.add_argument("--warmups", type=int, default=1, help="Warmup runs")
    parser.add_argument("--filter", type=str, default="", help="Filter benchmarks by name substring")
    parser.add_argument("--recipes", type=str, default="", help="Comma-separated recipe filter")
    parser.add_argument("--markdown", action="store_true", help="Output markdown table")
    args = parser.parse_args()

    python_cmd = detect_python()
    if python_cmd:
        py_version = subprocess.run(
            [python_cmd, "--version"], capture_output=True, text=True
        ).stdout.strip()
        print(f"Python: {py_version}")
    else:
        print("Python 3: not found (skipping Python benchmarks)")

    print(f"Sage: {SAGE}")
    print(f"Runs: {args.runs}, Warmups: {args.warmups}")
    print()

    # Discover benchmarks
    sage_files = sorted(BENCHMARKS.glob("[0-9]*.sage"))
    if args.filter:
        sage_files = [f for f in sage_files if args.filter in f.stem]

    if not sage_files:
        print("No benchmark files found.")
        return

    active_recipes = RECIPES
    if args.recipes:
        recipe_filter = set(args.recipes.split(","))
        active_recipes = [(label, key) for label, key in RECIPES if key in recipe_filter]

    # Collect results
    all_results: dict[str, list[RunResult]] = {}

    for sage_file in sage_files:
        bench_name = sage_file.stem
        py_file = sage_file.with_suffix(".py")
        all_results[bench_name] = []

        for label, recipe_key in active_recipes:
            result = run_benchmark(
                sage_file, py_file, recipe_key, args.runs, args.warmups, python_cmd
            )
            all_results[bench_name].append(result)

    # Print results
    header_labels = [label for label, _ in active_recipes]

    if args.markdown:
        # Markdown table
        header = "| Benchmark | " + " | ".join(header_labels) + " |"
        sep = "|" + "|".join(["---"] * (len(header_labels) + 1)) + "|"
        print(header)
        print(sep)
        for bench_name, results in all_results.items():
            cells = []
            for r in results:
                if r.status == "ok":
                    cells.append(format_time(r.median))
                elif r.status == "skip":
                    cells.append("skip")
                elif r.status == "timeout":
                    cells.append("timeout")
                else:
                    cells.append(f"FAIL")
            print(f"| {bench_name} | " + " | ".join(cells) + " |")
    else:
        # Console table
        col_width = 14
        name_width = 24
        print(f"{'Benchmark':<{name_width}}", end="")
        for label in header_labels:
            print(f"{label:>{col_width}}", end="")
        print()
        print("-" * (name_width + col_width * len(header_labels)))

        for bench_name, results in all_results.items():
            print(f"{bench_name:<{name_width}}", end="")
            for r in results:
                if r.status == "ok":
                    cell = format_time(r.median)
                elif r.status == "skip":
                    cell = "skip"
                elif r.status == "timeout":
                    cell = "timeout"
                else:
                    cell = "FAIL"
                print(f"{cell:>{col_width}}", end="")
            print()

    # Verify correctness: all non-skip results should produce the same output
    print()
    print("Correctness check:")
    all_correct = True
    for bench_name, results in all_results.items():
        outputs = set()
        for r in results:
            if r.status == "ok" and r.output:
                outputs.add(r.output)
        if len(outputs) > 1:
            print(f"  MISMATCH: {bench_name} — {len(outputs)} distinct outputs")
            for r in results:
                if r.status == "ok":
                    print(f"    {r.recipe}: {r.output[:80]}")
            all_correct = False
    if all_correct:
        print("  All outputs match across implementations.")


if __name__ == "__main__":
    main()
