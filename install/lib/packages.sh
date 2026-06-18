#!/usr/bin/env bash

install_dnf_rpm_repos() {
    local json_file="$1" repos
    repos=$(get_json_array "$json_file" ".os.fedora.packages.dnf.rpm_repos")
    [[ -z "$repos" ]] && return 0

    while IFS= read -r repo_url; do
        [[ -z "$repo_url" ]] && continue
        # Expand $(rpm -E %fedora) etc.
        local expanded pkg_name
        expanded=$(eval echo "$repo_url")
        pkg_name=$(basename "$expanded" .noarch.rpm)
        if rpm -q "$pkg_name" &>/dev/null; then
            log_info "RPM repo already installed: $pkg_name"
        else
            log_info "Installing RPM repo: $expanded"
            sudo dnf install -y "$expanded" || log_warning "Failed to enable repo: $expanded"
        fi
    done <<< "$repos"
}

install_dnf_copr() {
    local json_file="$1" copr_repos
    copr_repos=$(get_json_array "$json_file" ".os.fedora.packages.dnf.copr")
    [[ -z "$copr_repos" ]] && return 0

    if ! dnf copr --help &>/dev/null; then
        log_info "Installing dnf copr plugin..."
        sudo dnf install -y dnf-plugins-core || log_warning "Failed to install dnf-plugins-core"
    fi

    while IFS= read -r copr; do
        [[ -z "$copr" ]] && continue
        local repo_file
        repo_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:$(echo "$copr" | tr '/' ':').repo"
        if [[ -f "$repo_file" ]]; then
            log_info "COPR already enabled: $copr"
        else
            log_info "Enabling COPR: $copr"
            sudo dnf copr enable -y "$copr" || log_warning "Failed to enable COPR: $copr"
        fi
    done <<< "$copr_repos"
}

install_packages_dnf() {
    local json_file="$1"

    install_dnf_rpm_repos "$json_file"
    install_dnf_copr "$json_file"

    local packages
    packages=$(get_json_array "$json_file" ".os.fedora.packages.dnf.packages")
    if [[ -z "$packages" ]]; then
        log_info "No dnf packages configured"
        return 0
    fi

    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if rpm -q "$pkg" &>/dev/null; then
            log_info "Package already installed: $pkg"
        else
            log_info "Installing package: $pkg"
            sudo dnf install -y "$pkg" || log_warning "Failed to install: $pkg"
        fi
    done <<< "$packages"
}

ensure_flatpak_and_remotes() {
    local json_file="$1"

    if ! command -v flatpak &>/dev/null; then
        log_info "Installing flatpak..."
        sudo dnf install -y flatpak || { log_warning "Failed to install flatpak"; return 1; }
    fi

    local remote_count
    remote_count=$(run_jq -r '.os.fedora.packages.flatpak.remotes | length // 0' "$json_file" 2>/dev/null)
    [[ -z "$remote_count" || "$remote_count" == "null" ]] && remote_count=0

    local i name url
    for ((i = 0; i < remote_count; i++)); do
        name=$(get_json_value "$json_file" ".os.fedora.packages.flatpak.remotes[$i].name")
        url=$(get_json_value  "$json_file" ".os.fedora.packages.flatpak.remotes[$i].url")
        [[ -z "$name" || -z "$url" ]] && continue
        log_info "Adding flatpak remote: $name ($url)"
        flatpak remote-add --if-not-exists --user "$name" "$url" \
            || log_warning "Failed to add flatpak remote: $name"
    done
}

install_packages_flatpak() {
    local json_file="$1"
    json_value_exists "$json_file" ".os.fedora.packages.flatpak" || return 0

    ensure_flatpak_and_remotes "$json_file" || return 0

    local packages
    packages=$(get_json_array "$json_file" ".os.fedora.packages.flatpak.packages")
    if [[ -z "$packages" ]]; then
        log_info "No flatpak packages configured"
    else
        while IFS= read -r app; do
            [[ -z "$app" ]] && continue
            if flatpak info --user "$app" &>/dev/null; then
                log_info "Flatpak already installed: $app"
            else
                log_info "Installing flatpak: $app"
                flatpak install --user -y --noninteractive flathub "$app" \
                    || log_warning "Failed to install flatpak: $app"
            fi
        done <<< "$packages"
    fi

    apply_flatpak_overrides "$json_file"
}

# Overrides (sockets, env vars, etc). Idempotent.
apply_flatpak_overrides() {
    local json_file="$1"
    json_value_exists "$json_file" ".os.fedora.packages.flatpak.overrides" || return 0

    local count
    count=$(run_jq -r '.os.fedora.packages.flatpak.overrides | length // 0' "$json_file" 2>/dev/null)
    [[ -z "$count" || "$count" == "null" ]] && count=0

    local i app
    for ((i = 0; i < count; i++)); do
        app=$(get_json_value "$json_file" ".os.fedora.packages.flatpak.overrides[$i].app")
        [[ -z "$app" ]] && continue

        local args=()
        while IFS= read -r a; do
            [[ -n "$a" ]] && args+=("$a")
        done <<< "$(get_json_array "$json_file" ".os.fedora.packages.flatpak.overrides[$i].args")"
        [[ ${#args[@]} -eq 0 ]] && continue

        log_info "Applying flatpak override: $app (${args[*]})"
        flatpak override --user "$app" "${args[@]}" \
            || log_warning "Failed to set flatpak override for $app"
    done
}

install_packages_npm() {
    local json_file="$1"
    json_value_exists "$json_file" ".os.fedora.packages.npm_global" || return 0

    if ! command -v npm &>/dev/null; then
        log_warning "npm not available; skipping npm_global packages"
        return 0
    fi

    local packages
    packages=$(get_json_array "$json_file" ".os.fedora.packages.npm_global")
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if npm list -g --depth=0 "$pkg" &>/dev/null; then
            log_info "npm global already installed: $pkg"
        else
            log_info "Installing npm global: $pkg"
            sudo npm install -g "$pkg" || log_warning "Failed to install npm: $pkg"
        fi
    done <<< "$packages"
}

install_packages_pip() {
    local json_file="$1"
    json_value_exists "$json_file" ".os.fedora.packages.pip_user" || return 0

    local pip_cmd=""
    if command -v pipx &>/dev/null; then
        pip_cmd="pipx install"
    elif command -v pip3 &>/dev/null; then
        pip_cmd="pip3 install --user --break-system-packages"
    elif command -v pip &>/dev/null; then
        pip_cmd="pip install --user --break-system-packages"
    else
        log_warning "pip not available; skipping pip_user packages"
        return 0
    fi

    local packages
    packages=$(get_json_array "$json_file" ".os.fedora.packages.pip_user")
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        log_info "Installing pip (user): $pkg"
        $pip_cmd "$pkg" || log_warning "Failed to install pip pkg: $pkg"
    done <<< "$packages"
}

install_fedora_packages() {
    local json_file="$1"

    if ! command -v dnf &>/dev/null; then
        log_error "dnf not found. This installer supports Fedora only."
        return 1
    fi

    install_packages_dnf     "$json_file"
    install_packages_flatpak "$json_file"
    install_packages_npm     "$json_file"
    install_packages_pip     "$json_file"
}
