# Phase 2 (USE) - Self-Assessment Checklist

Answer each question honestly before moving to Phase 3. If you answer "No" to
any question, go back and repeat the relevant exercise until you can answer "Yes."

---

## Instructions

For each question, ask yourself: "Can I do this right now, from memory, without
looking at the guide?"

Mark each answer:
- **Yes** - I can do this confidently without reference material
- **No** - I need to review this before proceeding

---

## Questions

### Monitoring (Exercise 01)

**1. Can I use `repmgr cluster show` to identify every node's role, status, upstream, and timeline?**

- [ ] Yes
- [ ] No

**2. Can I run `repmgr node check` and interpret every line of output?**

- [ ] Yes
- [ ] No

**3. Can I use `repmgr cluster crosscheck` to diagnose connectivity issues between nodes?**

- [ ] Yes
- [ ] No

### Switchover (Exercise 02)

**4. Can I perform a planned switchover with `repmgr standby switchover --siblings-follow` and explain each step the command executes?**

- [ ] Yes
- [ ] No

**5. Can I explain the difference between switchover and promote, including data loss implications?**

- [ ] Yes
- [ ] No

### Promotion (Exercise 03)

**6. Can I manually promote a standby with `repmgr standby promote` and redirect other standbys with `standby follow`?**

- [ ] Yes
- [ ] No

**7. Can I explain what happens to the witness node's metadata after a promotion, and how to update it?**

- [ ] Yes
- [ ] No

### Rejoin (Exercise 04)

**8. Can I rejoin a failed primary as a standby using `repmgr node rejoin --force-rewind`?**

- [ ] Yes
- [ ] No

**9. Can I explain when `node rejoin` fails and when a full `standby clone --force` is needed instead?**

- [ ] Yes
- [ ] No

### Node Management (Exercise 05)

**10. Can I cleanly remove a standby from the cluster (unregister + drop replication slot)?**

- [ ] Yes
- [ ] No

**11. Can I add a new standby to an existing cluster (clone + register)?**

- [ ] Yes
- [ ] No

**12. Can I explain why orphaned replication slots are dangerous and how to detect them?**

- [ ] Yes
- [ ] No

---

## Scoring

- **12/12 Yes** - You are ready for Phase 3 (SURVIVE). Proceed with confidence.
- **10-11 Yes** - Review the exercises you missed, then re-test yourself. Do not proceed until you hit 12/12.
- **Below 10** - Repeat the full USE phase. Speed comes from repetition, not from rushing forward.

---

## What Phase 3 Expects From You

Phase 3 (SURVIVE) will test your ability to handle failure scenarios without
step-by-step instructions. You will face:

- Automatic failover triggered by primary crash
- Network partitions that risk split-brain
- Cascading node failures
- Witness failure during a failover event
- repmgrd daemon failures requiring manual intervention

If you cannot perform the USE phase tasks from memory, Phase 3 will be
frustrating rather than educational. Take the time now.

---

**Next:** Phase 3 - SURVIVE exercises
