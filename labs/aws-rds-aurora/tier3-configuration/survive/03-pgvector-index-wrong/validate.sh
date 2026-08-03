#!/usr/bin/env bash
# SURVIVE 03 - Validate pgvector index fix

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

check_required_vars

if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "ERROR: Set PGPASSWORD environment variable before running validate.sh"
  exit 1
fi

section "SURVIVE 03 - Validating pgvector Index Fix"

# -------------------------------------------------------
# Check 1: pgvector extension is installed
# -------------------------------------------------------
info "Checking pgvector extension..."
EXT=$(run_sql "SELECT installed_version FROM pg_available_extensions WHERE name = 'vector'" 2>/dev/null | tr -d '[:space:]')
if [[ -n "$EXT" && "$EXT" != "NULL" ]]; then
  success "pgvector (vector) extension is installed: $EXT"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "pgvector extension is NOT installed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 2: An index exists on the embedding column
# -------------------------------------------------------
info "Checking for index on embedding column..."
INDEX_COUNT=$(run_sql "
SELECT COUNT(*)
FROM pg_indexes
WHERE tablename = 'vector_products'
  AND indexdef LIKE '%embedding%'
  AND indexname != 'vector_products_pkey'
" 2>/dev/null | tr -d '[:space:]')

if [[ "$INDEX_COUNT" -ge 1 ]]; then
  success "Index exists on vector_products.embedding ($INDEX_COUNT index(es))"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "No index found on vector_products.embedding"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 3: If IVFFlat exists, lists must be >= 100
# -------------------------------------------------------
info "Checking IVFFlat index configuration (if present)..."
IVFFLAT_LISTS=$(run_sql "
SELECT
  CASE
    WHEN indexdef LIKE '%ivfflat%' THEN
      (regexp_match(indexdef, 'lists=([0-9]+)'))[1]::integer
    ELSE NULL
  END AS lists
FROM pg_indexes
WHERE tablename = 'vector_products'
  AND indexdef LIKE '%ivfflat%'
LIMIT 1;
" 2>/dev/null | tr -d '[:space:]')

if [[ -z "$IVFFLAT_LISTS" || "$IVFFLAT_LISTS" == "NULL" ]]; then
  info "No IVFFlat index found (may be using HNSW - that is OK)"
  PASS_COUNT=$((PASS_COUNT + 1))
elif [[ "$IVFFLAT_LISTS" -ge 100 ]]; then
  success "IVFFlat index has $IVFFLAT_LISTS lists (acceptable for 50k rows)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "IVFFlat index has only $IVFFLAT_LISTS lists (need >= 100 for 50k rows, recommended 224)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 4: search_catalog function exists
# -------------------------------------------------------
info "Checking search_catalog function..."
FUNC_EXISTS=$(run_sql "SELECT COUNT(*) FROM pg_proc WHERE proname = 'search_catalog'" 2>/dev/null | tr -d '[:space:]')
if [[ "$FUNC_EXISTS" == "1" ]]; then
  success "search_catalog function exists"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  fail "search_catalog function does not exist"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# -------------------------------------------------------
# Check 5: search_catalog no longer uses probes=1
# -------------------------------------------------------
info "Checking search_catalog for bad probes setting..."
FUNC_SRC=$(run_sql "SELECT prosrc FROM pg_proc WHERE proname = 'search_catalog'" 2>/dev/null)
if echo "$FUNC_SRC" | grep -q "probes = 1[^0-9]" || echo "$FUNC_SRC" | grep -q "probes=1[^0-9]"; then
  fail "search_catalog still has probes=1 (too low for production use)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  success "search_catalog does not use probes=1"
  PASS_COUNT=$((PASS_COUNT + 1))
fi

# -------------------------------------------------------
# Check 6: Recall test - index results should overlap with exact search
# -------------------------------------------------------
info "Running recall test (comparing index vs exact search)..."

TEST_VEC="'[0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5]'::vector"

# Get exact results (sequential scan)
EXACT_IDS=$(run_sql "
SET enable_indexscan = off;
SELECT string_agg(id::text, ',' ORDER BY distance) FROM (
  SELECT id, embedding <=> $TEST_VEC AS distance
  FROM vector_products
  ORDER BY distance
  LIMIT 10
) t;
" 2>/dev/null | tr -d '[:space:]')

# Get index results
INDEX_IDS=$(run_sql "
RESET enable_indexscan;
SELECT string_agg(id::text, ',' ORDER BY distance) FROM (
  SELECT id, embedding <=> $TEST_VEC AS distance
  FROM vector_products
  ORDER BY distance
  LIMIT 10
) t;
" 2>/dev/null | tr -d '[:space:]')

# Count overlap (rough recall check)
if [[ -n "$EXACT_IDS" && -n "$INDEX_IDS" ]]; then
  OVERLAP_COUNT=0
  IFS=',' read -ra EXACT_ARR <<< "$EXACT_IDS"
  IFS=',' read -ra INDEX_ARR <<< "$INDEX_IDS"
  for exact_id in "${EXACT_ARR[@]}"; do
    for index_id in "${INDEX_ARR[@]}"; do
      if [[ "$exact_id" == "$index_id" ]]; then
        OVERLAP_COUNT=$((OVERLAP_COUNT + 1))
        break
      fi
    done
  done
  RECALL_PCT=$((OVERLAP_COUNT * 100 / 10))
  if [[ $RECALL_PCT -ge 70 ]]; then
    success "Recall test: $OVERLAP_COUNT/10 matches ($RECALL_PCT% recall) - acceptable"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    fail "Recall test: $OVERLAP_COUNT/10 matches ($RECALL_PCT% recall) - too low (need >= 70%)"
    fail "Index is still misconfigured or probes/ef_search is too low"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
else
  warn "Could not run recall test - check connectivity and table contents"
fi

print_summary
