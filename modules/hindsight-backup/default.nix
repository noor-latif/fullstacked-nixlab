{ lib, pkgs, config, ... }:
let
  cfg = config.services.hindsightBackup;

  envFile = "/etc/hindsight-backup.env";
in {
  options.services.hindsightBackup = {
    enable = lib.mkEnableOption "daily Hindsight (docker) logical backup to S3";

    container = lib.mkOption {
      type = lib.types.str;
      default = "hindsight";
      description = "Name of the hindsight docker container";
    };

    s3Endpoint = lib.mkOption {
      type = lib.types.str;
      example = "https://s3.hostup.se";
    };

    s3Bucket = lib.mkOption {
      type = lib.types.str;
      example = "hindsight-backups";
    };

    s3Region = lib.mkOption {
      type = lib.types.str;
      default = "eu-north-1";
    };

    keep = lib.mkOption {
      type = lib.types.int;
      default = 7;
      description = "Number of timestamped backups to retain (latest.zip excluded)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hindsight-backup = {
      description = "Backup Hindsight database to S3";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
        EnvironmentFile = [ "-${envFile}" ];
        NoNewPrivileges = true;
      };
      path = [ pkgs.awscli2 pkgs.docker pkgs.coreutils ];
      script = ''
        set -euo pipefail
        stamp="hindsight-$(date +%Y%m%d-%H%M%S)"
        workdir="/tmp/hindsight-backup"
        zip="$workdir/$stamp.zip"
        mkdir -p "$workdir"
        trap 'rm -rf "$workdir"' EXIT
        docker exec ${cfg.container} hindsight-admin backup "/tmp/$stamp.zip"
        docker cp ${cfg.container}:/tmp/"$stamp".zip "$zip"
        docker exec ${cfg.container} rm -f "/tmp/$stamp.zip"
        aws --endpoint-url "$S3_ENDPOINT" s3 cp "$zip" "s3://$S3_BUCKET/hindsight/$stamp.zip"
        # Fixed latest pointer so restores don't need to list keys.
        aws --endpoint-url "$S3_ENDPOINT" s3 cp "$zip" "s3://$S3_BUCKET/hindsight/latest.zip"
        # Prune to newest KEEP timestamped backups.
        mapfile -t all < <(aws --endpoint-url "$S3_ENDPOINT" s3 ls "s3://$S3_BUCKET/hindsight/" \
          | awk '$4 ~ /^hindsight-[0-9]+/ {print $4}' | sort -r)
        if [[ ''${#all[@]} -gt ${toString cfg.keep} ]]; then
          for f in "''${all[@]:${toString cfg.keep}}"; do
            aws --endpoint-url "$S3_ENDPOINT" s3 rm "s3://$S3_BUCKET/hindsight/$f"
          done
        fi
      '';
    };

    systemd.timers.hindsight-backup = {
      description = "Daily Hindsight S3 backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}
