#!/usr/bin/env bash
# Usage: ./scripts/load_test.sh YOUR-BUCKET 200
# Uploads N uniquely-named copies of the good sample file to test queue buffering.
set -euo pipefail

BUCKET="$1"
COUNT="${2:-200}"

for i in $(seq 1 "$COUNT"); do
  # The leading \n guarantees the new row starts on its own line, even when the
  # sample file has no trailing newline. Unique content per file also gives each
  # upload a unique ETag, otherwise the idempotency check would skip them.
  { cat sample-data/good_orders.csv; printf '\n9%s,C-99,LoadTest,1,1.00,2026-09-28\n' "$i"; } \
    | aws s3 cp - "s3://${BUCKET}/incoming/load_${i}.csv"
done