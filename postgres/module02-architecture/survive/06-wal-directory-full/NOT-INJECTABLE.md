# Not injectable on a single lab node

Filling the WAL directory for real needs pg_wal on its own small filesystem. The only way to
get one on a single CentOS lab node is a loop-device image mounted over /opt/pgsql/wal with
pg_wal relocated onto it, and that relocation outlives the fix: after the learner frees the
space, their WAL keeps living on a 175 MB volume for the rest of the course and fills up
again under the next write-heavy module (it did exactly that in the 2026-11-04 self-test).
Filling the root filesystem instead is forbidden by the script contract (1 GB floor).

The tutor walks this runbook from the learner's pasted df, du and pg_wal listings.
