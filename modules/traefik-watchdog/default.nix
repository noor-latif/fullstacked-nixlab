{ lib, pkgs, config, ... }:
let
  cfg = config.services.traefikWatchdog;
in {
  options.services.traefikWatchdog = {
    enable = lib.mkEnableOption "Traefik/Gerbil netns split watchdog with auto-heal";

    traefikContainer = lib.mkOption {
      type = lib.types.str;
      default = "traefik";
      description = "Name of the Traefik docker container";
    };

    gerbilContainer = lib.mkOption {
      type = lib.types.str;
      default = "gerbil";
      description = "Name of the Gerbil docker container Traefik shares its netns with";
    };

    composeDir = lib.mkOption {
      type = lib.types.str;
      default = "/opt/pangolin";
      description = "Directory holding the Pangolin docker-compose.yml";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.traefik-watchdog = {
      description = "Recreate Traefik if orphaned from Gerbil network namespace";
      after = [ "docker.service" ];
      requires = [ "docker.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        UMask = "0077";
        NoNewPrivileges = true;
      };
      path = [ pkgs.docker pkgs.docker-compose pkgs.coreutils ];
      script = ''
        set -uo pipefail
        tpid=$(docker inspect ${cfg.traefikContainer} --format '{{.State.Pid}}' 2>/dev/null) \
          || { echo "traefik-watchdog: ${cfg.traefikContainer} missing, skip"; exit 0; }
        gpid=$(docker inspect ${cfg.gerbilContainer} --format '{{.State.Pid}}' 2>/dev/null) \
          || { echo "traefik-watchdog: ${cfg.gerbilContainer} missing, skip"; exit 0; }
        tns=$(readlink "/proc/$tpid/ns/net")
        gns=$(readlink "/proc/$gpid/ns/net")
        if [ "$tns" = "$gns" ]; then
          echo "traefik-watchdog: netns joined ($tns)"
          exit 0
        fi
        echo "traefik-watchdog: SPLIT traefik=$tns gerbil=$gns, recreating ${cfg.traefikContainer}"
        cd ${cfg.composeDir}
        docker compose up -d --force-recreate ${cfg.traefikContainer}
        sleep 10
        tpid=$(docker inspect ${cfg.traefikContainer} --format '{{.State.Pid}}')
        if [ "$(readlink "/proc/$tpid/ns/net")" != "$gns" ]; then
          echo "traefik-watchdog: heal FAILED, still split"
          exit 1
        fi
        echo "traefik-watchdog: healed"
      '';
    };

    systemd.timers.traefik-watchdog = {
      description = "Traefik/Gerbil netns split check every 5 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";
        Persistent = true;
      };
    };
  };
}
