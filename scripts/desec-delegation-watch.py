#!/usr/bin/env python3
"""Watch fullstacked.se delegation move HostUp -> DeSEC, mail on change.

Runs every 6h via desec-watch.timer (8 runs = 48h). Mails only on state
transitions: NS flipped, DS present, SUCCESS, or FAIL at run 8.
Secrets: none inside; STALWART_HEALTH_* come from ~/.secrets/fullstacked.env.
"""
import json
import os
import smtplib
import ssl
import subprocess
import sys
from email.message import EmailMessage

EXPECT_NS = {"ns1.desec.io.", "ns2.desec.org."}
EXPECT_DS_TAG = "56980"
EXPECT_DS_DIGEST = "3e698f3f65d249b336fa66c6a84a216c7aca0b344127686b1f507b4d84c3944d"
EXPECT_A = "143.14.50.130"
EXPECT_MX = "mail.fullstacked.se."
NOTIFY_TO = "noor.crystal@gmail.com"
MAX_RUNS = 8
STATE = os.path.expanduser("~/.cache/desec-watch.json")
RESOLVER = "1.1.1.1"


def dig(qtype, name, server=RESOLVER):
    try:
        out = subprocess.run(
            ["dig", "+short", qtype, name, "@" + server],
            capture_output=True, text=True, timeout=20,
        )
        return [l.strip() for l in out.stdout.splitlines() if l.strip()]
    except Exception:
        return []


def send(subject, body):
    env_file = os.path.expanduser("~/.secrets/fullstacked.env")
    vals = {}
    with open(env_file) as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                vals[k] = v
    frm = vals["STALWART_HEALTH_EMAIL"]
    m = EmailMessage()
    m["From"] = frm
    m["To"] = NOTIFY_TO
    m["Subject"] = subject
    m.set_content(body)
    ctx = ssl.create_default_context()
    s = smtplib.SMTP_SSL("mail.fullstacked.se", 465, context=ctx, timeout=30)
    s.ehlo()
    s.login(frm, vals["STALWART_HEALTH_PASSWORD"])
    s.send_message(m)
    s.quit()


def main():
    try:
        with open(STATE) as f:
            st = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        st = {"runs": 0, "mailed_ns": False, "mailed_ds": False, "mailed_done": False}
    if st["runs"] >= MAX_RUNS or st.get("mailed_done"):
        return 0
    st["runs"] += 1

    ns = set(dig("NS", "fullstacked.se"))
    ds = dig("DS", "fullstacked.se")
    a = dig("A", "fullstacked.se")
    mx = dig("MX", "fullstacked.se")
    ns_ok = EXPECT_NS <= ns
    ds_ok = any(
        EXPECT_DS_TAG in r and EXPECT_DS_DIGEST[:16].upper() in r.upper().replace(" ", "")
        for r in ds
    )
    rec_ok = EXPECT_A in a and any(EXPECT_MX in r for r in mx)

    NG = "desec-watch"
    if ns_ok and not st["mailed_ns"]:
        send(f"[{NG}] nameservers flipped to DeSEC",
             f"NS now: {sorted(ns)}\nDS yet: {bool(ds)}\nRun {st['runs']}/{MAX_RUNS}.")
        st["mailed_ns"] = True
    if ds_ok and not st["mailed_ds"]:
        send(f"[{NG}] DNSSEC DS back (DeSEC)",
             f"DS: {ds}\nRun {st['runs']}/{MAX_RUNS}. Chain should be green; verify at zonemaster.se.")
        st["mailed_ds"] = True
    if ns_ok and ds_ok and rec_ok and not st["mailed_done"]:
        send(f"[{NG}] SUCCESS: delegation complete and secure",
             f"NS: {sorted(ns)}\nDS: {ds}\nA: {a} MX: {mx}\nNext: wire Stalwart DnsServer/DeSEC.")
        st["mailed_done"] = True
    elif st["runs"] >= MAX_RUNS and not st.get("mailed_done"):
        send(f"[{NG}] FAIL: not green after 48h",
             f"NS: {sorted(ns)} (want {sorted(EXPECT_NS)})\nDS: {ds}\nA: {a} MX: {mx}\nManual fallback: paste DeSEC DS in HostUp portal.")
        st["mailed_done"] = True

    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        json.dump(st, f)
    print(f"run {st['runs']}: ns_ok={ns_ok} ds_ok={ds_ok} rec_ok={rec_ok}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
