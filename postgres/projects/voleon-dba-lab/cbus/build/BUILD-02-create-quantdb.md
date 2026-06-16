# Build Guide 02: Create quantdb Schema and Load Data

| | |
|---|---|
| **Time** | 45 minutes |
| **Server** | pg-primary (3.90.199.62) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Learn
- How to create a PostgreSQL database
- How to create roles with different permission levels
- How to design a schema for a quantitative finance platform
- How to create partitioned tables
- How to assign granular role-based permissions
- How to load seed data and create indexes

## Prerequisites
- BUILD-01 completed - PostgreSQL 17 is installed and running on pg-primary
- You can SSH into pg-primary as `ec2-user`

---

## Step 1: Connect to pg-primary

Open your terminal and connect:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

---

## Step 2: Switch to the postgres User

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

This switches your session to the `postgres` OS user so you can use `psql` with peer authentication. You will stay as the `postgres` user for all of the following steps until told otherwise.

---

## Step 3: Open psql

Still as **postgres** on **pg-primary**:

```bash
psql
```

You should see:

```
psql (17.x)
Type "help" for help.

postgres=#
```

---

## Step 4: Create the quantdb Database

Still as **postgres** on **pg-primary**, inside psql:

```sql
CREATE DATABASE quantdb;
```

`CREATE DATABASE` provisions a new, empty database. `quantdb` is the name we are using for the quantitative research and trading data platform.

Expected output:
```
CREATE DATABASE
```

---

## Step 5: Create Application Roles

Still as **postgres** on **pg-primary**, inside psql:

Create the application user role:

```sql
CREATE ROLE quant_app WITH LOGIN PASSWORD 'quant_app_2026';
```

Create the research analyst role:

```sql
CREATE ROLE quant_research WITH LOGIN PASSWORD 'quant_research_2026';
```

Create the data pipeline role:

```sql
CREATE ROLE quant_pipeline WITH LOGIN PASSWORD 'quant_pipeline_2026';
```

Create the read-only reporting role:

```sql
CREATE ROLE quant_readonly WITH LOGIN PASSWORD 'quant_readonly_2026';
```

