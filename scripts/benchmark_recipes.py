#!/usr/bin/env python3

from __future__ import annotations

import argparse
import statistics
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

RECIPE_LABELS = {
    "sage-interpreted-c-ast": "Interpreted (C + AST)",
    "sage-interpreted-vm": "Interpreted (VM)",
    "sage-compiled-c": "Compiled (C)",
    "sage-compiled-vm": "Compiled (VM)",
    "sage-compiled-sage": "Compiled (Sage)",
}


@dataclass
class CommandResult:
    returncode: int
    stdout: str
    stderr: str
    elapsed: float

    @property
    def combined_output(self) -> str:
        output = []
        if self.stdout.strip():
            output.append(f"stdout:\n{self.stdout.strip()}")
        if self.stderr.strip():
            output.append(f"stderr:\n{self.stderr.strip()}")
        return "\n".join(output) if output else "(no output)"


@dataclass
class RecipeResult:
    name: str
    status: str
    reason: str = ""
    output: str | None = None
    build_samples: list[float] | None = None
    run_samples: list[float] | None = None
    total_samples: list[float] | None = None


def recipe_label(name: str) -> str:
    return RECIPE_LABELS.get(name, name)


def run_process(command: list[str], cwd: Path) -> CommandResult:
    started = time.perf_counter()
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
    )
    return CommandResult(
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
        elapsed=time.perf_counter() - started,
    )


def benchmark_interpreted_recipe(
    name: str,
    command: list[str],
    cwd: Path,
    runs: int,
    warmups: int,
) -> RecipeResult:
    for _ in range(warmups):
        warmup = run_process(command, cwd)
        if warmup.returncode != 0:
            return RecipeResult(
                name=name,
                status="failed",
                reason=(
                    "warmup run failed\n"
                    f"command: {' '.join(command)}\n"
                    f"cwd: {cwd}\n"
                    f"{warmup.combined_output}"
                ),
            )

    outputs: list[str] = []
    run_samples: list[float] = []
    total_samples: list[float] = []

    for _ in range(runs):
        result = run_process(command, cwd)
        if result.returncode != 0:
            return RecipeResult(
                name=name,
                status="failed",
                reason=(
                    "timed run failed\n"
                    f"command: {' '.join(command)}\n"
                    f"cwd: {cwd}\n"
                    f"{result.combined_output}"
                ),
            )
        outputs.append(result.stdout.strip())
        run_samples.append(result.elapsed)
        total_samples.append(result.elapsed)

    first_output = outputs[0]
    if any(output != first_output for output in outputs[1:]):
        return RecipeResult(
            name=name,
            status="failed",
            reason="benchmark output changed across interpreted runs",
        )

    return RecipeResult(
        name=name,
        status="ok",
        output=first_output,
        build_samples=[0.0] * runs,
        run_samples=run_samples,
        total_samples=total_samples,
    )


def benchmark_compiled_recipe(
    name: str,
    repo_root: Path,
    build_steps: list[tuple[list[str], Path]],
    run_command: list[str],
    run_cwd: Path,
    runs: int,
    warmups: int,
) -> RecipeResult:
    outputs: list[str] = []
    build_samples: list[float] = []
    run_samples: list[float] = []
    total_samples: list[float] = []

    for index in range(warmups + runs):
        with tempfile.TemporaryDirectory(prefix=f"{name}-", dir=repo_root / ".tmp") as tmpdir_name:
            tmpdir = Path(tmpdir_name)
            resolved_build_steps = [
                ([part.replace("{tmpdir}", str(tmpdir)) for part in command], cwd)
                for command, cwd in build_steps
            ]
            resolved_run_command = [part.replace("{tmpdir}", str(tmpdir)) for part in run_command]

            build_elapsed = 0.0
            for command, cwd in resolved_build_steps:
                result = run_process(command, cwd)
                build_elapsed += result.elapsed
                if result.returncode != 0:
                    return RecipeResult(
                        name=name,
                        status="failed",
                        reason=(
                            "build step failed\n"
                            f"command: {' '.join(command)}\n"
                            f"cwd: {cwd}\n"
                            f"{result.combined_output}"
                        ),
                    )

            run_result = run_process(resolved_run_command, run_cwd)
            if run_result.returncode != 0:
                return RecipeResult(
                    name=name,
                    status="failed",
                    reason=(
                        "compiled program failed\n"
                        f"command: {' '.join(resolved_run_command)}\n"
                        f"cwd: {run_cwd}\n"
                        f"{run_result.combined_output}"
                    ),
                )

            if index < warmups:
                continue

            outputs.append(run_result.stdout.strip())
            build_samples.append(build_elapsed)
            run_samples.append(run_result.elapsed)
            total_samples.append(build_elapsed + run_result.elapsed)

    first_output = outputs[0]
    if any(output != first_output for output in outputs[1:]):
        return RecipeResult(
            name=name,
            status="failed",
            reason="benchmark output changed across compiled runs",
        )

    return RecipeResult(
        name=name,
        status="ok",
        output=first_output,
        build_samples=build_samples,
        run_samples=run_samples,
        total_samples=total_samples,
    )


def format_seconds(value: float | None) -> str:
    if value is None:
        return "n/a"
    return f"{value:.4f}s"


def median_or_none(values: list[float] | None) -> float | None:
    if not values:
        return None
    return statistics.median(values)


def mean_or_none(values: list[float] | None) -> float | None:
    if not values:
        return None
    return statistics.fmean(values)


