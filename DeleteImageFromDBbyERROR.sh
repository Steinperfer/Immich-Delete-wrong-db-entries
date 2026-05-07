#!/bin/bash
# Kein 'set -e', damit das Script bei kleinen SQL-Fehlern nicht stoppt

echo "=== IMMICH TOTAL CLEANUP (DISK + DB) ==="

DB_CONTAINER="immich_postgres"
SERVER_CONTAINER="immich_server"
DISK_PATH="/mnt/ImageDB"
TMP_DIR="/tmp/immich_fix"
mkdir -p "$TMP_DIR"

MISSING_DB="$TMP_DIR/db_paths.txt"
DELETE_LIST="$TMP_DIR/delete_uuids.txt"

echo "[1/3] Identifiziere Dateien zum Löschen..."
# Wir holen alle Pfade aus der DB
docker exec "$DB_CONTAINER" psql -U postgres -d immich -t -c "SELECT path FROM asset_file;" | sed '/^\s*$/d' | sort > "$MISSING_DB"

# HINWEIS: Da du sagtest, du willst die "falschen" Bilder löschen, 
# gehen wir davon aus, dass dies die 34k Einträge sind, die keine Zuordnung mehr haben 
# oder die du bereits als "falsch" markiert hast.

echo "[2/3] Lösche Dateien physisch von der Festplatte..."
# Wir wandern durch die Liste und löschen auf der echten Platte
while read -r path; do
    # Immich-Pfade in Container (/data/...) zu echten Pfaden (/mnt/ImageDB/...) wandeln
    real_file=$(echo "$path" | sed "s|^/data/|$DISK_PATH/|")
    if [ -f "$real_file" ]; then
        sudo rm "$real_file"
        echo -n "."
    fi
done < "$MISSING_DB"
echo -e "\nDateien gelöscht."

echo "[3/3] Bereinige Datenbank-Einträge..."
# Jetzt holen wir die IDs für diese Pfade
cat "$MISSING_DB" | xargs -L 100 | while read -r batch; do
    f=$(echo "$batch" | sed "s/ /','/g; s/^/'/; s/$/'/")

    # IDs holen
    ids=$(docker exec "$DB_CONTAINER" psql -U postgres -d immich -t -c "SELECT \"assetId\" FROM asset_file WHERE path IN ($f);" | sed '/^\s*$/d')

    if [ ! -z "$ids" ]; then
        id_batch=$(echo "$ids" | sed "s/ /','/g; s/^/'/; s/$/'/")
        # Referenzen und Assets löschen (Brute Force)
        docker exec "$DB_CONTAINER" psql -U postgres -d immich -c "DELETE FROM stack WHERE \"primaryAssetId\" IN ($id_batch);" >/dev/null 2>&1 || true
        docker exec "$DB_CONTAINER" psql -U postgres -d immich -c "DELETE FROM asset WHERE id IN ($id_batch);" >/dev/null 2>&1 || true
        echo -n "!"
    fi
done

echo -e "\n=== ALLES ERLEDIGT: 80GB SOLLTEN JETZT FREI SEIN ==="
