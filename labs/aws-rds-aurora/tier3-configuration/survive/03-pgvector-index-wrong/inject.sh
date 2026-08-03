#!/usr/bin/env bash
# SURVIVE 03 - Wrong pgvector Index Type
# Inject: Create an IVFFlat index configured for a high-recall workload that needs HNSW
# Also: Set probes too low, causing poor recall and slow queries
#
# INSTRUCTOR USE ONLY

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

check_required_vars

if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "ERROR: Set PGPASSWORD environment variable before running inject.sh"
  exit 1
fi

section "SURVIVE 03 - Injecting Wrong pgvector Index"

info "Ensuring pgvector is installed..."
run_sql "CREATE EXTENSION IF NOT EXISTS vector;" || true

info "Creating a large-ish product catalog table with embeddings..."
run_sql "DROP TABLE IF EXISTS vector_products CASCADE;"

run_sql "
CREATE TABLE vector_products (
  id        serial PRIMARY KEY,
  name      text NOT NULL,
  category  text,
  embedding vector(16)
);
"

info "Inserting 50,000 rows with random embeddings (this takes ~30 seconds)..."
run_sql "
INSERT INTO vector_products (name, category, embedding)
SELECT
  'Product ' || i,
  CASE (i % 5)
    WHEN 0 THEN 'electronics'
    WHEN 1 THEN 'clothing'
    WHEN 2 THEN 'furniture'
    WHEN 3 THEN 'sports'
    ELSE 'food'
  END,
  (
    SELECT array_agg(random()::float4)::vector(16)
    FROM generate_series(1, 16)
  )
FROM generate_series(1, 50000) AS i;
"

info "Creating an IVFFlat index with FAR TOO FEW LISTS for the data size..."
info "(Correct would be ~224 lists for 50k rows. Injecting 5.)"
run_sql "
CREATE INDEX vector_products_bad_idx
ON vector_products
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 5);
"

info "Setting probes to 1 (minimum, causing very poor recall)..."
# This is a session-level setting - we'll bake it into a function that the app uses
run_sql "
CREATE OR REPLACE FUNCTION search_catalog(
  query_vec vector(16),
  result_count integer DEFAULT 10
)
RETURNS TABLE(id integer, name text, category text, distance numeric)
LANGUAGE plpgsql
AS \$\$
BEGIN
  -- BUG: probes is hardcoded to 1 (the lowest setting)
  -- For an IVFFlat index with 5 lists, probes=1 means we only search 1/5 of the index
  SET LOCAL ivfflat.probes = 1;

  RETURN QUERY
  SELECT
    vp.id,
    vp.name,
    vp.category,
    round((vp.embedding <=> query_vec)::numeric, 6) AS distance
  FROM vector_products vp
  ORDER BY vp.embedding <=> query_vec
  LIMIT result_count;
END;
\$\$;
"

info "Verifying the broken setup..."
EXPLAIN_RESULT=$(run_sql "EXPLAIN SELECT * FROM vector_products ORDER BY embedding <=> '[0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,0.1,0.2,0.3,0.4,0.5,0.6,0.7]'::vector LIMIT 10;" 2>/dev/null)
info "Query plan (should show IVFFlat index):"
echo "$EXPLAIN_RESULT"

echo ""
warn "=================================================================="
warn "INJECT COMPLETE"
warn "=================================================================="
warn "Problems injected:"
warn "  1. IVFFlat index has only 5 lists for 50,000 rows"
warn "     (should be ~224 lists - sqrt of row count)"
warn "  2. probes=1 in the search function (too low for any accuracy)"
warn "  3. Result: poor recall (wrong results returned) and slow queries"
warn ""
warn "Symptom: Search results are inaccurate - users report 'search is broken'"
warn "Symptom: Query times vary wildly (1ms to 5000ms)"
warn ""
warn "Student scenario begins now."
warn "=================================================================="