def collect_recipe_results(
    repo_root: Path,
    workload: Path,
    runs: int,
    warmups: int,
    cc: str,
) -> list[RecipeResult]:
    sage_bin = repo_root / "sage"
    if not sage_bin.exists():
        raise SystemExit("error: ./sage not found; build SageLang first")
    if not workload.exists():
        raise SystemExit(f"error: workload not found: {workload}")

    (repo_root / ".tmp").mkdir(exist_ok=True)

    return [
        benchmark_interpreted_recipe(
            name="sage-interpreted-c-ast",
            command=[str(sage_bin), "--runtime", "ast", str(workload)],
            cwd=repo_root,
            runs=runs,
            warmups=warmups,
        ),
        benchmark_interpreted_recipe(
            name="sage-interpreted-vm",
            command=[str(sage_bin), "--runtime", "bytecode", str(workload)],
            cwd=repo_root,
            runs=runs,
            warmups=warmups,
        ),
        benchmark_compiled_recipe(
            name="sage-compiled-c",
            repo_root=repo_root,
            build_steps=[
                (
                    [
                        str(sage_bin),
                        "--compile",
                        str(workload),
                        "-o",
                        "{tmpdir}/recipe-compiled-c",
                    ],
                    repo_root,
                ),
            ],
            run_command=["{tmpdir}/recipe-compiled-c"],
            run_cwd=repo_root,
            runs=runs,
            warmups=warmups,
        ),
        RecipeResult(
            name="sage-compiled-vm",
            status="unsupported",
            reason=(
                "the current CLI exposes the VM only as a runtime backend "
                "(`sage --runtime bytecode` or `--runtime vm`), not as an ahead-of-time "
                "compile target or bytecode artifact format"
            ),
        ),
        benchmark_compiled_recipe(
            name="sage-compiled-sage",
            repo_root=repo_root,
            build_steps=[
                (
                    [
                        str(sage_bin),
                        "sage.sage",
                        "--emit-c",
                        str(workload),
                        "-o",
                        "{tmpdir}/recipe-compiled-sage.c",
                    ],
                    repo_root / "src" / "sage",
                ),
                (
                    [
                        cc,
                        "{tmpdir}/recipe-compiled-sage.c",
                        "-o",
                        "{tmpdir}/recipe-compiled-sage",
                        "-lm",
                    ],
                    repo_root,
                ),
            ],
            run_command=["{tmpdir}/recipe-compiled-sage"],
            run_cwd=repo_root,
            runs=runs,
            warmups=warmups,
        ),
    ]


def validate_recipe_checksums(results: list[RecipeResult]) -> str | None:
    expected_output = results[0].output if results and results[0].status == "ok" else None
    if expected_output is None:
        return None

    for result in results[1:]:
        if result.status != "ok":
            continue
        if result.output != expected_output:
            result.status = "failed"
            result.reason = f"checksum mismatch: expected {expected_output!r}, got {result.output!r}"

    return expected_output


def print_recipe_benchmark(
    results: list[RecipeResult],
    repo_root: Path,
    workload: Path,
    expected_output: str | None,
) -> None:
    baseline_total = median_or_none(results[0].total_samples if results else None)

    print("SageLang recipe benchmark")
    print(f"workload: {workload.relative_to(repo_root)}")
    if expected_output is not None:
        print(f"checksum: {expected_output}")
    print("")
    print("| Recipe | Status | Build Median | Run Median | Total Median | Relative to c-ast |")
    print("|--------|--------|--------------|------------|--------------|-------------------|")
    for result in results:
        total_median = median_or_none(result.total_samples)
        relative = "n/a"
        if result.status == "ok" and baseline_total not in (None, 0.0) and total_median is not None:
            relative = f"{total_median / baseline_total:.2f}x"

        print(
            f"| {result.name} | {result.status} | "
            f"{format_seconds(median_or_none(result.build_samples))} | "
            f"{format_seconds(median_or_none(result.run_samples))} | "
            f"{format_seconds(total_median)} | {relative} |"
        )

    notes = [result for result in results if result.status != "ok"]
    if notes:
        print("")
        print("Notes:")
        for result in notes:
            print(f"- {result.name}: {result.reason}")

    print("")
    print("Averages:")
    print("| Recipe | Build Mean | Run Mean | Total Mean |")
    print("|--------|------------|----------|------------|")
    for result in results:
        print(
            f"| {result.name} | "
            f"{format_seconds(mean_or_none(result.build_samples))} | "
            f"{format_seconds(mean_or_none(result.run_samples))} | "
            f"{format_seconds(mean_or_none(result.total_samples))} |"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Benchmark SageLang execution recipes across interpreted and compiled paths.",
    )
    parser.add_argument("--runs", type=int, default=5, help="timed runs per recipe")
    parser.add_argument("--warmups", type=int, default=1, help="warmup runs per recipe")
    parser.add_argument(
        "--workload",
        type=Path,
        default=Path("benchmarks/runtime_compare.sage"),
        help="Sage workload to benchmark (default: benchmarks/runtime_compare.sage)",
    )
    parser.add_argument(
        "--cc",
        default="cc",
        help="C compiler to use for the self-hosted compiled recipe (default: cc)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    workload = (repo_root / args.workload).resolve() if not args.workload.is_absolute() else args.workload
    results = collect_recipe_results(repo_root, workload, args.runs, args.warmups, args.cc)
    expected_output = validate_recipe_checksums(results)
    print_recipe_benchmark(results, repo_root, workload, expected_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
