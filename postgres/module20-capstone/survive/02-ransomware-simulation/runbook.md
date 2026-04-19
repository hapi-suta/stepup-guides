# Runbook 02 - Ransomware Simulation

**Severity:** Critical - Application data inaccessible, backup catalog corrupted
**Time to resolve:** 20-40 minutes
**Skills tested:** Backup restore (Module 09), PITR (Module 09), security audit (Module 07), damage assessment

---

## Fix Path

### Step 1: Assess the damage

Do NOT pay the ransom. Connect to the database and inventory what happened.

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "\dt app.*"
```

You should see the renamed tables (ending in `_encrypted_pay_5btc`) and the `ransom_note` table.

Check if the audit trail is gone:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM audit.activity_log;"
```

Expected: 0 (truncated by the attacker).

Check the backup catalog:

```bash
pgbackrest --stanza=prod info
```

If the catalog is corrupted/missing, you will see an error.

### Step 2: Restore the backup catalog

The catalog was moved, not deleted. Check:

```bash
ls /opt/pgsql/backup/pgbackrest/backup/
```

If you see `prod.ransomed`, move it back:

```bash
mv /opt/pgsql/backup/pgbackrest/backup/prod.ransomed /opt/pgsql/backup/pgbackrest/backup/prod
```

Verify:

```bash
pgbackrest --stanza=prod info
```

You should see your backups listed again.

### Step 3: Decide on recovery approach

You have two options:

**Option A: Rename the tables back** (fastest, if no data was actually modified)

Since the attacker only renamed tables (simulated encryption), the data is intact. Just rename them back.

**Option B: PITR to before the attack** (safest, if you suspect data modification)

Restore the entire cluster to a point before the attack happened.

### Step 4 (Option A): Rename tables back

```bash
/usr/pgsql-16/bin/psql -d appdb -c "ALTER TABLE app.orders_encrypted_pay_5btc RENAME TO orders;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "ALTER TABLE app.customers_encrypted_pay_5btc RENAME TO customers;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "ALTER TABLE app.items_encrypted_pay_5btc RENAME TO order_items;"
```

### Step 4 (Option B): PITR recovery

Check the injection time in the state file:

```bash
cat /tmp/stepup-capstone-02-state.env
```

Use the `INJECTED_AT` timestamp. Set your PITR target to 1 minute before that.

```bash
exit
```

Stop PostgreSQL:

```bash
systemctl stop postgresql-16
```

Restore:

```bash
su - postgres
```

```bash
pgbackrest --stanza=prod --type=time "--target=[1 MINUTE BEFORE INJECTION]" --target-action=promote --delta restore
```

```bash
exit
```

Start PostgreSQL:

```bash
systemctl start postgresql-16
```

### Step 5: Remove the ransom note

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "DROP TABLE IF EXISTS app.ransom_note;"
```

### Step 6: Verify data integrity

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.orders;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.customers;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.order_items;"
```

Compare with the values in the state file.

### Step 7: Re-establish backup schedule

Take an immediate full backup:

```bash
pgbackrest --stanza=prod --type=full backup
```

Verify:

```bash
pgbackrest --stanza=prod info
```

### Step 8: Security investigation

Check for unauthorized roles:

```bash
/usr/pgsql-16/bin/psql -c "SELECT rolname, rolsuper, rolcreaterole FROM pg_roles WHERE rolsuper = true;"
```

Check recent connections:

```bash
grep "connection authorized" /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log | tail -20
```

Rotate all passwords:

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE app_readwrite WITH PASSWORD 'NewRW_2026_rotated';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE app_readonly WITH PASSWORD 'NewRO_2026_rotated';"
```

```bash
/usr/pgsql-16/bin/psql -c "ALTER ROLE app_owner WITH PASSWORD 'NewOwner_2026_rotated';"
```

```bash
exit
```

---

## Revision Concepts

**Q: In a real ransomware attack, would renaming tables back work?**
A: No. Real ransomware encrypts the actual data files on disk, not just SQL objects. You would need to restore from backup. This scenario simulates the decision-making process, not the exact technical attack vector.

**Q: Why did we check the backup catalog before attempting PITR?**
A: Sophisticated attackers target backups first. If the backup catalog is gone, you need to reconstruct it or find offsite copies. This is why offsite/immutable backups (S3 with Object Lock, air-gapped tapes) are essential.

**Q: What if the attacker also compromised the standby?**
A: If both the primary and standby are compromised, your only option is the offsite backup repository. This is the scenario that justifies the cost of maintaining offsite encrypted backups with immutability protection.
