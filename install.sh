#!/bin/sh
# SageLang installer — powered by OIS (OneInstallSystem)
# Usage: sh install.sh [--cmake|--make] [--no-shaders] [--no-lib-*] [--yes] [-y]
cd "$(dirname "$0")" || exit 1
chmod +x OIS/OIS.sh OIS/core/*.sh 2>/dev/null || true
exec sh OIS/OIS.sh install "$@"
