#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# OIS — OneInstallSystem  v2.0.0  (SageLang)
# Pure POSIX sh — Linux, macOS, FreeBSD, OpenBSD, NetBSD, WSL
# ═══════════════════════════════════════════════════════════════════════════════

OIS_VERSION="2.0.0"
OIS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$OIS_DIR/.." && pwd)"
export OIS_VERSION OIS_DIR PROJECT_ROOT

# ── Source core ────────────────────────────────────────────────────────────────
. "$OIS_DIR/core/utils.sh"
. "$OIS_DIR/core/system.sh"
. "$OIS_DIR/core/conf.sh"
. "$OIS_DIR/core/registry.sh"
. "$OIS_DIR/core/deps.sh"
. "$OIS_DIR/core/builder.sh"
. "$OIS_DIR/core/integrate.sh"

# ── Sudo escalation ────────────────────────────────────────────────────────────
_ois_elevate() {
    [ "$OIS_IS_ROOT" = "yes" ] && return 0
    [ "$OIS_SUDO" = "none" ] && ois_die "Install requires sudo or doas."
    printf "\n  ${_B}Administrator privileges required.${_R}\n"
    exec $OIS_SUDO sh "$OIS_DIR/OIS.sh" "$@"
}

_resolve_scope() {
    OIS_SCOPE="system"
    OIS_APP_INSTALL_PATH="/usr/local/bin"
    export OIS_SCOPE OIS_APP_INSTALL_PATH
}

_fix_project_root() {
    _fpr="$(ois_reg_get "${OIS_APP_NAME:-_}" project_root 2>/dev/null)" || return 0
    [ -n "$_fpr" ] && [ -d "$_fpr" ] && { PROJECT_ROOT="$_fpr"; export PROJECT_ROOT; }
}

# ── Helpers ────────────────────────────────────────────────────────────────────
_step()   { printf "  ${_Y}⚙${_R}  %s" "$*"; }
_step_ok()   { printf "  ${_G}✓${_R}  %s\n" "${1:-done}"; }
_step_fail() { printf "  ${_RED}✗${_R}  %s\n" "$*"; }

