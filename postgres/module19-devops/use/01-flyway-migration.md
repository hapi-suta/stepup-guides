# Module 19 - USE 01: Flyway Migration Exercise

## Objective

Initialize a Flyway project from scratch, create three versioned migrations, run them, verify the schema_version table, and plan a rollback strategy.

---

## Setup

Make sure Flyway is installed (see BUILD 01).

Switch to the postgres user.

```bash
sudo -iu postgres
```

Create a fresh database.

```bash
createdb flyway_exercise
```

Exit the postgres user.

```bash
exit
```

---

## Exercise 1: Initialize the Flyway Project

Create the project directory.

```bash
mkdir -p /opt/pgsql/flyway-exercise/sql
```

Create the Flyway configuration file.

```bash
vi /opt/pgsql/flyway-exercise/flyway.conf
```

Add these settings:

```
flyway.url=jdbc:postgresql://localhost:5432/flyway_exercise
flyway.user=postgres
flyway.locations=filesystem:/opt/pgsql/flyway-exercise/sql
flyway.baselineOnMigrate=true
flyway.cleanDisabled=true
```

The `cleanDisabled=true` setting prevents accidental use of `flyway clean` which drops all objects.

---

## Exercise 2: Create V1 Migration - Users Table

```bash
vi /opt/pgsql/flyway-exercise/sql/V1__create_users_table.sql
```

```sql
-- V1: Create the users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Index for email lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);

-- Index for active user queries
CREATE INDEX IF NOT EXISTS idx_users_active ON users (is_active) WHERE is_active = true;

-- Comment on table for documentation
COMMENT ON TABLE users IS 'Application user accounts';
```

---

## Exercise 3: Create V2 Migration - Products and Categories

```bash
vi /opt/pgsql/flyway-exercise/sql/V2__create_products_and_categories.sql
```

```sql
-- V2: Create products and categories tables

CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    parent_id INTEGER REFERENCES categories(id),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    sku VARCHAR(50) NOT NULL UNIQUE,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    category_id INTEGER REFERENCES categories(id),
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_category ON products (category_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products (sku);
CREATE INDEX IF NOT EXISTS idx_products_available ON products (is_available) WHERE is_available = true;

COMMENT ON TABLE categories IS 'Product categories with self-referencing hierarchy';
COMMENT ON TABLE products IS 'Product catalog';
```

---

## Exercise 4: Create V3 Migration - Orders System

```bash
vi /opt/pgsql/flyway-exercise/sql/V3__create_orders_system.sql
```

```sql
-- V3: Create orders and order_items tables

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'confirmed', 'shipped', 'delivered', 'cancelled')),
    total NUMERIC(12,2) NOT NULL DEFAULT 0,
    shipping_address TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL,
    subtotal NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED
);

CREATE INDEX IF NOT EXISTS idx_orders_user ON orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders (created_at);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items (product_id);

COMMENT ON TABLE orders IS 'Customer orders';
COMMENT ON TABLE order_items IS 'Individual items within an order';
```

---

## Exercise 5: Run the Migrations

Run all three migrations.

```bash
flyway -configFiles=/opt/pgsql/flyway-exercise/flyway.conf migrate
```

Expected output (yours will differ):
```
Flyway Community Edition 10.10.0 by Redgate
Database: jdbc:postgresql://localhost:5432/flyway_exercise (PostgreSQL 16.2)
Successfully validated 3 migrations
Migrating schema "public" to version "1 - create users table"
Migrating schema "public" to version "2 - create products and categories"
Migrating schema "public" to version "3 - create orders system"
Successfully applied 3 migrations to schema "public"
```

---

## Exercise 6: Check the Schema Version Table

Switch to the postgres user.

```bash
sudo -iu postgres
```

Query Flyway's tracking table.

```bash
psql -d flyway_exercise -c "SELECT installed_rank, version, description, type, checksum, installed_on, execution_time, success FROM flyway_schema_history ORDER BY installed_rank;"
```

Expected output (yours will differ):
```
 installed_rank | version |            description            | type |  checksum   |     installed_on      | execution_time | success
----------------+---------+-----------------------------------+------+-------------+-----------------------+----------------+---------
              1 | 1       | create users table                | SQL  |  1234567890 | 2026-04-19 10:00:00.0 |             45 | t
              2 | 2       | create products and categories    | SQL  | -987654321  | 2026-04-19 10:00:00.1 |             62 | t
              3 | 3       | create orders system              | SQL  |  1122334455 | 2026-04-19 10:00:00.2 |             78 | t
(3 rows)
```

Key columns:
- `checksum` - Hash of the migration file contents. If you change a file after it ran, Flyway will detect the mismatch
- `execution_time` - How long the migration took in milliseconds
- `success` - Whether the migration completed without errors

Verify all expected tables exist.

```bash
psql -d flyway_exercise -c "\dt"
```

Expected output (yours will differ):
```
              List of relations
 Schema |         Name          | Type  |  Owner
--------+-----------------------+-------+----------
 public | categories            | table | postgres
 public | flyway_schema_history | table | postgres
 public | order_items           | table | postgres
 public | orders                | table | postgres
 public | products              | table | postgres
 public | users                 | table | postgres
(6 rows)
```

Check that indexes were created.

```bash
psql -d flyway_exercise -c "\di"
```

Exit the postgres user.

```bash
exit
```

---

## Exercise 7: Rollback Strategy

Flyway Community Edition does not have built-in rollback. Here is the standard approach.

### Step 1: Create a Rollback Migration

For every forward migration, write a corresponding undo file. This is not applied automatically - it is a manual safety net.

```bash
vi /opt/pgsql/flyway-exercise/sql/undo/U3__undo_create_orders_system.sql
```

```sql
-- Undo V3: Remove orders system
-- Run this manually if V3 needs to be rolled back

DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
```

```bash
vi /opt/pgsql/flyway-exercise/sql/undo/U2__undo_create_products_and_categories.sql
```

```sql
-- Undo V2: Remove products and categories
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
```

### Step 2: To Roll Back V3

If you need to undo migration V3, do the following.

Switch to the postgres user.

```bash
sudo -iu postgres
```

Run the undo script manually.

```bash
psql -d flyway_exercise -f /opt/pgsql/flyway-exercise/sql/undo/U3__undo_create_orders_system.sql
```

Then update Flyway's tracking table so it knows V3 was removed.

```bash
psql -d flyway_exercise -c "DELETE FROM flyway_schema_history WHERE version = '3';"
```

Verify the state.

```bash
flyway -configFiles=/opt/pgsql/flyway-exercise/flyway.conf info
```

Exit the postgres user.

```bash
exit
```

---

## Cleanup

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
dropdb flyway_exercise
```

Exit the postgres user.

```bash
exit
```

```bash
rm -rf /opt/pgsql/flyway-exercise
```

---

## Checklist

- [ ] Created Flyway project with config file
- [ ] Wrote V1, V2, V3 migrations with IF NOT EXISTS guards
- [ ] Ran all migrations successfully
- [ ] Examined flyway_schema_history table
- [ ] Verified all tables and indexes exist
- [ ] Created undo scripts for rollback strategy
- [ ] Understand that Flyway checksums detect modified migrations
