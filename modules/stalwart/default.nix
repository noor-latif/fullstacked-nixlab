{ lib, pkgs, config, ... }:
let
  cfg = config.services.stalwartSetup;

  # Stalwart 0.16 keeps its configuration in the datastore (JMAP objects edited
  # via the webadmin UI / stalwart-cli). The on-disk config only describes the
  # datastore. When this file is absent the server boots in bootstrap mode
  # (HTTP listener on STALWART_RECOVERY_MODE_PORT, setup wizard at /admin, temp
  # admin from STALWART_RECOVERY_ADMIN). Do not edit this path by hand.
  configJson = "/var/lib/stalwart/config.json";

  stateDir = "/var/lib/stalwart";
  cacheDir = "/var/cache/stalwart";

  adminEnvFile = "/etc/stalwart-admin.env";
  backupEnvFile = "/etc/stalwart-backup.env";

  listenPort = lib.last (lib.splitString ":" cfg.webadminBind);
in {
  options.services.stalwartSetup = {
    enable = lib.mkEnableOption "Stalwart mail server (0.16, DB-backed config)";

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

    adminAccount = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Bootstrap admin account name (used in STALWART_RECOVERY_ADMIN)";
    };

    webadminBind = lib.mkOption {
      type = lib.types.str;
      default = "172.18.0.1:1080";
      description = "Address:port for the Stalwart management HTTP listener (proxied by Traefik/Pangolin for mail.fullstacked.se)";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open mail ports in the firewall";
    };

    recoveryAdminEnvFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/stalwart-admin.env";
      description = "Env file (root:600) containing STALWART_RECOVERY_ADMIN=admin:<temp-password> for bootstrap mode. Optional; absent = random temp admin printed to stdout.";
    };

    backup = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable daily tar.gz backup of /var/lib/stalwart to S3";
      };
      s3Endpoint = lib.mkOption {
        type = lib.types.str;
        example = "https://s3.hostup.se";
        description = "S3-compatible endpoint URL";
      };
      s3Bucket = lib.mkOption {
        type = lib.types.str;
        example = "stalwart-mailserver";
        description = "S3 bucket name";
      };
      s3Region = lib.mkOption {
        type = lib.types.str;
        default = "eu-north-1";
        description = "S3 region";
      };
      keep = lib.mkOption {
        type = lib.types.int;
        default = 7;
        description = "Number of recent backups to keep";
      };
      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar value for the backup timer";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.stalwart = {
      isSystemUser = true;
      group = "stalwart";
      uid = 991;
      home = "/var/empty";
    };
    users.groups.stalwart = {
      gid = 989;
    };

    systemd.services.stalwart = {
      description = "Stalwart mail server (0.16)";
      # docker.service must be up first: the DB-configured webadmin listener
      # binds the Pangolin bridge IP (172.18.0.1). If we start before the
      # bridge exists, that bind fails silently and the process keeps running
      # without HTTP (SMTP survives - it binds *). Seen 2026-08-21 after a
      # reboot where stalwart started 6s before docker.
      after = [ "network-online.target" "docker.service" ];
      wants = [ "network-online.target" "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      # Never bounce a live MTA on nixos-rebuild switch; changes apply on
      # next restart/reboot. NOTE: unit-level option, NOT serviceConfig.*
      # (systemd rejects "restartIfChanged" inside [Service]).
      restartIfChanged = false;

      serviceConfig = {
        Type = "exec";
        ExecStart = "${pkgs.stalwart_0_16}/bin/stalwart --config=${configJson}";
        User = "stalwart";
        Group = "stalwart";
        StateDirectory = "stalwart";
        CacheDirectory = "stalwart";
        UMask = "0077";
        AmbientCapabilities = "CAP_NET_BIND_SERVICE";
        CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        LimitNOFILE = 65536;
        KillSignal = "SIGINT";
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = "5";
        # Optional bootstrap admin pin (root:600, not in the store).
        EnvironmentFile = [ "-${cfg.recoveryAdminEnvFile}" ];
        # Bootstrap HTTP port; only read in bootstrap/recovery mode.
        Environment = [ "STALWART_RECOVERY_MODE_PORT=${listenPort}" ];
        ReadWritePaths = [ stateDir cacheDir ];
      };
    };

    networking.firewall.allowedTCPPorts = lib.optionals cfg.openFirewall [ 25 465 993 ];

    environment.systemPackages = [
      pkgs.stalwart_0_16
      pkgs.stalwart-cli
      pkgs.openssl
      pkgs.bind.dnsutils
    ];

    # ---- S3 backup ----
    systemd.services.stalwart-backup = lib.mkIf cfg.backup.enable {
      description = "Backup Stalwart data dir to S3";
      after = [ "stalwart.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
        EnvironmentFile = [ "-${backupEnvFile}" ];
        ProtectSystem = "strict";
        ReadWritePaths = [ "/tmp" stateDir ];
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      };
      # gawk needed by the prune step below (missing => "awk: command not found",
      # broken pipe, backups never pruned).
      path = [ pkgs.awscli2 pkgs.gnutar pkgs.gzip pkgs.gawk pkgs.coreutils ];
      script = ''
        set -euo pipefail
        stampprefix="stalwart-$(date +%Y%m%d-%H%M%S)"
        tarball="/tmp/$stampprefix.tar.gz"
        trap 'rm -f "$tarball"' EXIT
        tar -czf "$tarball" -C ${stateDir} .
        ${pkgs.awscli2}/bin/aws --endpoint-url "$S3_ENDPOINT" s3 cp "$tarball" "s3://$S3_BUCKET/stalwart/$stampprefix.tar.gz"
        # Keep a fixed "latest" pointer so restores don't need to list keys.
        ${pkgs.awscli2}/bin/aws --endpoint-url "$S3_ENDPOINT" s3 cp "$tarball" "s3://$S3_BUCKET/stalwart/latest.tar.gz"
        # Prune to keep newest KEEP (default 7) timestamped backups (latest.tar.gz is excluded).
        mapfile -t all < <(${pkgs.awscli2}/bin/aws --endpoint-url "$S3_ENDPOINT" s3 ls "s3://$S3_BUCKET/stalwart/" \
          | awk '$4 ~ /^stalwart-[0-9]+/ {print $4}' | sort -r)
        if [[ ''${#all[@]} -gt ''${KEEP:-7} ]]; then
          for f in "''${all[@]:''${KEEP:-7}}"; do
            ${pkgs.awscli2}/bin/aws --endpoint-url "$S3_ENDPOINT" s3 rm "s3://$S3_BUCKET/stalwart/$f"
          done
        fi
      '';
    };

    systemd.timers.stalwart-backup = lib.mkIf cfg.backup.enable {
      description = "Daily Stalwart S3 backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.backup.schedule;
        RandomizedDelaySec = "30m";
        Persistent = true;
        Unit = "stalwart-backup.service";
      };
    };
  };

  meta.maintainers = with lib.maintainers; [ ];
}
