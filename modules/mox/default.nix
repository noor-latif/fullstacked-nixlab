{ lib, pkgs, config, ... }:
let
  cfg = config.services.mox-mail;
in {
  options.services.mox-mail = {
    enable = lib.mkEnableOption "Mox mail server";

    hostname = lib.mkOption {
      type = lib.types.str;
      example = "mail.example.com";
      description = "Full hostname of the mail server, e.g. mail.example.com";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "example.com";
      description = "Primary mail domain";
    };

    publicIps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "203.0.113.1" ];
      description = "Public IP addresses for the mail server listener";
    };

    adminAccount = lib.mkOption {
      type = lib.types.str;
      example = "admin";
      description = "Mox admin account name (for postmaster, DMARC, TLSRPT delivery)";
    };

    certName = lib.mkOption {
      type = lib.types.str;
      default = "mail";
      description = "Name prefix for TLS certificate files and lego cert name";
    };

    certExtraDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "mta-sts.example.com" "autoconfig.example.com" ];
      description = "Additional SAN domains for the TLS certificate";
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
      default = [ "127.0.0.1" "::1" ];
      example = [ "127.0.0.1" "172.18.0.1" "::1" ];
      description = "IPs for the internal Mox listener (web services)";
    };

    acme = {
      email = lib.mkOption {
        type = lib.types.str;
        example = "admin@example.com";
        description = "Email address for ACME account registration";
      };
      dnsProvider = lib.mkOption {
        type = lib.types.str;
        default = "cloudflare";
        description = "Lego DNS provider name (cloudflare, route53, digitalocean, etc.)";
      };
      envFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/acme/cloudflare.env";
        description = "File with DNS provider API credentials for DNS-01 challenge";
      };
      legoExtraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "--ipv4only" ];
        description = "Extra flags passed to lego run";
      };
    };

    relay = {
      enable = lib.mkEnableOption "SMTP relay for outbound mail";
      transportName = lib.mkOption {
        type = lib.types.str;
        default = "Relay";
        description = "Transport name used in Mox config";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "relay.example.com";
        description = "SMTP relay hostname (required if relay is enabled)";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "SMTP relay port";
      };
    };

    mtastsMaxAge = lib.mkOption {
      type = lib.types.str;
      default = "336h0m0s";
      description = "MTA-STS policy max-age as Go duration";
    };

    dkimSelectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "2026a" ];
      description = "DKIM selector names (must have matching private keys under dkim/)";
    };

    dkimSignSelectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "2026a" ];
      description = "DKIM selectors used to sign outgoing mail (defaults to dkimSelectors)";
    };

    dnsbls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "sbl.spamhaus.org" "bl.spamcop.net" ];
      description = "DNS blocklists for incoming spam filtering and outbound monitoring";
    };

    pangolin = {
      enable = lib.mkEnableOption "Pangolin/Traefik integration (copy certs, notify Traefik)";
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
    services.mox-mail.pangolin.enable = lib.mkDefault false;
    services.mox-mail.relay.enable = lib.mkDefault false;
    services.mox-mail.dkimSignSelectors = lib.mkDefault cfg.dkimSelectors;
  };

  imports = [
    ./firewall.nix
    ./seed-config.nix
    ./cert-renewal.nix
    ./systemd-service.nix
  ];
}