Create the replication role:

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_voleon_2026';
```

What each role is for:
- `quant_app` - The live trading application; needs to read and write quant data.
- `quant_research` - Analysts exploring data; read-only access to quant tables.
- `quant_pipeline` - ETL jobs that load market data; write access to market data tables and full access to ops tables.
- `quant_readonly` - Dashboards and reporting tools; read-only across all schemas.
- `replicator` - Used by standby servers to stream WAL from this primary. The `REPLICATION` attribute grants the special privilege needed for streaming replication.

Expected output (for each):
```
CREATE ROLE
```

---

## Step 6: Connect to quantdb

Still as **postgres** on **pg-primary**, inside psql:

```sql
\c quantdb
```

`\c` is the psql meta-command to switch your connection to a different database. All objects you create from this point forward will exist inside `quantdb`.

Expected output:
```
You are now connected to database "quantdb" as user "postgres".
```

---

## Step 7: Create the quant Schema

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

```sql
CREATE SCHEMA quant;
```

A schema is a namespace inside a database. It groups related tables together, keeps them separate from other schemas, and allows per-schema permission grants. The `quant` schema will hold all trading-related tables.

Expected output:
```
CREATE SCHEMA
```

---

## Step 8: Create the ops Schema

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

```sql
CREATE SCHEMA ops;
```

The `ops` schema holds operational and infrastructure tables - deployment records, pipeline run logs, and alerts. Keeping these separate from `quant` makes it easy to grant different permissions to each.

Expected output:
```
CREATE SCHEMA
```

---

## Step 9: Create Tables in the quant Schema

You will create seven tables. Run each `CREATE TABLE` statement one at a time.

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

### quant.instruments

Stores the master list of tradeable instruments (stocks, ETFs, futures, etc.).

```sql
CREATE TABLE quant.instruments (
    instrument_id   serial PRIMARY KEY,
    ticker          varchar(20),
    isin            varchar(12),
    name            varchar(200),
    exchange        varchar(50),
    asset_class     varchar(30),
    sector          varchar(100),
    currency        varchar(3),
    is_active       boolean,
    listed_date     date,
    created_at      timestamptz
);
```

Expected output:
```
CREATE TABLE
```

### quant.market_data

Stores daily OHLCV (open/high/low/close/volume) price data for each instrument. This table is **partitioned by range on trade_date**, meaning data for each month lives in a separate physical partition. This improves query performance and makes it easy to archive or drop old data.

```sql
CREATE TABLE quant.market_data (
    market_data_id      bigserial,
    instrument_id       int REFERENCES quant.instruments(instrument_id),
    trade_date          date,
    open_price          numeric(18,6),
    high_price          numeric(18,6),
    low_price           numeric(18,6),
    close_price         numeric(18,6),
    volume              bigint,
    vwap                numeric(18,6),
    source_feed         varchar(50),
    exchange_timestamp  timestamptz,
    created_at          timestamptz
) PARTITION BY RANGE (trade_date);
```

Expected output:
```
CREATE TABLE
```

### quant.models

Stores metadata about each machine learning or quantitative model, including its performance metrics.

```sql
CREATE TABLE quant.models (
    model_id            serial PRIMARY KEY,
    model_name          varchar(100),
    version             varchar(20),
    framework           varchar(50),
    description         text,
    training_dataset    varchar(200),
    status              varchar(20),
    accuracy            numeric(8,6),
    sharpe_ratio        numeric(8,4),
    max_drawdown        numeric(8,4),
    created_by          varchar(100),
    created_at          timestamptz,
    updated_at          timestamptz
);
```

Expected output:
```
CREATE TABLE
```

### quant.signals

Stores trading signals generated by models for each instrument. Like `market_data`, this table is **partitioned by range on signal_date** so signal history can be managed efficiently.

```sql
CREATE TABLE quant.signals (
    signal_id       bigserial,
    model_id        int REFERENCES quant.models(model_id),
    instrument_id   int REFERENCES quant.instruments(instrument_id),
    signal_date     date,
    signal_type     varchar(10),
    score           numeric(8,6),
    confidence      numeric(5,4),
    decay_hours     int,
    created_at      timestamptz
) PARTITION BY RANGE (signal_date);
```

Expected output:
```
CREATE TABLE
```

### quant.positions

Stores current open positions - what the fund is holding right now, at what price, and what the current P&L is.

```sql
CREATE TABLE quant.positions (
    position_id     serial PRIMARY KEY,
    instrument_id   int REFERENCES quant.instruments(instrument_id),
    model_id        int REFERENCES quant.models(model_id),
    quantity        int,
    entry_price     numeric(18,6),
    current_price   numeric(18,6),
    pnl             numeric(18,2),
    pnl_pct         numeric(8,4),
    opened_at       timestamptz,
    updated_at      timestamptz
);
```

Expected output:
```
CREATE TABLE
```

### quant.backtests

Stores backtest results - how a model would have performed over a historical period before it was deployed live.

```sql
CREATE TABLE quant.backtests (
    backtest_id     serial PRIMARY KEY,
    model_id        int REFERENCES quant.models(model_id),
    start_date      date,
    end_date        date,
    sharpe_ratio    numeric(8,4),
    max_drawdown    numeric(8,4),
    total_return    numeric(8,4),
    num_trades      int,
    win_rate        numeric(5,4),
    created_at      timestamptz
);
```

Expected output:
```
CREATE TABLE
```

### quant.model_features

Stores computed feature values used as inputs to models - useful for feature auditing and drift detection.

```sql
CREATE TABLE quant.model_features (
    feature_id      bigserial PRIMARY KEY,
    model_id        int REFERENCES quant.models(model_id),
    feature_name    varchar(100),
    feature_value   numeric(18,8),
    computed_at     timestamptz,
    created_at      timestamptz
);
```

Expected output:
```
CREATE TABLE
```

---

## Step 10: Create Tables in the ops Schema

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

### ops.deployments

Tracks every time a model version is deployed to an environment (dev, staging, production).

```sql
CREATE TABLE ops.deployments (
    deployment_id   serial PRIMARY KEY,
    model_id        int,
    model_version   varchar(20),
    environment     varchar(20),
    status          varchar(20),
    deployed_by     varchar(100),
    promoted_by     varchar(100),
    is_rollback     boolean,
    deployed_at     timestamptz,
    completed_at    timestamptz
);
```

Expected output:
```
CREATE TABLE
```

### ops.pipeline_runs

Tracks each run of a data pipeline - how many rows were processed, how long it took, and whether it succeeded.

```sql
CREATE TABLE ops.pipeline_runs (
    run_id              serial PRIMARY KEY,
    pipeline_name       varchar(100),
    source              varchar(100),
    rows_processed      bigint,
    rows_failed         bigint,
    duration_seconds    int,
    status              varchar(20),
    error_message       text,
    started_at          timestamptz,
    completed_at        timestamptz
);
```

Expected output:
```
CREATE TABLE
```

### ops.alerts

Stores system and data quality alerts that need acknowledgment.

```sql
CREATE TABLE ops.alerts (
    alert_id            serial PRIMARY KEY,
    alert_type          varchar(50),
    severity            varchar(20),
    source_table        varchar(100),
    source_id           int,
    message             text,
    acknowledged        boolean,
    acknowledged_by     varchar(100),
    created_at          timestamptz,
    acknowledged_at     timestamptz
);
```

Expected output:
```
CREATE TABLE
```

---

## Step 11: Create Partitions for market_data and signals

Partitioned tables need explicit child partitions created before data can be inserted. You will create one partition per month for the full year 2024.

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

Create monthly partitions for `quant.market_data`:

```sql
CREATE TABLE quant.market_data_2024_01 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE quant.market_data_2024_02 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE quant.market_data_2024_03 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
CREATE TABLE quant.market_data_2024_04 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
CREATE TABLE quant.market_data_2024_05 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
CREATE TABLE quant.market_data_2024_06 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');
CREATE TABLE quant.market_data_2024_07 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');
CREATE TABLE quant.market_data_2024_08 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');
CREATE TABLE quant.market_data_2024_09 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');
CREATE TABLE quant.market_data_2024_10 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');
CREATE TABLE quant.market_data_2024_11 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');
CREATE TABLE quant.market_data_2024_12 PARTITION OF quant.market_data
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
```

Each `PARTITION OF` statement creates a child table that automatically stores rows where `trade_date` falls within that month's range. The upper bound is exclusive (e.g., `TO ('2024-02-01')` means up to but not including February 1st).

Create monthly partitions for `quant.signals`:

```sql
CREATE TABLE quant.signals_2024_01 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
CREATE TABLE quant.signals_2024_02 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
CREATE TABLE quant.signals_2024_03 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
CREATE TABLE quant.signals_2024_04 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
CREATE TABLE quant.signals_2024_05 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
CREATE TABLE quant.signals_2024_06 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');
CREATE TABLE quant.signals_2024_07 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');
CREATE TABLE quant.signals_2024_08 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');
CREATE TABLE quant.signals_2024_09 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');
CREATE TABLE quant.signals_2024_10 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');
CREATE TABLE quant.signals_2024_11 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');
CREATE TABLE quant.signals_2024_12 PARTITION OF quant.signals
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
```

Expected output (for each partition):
```
CREATE TABLE
```

Verify the partitions were created:

```sql
SELECT tablename FROM pg_tables WHERE schemaname = 'quant' ORDER BY tablename;
```

Expected output (yours will differ):
```
         tablename
