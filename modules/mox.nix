{ lib, pkgs, ... }:

let
  certName = "fullstacked-mail";
  legoStateDir = "/var/lib/mox-lego";
  moxTlsDir = "/var/lib/mox/config/tls";
  traefikTlsDir = "/opt/pangolin/config/traefik/certs";
  traefikDynamicConfig = "/opt/pangolin/config/traefik/dynamic_config.yml";
  moxCertFile = "${moxTlsDir}/fullstacked-mail-chain.pem";
  moxKeyFile = "${moxTlsDir}/fullstacked-mail-key.pem";
  traefikCertFile = "${traefikTlsDir}/fullstacked-mail-chain.pem";
  traefikKeyFile = "${traefikTlsDir}/fullstacked-mail-key.pem";
in {
  environment.systemPackages = with pkgs; [
    jq
    lego
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
    "d ${legoStateDir} 0700 root root -"
    "d ${moxTlsDir} 0750 root mox -"
    "d ${traefikTlsDir} 0755 root root -"
  ];

  systemd.services.mox-lego-cert = {
    description = "Issue and renew Mox mail certificate with lego DNS-01";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      UMask = "0027";
      Restart = "on-failure";
      RestartSec = "45s";
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        legoStateDir
        moxTlsDir
        traefikTlsDir
        traefikDynamicConfig
      ];
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [ "@system-service" ];
    };

    script = ''
      set -euo pipefail

      install -d -m 0700 ${legoStateDir}
      install -d -o root -g mox -m 0750 ${moxTlsDir}
      install -d -o root -g root -m 0755 ${traefikTlsDir}

      ${pkgs.lego}/bin/lego run \
        --server letsencrypt \
        --ipv4only \
        --ari-disable \
        --accept-tos \
        --email noor@latif.se \
        --dns cloudflare \
        --env-file /var/lib/acme/fullstacked-cloudflare.env \
        --path ${legoStateDir} \
        --cert.name ${certName} \
        --key-type EC256 \
        -d mail.fullstacked.se \
        -d mta-sts.fullstacked.se \
        -d autoconfig.fullstacked.se

      install -o root -g mox -m 0640 \
        ${legoStateDir}/certificates/${certName}.crt \
        ${moxCertFile}.new
      install -o root -g mox -m 0640 \
        ${legoStateDir}/certificates/${certName}.key \
        ${moxKeyFile}.new
      install -o root -g root -m 0644 \
        ${legoStateDir}/certificates/${certName}.crt \
        ${traefikCertFile}.new
      install -o root -g root -m 0640 \
        ${legoStateDir}/certificates/${certName}.key \
        ${traefikKeyFile}.new

      ${pkgs.openssl}/bin/openssl x509 -in ${moxCertFile}.new -noout >/dev/null
      ${pkgs.openssl}/bin/openssl pkey -in ${moxKeyFile}.new -noout >/dev/null
      ${pkgs.openssl}/bin/openssl x509 -in ${traefikCertFile}.new -noout >/dev/null
      ${pkgs.openssl}/bin/openssl pkey -in ${traefikKeyFile}.new -noout >/dev/null

      mv -f ${moxCertFile}.new ${moxCertFile}
      mv -f ${moxKeyFile}.new ${moxKeyFile}
      mv -f ${traefikCertFile}.new ${traefikCertFile}
      mv -f ${traefikKeyFile}.new ${traefikKeyFile}

      if [ -f ${traefikDynamicConfig} ]; then
        touch ${traefikDynamicConfig}
      fi

      if ${pkgs.systemd}/bin/systemctl is-active --quiet mox.service; then
        ${pkgs.systemd}/bin/systemctl reload-or-restart mox.service
      fi
    '';
  };

  systemd.timers.mox-lego-cert = {
    description = "Daily Mox mail certificate renewal check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "3h";
      Persistent = true;
      Unit = "mox-lego-cert.service";
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [
    25
    465
    587
    993
    1080
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
