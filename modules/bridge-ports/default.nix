# Bridge-ports module — opens Docker-bridge-scoped host ports (see firewall.nix).
# Needed by containers that reach host services via the bridge gateway 172.18.0.1.
{ config, lib, pkgs, ... }:
{
  imports = [ ./firewall.nix ];
}
