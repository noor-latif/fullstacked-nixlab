{ lib, pkgs, config, ... }:
let
  # NOTE: do NOT name this `services.stalwart-mail` — the upstream stalwart.nix
  # module registers a mkRenamedOptionModule that redirects the entire
  # services.stalwart-mail.* subtree to services.stalwart.*, which would land
  # our custom options on non-existent paths. Use a distinct name.
  cfg = config.services.stalwartSetup;
  certName = cfg.certName;
  legoStateDir = "/var/lib/stalwart-lego";
  tlsDir = cfg.tlsDir;
  lockFile = "${legoStateDir}/.lock";

  legoDomains = [ cfg.hostname ] ++ cfg.certExtraDomains;
  legoDomainArgs = lib.concatMapStringsSep " " (d: "-d ${d}") legoDomains;

  legoExtraFlags = lib.optionalString (cfg.acme.legoExtraFlags != [])
    " \\\n          ${lib.concatStringsSep " " cfg.acme.legoExtraFlags}";
  dnsWaitFlag = lib.optionalString (cfg.dnsPropagationWait != "")
    " \\\n          --dns.propagation-wait ${cfg.dnsPropagationWait}";
in {
  options.services.stalwartSetup = {
    enable = lib.mkEnableOption "Stalwart mail server (wraps services.stalwart)";

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
      description = "Public IP addresses for the mail server (informational / SPF)";
    };

    adminAccount = lib.mkOption {
      type = lib.types.str;
      example = "admin";
      description = "Stalwart admin account name";
    };

    adminPasswordHash = lib.mkOption {
      type = lib.types.str;
      example = "$6$rounds=656000$....";
      description = "sha512-crypt hash for the admin account (mkpasswd -m sha-512 <pw>). Used by authentication.fallback-admin for first-run bootstrap.";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/keys/stalwart_admin_password";
      description = "Path to a file containing the admin account password (written at seed time)";
    };

    certName = lib.mkOption {
      type = lib.types.str;
      default = "fullstacked-mail";
      description = "Name prefix for TLS certificate files and lego cert name";
    };

    tlsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/stalwart/config/tls";
      description = "Directory holding the server TLS cert/key and dkim/ keys";
    };

    certExtraDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = [ "mta-sts.example.com" "autoconfig.example.com" ];
      description = "Additional SAN domains for the TLS certificate";
    };

    webadminBind = lib.mkOption {
      type = lib.types.str;
      default = "172.18.0.1:1080";
      description = "Address:port for the Stalwart webadmin HTTP listener (proxied by Traefik/Pangolin for mail.fullstacked.se)";
    };

    acme = {
      email = lib.mkOption {
        type = lib.types.str;
        example = "admin@example.com";
        description = "Email address for ACME account registration";
      };
      server = lib.mkOption {
        type = lib.types.str;
        default = "letsencrypt";
        description = "Lego ACME server (letsencrypt, letsencrypt-staging, or custom URL)";
      };
      dnsProvider = lib.mkOption {
        type = lib.types.str;
        default = "cloudflare";
        description = "Lego DNS provider name (cloudflare, route53, digitalocean, etc.)";
      };
      envFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/acme/fullstacked-cloudflare.env";
        description = "File with DNS provider API credentials for DNS-01 challenge";
      };
      legoExtraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "--ipv4only" ];
        description = "Extra flags passed to lego run";
      };
    };

    dkimSelectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "2026a" "2026b" ];
      description = "DKIM selector names (must have matching private keys under tlsDir/dkim/)";
    };

    dkimKeyType = lib.mkOption {
      type = lib.types.str;
      default = "rsa2048";
      description = "DKIM key type used in private key filenames (e.g. rsa2048, ed25519)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open mail ports in the firewall";
    };

    dnsPropagationWait = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "30s";
      description = "Fixed wait time for DNS propagation before ACME validation (lego --dns.propagation-wait)";
    };

    traefik = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Copy renewed certs to the Traefik/Pangolin certs dir for webmail";
      };
      certsDir = lib.mkOption {
        type = lib.types.str;
        default = "/opt/pangolin/config/traefik/certs";
        description = "Directory for Traefik TLS certificates";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.stalwart = {
      enable = true;
      stateVersion = config.system.stateVersion;
      openFirewall = cfg.openFirewall;

      settings = {
        server = {
          hostname = cfg.hostname;
          # Implicit-TLS-only listeners (matches mox: 25/465/993). No STARTTLS 587.
          listener = {
            smtp = { protocol = "smtp"; bind = [ "[::]:25" ]; };
            submissions = { protocol = "smtp"; bind = [ "[::]:465" ]; tlsImplicit = true; };
            imaps = { protocol = "imap"; bind = [ "[::]:993" ]; tlsImplicit = true; };
            webadmin = { protocol = "http"; bind = [ cfg.webadminBind ]; };
          };
          # Acme is handled by the lego timer below; point at the written certs.
          tls.certificate = "default";
        };

        certificate.default = {
          cert = "${tlsDir}/${certName}-chain.pem";
          private-key = "${tlsDir}/${certName}-key.pem";
        };

        # Stalwart treats certificate.* as a DB key by default, which makes the
        # TOML certificate block above ignored (no cert loaded -> TLS listeners
        # serve plaintext). Declare it a local key so the on-disk cert is used.
        config = {
          local-keys = [ "certificate.*" "server.tls.*" ];
        };

        # First-run admin bootstrap. Stalwart creates this principal on first
        # boot if no principals exist. Use `mkpasswd -m sha-512 <pw>` to rotate.
        authentication.fallback-admin = {
          user = cfg.adminAccount;
          secret = cfg.adminPasswordHash;
        };
      };
    };

    # DKIM keys are reused from mox: copy once into tlsDir/dkim/ (done by seed step).
    systemd.tmpfiles.rules = [
      "d ${tlsDir} 0750 stalwart stalwart -"
      "d ${tlsDir}/dkim 0750 stalwart stalwart -"
    ];

    systemd.services.stalwart-lego-cert = {
      description = "Issue and renew mail certificates with lego DNS-01";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "45s";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ legoStateDir tlsDir ] ++ lib.optional cfg.traefik.enable cfg.traefik.certsDir;
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        # lego DNS-01 + flock subprocess need namespace ops; RestrictNamespaces=true
        # caused status=226/NAMESPACE and blocked nixos-rebuild switch.
        RestrictNamespaces = false;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
      };

      script = ''
        set -euo pipefail

        exec ${pkgs.util-linux}/bin/flock -n ${lockFile} ${pkgs.bash}/bin/bash -s <<'LEGO_SCRIPT'
        set -euo pipefail

        install -d -m 0700 ${legoStateDir}
        install -d -o root -g stalwart -m 0750 ${tlsDir}
      '' + lib.optionalString cfg.traefik.enable ''
        install -d -o root -g root -m 0755 ${cfg.traefik.certsDir}
      '' + ''

        ${pkgs.lego}/bin/lego run \
          --server ${cfg.acme.server} \
          --accept-tos \
          --email ${cfg.acme.email} \
          --dns ${cfg.acme.dnsProvider} \
          --env-file ${cfg.acme.envFile} \
          --path ${legoStateDir} \
          --cert.name ${certName} \
          --key-type EC256${legoExtraFlags}${dnsWaitFlag} \
          ${legoDomainArgs}

        install -o root -g stalwart -m 0640 \
          ${legoStateDir}/certificates/${certName}.crt \
          ${tlsDir}/${certName}-chain.pem.new
        install -o root -g stalwart -m 0640 \
          ${legoStateDir}/certificates/${certName}.key \
          ${tlsDir}/${certName}-key.pem.new
      '' + lib.optionalString cfg.traefik.enable ''
        install -o root -g root -m 0644 \
          ${legoStateDir}/certificates/${certName}.crt \
          ${cfg.traefik.certsDir}/${certName}-chain.pem.new
        install -o root -g root -m 0640 \
          ${legoStateDir}/certificates/${certName}.key \
          ${cfg.traefik.certsDir}/${certName}-key.pem.new
      '' + ''

        ${pkgs.openssl}/bin/openssl x509 -in ${tlsDir}/${certName}-chain.pem.new -noout >/dev/null
        ${pkgs.openssl}/bin/openssl pkey -in ${tlsDir}/${certName}-key.pem.new -noout >/dev/null
      '' + lib.optionalString cfg.traefik.enable ''
        ${pkgs.openssl}/bin/openssl x509 -in ${cfg.traefik.certsDir}/${certName}-chain.pem.new -noout >/dev/null
        ${pkgs.openssl}/bin/openssl pkey -in ${cfg.traefik.certsDir}/${certName}-key.pem.new -noout >/dev/null
      '' + ''

        mv -f ${tlsDir}/${certName}-chain.pem.new ${tlsDir}/${certName}-chain.pem
        mv -f ${tlsDir}/${certName}-key.pem.new ${tlsDir}/${certName}-key.pem
      '' + lib.optionalString cfg.traefik.enable ''
        mv -f ${cfg.traefik.certsDir}/${certName}-chain.pem.new ${cfg.traefik.certsDir}/${certName}-chain.pem
        mv -f ${cfg.traefik.certsDir}/${certName}-key.pem.new ${cfg.traefik.certsDir}/${certName}-key.pem
      '' + ''

        if ${pkgs.systemd}/bin/systemctl is-active --quiet stalwart.service; then
          ${pkgs.systemd}/bin/systemctl reload-or-restart stalwart.service
        fi
        LEGO_SCRIPT
      '';
    };

    systemd.timers.stalwart-lego-cert = {
      description = "Daily mail certificate renewal check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "3h";
        Persistent = true;
        Unit = "stalwart-lego-cert.service";
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ ];
}
