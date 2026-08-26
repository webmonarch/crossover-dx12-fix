#!/bin/bash
#
# Restore CrossOver's stock D3DMetal, undoing reapply-gptk4.sh.
#
# Expect DX12 to crash again afterward with the GGlobalSamplerDescriptorHeapSize
# assertion -- that is the point of reverting, not a failure. See README.md.
#
# Restore sources, in order of preference:
#   1. backup-stock-apple_gptk-CX<version>/  (kept outside the app bundle)
#   2. external.old / wine.old               (left in place by the swap)
#
# Usage:
#   ./revert-gptk4.sh              restore stock D3DMetal
#   ./revert-gptk4.sh --dry-run    print the plan, change nothing
#
# Requires App Management permission for the calling terminal -- see README.md.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROSSOVER="/Applications/CrossOver.app"
GPTK="$CROSSOVER/Contents/SharedSupport/CrossOver/lib64/apple_gptk"
BOTTLE="$HOME/Library/Application Support/CrossOver/Bottles/Satisfactory"

DRY=0
case "${1:-}" in
    --dry-run) DRY=1 ;;
    "")        ;;
    *) echo "usage: $(basename "$0") [--dry-run]" >&2; exit 2 ;;
esac

info() { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

d3dmetal_version_at() {
    plutil -extract CFBundleShortVersionString raw \
        "$1/external/D3DMetal.framework/Resources/Info.plist" 2>/dev/null || echo "none"
}

cx_running() { pgrep -f "$CROSSOVER/Contents/MacOS/CrossOver" >/dev/null 2>&1; }

[ -d "$GPTK" ] || die "CrossOver apple_gptk not found: $GPTK"

CXVER="$(defaults read "$CROSSOVER/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo unknown)"
BACKUP="$HERE/backup-stock-apple_gptk-CX${CXVER}"
CURRENT="$(d3dmetal_version_at "$GPTK")"

info "CrossOver $CXVER, D3DMetal currently $CURRENT"

# Pick a restore source.
if [ -d "$BACKUP/external" ] && [ -d "$BACKUP/wine" ]; then
    SRC="$BACKUP"; SRC_DESC="backup: $(basename "$BACKUP")"
elif [ -d "$GPTK/external.old" ] && [ -d "$GPTK/wine.old" ]; then
    SRC="inplace";  SRC_DESC="in-place external.old / wine.old"
else
    die "no restore source found - reinstall CrossOver to get stock libraries back"
fi
info "restore source: $SRC_DESC"

if [ "$SRC" = "inplace" ]; then
    STOCK_VER="$(plutil -extract CFBundleShortVersionString raw \
        "$GPTK/external.old/D3DMetal.framework/Resources/Info.plist" 2>/dev/null || echo unknown)"
else
    STOCK_VER="$(d3dmetal_version_at "$SRC")"
fi
info "would restore D3DMetal $STOCK_VER"

if [ "$DRY" = "1" ]; then
    step "would do:"
    cx_running && info "quit CrossOver"
    info "restore external/ and wine/ from $SRC_DESC"
    info "remove nvngx.dll + nvapi64.dll from the Satisfactory bottle's system32"
    exit 0
fi

if cx_running; then
    step "Quitting CrossOver"
    osascript -e 'tell application "CrossOver" to quit' || true
    for _ in $(seq 1 15); do cx_running || break; sleep 1; done
    cx_running && die "CrossOver is still running - quit it and retry."
    info "quit."
fi

step "Restoring stock D3DMetal $STOCK_VER"
cd "$GPTK"
if [ "$SRC" = "inplace" ]; then
    rm -rf external wine
    mv external.old external
    mv wine.old     wine
else
    rm -rf external wine external.old wine.old
    ditto "$SRC/" .
fi
info "restored."

# Remove the files the swap added to the bottle. Stock CrossOver does not put
# these in system32, so leaving GPTK4 copies behind would be inconsistent.
for f in nvngx.dll nvapi64.dll; do
    if [ -e "$BOTTLE/drive_c/windows/system32/$f" ]; then
        rm -f "$BOTTLE/drive_c/windows/system32/$f"
        info "removed $f from the bottle"
    fi
done

step "Verifying"
NOW="$(d3dmetal_version_at "$GPTK")"
[ "$NOW" != "none" ] || die "no D3DMetal present after restore - reinstall CrossOver"
info "D3DMetal $NOW active."

cat <<EOF

Reverted. DX12 will crash again in UE 5.6 titles; use -DX11 in the Steam launch
options as a stopgap, or re-run ./reapply-gptk4.sh to go back to D3DMetal 4.
EOF
