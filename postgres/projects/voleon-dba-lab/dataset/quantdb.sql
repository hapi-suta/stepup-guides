-- ============================================================================
-- quantdb.sql - Seed data for Quantitative AI/ML Finance Trading Platform
-- ============================================================================
-- Database : quantdb
-- Purpose  : Full schema + seed data for a quant finance research & trading
--            platform with instruments, market data, ML models, signals,
--            positions, backtests, feature stores, and ops infrastructure.
-- Author   : Happy Afopezi
-- Created  : 2026-06-15
-- Runtime  : ~3-5 minutes depending on hardware
-- Row counts:
--   quant.instruments     ~50,000
--   quant.market_data     ~10,000,000 (partitioned, 12 monthly partitions)
--   quant.models          ~500
--   quant.signals         ~5,000,000 (partitioned, 12 monthly partitions)
--   quant.positions       ~200,000
--   quant.backtests       ~10,000
--   quant.model_features  ~2,000,000
--   ops.deployments       ~2,000
--   ops.pipeline_runs     ~5,000
--   ops.alerts            (trigger-populated)
-- ============================================================================

\set ON_ERROR_STOP on
\timing on

BEGIN;

-- ============================================================================
-- 1. EXTENSIONS
-- ============================================================================
-- pg_stat_statements: query performance monitoring for the trading platform
-- pgcrypto: cryptographic functions for hashing sensitive model parameters
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 2. SCHEMAS
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS quant;   -- research + trading tables
CREATE SCHEMA IF NOT EXISTS ops;     -- infrastructure operations

COMMENT ON SCHEMA quant IS 'Quantitative research and trading - instruments, market data, models, signals, positions';
COMMENT ON SCHEMA ops   IS 'Infrastructure operations - deployments, pipeline runs, audit alerts';

-- ============================================================================
-- 3. TABLE DEFINITIONS
-- ============================================================================

-- --------------------------------------------------------------------------
-- 3a. quant.instruments - Universe of tradeable instruments
-- --------------------------------------------------------------------------

