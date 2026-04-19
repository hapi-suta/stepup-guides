# Phase 2 (USE) - Self-Assessment Checklist

Answer each question honestly before moving to Phase 3. If you answer "No" to any question, go back and repeat the relevant exercise until you can answer "Yes."

---

## Instructions

For each question, ask yourself: "Can I do this right now, from memory, without looking at the guide?"

Mark each answer:
- **Yes** - I can do this confidently without reference material
- **No** - I need to review this before proceeding

---

## Questions

### Monitoring (Exercise 01)

**1. Can I determine whether a PostgreSQL node is a primary or standby using a single SQL function?**

- [ ] Yes
- [ ] No

**2. Can I name all four LSN columns in pg_stat_replication and explain what each stage represents (sent, write, flush, replay)?**

- [ ] Yes
- [ ] No

**3. Do I know which view to query on the standby side to check replication status, and how it differs from the primary-side view?**

- [ ] Yes
- [ ] No

### Promotion (Exercise 02)

**4. Can I promote a standby from memory without the guide - both the OS method and the SQL method?**

- [ ] Yes
- [ ] No

**5. Do I understand what happens to the old primary's timeline after promotion, and why the new primary gets a new timeline ID?**

- [ ] Yes
- [ ] No

**6. Can I explain why you must stop the old primary before promoting the standby in a planned failover?**

- [ ] Yes
- [ ] No

### Rejoin (Exercise 03)

**7. Can I explain why you cannot simply add standby.signal to the old primary and start it - why pg_rewind (or a fresh base backup) is required?**

- [ ] Yes
- [ ] No

**8. Can I list the prerequisites for pg_rewind (wal_log_hints or checksums) and explain why they are needed?**

- [ ] Yes
- [ ] No

### Lag Measurement (Exercise 04)

**9. Can I measure replication lag three different ways (bytes, time, slot position) and explain when each is most appropriate?**

- [ ] Yes
- [ ] No

**10. Can I explain why `now() - pg_last_xact_replay_timestamp()` gives misleading results on an idle primary, and what to use instead?**

- [ ] Yes
- [ ] No

---

## Scoring

- **10/10 Yes** - You are ready for Phase 3 (SURVIVE). Proceed with confidence.
- **8-9 Yes** - Review the exercises you missed, then re-test yourself. Do not proceed until you hit 10/10.
- **Below 8** - Repeat the full USE phase. Speed comes from repetition, not from rushing forward.

---

## What Phase 3 Expects From You

Phase 3 (SURVIVE) will test your ability to handle failure scenarios without step-by-step instructions. You will face:

- Unplanned primary failure (no clean shutdown)
- Network partitions between nodes
- WAL corruption and recovery
- Replication slot bloat and cleanup
- Cascading standby configuration

If you cannot perform the USE phase tasks from memory, Phase 3 will be frustrating rather than educational. Take the time now.

---

**Next:** Phase 3 - SURVIVE exercises
