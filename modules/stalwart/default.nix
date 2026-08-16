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
            submissions = { protocol = "smtp"; bind = [ "[::]:465" ]; tls = { implicit = true; }; };
            imaps = { protocol = "imap"; bind = [ "[::]:993" ]; tls = { implicit = true; }; };
            webadmin = { protocol = "http"; bind = [ cfg.webadminBind ]; };
          };
          # Acme is handled by the lego timer below; point at the written certs.
          # The cert block uses the %{file:...}% macro (NOT a plain path) so
          # Stalwart reads the PEM from disk — a literal path is treated as PEM
          # content and fails with "No certificates found", making implicit-TLS
          # listeners serve plaintext. `default = true` registers it as the
          # fallback cert. `certificate.*` must be in config.local-keys for the
          # macro to expand (per Stalwart discussion #2998 / #404).
          tls.certificate = "default";
        };

        certificate.default = {
          cert = "%{file:${tlsDir}/${certName}-chain.pem}%";
          private-key = "%{file:${tlsDir}/${certName}-key.pem}%";
          default = true;
        };

        # Forward salam@fullstacked.se -> noor.crystal@gmail.com at the SMTP
        # DATA stage (trusted system script, applies to unauthenticated inbound
        # mail). Pure forward: no local copy kept (avoids mailbox bloat).
        session.data.script = "'salam-forward'";
        sieve.trusted.scripts.salam-forward.contents = ''
          require ["envelope"];
          if address :is "To" "salam@fullstacked.se" {
              redirect "noor.crystal@gmail.com";
          }
        '';

        config = {
          local-keys = [ "certificate.*" "server.tls.*" ];
        };

        # First-run admin bootstrap. Stalwart creates this principal on first
        # boot if no principals exist. Use `mkpasswd -m sha-512 <pw>` to rotate.
        authentication.fallback-admin = {
          user = cfg.adminAccount;
          secret = cfg.adminPasswordHash;
        };

        # Outbound: relay everything (except local delivery) through Hostup,
        # matching the old Mox transport. IP-whitelist auth — no credentials.
        queue.route.hostup = {
          type = "relay";
          address = "relay.hostup.se";
          port = 587;
          protocol = "smtp";
          description = "Hostup outbound relay";
          tls = {
            implicit = false;
            allow-invalid-certs = false;
          };
        };
        queue.strategy.route = [
          { "if" = "is_local_domain('', rcpt_domain)"; "then" = "'local'"; }
          { "else" = "'hostup'"; }
        ];

        # DKIM: reuse the mox key material copied into tlsDir/dkim/ for
        # selectors 2026a/2026b (files are PKCS#8 PEM RSA 2048 keys).
        signature."2026a" = {
          domain = cfg.domain;
          selector = "2026a";
          private-key = "%{file:${tlsDir}/dkim/2026a._domainkey.${cfg.domain}.20260603T095354.rsa2048.privatekey.pkcs8.pem}%";
          headers = [ "From" "To" "Date" "Subject" "Message-ID" "MIME-Version" "Content-Type" "In-Reply-To" "References" ];
          algorithm = "rsa-sha256";
          canonicalization = "relaxed/relaxed";
          set-body-length = true;
          report = true;
        };
        signature."2026b" = {
          domain = cfg.domain;
          selector = "2026b";
          private-key = "%{file:${tlsDir}/dkim/2026b._domainkey.${cfg.domain}.20260603T095354.rsa2048.privatekey.pkcs8.pem}%";
          headers = [ "From" "To" "Date" "Subject" "Message-ID" "MIME-Version" "Content-Type" "In-Reply-To" "References" ];
          algorithm = "rsa-sha256";
          canonicalization = "relaxed/relaxed";
          set-body-length = true;
          report = true;
        };
      };
    };

    # DKIM keys are reused from mox: copy once into tlsDir/dkim/ (done by seed step).
    systemd.tmpfiles.rules = [
      "d ${tlsDir} 0750 stalwart stalwart -"
      "d ${tlsDir}/dkim 0750 stalwart stalwart -"
      # lego state dir must exist before systemd bind-mounts it for the cert
      # unit's ReadWritePaths (otherwise the unit dies with status=226/NAMESPACE).
      "d ${legoStateDir} 0700 stalwart stalwart -"
      # Cert files MUST be owned by the stalwart user (Stalwart rejects certs
      # not owned by its user even with 0644/0777 perms — Stalwart discussion
      # #2998). Enforce ownership via tmpfiles so the lego timer's copy sticks.
      "f ${tlsDir}/${cfg.certName}-chain.pem 0640 stalwart stalwart -"
      "f ${tlsDir}/${cfg.certName}-key.pem 0640 stalwart stalwart -"
      # Same ownership requirement for the reused mox DKIM keys (PKCS#8 PEM).
      "f ${tlsDir}/dkim/2026a._domainkey.${cfg.domain}.20260603T095354.rsa2048.privatekey.pkcs8.pem 0640 stalwart stalwart -"
      "f ${tlsDir}/dkim/2026b._domainkey.${cfg.domain}.20260603T095354.rsa2048.privatekey.pkcs8.pem 0640 stalwart stalwart -"
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
