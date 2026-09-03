# Use: operate and inspect

Read replication state from PostgreSQL, verify storage/checksums, and check the real
Mattermost workload. Healthy processes alone do not prove these contracts.

```sql
select state,count(*) from pg_stat_replication group by state;
```

```sql
show data_directory; show data_checksums;
```

```bash
curl -fsS http://$(hostname -I | awk '{print $1}'):8065/api/v4/system/ping
```
