{ pkgs, config, lib, ... }:
# Opens SMTP/IMAP/web ports via lib.mkAfter so they're appended after any
# user-defined firewall rules in configuration.nix.
let
  cfg = config.services.mox-mail;
in {
  config = lib.mkIf (cfg.enable && cfg.openFirewall) {
    networking.firewall.allowedTCPPorts = lib.mkAfter [
      25
      465
      993
      1080
    ];
    networking.firewall.allowedUDPPorts = lib.mkAfter [ ];
  };
}
