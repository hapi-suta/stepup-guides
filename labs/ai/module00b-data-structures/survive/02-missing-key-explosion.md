# SURVIVE 02: The Missing Key That Crashed Production

**Module:** 00b - Data Structures
**Type:** Chaos scenario - debug and fix
**Time:** 15-20 minutes

---

## The Symptom

Your team has a config parser that reads database connection settings from a dictionary. It works perfectly in the primary datacenter where all config fields are present. But when deployed to the DR site, it crashes because some optional fields are missing:

```
Traceback (most recent call last):
  File "/opt/scripts/config_parser.py", line 15, in <module>
    ssl_mode = config['ssl_mode']
KeyError: 'ssl_mode'
```

The DR site does not use SSL, so `ssl_mode` is not in its config. The script never considered that fields might be optional.

---

## The Diagnosis

**Create the buggy script:**

```bash
vi /tmp/survive2_buggy.py
```

**Paste this code (it has bugs - do NOT fix it yet, just read it):**

```python
# config_parser.py - BUGGY VERSION
# Parses database connection configs from different datacenters

# This config works (primary datacenter - all fields present)
primary_config = {
    'host': 'pg-primary.us-east-1.internal',
    'port': 5432,
    'database': 'myapp_prod',
    'user': 'app_user',
    'password': 'secret123',
    'ssl_mode': 'verify-full',
    'ssl_cert': '/etc/ssl/client.crt',
    'pool_size': 20,
    'statement_timeout': '30s',
}

# This config crashes (DR site - minimal config, no SSL)
dr_config = {
    'host': 'pg-dr.us-west-2.internal',
    'port': 5432,
    'database': 'myapp_prod',
    'user': 'app_user',
    'password': 'dr_secret456',
}

def parse_config(config, site_name):
    """Parse a database config dict and print connection details."""
    print(f"\n=== {site_name} ===")

    # BUG 1: Direct access on optional fields - crashes if missing
    host = config['host']
    port = config['port']
    database = config['database']
    user = config['user']
    ssl_mode = config['ssl_mode']  # BUG: not all sites use SSL

    print(f"Host: {host}:{port}")
    print(f"Database: {database}")
    print(f"User: {user}")
    print(f"SSL Mode: {ssl_mode}")

    # BUG 2: Accessing nested optional config without checking
    ssl_cert = config['ssl_cert']  # BUG: missing in DR config
    print(f"SSL Cert: {ssl_cert}")

    # BUG 3: Using optional field in calculation without default
    pool_size = config['pool_size']  # BUG: missing in DR config
    per_core = pool_size // 4
    print(f"Pool Size: {pool_size} ({per_core} per core)")

    # BUG 4: Building connection string assumes all fields exist
    timeout = config['statement_timeout']  # BUG: missing in DR config
    conn_string = f"host={host} port={port} dbname={database} user={user}"
    conn_string += f" sslmode={ssl_mode}"
    conn_string += f" options=-c\\ statement_timeout={timeout}"
    print(f"Connection string: {conn_string}")


# This works
parse_config(primary_config, "Primary (us-east-1)")

# This crashes
parse_config(dr_config, "DR (us-west-2)")
```

**Run it to see the crash:**

```bash
python3 /tmp/survive2_buggy.py
```

Expected output (yours will differ):
```
=== Primary (us-east-1) ===
Host: pg-primary.us-east-1.internal:5432
Database: myapp_prod
User: app_user
SSL Mode: verify-full
SSL Cert: /etc/ssl/client.crt
Pool Size: 20 (5 per core)
Connection string: host=pg-primary.us-east-1.internal port=5432 dbname=myapp_prod user=app_user sslmode=verify-full options=-c\ statement_timeout=30s

=== DR (us-west-2) ===
Traceback (most recent call last):
  File "/tmp/survive2_buggy.py", line 50, in <module>
    parse_config(dr_config, "DR (us-west-2)")
  File "/tmp/survive2_buggy.py", line 25, in parse_config
    ssl_mode = config['ssl_mode']
KeyError: 'ssl_mode'
```

Primary works fine because all keys exist. DR crashes on the first missing key.

---

## The Fix

The fix has two parts:
1. Use `.get()` with sensible defaults for all optional fields
2. Add validation for required fields

**Create the fixed version:**

```bash
vi /tmp/survive2_fixed.py
```

