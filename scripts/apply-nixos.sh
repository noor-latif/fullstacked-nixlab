#!/usr/bin/env bash
set -euo pipefail

cd /home/noor/dev/pangolin-mailserver-vps
exec sudo nixos-rebuild switch --flake .#nixos
