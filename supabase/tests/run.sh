#!/usr/bin/env bash
# Baut eine lokale Postgres-DB, spielt alle Migrationen + Seed ein und laesst
# die Verhaltenstests laufen. Braucht nur Postgres >= 14 lokal, kein Supabase.
#
#   ./supabase/tests/run.sh
#
set -uo pipefail
DB="${PLAYINDEX_TEST_DB:-playindex_test}"
PSQL_USER="${PLAYINDEX_TEST_USER:-postgres}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

run() { psql -U "$PSQL_USER" -q -v ON_ERROR_STOP=1 -d "$DB" -f "$1"; }

dropdb   -U "$PSQL_USER" --if-exists "$DB"
createdb -U "$PSQL_USER" "$DB"

run "$ROOT/supabase/tests/00_supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do
  echo "-> $(basename "$f")"
  run "$f" || { echo "MIGRATION FEHLGESCHLAGEN: $f"; exit 1; }
done
run "$ROOT/supabase/seed.sql"

echo
psql -U "$PSQL_USER" -q -d "$DB" -f "$ROOT/supabase/tests/01_schema_tests.sql" 2>&1 \
  | grep -vE '^(SET|RESET)$'

echo
echo "--- Zusammenfassung ---"
psql -U "$PSQL_USER" -q -d "$DB" -f "$ROOT/supabase/tests/01_schema_tests.sql" 2>&1 \
  | grep -cE '\[OK\]'   | xargs -I{} echo "bestanden: {}"
