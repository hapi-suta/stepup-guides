# BUILD 04: Advanced Migration Tools - Liquibase, Atlas, Bytebase

**Module 05: CI/CD for Database Changes**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to evaluate and use alternative migration tools beyond Flyway. Each tool takes a different approach to the same problem - tracking and applying database schema changes.

---

## Why Look Beyond Flyway?

Flyway is excellent for SQL-first teams, but it is not the only option. Different tools solve different problems:

- **Liquibase** - XML/YAML/JSON changeset format with auto-generated rollback
- **Atlas** - Declarative schema management (you define the goal, it figures out the DDL)
- **Bytebase** - Enterprise web UI with approval workflows and GitOps
- **sqitch** - Dependency-based migrations for teams that think in graphs, not sequences

Knowing multiple tools makes you dangerous (in a good way). You can pick the right tool for each project.

---

## Step 1: Liquibase Overview

Liquibase takes a different approach from Flyway. Instead of plain SQL files, you define changes in XML, YAML, JSON, or SQL format called "changesets."

### Install Liquibase

**On your Mac terminal:**

```bash
brew install liquibase
```

Expected output (yours will differ):
```
==> Downloading https://ghcr.io/v2/homebrew/core/liquibase/blobs/...
==> Pouring liquibase--4.x.x.all.bottle.tar.gz
==> Summary
  /opt/homebrew/Cellar/liquibase/4.x.x: 25 files, 75MB
```

Verify:

```bash
liquibase --version
```

### Liquibase Changelog Format

Liquibase organizes changes in a "changelog" file. Here is a YAML example:

```bash
mkdir -p ~/dba-labs/liquibase-demo
cd ~/dba-labs/liquibase-demo
vi changelog.yaml
```

```yaml
databaseChangeLog:
  - changeSet:
      id: 1
      author: dba-team
      comment: Create users table
      changes:
        - createTable:
            tableName: users
            columns:
              - column:
                  name: user_id
                  type: serial
                  constraints:
                    primaryKey: true
              - column:
                  name: username
                  type: varchar(50)
                  constraints:
                    nullable: false
                    unique: true
              - column:
                  name: email
                  type: varchar(255)
                  constraints:
                    unique: true
              - column:
                  name: created_at
                  type: timestamptz
                  defaultValueComputed: now()
                  constraints:
                    nullable: false
      rollback:
        - dropTable:
            tableName: users

  - changeSet:
      id: 2
      author: dba-team
      comment: Create products table
      changes:
        - createTable:
            tableName: products
            columns:
              - column:
                  name: product_id
                  type: serial
                  constraints:
                    primaryKey: true
              - column:
                  name: name
                  type: varchar(200)
                  constraints:
                    nullable: false
              - column:
                  name: price
                  type: numeric(10,2)
                  constraints:
                    nullable: false
        - createIndex:
            tableName: products
            indexName: idx_products_name
            columns:
              - column:
                  name: name
      rollback:
        - dropTable:
            tableName: products
```

### Liquibase Properties File

```bash
vi liquibase.properties
```

```properties
changeLogFile=changelog.yaml
url=jdbc:postgresql://localhost:5432/liquibase_lab
username=postgres
password=postgres
driver=org.postgresql.Driver
```

### Create the Test Database and Run

```bash
psql -U postgres -c "CREATE DATABASE liquibase_lab;"
```

```bash
liquibase update
```

Expected output (yours will differ):
```
Running Changeset: changelog.yaml::1::dba-team
Running Changeset: changelog.yaml::2::dba-team
Liquibase command 'update' was executed successfully.
```

### Liquibase Tracking Table

