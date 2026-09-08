#!/usr/bin/env python3
"""Stalwart Assistant: Unified Email, Calendar, and Task automation over JMAP + CalDAV.

Works anywhere: locally on laptop, on NixLab, or driven by OMP. Stdlib only.
Usage:
  stalwart-assistant summary [--json]
  stalwart-assistant events [today|week|all] [--json]
  stalwart-assistant event-add <title> <start_iso> [duration_or_end] [--desc "..."]
  stalwart-assistant event-rm <id>
  stalwart-assistant todos [open|completed|all] [--json]
  stalwart-assistant todo-add <title> [--due "YYYY-MM-DD..."] [--priority 1-3]
  stalwart-assistant todo-done <uid>
  stalwart-assistant todo-rm <uid>
  stalwart-assistant triage [account] [--json]
  stalwart-assistant draft
  stalwart-assistant send
  stalwart-assistant schedule <to> <minutes> <subject> <text...>
  stalwart-assistant cancel <submission-id>
  stalwart-assistant listen
  stalwart-assistant sieve-list [account]
  stalwart-assistant sieve-put <name> <file> [--active] [account]
  stalwart-assistant sieve-del <id> [account]
"""
import base64
import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
import xml.etree.ElementTree as ET

# --- Configuration & Environment --------------------------------------------

ACCT_NOOR = "c"
ACCT_ADMIN = "b"
DEFAULT_USER = "noor@fullstacked.se"

SECRETS_PATHS = [
    os.path.expanduser("~/.secrets/fullstacked.env"),
    os.path.expanduser("~/.secrets/email-assistant.env"),
]

USING_BASE = [
    "urn:ietf:params:jmap:core",
    "urn:ietf:params:jmap:mail",
    "urn:ietf:params:jmap:calendars",
    "urn:ietf:params:jmap:submission",
]
SIEVE = "urn:ietf:params:jmap:sieve"
VACATION = "urn:ietf:params:jmap:vacationresponse"


def load_env():
    env = {}
    for p in SECRETS_PATHS:
        if os.path.exists(p):
            for line in open(p):
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip().strip('"').strip("'")
    # Also inherit from OS environment
    for k in ["STALWART_ADMIN_EMAIL", "STALWART_ADMIN_PASSWORD", "JMAP_PASSWORD", "STALWART_URL"]:
        if os.environ.get(k):
            env[k] = os.environ[k]
    return env


def detect_base_url(env):
    if env.get("STALWART_URL"):
        return env["STALWART_URL"].rstrip("/")
    # Check if local nixlab port 41209 is up (0.05s timeout)
    try:
        req = urllib.request.Request("http://127.0.0.1:41209/.well-known/jmap")
        with urllib.request.urlopen(req, timeout=0.08):
            return "http://127.0.0.1:41209"
    except Exception:
        pass
    return "https://mail.fullstacked.se"