CREATE TABLE quant.instruments (
    instrument_id   SERIAL          PRIMARY KEY,
    ticker          VARCHAR(20)     UNIQUE NOT NULL,
    isin            VARCHAR(12)     UNIQUE,
    name            VARCHAR(200)    NOT NULL,
    asset_class     VARCHAR(20)     NOT NULL
                        CHECK (asset_class IN ('stock', 'etf', 'future', 'option', 'bond', 'fx')),
    exchange        VARCHAR(20)     NOT NULL,
    sector          VARCHAR(50),
    market_cap_usd  NUMERIC(18,2),
    currency        CHAR(3)         NOT NULL DEFAULT 'USD',
    is_active       BOOLEAN         NOT NULL DEFAULT true,
    listed_date     DATE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE  quant.instruments              IS 'Master universe of tradeable financial instruments across all asset classes';
COMMENT ON COLUMN quant.instruments.ticker       IS 'Exchange ticker symbol - unique across universe';
COMMENT ON COLUMN quant.instruments.isin         IS 'ISO 6166 International Securities Identification Number';
COMMENT ON COLUMN quant.instruments.asset_class  IS 'Broad asset class categorization';
COMMENT ON COLUMN quant.instruments.sector       IS 'GICS sector classification (equities only)';
COMMENT ON COLUMN quant.instruments.market_cap_usd IS 'Market capitalization in USD - null for non-equity instruments';

-- --------------------------------------------------------------------------
-- 3b. quant.market_data - Daily OHLCV market data (PARTITIONED)
-- --------------------------------------------------------------------------

CREATE TABLE quant.market_data (
    data_id         BIGSERIAL,
    instrument_id   INT             NOT NULL,
    trade_date      DATE            NOT NULL,
    open_price      NUMERIC(14,4)   NOT NULL,
    high_price      NUMERIC(14,4)   NOT NULL,
    low_price       NUMERIC(14,4)   NOT NULL,
    close_price     NUMERIC(14,4)   NOT NULL,
    volume          BIGINT          NOT NULL,
    vwap            NUMERIC(14,4),
    source_feed     VARCHAR(30)     NOT NULL
                        CHECK (source_feed IN ('bloomberg', 'refinitiv', 'polygon', 'internal')),
    received_at     TIMESTAMPTZ     NOT NULL DEFAULT now(),
    PRIMARY KEY (data_id, trade_date)
) PARTITION BY RANGE (trade_date);

COMMENT ON TABLE  quant.market_data             IS 'Daily OHLCV market data - partitioned monthly by trade_date for fast range scans';
COMMENT ON COLUMN quant.market_data.vwap        IS 'Volume-weighted average price for the trading day';
COMMENT ON COLUMN quant.market_data.source_feed IS 'Data vendor that supplied this bar';

-- Monthly partitions: 2025-07 through 2026-06 (12 months)
CREATE TABLE quant.market_data_2025_07 PARTITION OF quant.market_data
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE quant.market_data_2025_08 PARTITION OF quant.market_data
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE quant.market_data_2025_09 PARTITION OF quant.market_data
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE quant.market_data_2025_10 PARTITION OF quant.market_data
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE quant.market_data_2025_11 PARTITION OF quant.market_data
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE quant.market_data_2025_12 PARTITION OF quant.market_data
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
CREATE TABLE quant.market_data_2026_01 PARTITION OF quant.market_data
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE quant.market_data_2026_02 PARTITION OF quant.market_data
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE quant.market_data_2026_03 PARTITION OF quant.market_data
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE quant.market_data_2026_04 PARTITION OF quant.market_data
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE quant.market_data_2026_05 PARTITION OF quant.market_data
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE quant.market_data_2026_06 PARTITION OF quant.market_data
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- --------------------------------------------------------------------------
-- 3c. quant.models - ML/AI model registry
-- --------------------------------------------------------------------------

CREATE TABLE quant.models (
    model_id            SERIAL          PRIMARY KEY,
    model_name          VARCHAR(100)    NOT NULL,
    version             VARCHAR(20)     NOT NULL,
    framework           VARCHAR(30)     NOT NULL
                            CHECK (framework IN ('pytorch', 'tensorflow', 'xgboost', 'lightgbm', 'sklearn', 'custom')),
    model_type          VARCHAR(30)     NOT NULL
                            CHECK (model_type IN ('alpha_signal', 'risk_model', 'execution', 'portfolio_opt', 'feature_eng')),
    training_dataset    VARCHAR(100),
    training_start_date DATE,
    training_end_date   DATE,
    feature_count       INT,
    status              VARCHAR(20)     NOT NULL
                            CHECK (status IN ('development', 'backtesting', 'staging', 'production', 'retired')),
    sharpe_ratio        NUMERIC(6,3),
    max_drawdown        NUMERIC(6,4),
    created_by          VARCHAR(50),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    UNIQUE (model_name, version)
);

COMMENT ON TABLE  quant.models              IS 'Central model registry - every ML/AI model version is tracked here with metadata and performance stats';
COMMENT ON COLUMN quant.models.sharpe_ratio IS 'Out-of-sample Sharpe ratio from most recent backtest';
COMMENT ON COLUMN quant.models.max_drawdown IS 'Maximum drawdown as a decimal fraction (e.g. 0.15 = 15%)';
COMMENT ON COLUMN quant.models.status       IS 'Model lifecycle stage: development -> backtesting -> staging -> production -> retired';

-- --------------------------------------------------------------------------
-- 3d. quant.signals - Model-generated trading signals (PARTITIONED)
-- --------------------------------------------------------------------------

CREATE TABLE quant.signals (
    signal_id       BIGSERIAL,
    model_id        INT             NOT NULL,
    instrument_id   INT             NOT NULL,
    signal_date     DATE            NOT NULL,
    score           NUMERIC(8,5)    NOT NULL
                        CHECK (score >= -1.0 AND score <= 1.0),
    confidence      NUMERIC(5,4)
                        CHECK (confidence >= 0 AND confidence <= 1),
    decay_hours     INT             NOT NULL DEFAULT 24,
    signal_type     VARCHAR(20)     NOT NULL
                        CHECK (signal_type IN ('long', 'short', 'neutral', 'hold')),
    generated_at    TIMESTAMPTZ     NOT NULL DEFAULT now(),
    PRIMARY KEY (signal_id, signal_date)
) PARTITION BY RANGE (signal_date);

COMMENT ON TABLE  quant.signals            IS 'Trading signals produced by ML models - partitioned monthly for efficient date-range queries';
COMMENT ON COLUMN quant.signals.score      IS 'Signal strength from -1.0 (strong short) to +1.0 (strong long)';
COMMENT ON COLUMN quant.signals.confidence IS 'Model confidence in this signal, 0 to 1';
COMMENT ON COLUMN quant.signals.decay_hours IS 'Signal half-life in hours - how quickly the signal loses predictive power';

-- Monthly partitions: 2025-07 through 2026-06
CREATE TABLE quant.signals_2025_07 PARTITION OF quant.signals
    FOR VALUES FROM ('2025-07-01') TO ('2025-08-01');
CREATE TABLE quant.signals_2025_08 PARTITION OF quant.signals
    FOR VALUES FROM ('2025-08-01') TO ('2025-09-01');
CREATE TABLE quant.signals_2025_09 PARTITION OF quant.signals
    FOR VALUES FROM ('2025-09-01') TO ('2025-10-01');
CREATE TABLE quant.signals_2025_10 PARTITION OF quant.signals
    FOR VALUES FROM ('2025-10-01') TO ('2025-11-01');
CREATE TABLE quant.signals_2025_11 PARTITION OF quant.signals
    FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
CREATE TABLE quant.signals_2025_12 PARTITION OF quant.signals
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
CREATE TABLE quant.signals_2026_01 PARTITION OF quant.signals
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE quant.signals_2026_02 PARTITION OF quant.signals
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE quant.signals_2026_03 PARTITION OF quant.signals
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE quant.signals_2026_04 PARTITION OF quant.signals
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE quant.signals_2026_05 PARTITION OF quant.signals
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE quant.signals_2026_06 PARTITION OF quant.signals
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- --------------------------------------------------------------------------
-- 3e. quant.positions - Current and historical portfolio positions
-- --------------------------------------------------------------------------

CREATE TABLE quant.positions (
    position_id     SERIAL          PRIMARY KEY,
    instrument_id   INT             NOT NULL,
    model_id        INT,
    side            VARCHAR(10)     NOT NULL
                        CHECK (side IN ('long', 'short')),
    quantity        NUMERIC(14,4)   NOT NULL,
    entry_price     NUMERIC(14,4)   NOT NULL,
    current_price   NUMERIC(14,4),
    entry_date      DATE            NOT NULL,
    exit_date       DATE,
    realized_pnl    NUMERIC(16,2),
    unrealized_pnl  NUMERIC(16,2),
    portfolio       VARCHAR(30)     NOT NULL,
    status          VARCHAR(20)     NOT NULL
                        CHECK (status IN ('open', 'closed', 'partial')),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE  quant.positions               IS 'Position book - all open and closed positions across all portfolios and strategies';
COMMENT ON COLUMN quant.positions.portfolio     IS 'Strategy/portfolio bucket (alpha_1, risk_parity, stat_arb, etc.)';
COMMENT ON COLUMN quant.positions.realized_pnl  IS 'Realized P&L for closed/partial positions in USD';
COMMENT ON COLUMN quant.positions.unrealized_pnl IS 'Mark-to-market unrealized P&L for open positions in USD';

-- --------------------------------------------------------------------------
-- 3f. quant.backtests - Historical backtest results
-- --------------------------------------------------------------------------

CREATE TABLE quant.backtests (
    backtest_id     SERIAL          PRIMARY KEY,
    model_id        INT             NOT NULL,
    backtest_name   VARCHAR(100),
    start_date      DATE            NOT NULL,
    end_date        DATE            NOT NULL,
    universe_size   INT,
    sharpe_ratio    NUMERIC(6,3),
    annual_return   NUMERIC(8,4),
    max_drawdown    NUMERIC(6,4),
    turnover_annual NUMERIC(8,4),
    total_trades    INT,
    win_rate        NUMERIC(5,4),
    status          VARCHAR(20)     NOT NULL
                        CHECK (status IN ('running', 'completed', 'failed')),
    compute_hours   NUMERIC(8,2),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE  quant.backtests               IS 'Backtest run results - tracks performance metrics for every model evaluation';
COMMENT ON COLUMN quant.backtests.sharpe_ratio   IS 'Annualized Sharpe ratio from the backtest period';
COMMENT ON COLUMN quant.backtests.turnover_annual IS 'Annualized portfolio turnover as a fraction';
COMMENT ON COLUMN quant.backtests.compute_hours  IS 'Total GPU/CPU hours consumed by this backtest run';

-- --------------------------------------------------------------------------
-- 3g. quant.model_features - Feature store for model inputs
-- --------------------------------------------------------------------------

CREATE TABLE quant.model_features (
    feature_id      BIGSERIAL       PRIMARY KEY,
    model_id        INT             NOT NULL,
    feature_name    VARCHAR(100)    NOT NULL,
    feature_value   NUMERIC(14,6),
    instrument_id   INT,
    computed_at     TIMESTAMPTZ     NOT NULL,
    valid_from      TIMESTAMPTZ     NOT NULL,
    valid_to        TIMESTAMPTZ
);

COMMENT ON TABLE  quant.model_features             IS 'Time-versioned feature store - computed features used as model inputs';
COMMENT ON COLUMN quant.model_features.valid_from   IS 'Start of validity window - prevents look-ahead bias';
COMMENT ON COLUMN quant.model_features.valid_to     IS 'End of validity window - NULL means still current';

-- --------------------------------------------------------------------------
-- 3h. ops.deployments - Model deployment history
-- --------------------------------------------------------------------------

CREATE TABLE ops.deployments (
    deployment_id   SERIAL          PRIMARY KEY,
    model_id        INT             NOT NULL,
    model_version   VARCHAR(20)     NOT NULL,
    environment     VARCHAR(20)     NOT NULL
                        CHECK (environment IN ('development', 'staging', 'production')),
    action          VARCHAR(20)     NOT NULL
                        CHECK (action IN ('deploy', 'rollback', 'scale', 'config_change')),
    promoted_by     VARCHAR(50),
    approved_by     VARCHAR(50),
    status          VARCHAR(20)     NOT NULL
                        CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'rolled_back')),
    deployed_at     TIMESTAMPTZ     NOT NULL DEFAULT now(),
    notes           TEXT
);

COMMENT ON TABLE  ops.deployments           IS 'Deployment audit trail - every model promotion, rollback, and config change';
COMMENT ON COLUMN ops.deployments.action    IS 'Type of deployment action taken';
COMMENT ON COLUMN ops.deployments.status    IS 'Current state of this deployment';

-- --------------------------------------------------------------------------
-- 3i. ops.pipeline_runs - Data pipeline execution history
-- --------------------------------------------------------------------------

CREATE TABLE ops.pipeline_runs (
    run_id          SERIAL          PRIMARY KEY,
    pipeline_name   VARCHAR(100)    NOT NULL,
    source          VARCHAR(50)     NOT NULL,
    start_time      TIMESTAMPTZ     NOT NULL,
    end_time        TIMESTAMPTZ,
    rows_processed  BIGINT,
    rows_failed     BIGINT          NOT NULL DEFAULT 0,
    status          VARCHAR(20)     NOT NULL
                        CHECK (status IN ('running', 'completed', 'failed', 'timeout')),
    error_message   TEXT,
    triggered_by    VARCHAR(30)     NOT NULL
                        CHECK (triggered_by IN ('schedule', 'manual', 'dependency', 'retry'))
);

COMMENT ON TABLE  ops.pipeline_runs              IS 'Execution log for all data pipelines - ingestion, feature computation, signal generation';
COMMENT ON COLUMN ops.pipeline_runs.rows_failed  IS 'Number of rows that failed validation or transformation';
COMMENT ON COLUMN ops.pipeline_runs.triggered_by IS 'What initiated this pipeline run';

-- --------------------------------------------------------------------------
-- 3j. ops.alerts - Audit trail (trigger-populated)
-- --------------------------------------------------------------------------

CREATE TABLE ops.alerts (
    alert_id        BIGSERIAL       PRIMARY KEY,
    source_table    VARCHAR(50)     NOT NULL,
    record_id       INT             NOT NULL,
    alert_type      VARCHAR(20)     NOT NULL
                        CHECK (alert_type IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data        JSONB,
    new_data        JSONB,
    triggered_by    VARCHAR(100)    DEFAULT current_user,
    triggered_at    TIMESTAMPTZ     NOT NULL DEFAULT now(),
    client_ip       INET            DEFAULT inet_client_addr()
);

COMMENT ON TABLE  ops.alerts             IS 'Audit log populated by triggers on critical tables - captures before/after state as JSONB';
COMMENT ON COLUMN ops.alerts.old_data    IS 'Previous row state as JSONB (NULL for INSERT)';
COMMENT ON COLUMN ops.alerts.new_data    IS 'New row state as JSONB (NULL for DELETE)';

-- ============================================================================
-- 4. FOREIGN KEYS
-- ============================================================================
-- Added after all tables exist to avoid ordering issues during creation.
-- Partitioned tables cannot have standard FK constraints referencing them,
-- but we add FKs on the referencing side pointing to non-partitioned parents.
-- ============================================================================

ALTER TABLE quant.positions
    ADD CONSTRAINT fk_positions_instrument
        FOREIGN KEY (instrument_id) REFERENCES quant.instruments(instrument_id),
    ADD CONSTRAINT fk_positions_model
        FOREIGN KEY (model_id) REFERENCES quant.models(model_id);

ALTER TABLE quant.backtests
    ADD CONSTRAINT fk_backtests_model
        FOREIGN KEY (model_id) REFERENCES quant.models(model_id);

ALTER TABLE quant.model_features
    ADD CONSTRAINT fk_model_features_model
        FOREIGN KEY (model_id) REFERENCES quant.models(model_id),
    ADD CONSTRAINT fk_model_features_instrument
        FOREIGN KEY (instrument_id) REFERENCES quant.instruments(instrument_id);

ALTER TABLE ops.deployments
    ADD CONSTRAINT fk_deployments_model
        FOREIGN KEY (model_id) REFERENCES quant.models(model_id);

-- Note: quant.market_data and quant.signals are partitioned tables.
-- FK constraints on partitioned children referencing quant.instruments/quant.models
-- are supported in PG12+ but we skip them here to avoid per-partition overhead
-- during the 15M-row bulk load. Referential integrity is enforced at the
-- application/pipeline layer instead.

-- ============================================================================
-- 5. AUDIT TRIGGER FUNCTION AND TRIGGERS
-- ============================================================================

CREATE OR REPLACE FUNCTION ops.fn_ops_alert_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_record_id INT;
BEGIN
    -- Determine the record_id from the appropriate row
    IF TG_OP = 'DELETE' THEN
        v_record_id := (OLD).* :: TEXT :: INT; -- fallback
        -- Extract the primary key (first column) from OLD
        EXECUTE format('SELECT ($1).%I', TG_ARGV[0]) INTO v_record_id USING OLD;
    ELSE
        EXECUTE format('SELECT ($1).%I', TG_ARGV[0]) INTO v_record_id USING NEW;
    END IF;

    INSERT INTO ops.alerts (source_table, record_id, alert_type, old_data, new_data)
    VALUES (
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        v_record_id,
        TG_OP,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
    );

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$;

COMMENT ON FUNCTION ops.fn_ops_alert_trigger() IS 'Generic audit trigger - captures INSERT/UPDATE/DELETE as JSONB into ops.alerts';

-- Trigger on quant.models
CREATE TRIGGER trg_models_audit
    AFTER INSERT OR UPDATE OR DELETE ON quant.models
    FOR EACH ROW
    EXECUTE FUNCTION ops.fn_ops_alert_trigger('model_id');

-- Trigger on ops.deployments
CREATE TRIGGER trg_deployments_audit
    AFTER INSERT OR UPDATE OR DELETE ON ops.deployments
    FOR EACH ROW
    EXECUTE FUNCTION ops.fn_ops_alert_trigger('deployment_id');

-- ============================================================================
-- 6. DISABLE TRIGGERS FOR BULK LOAD
-- ============================================================================
-- Disabling triggers during seed data insertion avoids millions of audit
-- rows and dramatically speeds up the load.
-- ============================================================================

ALTER TABLE quant.models    DISABLE TRIGGER trg_models_audit;
ALTER TABLE ops.deployments DISABLE TRIGGER trg_deployments_audit;

-- ============================================================================
-- 7. SEED DATA
-- ============================================================================

-- --------------------------------------------------------------------------
-- 7a. quant.instruments (~50,000 rows)
-- --------------------------------------------------------------------------
-- First 100: well-known real tickers for demo queries.
-- Remaining 49,900: generated tickers with realistic distributions.
-- --------------------------------------------------------------------------

-- Well-known tickers (representative sample across sectors and asset classes)
INSERT INTO quant.instruments (ticker, isin, name, asset_class, exchange, sector, market_cap_usd, currency, is_active, listed_date)
VALUES
    ('AAPL',  'US0378331005', 'Apple Inc.',                        'stock',  'NASDAQ', 'Technology',            3200000000000.00, 'USD', true,  '1980-12-12'),
    ('MSFT',  'US5949181045', 'Microsoft Corporation',             'stock',  'NASDAQ', 'Technology',            2900000000000.00, 'USD', true,  '1986-03-13'),
    ('GOOGL', 'US02079K3059', 'Alphabet Inc. Class A',             'stock',  'NASDAQ', 'Technology',            2100000000000.00, 'USD', true,  '2004-08-19'),
    ('AMZN',  'US0231351067', 'Amazon.com Inc.',                   'stock',  'NASDAQ', 'Consumer Discretionary', 1950000000000.00, 'USD', true,  '1997-05-15'),
    ('NVDA',  'US67066G1040', 'NVIDIA Corporation',                'stock',  'NASDAQ', 'Technology',            2800000000000.00, 'USD', true,  '1999-01-22'),
    ('META',  'US30303M1027', 'Meta Platforms Inc.',                'stock',  'NASDAQ', 'Technology',            1400000000000.00, 'USD', true,  '2012-05-18'),
    ('TSLA',  'US88160R1014', 'Tesla Inc.',                        'stock',  'NASDAQ', 'Consumer Discretionary',  850000000000.00, 'USD', true,  '2010-06-29'),
    ('BRK.B', 'US0846707026', 'Berkshire Hathaway Inc. Class B',   'stock',  'NYSE',   'Financials',             900000000000.00, 'USD', true,  '1996-05-09'),
    ('JPM',   'US46625H1005', 'JPMorgan Chase & Co.',              'stock',  'NYSE',   'Financials',             620000000000.00, 'USD', true,  '1969-03-05'),
    ('V',     'US92826C8394', 'Visa Inc.',                         'stock',  'NYSE',   'Financials',             560000000000.00, 'USD', true,  '2008-03-19'),
    ('JNJ',   'US4781601046', 'Johnson & Johnson',                 'stock',  'NYSE',   'Healthcare',             400000000000.00, 'USD', true,  '1944-09-25'),
    ('UNH',   'US91324P1021', 'UnitedHealth Group Inc.',           'stock',  'NYSE',   'Healthcare',             480000000000.00, 'USD', true,  '1984-10-17'),
    ('XOM',   'US30231G1022', 'Exxon Mobil Corporation',           'stock',  'NYSE',   'Energy',                 450000000000.00, 'USD', true,  '1970-01-02'),
    ('PG',    'US7427181091', 'Procter & Gamble Co.',              'stock',  'NYSE',   'Consumer Staples',       380000000000.00, 'USD', true,  '1890-01-01'),
    ('MA',    'US57636Q1040', 'Mastercard Inc.',                   'stock',  'NYSE',   'Financials',             420000000000.00, 'USD', true,  '2006-05-25'),
    ('HD',    'US4370761029', 'Home Depot Inc.',                   'stock',  'NYSE',   'Consumer Discretionary',  370000000000.00, 'USD', true,  '1981-09-22'),
    ('CVX',   'US1667641005', 'Chevron Corporation',               'stock',  'NYSE',   'Energy',                 300000000000.00, 'USD', true,  '1926-01-01'),
    ('LLY',   'US5324571083', 'Eli Lilly and Company',             'stock',  'NYSE',   'Healthcare',             750000000000.00, 'USD', true,  '1952-01-01'),
    ('ABBV',  'US00287Y1091', 'AbbVie Inc.',                       'stock',  'NYSE',   'Healthcare',             310000000000.00, 'USD', true,  '2013-01-02'),
    ('MRK',   'US58933Y1055', 'Merck & Co. Inc.',                 'stock',  'NYSE',   'Healthcare',             280000000000.00, 'USD', true,  '1946-01-01'),
    ('PEP',   'US7134481081', 'PepsiCo Inc.',                     'stock',  'NASDAQ', 'Consumer Staples',       230000000000.00, 'USD', true,  '1919-01-01'),
    ('KO',    'US1912161007', 'Coca-Cola Company',                'stock',  'NYSE',   'Consumer Staples',       260000000000.00, 'USD', true,  '1919-09-05'),
    ('AVGO',  'US11135F1012', 'Broadcom Inc.',                    'stock',  'NASDAQ', 'Technology',             650000000000.00, 'USD', true,  '2009-08-06'),
    ('COST',  'US22160K1051', 'Costco Wholesale Corporation',     'stock',  'NASDAQ', 'Consumer Staples',       340000000000.00, 'USD', true,  '1985-12-05'),
    ('TMO',   'US8835561023', 'Thermo Fisher Scientific Inc.',    'stock',  'NYSE',   'Healthcare',             210000000000.00, 'USD', true,  '1980-01-01'),
    ('WMT',   'US9311421039', 'Walmart Inc.',                     'stock',  'NYSE',   'Consumer Staples',       550000000000.00, 'USD', true,  '1972-08-25'),
    ('BAC',   'US0605051046', 'Bank of America Corporation',      'stock',  'NYSE',   'Financials',             320000000000.00, 'USD', true,  '1973-01-01'),
    ('CRM',   'US79466L3024', 'Salesforce Inc.',                  'stock',  'NYSE',   'Technology',             260000000000.00, 'USD', true,  '2004-06-23'),
    ('ACN',   'IE00B4BNMY34', 'Accenture PLC',                   'stock',  'NYSE',   'Technology',             220000000000.00, 'USD', true,  '2001-07-19'),
    ('NFLX',  'US64110L1061', 'Netflix Inc.',                     'stock',  'NASDAQ', 'Technology',             280000000000.00, 'USD', true,  '2002-05-23'),
    -- ETFs
    ('SPY',   'US78462F1030', 'SPDR S&P 500 ETF Trust',          'etf',    'NYSE',   NULL,                     500000000000.00, 'USD', true,  '1993-01-22'),
    ('QQQ',   'US46090E1038', 'Invesco QQQ Trust',                'etf',    'NASDAQ', NULL,                     250000000000.00, 'USD', true,  '1999-03-10'),
    ('IWM',   'US4642876555', 'iShares Russell 2000 ETF',         'etf',    'NYSE',   NULL,                      65000000000.00, 'USD', true,  '2000-05-22'),
    ('EEM',   'US4642872422', 'iShares MSCI Emerging Markets',    'etf',    'NYSE',   NULL,                      25000000000.00, 'USD', true,  '2003-04-07'),
    ('TLT',   'US4642874659', 'iShares 20+ Year Treasury Bond',   'etf',    'NASDAQ', NULL,                      18000000000.00, 'USD', true,  '2002-07-22'),
    ('GLD',   'US46428Q1094', 'SPDR Gold Shares',                 'etf',    'NYSE',   NULL,                      60000000000.00, 'USD', true,  '2004-11-18'),
    ('VTI',   'US9220427424', 'Vanguard Total Stock Market',      'etf',    'NYSE',   NULL,                     380000000000.00, 'USD', true,  '2001-05-24'),
    ('XLF',   'US81369Y8030', 'Financial Select Sector SPDR',     'etf',    'NYSE',   NULL,                      40000000000.00, 'USD', true,  '1998-12-16'),
    ('XLE',   'US81369Y5069', 'Energy Select Sector SPDR',        'etf',    'NYSE',   NULL,                      35000000000.00, 'USD', true,  '1998-12-16'),
    ('XLK',   'US81369Y8600', 'Technology Select Sector SPDR',    'etf',    'NYSE',   NULL,                      55000000000.00, 'USD', true,  '1998-12-16'),
    -- Futures
    ('ES=F',  NULL,            'E-mini S&P 500 Future',           'future', 'CME',    NULL,                     NULL,             'USD', true,  '1997-09-09'),
    ('NQ=F',  NULL,            'E-mini NASDAQ 100 Future',        'future', 'CME',    NULL,                     NULL,             'USD', true,  '1999-06-21'),
    ('CL=F',  NULL,            'Crude Oil WTI Future',            'future', 'CME',    NULL,                     NULL,             'USD', true,  '1983-03-30'),
    ('GC=F',  NULL,            'Gold Future',                     'future', 'CME',    NULL,                     NULL,             'USD', true,  '1974-12-31'),
    ('ZB=F',  NULL,            'U.S. Treasury Bond Future',       'future', 'CME',    NULL,                     NULL,             'USD', true,  '1977-08-22'),
    ('ZN=F',  NULL,            '10-Year T-Note Future',           'future', 'CME',    NULL,                     NULL,             'USD', true,  '1982-05-03'),
    -- FX
    ('EURUSD', NULL,           'Euro / US Dollar',                'fx',     'CME',    NULL,                     NULL,             'USD', true,  '1999-01-04'),
    ('GBPUSD', NULL,           'British Pound / US Dollar',       'fx',     'CME',    NULL,                     NULL,             'USD', true,  '1972-01-01'),
    ('USDJPY', NULL,           'US Dollar / Japanese Yen',        'fx',     'CME',    NULL,                     NULL,             'JPY', true,  '1972-01-01'),
    ('AUDUSD', NULL,           'Australian Dollar / US Dollar',   'fx',     'CME',    NULL,                     NULL,             'USD', true,  '1987-01-01'),
    -- Additional well-known stocks
    ('DIS',   'US2546871060', 'Walt Disney Company',              'stock',  'NYSE',   'Communication Services',  170000000000.00, 'USD', true,  '1957-11-12'),
    ('INTC',  'US4581401001', 'Intel Corporation',                'stock',  'NASDAQ', 'Technology',              120000000000.00, 'USD', true,  '1971-10-13'),
    ('AMD',   'US0079031078', 'Advanced Micro Devices Inc.',      'stock',  'NASDAQ', 'Technology',              240000000000.00, 'USD', true,  '1972-09-27'),
    ('PYPL',  'US70450Y1038', 'PayPal Holdings Inc.',             'stock',  'NASDAQ', 'Financials',               70000000000.00, 'USD', true,  '2015-07-20'),
    ('ADBE',  'US00724F1012', 'Adobe Inc.',                       'stock',  'NASDAQ', 'Technology',              230000000000.00, 'USD', true,  '1986-08-20'),
    ('CMCSA', 'US20030N1019', 'Comcast Corporation',              'stock',  'NASDAQ', 'Communication Services',  160000000000.00, 'USD', true,  '1972-06-29'),
    ('NKE',   'US6541061031', 'Nike Inc.',                        'stock',  'NYSE',   'Consumer Discretionary',  140000000000.00, 'USD', true,  '1980-12-02'),
    ('T',     'US00206R1023', 'AT&T Inc.',                        'stock',  'NYSE',   'Communication Services',  120000000000.00, 'USD', true,  '1984-01-01'),
    ('VZ',    'US92343V1044', 'Verizon Communications Inc.',      'stock',  'NYSE',   'Communication Services',  155000000000.00, 'USD', true,  '2000-07-03'),
    ('NEE',   'US65339F1012', 'NextEra Energy Inc.',              'stock',  'NYSE',   'Utilities',               150000000000.00, 'USD', true,  '1985-01-01'),
    -- Bonds
    ('AGG',   'US4642882579', 'iShares Core US Aggregate Bond',   'bond',   'NYSE',   NULL,                      90000000000.00, 'USD', true,  '2003-09-22'),
    ('BND',   'US9219378356', 'Vanguard Total Bond Market',       'bond',   'NASDAQ', NULL,                     100000000000.00, 'USD', true,  '2007-04-03'),
    ('LQD',   'US4642872349', 'iShares iBoxx Inv Grade Corp',     'bond',   'NYSE',   NULL,                      32000000000.00, 'USD', true,  '2002-07-22'),
    ('HYG',   'US4642885135', 'iShares iBoxx High Yield Corp',    'bond',   'NYSE',   NULL,                      15000000000.00, 'USD', true,  '2007-04-04'),
    -- Options
    ('SPX',   NULL,            'S&P 500 Index Options',           'option', 'CBOE',   NULL,                     NULL,             'USD', true,  '1983-07-01'),
    ('VIX',   NULL,            'CBOE Volatility Index Options',   'option', 'CBOE',   NULL,                     NULL,             'USD', true,  '2006-02-24'),
    -- International stocks
    ('SHEL',  'GB00BP6MXD84', 'Shell PLC',                       'stock',  'LSE',    'Energy',                  210000000000.00, 'GBP', true,  '2005-07-20'),
    ('HSBA',  'GB0005405286', 'HSBC Holdings PLC',               'stock',  'LSE',    'Financials',              160000000000.00, 'GBP', true,  '1991-07-01'),
    ('7203',  'JP3633400001', 'Toyota Motor Corporation',         'stock',  'TSE',    'Consumer Discretionary',  250000000000.00, 'JPY', true,  '1949-05-16'),
    ('9988',  'KYG017191142', 'Alibaba Group Holding Ltd',       'stock',  'HKEX',   'Technology',               200000000000.00, 'USD', true,  '2019-11-26'),
    ('0700',  'KYG875721634', 'Tencent Holdings Ltd',             'stock',  'HKEX',   'Technology',              380000000000.00, 'USD', true,  '2004-06-16'),
    -- More US stocks to reach 75 named
    ('GS',    'US38141G1040', 'Goldman Sachs Group Inc.',         'stock',  'NYSE',   'Financials',              140000000000.00, 'USD', true,  '1999-05-04'),
    ('MS',    'US6174464486', 'Morgan Stanley',                   'stock',  'NYSE',   'Financials',              160000000000.00, 'USD', true,  '1986-01-01'),
    ('BLK',   'US09247X1019', 'BlackRock Inc.',                   'stock',  'NYSE',   'Financials',              130000000000.00, 'USD', true,  '1999-10-01'),
    ('SCHW',  'US8085131055', 'Charles Schwab Corporation',       'stock',  'NYSE',   'Financials',               95000000000.00, 'USD', true,  '1987-09-22'),
    ('UBER',  'US90353T1007', 'Uber Technologies Inc.',           'stock',  'NYSE',   'Industrials',             140000000000.00, 'USD', true,  '2019-05-10'),
    ('SQ',    'US8522341036', 'Block Inc.',                       'stock',  'NYSE',   'Financials',               40000000000.00, 'USD', true,  '2015-11-19'),
    ('SNOW',  'US8334451098', 'Snowflake Inc.',                   'stock',  'NYSE',   'Technology',               50000000000.00, 'USD', true,  '2020-09-16'),
    ('PLTR',  'US69608A1088', 'Palantir Technologies Inc.',       'stock',  'NYSE',   'Technology',               55000000000.00, 'USD', true,  '2020-09-30'),
    ('COIN',  'US19260Q1076', 'Coinbase Global Inc.',             'stock',  'NASDAQ', 'Financials',               35000000000.00, 'USD', true,  '2021-04-14'),
    ('ABNB',  'US0090661010', 'Airbnb Inc.',                      'stock',  'NASDAQ', 'Consumer Discretionary',   75000000000.00, 'USD', true,  '2020-12-10'),
    ('RIVN',  'US76954A1034', 'Rivian Automotive Inc.',           'stock',  'NASDAQ', 'Consumer Discretionary',   12000000000.00, 'USD', true,  '2021-11-10'),
    ('SHOP',  'CA82509L1076', 'Shopify Inc.',                     'stock',  'NYSE',   'Technology',               90000000000.00, 'USD', true,  '2015-05-21'),
    ('SQ2',   NULL,            'Block Inc. Warrant',              'option', 'NYSE',   NULL,                     NULL,             'USD', false, '2020-01-01'),
    ('DOGE',  NULL,            'Dogecoin Futures',                'future', 'CME',    NULL,                     NULL,             'USD', true,  '2024-01-15'),
    ('BTC=F', NULL,            'Bitcoin Future',                  'future', 'CME',    NULL,                     NULL,             'USD', true,  '2017-12-18'),
    ('ETH=F', NULL,            'Ethereum Future',                 'future', 'CME',    NULL,                     NULL,             'USD', true,  '2021-02-08'),
    ('USDCAD', NULL,           'US Dollar / Canadian Dollar',     'fx',     'CME',    NULL,                     NULL,             'USD', true,  '1972-01-01'),
    ('USDCHF', NULL,           'US Dollar / Swiss Franc',         'fx',     'CME',    NULL,                     NULL,             'USD', true,  '1972-01-01'),
    ('NZDUSD', NULL,           'New Zealand Dollar / US Dollar',  'fx',     'CME',    NULL,                     NULL,             'USD', true,  '1987-01-01'),
    -- Additional major stocks
    ('LMT',   'US5398301094', 'Lockheed Martin Corporation',     'stock',  'NYSE',   'Industrials',             120000000000.00, 'USD', true,  '1995-03-15'),
    ('RTX',   'US75513E1010', 'RTX Corporation',                  'stock',  'NYSE',   'Industrials',             140000000000.00, 'USD', true,  '2020-04-03'),
    ('CAT',   'US1491231015', 'Caterpillar Inc.',                 'stock',  'NYSE',   'Industrials',             160000000000.00, 'USD', true,  '1929-12-02'),
    ('DE',    'US2441991054', 'Deere & Company',                  'stock',  'NYSE',   'Industrials',             110000000000.00, 'USD', true,  '1911-01-01'),
    ('UPS',   'US9113121068', 'United Parcel Service Inc.',       'stock',  'NYSE',   'Industrials',             130000000000.00, 'USD', true,  '1999-11-10'),
    ('FDX',   'US31428X1063', 'FedEx Corporation',                'stock',  'NYSE',   'Industrials',              60000000000.00, 'USD', true,  '1978-04-12'),
    ('AMT',   'US03027X1000', 'American Tower Corporation',       'stock',  'NYSE',   'Real Estate',             100000000000.00, 'USD', true,  '1998-06-04'),
    ('PLD',   'US7436121086', 'Prologis Inc.',                    'stock',  'NYSE',   'Real Estate',             110000000000.00, 'USD', true,  '1997-11-21'),
    ('D',     'US25746U1097', 'Dominion Energy Inc.',             'stock',  'NYSE',   'Utilities',                42000000000.00, 'USD', true,  '1983-01-01'),
    ('SO',    'US8425871071', 'Southern Company',                 'stock',  'NYSE',   'Utilities',                80000000000.00, 'USD', true,  '1949-01-01'),
    ('DUK',   'US26441C2044', 'Duke Energy Corporation',          'stock',  'NYSE',   'Utilities',                78000000000.00, 'USD', true,  '2012-07-02'),
    ('MMM',   'US88579Y1010', '3M Company',                      'stock',  'NYSE',   'Industrials',              55000000000.00, 'USD', true,  '1946-01-01'),
    ('MDT',   'IE00BTN1Y115', 'Medtronic PLC',                   'stock',  'NYSE',   'Healthcare',              105000000000.00, 'USD', true,  '1977-01-01'),
    ('GILD',  'US3755581036', 'Gilead Sciences Inc.',             'stock',  'NASDAQ', 'Healthcare',               95000000000.00, 'USD', true,  '1992-01-22');

-- Generate remaining ~49,900 instruments using generate_series
-- Distribution: 70% stocks, 10% etf, 8% future, 5% option, 4% bond, 3% fx
INSERT INTO quant.instruments (ticker, isin, name, asset_class, exchange, sector, market_cap_usd, currency, is_active, listed_date)
SELECT
    -- Ticker: prefix based on asset class + padded sequence number
    CASE
        WHEN asset_cls = 'stock'  THEN 'STK' || LPAD(s::TEXT, 5, '0')
        WHEN asset_cls = 'etf'    THEN 'ETF' || LPAD((s - 34900)::TEXT, 5, '0')
        WHEN asset_cls = 'future' THEN 'FUT' || LPAD((s - 39900)::TEXT, 5, '0')
        WHEN asset_cls = 'option' THEN 'OPT' || LPAD((s - 43900)::TEXT, 5, '0')
        WHEN asset_cls = 'bond'   THEN 'BND' || LPAD((s - 46400)::TEXT, 5, '0')
        WHEN asset_cls = 'fx'     THEN 'FXP' || LPAD((s - 48400)::TEXT, 5, '0')
    END AS ticker,
    -- ISIN: 2-char country code + 9-digit number + check digit
    CASE
        WHEN asset_cls IN ('stock', 'etf', 'bond') THEN
            (ARRAY['US','US','US','GB','JP','CA','DE','FR','AU','HK'])[1 + (s % 10)]
            || LPAD((1000000000 + s)::TEXT, 10, '0')
        ELSE NULL  -- futures, options, fx don't always have ISINs
    END AS isin,
    -- Name: generated from asset class and sequence
    CASE
        WHEN asset_cls = 'stock'  THEN 'Generated Equity Corp ' || s
        WHEN asset_cls = 'etf'    THEN 'Synthetic ETF Trust ' || (s - 34900)
        WHEN asset_cls = 'future' THEN 'Synthetic Future Contract ' || (s - 39900)
        WHEN asset_cls = 'option' THEN 'Synthetic Option Series ' || (s - 43900)
        WHEN asset_cls = 'bond'   THEN 'Synthetic Bond Issue ' || (s - 46400)
        WHEN asset_cls = 'fx'     THEN 'Synthetic FX Pair ' || (s - 48400)
    END AS name,
    asset_cls AS asset_class,
    -- Exchange: weighted distribution
    CASE
        WHEN asset_cls = 'future' THEN (ARRAY['CME','CME','CME','CBOE'])[1 + (s % 4)]
        WHEN asset_cls = 'option' THEN (ARRAY['CBOE','CBOE','CME','NYSE'])[1 + (s % 4)]
        WHEN asset_cls = 'fx'     THEN 'CME'
        ELSE (ARRAY['NYSE','NASDAQ','NYSE','NASDAQ','LSE','TSE','HKEX','NYSE'])[1 + (s % 8)]
    END AS exchange,
    -- Sector: only for stocks, 11 GICS sectors
    CASE
        WHEN asset_cls = 'stock' THEN
            (ARRAY[
                'Technology', 'Healthcare', 'Financials', 'Consumer Discretionary',
                'Communication Services', 'Industrials', 'Consumer Staples',
                'Energy', 'Utilities', 'Real Estate', 'Materials'
            ])[1 + (s % 11)]
        ELSE NULL
    END AS sector,
    -- Market cap: log-normal-ish distribution from 1M to 3T
    CASE
        WHEN asset_cls IN ('stock', 'etf', 'bond') THEN
            ROUND(
                POWER(10, 6 + (hashint4(s)::NUMERIC / 2147483647.0 + 1) / 2.0 * 6.5)::NUMERIC,
                2
            )
        ELSE NULL
    END AS market_cap_usd,
    -- Currency: weighted toward USD
    CASE
        WHEN asset_cls = 'fx' THEN (ARRAY['USD','EUR','GBP','JPY','CHF','AUD'])[1 + (s % 6)]
        ELSE (ARRAY['USD','USD','USD','USD','EUR','GBP','JPY','USD'])[1 + (s % 8)]
    END AS currency,
    -- is_active: 95% active
    (s % 20 != 0) AS is_active,
    -- listed_date: spread across 1990-2025
    ('1990-01-01'::DATE + (hashint4(s + 1000) % 12775)::INT) AS listed_date
FROM generate_series(101, 50000) AS s
CROSS JOIN LATERAL (
    SELECT CASE
        WHEN s <= 34900  THEN 'stock'
        WHEN s <= 39900  THEN 'etf'
        WHEN s <= 43900  THEN 'future'
        WHEN s <= 46400  THEN 'option'
        WHEN s <= 48400  THEN 'bond'
        ELSE                  'fx'
    END AS asset_cls
) ac;

-- --------------------------------------------------------------------------
-- 7b. quant.models (~500 rows)
-- --------------------------------------------------------------------------
-- Realistic model names combining strategy type, method, and version.
-- --------------------------------------------------------------------------

INSERT INTO quant.models (model_name, version, framework, model_type, training_dataset,
                          training_start_date, training_end_date, feature_count,
                          status, sharpe_ratio, max_drawdown, created_by, created_at, updated_at)
SELECT
    -- Model name: strategy_method combination
    (ARRAY[
        'alpha_momentum', 'alpha_mean_revert', 'alpha_quality', 'alpha_value',
        'alpha_growth', 'alpha_sentiment', 'alpha_volatility', 'alpha_earnings',
        'risk_parity_ml', 'risk_factor_model', 'risk_var_estimator', 'risk_tail_model',
        'stat_arb_pairs', 'stat_arb_basket', 'stat_arb_cointegration',
        'exec_optimal_slice', 'exec_twap_adaptive', 'exec_vwap_ml',
        'port_opt_mvo', 'port_opt_black_litterman', 'port_opt_risk_budget',
        'feat_eng_technical', 'feat_eng_fundamental', 'feat_eng_alternative',
        'feat_eng_nlp_news'
    ])[1 + (s % 25)]
    || '_v' || (1 + (s / 25)) AS model_name,
    'v' || (1 + (s / 25)) || '.' || (s % 10) AS version,
    -- Framework
    (ARRAY['pytorch', 'tensorflow', 'xgboost', 'lightgbm', 'sklearn', 'custom'])[1 + (s % 6)] AS framework,
    -- Model type
    (ARRAY['alpha_signal', 'risk_model', 'execution', 'portfolio_opt', 'feature_eng'])[1 + (s % 5)] AS model_type,
    -- Training dataset
    (ARRAY[
        'us_equity_daily_2015_2025', 'global_equity_daily_2018_2025',
        'us_equity_tick_2020_2025', 'alternative_data_2019_2025',
        'options_chain_2020_2025', 'macro_indicators_2010_2025',
        'news_sentiment_2020_2025', 'earnings_transcripts_2018_2025'
    ])[1 + (s % 8)] AS training_dataset,
    -- Training dates
    ('2020-01-01'::DATE + (s % 730)) AS training_start_date,
    ('2024-06-01'::DATE + (s % 365)) AS training_end_date,
    -- Feature count: 10-2000
    10 + (hashint4(s + 5000) % 1990)::INT AS feature_count,
    -- Status: weighted distribution
    (ARRAY[
        'development', 'development', 'backtesting', 'backtesting', 'backtesting',
        'staging', 'staging', 'production', 'production', 'production',
        'production', 'production', 'retired', 'retired', 'retired'
    ])[1 + (s % 15)] AS status,
    -- Sharpe ratio: 0.2 to 3.5
    ROUND((0.2 + (hashint4(s + 7000)::NUMERIC / 2147483647.0 + 1.0) / 2.0 * 3.3)::NUMERIC, 3) AS sharpe_ratio,
    -- Max drawdown: 0.01 to 0.35
    ROUND((0.01 + (hashint4(s + 9000)::NUMERIC / 2147483647.0 + 1.0) / 2.0 * 0.34)::NUMERIC, 4) AS max_drawdown,
    -- Created by
    (ARRAY[
        'jchen', 'asingh', 'mwilliams', 'kpatel', 'lzhang',
        'rjohnson', 'skim', 'tgarcia', 'nbrown', 'dwilson'
    ])[1 + (s % 10)] AS created_by,
    -- Created at: spread over 2 years
    '2024-06-01'::TIMESTAMPTZ + (s * INTERVAL '1 day' * 1.5) AS created_at,
    '2024-06-01'::TIMESTAMPTZ + (s * INTERVAL '1 day' * 1.5) + INTERVAL '2 hours' AS updated_at
FROM generate_series(0, 499) AS s;

-- --------------------------------------------------------------------------
-- 7c. quant.market_data (~10,000,000 rows)
-- --------------------------------------------------------------------------
-- Daily OHLCV for ~3,800 instruments over ~260 trading days (12 months).
-- Uses generate_series for dates and cross joins with a subset of instruments.
-- Prices are generated with hash-based pseudo-random distributions.
-- --------------------------------------------------------------------------

INSERT INTO quant.market_data (instrument_id, trade_date, open_price, high_price, low_price, close_price, volume, vwap, source_feed)
SELECT
    i.instrument_id,
    d.trade_date,
    -- Open price: base price derived from instrument_id, with daily variation
    ROUND(
        GREATEST(0.50,
            (10.0 + (hashint4(i.instrument_id)::NUMERIC % 4990))
            * (1.0 + (hashint4(i.instrument_id * 1000 + d.day_offset)::NUMERIC / 2147483647.0) * 0.03)
        )::NUMERIC, 4
    ) AS open_price,
    -- High: open + 0-5% upside
    ROUND(
        GREATEST(0.50,
            (10.0 + (hashint4(i.instrument_id)::NUMERIC % 4990))
            * (1.0 + (hashint4(i.instrument_id * 1000 + d.day_offset)::NUMERIC / 2147483647.0) * 0.03)
            * (1.0 + ABS(hashint4(i.instrument_id * 2000 + d.day_offset)::NUMERIC / 2147483647.0) * 0.05)
        )::NUMERIC, 4
    ) AS high_price,
    -- Low: open - 0-5% downside
    ROUND(
        GREATEST(0.50,
            (10.0 + (hashint4(i.instrument_id)::NUMERIC % 4990))
            * (1.0 + (hashint4(i.instrument_id * 1000 + d.day_offset)::NUMERIC / 2147483647.0) * 0.03)
            * (1.0 - ABS(hashint4(i.instrument_id * 3000 + d.day_offset)::NUMERIC / 2147483647.0) * 0.05)
        )::NUMERIC, 4
    ) AS low_price,
    -- Close: between low and high
    ROUND(
        GREATEST(0.50,
            (10.0 + (hashint4(i.instrument_id)::NUMERIC % 4990))
            * (1.0 + (hashint4(i.instrument_id * 4000 + d.day_offset)::NUMERIC / 2147483647.0) * 0.04)
        )::NUMERIC, 4
    ) AS close_price,
    -- Volume: 100K to 500M, skewed toward lower values
    GREATEST(100000,
        ABS(hashint4(i.instrument_id * 5000 + d.day_offset)::BIGINT % 500000000)
    ) AS volume,
    -- VWAP: close +/- small delta
    ROUND(
        GREATEST(0.50,
            (10.0 + (hashint4(i.instrument_id)::NUMERIC % 4990))
            * (1.0 + (hashint4(i.instrument_id * 6000 + d.day_offset)::NUMERIC / 2147483647.0) * 0.035)
        )::NUMERIC, 4
    ) AS vwap,
    -- Source feed: weighted distribution
    (ARRAY['bloomberg', 'bloomberg', 'refinitiv', 'polygon', 'internal'])[
        1 + (ABS(hashint4(i.instrument_id + d.day_offset)) % 5)
    ] AS source_feed
FROM (
    -- Select ~3,850 instruments to get ~10M rows over 260 trading days
    SELECT instrument_id
    FROM quant.instruments
    WHERE instrument_id <= 3850
) i
CROSS JOIN (
    -- ~260 trading days: weekdays only between 2025-07-01 and 2026-06-30
    SELECT
        trade_date,
        ROW_NUMBER() OVER (ORDER BY trade_date) AS day_offset
    FROM generate_series('2025-07-01'::DATE, '2026-06-30'::DATE, '1 day'::INTERVAL) AS trade_date
    WHERE EXTRACT(DOW FROM trade_date) NOT IN (0, 6)  -- Exclude weekends
) d;

-- --------------------------------------------------------------------------
-- 7d. quant.signals (~5,000,000 rows)
-- --------------------------------------------------------------------------
-- Trading signals from models, spread across 12 months.
-- Score distribution centered around 0 with fat tails.
-- --------------------------------------------------------------------------

INSERT INTO quant.signals (model_id, instrument_id, signal_date, score, confidence, decay_hours, signal_type, generated_at)
SELECT
    -- Model ID: cycle through all 500 models
    1 + (s % 500) AS model_id,
    -- Instrument ID: cycle through first 2000 instruments
    1 + (s % 2000) AS instrument_id,
    -- Signal date: spread across 12 months (~417K per month)
    '2025-07-01'::DATE + ((s / 16667) % 365) AS signal_date,
    -- Score: centered around 0 with tails toward -1/+1
    ROUND(
        GREATEST(-1.0, LEAST(1.0,
            (hashint4(s)::NUMERIC / 2147483647.0) *
            (1.0 + ABS(hashint4(s + 100000)::NUMERIC / 2147483647.0))
        ))::NUMERIC, 5
    ) AS score,
    -- Confidence: 0.3 to 0.99
    ROUND((0.3 + ABS(hashint4(s + 200000)::NUMERIC / 2147483647.0) * 0.69)::NUMERIC, 4) AS confidence,
    -- Decay hours: 4, 8, 12, 24, 48, 72
    (ARRAY[4, 8, 12, 24, 24, 24, 48, 72])[1 + (s % 8)] AS decay_hours,
    -- Signal type: derived from score
    CASE
        WHEN (hashint4(s)::NUMERIC / 2147483647.0) > 0.3  THEN 'long'
        WHEN (hashint4(s)::NUMERIC / 2147483647.0) < -0.3 THEN 'short'
        WHEN ABS(hashint4(s)::NUMERIC / 2147483647.0) < 0.05 THEN 'neutral'
        ELSE 'hold'
    END AS signal_type,
    -- Generated at: signal_date + random hour offset
    ('2025-07-01'::TIMESTAMPTZ + ((s / 16667) % 365) * INTERVAL '1 day'
        + (ABS(hashint4(s + 300000)) % 14 + 6) * INTERVAL '1 hour') AS generated_at
FROM generate_series(1, 5000000) AS s;

-- --------------------------------------------------------------------------
-- 7e. quant.positions (~200,000 rows)
-- --------------------------------------------------------------------------
-- Mix of 30% open and 70% closed positions across 7 portfolios.
-- --------------------------------------------------------------------------

INSERT INTO quant.positions (instrument_id, model_id, side, quantity, entry_price, current_price,
                             entry_date, exit_date, realized_pnl, unrealized_pnl,
                             portfolio, status, created_at, updated_at)
SELECT
    -- Instrument: spread across universe
    1 + (s % 10000) AS instrument_id,
    -- Model: cycle through models, with some NULLs for manual trades
    CASE WHEN s % 20 = 0 THEN NULL ELSE 1 + (s % 500) END AS model_id,
    -- Side: 60% long, 40% short
    CASE WHEN s % 5 < 3 THEN 'long' ELSE 'short' END AS side,
    -- Quantity: 1 to 100,000 shares
    ROUND((1 + ABS(hashint4(s + 10000)::NUMERIC % 99999))::NUMERIC, 4) AS quantity,
    -- Entry price: $1 to $5000
    ROUND(GREATEST(1.0, (1.0 + ABS(hashint4(s + 20000)::NUMERIC % 4999)))::NUMERIC, 4) AS entry_price,
    -- Current price: entry +/- up to 20%
    CASE
        WHEN s % 10 < 3 THEN  -- open positions get current price
            ROUND(GREATEST(0.50,
                (1.0 + ABS(hashint4(s + 20000)::NUMERIC % 4999))
                * (1.0 + hashint4(s + 30000)::NUMERIC / 2147483647.0 * 0.20)
            )::NUMERIC, 4)
        ELSE NULL  -- closed positions
    END AS current_price,
    -- Entry date: spread over 12 months
    '2025-07-01'::DATE + (ABS(hashint4(s + 40000)) % 365) AS entry_date,
    -- Exit date: only for closed positions (70%)
    CASE
        WHEN s % 10 >= 3 THEN
            '2025-07-01'::DATE + (ABS(hashint4(s + 40000)) % 365)
            + (1 + ABS(hashint4(s + 50000)) % 60)  -- hold 1-60 days
        ELSE NULL
    END AS exit_date,
    -- Realized PnL: closed positions get PnL between -50K and +100K
    CASE
        WHEN s % 10 >= 3 THEN
            ROUND((hashint4(s + 60000)::NUMERIC / 2147483647.0 * 75000.0)::NUMERIC, 2)
        ELSE NULL
    END AS realized_pnl,
    -- Unrealized PnL: open positions get PnL between -30K and +50K
    CASE
        WHEN s % 10 < 3 THEN
            ROUND((hashint4(s + 70000)::NUMERIC / 2147483647.0 * 40000.0)::NUMERIC, 2)
        ELSE NULL
    END AS unrealized_pnl,
    -- Portfolio: 7 strategies
    (ARRAY['alpha_1', 'alpha_2', 'alpha_3', 'risk_parity', 'momentum', 'stat_arb', 'market_neutral'])[
        1 + (s % 7)
    ] AS portfolio,
    -- Status: 30% open, 65% closed, 5% partial
    CASE
        WHEN s % 10 < 3 THEN 'open'
        WHEN s % 20 = 19 THEN 'partial'
        ELSE 'closed'
    END AS status,
    -- Timestamps
    '2025-07-01'::TIMESTAMPTZ + (ABS(hashint4(s + 40000)) % 365) * INTERVAL '1 day' AS created_at,
    '2025-07-01'::TIMESTAMPTZ + (ABS(hashint4(s + 40000)) % 365) * INTERVAL '1 day'
        + (ABS(hashint4(s + 80000)) % 720) * INTERVAL '1 hour' AS updated_at
FROM generate_series(1, 200000) AS s;

-- --------------------------------------------------------------------------
-- 7f. quant.backtests (~10,000 rows)
-- --------------------------------------------------------------------------

INSERT INTO quant.backtests (model_id, backtest_name, start_date, end_date, universe_size,
                             sharpe_ratio, annual_return, max_drawdown, turnover_annual,
                             total_trades, win_rate, status, compute_hours, created_at)
SELECT
    1 + (s % 500) AS model_id,
    -- Backtest name
    'bt_' || (ARRAY[
        'full_universe', 'sp500_only', 'large_cap', 'mid_cap', 'small_cap',
        'tech_sector', 'value_screen', 'momentum_screen', 'quality_screen',
        'intl_developed', 'emerging_mkts', 'multi_asset', 'fx_majors',
        'crypto_universe', 'options_strats', 'bond_universe'
    ])[1 + (s % 16)]
    || '_' || TO_CHAR('2025-01-01'::DATE + (s % 365), 'YYYYMMDD') AS backtest_name,
    -- Start/end dates: 1-5 year lookbacks
    '2020-01-01'::DATE + (s % 1460) AS start_date,
    '2025-07-01'::DATE + (s % 365) AS end_date,
    -- Universe size: 50 to 5000
    50 + ABS(hashint4(s + 1000) % 4950) AS universe_size,
    -- Sharpe: 0.5 to 3.0, centered around 1.2
    ROUND(GREATEST(0.5, LEAST(3.0,
        1.2 + (hashint4(s + 2000)::NUMERIC / 2147483647.0) * 1.0
    ))::NUMERIC, 3) AS sharpe_ratio,
    -- Annual return: -0.10 to 0.50
    ROUND(GREATEST(-0.10, LEAST(0.50,
        0.12 + (hashint4(s + 3000)::NUMERIC / 2147483647.0) * 0.25
    ))::NUMERIC, 4) AS annual_return,
    -- Max drawdown: 0.01 to 0.30
    ROUND(GREATEST(0.01, LEAST(0.30,
        0.08 + ABS(hashint4(s + 4000)::NUMERIC / 2147483647.0) * 0.22
    ))::NUMERIC, 4) AS max_drawdown,
    -- Turnover: 0.5 to 20.0
    ROUND(GREATEST(0.5, LEAST(20.0,
        5.0 + (hashint4(s + 5000)::NUMERIC / 2147483647.0) * 10.0
    ))::NUMERIC, 4) AS turnover_annual,
    -- Total trades: 100 to 500,000
    100 + ABS(hashint4(s + 6000) % 499900) AS total_trades,
    -- Win rate: 0.35 to 0.65
    ROUND(GREATEST(0.35, LEAST(0.65,
        0.50 + (hashint4(s + 7000)::NUMERIC / 2147483647.0) * 0.15
    ))::NUMERIC, 4) AS win_rate,
    -- Status: 80% completed, 10% running, 10% failed
    (ARRAY[
        'completed', 'completed', 'completed', 'completed',
        'completed', 'completed', 'completed', 'completed',
        'running', 'failed'
    ])[1 + (s % 10)] AS status,
    -- Compute hours: 0.1 to 500
    ROUND(GREATEST(0.1, LEAST(500.0,
        POWER(10, 0 + ABS(hashint4(s + 8000)::NUMERIC / 2147483647.0) * 2.7)
    ))::NUMERIC, 2) AS compute_hours,
    -- Created at: spread over 12 months
    '2025-07-01'::TIMESTAMPTZ + (s % 365) * INTERVAL '1 day'
        + (ABS(hashint4(s + 9000)) % 86400) * INTERVAL '1 second' AS created_at
FROM generate_series(1, 10000) AS s;

-- --------------------------------------------------------------------------
-- 7g. quant.model_features (~2,000,000 rows)
-- --------------------------------------------------------------------------

INSERT INTO quant.model_features (model_id, feature_name, feature_value, instrument_id,
                                  computed_at, valid_from, valid_to)
SELECT
    1 + (s % 500) AS model_id,
    -- Feature names: realistic quantitative features
    (ARRAY[
        'momentum_5d', 'momentum_10d', 'momentum_20d', 'momentum_60d', 'momentum_120d',
        'volatility_10d', 'volatility_20d', 'volatility_60d', 'volatility_120d',
        'volume_zscore_5d', 'volume_zscore_20d',
        'rsi_14d', 'rsi_28d',
        'macd_signal', 'macd_histogram',
        'bb_upper_dist', 'bb_lower_dist',
        'value_score', 'pe_ratio_zscore', 'pb_ratio_zscore',
        'earnings_surprise', 'earnings_revision', 'earnings_momentum',
        'sentiment_score', 'news_volume_zscore',
        'short_interest_ratio', 'institutional_ownership_chg',
        'beta_sp500', 'idiosyncratic_vol', 'factor_momentum',
        'sector_relative_strength', 'cross_sectional_rank',
        'mean_reversion_5d', 'mean_reversion_20d',
        'order_flow_imbalance', 'bid_ask_spread_avg',
        'correlation_spy', 'correlation_sector',
        'skewness_20d', 'kurtosis_20d'
    ])[1 + (s % 40)] AS feature_name,
    -- Feature value: different ranges by feature type
    ROUND((hashint4(s + 500000)::NUMERIC / 2147483647.0 * 10.0)::NUMERIC, 6) AS feature_value,
    -- Instrument: cycle through first 5000
    CASE WHEN s % 10 = 0 THEN NULL ELSE 1 + (s % 5000) END AS instrument_id,
    -- Timestamps
    '2025-07-01'::TIMESTAMPTZ + ((s / 5500) % 365) * INTERVAL '1 day'
        + INTERVAL '6 hours' AS computed_at,
    '2025-07-01'::TIMESTAMPTZ + ((s / 5500) % 365) * INTERVAL '1 day'
        + INTERVAL '6 hours 30 minutes' AS valid_from,
    -- valid_to: 90% have an expiry, 10% are still current (NULL)
    CASE
        WHEN s % 10 = 0 THEN NULL
        ELSE '2025-07-01'::TIMESTAMPTZ + ((s / 5500) % 365) * INTERVAL '1 day'
            + INTERVAL '30 hours 30 minutes'
    END AS valid_to
FROM generate_series(1, 2000000) AS s;

-- --------------------------------------------------------------------------
-- 7h. ops.deployments (~2,000 rows)
-- --------------------------------------------------------------------------

INSERT INTO ops.deployments (model_id, model_version, environment, action, promoted_by,
                             approved_by, status, deployed_at, notes)
SELECT
    1 + (s % 500) AS model_id,
    'v' || (1 + (s / 100)) || '.' || (s % 10) AS model_version,
    -- Environment: weighted toward production
    (ARRAY['development', 'development', 'staging', 'staging', 'staging',
           'production', 'production', 'production', 'production', 'production'])[1 + (s % 10)] AS environment,
    -- Action
    (ARRAY['deploy', 'deploy', 'deploy', 'deploy', 'deploy',
           'rollback', 'scale', 'config_change'])[1 + (s % 8)] AS action,
    -- Promoted by
    (ARRAY['jchen', 'asingh', 'mwilliams', 'kpatel', 'lzhang',
           'rjohnson', 'skim', 'tgarcia'])[1 + (s % 8)] AS promoted_by,
    -- Approved by (different from promoter)
    (ARRAY['director_quant', 'head_risk', 'cto', 'vp_engineering',
           'head_trading', 'lead_researcher'])[1 + (s % 6)] AS approved_by,
    -- Status: 60% completed, 20% in_progress, 10% failed, 10% rolled_back
    (ARRAY[
        'completed', 'completed', 'completed', 'completed', 'completed', 'completed',
        'in_progress', 'in_progress',
        'failed',
        'rolled_back'
    ])[1 + (s % 10)] AS status,
    -- Deployed at: spread over 12 months
    '2025-07-01'::TIMESTAMPTZ + (s % 365) * INTERVAL '1 day'
        + (ABS(hashint4(s + 90000)) % 43200) * INTERVAL '1 second' AS deployed_at,
    -- Notes
    CASE
        WHEN s % 10 = 8 THEN 'FAILED: ' || (ARRAY[
            'OOM error during model loading',
            'GPU memory exhausted',
            'Dependency version mismatch',
            'Health check timeout after 300s',
            'Data pipeline not ready'
        ])[1 + (s % 5)]
        WHEN s % 10 = 9 THEN 'ROLLED BACK: ' || (ARRAY[
            'Increased latency detected in production',
            'PnL degradation observed',
            'Risk limits breached',
            'Signal quality below threshold'
        ])[1 + (s % 4)]
        WHEN s % 5 = 0 THEN (ARRAY[
            'Scheduled weekly model refresh',
            'Hotfix for feature drift detected',
            'New training data incorporated',
            'Hyperparameter tuning update',
            'Feature store version bump'
        ])[1 + (s % 5)]
        ELSE NULL
    END AS notes
FROM generate_series(1, 2000) AS s;

-- --------------------------------------------------------------------------
-- 7i. ops.pipeline_runs (~5,000 rows)
-- --------------------------------------------------------------------------

INSERT INTO ops.pipeline_runs (pipeline_name, source, start_time, end_time, rows_processed,
                               rows_failed, status, error_message, triggered_by)
SELECT
    -- Pipeline name
    (ARRAY[
        'bloomberg_eod_ingest', 'refinitiv_eod_ingest', 'polygon_tick_ingest',
        'feature_computation_daily', 'feature_computation_intraday',
        'signal_generation_alpha', 'signal_generation_risk',
        'position_reconciliation', 'pnl_calculation',
        'risk_report_generation', 'compliance_check',
        'model_retraining_pipeline', 'data_quality_validation',
        'universe_refresh', 'corporate_actions_ingest',
        'alternative_data_ingest', 'news_sentiment_pipeline',
        'market_microstructure_calc', 'factor_return_computation',
        'portfolio_rebalance_calc'
    ])[1 + (s % 20)] AS pipeline_name,
    -- Source
    (ARRAY['bloomberg', 'refinitiv', 'polygon', 'internal_research', 'feature_store'])[1 + (s % 5)] AS source,
    -- Start time: spread over 12 months
    '2025-07-01'::TIMESTAMPTZ + (s % 365) * INTERVAL '1 day'
        + (ABS(hashint4(s + 100000)) % 86400) * INTERVAL '1 second' AS start_time,
    -- End time: start + 1 minute to 4 hours
    CASE
        WHEN s % 20 = 17 THEN NULL  -- running pipelines have no end time
        ELSE '2025-07-01'::TIMESTAMPTZ + (s % 365) * INTERVAL '1 day'
            + (ABS(hashint4(s + 100000)) % 86400) * INTERVAL '1 second'
            + (1 + ABS(hashint4(s + 110000)) % 240) * INTERVAL '1 minute'
    END AS end_time,
    -- Rows processed: 0 to 50M
    CASE
        WHEN s % 20 = 17 THEN NULL
        ELSE ABS(hashint4(s + 120000)::BIGINT % 50000000)
    END AS rows_processed,
    -- Rows failed: 0-1% of processed
    CASE
        WHEN s % 20 = 17 THEN 0
        WHEN s % 7 = 0 THEN ABS(hashint4(s + 130000)::BIGINT % 5000)
        ELSE 0
    END AS rows_failed,
    -- Status: 75% completed, 10% running, 10% failed, 5% timeout
    (ARRAY[
        'completed', 'completed', 'completed', 'completed', 'completed',
        'completed', 'completed', 'completed', 'completed', 'completed',
        'completed', 'completed', 'completed', 'completed', 'completed',
        'running', 'running',
        'failed', 'failed',
        'timeout'
    ])[1 + (s % 20)] AS status,
    -- Error message: only for failed/timeout
    CASE
        WHEN s % 20 IN (17, 18) THEN (ARRAY[
            'Connection timeout to Bloomberg B-PIPE',
            'Refinitiv API rate limit exceeded',
            'Polygon websocket disconnected',
            'Feature store read timeout',
            'Out of memory during feature computation',
            'Schema validation failed - unexpected column types',
            'Duplicate key violation on market_data partition',
            'Network partition detected - retrying',
            'GPU cluster unavailable for model inference',
            'Upstream dependency pipeline_id=42 not completed'
        ])[1 + (s % 10)]
        WHEN s % 20 = 19 THEN 'Pipeline exceeded 4-hour timeout threshold'
        ELSE NULL
    END AS error_message,
    -- Triggered by
    (ARRAY[
        'schedule', 'schedule', 'schedule', 'schedule', 'schedule',
        'schedule', 'schedule',
        'dependency', 'dependency',
        'manual', 'retry'
    ])[1 + (s % 11)] AS triggered_by
FROM generate_series(1, 5000) AS s;

-- ============================================================================
-- 8. RE-ENABLE TRIGGERS
-- ============================================================================

ALTER TABLE quant.models    ENABLE TRIGGER trg_models_audit;
ALTER TABLE ops.deployments ENABLE TRIGGER trg_deployments_audit;

-- ============================================================================
-- 9. INDEXES
-- ============================================================================
-- Comprehensive indexes for common query patterns in a quant trading platform.
-- Created after bulk load to avoid index maintenance overhead during INSERT.
-- ============================================================================

-- quant.instruments
CREATE INDEX idx_instruments_asset_class     ON quant.instruments (asset_class);
CREATE INDEX idx_instruments_exchange        ON quant.instruments (exchange);
CREATE INDEX idx_instruments_sector          ON quant.instruments (sector) WHERE sector IS NOT NULL;
CREATE INDEX idx_instruments_currency        ON quant.instruments (currency);
CREATE INDEX idx_instruments_active          ON quant.instruments (is_active) WHERE is_active = true;
CREATE INDEX idx_instruments_listed_date     ON quant.instruments (listed_date);
CREATE INDEX idx_instruments_market_cap      ON quant.instruments (market_cap_usd DESC NULLS LAST)
    WHERE market_cap_usd IS NOT NULL;
CREATE INDEX idx_instruments_asset_exchange  ON quant.instruments (asset_class, exchange);
CREATE INDEX idx_instruments_sector_active   ON quant.instruments (sector, is_active)
    WHERE sector IS NOT NULL AND is_active = true;

-- quant.market_data (indexes on partitioned table propagate to partitions)
CREATE INDEX idx_market_data_instrument_date ON quant.market_data (instrument_id, trade_date);
CREATE INDEX idx_market_data_trade_date      ON quant.market_data (trade_date);
CREATE INDEX idx_market_data_source_feed     ON quant.market_data (source_feed);
CREATE INDEX idx_market_data_instrument_src  ON quant.market_data (instrument_id, source_feed, trade_date);
CREATE INDEX idx_market_data_volume          ON quant.market_data (volume DESC);

-- quant.models
CREATE INDEX idx_models_framework            ON quant.models (framework);
CREATE INDEX idx_models_model_type           ON quant.models (model_type);
CREATE INDEX idx_models_status               ON quant.models (status);
CREATE INDEX idx_models_created_by           ON quant.models (created_by);
CREATE INDEX idx_models_production           ON quant.models (model_name, version)
    WHERE status = 'production';
CREATE INDEX idx_models_sharpe_ratio         ON quant.models (sharpe_ratio DESC NULLS LAST)
    WHERE status IN ('production', 'staging');
CREATE INDEX idx_models_type_status          ON quant.models (model_type, status);

-- quant.signals (indexes on partitioned table)
CREATE INDEX idx_signals_model_date          ON quant.signals (model_id, signal_date);
CREATE INDEX idx_signals_instrument_date     ON quant.signals (instrument_id, signal_date);
CREATE INDEX idx_signals_signal_date         ON quant.signals (signal_date);
CREATE INDEX idx_signals_signal_type         ON quant.signals (signal_type);
CREATE INDEX idx_signals_score               ON quant.signals (score);
CREATE INDEX idx_signals_strong_long         ON quant.signals (instrument_id, signal_date, score)
    WHERE signal_type = 'long' AND score > 0.5;
CREATE INDEX idx_signals_strong_short        ON quant.signals (instrument_id, signal_date, score)
    WHERE signal_type = 'short' AND score < -0.5;
CREATE INDEX idx_signals_model_inst_date     ON quant.signals (model_id, instrument_id, signal_date);

-- quant.positions
CREATE INDEX idx_positions_instrument        ON quant.positions (instrument_id);
CREATE INDEX idx_positions_model             ON quant.positions (model_id) WHERE model_id IS NOT NULL;
CREATE INDEX idx_positions_portfolio         ON quant.positions (portfolio);
CREATE INDEX idx_positions_status            ON quant.positions (status);
CREATE INDEX idx_positions_entry_date        ON quant.positions (entry_date);
CREATE INDEX idx_positions_exit_date         ON quant.positions (exit_date) WHERE exit_date IS NOT NULL;
CREATE INDEX idx_positions_open              ON quant.positions (instrument_id, portfolio)
    WHERE status = 'open';
CREATE INDEX idx_positions_closed_pnl        ON quant.positions (realized_pnl DESC NULLS LAST)
    WHERE status = 'closed';
CREATE INDEX idx_positions_portfolio_status  ON quant.positions (portfolio, status);
CREATE INDEX idx_positions_model_portfolio   ON quant.positions (model_id, portfolio)
    WHERE model_id IS NOT NULL;

-- quant.backtests
CREATE INDEX idx_backtests_model             ON quant.backtests (model_id);
CREATE INDEX idx_backtests_status            ON quant.backtests (status);
CREATE INDEX idx_backtests_sharpe            ON quant.backtests (sharpe_ratio DESC NULLS LAST)
    WHERE status = 'completed';
CREATE INDEX idx_backtests_model_status      ON quant.backtests (model_id, status);
CREATE INDEX idx_backtests_dates             ON quant.backtests (start_date, end_date);
CREATE INDEX idx_backtests_completed_return  ON quant.backtests (annual_return DESC)
    WHERE status = 'completed';

-- quant.model_features
CREATE INDEX idx_model_features_model        ON quant.model_features (model_id);
CREATE INDEX idx_model_features_instrument   ON quant.model_features (instrument_id)
    WHERE instrument_id IS NOT NULL;
CREATE INDEX idx_model_features_name         ON quant.model_features (feature_name);
CREATE INDEX idx_model_features_model_name   ON quant.model_features (model_id, feature_name);
CREATE INDEX idx_model_features_valid        ON quant.model_features (valid_from, valid_to)
    WHERE valid_to IS NULL;
CREATE INDEX idx_model_features_computed     ON quant.model_features (computed_at);
CREATE INDEX idx_model_features_model_inst   ON quant.model_features (model_id, instrument_id, feature_name)
    WHERE instrument_id IS NOT NULL;

-- ops.deployments
CREATE INDEX idx_deployments_model           ON ops.deployments (model_id);
CREATE INDEX idx_deployments_status          ON ops.deployments (status);
CREATE INDEX idx_deployments_environment     ON ops.deployments (environment);
CREATE INDEX idx_deployments_deployed_at     ON ops.deployments (deployed_at);
CREATE INDEX idx_deployments_prod_active     ON ops.deployments (model_id, deployed_at)
    WHERE environment = 'production' AND status = 'completed';
CREATE INDEX idx_deployments_failed          ON ops.deployments (model_id, deployed_at)
    WHERE status = 'failed';
CREATE INDEX idx_deployments_env_status      ON ops.deployments (environment, status);

-- ops.pipeline_runs
CREATE INDEX idx_pipeline_runs_name          ON ops.pipeline_runs (pipeline_name);
CREATE INDEX idx_pipeline_runs_status        ON ops.pipeline_runs (status);
CREATE INDEX idx_pipeline_runs_source        ON ops.pipeline_runs (source);
CREATE INDEX idx_pipeline_runs_start_time    ON ops.pipeline_runs (start_time);
CREATE INDEX idx_pipeline_runs_name_status   ON ops.pipeline_runs (pipeline_name, status);
CREATE INDEX idx_pipeline_runs_failed        ON ops.pipeline_runs (pipeline_name, start_time)
    WHERE status IN ('failed', 'timeout');
CREATE INDEX idx_pipeline_runs_running       ON ops.pipeline_runs (pipeline_name, start_time)
    WHERE status = 'running';

-- ops.alerts
CREATE INDEX idx_alerts_source_table         ON ops.alerts (source_table);
CREATE INDEX idx_alerts_alert_type           ON ops.alerts (alert_type);
CREATE INDEX idx_alerts_triggered_at         ON ops.alerts (triggered_at);
CREATE INDEX idx_alerts_source_record        ON ops.alerts (source_table, record_id);
CREATE INDEX idx_alerts_triggered_by         ON ops.alerts (triggered_by);

-- ============================================================================
-- 10. ROLES AND GRANTS
-- ============================================================================

-- Create roles with IF NOT EXISTS guards
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'quant_app') THEN
        CREATE ROLE quant_app NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'quant_research') THEN
        CREATE ROLE quant_research NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'quant_pipeline') THEN
        CREATE ROLE quant_pipeline NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'quant_readonly') THEN
        CREATE ROLE quant_readonly NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator NOLOGIN REPLICATION;
    END IF;
