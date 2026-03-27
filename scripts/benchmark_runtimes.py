#!/usr/bin/env python3

from __future__ import annotations

import argparse
import statistics
import subprocess
import sys
import time
from pathlib import Path


def run_command(command: list[str], cwd: Path) -> tuple[str, float]:
    started = time.perf_counter()
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "benchmark command failed\n"
            f"command: {' '.join(command)}\n"
            f"cwd: {cwd}\n"
            f"stdout:\n{exc.stdout}\n"
            f"stderr:\n{exc.stderr}"
        ) from exc
    elapsed = time.perf_counter() - started
    return completed.stdout.strip(), elapsed


def benchmark_mode(
    name: str,
    command: list[str],
    cwd: Path,
    runs: int,
    warmups: int,
) -> dict[str, object]:
    for _ in range(warmups):
        run_command(command, cwd)

    outputs: list[str] = []
    samples: list[float] = []

    for _ in range(runs):
        output, elapsed = run_command(command, cwd)
        outputs.append(output)
        samples.append(elapsed)

    first_output = outputs[0]
    if any(output != first_output for output in outputs[1:]):
        raise RuntimeError(f"{name}: benchmark output changed across runs")

    return {
        "name": name,
        "output": first_output,
        "samples": samples,
        "median": statistics.median(samples),
        "mean": statistics.fmean(samples),
        "min": min(samples),
        "max": max(samples),
    }


def format_seconds(value: float) -> str:
    return f"{value:.4f}s"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Benchmark SageLang runtime paths on the same workload.",
    )
    parser.add_argument("--runs", type=int, default=5, help="timed runs per mode")
    parser.add_argument("--warmups", type=int, default=1, help="warmup runs per mode")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    sage_bin = repo_root / "sage"
    bench_file = repo_root / "benchmarks" / "runtime_compare.sage"

    if not sage_bin.exists():
        print("error: ./sage not found; build SageLang first", file=sys.stderr)
        return 1

    modes = [
        {
            "name": "c-ast",
            "cwd": repo_root,
            "command": [str(sage_bin), "--runtime", "ast", str(bench_file)],
        },
        {
            "name": "c-bytecode-vm",
            "cwd": repo_root,
            "command": [str(sage_bin), "--runtime", "bytecode", str(bench_file)],
        },
        {
            "name": "sage-selfhost",
            "cwd": repo_root / "src" / "sage",
            "command": [str(sage_bin), "sage.sage", str(bench_file)],
        },
        {
            "name": "sage-jit",
            "cwd": repo_root,
            "command": [str(sage_bin), "--jit", str(bench_file)],
        },
    ]

    results = [
        benchmark_mode(
            name=mode["name"],
            command=mode["command"],
            cwd=mode["cwd"],
            runs=args.runs,
            warmups=args.warmups,
        )
        for mode in modes
    ]

    expected_output = results[0]["output"]
    for result in results[1:]:
        if result["output"] != expected_output:
            raise RuntimeError(
                f"benchmark checksum mismatch: {results[0]['name']}={expected_output}, "
                f"{result['name']}={result['output']}"
            )

    baseline = results[0]["median"]

    print("SageLang runtime benchmark")
    print(f"workload: {bench_file.relative_to(repo_root)}")
    print(f"checksum: {expected_output}")
    print("")
    print("| Mode | Median | Mean | Min | Max | Relative to c-ast |")
    print("|------|--------|------|-----|-----|-------------------|")
    for result in results:
        relative = result["median"] / baseline if baseline else 0.0
        print(
            f"| {result['name']} | {format_seconds(result['median'])} | "
            f"{format_seconds(result['mean'])} | {format_seconds(result['min'])} | "
            f"{format_seconds(result['max'])} | {relative:.2f}x |"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