Liquibase tracks applied changes in `databasechangelog` (similar to Flyway's `flyway_schema_history`):

```bash
psql -U postgres -d liquibase_lab -c "SELECT id, author, filename, dateexecuted, orderexecuted FROM databasechangelog;"
```

Expected output (yours will differ):
```
 id | author   |    filename     |      dateexecuted       | orderexecuted
----+----------+-----------------+-------------------------+---------------
 1  | dba-team | changelog.yaml  | 2026-06-09 10:00:00.123 |             1
 2  | dba-team | changelog.yaml  | 2026-06-09 10:00:00.145 |             2
```

### Liquibase Rollback

One advantage of Liquibase: if you define rollback blocks, you can undo changes:

```bash
liquibase rollbackCount 1
```

This rolls back the last changeset (drops the products table). Flyway Community does not support this without the paid Undo feature.

---

## Step 2: Flyway vs Liquibase - Key Differences

| Feature | Flyway | Liquibase |
|---------|--------|-----------|
| Change format | Plain SQL files | XML, YAML, JSON, or SQL |
| Rollback (free tier) | No (Teams only) | Yes (if rollback block defined) |
| Change tracking table | `flyway_schema_history` | `databasechangelog` |
| Learning curve | Very low (just write SQL) | Medium (learn changeset format) |
| Database-agnostic migrations | No (SQL is database-specific) | Yes (abstract types auto-translate) |
| Diff/compare | No | Yes (`liquibase diff`) |
| Context/label filtering | Limited | Yes (run specific changesets by context) |
| Community | Large, well-documented | Large, enterprise-focused |

**When to choose Flyway:** Your team writes raw SQL and does not need rollback automation. You want simplicity.

**When to choose Liquibase:** You need rollback support, database-agnostic migrations, or the ability to diff schemas.

---

## Step 3: Atlas by Ariga - Declarative Schema Management

Atlas takes a fundamentally different approach. Instead of writing migration scripts, you define the desired schema state, and Atlas generates the DDL needed to get there.

**DBA Analogy:** Think of it this way:
- Flyway/Liquibase: "Run these ALTER TABLE commands in this order" (imperative)
- Atlas: "Here is what the schema should look like - figure out the commands" (declarative)

This is similar to how Terraform works for infrastructure. You declare the desired state, and the tool calculates the diff.

### Install Atlas

**On your Mac terminal:**

```bash
brew install ariga/tap/atlas
```

Expected output (yours will differ):
```
==> Fetching ariga/tap/atlas
==> Downloading https://release.ariga.io/atlas/atlas-darwin-arm64-latest
==> Installing atlas from ariga/tap
==> Summary
  /opt/homebrew/Cellar/atlas/0.x.x: 3 files, 45MB
```

Verify:

```bash
atlas version
```

### Define Your Desired Schema in HCL

Atlas uses HCL (HashiCorp Configuration Language) - the same format used by Terraform.

```bash
mkdir -p ~/dba-labs/atlas-demo
cd ~/dba-labs/atlas-demo
vi schema.hcl
```

```hcl
schema "public" {
}

table "users" {
  schema = schema.public

  column "user_id" {
    type = serial
  }
  column "username" {
    type = varchar(50)
    null = false
  }
  column "email" {
    type = varchar(255)
  }
  column "created_at" {
    type    = timestamptz
    null    = false
    default = sql("now()")
  }

  primary_key {
    columns = [column.user_id]
  }

  index "idx_users_username" {
    columns = [column.username]
    unique  = true
  }

  index "idx_users_email" {
    columns = [column.email]
    unique  = true
  }
}

table "products" {
  schema = schema.public

  column "product_id" {
    type = serial
  }
  column "name" {
    type = varchar(200)
    null = false
  }
  column "price" {
    type = numeric(10,2)
    null = false
  }
  column "created_at" {
    type    = timestamptz
    null    = false
    default = sql("now()")
  }

  primary_key {
    columns = [column.product_id]
  }

  index "idx_products_name" {
    columns = [column.name]
  }
}

table "orders" {
  schema = schema.public

  column "order_id" {
    type = serial
  }
  column "user_id" {
    type = int
    null = false
  }
  column "product_id" {
    type = int
    null = false
  }
  column "quantity" {
    type = int
    null = false
  }
  column "total_price" {
    type = numeric(10,2)
    null = false
  }
  column "ordered_at" {
    type    = timestamptz
    null    = false
    default = sql("now()")
  }

  primary_key {
    columns = [column.order_id]
  }

  foreign_key "fk_orders_user" {
    columns     = [column.user_id]
    ref_columns = [table.users.column.user_id]
  }

  foreign_key "fk_orders_product" {
    columns     = [column.product_id]
    ref_columns = [table.products.column.product_id]
  }

  index "idx_orders_user_id" {
    columns = [column.user_id]
  }

  index "idx_orders_ordered_at" {
    columns = [column.ordered_at]
  }
}
```

### Apply the Schema

Create a test database:

```bash
psql -U postgres -c "CREATE DATABASE atlas_lab;"
```

Use `atlas schema apply` to apply the desired state:

```bash
atlas schema apply \
  --url "postgres://postgres:postgres@localhost:5432/atlas_lab?sslmode=disable" \
  --to "file://schema.hcl" \
  --dev-url "postgres://postgres:postgres@localhost:5432/atlas_lab?sslmode=disable"
```

Atlas shows you the planned SQL and asks for confirmation:

Expected output (yours will differ):
```
-- Planned Changes:
-- Create table "users"
CREATE TABLE "public"."users" (
  "user_id" serial NOT NULL,
  "username" varchar(50) NOT NULL,
  "email" varchar(255) NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("user_id")
);
-- Create index "idx_users_username"
CREATE UNIQUE INDEX "idx_users_username" ON "public"."users" ("username");
...
Use the arrow keys to navigate: Up Down
? Are you sure?:
  Yes
> No
```

### Diff Two Schemas

Atlas can compare two schemas and generate the migration DDL:

```bash
atlas schema diff \
  --from "postgres://postgres:postgres@localhost:5432/atlas_lab?sslmode=disable" \
  --to "file://schema.hcl" \
  --dev-url "postgres://postgres:postgres@localhost:5432/atlas_dev?sslmode=disable"
```

**Note:** Atlas requires a `--dev-url` pointing to a clean, empty database it can use for planning. Create one first: `createdb atlas_dev`. The `--dev-url` database must be different from the `--from` database.

If the database matches the schema file, there is no diff. If you modify the HCL file (say, add a column), Atlas generates the ALTER TABLE statement.

---

## Step 4: Atlas vs Flyway - Mental Model

| Aspect | Flyway (Imperative) | Atlas (Declarative) |
|--------|---------------------|---------------------|
| You write | "Add column email to users" | "Users table has column email" |
| Tool generates | Nothing - you wrote the SQL | ALTER TABLE ADD COLUMN |
| Ordering | You manage version numbers | Tool figures out dependency order |
| Drift detection | flyway validate (checksum only) | atlas schema diff (full structural diff) |
| Rollback | Manual undo migrations | Atlas generates reverse DDL |

**DBA Analogy:** Flyway is like writing every `ALTER TABLE` by hand. Atlas is like running `pg_dump --schema-only` of your ideal database and saying "make it look like this."

---

## Step 5: Bytebase - Enterprise Database Change Management

Bytebase is a web-based tool for database change management with built-in approval workflows, SQL review, and GitOps integration. It is aimed at enterprises where multiple teams modify databases and you need governance.

### Key Features

- **Web UI for change review:** Developers submit SQL changes through a web interface, DBAs review and approve.
- **SQL lint/review:** Automatic analysis of SQL changes for anti-patterns (missing indexes, dangerous ALTER TABLE).
- **GitOps integration:** Changes can be synced from Git repositories.
- **Approval workflows:** Multi-stage approval (developer -> tech lead -> DBA).
- **Schema drift detection:** Compares the expected schema against the actual database.
- **Audit log:** Full history of who changed what, when.

### Install and Try Bytebase

Bytebase runs as a Docker container:

```bash
docker run --init \
  --name bytebase \
  --publish 8080:8080 \
  --volume ~/.bytebase/data:/var/opt/bytebase \
  bytebase/bytebase:latest
```

Open http://localhost:8080 in your browser. Bytebase provides a guided setup wizard.

**DBA Analogy:** Bytebase is like having a ticketing system specifically for DDL changes - with built-in review, testing, and deployment. Instead of emailing SQL files or pasting them in Slack, everyone uses a structured workflow.

### When to Choose Bytebase

- Multiple development teams submitting schema changes
- Regulatory requirements for audit trails
- You want non-DBA reviewers (tech leads) in the approval chain
- You need a UI for less technical stakeholders

---

## Step 6: Schema Drift Detection

Schema drift occurs when the actual database schema does not match what your migration tool thinks it should be. This happens when:

- Someone runs manual DDL directly against production
- A migration partially fails
- Different environments get out of sync

**DBA Analogy:** This is like comparing `postgresql.conf` across your 11 datacenters - you need to detect where things have diverged.

### Detecting Drift with Atlas

```bash
atlas schema diff \
  --from "postgres://postgres:postgres@localhost:5432/atlas_lab?sslmode=disable" \
  --to "file://schema.hcl"
```

If someone manually added a column that is not in your schema file, Atlas shows the difference.

### Detecting Drift with Liquibase

```bash
liquibase diff \
  --referenceUrl="jdbc:postgresql://localhost:5432/liquibase_lab" \
  --url="jdbc:postgresql://localhost:5432/atlas_lab"
```

This compares two databases and shows the differences.

### Detecting Drift with pg_dump

For a quick manual check:

```bash
pg_dump -U postgres --schema-only -d database_a > schema_a.sql
pg_dump -U postgres --schema-only -d database_b > schema_b.sql
diff schema_a.sql schema_b.sql
```

---

## Step 7: sqitch - Brief Overview

sqitch is a database-agnostic migration tool that uses a dependency-based approach instead of sequential versions.

Key differences:
- Changes are named (not numbered) and declare dependencies on other changes
- Uses native database scripting (plain SQL for PostgreSQL)
- Built-in revert scripts are required for every change
- Verification scripts confirm each change was applied correctly

```
sqitch add create_users --requires appschema --note "Create users table"
sqitch add create_orders --requires create_users --note "Create orders table"
```

sqitch is popular with teams that think about schema changes as a dependency graph rather than a linear sequence. If your migrations naturally have branching dependencies, sqitch handles that well.

---

## Step 8: Decision Matrix - Choosing a Tool

| Factor | Flyway | Liquibase | Atlas | Bytebase | sqitch |
|--------|--------|-----------|-------|----------|--------|
| **Best for** | SQL-first teams | Enterprise/multi-DB | Declarative fans | Large orgs with UI needs | Dependency-graph thinkers |
| **Learning curve** | Low | Medium | Medium | Low (has UI) | Medium-High |
| **Format** | Plain SQL | XML/YAML/JSON/SQL | HCL or SQL | SQL with UI | Plain SQL |
| **Rollback** | Paid only | Free | Auto-generated | Built-in | Required for every change |
| **Drift detection** | Checksum only | Full diff | Full diff | Full diff | Verify scripts |
| **CI/CD integration** | Excellent | Excellent | Excellent | Good (GitOps) | Good |
| **Approval workflows** | None (use GitHub) | None (use GitHub) | None (use GitHub) | Built-in UI | None |
| **Cost** | Free (Community) | Free (Community) | Free (Community) | Free (Community) | Free (open source) |
| **PostgreSQL support** | Excellent | Excellent | Excellent | Excellent | Excellent |

### Recommendations

- **Solo DBA or small team:** Flyway. Simple, SQL-based, minimal learning curve.
- **Multi-database enterprise:** Liquibase. Supports many databases, has rollback.
- **Infrastructure-as-code shop:** Atlas. If you use Terraform, Atlas feels natural.
- **Large org with governance needs:** Bytebase. Web UI, approval workflows, audit trails.
- **Migration-savvy team:** sqitch. Dependency-based approach is powerful but requires discipline.

---

## Step 9: Practical - Implement the Same Migration in Flyway and Atlas

Let's add a `reviews` table using both approaches.

### Flyway Approach

```bash
vi ~/dba-labs/flyway-demo/sql/V6__create_reviews_table.sql
```

```sql
CREATE TABLE reviews (
    review_id   SERIAL PRIMARY KEY,
    user_id     INTEGER NOT NULL REFERENCES users(user_id),
    product_id  INTEGER NOT NULL REFERENCES products(product_id),
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_reviews_product_id ON reviews (product_id);
CREATE UNIQUE INDEX idx_reviews_user_product ON reviews (user_id, product_id);
```

Apply:

```bash
cd ~/dba-labs/flyway-demo
flyway -configFiles=flyway.conf migrate
```

### Atlas Approach

Add the reviews table to the schema file:

```bash
vi ~/dba-labs/atlas-demo/schema.hcl
```

Append to the file:

```hcl
table "reviews" {
  schema = schema.public

  column "review_id" {
    type = serial
  }
  column "user_id" {
    type = int
    null = false
  }
  column "product_id" {
    type = int
    null = false
  }
  column "rating" {
    type = smallint
    null = false
  }
  column "body" {
    type = text
    null = true
  }
  column "created_at" {
    type    = timestamptz
    null    = false
    default = sql("now()")
  }

  primary_key {
    columns = [column.review_id]
  }

  foreign_key "fk_reviews_user" {
    columns     = [column.user_id]
    ref_columns = [table.users.column.user_id]
  }

  foreign_key "fk_reviews_product" {
    columns     = [column.product_id]
    ref_columns = [table.products.column.product_id]
  }

  index "idx_reviews_product_id" {
    columns = [column.product_id]
  }

  index "idx_reviews_user_product" {
    columns = [column.user_id, column.product_id]
    unique  = true
  }

  check "chk_reviews_rating" {
    expr = "rating >= 1 AND rating <= 5"
  }
}
```

Apply:

```bash
atlas schema apply \
  --url "postgres://postgres:postgres@localhost:5432/atlas_lab?sslmode=disable" \
  --to "file://schema.hcl" \
  --dev-url "postgres://postgres:postgres@localhost:5432/atlas_lab?sslmode=disable"
```

Atlas detects that the `reviews` table does not exist and generates the CREATE TABLE. You did not write any DDL - Atlas figured it out from the schema definition.

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Liquibase | XML/YAML/JSON changeset format with free rollback support |
| Liquibase changelog | Central file defining all changesets with rollback blocks |
| Atlas | Declarative schema management - define desired state, tool generates DDL |
| Atlas HCL | Schema definition language (same family as Terraform) |
| atlas schema diff | Compare actual database against desired schema - detect drift |
| Bytebase | Enterprise web UI with approval workflows and SQL review |
| Schema drift | When the actual database diverges from expected schema |
| sqitch | Dependency-based migrations with required revert scripts |
| Decision matrix | Choose based on team size, governance needs, and workflow preferences |
| Flyway vs Atlas | Imperative (write every DDL) vs declarative (define end state) |

---

**Next:** Module 05 exercises and survive scenarios will test your ability to build complete migration pipelines and handle failures.
