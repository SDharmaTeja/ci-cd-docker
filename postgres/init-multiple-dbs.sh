#!/bin/bash
# =============================================================================
# postgres/init-multiple-dbs.sh
# Creates multiple databases on first PostgreSQL startup
# Reads from POSTGRES_MULTIPLE_DATABASES env var (comma-separated)
# =============================================================================

set -e

function create_database() {
  local database=$1
  echo "  Creating database: $database"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE "$database";
    GRANT ALL PRIVILEGES ON DATABASE "$database" TO "$POSTGRES_USER";
EOSQL
}

if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
  echo "================================================"
  echo "  PostgreSQL: creating additional databases"
  echo "================================================"
  for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
    # Skip the default database (POSTGRES_DB or POSTGRES_USER)
    if [ "$db" != "$POSTGRES_USER" ] && [ "$db" != "$POSTGRES_DB" ]; then
      create_database "$db"
    fi
  done
  echo "✅ All databases created."
fi
