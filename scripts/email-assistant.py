#!/usr/bin/env python3
"""MVP email assistant: JMAP triage + draft + send proof. Stdlib only.

Runs ON nixlab (JMAP at localhost). Auth as admin, operates on account c
(noor@fullstacked.se) for read/draft, self-mail in b for send proof.
Usage: python3 mvp.py [triage|draft|send|schedule|all]
"""
import base64
import json
import sys
import urllib.request

BASE = "http://172.18.0.1:1080"
SECRETS = "/home/noor/.secrets/fullstacked.env"
ACCT_NOOR = "c"
ACCT_ADMIN = "b"


def load_env(path):
    env = {}
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def call(env, calls):
    tok = base64.b64encode(
        f'{env["STALWART_ADMIN_EMAIL"]}:{env["STALWART_ADMIN_PASSWORD"]}'.encode()
    ).decode()
    req = urllib.request.Request(
        BASE + "/jmap/",
        data=json.dumps(
            {
                "using": [
                    "urn:ietf:params:jmap:core",
                    "urn:ietf:params:jmap:mail",
                    "urn:ietf:params:jmap:submission",
                ],
                "methodCalls": calls,
            }
        ).encode(),
        headers={"Authorization": "Basic " + tok, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)


def resp(r, name):
    for m, body, _ in r["methodResponses"]:
        if m == name:
            return body
    raise KeyError(name)


def mailboxes(env, account):
    r = call(env, [["Mailbox/query", {"accountId": account}, "0"]])
    ids = resp(r, "Mailbox/query")["ids"]
    r = call(
        env,
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
    return resp(r, "Mailbox/get")["list"]


def triage(env):
    out = {}
    for account in (ACCT_NOOR, ACCT_ADMIN):
        boxes = mailboxes(env, account)
        out[account] = [
            (b.get("role") or b["name"], b["unreadEmails"], b["totalEmails"])
            for b in boxes
        ]
    return out


def draft(env):
    boxes = mailboxes(env, ACCT_NOOR)
    drafts = next(b["id"] for b in boxes if b.get("role") == "drafts")
    r = call(
        env,
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
                            "bodyStructure": {
                                "partId": "t",
                                "type": "text/plain",
                            },
                            "bodyValues": {"t": {"value": "mvp draft proof"}},
                        }
                    },
                },
                "0",
            ]
        ],
    )
    did = resp(r, "Email/set")["created"]["d1"]["id"]
    r = call(env, [["Email/set", {"accountId": ACCT_NOOR, "destroy": [did]}, "1"]])
    return {"created": did, "destroyed": resp(r, "Email/set")["destroyed"]}


def send(env):
    boxes = mailboxes(env, ACCT_ADMIN)
    sent = next(b["id"] for b in boxes if b.get("role") == "sent")
    r = call(
        env,
        [
            [
                "Identity/get",
                {"accountId": ACCT_ADMIN, "properties": ["id", "email"]},
                "0",
            ]
        ],
    )
    ident = next(
        i["id"] for i in resp(r, "Identity/get")["list"] if "admin@" in i["email"]
    )
    r = call(
        env,
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
    mid = resp(r, "Email/set")["created"]["m1"]["id"]
    r = call(
        env,
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
    sub = resp(r, "EmailSubmission/set")
    r = call(
        env,
        [
            [
                "Email/query",
                {
                    "accountId": ACCT_ADMIN,
                    "filter": {"subject": "MVP ping"},
                    "limit": 5,
                },
                "2",
            ]
        ],
    )
    return {"submission": sub.get("created", sub), "found": resp(r, "Email/query")["ids"]}


def schedule(env, to, subject, text, minutes, sender="noor@fullstacked.se"):
    """Native future release via RFC 4865 HOLDUNTIL. Returns submission id."""
    import datetime
    account = ACCT_NOOR if sender.startswith("noor@") else ACCT_ADMIN
    boxes = mailboxes(env, account)
    sent = next(b["id"] for b in boxes if b.get("role") == "sent")
    r = call(env, [["Identity/get", {"accountId": account}, "0"]])
    ident = next(i["id"] for i in resp(r, "Identity/get")["list"] if i["email"] == sender)
    future = (
        datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=minutes)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")
    r = call(
        env,
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
    mid = resp(r, "Email/set")["created"]["m1"]["id"]
    r = call(
        env,
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
                                "mailFrom": {
                                    "email": sender,
                                    "parameters": {"HOLDUNTIL": future},
                                },
                                "rcptTo": [{"email": to}],
                            },
                        }
                    },
                },
                "2",
            ]
        ],
    )
    created = resp(r, "EmailSubmission/set")["created"]["s1"]
    return {"submission": created["id"], "sendAt": created["sendAt"], "email": mid}


def cancel(env, submission, account=ACCT_ADMIN):
    r = call(
        env,
        [
            [
                "EmailSubmission/set",
                {"accountId": account, "update": {submission: {"undoStatus": "canceled"}}},
                "0",
            ]
        ],
    )
    return resp(r, "EmailSubmission/set")


if __name__ == "__main__":
    env = load_env(SECRETS)
    what = sys.argv[1] if len(sys.argv) > 1 else "triage"
    if what in ("triage", "all"):
        print(json.dumps({"triage": triage(env)}, indent=1))
    if what in ("draft", "all"):
        print(json.dumps({"draft": draft(env)}, indent=1))
    if what in ("send", "all"):
        print(json.dumps({"send": send(env)}, indent=1))
    if what == "schedule":
        # schedule <to> <minutes> <subject> <text...>
        to, minutes, subject = sys.argv[2], int(sys.argv[3]), sys.argv[4]
        print(json.dumps({"schedule": schedule(env, to, subject, " ".join(sys.argv[5:]), minutes)}, indent=1))
    if what == "cancel":
        # cancel <submission-id> [account]
        acct = sys.argv[3] if len(sys.argv) > 3 else ACCT_ADMIN
        print(json.dumps({"cancel": cancel(env, sys.argv[2], acct)}, indent=1))
