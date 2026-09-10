# Firewall rules for host services reachable ONLY via the Docker bridge.
# Reads the port list from data/bridge-ports.json at build
# time so a script can add ports without touching Nix syntax.
#
# Design rationale (see Research notes in SKILL.md):
#  * Containers reach host-bound ports through the bridge gateway 172.18.0.1.
#  * Rules are scoped to -s 172.18.0.0/16 so they are NOT exposed publicly.
#  * We use a DEDICATED chain (BRIDGE-PORTS) + extraStopCommands that flush
#    it, so rules are idempotent across `nixos-rebuild switch` — the known
#    pitfall with bare `extraCommands` (rules accumulate on every activation
#    and orphan when removed). NixOS nixpkgs issues + Nix Discourse both
#    recommend extraStopCommands for declarative teardown.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.bridge-ports;
  bridgeSubnet = "172.18.0.0/16";

  # Build-time data import: read the JSON port list and turn it into iptables
  # rules. This is the "Nix loads ports dynamically" pattern — the source of
  # truth is a plain JSON file the bridge-ports.py --persist-port flag appends to.
  portsFile = ../../data/bridge-ports.json;
  ports = builtins.fromJSON (builtins.readFile portsFile);
  validatePort = lib.assertMsg (builtins.all (p: lib.isInt p && p > 0 && p < 65536) ports)
    "bridge-ports: bridge-ports.json contains an invalid port (must be int 1..65535)";

  # iptables chain for bridge-scoped accepts.
  chain = "BRIDGE-PORTS";

  # One accept rule per port, jumped from INPUT.
  acceptRules = lib.concatMapStringsSep "\n" (port:
    ''iptables -w -A ${chain} -p tcp -s ${bridgeSubnet} --dport ${toString port} -j ACCEPT''
  ) ports;
in
{
  options.services.bridge-ports = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open Docker-bridge-scoped ports for container-reached host services.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [ { assertion = validatePort; message = "Invalid ports in ${portsFile}"; } ];

    networking.firewall = {
      # Flush + rebuild our chain on every activation, so rules never
      # accumulate and removed ports are actually torn down.
      extraStopCommands = ''
        iptables -w -D INPUT -j ${chain} 2>/dev/null || true
        iptables -w -F ${chain} 2>/dev/null || true
        iptables -w -X ${chain} 2>/dev/null || true
      '';
      extraCommands = ''
        iptables -w -N ${chain} 2>/dev/null || iptables -w -F ${chain}
        ${acceptRules}
        iptables -w -A INPUT -j ${chain}
      '';
    };
  };
}
