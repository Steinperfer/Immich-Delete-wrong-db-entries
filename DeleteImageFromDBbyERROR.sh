#!/bin/bash

echo "=== IMMICH CLEANUP: DELETE ORPHANED FILES (ON DISK BUT NOT IN DB) ==="

DB_CONTAINER="immich_postgres"
SERVER_CONTAINER="immich_server"
DISK_PATH="/mnt/ImageDB"
TMP_DIR="/tmp/immich_fix"
mkdir -p "$TMP_DIR"

DB_PATHS="$TMP_DIR/db_paths.txt"
FS_PATHS="$TMP_DIR/fs_paths.txt"
ORPHANED="$TMP_DIR/orphaned_files.txt"

echo "[1/4] Getting DB paths..."
docker exec "$DB_CONTAINER" psql -U postgres -d immich -t -c "SELECT path FROM asset_file;" | sed '/^\s*$/d' | sort > "$DB_PATHS"
echo "DB entries: $(wc -l < "$DB_PATHS")"

echo "[2/4] Getting filesystem paths from Immich container..."
docker exec "$SERVER_CONTAINER" bash -c "find /data/upload -type f 2>/dev/null" | sort > "$FS_PATHS"
echo "Files on disk: $(wc -l < "$FS_PATHS")"

echo "[3/4] Finding orphaned files (on disk but NOT in DB)..."
comm -13 "$DB_PATHS" "$FS_PATHS" > "$ORPHANED"
ORPHAN_COUNT=$(wc -l < "$ORPHANED")
echo "Orphaned files to delete: $ORPHAN_COUNT"

if [ "$ORPHAN_COUNT" -eq 0 ]; then
    echo "Nothing to delete."
    exit 0
fi

echo "[4/4] Deleting $ORPHAN_COUNT orphaned files from disk..."

# Process in batches of 100
cat "$ORPHANED" | xargs -L 100 | while read -r batch; do
    # Convert each path in batch to real filesystem path and delete
    for path in $batch; do
        real_file=$(echo "$path" | sed "s|^/data/|$DISK_PATH/|")
        if [ -f "$real_file" ]; then
            sudo rm "$real_file"
            echo -n "."
        fi
    done
done

echo -e "\n=== DONE: $ORPHAN_COUNT files deleted from disk ==="
echo "No database cleanup needed - these files had no DB entries."
