{ lib, pkgs, config, ... }:
let
  cfg = config.services.mox-mail;
in {
  options.services.mox-mail = {
    enable = lib.mkEnableOption "Mox mail server";

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "mail.fullstacked.se";
      description = "Full hostname of the mail server, e.g. mail.example.com";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "fullstacked.se";
      description = "Primary mail domain";
    };

    publicIps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "143.14.50.130" ];
      description = "Public IP addresses for the mail server listener";
    };

    adminAccount = lib.mkOption {
      type = lib.types.str;
      default = "noor";
      description = "Mox admin account name (for postmaster, DMARC, TLSRPT delivery)";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "error" "info" "debug" "trace" "traceauth" "tracedata" ];
      default = "info";
      description = "Mox log level";
    };

    checkUpdates = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Mox update check every 24h";
    };

    internalIps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1" "172.18.0.1" "::1" ];
      description = "IPs for the internal Mox listener (web services)";
    };

    acme = {
      email = lib.mkOption {
        type = lib.types.str;
        default = "noor@latif.se";
        description = "Email address for ACME account registration";
      };
      cloudflareEnvFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/acme/fullstacked-cloudflare.env";
        description = "File with CLOUDFLARE_API_TOKEN for DNS-01 challenge";
      };
    };

    relay = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "relay.hostup.se";
        description = "SMTP relay hostname";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "SMTP relay port (STARTTLS)";
      };
    };

    mtastsMaxAge = lib.mkOption {
      type = lib.types.str;
      default = "336h0m0s";
      description = "MTA-STS policy max-age as Go duration (e.g. 336h0m0s for 2 weeks)";
    };

    dkimSelectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "2026a" "2026b" ];
      description = "DKIM selector names (must have matching private keys under dkim/)";
    };

    dkimSignSelectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "2026a" "2026b" ];
      description = "DKIM selectors used to sign outgoing mail";
    };

    dnsbls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "sbl.spamhaus.org" "bl.spamcop.net" ];
      description = "DNS blocklists for incoming spam filtering and outbound monitoring";
    };

    pangolin = {
      enable = lib.mkEnableOption "Pangolin/Traefik integration (copy certs for HTTPS, notify Traefik)";
      certsDir = lib.mkOption {
        type = lib.types.str;
        default = "/opt/pangolin/config/traefik/certs";
        description = "Directory for Traefik TLS certificates";
      };
      dynamicConfig = lib.mkOption {
        type = lib.types.str;
        default = "/opt/pangolin/config/traefik/dynamic_config.yml";
        description = "Path to Traefik dynamic config (touched to trigger reload)";
      };
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open mail ports in the firewall";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mox-mail.pangolin.enable = lib.mkDefault true;
  };

  imports = [
    ./firewall.nix
    ./seed-config.nix
    ./cert-renewal.nix
    ./systemd-service.nix
  ];
}
