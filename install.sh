#!/usr/bin/env bash
# Bootstrap entry for Fedora, invoked via `curl … | bash`. Ensures git,
# clones this repo, then hands off to install/install.sh (which also
# clones the dotfiles repo for the actual config files).

set -e

REPO_URL="https://github.com/alessandrovisentini/fedora-install.git"
TARGET_DIR="$HOME/Development/repos/fedora-install"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

if [[ ! -f /etc/os-release ]] || { . /etc/os-release; [[ "$ID" != "fedora" ]]; }; then
    log_error "This installer targets Fedora, which was not detected."
    exit 1
fi

if ! command -v git &>/dev/null; then
    log_info "Git not found. Installing git..."
    sudo dnf install -y git || { log_error "Failed to install git with dnf"; exit 1; }
    log_success "Git installed successfully"
fi

log_info "Creating directory structure..."
mkdir -p "$HOME/Development/repos"

if [[ -d "$TARGET_DIR/.git" ]]; then
    log_info "Repository exists at $TARGET_DIR. Updating..."
    git -C "$TARGET_DIR" pull --ff-only || log_warning "Failed to update repository. Continuing with existing files."
else
    log_info "Cloning fedora-install repository..."
    git clone "$REPO_URL" "$TARGET_DIR" || {
        log_error "Failed to clone repository. Check your internet connection."
        exit 1
    }
fi

chmod +x "$TARGET_DIR/install/install.sh" "$TARGET_DIR/install/install-fedora-nerd-font.sh"
exec "$TARGET_DIR/install/install.sh" "$@"
