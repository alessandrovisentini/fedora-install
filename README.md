# fedora-install

Fedora installer for a Sway desktop. Installs packages (dnf/flatpak/npm/pip),
clones the [dotfiles](https://github.com/alessandrovisentini/dotfiles) config,
and links it into `~/.config`.

## Quick install

Run on a Fedora machine:

```bash
curl -fsSL https://raw.githubusercontent.com/alessandrovisentini/fedora-install/main/install.sh | bash
```

It installs `git` if missing, clones this repo to
`~/Development/repos/fedora-install`, clones `dotfiles` to
`~/Development/repos/dotfiles`, installs packages, links `~/.config/*` and
`~/.claude/*`, and sources the shell env.

## What it does

1. **packages** — dnf (with RPM Fusion + COPR), flatpak, npm globals, pip user
2. **symlinks** — links `dotfiles/config/*` into `~/.config/*` and Claude config
3. **shell** — sources `config/shell/env.sh` from `.bashrc` / `.zshrc`
4. **post** — installs the DejaVu Sans Mono Nerd Font

## Running only some steps

```bash
./install/install.sh symlinks      # only recreate ~/.config symlinks
./install/install.sh packages      # only install software
./install/install.sh --help        # full step list
```