----------------------------
 backtests
 instruments
 market_data
 market_data_2024_01
 market_data_2024_02
 ...
 signals
 signals_2024_01
 ...
(27 rows)
```

---

## Step 12: Grant Permissions

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

### quant_app permissions

`quant_app` is the live trading application. It needs to read and write data in the `quant` schema.

```sql
GRANT USAGE ON SCHEMA quant TO quant_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA quant TO quant_app;
```

`GRANT USAGE ON SCHEMA` allows the role to see and access objects inside the schema. Without it, the role cannot even find the tables. `GRANT SELECT, INSERT, UPDATE ON ALL TABLES` gives the actual data access on every existing table in that schema.

### quant_research permissions

`quant_research` is for analysts - read-only.

```sql
GRANT USAGE ON SCHEMA quant TO quant_research;
GRANT SELECT ON ALL TABLES IN SCHEMA quant TO quant_research;
```

### quant_pipeline permissions

`quant_pipeline` runs ETL jobs. It needs full control over the `ops` schema and write access to the key data tables in `quant`.

```sql
GRANT USAGE ON SCHEMA ops TO quant_pipeline;
GRANT ALL ON ALL TABLES IN SCHEMA ops TO quant_pipeline;
GRANT USAGE ON SCHEMA quant TO quant_pipeline;
GRANT INSERT ON quant.market_data TO quant_pipeline;
GRANT INSERT ON quant.signals TO quant_pipeline;
```

`GRANT ALL ON ALL TABLES IN SCHEMA ops` gives every privilege (SELECT, INSERT, UPDATE, DELETE, TRUNCATE) on all tables in the `ops` schema. This is appropriate for the pipeline role that owns the operational data.

### quant_readonly permissions

`quant_readonly` is for dashboards and reporting - read-only across everything.

```sql
GRANT USAGE ON SCHEMA quant TO quant_readonly;
GRANT USAGE ON SCHEMA ops TO quant_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA quant TO quant_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA ops TO quant_readonly;
```

---

## Step 13: Enable the pg_stat_statements Extension

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

`pg_stat_statements` tracks statistics on every SQL statement executed in the database - how many times each query ran, how long it took on average, how many rows it returned. This is one of the most important tools for identifying slow queries in production. The `IF NOT EXISTS` guard means this is safe to run multiple times.

Expected output:
```
CREATE EXTENSION
```

---

## Step 14: Load Sample Data

Now you will insert representative seed data so the schemas are usable for practice queries.

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

Insert sample instruments using `generate_series` to create multiple rows efficiently:

```sql
INSERT INTO quant.instruments (ticker, isin, name, exchange, asset_class, sector, currency, is_active, listed_date, created_at)
VALUES
    ('AAPL',  'US0378331005', 'Apple Inc.',             'NASDAQ', 'equity', 'Technology',        'USD', true, '1980-12-12', now()),
    ('MSFT',  'US5949181045', 'Microsoft Corporation',  'NASDAQ', 'equity', 'Technology',        'USD', true, '1986-03-13', now()),
    ('GOOGL', 'US02079K3059', 'Alphabet Inc.',          'NASDAQ', 'equity', 'Technology',        'USD', true, '2004-08-19', now()),
    ('JPM',   'US46625H1005', 'JPMorgan Chase & Co.',   'NYSE',   'equity', 'Financials',        'USD', true, '1969-01-01', now()),
    ('XOM',   'US30231G1022', 'Exxon Mobil Corporation','NYSE',   'equity', 'Energy',            'USD', true, '1920-01-01', now()),
    ('SPY',   'US78462F1030', 'SPDR S&P 500 ETF',       'NYSE',   'etf',    'Broad Market',      'USD', true, '1993-01-22', now()),
    ('GLD',   'US78463V1070', 'SPDR Gold Shares',       'NYSE',   'etf',    'Commodities',       'USD', true, '2004-11-18', now()),
    ('QQQ',   'US46090E1038', 'Invesco QQQ Trust',      'NASDAQ', 'etf',    'Technology',        'USD', true, '1999-03-10', now());
