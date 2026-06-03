{ pkgs, config, lib, ... }:
let
  cfg = config.services.mox-mail;
in {
  config = lib.mkIf cfg.enable {
    systemd.services.mox = {
      description = "Mox mail server";
      after = [ "network-online.target" "mox-seed-config.service" ];
      wants = [ "network-online.target" "mox-seed-config.service" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "/var/lib/mox/config/mox.conf";

      serviceConfig = {
        WorkingDirectory = "/var/lib/mox";
        ExecStart = "${pkgs.mox}/bin/mox -config /var/lib/mox/config/mox.conf serve";
        ExecStop = "${pkgs.mox}/bin/mox -config /var/lib/mox/config/mox.conf stop";
        UMASK = "0007";
        LimitNOFILE = 65535;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/var/lib/mox/config"
          "/var/lib/mox/data"
        ];
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        AmbientCapabilities = "";
        CapabilityBoundingSet = [
          "CAP_SETUID"
          "CAP_SETGID"
          "CAP_NET_BIND_SERVICE"
          "CAP_CHOWN"
          "CAP_FSETID"
          "CAP_DAC_OVERRIDE"
          "CAP_DAC_READ_SEARCH"
          "CAP_FOWNER"
          "CAP_KILL"
        ];
        NoNewPrivileges = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
          "AF_NETLINK"
        ];
        ProtectProc = "invisible";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RemoveIPC = true;
        ProtectHostname = true;
        ProtectClock = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        DevicePolicy = "closed";
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        Restart = "always";
        RestartSec = "5s";
        SyslogFacility = "mail";
      };
    };
  };
}
