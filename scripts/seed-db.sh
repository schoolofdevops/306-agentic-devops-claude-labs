#!/usr/bin/env bash
set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-orders}"
DB_NAME="${DB_NAME:-orders}"
PGPASSWORD="${DB_PASSWORD:-orders}"
export PGPASSWORD

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/../fixtures/seed-data"

echo "==> Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."
until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -q 2>/dev/null; do
  sleep 1
done

echo "==> Creating tables..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q <<'SQL'
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    product_id VARCHAR(50) NOT NULL,
    quantity INTEGER NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS products_cache (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200),
    price DECIMAL(10,2),
    last_synced TIMESTAMP
);

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SQL

echo "==> Seeding sample orders..."
cat "$FIXTURES_DIR/sample-orders.json" | python3 -c "
import json, sys
orders = json.load(sys.stdin)
for o in orders:
    print(f\"INSERT INTO orders (product_id, quantity, status) VALUES ('{o[\"product_id\"]}', {o[\"quantity\"]}, '{o[\"status\"]}') ON CONFLICT DO NOTHING;\")
" | psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q

echo "==> Seed complete. $(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc 'SELECT count(*) FROM orders') orders in database."