```

Expected output:
```
INSERT 0 8
```

Insert sample models:

```sql
INSERT INTO quant.models (model_name, version, framework, description, training_dataset, status, accuracy, sharpe_ratio, max_drawdown, created_by, created_at, updated_at)
VALUES
    ('momentum_v1',    '1.0', 'sklearn',    'Short-term momentum signal',          'SP500_2018_2022', 'active',  0.623400, 1.4200, -0.1230, 'research_team', now(), now()),
    ('mean_rev_v2',    '2.1', 'pytorch',    'Mean reversion on daily close',        'SP500_2019_2023', 'active',  0.589200, 1.1800, -0.1540, 'research_team', now(), now()),
    ('factor_alpha',   '3.0', 'xgboost',   'Multi-factor alpha model',             'SP500_2015_2023', 'staging', 0.641000, 1.6700, -0.0980, 'quant_lab',     now(), now()),
    ('nlp_sentiment',  '1.2', 'transformers','NLP sentiment from earnings calls',  'SEC_filings_2020_2023', 'dev', 0.557800, 0.9200, -0.2010, 'nlp_team', now(), now());
```

Expected output:
```
INSERT 0 4
```

Insert sample market data using `generate_series` to produce one row per trading day for January 2024 for instrument_id 1 (AAPL):

```sql
INSERT INTO quant.market_data (instrument_id, trade_date, open_price, high_price, low_price, close_price, volume, vwap, source_feed, exchange_timestamp, created_at)
SELECT
    1,
    gs::date,
    185.00 + (random() * 10),
    190.00 + (random() * 10),
    182.00 + (random() * 5),
    187.00 + (random() * 10),
    (50000000 + (random() * 20000000))::bigint,
    186.00 + (random() * 8),
    'bloomberg',
    gs + interval '16 hours',
    now()
