#!/usr/bin/env bash
# The one runnable check of the ledger: roles, prices and the config path.
# usage: test/budget.sh      (needs yq and jq, like the workflows)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export SPECIMEN=spec TELEMETRY_DIR="$tmp/tel" ANTFARM_CONFIG="$tmp/config.yml"
unset GITHUB_OUTPUT
mkdir -p "$tmp/tel/runs/spec/run-009/events"
cat > "$ANTFARM_CONFIG" <<'Y'
run: run-009
telemetry_repo: x/y
queen:  { model: claude-opus-5-5,   runs_per_day: 5 }
worker: { model: claude-sonnet-5-5, runs_per_day: 5 }
oracle: { model: claude-fable-5-1,  runs_per_day: 1 }
budget:
  weekly_cost_usd: 100
  assumed_cache_share: 0.70
  price_per_mtok:
    claude-sonnet-5-5: { input: 2, output: 10, cache_read: 0.20 }
    default:           { input: 5, output: 25, cache_read: 0.50 }
  weekly_tokens: 1000000000
day_utc_offset_hours: 0
Y
now=$(date -u +%FT%TZ)
ev() { # ev <role> <model> <out_tokens> <in_tokens>
  jq -cn --arg ts "$now" --arg r "$1" --arg m "$2" --argjson o "$3" --argjson i "$4" \
    '{schema_version:1,ts:$ts,run:"run-009",specimen:"spec",type:($r+".completed"),actor:{type:$r,model:$m},usage:{output_tokens:$o,input_tokens:$i}}'
}
{ ev queen claude-opus-5-5 1 0; ev worker claude-sonnet-5-5 1000000 0; ev oracle claude-fable-5-1 1 0; } \
  > "$tmp/tel/runs/spec/run-009/events/${now//[:-]/}_t.jsonl"

out=$(bash "$here/../antfarm/budget.sh" queen)
grep -q '^runs_today=1$' <<<"$out" || { echo "FAIL queen runs_today: $out"; exit 1; }
# 1M output tokens of sonnet-5-5 at 10 USD/MTok, plus three negligible events
grep -Eq '^cost_week=10(\.0+)?$' <<<"$out" || { echo "FAIL price per model: $out"; exit 1; }

set +e; out=$(bash "$here/../antfarm/budget.sh" oracle); rc=$?; set -e
[ "$rc" = 3 ] || { echo "FAIL oracle should be over runs_per_day (rc=$rc): $out"; exit 1; }
grep -q '^runs_today=1$' <<<"$out" || { echo "FAIL oracle runs_today: $out"; exit 1; }
echo "ok"
