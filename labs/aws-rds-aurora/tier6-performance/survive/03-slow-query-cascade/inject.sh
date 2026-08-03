#!/usr/bin/env bash
# survive/03-slow-query-cascade/inject.sh
# Injects: One bad query consuming all CPU, causing cascade of slow responses
# Difficulty: Expert

set -euo pipefail
source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../lib/common.sh"

section "INJECT: Slow Query Cascade"
log "Setting up target tables and injecting CPU-saturating queries"

# Setup
psql_exec "
DROP TABLE IF EXISTS cascade_orders CASCADE;
DROP TABLE IF EXISTS cascade_users CASCADE;

CREATE TABLE cascade_users (
    user_id BIGSERIAL PRIMARY KEY,
    email TEXT NOT NULL,
    country TEXT NOT NULL,
    signup_date DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE cascade_orders (
    order_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO cascade_users (email, country)
SELECT 'user' || g || '@example.com',
       CASE (g % 4) WHEN 0 THEN 'US' WHEN 1 THEN 'UK' WHEN 2 THEN 'DE' ELSE 'FR' END
FROM generate_series(1, 200000) g;

INSERT INTO cascade_orders (user_id, amount, status, description)
SELECT
    (random() * 200000 + 1)::BIGINT,
    (random() * 1000)::NUMERIC(12,2),
    'completed',
    md5(random()::TEXT) || ' ' || md5(random()::TEXT)
FROM generate_series(1, 3000000);

ANALYZE cascade_users, cascade_orders;
"

log "Tables created. Dropping index to force full table scan..."

# Drop any index that might save the query
psql_exec "DROP INDEX IF EXISTS cascade_orders_user_id_idx;"

log "Launching 20 parallel CPU-saturating queries..."

echo "$(date)" > "${SURVIVE_LOG_DIR}/03-inject-time.txt"

# Launch expensive queries that do cross joins and regex matching
for i in $(seq 1 20); do
    psql -h "$DB_ENDPOINT" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT u.country,
       count(o.order_id) AS order_count,
       sum(o.amount) AS total_amount,
       avg(o.amount) AS avg_amount
FROM cascade_users u
JOIN cascade_orders o ON u.user_id = o.user_id
WHERE o.description ~ '.*[aeiou]{3}.*'
  AND o.amount > 100
GROUP BY u.country
ORDER BY total_amount DESC;" &>/dev/null &
done

log "20 CPU-saturating queries running in background"

echo ""
echo "=========================================="
echo "SCENARIO INJECTED: Slow Query Cascade"
echo "=========================================="
echo ""
echo "What is happening:"
echo "  - 20 parallel queries are doing full table scans on 3M rows"
echo "  - Each uses regex matching (non-indexable) on the description column"
echo "  - Combined they will saturate CPU on smaller instances"
echo "  - Other queries are being starved of CPU time"
echo ""
echo "Symptoms:"
echo "  - CloudWatch CPUUtilization near 100%"
echo "  - Performance Insights shows 'CPU' wait event dominating"
echo "  - Even simple queries like SELECT 1 take multiple seconds"
echo ""
echo "To stop injection early: pkill -f 'psql.*description'"
