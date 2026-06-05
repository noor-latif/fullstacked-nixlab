# Troubleshooting

## First Checks

```sh
. /home/noor/.config/opencode/fullstacked.env
systemctl status mox --no-pager
sudo -u mox sh -c 'cd /var/lib/mox && mox -config config/mox.conf config test'
ss -ltnp | grep -E ':(25|465|993|81|1080) '
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker logs pangolin --tail 80
sudo journalctl -u mox --no-pager -n 30
```

## Mox Won't Start — Config Parse Error

Symptom:

```text
parsing config/mox.conf:196: unknown key "DNSBLs"
```

Cause: sconf indentation is wrong — `DNSBLs:` must be inside the `SMTP:` block, not at listener level. Each nesting level = one tab.

Fix: verify indentation in `/var/lib/mox/config/mox.conf`. The correct structure:

```
		SMTP:
			Enabled: true
			DNSBLs:
				- sbl.spamhaus.org
				- bl.spamcop.net
```

If you edited via sed, tabs may have been lost. Use `cat -A` to see literal tabs (`^I`).

## Mox Must Be Started As Root

Symptom:

```text
mox must be started as root, and will drop privileges after binding required sockets
```

Cause: `serviceConfig.User` is set in the systemd unit. Mox starts as root and drops privileges using its `User:` config, not systemd's user switching.

Fix: the `modules/mox/systemd-service.nix` unit does NOT set `User=`. If someone adds it back, compare against `mox config printservice`. The service must run as root with capabilities for binding ports <1024.

## lego ACME Incompatibility

Symptom:

```text
accountDoesNotExist :: Unable to validate JWS
```

Cause: NixOS `security.acme` emits lego 4 CLI flags; lego 5 expects `lego run` subcommand with flags under it.

Fix: the flake overrides `pkgs.lego` to v5.2.2 and uses a dedicated systemd service (`mox-lego-cert.service`). Do not re-enable `security.acme.certs` for Mox domains.

## lego Production Fails But Staging Works

On this VPS, lego 5 staging succeeds, but production fails unless `--ipv4only` is set. Keep this flag in `modules/mox/cert-renewal.nix`.

Verify:

```sh
systemctl status mox-lego-cert.service --no-pager
systemctl status mox-lego-cert.timer --no-pager
```

Expected output on fresh check: `Skip renewal: The certificate expires ...`

## Traefik Serves Default Certificate For Mail Hostnames

Symptom: `openssl s_client -connect mail.fullstacked.se:443` shows `TRAEFIK DEFAULT CERT`.

Fix: verify `/opt/pangolin/config/traefik/dynamic_config.yml` contains the `tls.certificates` section, cert files exist at `/opt/pangolin/config/traefik/certs/`, then:

```sh
docker restart traefik
```

## Pangolin 504 To Mox Internal HTTP

Symptom: MTA-STS or autoconfig returns 504 through Pangolin, but direct localhost access works.

Check from Traefik's network:

```sh
docker exec traefik sh -c 'wget -qO- --header="Host: mta-sts.fullstacked.se" http://172.18.0.1:81/.well-known/mta-sts.txt'
```

If this fails, verify Mox is binding to 172.18.0.1:81 (not just 127.0.0.1:81):

```sh
ss -ltnp | grep :81
```

Should show 172.18.0.1:81, not just 127.0.0.1.

## Pangolin API Not Responding

Check:

```sh
docker exec pangolin sh -c 'curl -sS http://localhost:3003/v1/'
docker logs pangolin --tail 80 | grep -i 'integration\|api\|listen'
```

If not available, verify `/opt/pangolin/config/config.yml` has:

```yaml
flags:
  enable_integration_api: true
```

Then: `docker restart pangolin`.

API reference: `/opt/pangolin/config/openapi.yaml` — use this, not external docs, for exact schemas.

## Pangolin Resources Missing or Wrong

Run reconcile script:

```sh
/home/noor/dev/fullstacked-nixlab/scripts/pangolin-reconcile-mox-resources.sh
```

Or check manually:

```sh
. /home/noor/.config/opencode/fullstacked.env
curl -sS -H "Authorization: Bearer $PANGOLIN_API_TOKEN" \
  'http://localhost:3003/v1/org/fullstacked/resources?pageSize=100' | jq '.data.resources'
```

Expected: three resources (mail→1080 SSO=on, mta-sts→81 SSO=off, autoconfig→81 SSO=off).

## Cloudflare DNS Out of Sync

Run DNS script:

```sh
/home/noor/dev/fullstacked-nixlab/scripts/cloudflare-upsert-fullstacked-dns.sh
```

Verify:

```sh
. /home/noor/.config/opencode/fullstacked.env
curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones?name=fullstacked.se" | jq '.result[0].id'
```

All mail records must be DNS-only, not proxied (orange cloud off).

## Hostup Relay Not Working

Verify transport in `/var/lib/mox/config/mox.conf`:

```sconf
Transports:
	Hostup:
		Submission:
			Host: relay.hostup.se
			Port: 587
```

Verify route in `/var/lib/mox/config/domains.conf`:

```sconf
Routes:
	-
		Transport: Hostup
```

SPF must include: `include:spf.hostup.se`

Outbound relay uses IP whitelist auth, not SMTP AUTH.

## DNSSEC Warning in dnscheck

Mox warns: "DNS resolvers do not verify DNSSEC." Does not block startup. Hostup SmartDNSSEC handles DS record push automatically. Once active, verify with `delv fullstacked.se @1.1.1.1` (requires `bind` package).

## Config Divergence: Nix Module vs Runtime

If you edit Mox config via its web admin UI, the changes live at `/var/lib/mox/config/` and are NOT synced to the Nix module templates. `nixos-rebuild switch` will not overwrite them (seed-config has `ConditionPathExists`). To sync back:

1. Compare: diff `/var/lib/mox/config/mox.conf` against the generated template in the Nix store
2. Update the Nix module options in `modules/mox/default.nix` or the templates in `modules/mox/seed-config.nix`
3. Commit: `git add -A && git commit`
4. If you want fresh seed on next rebuild: `sudo rm /var/lib/mox/config/mox.conf`

## Mox Won't Auto-Start After Reboot

Verify the service is enabled:

```sh
systemctl is-enabled mox.service
```

Should show `enabled`. The service has `wantedBy = [ "multi-user.target" ]` in `systemd-service.nix`. If missing from /etc/nixos, it was likely edited away.

## Mox Seed-Config Skipped

The seed-config service is designed to skip if config exists. Check:

```sh
systemctl status mox-seed-config --no-pager
```

Expected: `Condition start unmet`. This is normal — it protects your runtime configs from being overwritten.

## Mox Logs

Mox logs go to journald (SyslogFacility=mail):

```sh
sudo journalctl -u mox --no-pager -n 50
sudo journalctl -u mox-lego-cert --no-pager -n 50
```

Log level is set in `/var/lib/mox/config/mox.conf` (`LogLevel: info`). Change to `debug` for troubleshooting, `error` for quiet production.
