#!/bin/sh
# OIS core/builder.sh — build from source
# ─────────────────────────────────────────

ois_builder_detect() {
    [ "$OIS_APP_BUILD_SYSTEM" != "auto" ] && return 0
    if   [ -f "CMakeLists.txt" ];                then OIS_APP_BUILD_SYSTEM="cmake"
    elif [ -f "Makefile" ] || [ -f "makefile" ]; then OIS_APP_BUILD_SYSTEM="make"
    elif [ -f "meson.build" ];                   then OIS_APP_BUILD_SYSTEM="meson"
    elif [ -f "Cargo.toml" ];                    then OIS_APP_BUILD_SYSTEM="cargo"
    elif [ -f "go.mod" ];                        then OIS_APP_BUILD_SYSTEM="go"
    elif [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then OIS_APP_BUILD_SYSTEM="python"
    else ois_die "No build system found. Set [build] system= in OIS.conf"
    fi
    export OIS_APP_BUILD_SYSTEM
}

_ois_build_env() {
    case "$OIS_OS" in
        macos|freebsd|openbsd|netbsd|dragonfly) OIS_CC="clang" ; OIS_CXX="clang++" ;;
        *) OIS_CC="gcc" ; OIS_CXX="g++" ;;
    esac
    # macOS: expose Homebrew include/lib paths to the build
    if [ "$OIS_OS" = "macos" ] && [ -n "$OIS_BREW_PREFIX" ]; then
        _brew_inc="-I$OIS_BREW_PREFIX/include"
        _brew_lib="-L$OIS_BREW_PREFIX/lib"
        # openssl is keg-only on Homebrew — needs explicit path
        [ -d "$OIS_BREW_PREFIX/opt/openssl@3/include" ] && \
            _brew_inc="$_brew_inc -I$OIS_BREW_PREFIX/opt/openssl@3/include"
        [ -d "$OIS_BREW_PREFIX/opt/openssl@3/lib" ] && \
            _brew_lib="$_brew_lib -L$OIS_BREW_PREFIX/opt/openssl@3/lib"
        [ -d "$OIS_BREW_PREFIX/opt/curl/include" ] && \
            _brew_inc="$_brew_inc -I$OIS_BREW_PREFIX/opt/curl/include"
        [ -d "$OIS_BREW_PREFIX/opt/curl/lib" ] && \
            _brew_lib="$_brew_lib -L$OIS_BREW_PREFIX/opt/curl/lib"
        export CFLAGS_EXTRA="${CFLAGS_EXTRA:-} $_brew_inc"
        export LDFLAGS_EXTRA="${LDFLAGS_EXTRA:-} $_brew_lib"
        export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"  # already set in system.sh
    fi
    # BSD: /usr/local paths (where pkg installs headers/libs)
    case "$OIS_OS" in freebsd|openbsd|netbsd|dragonfly)
        export CFLAGS_EXTRA="${CFLAGS_EXTRA:-} -I/usr/local/include"
        export LDFLAGS_EXTRA="${LDFLAGS_EXTRA:-} -L/usr/local/lib" ;;
    esac
    # Pass CC to make builds
    export CC="$OIS_CC" CXX="$OIS_CXX"
    _jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || printf '2')"
    # Re-detect GNU make — gmake may have just been installed by the deps phase
    command -v gmake >/dev/null 2>&1 && OIS_MAKE="gmake"
    export OIS_CC OIS_CXX OIS_MAKE
}

ois_builder_clean() {
    [ -n "$OIS_APP_CUSTOM_BUILD" ] && return 0
    case "$OIS_APP_BUILD_SYSTEM" in
        make)  $OIS_MAKE clean 2>/dev/null || true ;;
        cmake) rm -rf _ois_build 2>/dev/null || true ;;
        meson) rm -rf build 2>/dev/null || true ;;
        cargo) cargo clean 2>/dev/null || true ;;
        *) true ;;
    esac
}

ois_builder_build() {
    _ois_build_env
    [ -n "$OIS_APP_CUSTOM_BUILD" ] && {
        eval "$OIS_APP_CUSTOM_BUILD" || ois_die "Custom build failed."
        return 0
    }
    case "$OIS_APP_BUILD_SYSTEM" in
        make)
            export CXX="$OIS_CXX" CC="$OIS_CC"
            $OIS_MAKE -j"$_jobs" || ois_die "Build failed." ;;
        cmake)
            command -v cmake >/dev/null 2>&1 || ois_die "cmake not found."
            mkdir -p _ois_build
            cmake -S . -B _ois_build \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_COMPILER="$OIS_CC" \
                -DCMAKE_CXX_COMPILER="$OIS_CXX" \
                || ois_die "cmake configure failed."
            cmake --build _ois_build -- -j"$_jobs" || ois_die "cmake build failed." ;;
        meson)
            command -v meson >/dev/null 2>&1 || ois_die "meson not found."
            meson setup build --wipe 2>/dev/null || meson setup build
            meson compile -C build || ois_die "meson build failed." ;;
        cargo)
            command -v cargo >/dev/null 2>&1 || ois_die "cargo not found — https://rustup.rs"
            cargo build --release || ois_die "cargo build failed." ;;
        go)
            command -v go >/dev/null 2>&1 || ois_die "go not found."
            go build -o "$OIS_APP_BINARY_OUT" ./... || ois_die "go build failed." ;;
        dotnet)
            if command -v dotnet >/dev/null 2>&1; then
                dotnet build --configuration Release || ois_die "dotnet build failed."
                dotnet publish --configuration Release --output ./publish || ois_die "publish failed."
            elif command -v mcs >/dev/null 2>&1; then
                _srcs="$(find . -name '*.cs' ! -path '*/obj/*' | tr '\n' ' ')"
                mcs -out:"${OIS_APP_BINARY_OUT}.exe" $_srcs || ois_die "mcs build failed."
            else ois_die "No .NET runtime found."; fi ;;
        python)
            [ -n "$OIS_PYTHON" ] || ois_die "Python not found."
            [ -d ".venv" ] || $OIS_PYTHON -m venv .venv || ois_die "venv failed."
            [ -f "requirements.txt" ] && .venv/bin/pip install -q -r requirements.txt ;;
        *) ois_die "Unknown build system: $OIS_APP_BUILD_SYSTEM" ;;
    esac
}

ois_builder_find_binary() {
    _n="$OIS_APP_BINARY_OUT"
    for _p in "./$_n" "./build/$_n" "./_ois_build/$_n" \
              "./publish/$_n" "./target/release/$_n" "./target/debug/$_n"; do
        [ -f "$_p" ] && [ -x "$_p" ] && { printf '%s' "$_p"; return 0; }
    done
    [ "$OIS_APP_BUILD_SYSTEM" = "python" ] && {
        _e="${OIS_APP_PYTHON_ENTRY:-$_n}"
        [ -f "./$_e" ]    && { printf './%s'    "$_e"; return 0; }
        [ -f "./$_e.py" ] && { printf './%s.py' "$_e"; return 0; }
    }
    return 1
}
