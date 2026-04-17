#!/bin/bash

set -e

echo "=== IMMICH CLEANUP START ==="

DB_CONTAINER="immich_postgres"
SERVER_CONTAINER="immich_server"

TMP_DIR="/tmp/immich_fix"
mkdir -p "$TMP_DIR"

MISSING_DB="$TMP_DIR/db_paths.txt"
MISSING_FS="$TMP_DIR/missing_real.txt"
DELETE_LIST="$TMP_DIR/delete_uuids.txt"

echo "[1/5] Exporting DB paths..."

docker exec "$DB_CONTAINER" psql -U postgres -d immich -t -c "SELECT path FROM asset_file;" \
  | sed '/^\s*$/d' \
  | sort > "$MISSING_DB"

echo "DB paths: $(wc -l < "$MISSING_DB")"

echo "[2/5] Checking filesystem..."

docker exec "$SERVER_CONTAINER" bash -c "
find /data/upload -type f 2>/dev/null
" | sort > "$TMP_DIR/fs_paths.txt"

echo "Filesystem paths: $(wc -l < "$TMP_DIR/fs_paths.txt")"

echo "[3/5] Comparing..."

comm -23 "$MISSING_DB" "$TMP_DIR/fs_paths.txt" > "$MISSING_FS"

echo "Missing files: $(wc -l < "$MISSING_FS")"

echo "[4/5] Mapping to asset IDs..."

docker exec "$DB_CONTAINER" psql -U postgres -d immich -t -c "
SELECT af.\"assetId\"
FROM asset_file af
WHERE af.path IN (
$(sed "s/^/'/;s/$/'/" "$MISSING_FS" | paste -sd,)
);
" | sed '/^\s*$/d' | sort -u > "$DELETE_LIST"

echo "Assets to delete: $(wc -l < "$DELETE_LIST")"

echo "[5/5] DELETING..."

if [ ! -s "$DELETE_LIST" ]; then
  echo "Nothing to delete."
  exit 0
fi

docker exec "$DB_CONTAINER" psql -U postgres -d immich -c "
DELETE FROM asset
WHERE id IN (
  SELECT unnest(ARRAY[
$(sed "s/^/'/;s/$/'/" "$DELETE_LIST" | paste -sd,)
  ]::uuid[])
);
"

echo "=== DONE ==="
