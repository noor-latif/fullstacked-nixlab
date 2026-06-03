{ lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    jq
    mox
  ];

  users.groups.mox = {};

  users.users.mox = {
    isSystemUser = true;
    group = "mox";
    home = "/var/lib/mox";
    createHome = true;
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/mox 0750 mox mox -"
  ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [
    25
    465
    587
    993
  ];

  systemd.services.mox = {
    description = "Mox mail server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    unitConfig.ConditionPathExists = "/var/lib/mox/config/mox.conf";

    serviceConfig = {
      WorkingDirectory = "/var/lib/mox";
      ExecStart = "${pkgs.mox}/bin/mox -config /var/lib/mox/config/mox.conf serve";
      ExecStop = "${pkgs.mox}/bin/mox -config /var/lib/mox/config/mox.conf stop";
      UMask = "0007";
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
}
