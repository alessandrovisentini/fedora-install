#!/usr/bin/env bash
# auto-cpufreq picks the CPU governor/turbo automatically from load and power
# source. It isn't packaged for Fedora, so clone upstream and run its installer,
# then register the systemd daemon. power-profiles-daemon conflicts with it.
set -e

if ! command -v auto-cpufreq &>/dev/null; then
    tmp="$(mktemp -d)"
    git clone --depth 1 https://github.com/AdnanHodzic/auto-cpufreq.git "$tmp/auto-cpufreq"
    ( cd "$tmp/auto-cpufreq" && sudo ./auto-cpufreq-installer --install )
    rm -rf "$tmp"
fi

sudo systemctl disable --now power-profiles-daemon.service 2>/dev/null || true
sudo auto-cpufreq --install
