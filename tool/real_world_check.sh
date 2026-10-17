#!/usr/bin/env bash
# Runs Sentinel against the official Flutter compass_app (pinned commit) with
# the flutter_official template and fails if findings grow beyond the known
# baseline — a regression guard for false positives on real code.
set -euo pipefail

SAMPLES_REV="5541c59ab8e9d7e74c1a35ef22bd43a487fc596c"
MAX_TOTAL=${MAX_TOTAL:-44}
MAX_ERRORS=${MAX_ERRORS:-2}

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone -q --filter=blob:none --sparse https://github.com/flutter/samples.git "$work/samples"
git -C "$work/samples" sparse-checkout set compass_app/app
git -C "$work/samples" checkout -q "$SAMPLES_REV"
app="$work/samples/compass_app/app"
cp "$root/example/templates/flutter_official.yaml" "$app/analyzer.yaml"

report="$work/report.json"
(cd "$root" && dart run bin/dart_sentinel.dart -p "$app" --no-report -f json > "$report" 2>/dev/null) || true

python3 - "$report" "$MAX_TOTAL" "$MAX_ERRORS" <<'PY'
import json, sys
issues = json.load(open(sys.argv[1]))["issues"]
total, errors = len(issues), sum(i["severity"] == "error" for i in issues)
print(f"compass_app: {total} findings, {errors} errors "
      f"(limits: {sys.argv[2]} / {sys.argv[3]})")
if total > int(sys.argv[2]) or errors > int(sys.argv[3]):
    sys.exit("findings grew — new false positives?")
PY