```python
# config_parser.py - FIXED VERSION

primary_config = {
    'host': 'pg-primary.us-east-1.internal',
    'port': 5432,
    'database': 'myapp_prod',
    'user': 'app_user',
    'password': 'secret123',
    'ssl_mode': 'verify-full',
    'ssl_cert': '/etc/ssl/client.crt',
    'pool_size': 20,
    'statement_timeout': '30s',
}

dr_config = {
    'host': 'pg-dr.us-west-2.internal',
    'port': 5432,
    'database': 'myapp_prod',
    'user': 'app_user',
    'password': 'dr_secret456',
}

# Even worse - a completely broken config for testing validation
bad_config = {
    'port': 5432,
}

# Define which fields are required vs optional (with defaults)
REQUIRED_FIELDS = ['host', 'port', 'database', 'user', 'password']
OPTIONAL_DEFAULTS = {
    'ssl_mode': 'disable',
    'ssl_cert': None,
    'pool_size': 10,
    'statement_timeout': '60s',
}


def validate_config(config, site_name):
    """Check that all required fields are present. Return list of missing fields."""
    missing = [field for field in REQUIRED_FIELDS if field not in config]
    if missing:
        print(f"ERROR [{site_name}]: Missing required fields: {', '.join(missing)}")
        return False
    return True


def parse_config(config, site_name):
    """Parse a database config dict and print connection details."""
    print(f"\n=== {site_name} ===")

    # FIX: Validate required fields first
    if not validate_config(config, site_name):
        return

    # Required fields - safe to use direct access after validation
    host = config['host']
    port = config['port']
    database = config['database']
    user = config['user']

    print(f"Host: {host}:{port}")
    print(f"Database: {database}")
    print(f"User: {user}")

    # FIX 1: Use .get() with defaults for optional fields
    ssl_mode = config.get('ssl_mode', OPTIONAL_DEFAULTS['ssl_mode'])
    print(f"SSL Mode: {ssl_mode}")

    # FIX 2: Check for None before using optional values
    ssl_cert = config.get('ssl_cert', OPTIONAL_DEFAULTS['ssl_cert'])
    if ssl_cert:
        print(f"SSL Cert: {ssl_cert}")
    else:
        print("SSL Cert: (none)")

    # FIX 3: Use default for optional numeric field
    pool_size = config.get('pool_size', OPTIONAL_DEFAULTS['pool_size'])
    per_core = pool_size // 4
    print(f"Pool Size: {pool_size} ({per_core} per core)")

    # FIX 4: Build connection string conditionally
    timeout = config.get('statement_timeout', OPTIONAL_DEFAULTS['statement_timeout'])
    conn_string = f"host={host} port={port} dbname={database} user={user}"
    if ssl_mode != 'disable':
        conn_string += f" sslmode={ssl_mode}"
    conn_string += f" options=-c\\ statement_timeout={timeout}"
    print(f"Connection string: {conn_string}")


# All three configs - no crashes
parse_config(primary_config, "Primary (us-east-1)")
parse_config(dr_config, "DR (us-west-2)")
parse_config(bad_config, "Bad Config (test)")
```

**Run the fixed version:**

```bash
python3 /tmp/survive2_fixed.py
```

Expected output (yours will differ):
```
=== Primary (us-east-1) ===
Host: pg-primary.us-east-1.internal:5432
Database: myapp_prod
User: app_user
SSL Mode: verify-full
SSL Cert: /etc/ssl/client.crt
Pool Size: 20 (5 per core)
Connection string: host=pg-primary.us-east-1.internal port=5432 dbname=myapp_prod user=app_user sslmode=verify-full options=-c\ statement_timeout=30s

=== DR (us-west-2) ===
Host: pg-dr.us-west-2.internal:5432
Database: myapp_prod
User: app_user
SSL Mode: disable
SSL Cert: (none)
Pool Size: 10 (2 per core)
Connection string: host=pg-dr.us-west-2.internal port=5432 dbname=myapp_prod user=app_user options=-c\ statement_timeout=60s

=== Bad Config (test) ===
ERROR [Bad Config (test)]: Missing required fields: host, database, user, password
```

---

## Validation Checklist

- [ ] Primary config works exactly as before (no behavior change)
- [ ] DR config no longer crashes - uses sensible defaults
- [ ] Bad config is caught with a clear error message listing ALL missing fields
- [ ] SSL mode shows "disable" instead of crashing when not configured
- [ ] Pool size defaults to 10 when not specified
- [ ] Connection string skips `sslmode` when SSL is disabled
- [ ] No `KeyError` exceptions anywhere

## Key Takeaways

1. **Use `dict.get(key, default)` for optional fields.** It is like `COALESCE()` - always provides a fallback. Use direct `dict[key]` access only when the key is guaranteed to exist.

2. **Validate required fields explicitly.** Define what is required and what is optional. Check before processing. This is like adding `NOT NULL` constraints.

3. **Define defaults in one place.** The `OPTIONAL_DEFAULTS` dict acts like `DEFAULT` values in a `CREATE TABLE`. If the default ever changes, you change it in one place.

4. **Test with minimal configs.** Just like you test database migrations on empty tables, test config parsers with minimal configs. Whatever can be missing, will be missing.

5. **Never assume all environments are identical.** Primary, replica, staging, and DR sites often have different configurations. Code must handle the differences.
