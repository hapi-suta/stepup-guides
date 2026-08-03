-- ============================================================
--  Demo: Cross-Column Email Uniqueness in PostgreSQL
--  Author: SUTA Labs
-- ============================================================
--  Business Rule:
--    1. primary_email and secondary_email on the SAME row CAN match
--    2. An email value must not appear in ANY other row (either column)
-- ============================================================

-- ── Clean slate ─────────────────────────────────────────────
DROP TABLE IF EXISTS contacts CASCADE;
DROP FUNCTION IF EXISTS enforce_email_uniqueness() CASCADE;

-- ── Table ────────────────────────────────────────────────────
CREATE TABLE contacts (
    id              SERIAL PRIMARY KEY,
    name            TEXT   NOT NULL,
    primary_email   TEXT   NOT NULL,
    secondary_email TEXT
);

-- ── Enforcement function ─────────────────────────────────────
CREATE OR REPLACE FUNCTION enforce_email_uniqueness()
RETURNS TRIGGER AS $$
BEGIN
    -- Rule 1: primary_email must not exist in any OTHER row (either column)
    IF EXISTS (
        SELECT 1 FROM contacts
        WHERE id != COALESCE(NEW.id, 0)
          AND (primary_email   = NEW.primary_email
            OR secondary_email = NEW.primary_email)
    ) THEN
        RAISE EXCEPTION
            'CONFLICT: primary_email "%" is already used by another record',
            NEW.primary_email;
    END IF;

    -- Rule 2: secondary_email must not exist in any OTHER row (either column)
    --         Exception: if secondary = primary on the SAME row, skip this check
    --         (same-row duplicate is permitted; Rule 1 already protects that email)
    IF NEW.secondary_email IS NOT NULL
       AND NEW.secondary_email <> NEW.primary_email THEN
        IF EXISTS (
            SELECT 1 FROM contacts
            WHERE id != COALESCE(NEW.id, 0)
              AND (primary_email   = NEW.secondary_email
                OR secondary_email = NEW.secondary_email)
        ) THEN
            RAISE EXCEPTION
                'CONFLICT: secondary_email "%" is already used by another record',
                NEW.secondary_email;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── Trigger (fires on INSERT and UPDATE) ─────────────────────
CREATE TRIGGER trg_email_uniqueness
BEFORE INSERT OR UPDATE ON contacts
FOR EACH ROW EXECUTE FUNCTION enforce_email_uniqueness();

SELECT 'Setup complete: table + trigger ready.' AS status;