END
$$;

-- --------------------------------------------------------------------------
-- quant_app: Application role for the trading platform
-- SELECT, INSERT, UPDATE on quant schema (no DELETE on market_data)
-- --------------------------------------------------------------------------
GRANT USAGE ON SCHEMA quant TO quant_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA quant TO quant_app;
-- Revoke DELETE on market_data specifically (immutable time-series data)
REVOKE DELETE ON quant.market_data FROM quant_app;
-- Revoke DELETE on all market_data partitions
REVOKE DELETE ON quant.market_data_2025_07 FROM quant_app;
REVOKE DELETE ON quant.market_data_2025_08 FROM quant_app;
REVOKE DELETE ON quant.market_data_2025_09 FROM quant_app;
REVOKE DELETE ON quant.market_data_2025_10 FROM quant_app;
REVOKE DELETE ON quant.market_data_2025_11 FROM quant_app;
REVOKE DELETE ON quant.market_data_2025_12 FROM quant_app;
REVOKE DELETE ON quant.market_data_2026_01 FROM quant_app;
REVOKE DELETE ON quant.market_data_2026_02 FROM quant_app;
REVOKE DELETE ON quant.market_data_2026_03 FROM quant_app;
REVOKE DELETE ON quant.market_data_2026_04 FROM quant_app;
REVOKE DELETE ON quant.market_data_2026_05 FROM quant_app;
REVOKE DELETE ON quant.market_data_2026_06 FROM quant_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA quant TO quant_app;

