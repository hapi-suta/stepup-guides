# SURVIVE 01: The Off-By-One Error

**Module:** 00b - Data Structures
**Type:** Chaos scenario - debug and fix
**Time:** 15-20 minutes

---

## The Symptom

A junior developer wrote a script that generates a daily report from database query results. It worked in testing (with 5 rows) but crashes in production. The on-call engineer sees this in the logs:

```
Traceback (most recent call last):
  File "/opt/scripts/daily_report.py", line 28, in <module>
    row = results[row_number]
IndexError: list index out of range
```

The script processes query results and refers to rows by their "row number" - but it uses **1-based numbering** (like SQL `ROW_NUMBER()`) instead of **0-based indexing** (like Python lists). There are also missing bounds checks.

---

## The Diagnosis

**Create the buggy script:**

```bash
vi /tmp/survive1_buggy.py
```

**Paste this code (it has bugs - do NOT fix it yet, just read it):**

```python
# daily_report.py - BUGGY VERSION
# This script generates a report from query results

# Simulated query results: (db_name, size_mb, connections)
results = [
    ('myapp_prod', 2048, 150),
    ('analytics', 8192, 300),
    ('reporting', 512, 20),
    ('myapp_staging', 256, 25),
    ('metrics', 4096, 100),
]

# BUG 1: The developer thinks row numbers start at 1 (like SQL)
# They want to print "row 1" through "row 5"
print("=== Database Report ===")
for row_number in range(1, len(results) + 1):
    row = results[row_number]  # BUG: off by one
    name, size, conns = row
    print(f"Row {row_number}: {name} - {size} MB")

# BUG 2: Hardcoded index assumes there are always at least 3 results
print("\n=== Top 3 Databases ===")
sorted_results = sorted(results, key=lambda r: r[1], reverse=True)
print(f"1st: {sorted_results[0][0]}")
print(f"2nd: {sorted_results[1][0]}")
print(f"3rd: {sorted_results[2][0]}")

# BUG 3: Tries to access "the 6th database" without checking bounds
print("\n=== Specific Lookup ===")
target_index = 5  # Developer thinks "5th database" = index 5
print(f"Database at position 5: {results[target_index][0]}")

# BUG 4: Slicing mistake - wants the last 2 items
print("\n=== Last 2 Databases ===")
last_two = results[len(results) - 2:len(results) - 1]  # BUG: off by one in slice
for name, size, conns in last_two:
    print(f"  {name}: {size} MB")
```

**Run it to see the crash:**

```bash
python3 /tmp/survive1_buggy.py
```

Expected output (yours will differ):
```
=== Database Report ===
Row 1: analytics - 8192 MB
Row 2: reporting - 512 MB
Row 3: myapp_staging - 256 MB
Row 4: metrics - 4096 MB
Traceback (most recent call last):
  File "/tmp/survive1_buggy.py", line 14, in <module>
    row = results[row_number]
IndexError: list index out of range
```

Notice two things wrong before the crash:
1. "Row 1" shows `analytics` (the 2nd item), not `myapp_prod` (the 1st item)
2. It crashes on the 5th iteration because `results[5]` does not exist in a 5-element list (valid indices are 0-4)

---

## The Fix

Now fix all 4 bugs. Create the corrected version:

```bash
vi /tmp/survive1_fixed.py
```

**Fix each bug:**

**BUG 1:** The loop starts at `range(1, ...)` and uses `results[row_number]` directly. Since Python is 0-indexed, `results[1]` is the second item, and `results[5]` does not exist.

**Fix:** Use `enumerate()` to get both the display number and the correct index:

```python
for row_number, row in enumerate(results, start=1):
    name, size, conns = row
    print(f"Row {row_number}: {name} - {size} MB")
```

**BUG 2:** Hardcoded access to `sorted_results[0]`, `[1]`, `[2]` will crash if there are fewer than 3 results.

**Fix:** Add a bounds check or use slicing:

