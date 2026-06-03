{ pkgs, config, lib, ... }:
let
  cfg = config.services.mox-mail;

  tab = "\t";

  indent = n: builtins.concatStringsSep "" (builtins.genList (_: tab) n);

  sconfList = items: builtins.concatStringsSep "\n" (map (i: "${indent 4}- ${i}") items);

  moxConf = pkgs.writeText "mox.conf" ''
# NOTE: This config file is in 'sconf' format. Indent with tabs. Comments must be
# on their own line, they don't end a line. Do not escape or quote strings.
# Details: https://pkg.go.dev/github.com/mjl-/sconf.


# Directory where all data is stored, e.g. queue, accounts and messages, ACME TLS
# certs/keys. If this is a relative path, it is relative to the directory of
# mox.conf.
DataDir: ../data

# Default log level, one of: error, info, debug, trace, traceauth, tracedata.
# Trace logs SMTP and IMAP protocol transcripts, with traceauth also messages with
# passwords, and tracedata on top of that also the full data exchanges (full
# messages), which can be a large amount of data.
LogLevel: ${cfg.logLevel}

# User to switch to after binding to all sockets as root. Default: mox. If the
# value is not a known user, it is parsed as integer and used as uid and gid.
# (optional)
User: mox

# Full hostname of system, e.g. mail.<domain>
Hostname: ${cfg.hostname}

# If enabled, a single DNS TXT lookup of _updates.xmox.nl is done every 24h to
# check for a new release. Each time a new release is found, a changelog is
# fetched from https://updates.xmox.nl/changelog and delivered to the postmaster
# mailbox. (optional)
#
# RECOMMENDED: please enable to stay up to date
#
CheckUpdates: ${if cfg.checkUpdates then "true" else "false"}

# File containing hash of admin password, for authentication in the web admin
# pages (if enabled). (optional)
AdminPasswordFile: adminpasswd

# Listeners are groups of IP addresses and services enabled on those IP addresses,
# such as SMTP/IMAP or internal endpoints for administration or Prometheus
# metrics. All listeners with SMTP/IMAP services enabled will serve all configured
# domains. If the listener is named 'public', it will get a few helpful additional
# configuration checks, for acme automatic tls certificates and monitoring of ips
# in dnsbls if those are configured.
Listeners:
${indent 1}internal:
${indent 2}IPs:
${indent 3}- ${builtins.concatStringsSep "\n${indent 3}- " cfg.internalIps}
${indent 2}Hostname: localhost

${indent 2}AccountHTTP:
${indent 3}Enabled: true
${indent 3}Port: 1080
${indent 3}Forwarded: true

${indent 2}AdminHTTP:
${indent 3}Enabled: true
${indent 3}Port: 1080
${indent 3}Forwarded: true

${indent 2}WebmailHTTP:
${indent 3}Enabled: true
${indent 3}Port: 1080
${indent 3}Forwarded: true

${indent 2}WebAPIHTTP:
${indent 3}Enabled: true
${indent 3}Port: 1080
${indent 3}Forwarded: true

${indent 2}AutoconfigHTTPS:
${indent 3}Enabled: true
${indent 3}Port: 81
${indent 3}NonTLS: true

${indent 2}MTASTSHTTPS:
${indent 3}Enabled: true
${indent 3}Port: 81
${indent 3}NonTLS: true

${indent 2}WebserverHTTP:
${indent 3}Enabled: true
${indent 3}Port: 81

${indent 1}public:
${indent 2}IPs:
${indent 3}- ${builtins.concatStringsSep "\n${indent 3}- " cfg.publicIps}

${indent 2}TLS:
${indent 3}KeyCerts:
${indent 4}-
${indent 5}CertFile: tls/fullstacked-mail-chain.pem
${indent 5}KeyFile: tls/fullstacked-mail-key.pem

${indent 2}SMTP:
${indent 3}Enabled: true
${indent 3}DNSBLs:
${builtins.concatStringsSep "\n" (map (d: "${indent 4}- ${d}") cfg.dnsbls)}

${indent 2}Submissions:
${indent 3}Enabled: true

${indent 2}IMAPS:
${indent 3}Enabled: true

# Destination for emails delivered to postmaster addresses: a plain 'postmaster'
# without domain, 'postmaster@<hostname>' (also for each listener with SMTP
# enabled), and as fallback for each domain without explicitly configured
# postmaster destination.
Postmaster:
${indent 1}Account: ${cfg.adminAccount}
${indent 1}Mailbox: Postmaster

