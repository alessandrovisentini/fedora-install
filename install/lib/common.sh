#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Every step this installer understands.
VALID_STEPS="symlinks packages shell post all"

# Args → INSTALL_STEPS. Unknown steps are fatal: a typo would otherwise
# skip every step and still print success.
parse_install_steps() {
    INSTALL_STEPS=()
    local rest=()
    for arg in "$@"; do
        if [[ " $VALID_STEPS " != *" $arg "* ]]; then
            log_error "Unknown step '$arg'. Valid steps: $VALID_STEPS"
            exit 64
        fi
        rest+=("$arg")
    done
    if [[ ${#rest[@]} -eq 0 ]]; then
        INSTALL_STEPS=("all")
    else
        INSTALL_STEPS=("${rest[@]}")
    fi
}

should_run() {
    local step="$1"
    for s in "${INSTALL_STEPS[@]}"; do
        [[ "$s" == "all" || "$s" == "$step" ]] && return 0
    done
    return 1
}

expand_vars() { eval echo "$1"; }

ensure_jq() {
    command -v jq &>/dev/null && return 0
    log_info "jq not found. Installing jq..."
    sudo dnf install -y jq || { log_error "Failed to install jq with dnf"; return 1; }
    log_success "jq installed successfully"
}

run_jq() { jq "$@"; }

get_json_value() { run_jq -r "$2" "$1"; }
get_json_array() { run_jq -r "$2 | .[]" "$1" 2>/dev/null; }
json_value_exists() {
    local value
    value=$(run_jq -r "$2 // empty" "$1" 2>/dev/null)
    [[ -n "$value" ]]
}

# Idempotent. Backs up an existing non-matching target before replacing.
create_symlink() {
    local source_path target_path backup
    source_path=$(expand_vars "$1")
    target_path=$(expand_vars "$2")
    backup="${3:-true}"

    if [[ ! -e "$source_path" ]]; then
        log_error "Source does not exist: $source_path"
        return 1
    fi

    mkdir -p "$(dirname "$target_path")"

    if [[ -L "$target_path" && "$(readlink "$target_path")" == "$source_path" ]]; then
        log_info "Symlink already exists: $target_path -> $source_path"
        return 0
    fi

    if [[ -e "$target_path" || -L "$target_path" ]]; then
        if [[ "$backup" == "true" ]]; then
            local backup_path
            backup_path="${target_path}.backup.$(date +%Y%m%d%H%M%S)"
            log_warning "Backing up existing: $target_path -> $backup_path"
            mv "$target_path" "$backup_path"
        else
            rm -rf "$target_path"
        fi
    fi

    ln -s "$source_path" "$target_path"
    log_success "Created symlink: $target_path -> $source_path"
}

run_post_install() {
    local json_file="$1" os="$2" commands
    commands=$(run_jq -r ".os.$os.post_install[]" "$json_file" 2>/dev/null)
    [[ -z "$commands" ]] && return 0

    log_info "Running post-install commands..."
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        log_info "Executing: $cmd"
        eval "$cmd"
    done <<< "$commands"
}

create_config_symlinks() {
    local json_file="$1" os="$2" repo_dir="$3"
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"

    mkdir -p "$config_dir"
    log_info "Creating config symlinks..."

    local folders=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && folders+=("$f")
    done < <(get_json_array "$json_file" ".os.$os.config_symlinks")

    if [[ ${#folders[@]} -eq 0 ]]; then
        log_info "No config symlinks to create for this selection"
        return 0
    fi

    for folder in "${folders[@]}"; do
        create_symlink "$repo_dir/config/$folder" "$config_dir/$folder"
    done
}

# Claude Code reads ~/.claude regardless of OS, so the same files link in
# everywhere. The source lives under config/claude in the dotfiles repo, but
# the target is ~/.claude, not ~/.config. Per-machine state
# (settings.local.json, .claude.json) stays put and is left untouched.
create_claude_symlinks() {
    local repo_dir="$1"
    local claude_dir="$HOME/.claude"

    log_info "Creating Claude config symlinks..."
    for file in settings.json CLAUDE.md; do
        create_symlink "$repo_dir/config/claude/$file" "$claude_dir/$file"
    done
}

_ensure_rc_sources_env() {
    local rcfile="$1" env_file="$2"
    if grep -q "source.*shell/env.sh" "$rcfile" 2>/dev/null; then
        log_info "Shell env already sourced in $rcfile"
        return
    fi
    log_info "Adding source line to $rcfile"
    {
        printf '\n# Dotfiles environment\n'
        printf '[ -f "%s" ] && source "%s"\n' "$env_file" "$env_file"
    } >> "$rcfile"
    log_success "Updated $rcfile"
}

setup_shell_env() {
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
    local env_file="$config_dir/shell/env.sh"

    if [[ ! -f "$env_file" ]]; then
        log_warning "Shell env file not found: $env_file"
        return 0
    fi

    log_info "Setting up shell environment sourcing..."

    local bashrc="$HOME/.bashrc"
    [[ -f "$bashrc" ]] && _ensure_rc_sources_env "$bashrc" "$env_file"

    local zshrc="$HOME/.zshrc"
    if [[ -f "$zshrc" || "$SHELL" == *"zsh"* ]]; then
        [[ ! -f "$zshrc" ]] && touch "$zshrc"
        _ensure_rc_sources_env "$zshrc" "$env_file"
    fi
}