FROM generate_series('2024-01-02'::date, '2024-01-31'::date, '1 day'::interval) AS gs
WHERE EXTRACT(DOW FROM gs) NOT IN (0, 6);
```

`generate_series` produces one row for each day from January 2 to January 31. `WHERE EXTRACT(DOW FROM gs) NOT IN (0, 6)` filters out Sundays (0) and Saturdays (6) so you only get weekday rows. The `random()` function adds realistic price variation. `DOW` means "day of week".

Expected output (yours will differ):
```
INSERT 0 23
```

Insert sample signals for model 1 and instrument 1:

```sql
INSERT INTO quant.signals (model_id, instrument_id, signal_date, signal_type, score, confidence, decay_hours, created_at)
SELECT
    1,
    1,
    gs::date,
    CASE WHEN random() > 0.5 THEN 'long' ELSE 'short' END,
    (random() * 0.4 + 0.5)::numeric(8,6),
    (random() * 0.3 + 0.6)::numeric(5,4),
    24,
    now()
FROM generate_series('2024-01-02'::date, '2024-01-31'::date, '1 day'::interval) AS gs
WHERE EXTRACT(DOW FROM gs) NOT IN (0, 6);
```

Expected output (yours will differ):
```
INSERT 0 23
```

Insert sample positions:

```sql
INSERT INTO quant.positions (instrument_id, model_id, quantity, entry_price, current_price, pnl, pnl_pct, opened_at, updated_at)
VALUES
    (1, 1, 500,  182.34, 187.50,  2580.00,  0.0283, now() - interval '5 days', now()),
    (2, 1, 300,  370.10, 374.80,  1410.00,  0.0127, now() - interval '3 days', now()),
    (3, 2, 200,  140.50, 138.20, -460.00,  -0.0164, now() - interval '7 days', now());
```

Expected output:
```
INSERT 0 3
```

Insert sample backtests:

```sql
INSERT INTO quant.backtests (model_id, start_date, end_date, sharpe_ratio, max_drawdown, total_return, num_trades, win_rate, created_at)
VALUES
    (1, '2022-01-01', '2023-12-31', 1.42, -0.1230, 0.2310, 1842, 0.5430, now()),
    (2, '2022-01-01', '2023-12-31', 1.18, -0.1540, 0.1870, 2103, 0.5120, now()),
    (3, '2020-01-01', '2023-12-31', 1.67, -0.0980, 0.4120, 3450, 0.5780, now());
```

Expected output:
```
INSERT 0 3
```

Insert sample ops data:

```sql
INSERT INTO ops.deployments (model_id, model_version, environment, status, deployed_by, is_rollback, deployed_at, completed_at)
VALUES
    (1, '1.0', 'production', 'success', 'ops_admin', false, now() - interval '30 days', now() - interval '30 days' + interval '5 minutes'),
    (2, '2.1', 'production', 'success', 'ops_admin', false, now() - interval '14 days', now() - interval '14 days' + interval '3 minutes'),
    (3, '3.0', 'staging',    'running', 'ops_admin', false, now() - interval '1 day',  null);
```

Expected output:
```
INSERT 0 3
```

```sql
INSERT INTO ops.pipeline_runs (pipeline_name, source, rows_processed, rows_failed, duration_seconds, status, started_at, completed_at)
VALUES
    ('market_data_loader', 'bloomberg_api', 45230, 0,  142, 'success', now() - interval '1 day', now() - interval '1 day' + interval '142 seconds'),
    ('signal_generator',   'internal',      45230, 12,  89, 'success', now() - interval '1 day', now() - interval '1 day' + interval '89 seconds'),
    ('feature_pipeline',   'internal',      180920, 0, 310, 'success', now() - interval '1 day', now() - interval '1 day' + interval '310 seconds');