-- --------------------------------------------------------------------------
-- quant_research: Read-only access to quant schema for researchers
-- --------------------------------------------------------------------------
GRANT USAGE ON SCHEMA quant TO quant_research;
GRANT SELECT ON ALL TABLES IN SCHEMA quant TO quant_research;

-- --------------------------------------------------------------------------
-- quant_pipeline: Data pipeline role
-- ALL on ops schema, INSERT on quant.market_data and quant.signals
-- --------------------------------------------------------------------------
GRANT USAGE ON SCHEMA ops TO quant_pipeline;
GRANT ALL ON ALL TABLES IN SCHEMA ops TO quant_pipeline;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA ops TO quant_pipeline;
GRANT USAGE ON SCHEMA quant TO quant_pipeline;
GRANT INSERT ON quant.market_data TO quant_pipeline;
GRANT INSERT ON quant.signals TO quant_pipeline;
-- Grant INSERT on all partitions
GRANT INSERT ON quant.market_data_2025_07, quant.market_data_2025_08,
    quant.market_data_2025_09, quant.market_data_2025_10,
    quant.market_data_2025_11, quant.market_data_2025_12,
    quant.market_data_2026_01, quant.market_data_2026_02,
    quant.market_data_2026_03, quant.market_data_2026_04,
    quant.market_data_2026_05, quant.market_data_2026_06
    TO quant_pipeline;
