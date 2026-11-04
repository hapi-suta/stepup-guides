# Not injectable: 08-multi-region-failover

The scenario is a whole region going away: the fix is promoting the standby in the other region and moving DNS or a load balancer to it. There is no region, DNS zone or cloud console on the lab node, and the surviving standby is another host the scripts cannot reach. The tutor should walk the runbook from pasted output: have the learner describe or paste the standby's `pg_stat_wal_receiver`, replay lag and `pg_is_in_recovery()`, then guide the promotion decision, the DNS cutover and the post-failover checks as a tabletop exercise.