# Destination for per-host TLS reports (TLSRPT). TLS reports can be per recipient
# domain (for MTA-STS), or per MX host (for DANE). The per-domain TLS reporting
# configuration is in domains.conf. This is the TLS reporting configuration for
# this host. If absent, no host-based TLSRPT address is configured, and no host
# TLSRPT DNS record is suggested. (optional)
HostTLSRPT:
${indent 1}Account: ${cfg.adminAccount}
${indent 1}Mailbox: TLSRPT
${indent 1}Localpart: tlsreports

Transports:
${indent 1}Hostup:
${indent 2}Submission:
${indent 3}Host: ${cfg.relay.host}
${indent 3}Port: ${builtins.toString cfg.relay.port}
'';

  domainsConf = pkgs.writeText "domains.conf" ''
# NOTE: This config file is in 'sconf' format. Indent with tabs. Comments must be
# on their own line, they don't end a line. Do not escape or quote strings.
# Details: https://pkg.go.dev/github.com/mjl-/sconf.


# Domains for which email is accepted. For internationalized domains, use their
# IDNA names in UTF-8.
Domains:
${indent 1}${cfg.domain}:
${indent 2}ClientSettingsDomain: ${cfg.hostname}
${indent 2}LocalpartCatchallSeparator: +

${indent 2}DKIM:
${indent 3}Selectors:
${builtins.concatStringsSep "\n" (map (s: ''
${indent 4}${s}:
${indent 5}Expiration: 72h
${indent 5}PrivateKeyFile: dkim/${s}._domainkey.${cfg.domain}.rsa2048.privatekey.pkcs8.pem'') cfg.dkimSelectors)}
${indent 3}Sign:
${builtins.concatStringsSep "\n" (map (s: "${indent 4}- ${s}") cfg.dkimSignSelectors)}

${indent 2}DMARC:
${indent 3}Localpart: dmarcreports
${indent 3}Account: ${cfg.adminAccount}
${indent 3}Mailbox: DMARC

${indent 2}MTASTS:
${indent 3}Mode: enforce
${indent 3}MaxAge: ${cfg.mtastsMaxAge}
${indent 3}MX:
${indent 4}- ${cfg.hostname}

${indent 2}TLSRPT:
${indent 3}Localpart: tlsreports
${indent 3}Account: ${cfg.adminAccount}
${indent 3}Mailbox: TLSRPT

# Accounts represent mox users, each with a password and email address(es) to
# which email can be delivered (possibly at different domains). Each account has
# its own on-disk directory holding its messages and index database. An account
# name is not an email address.
Accounts:
${indent 1}${cfg.adminAccount}:
${indent 2}Domain: ${cfg.domain}
${indent 2}Destinations:
${indent 3}${cfg.adminAccount}@${cfg.domain}:
${indent 4}FullName: ${cfg.adminAccount}
${indent 2}SubjectPass:
${indent 3}Period: 12h0m0s
${indent 2}RejectsMailbox: Rejects
${indent 2}AutomaticJunkFlags:
${indent 3}Enabled: true
${indent 3}JunkMailboxRegexp: ^(junk|spam)
${indent 3}NeutralMailboxRegexp: ^(inbox|neutral|postmaster|dmarc|tlsrpt|rejects)
${indent 2}JunkFilter:
${indent 3}Threshold: 0.950000
${indent 3}Params:
${indent 4}Onegrams: true
${indent 4}MaxPower: 0.010000
${indent 4}TopWords: 10
${indent 4}IgnoreWords: 0.100000
${indent 4}RareWords: 2
${indent 2}NoCustomPassword: true

Routes:
${indent 1}-
${indent 2}Transport: Hostup

# DNS blocklists to periodically check with if IPs we send from are present,
# without using them for checking incoming deliveries. Also see DNSBLs in SMTP
# listeners in mox.conf, which specifies DNSBLs to use both for incoming
# deliveries and for checking our IPs against. (optional)
MonitorDNSBLs:
${builtins.concatStringsSep "\n" (map (d: "${indent 1}- ${d}") cfg.dnsbls)}
'';

in {
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.jq
      pkgs.lego
      pkgs.mox
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
      "d /var/lib/mox/config 0750 root mox -"
      "d /var/lib/mox-lego 0700 root root -"
      "d /var/lib/mox/config/tls 0750 root mox -"
    ] ++ lib.optionals cfg.pangolin.enable [
      "d ${cfg.pangolin.certsDir} 0755 root root -"
    ];

    systemd.services.mox-seed-config = {
      description = "Seed Mox config on first boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "mox.service" ];
      unitConfig.ConditionPathExists = "!/var/lib/mox/config/mox.conf";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -eu
        install -d -o root -g mox -m 0750 /var/lib/mox/config
        install -o root -g mox -m 0640 ${moxConf} /var/lib/mox/config/mox.conf
        install -o root -g mox -m 0640 ${domainsConf} /var/lib/mox/config/domains.conf
      '';
    };
  };
}
