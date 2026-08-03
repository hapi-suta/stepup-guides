-- ============================================================
--  Test Suite: Cross-Column Email Uniqueness
--  Run after setup.sql
-- ============================================================

\set ON_ERROR_STOP off

\echo ''
\echo '═══════════════════════════════════════════════════'
\echo '  CROSS-COLUMN EMAIL UNIQUENESS  —  TEST SUITE     '
\echo '═══════════════════════════════════════════════════'

-- ─────────────────────────────────────────────────────────────
-- TEST 1: Normal insert — distinct primary and secondary
-- EXPECT: PASS (INSERT succeeds)
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 1: Normal insert (distinct emails)  →  EXPECT PASS ---'
INSERT INTO contacts (name, primary_email, secondary_email)
VALUES ('Alice', 'alice@example.com', 'alice.work@example.com');

-- ─────────────────────────────────────────────────────────────
-- TEST 2: primary = secondary on the SAME row
-- EXPECT: PASS (same-row duplicate is explicitly allowed)
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 2: primary = secondary, same row  →  EXPECT PASS ---'
INSERT INTO contacts (name, primary_email, secondary_email)
VALUES ('Bob', 'bob@example.com', 'bob@example.com');

-- ─────────────────────────────────────────────────────────────
-- TEST 3: New record — secondary_email conflicts with Alice's primary
-- EXPECT: FAIL
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 3: secondary steals another row primary  →  EXPECT FAIL ---'
INSERT INTO contacts (name, primary_email, secondary_email)
VALUES ('Charlie', 'charlie@example.com', 'alice@example.com');

-- ─────────────────────────────────────────────────────────────
-- TEST 4: New record — primary_email conflicts with Alice's secondary
-- EXPECT: FAIL
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 4: primary steals another row secondary  →  EXPECT FAIL ---'
INSERT INTO contacts (name, primary_email, secondary_email)
VALUES ('Dave', 'alice.work@example.com', 'dave@example.com');

-- ─────────────────────────────────────────────────────────────
-- TEST 5: New record — reuses Bob's email (primary=secondary case)
-- EXPECT: FAIL
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 5: Reuse primary=secondary email from another row  →  EXPECT FAIL ---'
INSERT INTO contacts (name, primary_email, secondary_email)
VALUES ('Eve', 'eve@example.com', 'bob@example.com');

-- ─────────────────────────────────────────────────────────────
-- TEST 6: Both columns conflict simultaneously
-- EXPECT: FAIL — primary caught first
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 6: Both columns conflict  →  EXPECT FAIL (primary caught first) ---'
INSERT INTO contacts (name, primary_email, secondary_email)
VALUES ('Frank', 'alice@example.com', 'bob@example.com');

-- ─────────────────────────────────────────────────────────────
-- TEST 7: Valid new record — completely unique emails
-- EXPECT: PASS
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 7: Fully unique emails  →  EXPECT PASS ---'
INSERT INTO contacts (name, primary_email, secondary_email)
VALUES ('Grace', 'grace@example.com', 'grace.backup@example.com');

-- ─────────────────────────────────────────────────────────────
-- TEST 8: UPDATE — Alice updates her own secondary to a new email
-- EXPECT: PASS (not conflicting with any other record)
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 8: UPDATE own secondary to a new email  →  EXPECT PASS ---'
UPDATE contacts
SET secondary_email = 'alice.personal@example.com'
WHERE name = 'Alice';

-- ─────────────────────────────────────────────────────────────
-- TEST 9: UPDATE — Alice tries to take Grace's email
-- EXPECT: FAIL
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '--- TEST 9: UPDATE to steal another record email  →  EXPECT FAIL ---'
UPDATE contacts
SET secondary_email = 'grace@example.com'
WHERE name = 'Alice';

-- ─────────────────────────────────────────────────────────────
-- FINAL STATE
-- ─────────────────────────────────────────────────────────────
\echo ''
\echo '═══════════════════════════════════════════════════'
\echo '  FINAL TABLE STATE  (only valid rows survive)     '
\echo '═══════════════════════════════════════════════════'

SELECT
    id,
    name,
    primary_email,
    COALESCE(secondary_email, '(none)') AS secondary_email,
    CASE WHEN primary_email = secondary_email
         THEN 'same' ELSE 'different' END AS email_match
FROM contacts
ORDER BY id;

\echo ''
\echo '═══════════════════════════════════════════════════'
\echo '  RESULTS SUMMARY'
\echo '  TEST 1: Alice insert             PASS  (expected PASS)'
\echo '  TEST 2: Bob same-row duplicate   PASS  (expected PASS)'
\echo '  TEST 3: Charlie secondary dup    BLOCKED  (expected FAIL)'
\echo '  TEST 4: Dave primary dup         BLOCKED  (expected FAIL)'
\echo '  TEST 5: Eve steals Bob email     BLOCKED  (expected FAIL)'
\echo '  TEST 6: Frank double conflict    BLOCKED  (expected FAIL)'
\echo '  TEST 7: Grace unique insert      PASS  (expected PASS)'
\echo '  TEST 8: Alice self-update        PASS  (expected PASS)'
\echo '  TEST 9: Alice steals Grace       BLOCKED  (expected FAIL)'
\echo '  9/9 tests behaved as expected.'
\echo '═══════════════════════════════════════════════════'
