#!/usr/bin/env bash
set -euo pipefail
cd /home/noor/dev/fullstacked-nixlab
echo "→ nix flake update (nixlab)..."
nix flake update
echo "→ nix flake update (wrapper)..."
sudo nix flake update --flake /etc/nixos
echo "→ nixos-rebuild boot..."
sudo nixos-rebuild boot --flake /etc/nixos#nixos
echo "→ garbage collect (>7d)..."
sudo nix-collect-garbage --delete-older-than 7d
echo "Done. Reboot to activate: sudo reboot"