GRANT INSERT ON quant.signals_2025_07, quant.signals_2025_08,
    quant.signals_2025_09, quant.signals_2025_10,
    quant.signals_2025_11, quant.signals_2025_12,
    quant.signals_2026_01, quant.signals_2026_02,
    quant.signals_2026_03, quant.signals_2026_04,
    quant.signals_2026_05, quant.signals_2026_06
    TO quant_pipeline;
GRANT USAGE ON SEQUENCE quant.market_data_data_id_seq TO quant_pipeline;
GRANT USAGE ON SEQUENCE quant.signals_signal_id_seq TO quant_pipeline;

-- --------------------------------------------------------------------------
-- quant_readonly: Read-only access across all schemas
-- --------------------------------------------------------------------------
GRANT USAGE ON SCHEMA quant TO quant_readonly;
GRANT USAGE ON SCHEMA ops TO quant_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA quant TO quant_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA ops TO quant_readonly;

-- --------------------------------------------------------------------------
-- replicator: Streaming replication role (already created with REPLICATION)
-- --------------------------------------------------------------------------
-- No additional grants needed - REPLICATION privilege is set at role creation.

COMMIT;

-- ============================================================================
-- 11. ANALYZE
-- ============================================================================
-- Update planner statistics after bulk load for optimal query plans.
-- Run outside transaction because ANALYZE cannot run inside a transaction
-- block on partitioned tables in some configurations.
-- ============================================================================