```

Expected output:
```
INSERT 0 3
```

---

### Alternative: Load Everything from quantdb.sql

In the actual lab environment, you can skip the manual inserts above and load everything at once using the provided SQL dump file. Exit psql first, then run:

```bash
psql -d quantdb -f /tmp/quantdb.sql
```

`psql -d quantdb` connects to the `quantdb` database. The `-f` flag reads and executes all SQL statements from the file. This is the fastest way to reproduce the full schema and data set on a new server.

---

## Step 15: Create Indexes

Indexes speed up queries by giving PostgreSQL a fast lookup structure instead of scanning every row. Create them after loading data so the inserts are not slowed down by index maintenance.

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

Index for market data lookups by instrument and date (the most common query pattern):

```sql
CREATE INDEX idx_market_data_instrument_date
    ON quant.market_data (instrument_id, trade_date);
```

Index for signal lookups by model and date:

```sql
CREATE INDEX idx_signals_model_date
    ON quant.signals (model_id, signal_date);
```

Index for position lookups by instrument:

```sql
CREATE INDEX idx_positions_instrument
    ON quant.positions (instrument_id);
```

Expected output (for each):
```
CREATE INDEX
```

---

## Step 16: Run ANALYZE

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

```sql
ANALYZE;
```

`ANALYZE` scans the tables and collects statistics about the data distribution - how many rows, what values appear most often, etc. PostgreSQL's query planner uses these statistics to choose the most efficient execution plan for each query. Always run `ANALYZE` after loading significant amounts of data.

Expected output:
```
ANALYZE
```

---

## Step 17: Verify Row Counts

Still as **postgres** on **pg-primary**, inside psql, connected to quantdb:

Check row counts for all key tables:

```sql
SELECT 'quant.instruments'   AS table_name, COUNT(*) AS rows FROM quant.instruments
UNION ALL
SELECT 'quant.market_data',                 COUNT(*)          FROM quant.market_data
UNION ALL
SELECT 'quant.models',                      COUNT(*)          FROM quant.models
UNION ALL
SELECT 'quant.signals',                     COUNT(*)          FROM quant.signals
UNION ALL
SELECT 'quant.positions',                   COUNT(*)          FROM quant.positions
UNION ALL
SELECT 'quant.backtests',                   COUNT(*)          FROM quant.backtests
UNION ALL
SELECT 'ops.deployments',                   COUNT(*)          FROM ops.deployments
UNION ALL
SELECT 'ops.pipeline_runs',                 COUNT(*)          FROM ops.pipeline_runs
UNION ALL
SELECT 'ops.alerts',                        COUNT(*)          FROM ops.alerts
ORDER BY table_name;
```

Expected output (yours will differ):
```
      table_name       | rows
-----------------------+------
 ops.alerts            |    0
 ops.deployments       |    3
 ops.pipeline_runs     |    3
 quant.backtests       |    3
 quant.instruments     |    8
 quant.market_data     |   23
 quant.models          |    4
 quant.positions       |    3
 quant.signals         |   23
(9 rows)
```

Confirm the extension is installed:

```sql
SELECT extname, extversion FROM pg_extension;
```

Expected output (yours will differ):
```
       extname        | extversion
----------------------+------------
 plpgsql              | 1.0
 pg_stat_statements   | 1.10
(2 rows)
```

---

## Step 18: Exit psql and the postgres Session

Still as **postgres** on **pg-primary**, inside psql:

```sql
\q
```

Now exit the postgres OS user session:

```bash
exit
```

You are back as `ec2-user` on pg-primary.

---

## Summary

You have:
- Created the `quantdb` database
- Created five application roles with appropriate privilege levels
- Built a two-schema design (`quant` for trading data, `ops` for infrastructure)
- Created seven tables in the `quant` schema and three in the `ops` schema
- Created monthly range partitions for `market_data` and `signals` (2024)
- Granted fine-grained permissions to each role
- Loaded seed data and created performance indexes
- Enabled `pg_stat_statements` for query monitoring
- Verified the schema with row count checks

The database is now ready for the USE exercises, where you will run analytical queries, investigate query plans, and practice DBA tasks against a realistic quantitative finance data model.
