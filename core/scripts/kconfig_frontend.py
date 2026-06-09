#!/usr/bin/env python3
"""Launch Kconfig frontends with reliable dependency checks."""

from __future__ import annotations

import importlib.util
import os
import shutil
import site
import sys
from pathlib import Path


USAGE = "Usage: python3 scripts/kconfig_frontend.py <menuconfig|guiconfig> [kconfig-file]"


def module_available(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def is_truthy_env(name: str) -> bool:
    value = os.environ.get(name, "")
    return value.lower() not in ("", "0", "false", "no")


def is_user_site_executable(path: str) -> bool:
    try:
        resolved = Path(path).resolve()
    except OSError:
        return False

    candidates = []
    user_base = getattr(site, "USER_BASE", None)
    if user_base:
        candidates.append(Path(user_base).resolve())

    try:
        user_site = site.getusersitepackages()
    except AttributeError:
        user_site = None
    if user_site:
        candidates.append(Path(user_site).resolve().parent)

    for candidate in candidates:
        try:
            resolved.relative_to(candidate)
            return True
        except ValueError:
            continue
    return False


def print_missing_dependency(frontend: str, missing_tk: bool) -> None:
    target = f"make {frontend}"
    print(
        f"SageLang uses Kconfiglib's Python frontends for '{target}'.",
        file=sys.stderr,
    )
    print(file=sys.stderr)
    print(f"Could not launch '{frontend}' from {sys.executable}.", file=sys.stderr)
    print("Install it with:", file=sys.stderr)
    print("  python3 -m pip install --user kconfiglib", file=sys.stderr)
    if missing_tk:
        print(file=sys.stderr)
        print("GUI mode also needs Python Tk support.", file=sys.stderr)
        print("On Ubuntu/Debian install:", file=sys.stderr)
        print("  sudo apt install python3-tk", file=sys.stderr)
    print(file=sys.stderr)
    print(f"Then rerun: {target}", file=sys.stderr)


def should_use_path_fallback(executable: str) -> bool:
    if not executable:
        return False
    if not is_truthy_env("PYTHONNOUSERSITE"):
        return True
    return not is_user_site_executable(executable)


def exec_program(program: str, argv: list[str]) -> None:
    try:
        os.execv(program, argv)
    except OSError as exc:
        print(f"Failed to launch '{program}': {exc}", file=sys.stderr)
        raise SystemExit(1) from exc


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in {"menuconfig", "guiconfig"}:
        print(USAGE, file=sys.stderr)
        return 2

    frontend = sys.argv[1]
    frontend_args = sys.argv[2:] or ["Kconfig"]
    missing_tk = frontend == "guiconfig" and not module_available("tkinter")

    if module_available(frontend):
        if missing_tk:
            print_missing_dependency(frontend, missing_tk=True)
            return 1
        exec_program(sys.executable, [sys.executable, "-m", frontend, *frontend_args])

    executable = shutil.which(frontend)
    if should_use_path_fallback(executable):
        exec_program(executable, [executable, *frontend_args])

    print_missing_dependency(frontend, missing_tk=missing_tk)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
