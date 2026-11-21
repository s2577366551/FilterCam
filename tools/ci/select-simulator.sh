#!/usr/bin/env bash
set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json, sys

data = json.load(sys.stdin)["devices"]
for runtime in sorted(data, reverse=True):
    for device in data[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("no iPhone simulator available")
'
