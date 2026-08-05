# Pangolin bridge module — binds host services reachable only via the Docker
# bridge (Pangolin/Traefik). See firewall.nix for the dynamic port design.
{ config, lib, pkgs, ... }:
{
  imports = [ ./firewall.nix ];
}
