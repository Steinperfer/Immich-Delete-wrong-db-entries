#!/bin/bash

echo "=== IMMICH CLEANUP: DELETE ALL ORPHANED (DISK + DB) ==="

DB_CONTAINER="immich_postgres"
SERVER_CONTAINER="immich_server"
DISK_PATH="/mnt/ImageDB"
TMP_DIR="/tmp/immich_fix"
mkdir -p "$TMP_DIR"

DB_PATHS="$TMP_DIR/db_paths.txt"
FS_PATHS="$TMP_DIR/fs_paths.txt"
ON_DISK_NOT_DB="$TMP_DIR/on_disk_not_db.txt"
IN_DB_NOT_DISK="$TMP_DIR/in_db_not_disk.txt"

echo "[1/5] Getting DB paths..."
docker exec "$DB_CONTAINER" psql -U postgres -d immich -t -c "SELECT path FROM asset_file;" | sed '/^\s*$/d' | sort > "$DB_PATHS"
echo "DB entries: $(wc -l < "$DB_PATHS")"

echo "[2/5] Getting filesystem paths..."
docker exec "$SERVER_CONTAINER" bash -c "find /data/upload -type f 2>/dev/null" | sort > "$FS_PATHS"
echo "Files on disk: $(wc -l < "$FS_PATHS")"

echo "[3/5] Finding orphaned files on disk (ON disk but NOT in DB)..."
comm -13 "$DB_PATHS" "$FS_PATHS" > "$ON_DISK_NOT_DB"
DISK_ORPHANS=$(wc -l < "$ON_DISK_NOT_DB")
echo "Files to delete from disk: $DISK_ORPHANS"

echo "[4/5] Finding orphaned DB entries (IN DB but NOT on disk)..."
comm -23 "$DB_PATHS" "$FS_PATHS" > "$IN_DB_NOT_DISK"
DB_ORPHANS=$(wc -l < "$IN_DB_NOT_DISK")
echo "DB entries to delete: $DB_ORPHANS"

echo "[5/5] DELETING..."

# Delete files on disk without DB entry
if [ "$DISK_ORPHANS" -gt 0 ]; then
    echo "Deleting $DISK_ORPHANS files from disk..."
    while read -r path; do
        real_file=$(echo "$path" | sed "s|^/data|$DISK_PATH|")
        if [ -f "$real_file" ]; then
            sudo rm "$real_file"
            echo -n "."
        fi
    done < "$ON_DISK_NOT_DB"
    echo ""
fi

# Delete DB entries without file on disk
if [ "$DB_ORPHANS" -gt 0 ]; then
    echo "Deleting $DB_ORPHANS DB entries..."
    cat "$IN_DB_NOT_DISK" | xargs -L 100 | while read -r batch; do
        formatted_paths=$(echo "$batch" | sed "s/ /','/g; s/^/'/; s/$/'/")
        ids=$(docker exec "$DB_CONTAINER" psql -U postgres -d immich -t -c "SELECT \"assetId\" FROM asset_file WHERE path IN ($formatted_paths);" | sed '/^\s*$/d')
        if [ ! -z "$ids" ]; then
            id_batch=$(echo "$ids" | sed "s/ /','/g; s/^/'/; s/$/'/")
            docker exec "$DB_CONTAINER" psql -U postgres -d immich -c "DELETE FROM stack WHERE \"primaryAssetId\" IN ($id_batch);" >/dev/null 2>&1 || true
            docker exec "$DB_CONTAINER" psql -U postgres -d immich -c "DELETE FROM asset WHERE id IN ($id_batch);" >/dev/null 2>&1 || true
            echo -n "!"
        fi
    done
    echo ""
fi

echo "=== DONE ==="
echo "Deleted from disk: $DISK_ORPHANS"
echo "Deleted from DB: $DB_ORPHANS"