```python
print("\n=== Top 3 Databases ===")
sorted_results = sorted(results, key=lambda r: r[1], reverse=True)
top_n = min(3, len(sorted_results))
for i in range(top_n):
    print(f"{i+1}: {sorted_results[i][0]}")
```

**BUG 3:** `results[5]` is out of range for a 5-element list. The developer confused "5th item" with "index 5".

**Fix:** Add bounds checking:

```python
print("\n=== Specific Lookup ===")
target_position = 5  # Human-readable: "5th database"
target_index = target_position - 1  # Convert to 0-based
if target_index < len(results):
    print(f"Database at position {target_position}: {results[target_index][0]}")
else:
    print(f"Position {target_position} is out of range (only {len(results)} databases)")
```

**BUG 4:** The slice `[len-2:len-1]` excludes the last element. Remember, the end index in a slice is **excluded**.

**Fix:** Use negative indexing:

```python
print("\n=== Last 2 Databases ===")
last_two = results[-2:]  # Clean and correct
for name, size, conns in last_two:
    print(f"  {name}: {size} MB")
```

**Full fixed file:**

```python
# daily_report.py - FIXED VERSION

results = [
    ('myapp_prod', 2048, 150),
    ('analytics', 8192, 300),
    ('reporting', 512, 20),
    ('myapp_staging', 256, 25),
    ('metrics', 4096, 100),
]

# FIX 1: Use enumerate for correct indexing
print("=== Database Report ===")
for row_number, row in enumerate(results, start=1):
    name, size, conns = row
    print(f"Row {row_number}: {name} - {size} MB")

# FIX 2: Bounds check before accessing by index
print("\n=== Top 3 Databases ===")
sorted_results = sorted(results, key=lambda r: r[1], reverse=True)
top_n = min(3, len(sorted_results))
for i in range(top_n):
    print(f"{i+1}: {sorted_results[i][0]}")

# FIX 3: Convert human position to 0-based index with bounds check
print("\n=== Specific Lookup ===")
target_position = 5
target_index = target_position - 1
if target_index < len(results):
    print(f"Database at position {target_position}: {results[target_index][0]}")
else:
    print(f"Position {target_position} is out of range (only {len(results)} databases)")

# FIX 4: Use negative slicing for last N items
print("\n=== Last 2 Databases ===")
last_two = results[-2:]
for name, size, conns in last_two:
    print(f"  {name}: {size} MB")
```

**Run the fixed version:**

```bash
python3 /tmp/survive1_fixed.py
```

Expected output (yours will differ):
```
=== Database Report ===
Row 1: myapp_prod - 2048 MB
Row 2: analytics - 8192 MB
Row 3: reporting - 512 MB
Row 4: myapp_staging - 256 MB
Row 5: metrics - 4096 MB

=== Top 3 Databases ===
1: analytics
2: metrics
3: myapp_prod

=== Specific Lookup ===
Database at position 5: metrics

=== Last 2 Databases ===
  myapp_staging: 256 MB
  metrics: 4096 MB
```

---

## Validation Checklist

- [ ] No `IndexError` crashes
- [ ] Row 1 correctly shows the first item (`myapp_prod`), not the second
- [ ] Top 3 would not crash even with fewer than 3 databases
- [ ] Position 5 correctly maps to index 4 (the 5th item)
- [ ] Last 2 databases are both shown, not just one

## Key Takeaways

1. **Python is 0-indexed.** The first element is at index 0. If you are used to SQL's `ROW_NUMBER()` starting at 1, always subtract 1 when converting to a Python index.
2. **Always check bounds** before accessing a specific index. Use `if index < len(list)` or use `.get()` for dicts.
3. **Slice end is excluded.** `list[3:5]` gives indices 3 and 4, not 3, 4, and 5.
4. **Use `enumerate()`** instead of manual index math. It eliminates an entire category of off-by-one bugs.
5. **Use negative indexing** for "last N" operations. `list[-2:]` is cleaner and safer than computing `len(list) - 2`.
