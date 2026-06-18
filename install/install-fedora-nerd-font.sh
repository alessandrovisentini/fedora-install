#!/usr/bin/env bash
# Fedora doesn't package DejaVu Sans Mono Nerd Font; fetch the upstream release.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

FONT_NAME="DejaVuSansMono"
FONT_DIR="$HOME/.local/share/fonts/NerdFonts/$FONT_NAME"
RELEASE_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${FONT_NAME}.zip"

if fc-list 2>/dev/null | grep -qi "DejaVuSansM Nerd Font"; then
    log_info "DejaVu Sans Mono Nerd Font already installed; skipping"
    exit 0
fi

for cmd in curl unzip; do
    command -v "$cmd" &>/dev/null || { log_error "$cmd is required"; exit 1; }
done

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

log_info "Downloading DejaVu Sans Mono Nerd Font..."
curl -fsSL "$RELEASE_URL" -o "$tmpdir/${FONT_NAME}.zip" \
    || { log_error "Failed to download $RELEASE_URL"; exit 1; }

mkdir -p "$FONT_DIR"
log_info "Extracting fonts to $FONT_DIR..."
unzip -q -o "$tmpdir/${FONT_NAME}.zip" -d "$FONT_DIR"

if command -v fc-cache &>/dev/null; then
    log_info "Rebuilding font cache..."
    fc-cache -f "$FONT_DIR" >/dev/null
fi

log_success "DejaVu Sans Mono Nerd Font installed"
