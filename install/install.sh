#!/usr/bin/env bash
# Fedora installer. Steps: symlinks, packages, shell, post, all.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
JSON_FILE="$SCRIPT_DIR/install.json"

source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

export DETECTED_OS="fedora"

show_help() {
    cat <<EOF
Usage: $(basename "$0") [step ...]

Run the Fedora installer. With no arguments, runs all steps.

Steps:
  symlinks   Create config symlinks (~/.config/*, ~/.claude/*) from dotfiles
  packages   Install software packages (dnf, flatpak, npm, pip)
  shell      Source config/shell/env.sh from .bashrc / .zshrc
  post       Run post-install commands
  all        Run everything (default)
EOF
}

for a in "$@"; do
    case "$a" in -h|--help) show_help; exit 0 ;; esac
done

parse_install_steps "$@"

log_info "Starting Fedora installation..."

ensure_jq

# Clone or update the dotfiles repo that holds the actual config files.
ensure_dotfiles() {
    local url target
    url=$(get_json_value "$JSON_FILE" ".dotfiles.url")
    target=$(expand_vars "$(get_json_value "$JSON_FILE" ".dotfiles.target_dir")")
    DOTFILES_DIR="$target"

    if [[ -d "$target/.git" ]]; then
        log_info "Updating dotfiles in $target..."
        git -C "$target" pull --ff-only || log_warning "Could not update dotfiles; using existing checkout."
    else
        log_info "Cloning dotfiles into $target..."
        mkdir -p "$(dirname "$target")"
        git clone "$url" "$target"
    fi
}

ensure_dotfiles

if should_run packages; then
    log_info "Installing packages..."
    install_fedora_packages "$JSON_FILE"
fi

should_run symlinks && create_config_symlinks "$JSON_FILE" fedora "$DOTFILES_DIR"
should_run symlinks && create_claude_symlinks "$DOTFILES_DIR"
should_run shell    && setup_shell_env
should_run post     && run_post_install       "$JSON_FILE" fedora

log_success "Fedora installation complete!"