# ═══════════════════════════════════════════════════════════════════════════════
# INSTALL
# ═══════════════════════════════════════════════════════════════════════════════
cmd_install() {
    ois_hdr "  $OIS_APP_DISPLAY" "Installing  ·  OIS v$OIS_VERSION  ·  $OIS_OS $OIS_ARCH"
    printf "  ${_D}%-16s${_R} %s\n" "System:"   "$OIS_OS${OIS_DISTRO:+ ($OIS_DISTRO $OIS_DISTRO_VER)}"
    printf "  ${_D}%-16s${_R} %s\n" "Package:"  "$OIS_PM"
    printf "  ${_D}%-16s${_R} %s\n" "Scope:"    "system (/usr/local)"
    printf "  ${_D}%-16s${_R} %s/%s\n" "Install:" "/usr/local/bin" "$OIS_APP_BINARY"
    printf '\n'

    if ois_reg_has "$OIS_APP_NAME"; then
        _ev="$(ois_reg_get "$OIS_APP_NAME" version)"
        ois_warn "$OIS_APP_NAME v$_ev is already installed."
        if [ "$OIS_YES" != "yes" ]; then
            printf '\n  Reinstall? [y/N] ' ; read -r _r
            case "$_r" in y|Y|yes) ;; *) printf '\n'; return 0 ;; esac
        fi
        _ois_remove_current
        printf '\n'
    fi

    printf "${_B}[1/4] Dependencies${_R}\n"
    ois_deps_install || ois_die "Required dependency failed — fix above and retry."
    printf '\n'

    printf "${_B}[2/4] Build${_R}\n"
    _fix_project_root
    cd "$PROJECT_ROOT" || ois_die "Cannot cd to project root: $PROJECT_ROOT"

    _step "Synchronizing submodules"
    if [ -f "sagesync" ] && [ -x "sagesync" ]; then
        python3 sagesync 2>/dev/null || true
    elif [ -d ".git" ]; then
        git submodule sync 2>/dev/null || true
        git submodule update --init --recursive 2>/dev/null || true
    fi
    _step_ok "done"

    _step "Cleaning build artifacts"
    rm -rf core/build_sage 2>/dev/null || true
    make -C core clean 2>/dev/null || true
    _step_ok "clean"

    if [ "$OIS_NO_SHADERS" != "yes" ]; then
        _compile_shaders
    fi

    _detect_build_system
    _build_sage

    printf "${_B}[3/4] Install${_R}\n"
    _install_sage
    _install_ois_runtime
    _remove_excluded_libs
    _fix_permissions

    printf "${_B}[4/4] Integrate${_R}\n"
    _ver="unknown"
    [ -f "$PROJECT_ROOT/VERSION" ] && _ver="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION")"

    _dep_str=""
    _di=0
    while [ "$_di" -lt "$OIS_DEP_COUNT" ]; do
        eval "_dn=\$OIS_DEP_${_di}_NAME"
        eval "_dc=\$OIS_DEP_${_di}_CMD"
        eval "_do=\$OIS_DEP_${_di}_OPT"
        _dep_str="${_dep_str}${_dn}:${_dc:-$_dn}:${_do} "
        _di=$(( _di + 1 ))
    done

    ois_reg_init
    ois_reg_set "$OIS_APP_NAME" version         "$_ver"
    ois_reg_set "$OIS_APP_NAME" binary_path     "/usr/local/bin/$OIS_APP_BINARY"
    ois_reg_set "$OIS_APP_NAME" scope           "system"
    ois_reg_set "$OIS_APP_NAME" version_url     "${OIS_APP_VERSION_URL:-}"
    ois_reg_set "$OIS_APP_NAME" github          "${OIS_APP_GITHUB:-}"
    ois_reg_set "$OIS_APP_NAME" update_mode     "off"
    ois_reg_set "$OIS_APP_NAME" installed_at    "$(date '+%Y-%m-%d %H:%M %Z')"
    ois_reg_set "$OIS_APP_NAME" project_root    "$PROJECT_ROOT"
    ois_reg_set "$OIS_APP_NAME" installed_by    "$OIS_PM"
    ois_reg_set "$OIS_APP_NAME" additional_info "${OIS_APP_ADDITIONAL_INFO:-}"
    ois_reg_set "$OIS_APP_NAME" deps            "$_dep_str"
    ois_mf_add  "$OIS_APP_NAME" "/usr/local/bin/$OIS_APP_BINARY"

    ois_integrate_run "/usr/local/bin/$OIS_APP_BINARY"
    printf '\n'

    ois_div
    printf "${_B}${_G}  ✓  $OIS_APP_DISPLAY installed!${_R}\n"
    ois_div
    printf '\n'
    printf "  ${_B}%-34s${_R} %s\n" "$OIS_APP_BINARY" "launch"
    printf '\n'
}