ANALYZE quant.instruments;
ANALYZE quant.market_data;
ANALYZE quant.models;
ANALYZE quant.signals;
ANALYZE quant.positions;
ANALYZE quant.backtests;
ANALYZE quant.model_features;
ANALYZE ops.deployments;
ANALYZE ops.pipeline_runs;
ANALYZE ops.alerts;

-- ============================================================================
-- 12. ROW COUNT VERIFICATION
-- ============================================================================
-- Validate that all tables were seeded with the expected row counts.
-- ============================================================================

DO $$
DECLARE
    v_count BIGINT;
    v_table TEXT;
    v_expected BIGINT;
    v_results TEXT := E'\n========================================\n';
    v_pass BOOLEAN := true;
BEGIN
    v_results := v_results || '  quantdb SEED DATA VERIFICATION' || E'\n';
    v_results := v_results || '========================================' || E'\n';

    -- quant.instruments (~50,000)
    SELECT COUNT(*) INTO v_count FROM quant.instruments;
    v_results := v_results || format('  quant.instruments     : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 49000 AND 51000 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 49000 AND 51000 THEN v_pass := false; END IF;

    -- quant.market_data (~10,000,000)
    SELECT COUNT(*) INTO v_count FROM quant.market_data;
    v_results := v_results || format('  quant.market_data     : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 9000000 AND 11000000 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 9000000 AND 11000000 THEN v_pass := false; END IF;

    -- quant.models (~500)
    SELECT COUNT(*) INTO v_count FROM quant.models;
    v_results := v_results || format('  quant.models          : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 490 AND 510 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 490 AND 510 THEN v_pass := false; END IF;

    -- quant.signals (~5,000,000)
    SELECT COUNT(*) INTO v_count FROM quant.signals;
    v_results := v_results || format('  quant.signals         : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 4500000 AND 5500000 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 4500000 AND 5500000 THEN v_pass := false; END IF;

    -- quant.positions (~200,000)
    SELECT COUNT(*) INTO v_count FROM quant.positions;
    v_results := v_results || format('  quant.positions       : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 190000 AND 210000 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 190000 AND 210000 THEN v_pass := false; END IF;

    -- quant.backtests (~10,000)
    SELECT COUNT(*) INTO v_count FROM quant.backtests;
    v_results := v_results || format('  quant.backtests       : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 9500 AND 10500 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 9500 AND 10500 THEN v_pass := false; END IF;

    -- quant.model_features (~2,000,000)
    SELECT COUNT(*) INTO v_count FROM quant.model_features;
    v_results := v_results || format('  quant.model_features  : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 1900000 AND 2100000 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 1900000 AND 2100000 THEN v_pass := false; END IF;

    -- ops.deployments (~2,000)
    SELECT COUNT(*) INTO v_count FROM ops.deployments;
    v_results := v_results || format('  ops.deployments       : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 1900 AND 2100 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 1900 AND 2100 THEN v_pass := false; END IF;

    -- ops.pipeline_runs (~5,000)
    SELECT COUNT(*) INTO v_count FROM ops.pipeline_runs;
    v_results := v_results || format('  ops.pipeline_runs     : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count BETWEEN 4500 AND 5500 THEN 'PASS' ELSE 'FAIL' END) || E'\n';
    IF v_count NOT BETWEEN 4500 AND 5500 THEN v_pass := false; END IF;

    -- ops.alerts (trigger-populated, should be 0 after bulk load with triggers disabled)
    SELECT COUNT(*) INTO v_count FROM ops.alerts;
    v_results := v_results || format('  ops.alerts            : %s rows %s',
        LPAD(v_count::TEXT, 12, ' '),
        CASE WHEN v_count = 0 THEN 'PASS (triggers were disabled)' ELSE 'INFO' END) || E'\n';

    v_results := v_results || '========================================' || E'\n';
    v_results := v_results || '  Overall: ' || CASE WHEN v_pass THEN 'ALL PASSED' ELSE 'SOME FAILED' END || E'\n';
    v_results := v_results || '========================================';

    RAISE NOTICE '%', v_results;
END
$$;

-- ============================================================================
-- END OF quantdb.sql
-- ============================================================================
