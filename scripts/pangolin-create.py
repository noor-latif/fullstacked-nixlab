#!/usr/bin/env python3
"""Pangolin bridge-port helper.

Appends host ports (reachable ONLY via the Docker bridge / Pangolin) to
data/bridge-ports.json so the pangolin-bridge firewall module opens them.
This is the mechanism referenced by modules/pangolin-bridge/firewall.nix
(the `pangolin-create.py --persist` flow). Idempotent: a port already
present is left untouched and the file is not rewritten.

Usage:
    scripts/pangolin-create.py --persist-port 1080
    scripts/pangolin-create.py --persist-port 8080 --persist-port 9000
"""

import argparse
import json
import pathlib

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_PORTS_FILE = REPO_ROOT / "data" / "bridge-ports.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--persist-port",
        type=int,
        action="append",
        default=[],
        metavar="PORT",
        help="port to add to bridge-ports.json (repeatable)",
    )
    parser.add_argument(
        "--ports-file",
        type=pathlib.Path,
        default=DEFAULT_PORTS_FILE,
        help="path to bridge-ports.json (default: repo/data/bridge-ports.json)",
    )
    args = parser.parse_args()

    ports_file: pathlib.Path = args.ports_file
    ports = json.loads(ports_file.read_text()) if ports_file.exists() else []

    added = []
    for port in args.persist_port:
        if port not in ports:
            ports.append(port)
            added.append(port)

    if added:
        ports_file.write_text(json.dumps(ports) + "\n")
        print(f"added port(s) {added} -> {ports_file}")
    else:
        print(f"port(s) {args.persist_port} already present, no change: {ports_file}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
