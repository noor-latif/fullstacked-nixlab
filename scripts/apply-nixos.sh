#!/usr/bin/env bash
set -euo pipefail

cd /home/noor/dev/pangolin-mailserver-vps
nix --extra-experimental-features 'nix-command flakes' build \
  --print-out-paths \
  '.#nixosConfigurations."nixos".config.system.build.toplevel' \
  --out-link result-system

exec sudo -S ./result-system/bin/switch-to-configuration switch
