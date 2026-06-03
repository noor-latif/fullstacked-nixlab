{ pkgs, config, lib, ... }:
let
  cfg = config.services.mox-mail;
in {
  config = lib.mkIf (cfg.enable && cfg.openFirewall) {
    networking.firewall.allowedTCPPorts = lib.mkAfter [
      25
      465
      587
      993
      1080
    ];
  };
}