def jmap_call(env, base_url, calls, extra=()):
    admin_user = env.get("STALWART_ADMIN_EMAIL", "admin@fullstacked.se")
    admin_pw = env.get("STALWART_ADMIN_PASSWORD", "")
    tok = base64.b64encode(f"{admin_user}:{admin_pw}".encode()).decode()
    req = urllib.request.Request(
        f"{base_url}/jmap/",
        data=json.dumps({"using": USING_BASE + list(extra), "methodCalls": calls}).encode(),
        headers={"Authorization": f"Basic {tok}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def jmap_resp(r, name):
    for m, body, _ in r["methodResponses"]:
        if m == name:
            return body
    raise KeyError(name)


def caldav_req(env, method, path, body=None, content_type=None, depth=None):
    base_url = "https://mail.fullstacked.se"
    user = DEFAULT_USER
    pw = env.get("JMAP_PASSWORD") or env.get("STALWART_ADMIN_PASSWORD")
    tok = base64.b64encode(f"{user}:{pw}".encode()).decode()

    headers = {"Authorization": f"Basic {tok}"}
    if content_type:
        headers["Content-Type"] = content_type
    if depth is not None:
        headers["Depth"] = str(depth)

    url = f"{base_url}{path}" if path.startswith("/") else f"{base_url}/{path}"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    return urllib.request.urlopen(req, timeout=15)


# --- Calendar Events (JMAP) --------------------------------------------------

def events_list(env, base_url, span="week", account=ACCT_NOOR):
    # Query events
    r = jmap_call(env, base_url, [["CalendarEvent/query", {"accountId": account}, "0"]])
    ids = jmap_resp(r, "CalendarEvent/query").get("ids", [])
    if not ids:
        return []

    r = jmap_call(
        env,
        base_url,
        [
            [
                "CalendarEvent/get",
                {
                    "accountId": account,
                    "ids": ids,
                    "properties": ["id", "title", "start", "duration", "description", "location", "uid"],
                },
                "0",
            ]
        ],
    )
    events = jmap_resp(r, "CalendarEvent/get").get("list", [])

    # Filter by date if span is today/week
    now = datetime.datetime.now(datetime.timezone.utc)
    today_str = now.strftime("%Y-%m-%d")

    filtered = []
    for ev in events:
        start = ev.get("start", "")
        if span == "today":
            if start.startswith(today_str):
                filtered.append(ev)
        elif span == "week":
            # Events in the next 7 days
            try:
                start_dt = datetime.datetime.fromisoformat(start.replace("Z", "+00:00"))
                if 0 <= (start_dt - now).total_seconds() <= 7 * 86400:
                    filtered.append(ev)
                elif start.startswith(today_str):
                    filtered.append(ev)
            except Exception:
                filtered.append(ev)
        else:
            filtered.append(ev)

    filtered.sort(key=lambda x: x.get("start", ""))
    return filtered


def event_add(env, base_url, title, start_iso, duration="PT1H", desc=None, loc=None, account=ACCT_NOOR):
    # Normalize start string
    if " " in start_iso and "T" not in start_iso:
        start_iso = start_iso.replace(" ", "T")
    if len(start_iso) == 16:  # YYYY-MM-DDTHH:MM
        start_iso += ":00"

    # Get default calendar ID
    r = jmap_call(env, base_url, [["Calendar/get", {"accountId": account}, "0"]])
    cals = jmap_resp(r, "Calendar/get").get("list", [])
    default_cal_id = next((c["id"] for c in cals if c.get("isDefault")), cals[0]["id"] if cals else "b")

    ev_data = {
        "@type": "Event",
        "calendarIds": {default_cal_id: True},
        "title": title,
        "start": start_iso,
        "duration": duration,
    }
    if desc:
        ev_data["description"] = desc
    if loc:
        ev_data["location"] = loc

    r = jmap_call(
        env,
        base_url,
        [
            [
                "CalendarEvent/set",
                {
                    "accountId": account,
                    "create": {"e1": ev_data},
                },
                "0",
            ]
        ],
    )
    res = jmap_resp(r, "CalendarEvent/set")
    created = res.get("created", {}).get("e1", {})
    if not created and res.get("notCreated"):
        raise RuntimeError(f"Event creation failed: {res['notCreated']}")
    return {"id": created.get("id"), "title": title, "start": start_iso, "duration": duration}


def event_rm(env, base_url, event_id, account=ACCT_NOOR):
    r = jmap_call(
        env,
        base_url,
        [["CalendarEvent/set", {"accountId": account, "destroy": [event_id]}, "0"]],
    )
    res = jmap_resp(r, "CalendarEvent/set")
    return {"destroyed": res.get("destroyed", [])}


# --- Tasks / Todos (CalDAV VTODO) -------------------------------------------

CALDAV_COLLECTION = "/dav/cal/noor%40fullstacked.se/default/"

def todos_list(env, status="open"):
    query = """<?xml version="1.0" encoding="utf-8" ?>
<C:calendar-query xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:prop>
    <C:calendar-data/>
  </D:prop>
  <C:filter>
    <C:comp-filter name="VCALENDAR">
      <C:comp-filter name="VTODO"/>
    </C:comp-filter>
  </C:filter>
</C:calendar-query>""".encode("utf-8")

    try:
        with caldav_req(env, "REPORT", CALDAV_COLLECTION, body=query, content_type="application/xml; charset=utf-8", depth=1) as resp:
            root = ET.fromstring(resp.read())
    except Exception as e:
        return []

    todos = []
    for r in root.findall("{DAV:}response"):
        href = r.findtext("{DAV:}href", "")
        caldata = r.findtext(".//{urn:ietf:params:xml:ns:caldav}calendar-data", "")
        if not caldata:
            continue

        item = {"href": href, "uid": "", "summary": "", "status": "NEEDS-ACTION", "due": "", "priority": ""}
        for line in caldata.splitlines():
            line = line.strip()
            if line.startswith("UID:"):
                item["uid"] = line[4:].strip()
            elif line.startswith("SUMMARY:"):
                item["summary"] = line[8:].strip()
            elif line.startswith("STATUS:"):
                item["status"] = line[7:].strip()
            elif line.startswith("DUE:"):
                item["due"] = line[4:].strip()
            elif line.startswith("PRIORITY:"):
                item["priority"] = line[9:].strip()

        if not item["uid"]:
            item["uid"] = href.split("/")[-1].replace(".ics", "")

        is_done = item["status"].upper() == "COMPLETED"
        if status == "open" and is_done:
            continue
        if status == "completed" and not is_done:
            continue

        todos.append(item)

    todos.sort(key=lambda x: (x.get("due") or "9999", x.get("priority") or "9"))
    return todos


def todo_add(env, summary, due_iso=None, priority=None):
    uid = uuid.uuid4().hex[:12]
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    vtodo = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Stalwart Assistant//EN",
        "BEGIN:VTODO",
        f"UID:{uid}",
        f"DTSTAMP:{now}",
        f"SUMMARY:{summary}",
        "STATUS:NEEDS-ACTION",
    ]
    if due_iso:
        clean_due = due_iso.replace("-", "").replace(":", "").replace(" ", "T")
        if "T" in clean_due and not clean_due.endswith("Z"):
            clean_due += "Z"
        vtodo.append(f"DUE:{clean_due}")
    if priority:
        vtodo.append(f"PRIORITY:{priority}")

    vtodo.extend(["END:VTODO", "END:VCALENDAR"])
    body = "\r\n".join(vtodo).encode("utf-8")

    path = f"{CALDAV_COLLECTION}{uid}.ics"
    with caldav_req(env, "PUT", path, body=body, content_type="text/calendar; charset=utf-8") as resp:
        if resp.status not in (200, 201, 204):
            raise RuntimeError(f"PUT failed: {resp.status}")

    return {"uid": uid, "summary": summary, "status": "NEEDS-ACTION", "due": due_iso or ""}


def todo_done(env, uid):
    # Fetch existing
    path = f"{CALDAV_COLLECTION}{uid}.ics"
    with caldav_req(env, "GET", path) as resp:
        caldata = resp.read().decode("utf-8", errors="replace")

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = []
    status_updated = False
    for line in caldata.splitlines():
        if line.startswith("STATUS:"):
            lines.append("STATUS:COMPLETED")
            status_updated = True
        else:
            lines.append(line)

    if not status_updated:
        # Insert before END:VTODO
        for i, l in enumerate(lines):
            if l.strip() == "END:VTODO":
                lines.insert(i, "STATUS:COMPLETED")
                break

    lines.insert(len(lines) - 2, f"COMPLETED:{now}")
    body = "\r\n".join(lines).encode("utf-8")

    with caldav_req(env, "PUT", path, body=body, content_type="text/calendar; charset=utf-8") as resp:
        if resp.status not in (200, 201, 204):
            raise RuntimeError(f"PUT failed: {resp.status}")

    return {"uid": uid, "status": "COMPLETED"}


def todo_rm(env, uid):
    path = f"{CALDAV_COLLECTION}{uid}.ics"
    with caldav_req(env, "DELETE", path) as resp:
        if resp.status not in (200, 204):
            raise RuntimeError(f"DELETE failed: {resp.status}")
    return {"destroyed": uid}


# --- Mail Functions (Preserved from email-assistant.py) ----------------------

def mailboxes(env, base_url, account):
    r = jmap_call(env, base_url, [["Mailbox/query", {"accountId": account}, "0"]])
    ids = jmap_resp(r, "Mailbox/query")["ids"]
    r = jmap_call(
        env,
        base_url,
        [
            [
                "Mailbox/get",
                {
                    "accountId": account,
                    "ids": ids,
                    "properties": ["id", "name", "role", "unreadEmails", "totalEmails"],
                },
                "1",
            ]
        ],
    )
    return jmap_resp(r, "Mailbox/get")["list"]


def triage(env, base_url):
    out = {}
    for account in (ACCT_NOOR, ACCT_ADMIN):
        boxes = mailboxes(env, base_url, account)
        out[account] = [
            (b.get("role") or b["name"], b["unreadEmails"], b["totalEmails"])
            for b in boxes
        ]
    return out


def draft(env, base_url):
    boxes = mailboxes(env, base_url, ACCT_NOOR)
    drafts = next(b["id"] for b in boxes if b.get("role") == "drafts")
    r = jmap_call(
        env,
        base_url,
        [
            [
                "Email/set",
                {
                    "accountId": ACCT_NOOR,
                    "create": {
                        "d1": {
                            "mailboxIds": {drafts: True},
                            "keywords": {"$draft": True},
                            "from": [{"email": "noor@fullstacked.se"}],
                            "to": [{"email": "noor@fullstacked.se"}],
                            "subject": "MVP draft - safe to delete",
                            "bodyStructure": {"partId": "t", "type": "text/plain"},
                            "bodyValues": {"t": {"value": "mvp draft proof"}},
                        }
                    },
                },
                "0",
            ]
        ],
    )
    did = jmap_resp(r, "Email/set")["created"]["d1"]["id"]
    r = jmap_call(env, base_url, [["Email/set", {"accountId": ACCT_NOOR, "destroy": [did]}, "1"]])
    return {"created": did, "destroyed": jmap_resp(r, "Email/set")["destroyed"]}


def send(env, base_url):
    boxes = mailboxes(env, base_url, ACCT_ADMIN)
    sent = next(b["id"] for b in boxes if b.get("role") == "sent")
    r = jmap_call(
        env,
        base_url,
        [["Identity/get", {"accountId": ACCT_ADMIN, "properties": ["id", "email"]}, "0"]],
    )
    ident = next(i["id"] for i in jmap_resp(r, "Identity/get")["list"] if "admin@" in i["email"])
    r = jmap_call(
        env,
        base_url,
        [
            [
                "Email/set",
                {
                    "accountId": ACCT_ADMIN,
                    "create": {
                        "m1": {
                            "mailboxIds": {sent: True},
                            "from": [{"email": "admin@fullstacked.se"}],
                            "to": [{"email": "admin@fullstacked.se"}],
                            "subject": "MVP ping",
                            "bodyStructure": {"partId": "t", "type": "text/plain"},
                            "bodyValues": {"t": {"value": "mvp send proof"}},
                        }
                    },
                },
                "0",
            ]
        ],
    )
    mid = jmap_resp(r, "Email/set")["created"]["m1"]["id"]
    r = jmap_call(
        env,
        base_url,
        [
            [
                "EmailSubmission/set",
                {
                    "accountId": ACCT_ADMIN,
                    "create": {
                        "s1": {
                            "emailId": mid,
                            "identityId": ident,
                            "envelope": {
                                "mailFrom": {"email": "admin@fullstacked.se"},
                                "rcptTo": [{"email": "admin@fullstacked.se"}],
                            },
                        }
                    },
                },
                "1",
            ]
        ],
    )
    sub = jmap_resp(r, "EmailSubmission/set")
    return {"submission": sub.get("created", sub), "emailId": mid}


def schedule(env, base_url, to, minutes, subject, text, sender="noor@fullstacked.se"):
    account = ACCT_NOOR if sender.startswith("noor@") else ACCT_ADMIN
    boxes = mailboxes(env, base_url, account)
    sent = next(b["id"] for b in boxes if b.get("role") == "sent")
    r = jmap_call(env, base_url, [["Identity/get", {"accountId": account}, "0"]])
    ident = next(i["id"] for i in jmap_resp(r, "Identity/get")["list"] if i["email"] == sender)
    future = (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
    r = jmap_call(
        env,
        base_url,
        [
            [
                "Email/set",
                {
                    "accountId": account,
                    "create": {
                        "m1": {
                            "mailboxIds": {sent: True},
                            "from": [{"email": sender}],
                            "to": [{"email": to}],
                            "subject": subject,
                            "bodyStructure": {"partId": "t", "type": "text/plain"},
                            "bodyValues": {"t": {"value": text}},
                        }
                    },
                },
                "1",
            ]
        ],
    )
    mid = jmap_resp(r, "Email/set")["created"]["m1"]["id"]
    r = jmap_call(
        env,
        base_url,
        [
            [
                "EmailSubmission/set",
                {
                    "accountId": account,
                    "create": {
                        "s1": {
                            "emailId": mid,
                            "identityId": ident,
                            "envelope": {
                                "mailFrom": {"email": sender, "parameters": {"HOLDUNTIL": future}},
                                "rcptTo": [{"email": to}],
                            },
                        }
                    },
                },
                "2",
            ]
        ],
    )
    created = jmap_resp(r, "EmailSubmission/set")["created"]["s1"]
    return {"submission": created["id"], "sendAt": created["sendAt"], "email": mid}


def cancel(env, base_url, submission, account=ACCT_ADMIN):
    r = jmap_call(
        env,
        base_url,
        [["EmailSubmission/set", {"accountId": account, "update": {submission: {"undoStatus": "canceled"}}}, "0"]],
    )
    return jmap_resp(r, "EmailSubmission/set")


def listen(env, base_url):
    import time
    def stamp():
        return datetime.datetime.now().astimezone().strftime("%H:%M:%S")

    admin_user = env.get("STALWART_ADMIN_EMAIL", "admin@fullstacked.se")
    admin_pw = env.get("STALWART_ADMIN_PASSWORD", "")
    tok = base64.b64encode(f"{admin_user}:{admin_pw}".encode()).decode()
    stream_auth = {"Authorization": f"Basic {tok}", "Accept": "text/event-stream"}

    seen = {}
    backoff = 5
    while True:
        try:
            req = urllib.request.Request(f"{base_url}/jmap/eventsource/?types=*&closeafter=no&ping=30", headers=stream_auth)
            with urllib.request.urlopen(req, timeout=90) as r:
                print(f"{stamp()} listening", flush=True)
                backoff = 5
                data = ""
                for raw in r:
                    line = raw.decode(errors="replace").strip()
                    if line.startswith("data:"):
                        data += line[5:].strip()
                    elif line == "" and data:
                        try:
                            changed = json.loads(data).get("changed", {})
                        except ValueError:
                            changed = {}
                        data = ""
                        if ACCT_NOOR in changed:
                            snap = json.dumps(changed[ACCT_NOOR], sort_keys=True)
                            if seen.get(ACCT_NOOR) != snap:
                                seen[ACCT_NOOR] = snap
                                print(json.dumps({"push": changed[ACCT_NOOR]}), flush=True)
        except Exception as ex:
            print(f"{stamp()} reconnect in {backoff}s: {type(ex).__name__}", flush=True)
            time.sleep(backoff)
            backoff = min(backoff * 2, 300)


def sieve_list(env, base_url, account=ACCT_NOOR):
    r = jmap_call(env, base_url, [["SieveScript/query", {"accountId": account}, "0"]], extra=[SIEVE])
    ids = jmap_resp(r, "SieveScript/query")["ids"]
    if not ids:
        return []
    r = jmap_call(env, base_url, [["SieveScript/get", {"accountId": account, "ids": ids}, "1"]], extra=[SIEVE])
    return jmap_resp(r, "SieveScript/get")["list"]


def sieve_put(env, base_url, name, path, account=ACCT_NOOR, active=False):
    admin_user = env.get("STALWART_ADMIN_EMAIL", "admin@fullstacked.se")
    admin_pw = env.get("STALWART_ADMIN_PASSWORD", "")
    tok = base64.b64encode(f"{admin_user}:{admin_pw}".encode()).decode()

    with open(path, "rb") as f:
        blob = f.read()
    req = urllib.request.Request(
        f"{base_url}/jmap/upload/{account}/",
        data=blob,
        headers={"Authorization": f"Basic {tok}", "Content-Type": "application/sieve"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        blob_id = json.load(r)["blobId"]

    r = jmap_call(
        env,
        base_url,
        [["SieveScript/set", {"accountId": account, "create": {"s1": {"name": name, "blobId": blob_id, "isActive": active}}}, "0"]],
        extra=[SIEVE],
    )
    return jmap_resp(r, "SieveScript/set")["created"]["s1"]


def sieve_del(env, base_url, sid, account=ACCT_NOOR):
    r = jmap_call(env, base_url, [["SieveScript/set", {"accountId": account, "destroy": [sid]}, "0"]], extra=[SIEVE])
    return jmap_resp(r, "SieveScript/set")["destroyed"]


# --- Unified Chief of Staff Summary -----------------------------------------

def summary(env, base_url):
    boxes = mailboxes(env, base_url, ACCT_NOOR)
    unread_mail = sum(b.get("unreadEmails", 0) for b in boxes if b.get("role") in ("inbox", None))
    evs = events_list(env, base_url, span="today")
    tds = todos_list(env, status="open")
    return {
        "unread_inbox": unread_mail,
        "events_today": evs,
        "todos_open": tds,
    }


# --- CLI Routing -------------------------------------------------------------

def print_table(headers, rows):
    if not rows:
        print("(none)")
        return
    col_widths = [len(h) for h in headers]
    for row in rows:
        for i, val in enumerate(row):
            col_widths[i] = max(col_widths[i], len(str(val)))
    fmt = "  ".join(f"{{:<{w}}}" for w in col_widths)
    print(fmt.format(*headers))
    print("  ".join("-" * w for w in col_widths))
    for row in rows:
        print(fmt.format(*[str(val) for val in row]))


def main():
    env = load_env()
    base_url = detect_base_url(env)

    args = sys.argv[1:]
    as_json = "--json" in args
    args = [a for a in args if a != "--json"]

    cmd = args[0] if args else "summary"

    if cmd in ("summary", "status"):
        res = summary(env, base_url)
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            print(f"=== STALWART ASSISTANT SUMMARY ({base_url}) ===")
            print(f"Unread Inbox: {res['unread_inbox']}")
            print("\nToday's Events:")
            ev_rows = [[e.get("start", ""), e.get("duration", ""), e.get("title", ""), e.get("id", "")] for e in res["events_today"]]
            print_table(["START", "DURATION", "TITLE", "ID"], ev_rows)
            print("\nOpen Todos:")
            td_rows = [[t.get("due") or "-", t.get("priority") or "-", t.get("summary", ""), t.get("uid", "")] for t in res["todos_open"]]
            print_table(["DUE", "PRIORITY", "SUMMARY", "UID"], td_rows)

    elif cmd == "events":
        span = args[1] if len(args) > 1 else "week"
        res = events_list(env, base_url, span=span)
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            rows = [[e.get("start", ""), e.get("duration", ""), e.get("title", ""), e.get("id", "")] for e in res]
            print_table(["START", "DURATION", "TITLE", "ID"], rows)

    elif cmd == "event-add":
        if len(args) < 3:
            print("Usage: stalwart-assistant event-add <title> <start_iso> [duration] [--desc '...']", file=sys.stderr)
            sys.exit(1)
        title = args[1]
        start = args[2]
        duration = args[3] if len(args) > 3 and not args[3].startswith("--") else "PT1H"
        desc = None
        if "--desc" in sys.argv:
            idx = sys.argv.index("--desc")
            if idx + 1 < len(sys.argv):
                desc = sys.argv[idx + 1]
        res = event_add(env, base_url, title, start, duration=duration, desc=desc)
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            print(f"[OK] Created Event: {res['title']} at {res['start']} (ID: {res['id']})")

    elif cmd == "event-rm":
        if len(args) < 2:
            print("Usage: stalwart-assistant event-rm <id>", file=sys.stderr)
            sys.exit(1)
        res = event_rm(env, base_url, args[1])
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            print(f"[OK] Destroyed Event: {args[1]}")

    elif cmd == "todos":
        status = args[1] if len(args) > 1 else "open"
        res = todos_list(env, status=status)
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            rows = [[t.get("due") or "-", t.get("priority") or "-", t.get("status", ""), t.get("summary", ""), t.get("uid", "")] for t in res]
            print_table(["DUE", "PRIORITY", "STATUS", "SUMMARY", "UID"], rows)

    elif cmd == "todo-add":
        if len(args) < 2:
            print("Usage: stalwart-assistant todo-add <summary> [--due 'YYYY-MM-DD...'] [--priority 1-3]", file=sys.stderr)
            sys.exit(1)
        summary_text = args[1]
        due = None
        prio = None
        if "--due" in sys.argv:
            idx = sys.argv.index("--due")
            if idx + 1 < len(sys.argv):
                due = sys.argv[idx + 1]
        if "--priority" in sys.argv:
            idx = sys.argv.index("--priority")
            if idx + 1 < len(sys.argv):
                prio = sys.argv[idx + 1]
        res = todo_add(env, summary_text, due_iso=due, priority=prio)
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            print(f"[OK] Created Todo: {res['summary']} (UID: {res['uid']})")

    elif cmd == "todo-done":
        if len(args) < 2:
            print("Usage: stalwart-assistant todo-done <uid>", file=sys.stderr)
            sys.exit(1)
        res = todo_done(env, args[1])
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            print(f"[OK] Marked Done: {res['uid']}")

    elif cmd == "todo-rm":
        if len(args) < 2:
            print("Usage: stalwart-assistant todo-rm <uid>", file=sys.stderr)
            sys.exit(1)
        res = todo_rm(env, args[1])
        if as_json:
            print(json.dumps(res, indent=2))
        else:
            print(f"[OK] Removed Todo: {res['destroyed']}")

    elif cmd == "triage":
        res = triage(env, base_url)
        print(json.dumps(res, indent=2) if as_json else json.dumps(res, indent=1))

    elif cmd == "draft":
        res = draft(env, base_url)
        print(json.dumps(res, indent=2))

    elif cmd == "send":
        res = send(env, base_url)
        print(json.dumps(res, indent=2))

    elif cmd == "schedule":
        if len(args) < 5:
            print("Usage: stalwart-assistant schedule <to> <minutes> <subject> <text...>", file=sys.stderr)
            sys.exit(1)
        to, minutes, subject = args[1], int(args[2]), args[3]
        text = " ".join(args[4:])
        res = schedule(env, base_url, to, minutes, subject, text)
        print(json.dumps(res, indent=2))

    elif cmd == "cancel":
        if len(args) < 2:
            print("Usage: stalwart-assistant cancel <submission-id> [account]", file=sys.stderr)
            sys.exit(1)
        acct = args[2] if len(args) > 2 else ACCT_ADMIN
        res = cancel(env, base_url, args[1], acct)
        print(json.dumps(res, indent=2))

    elif cmd == "listen":
        listen(env, base_url)

    elif cmd == "sieve-list":
        acct = args[1] if len(args) > 1 else ACCT_NOOR
        res = sieve_list(env, base_url, acct)
        print(json.dumps(res, indent=2))

    elif cmd == "sieve-put":
        active = "--active" in sys.argv
        p_args = [a for a in args[1:] if a != "--active"]
        name, path = p_args[0], p_args[1]
        acct = p_args[2] if len(p_args) > 2 else ACCT_NOOR
        res = sieve_put(env, base_url, name, path, acct, active)
        print(json.dumps(res, indent=2))

    elif cmd == "sieve-del":
        acct = args[2] if len(args) > 2 else ACCT_NOOR
        res = sieve_del(env, base_url, args[1], acct)
        print(json.dumps(res, indent=2))

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
