{ pkgs, config, lib, ... }:
let
  cfg = config.services.mox-mail;
  certName = cfg.certName;
  legoStateDir = "/var/lib/mox-lego";
  moxTlsDir = "/var/lib/mox/config/tls";

  legoDomains = [ cfg.hostname ] ++ cfg.certExtraDomains;
  legoFlags = lib.concatStringsSep " " cfg.acme.legoExtraFlags;
  legoDomainArgs = lib.concatMapStringsSep " " (d: "-d ${d}") legoDomains;
in {
  config = lib.mkIf cfg.enable {
    systemd.services.mox-lego-cert = {
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
        ReadWritePaths = [
          legoStateDir
          moxTlsDir
        ] ++ lib.optionals cfg.pangolin.enable [
          cfg.pangolin.certsDir
          cfg.pangolin.dynamicConfig
        ];
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
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
      '' + lib.optionalString cfg.pangolin.enable ''
        install -d -o root -g root -m 0755 ${cfg.pangolin.certsDir}
      '' + ''

        ${pkgs.lego}/bin/lego run \
          --server letsencrypt \
          --accept-tos \
          --email ${cfg.acme.email} \
          --dns ${cfg.acme.dnsProvider} \
          --env-file ${cfg.acme.envFile} \
          --path ${legoStateDir} \
          --cert.name ${certName} \
          --key-type EC256 \
          ${legoFlags} \
          ${legoDomainArgs}

        install -o root -g mox -m 0640 \
          ${legoStateDir}/certificates/${certName}.crt \
          ${moxTlsDir}/${certName}-chain.pem.new
        install -o root -g mox -m 0640 \
          ${legoStateDir}/certificates/${certName}.key \
          ${moxTlsDir}/${certName}-key.pem.new
      '' + lib.optionalString cfg.pangolin.enable ''
        install -o root -g root -m 0644 \
          ${legoStateDir}/certificates/${certName}.crt \
          ${cfg.pangolin.certsDir}/${certName}-chain.pem.new
        install -o root -g root -m 0640 \
          ${legoStateDir}/certificates/${certName}.key \
          ${cfg.pangolin.certsDir}/${certName}-key.pem.new
      '' + ''

        ${pkgs.openssl}/bin/openssl x509 -in ${moxTlsDir}/${certName}-chain.pem.new -noout >/dev/null
        ${pkgs.openssl}/bin/openssl pkey -in ${moxTlsDir}/${certName}-key.pem.new -noout >/dev/null
      '' + lib.optionalString cfg.pangolin.enable ''
        ${pkgs.openssl}/bin/openssl x509 -in ${cfg.pangolin.certsDir}/${certName}-chain.pem.new -noout >/dev/null
        ${pkgs.openssl}/bin/openssl pkey -in ${cfg.pangolin.certsDir}/${certName}-key.pem.new -noout >/dev/null
      '' + ''

        mv -f ${moxTlsDir}/${certName}-chain.pem.new ${moxTlsDir}/${certName}-chain.pem
        mv -f ${moxTlsDir}/${certName}-key.pem.new ${moxTlsDir}/${certName}-key.pem
      '' + lib.optionalString cfg.pangolin.enable ''
        mv -f ${cfg.pangolin.certsDir}/${certName}-chain.pem.new ${cfg.pangolin.certsDir}/${certName}-chain.pem
        mv -f ${cfg.pangolin.certsDir}/${certName}-key.pem.new ${cfg.pangolin.certsDir}/${certName}-key.pem

        if [ -f ${cfg.pangolin.dynamicConfig} ]; then
          touch ${cfg.pangolin.dynamicConfig}
        fi
      '' + ''

        if ${pkgs.systemd}/bin/systemctl is-active --quiet mox.service; then
          ${pkgs.systemd}/bin/systemctl reload-or-restart mox.service
        fi
      '';
    };

    systemd.timers.mox-lego-cert = {
      description = "Daily mail certificate renewal check";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "3h";
        Persistent = true;
        Unit = "mox-lego-cert.service";
      };
    };
  };
}
