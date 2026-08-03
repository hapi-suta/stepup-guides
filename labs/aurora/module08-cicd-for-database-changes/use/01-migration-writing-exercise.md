# USE 01: Migration Writing Exercise

**Module 08: CI/CD for Database Changes**
**Track:** DevOps DBA Training
**Cluster:** devops-lab-cluster

---

## Objective

Write 10 Flyway migrations that build a complete e-commerce schema from scratch. This exercise tests your ability to structure migrations, handle dependencies between tables, and follow zero-downtime best practices.

---

## Setup

**On your Mac terminal:**

```bash
mkdir -p ~/dba-labs/use-migration-chain/sql
```

```bash
cd ~/dba-labs/use-migration-chain
```

Create `flyway.conf` with your Aurora connection details:

```properties
flyway.url=jdbc:postgresql://YOUR_AURORA_ENDPOINT:5432/migration_exercise
flyway.user=postgres
flyway.password=YOUR_PASSWORD
flyway.locations=filesystem:./sql
flyway.cleanDisabled=false
```

Create the database:

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "CREATE DATABASE migration_exercise;"
```

---

## Requirements

Write the following 10 migrations in order. Each file must include `SET lock_timeout = '5s';` at the top.

| Version | Description | What to Create |
|---------|-------------|---------------|
| V1 | Create users table | `users` (user_id SERIAL PK, username VARCHAR(50) UNIQUE NOT NULL, email VARCHAR(255) UNIQUE NOT NULL, password_hash VARCHAR(255) NOT NULL, created_at TIMESTAMPTZ DEFAULT now()) |
| V2 | Create products table | `products` (product_id SERIAL PK, name VARCHAR(200) NOT NULL, description TEXT, price NUMERIC(10,2) NOT NULL CHECK >= 0, stock_quantity INT NOT NULL DEFAULT 0 CHECK >= 0, created_at TIMESTAMPTZ DEFAULT now()) |
| V3 | Create categories table | `categories` (category_id SERIAL PK, name VARCHAR(100) NOT NULL UNIQUE, parent_category_id INT self-referencing FK) |
| V4 | Link products to categories | `product_categories` junction table (product_id, category_id composite PK, both FKs) |
| V5 | Create orders table | `orders` (order_id SERIAL PK, user_id FK, status VARCHAR(20) DEFAULT 'pending' with CHECK, total_amount NUMERIC(12,2) DEFAULT 0, ordered_at TIMESTAMPTZ DEFAULT now()) |
| V6 | Create order items | `order_items` (item_id SERIAL PK, order_id FK, product_id FK, quantity INT CHECK > 0, unit_price NUMERIC(10,2)) |
| V7 | Add indexes | Indexes on all FK columns and common query columns (status, ordered_at, name) |
| V8 | Create views | `v_order_summary` (user, order count, total spent), `v_product_catalog` (product, category, price) |
| V9 | Add audit trigger | Trigger on `orders` that logs status changes to an `order_audit` table |
| V10 | Add constraints | CHECK on status values, CHECK on price > 0, UNIQUE on (user_id, product_id) for preventing duplicate order items in same order |

---

## Rules

1. Every migration file must include `SET lock_timeout = '5s';`
2. Use `IF NOT EXISTS` guards on CREATE TABLE and CREATE INDEX
3. Tables must be created before any table that references them (ordering matters)
4. The audit trigger must use `CREATE OR REPLACE FUNCTION`
5. Views must handle NULL values with `COALESCE`

---

## Acceptance Criteria

<details>
<summary>Click to expand the checklist</summary>

- [ ] All 10 migrations apply cleanly with `flyway migrate`
- [ ] `flyway validate` passes with no errors
- [ ] All foreign keys are properly defined
- [ ] Indexes exist on all FK columns
- [ ] `v_order_summary` returns data after inserting test rows
- [ ] `v_product_catalog` joins products with categories correctly
- [ ] Audit trigger fires on order status update
- [ ] `flyway clean` followed by `flyway migrate` works (full idempotent rebuild)
- [ ] The status CHECK constraint rejects invalid values

</details>

---

## Verification

After applying all migrations, run these checks.

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d migration_exercise
```

```sql
-- Should return 10
SELECT count(*) FROM flyway_schema_history WHERE success = true;
```

```sql
-- Should list all tables
SELECT tablename FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
```

```sql
-- Insert test data
INSERT INTO users (username, email, password_hash)
VALUES ('testuser', 'test@test.com', 'hash123');

INSERT INTO categories (name) VALUES ('Electronics');

INSERT INTO products (name, description, price, stock_quantity)
VALUES ('Widget', 'A test widget', 9.99, 100);

INSERT INTO product_categories (product_id, category_id) VALUES (1, 1);

INSERT INTO orders (user_id, status, total_amount)
VALUES (1, 'pending', 9.99);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (1, 1, 1, 9.99);
```

```sql
-- Views should return data
SELECT * FROM v_order_summary;
SELECT * FROM v_product_catalog;
```

```sql
-- Test the audit trigger
UPDATE orders SET status = 'confirmed' WHERE order_id = 1;
SELECT * FROM order_audit;
```

```sql
-- Test the status CHECK constraint (should fail)
INSERT INTO orders (user_id, status, total_amount)
VALUES (1, 'invalid_status', 5.00);
```

Expected: the last INSERT fails with a CHECK constraint violation.

---

## Clean Up

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -c "DROP DATABASE IF EXISTS migration_exercise;"
```

---

## Hints

<details>
<summary>Click if you are stuck on V3 (self-referencing FK)</summary>

```sql
CREATE TABLE categories (
    category_id        SERIAL PRIMARY KEY,
    name               VARCHAR(100) NOT NULL UNIQUE,
    parent_category_id INTEGER REFERENCES categories(category_id)
);
```

The FK points back to the same table. This allows nested categories (e.g., Electronics > Laptops > Gaming Laptops).

</details>

<details>
<summary>Click if you are stuck on V9 (audit trigger)</summary>

```sql
CREATE TABLE order_audit (
    audit_id   SERIAL PRIMARY KEY,
    order_id   INTEGER NOT NULL,
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_at TIMESTAMPTZ DEFAULT now()
);

CREATE OR REPLACE FUNCTION log_order_status()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO order_audit (order_id, old_status, new_status)
        VALUES (NEW.order_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_order_audit
    AFTER UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION log_order_status();
```

</details>