# ── Shaders ────────────────────────────────────────────────────────────────────
_compile_shaders() {
    command -v glslc >/dev/null 2>&1 || return 0
    [ -d "core/examples/shaders" ] || return 0
    _step "Compiling GLSL shaders to SPIR-V"
    _count=0; _fail=0
    for _sf in core/examples/shaders/*.vert core/examples/shaders/*.frag core/examples/shaders/*.comp; do
        [ -f "$_sf" ] || continue
        if glslc "$_sf" -o "$_sf.spv" 2>/dev/null; then
            _count=$(( _count + 1 ))
        else
            _fail=$(( _fail + 1 ))
        fi
    done
    if [ "$_fail" -eq 0 ]; then
        _step_ok "$_count modules"
    else
        _step_ok "$_count modules ($_fail failed)"
    fi
}

# ── Build system detection ─────────────────────────────────────────────────────
_detect_build_system() {
    _has_cmake=0
    command -v cmake >/dev/null 2>&1 && _has_cmake=1
    case "$OIS_USE_CMAKE" in
        yes) [ "$_has_cmake" -eq 1 ] || ois_die "CMake chosen but cmake(1) not found." ;;
        no)  OIS_USE_CMAKE="no" ;;
        auto)
            if [ "$_has_cmake" -eq 1 ]; then
                OIS_USE_CMAKE="yes"
            else
                OIS_USE_CMAKE="no"
                ois_warn "cmake(1) not found — falling back to Make"
            fi
            ;;
    esac
    export OIS_USE_CMAKE
}

# ── Sage build ─────────────────────────────────────────────────────────────────
_build_sage() {
    _njobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"
    if [ "$OIS_USE_CMAKE" = "yes" ]; then
        _step "Configuring CMake build (self-hosted Sage mode)"
        mkdir -p core/build_sage
        if cmake -S core -B core/build_sage -DBUILD_SAGE=ON >/dev/null 2>&1; then
            _step_ok "v$(tr -d '[:space:]' < VERSION 2>/dev/null || echo '?')"
        else
            ois_die "CMake configuration failed"
        fi
        _step "Compiling sage (C sources)"
        if cmake --build core/build_sage --target sage -j "$_njobs" >/dev/null 2>&1; then
            _step_ok "built"
        else
            ois_die "CMake build failed"
        fi
        OIS_BUILT_BIN="core/build_sage/sage"
    else
        _step "Compiling sage (C sources)"
        if make -C core -j "$_njobs" $OIS_MAKE_VARS >/dev/null 2>&1; then
            _step_ok "built"
        else
            ois_die "Make build failed"
        fi
        OIS_BUILT_BIN="core/sage"
    fi

    if [ -f "$OIS_BUILT_BIN" ] && [ -x "$OIS_BUILT_BIN" ]; then
        _size="$(du -sh "$OIS_BUILT_BIN" 2>/dev/null | cut -f1)"
        ois_ok "Binary: $OIS_BUILT_BIN  ($_size)"
    else
        ois_die "Binary not found after build: $OIS_BUILT_BIN"
    fi
}

# ── Install sage + lsp + libs + examples + docs ────────────────────────────────
_install_sage() {
    # cmake build produces binaries in core/build_sage/; copy to core/ so
    # the Makefile install target can find them without a redundant rebuild.
    if [ "$OIS_USE_CMAKE" = "yes" ]; then
        cp core/build_sage/sage    core/sage    2>/dev/null || true
        cp core/build_sage/sage-lsp core/sage-lsp 2>/dev/null || true
    fi
    _step "Installing sage system-wide"
    if [ "$OIS_IS_ROOT" = "yes" ]; then
        make -C core install PREFIX=/usr/local >/dev/null 2>&1
    else
        sudo make -C core install PREFIX=/usr/local >/dev/null 2>&1
    fi || ois_die "Install failed"
    _step_ok "sage → /usr/local/bin"
    [ -f "/usr/local/bin/sage-lsp" ] && ois_ok "sage-lsp → /usr/local/bin/sage-lsp"
}

# ── OIS runtime to share dir ───────────────────────────────────────────────────
_install_ois_runtime() {
    _oirs="/usr/local/share/sage/OIS"
    ois_mkdir "$_oirs/core"
    if ois_cp "$OIS_DIR/OIS.sh" "$_oirs/OIS.sh" 2>/dev/null && \
       cp -r "$OIS_DIR/core/." "$_oirs/core/" 2>/dev/null; then
        ois_chmod 755 "$_oirs/OIS.sh"
        ois_chmod 755 "$_oirs/core/"*.sh 2>/dev/null || true
        ois_cp "$OIS_DIR/OIS.conf" "$_oirs/OIS.conf" 2>/dev/null || true
        ois_ok "OIS runtime    →  $_oirs"
        ois_mf_add "$OIS_APP_NAME" "$_oirs"
    else
        ois_warn "Could not install OIS runtime to $_oirs"
    fi
}

_remove_excluded_libs() {
    [ -z "$OIS_EXCLUDE_LIBS" ] && return 0
    for _lib in $OIS_EXCLUDE_LIBS; do
        _lp="/usr/local/share/sage/lib/$_lib"
        [ -d "$_lp" ] || continue
        rm -rf "$_lp" 2>/dev/null || sudo rm -rf "$_lp" 2>/dev/null || true
        ois_ok "Excluded lib: $_lib"
    done
}

_fix_permissions() {
    _su="${SUDO_USER:-}"
    [ -z "$_su" ] && return 0
    chown -R "$_su" "$PROJECT_ROOT" 2>/dev/null || true
}

# ── Remove current install (internal, no prompts) ──────────────────────────────
_ois_remove_current() {
    _rc_bin="$(ois_reg_get "$OIS_APP_NAME" binary_path 2>/dev/null)"
    _rc_hook="${OIS_APP_INSTALL_PATH}/.${OIS_APP_BINARY}-ois"
    [ -n "$_rc_bin" ] && _rc_hook="$(dirname "$_rc_bin")/.${OIS_APP_BINARY}-ois"

    [ -n "$_rc_bin" ] && [ -f "$_rc_bin" ] && ois_rm "$_rc_bin" && ois_ok "Removed  $_rc_bin"
    [ -f "$_rc_hook" ] && ois_rm "$_rc_hook" && ois_ok "Removed  $_rc_hook"

    _rc_mf="$(ois_mf_file "$OIS_APP_NAME")"
    if [ -f "$_rc_mf" ]; then
        while IFS= read -r _f || [ -n "$_f" ]; do
            [ -z "$_f" ] && continue
            [ "$_f" = "$_rc_bin" ]  && continue
            [ "$_f" = "$_rc_hook" ] && continue
            [ -f "$_f" ] && ois_rm    "$_f" && ois_ok "Removed  $_f"
            [ -d "$_f" ] && ois_rmdir "$_f" && ois_ok "Removed  $_f"
        done < "$_rc_mf"
    fi

    for _mf in /usr/local/bin/sage /usr/local/bin/sage-lsp /usr/local/bin/sagepkg; do
        [ -f "$_mf" ] && ois_rm "$_mf" && ois_ok "Removed  $_mf"
    done
    for _md in /usr/local/share/sage /usr/local/share/doc/sage; do
        [ -d "$_md" ] && ois_rmdir "$_md" && ois_ok "Removed  $_md"
    done

    ois_rm "$(ois_mf_file  "$OIS_APP_NAME")"
    ois_rm "$(ois_reg_file "$OIS_APP_NAME")"
}

# ═══════════════════════════════════════════════════════════════════════════════
# UNINSTALL
# ═══════════════════════════════════════════════════════════════════════════════
cmd_uninstall() {
    ois_hdr "  $OIS_APP_DISPLAY" "Uninstall  ·  OIS v$OIS_VERSION"
    ois_reg_has "$OIS_APP_NAME" || ois_die "$OIS_APP_NAME is not installed."
    _u="$(ois_reg_get "$OIS_APP_NAME" uninstaller 2>/dev/null)"
    if [ -n "$_u" ] && [ -f "$_u" ]; then
        if [ "$OIS_YES" = "yes" ]; then
            sh "$_u" --yes
        else
            sh "$_u"
        fi
    else
        ois_warn "Uninstaller not found — removing directly."
        if [ "$OIS_YES" != "yes" ]; then
            printf '  Remove %s? [y/N] ' "$OIS_APP_NAME" ; read -r _r
            case "$_r" in y|Y|yes) ;; *) printf '  Cancelled.\n\n'; exit 0 ;; esac
        fi
        _ois_remove_current
        ois_ok "$OIS_APP_NAME removed."
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# REINSTALL
# ═══════════════════════════════════════════════════════════════════════════════
cmd_reinstall() {
    ois_hdr "  $OIS_APP_DISPLAY" "Reinstall  ·  OIS v$OIS_VERSION"
    _ri_root="$(ois_reg_get "$OIS_APP_NAME" project_root 2>/dev/null)"
    _ri_gh="$(ois_reg_get   "$OIS_APP_NAME" github        2>/dev/null)"

    if ois_reg_has "$OIS_APP_NAME"; then
        ois_info "Removing current install..."
        _ois_remove_current
        ois_ok "Removed."
    fi

    _ri_tmp=""
    if [ -n "$_ri_root" ] && [ -d "$_ri_root" ] && \
       { [ -f "$_ri_root/Makefile" ] || [ -f "$_ri_root/CMakeLists.txt" ]; }; then
        PROJECT_ROOT="$_ri_root"
        export PROJECT_ROOT
        ois_info "Building from: $PROJECT_ROOT"
    elif [ -n "$_ri_gh" ]; then
        ois_info "Source dir gone — cloning fresh from GitHub..."
        _ri_tmp="$(mktemp -d 2>/dev/null || mktemp -d -t ois_ri)"
        git clone --depth 1 "https://github.com/$_ri_gh" "$_ri_tmp/src" \
            || ois_die "Git clone failed."
        PROJECT_ROOT="$_ri_tmp/src"
        export PROJECT_ROOT
    else
        ois_die "No source dir and no GitHub repo — cannot reinstall."
    fi

    printf '\n'
    cmd_install

    [ -n "$_ri_tmp" ] && rm -rf "$_ri_tmp" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# REPAIR
# ═══════════════════════════════════════════════════════════════════════════════
cmd_repair() {
    ois_hdr "  $OIS_APP_DISPLAY" "Repair  ·  OIS v$OIS_VERSION"
    ois_reg_has "$OIS_APP_NAME" || ois_die "$OIS_APP_NAME is not installed."
    ois_info "Rebuilding — config and data untouched."
    _fix_project_root
    cd "$PROJECT_ROOT" || ois_die "Cannot cd to project root."
    rm -rf core/build_sage 2>/dev/null || true
    make -C core clean 2>/dev/null || true
    _detect_build_system
    _build_sage
    _install_sage
    _install_ois_runtime
    _fix_permissions
    ois_ok "Repaired  →  /usr/local/bin/sage"
    printf '\n'
}

# ═══════════════════════════════════════════════════════════════════════════════
# STATUS / INFO / LIST / HELP / PANEL
# ═══════════════════════════════════════════════════════════════════════════════
cmd_status() {
    ois_hdr "  $OIS_APP_DISPLAY" "Status  ·  OIS v$OIS_VERSION"
    if ! ois_reg_has "$OIS_APP_NAME"; then
        ois_warn "Not installed."; printf '\n  Run: sh install.sh\n\n'; return 0
    fi
    _ver="$(ois_reg_get "$OIS_APP_NAME" version)"
    _bin="$(ois_reg_get "$OIS_APP_NAME" binary_path)"
    _date="$(ois_reg_get "$OIS_APP_NAME" installed_at)"
    _bs="✓" ; [ ! -f "$_bin" ] && _bs="${_RED}missing${_R}"
    printf "  ${_D}%-18s${_R} v%s  (%s)\n" "Installed:" "$_ver" "$_date"
    printf "  ${_D}%-18s${_R} %s  [%b]\n"  "Binary:"    "$_bin" "$_bs"
    printf '\n'
}

cmd_info() {
    ois_hdr "  OIS System Info" "OIS v$OIS_VERSION"
    printf "  ${_D}%-22s${_R} %s\n" "OS:"         "$OIS_OS"
    printf "  ${_D}%-22s${_R} %s\n" "Distro:"     "${OIS_DISTRO:-n/a} ${OIS_DISTRO_VER:-}"
    printf "  ${_D}%-22s${_R} %s\n" "Arch:"       "$OIS_ARCH"
    printf "  ${_D}%-22s${_R} %s\n" "Package mgr:""$OIS_PM"
    printf "  ${_D}%-22s${_R} %s\n" "Privilege:"  "${OIS_SUDO}  (root: $OIS_IS_ROOT)"
    printf "  ${_D}%-22s${_R} %s\n" "Make:"       "$OIS_MAKE"
    printf "  ${_D}%-22s${_R} %s\n" "Python:"     "${OIS_PYTHON:-not found}"
    printf "  ${_D}%-22s${_R} %s\n" ".NET:"       "${OIS_DOTNET:-not found}"
    printf '\n'
}

cmd_list() {
    ois_hdr "  OIS — Installed Apps" "OIS v$OIS_VERSION"
    printf "  ${_D}%-20s %-10s %-8s %-35s %s${_R}\n" "App" "Version" "Scope" "Binary" "Date"
    printf '  %s\n' "──────────────────────────────────────────────────────────────────────"
    ois_reg_list
    printf '\n'
}

cmd_ois_panel() {
    ois_hdr "  $OIS_APP_DISPLAY" "Managed by OIS v$OIS_VERSION"
    if ! ois_reg_has "$OIS_APP_NAME"; then
        ois_warn "$OIS_APP_NAME is not installed."
        printf '\n  Run:  sh install.sh\n\n'; return 0
    fi
    _ver="$(ois_reg_get  "$OIS_APP_NAME" version)"
    _date="$(ois_reg_get "$OIS_APP_NAME" installed_at)"
    _gh="$(ois_reg_get   "$OIS_APP_NAME" github)"
    _info="$(ois_reg_get "$OIS_APP_NAME" additional_info)"

    printf "  ${_D}%-14s${_R} v%s\n"  "Version:"  "$_ver"
    printf '\n'
    printf "  ${_D}%s${_R} Installed on:     %s\n" "$OIS_APP_NAME" "$_date"
    printf "  ${_D}%s${_R} Source:           https://github.com/%s\n" "$OIS_APP_NAME" "$_gh"
    [ -n "$_info" ] && \
    printf "  ${_D}%s${_R} Info:             %s\n" "$OIS_APP_NAME" "$_info"
    printf '\n'
    printf "  ${_B}Commands:${_R}\n\n"
    printf "  %-38s %s\n" "$OIS_APP_BINARY --uninstall"    "remove cleanly"
    printf "  %-38s %s\n" "$OIS_APP_BINARY --reinstall"    "full clean reinstall from source"
    printf "  %-38s %s\n" "$OIS_APP_BINARY --install-info" "full installation details"
    printf '\n'
    printf "  ${_D}OIS v%s${_R}\n\n" "$OIS_VERSION"
}

cmd_install_info() {
    ois_hdr "  $OIS_APP_DISPLAY" "Installation Info  ·  OIS v$OIS_VERSION"
    if ! ois_reg_has "$OIS_APP_NAME"; then
        ois_warn "Not installed."; printf '\n  Run: sh install.sh\n\n'; return 0
    fi
    _ver="$(ois_reg_get  "$OIS_APP_NAME" version)"
    _bin="$(ois_reg_get  "$OIS_APP_NAME" binary_path)"
    _date="$(ois_reg_get "$OIS_APP_NAME" installed_at)"
    _gh="$(ois_reg_get   "$OIS_APP_NAME" github)"
    _root="$(ois_reg_get "$OIS_APP_NAME" project_root)"
    _bin_s="✓" ; [ ! -f "$_bin" ] && _bin_s="${_RED}MISSING${_R}"

    printf "  ${_B}Package${_R}\n"
    printf "  ${_D}%-20s${_R} %s\n"   "Name:"      "$OIS_APP_DISPLAY"
    printf "  ${_D}%-20s${_R} v%s\n"  "Version:"   "$_ver"
    printf "  ${_D}%-20s${_R} %s\n"   "Installed:" "$_date"
    printf '\n'
    printf "  ${_B}Location${_R}\n"
    printf "  ${_D}%-20s${_R} %b  [%b]\n" "Binary:"   "$_bin" "$_bin_s"
    printf "  ${_D}%-20s${_R} %s\n"    "Scope:"     "system"
    printf "  ${_D}%-20s${_R} %s\n"    "Source:"    "${_root:-unknown}"
    printf '\n'
    printf "  ${_B}Dependencies${_R}\n"
    _deps="$(ois_reg_get "$OIS_APP_NAME" deps 2>/dev/null)"
    if [ -n "$_deps" ]; then
        for _de in $_deps; do
            _dn="${_de%%:*}" ; _r="${_de#*:}" ; _dc="${_r%%:*}" ; _do="${_r#*:}"
            _chk="${_dc:-$_dn}"
            case "$_chk" in
                pkgconfig:*)
                    _pc="${_chk#pkgconfig:}"
                    pkg-config --exists "$_pc" 2>/dev/null \
                        && _ds="${_G}✓ installed${_R}" || _ds="${_Y}not found${_R}" ;;
                *)
                    command -v "$_chk" >/dev/null 2>&1 \
                        && _ds="${_G}✓ installed${_R}" || _ds="${_Y}not found${_R}" ;;
            esac
            _dot="" ; [ "$_do" = "yes" ] && _dot=" (optional)"
            printf "  ${_D}  %-18s${_R} %b%s\n" "$_dn" "$_ds" "$_dot"
        done
    else
        printf "  ${_D}  (none declared)${_R}\n"
    fi
    printf '\n'
    printf "  ${_B}Installed files${_R}\n"
    ois_mf_read "$OIS_APP_NAME" | while IFS= read -r _f; do
        [ -z "$_f" ] && continue
        _fs="✓" ; [ ! -e "$_f" ] && _fs="${_Y}missing${_R}"
        printf "  ${_D}%b${_R}  %s\n" "$_fs" "$_f"
    done
    printf '\n  %bOIS v%s  ·  %s %s%b\n\n' "$_D" "$OIS_VERSION" "$OIS_OS" "$OIS_ARCH" "$_R"
}

cmd_help() {
    printf '\n%bOIS — OneInstallSystem  v%s%b\n\n' "$_B" "$OIS_VERSION" "$_R"
    printf '  The one folder that makes any Unix app installable.\n\n'
    printf '  %bDev setup:%b  put OIS/ in your project, fill in OIS/OIS.conf\n' "$_B" "$_R"
    printf '  %bUser install:%b  sh install.sh\n\n' "$_B" "$_R"
    printf '  %bFlags:%b\n\n' "$_B" "$_R"
    printf '  %-36s %s\n' "--cmake"           "use CMake build (default)"
    printf '  %-36s %s\n' "--make"            "use Make build"
    printf '  %-36s %s\n' "--no-shaders"      "skip shader compilation"
    printf '  %-36s %s\n' "--no-vulkan"       "disable Vulkan GPU support"
    printf '  %-36s %s\n' "--no-gpu"          "disable all GPU features"
    printf '  %-36s %s\n' "--no-curl"         "disable HTTP/libcurl"
    printf '  %-36s %s\n' "--no-ssl"          "disable OpenSSL"
    printf '  %-36s %s\n' "--no-lib-<name>"   "exclude lib/<name> (e.g. --no-lib-ml)"
    printf '  %-36s %s\n' "--minimal"         "disable all optional features"
    printf '  %-36s %s\n' "--yes / -y"        "non-interactive mode"
    printf '\n  %bApp flags (after install):%b\n\n' "$_B" "$_R"
    printf '  %-36s %s\n' "sage --ois"           "OIS panel"
    printf '  %-36s %s\n' "sage --install-info"  "full install details"
    printf '  %-36s %s\n' "sage --uninstall"     "remove cleanly"
    printf '  %-36s %s\n' "sage --reinstall"     "full clean reinstall"
    printf '\n  %bDirect OIS commands:%b\n\n' "$_B" "$_R"
    printf '  %-36s %s\n' "sh OIS/OIS.sh install"      "install"
    printf '  %-36s %s\n' "sh OIS/OIS.sh uninstall"    "uninstall"
    printf '  %-36s %s\n' "sh OIS/OIS.sh reinstall"    "reinstall"
    printf '  %-36s %s\n' "sh OIS/OIS.sh repair"       "rebuild only"
    printf '  %-36s %s\n' "sh OIS/OIS.sh status"       "status"
    printf '  %-36s %s\n' "sh OIS/OIS.sh install-info" "full install details"
    printf '  %-36s %s\n' "sh OIS/OIS.sh info"         "system detection"
    printf '  %-36s %s\n' "sh OIS/OIS.sh list"         "all OIS apps on system"
    printf '\n'
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
main() {
    _cmd="" OIS_USE_CMAKE="auto" OIS_NO_SHADERS="no" OIS_EXCLUDE_LIBS=""
    OIS_MAKE_VARS="" OIS_YES=""

    for _a in "$@"; do
        case "$_a" in
            install|uninstall|reinstall|repair|\
            status|info|list|help|ois|install-info) _cmd="$_a" ;;
            --cmake)       OIS_USE_CMAKE="yes"  ;;
            --make)        OIS_USE_CMAKE="no"   ;;
            --no-shaders)  OIS_NO_SHADERS="yes" ;;
            --no-vulkan|--no-gpu)
                OIS_MAKE_VARS="$OIS_MAKE_VARS VULKAN=0" ;;
            --no-curl|--no-ssl)
                OIS_MAKE_VARS="$OIS_MAKE_VARS SAGE_NO_NET=1 CFLAGS_EXTRA=-DSAGE_NO_NET" ;;
            --minimal)
                OIS_MAKE_VARS="$OIS_MAKE_VARS VULKAN=0 SAGE_NO_NET=1 CFLAGS_EXTRA=-DSAGE_NO_NET"
                OIS_EXCLUDE_LIBS="blockchain graphics os net crypto ml cuda llm agent chat android transpiler metal rich" ;;
            --no-lib-*)
                _lib="${_a#--no-lib-}"
                OIS_EXCLUDE_LIBS="$OIS_EXCLUDE_LIBS $_lib" ;;
            --yes|-y)      OIS_YES="yes"        ;;
            --version)     printf 'OIS v%s\n' "$OIS_VERSION"; exit 0 ;;
            --update|--upgrade)
                printf '  Updates are handled by re-running: sh install.sh\n\n'
                exit 0 ;;
            --uninstall|--reinstall|--ois|--install-info)
                _cmd="${_a#--}" ;;
        esac
    done
    export OIS_USE_CMAKE OIS_NO_SHADERS OIS_EXCLUDE_LIBS OIS_MAKE_VARS OIS_YES

    case "$_cmd" in info|list|help) ;;
        *) ois_conf_load ;;
    esac

    _resolve_scope

    case "$_cmd" in
        install|uninstall|reinstall|repair)
            _ois_elevate "$@" ;;
    esac

    case "$_cmd" in
        install)          cmd_install        ;;
        uninstall)        cmd_uninstall      ;;
        reinstall)        cmd_reinstall      ;;
        repair)           cmd_repair         ;;
        status)           cmd_status         ;;
        info)             cmd_info           ;;
        list)             cmd_list           ;;
        help)             cmd_help           ;;
        ois)              cmd_ois_panel      ;;
        install-info)     cmd_install_info   ;;
        "")
            if ois_reg_has "${OIS_APP_NAME:-_}" 2>/dev/null; then
                cmd_status
            else
                cmd_install
            fi ;;
        *) ois_err "Unknown: $_cmd"; printf '  sh OIS/OIS.sh help\n\n'; exit 1 ;;
    esac
}

main "$@"
