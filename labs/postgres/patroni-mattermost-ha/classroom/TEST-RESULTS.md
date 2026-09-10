# Live classroom rehearsal — 9 September 2026

Executed September 9 Pacific / September 10 UTC on a fresh HA001 eight-node CentOS lab provisioned with Terraform. Software preparation ran through Ansible; configuration bodies came from the classroom manual with real private addresses and protected passwords substituted.

## Final verified behavior

| Check | Result |
|---|---|
| etcd | Three healthy endpoints using mutual TLS |
| Patroni | One running leader and two streaming replicas |
| PostgreSQL | Two streaming connections; `/opt/pgsql/data`; checksums on |
| Writer endpoint, 5432 | Writable primary reached through HAProxy |
| Reader endpoint, 5433 | Standbys reached; replicated row read; INSERT rejected |
| Real application | Account login, message creation and readback through the router |
| Planned switchover, corrected configuration | 22 successful writes, 1 transient failed write during the marked test window |
| PostgreSQL immediate stop | Same writer recovered; 28 successful writes, no failed writes in the marked window |
| Whole writer server stop/start, corrected configuration | Different leader promoted; returned server rejoined without repair; 83 successful writes, no failed writes in the marked window |
| Patroni service stop, corrected configuration | Different leader promoted; stopped member rejoined; 30 successful writes, 1 transient failed write |
| Final verification | One leader, two streaming replicas; both router endpoints correct; app healthy |
| Data readback | All 470 acknowledged messages, including the baseline message, remained readable |

The workload issued one API write at a time, waited for its result, then paused one second. Windows include recovery observation; request counts are not throughput benchmarks. Maximum observed request durations were 2.805 s for the corrected switchover, 2.048 s for the PostgreSQL stop, 5.431 s for the corrected node test and 2.228 s for the corrected Patroni-service stop. These are request latencies, not measurements of total outage duration.

The application checks used real Mattermost login/post/read APIs. They were not a browser click-through or a concurrent student load test. Failed/timed-out requests were not counted as acknowledged. This is evidence for these runs, not a zero-data-loss guarantee for asynchronous replication.

## Problems found and corrected

1. **Expired Patroni client certificate.** The staged identity had expired September 8. It was renewed from the protected CA, verified, and redistributed before bootstrap. Certificate validity checks are now in the prerequisites.
2. **Connections retained on the former primary.** The original router switched new connections but the app pool retained old connections to the demoted node. App logs showed SQLSTATE 25006, an UPDATE attempted in a read-only transaction. Added `on-marked-down shutdown-sessions` to writer and reader backend lines, validated, and repeated the switchover. App writes then recovered automatically; a transient request failure remained visible rather than being hidden.
3. **Missing socket directory after reboot.** The original unit did not recreate `/var/run/postgresql`. Returning node failed with PermissionError. Added the systemd RuntimeDirectory drop-in on all PG nodes, recovered the member, then repeated a complete writer stop/start on another node without manual repair.

An initial power-operation attempt was rejected because a provisioning-only STS session lacked Stop/Start. No instance changed in that rejected attempt. The actual test used a short-lived session scoped to the selected owned test instance; no IAM role grants were changed.

## Reproduction order

Provision → install software and corrected runtime unit → validate TLS → etcd → Patroni bootstrap → replicas and SQL checks → HAProxy → application database → instructor app → reader endpoint → app workload → switchover → PostgreSQL stop → server stop/start → Patroni stop → endpoint checks → read back acknowledged messages.

The classroom pages place reader routing before handing the app to students, avoiding an unnecessary router restart during their first app use. Both endpoints were verified again after the failure exercises.

[Machine-readable request counts](test-results.json) include the initial failed configuration runs and corrected runs. They are deliberately not collapsed into a misleading all-green total. Private runtime logs and credentials are retained outside this public guide.
