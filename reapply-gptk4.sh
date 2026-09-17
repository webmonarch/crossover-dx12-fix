#!/bin/bash
#
# Apply Apple's Game Porting Toolkit 4 (D3DMetal 4.0b2) to CrossOver.
#
# CrossOver 26.3 ships D3DMetal 3.0, under which UE 5.6 titles (Satisfactory,
# StarRupture) die during renderer init with:
#
#   Assertion failed: GGlobalSamplerDescriptorHeapSize <= MaximumSamplerHeapSize
#   [Engine\Source\Runtime\D3D12RHI\Private\D3D12Device.cpp] [Line: 372]
#
# D3DMetal 4 reports the sampler descriptor heap limits UE 5.6 expects, so DX12
# initializes. Every CrossOver update reverts the swap -- re-run this script.
#
# The procedure is Apple's own, from the Read Me inside the GPTK 4 disk image
# (vendored alongside this script as gptk4-b2/Apple-ReadMe.rtf).
#
# Usage:
#   ./reapply-gptk4.sh              apply (idempotent)
#   ./reapply-gptk4.sh --status     report what is installed, change nothing
#   ./reapply-gptk4.sh --dry-run    print the plan, change nothing
#
# Requires the calling terminal to hold System Settings -> Privacy & Security ->
# App Management. Without it every write fails with "Operation not permitted",
# and sudo does NOT help. See README.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$HERE/gptk4-b2/lib"
CROSSOVER="/Applications/CrossOver.app"
GPTK="$CROSSOVER/Contents/SharedSupport/CrossOver/lib64/apple_gptk"
BOTTLE="$HOME/Library/Application Support/CrossOver/Bottles/Satisfactory"
WANT="4.0b2"

MODE="apply"
case "${1:-}" in
    --status)  MODE="status" ;;
    --dry-run) MODE="dry-run" ;;
    "")        ;;
    *) echo "usage: $(basename "$0") [--status|--dry-run]" >&2; exit 2 ;;
esac

info() { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

d3dmetal_version_at() {
    plutil -extract CFBundleShortVersionString raw \
        "$1/external/D3DMetal.framework/Resources/Info.plist" 2>/dev/null || echo "none"
}

cx_running() {
    pgrep -f "$CROSSOVER/Contents/MacOS/CrossOver" >/dev/null 2>&1
}

# CrossOver's wine looks builtin DLLs up by the PE's *internal* export name.
# Apple builds nvapi64.dll with the internal name "nvapi.dll", so the loader
# searches for nvapi.dll / nvapi.so, finds neither, and nvapi64 fails to load
# (LoadLibrary error 1114, ERROR_DLL_INIT_FAILED). D3DMetal probes exactly that
# load before switching the adapter from "AMD Compatibility Mode" (vendor
# 0x1002) to an NVIDIA identity (0x10de), and every DLSS gate downstream -- the
# UE DLSS plugin, Streamline's sl.dlss_g -- keys off that vendor ID. Aliasing
# the builtin under the name the loader wants is what turns DLSS on.
alias_nvapi() {
    ln -sf nvapi64.dll                       "$GPTK/wine/x86_64-windows/nvapi.dll"
    ln -sf ../../external/libd3dshared.dylib "$GPTK/wine/x86_64-unix/nvapi.so"
}

nvapi_aliased() {
    [ -e "$GPTK/wine/x86_64-windows/nvapi.dll" ] && [ -e "$GPTK/wine/x86_64-unix/nvapi.so" ]
}

[ -d "$GPTK" ] || die "CrossOver apple_gptk not found: $GPTK"

CXVER="$(defaults read "$CROSSOVER/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
CURRENT="$(d3dmetal_version_at "$GPTK")"
BACKUP="$HERE/backup-stock-apple_gptk-CX${CXVER}"

# ---------------------------------------------------------------- status ----
if [ "$MODE" = "status" ]; then
    printf 'CrossOver      %s\n' "$CXVER"
    printf 'D3DMetal       %s   (want %s)\n' "$CURRENT" "$WANT"
    printf 'payload        %s\n' \
        "$([ -d "$PAYLOAD" ] && d3dmetal_version_at "$HERE/gptk4-b2/lib" || echo 'MISSING')"
    printf 'stock backup   %s\n' \
        "$([ -d "$BACKUP" ] && echo "$(basename "$BACKUP")" || echo 'none for this CrossOver version')"
    printf 'nvngx bridge   %s\n' \
        "$([ -e "$GPTK/wine/x86_64-windows/nvngx.dll" ] && echo present || echo absent)"
    printf 'nvapi alias    %s\n' \
        "$(nvapi_aliased && echo present || echo absent)"
    printf 'bottle nvngx   %s\n' \
        "$([ -e "$BOTTLE/drive_c/windows/system32/nvngx.dll" ] && echo present || echo absent)"
    printf 'CrossOver      %s\n' "$(cx_running && echo running || echo 'not running')"
    if [ "$CURRENT" = "$WANT" ]; then
        printf '\n=> patched\n'
    else
        printf '\n=> NOT patched -- run %s\n' "$(basename "$0")"
    fi
    exit 0
fi

info "CrossOver $CXVER, D3DMetal $CURRENT (want $WANT)"

[ -d "$PAYLOAD" ] || die "payload missing: $PAYLOAD (see 'Upgrading the payload' in README.md)"
PAYLOAD_VER="$(d3dmetal_version_at "$HERE/gptk4-b2/lib")"
[ "$PAYLOAD_VER" = "$WANT" ] \
    || die "payload is D3DMetal $PAYLOAD_VER but WANT=$WANT -- update WANT in this script"

if [ "$CURRENT" = "$WANT" ]; then
    if nvapi_aliased; then
        info "already patched - nothing to do."
    else
        alias_nvapi
        info "already patched - added the missing nvapi builtin alias (enables DLSS)."
    fi
    exit 0
fi

if [ "$MODE" = "dry-run" ]; then
    step "would do:"
    cx_running && info "quit CrossOver"
    [ -d "$BACKUP" ] || info "back up stock apple_gptk (D3DMetal $CURRENT) -> $(basename "$BACKUP")"
    info "swap in D3DMetal $WANT from gptk4-b2/lib/"
    info "rename nvngx-on-metalfx.{so,dll} -> nvngx.{so,dll}"
    info "copy nvngx.dll + nvapi64.dll into the Satisfactory bottle's system32"
    info "alias nvapi.dll/nvapi.so so the loader can start nvapi64 (enables DLSS)"
    exit 0
fi

# ------------------------------------------------------- quit CrossOver ----
if cx_running; then
    step "Quitting CrossOver"
    osascript -e 'tell application "CrossOver" to quit' || true
    for _ in $(seq 1 15); do cx_running || break; sleep 1; done
    cx_running && die "CrossOver is still running - quit it and retry."
    info "quit."
fi

# ------------------------------------------------------------- back up ----
# One pristine copy per CrossOver version, kept outside the app bundle so a
# CrossOver reinstall cannot take it with it.
if [ ! -d "$BACKUP" ] && [ "$CURRENT" != "none" ]; then
    step "Backing up stock apple_gptk (D3DMetal $CURRENT)"
    ditto "$GPTK" "$BACKUP"
    info "-> $(basename "$BACKUP")"
fi

# ---------------------------------------------------------------- swap ----
step "Installing D3DMetal $WANT"
cd "$GPTK"
rm -rf external.old wine.old
[ -e external ] && mv external external.old
[ -e wine ]     && mv wine     wine.old
# ditto, not cp: preserves the x86_64-unix/*.so symlinks into libd3dshared.dylib
ditto "$PAYLOAD/" .
info "swapped (previous kept in place as external.old / wine.old)"

# Apple's Read Me: enable the experimental DLSS -> MetalFX bridge.
[ -e wine/x86_64-unix/nvngx-on-metalfx.so ] \
    && mv wine/x86_64-unix/nvngx-on-metalfx.so wine/x86_64-unix/nvngx.so
[ -e wine/x86_64-windows/nvngx-on-metalfx.dll ] \
    && mv wine/x86_64-windows/nvngx-on-metalfx.dll wine/x86_64-windows/nvngx.dll
info "nvngx bridge enabled"

alias_nvapi
info "nvapi builtin aliased (nvapi.dll -> nvapi64.dll) so the bridge can load it"

if [ -d "$BOTTLE/drive_c/windows/system32" ]; then
    cp wine/x86_64-windows/nvngx.dll   "$BOTTLE/drive_c/windows/system32/nvngx.dll"
    cp wine/x86_64-windows/nvapi64.dll "$BOTTLE/drive_c/windows/system32/nvapi64.dll"
    info "installed nvngx.dll + nvapi64.dll into the Satisfactory bottle"
else
    info "bottle not found at $BOTTLE - skipped system32 copy"
fi

# --------------------------------------------------------------- verify ----
step "Verifying"
NOW="$(d3dmetal_version_at "$GPTK")"
[ "$NOW" = "$WANT" ] || die "D3DMetal reports '$NOW', expected '$WANT'"
codesign -v "$GPTK/external/D3DMetal.framework" 2>/dev/null \
    || die "D3DMetal signature invalid"
info "D3DMetal $NOW active, signature valid."

cat <<EOF

Done. Before launching:
  - bottle graphics engine must be D3DMetal (not DXVK/DXMT)
  - Steam launch options: -dx12 -NOTEXTURESTREAMING
First launch rebuilds the shader cache and will be slow. DLSS and DLSS-G
(frame generation) run via MetalFX; FSR and XeSS also work. See README.md.
EOF
