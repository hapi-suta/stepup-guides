# Interview Questions: Data Structures

**Module:** 00b - Data Structures
**Purpose:** Practice explaining data structure concepts in a technical interview context
**Time:** 20-30 minutes to review

---

## Question 1: When would you use a list vs a dict vs a set?

### What the interviewer is looking for:
- Understanding of performance tradeoffs (not just features)
- Practical examples showing each one's sweet spot
- Awareness that choosing the wrong data structure leads to performance problems

### Strong Answer:

"It depends on what operations I need to do most.

A **list** is for ordered collections where I need to access items by position, iterate in order, or allow duplicates. Like storing query results row by row.

A **dict** is for key-value lookups. If I need to find something by name, ID, or any key - a dict gives me O(1) lookup instead of scanning a list. As a DBA, I think of it like a hash index. If I have 10,000 servers and I need to find one by hostname, a dict keyed by hostname is instant. Scanning a list of 10,000 items is not.

A **set** is for uniqueness and set operations. If I need to deduplicate data, check membership quickly, or find the intersection/difference of two collections - like finding which databases exist in prod but not in staging - a set is the right choice. It is like `SELECT DISTINCT` or `INTERSECT` in SQL.

The key insight: if you are writing `for item in my_list: if item == target:` repeatedly, you probably want a dict or set instead. That is like doing sequential scans when you should have an index."

### Weak Answer:

"Lists are for storing multiple items. Dicts store key-value pairs. Sets store unique items." (Too shallow - no performance reasoning, no practical examples)

---

## Question 2: What is a list comprehension and why is it faster than a for loop?

### What the interviewer is looking for:
- Can explain the syntax clearly
- Understands the performance difference (C-level loop vs Python-level loop)
- Knows when NOT to use a comprehension

### Strong Answer:

"A list comprehension is a one-line syntax for creating a list by transforming or filtering another collection. The basic pattern is `[expression for item in iterable if condition]`. I think of it like writing a SELECT statement - the expression is what you SELECT, the for clause is FROM, and the if clause is WHERE.

It is faster than an equivalent for loop with `.append()` for two reasons. First, the comprehension is optimized at the C level inside the Python interpreter. The loop overhead, the `.append()` method lookup, and the list resizing are all handled more efficiently. Second, it avoids repeated attribute lookups - in a regular loop, Python has to look up the `.append` method on every iteration.

In practice, comprehensions are typically 10-30% faster for simple operations. But the bigger benefit is readability - experienced Python developers expect to see comprehensions for simple transforms and filters.

I would NOT use a comprehension when the logic is complex (multiple if/else branches, side effects), when the expression is longer than about 80 characters, or when I need to break/continue mid-loop. In those cases, a regular loop is clearer."

### Weak Answer:

"A list comprehension is a shorter way to write a for loop. It is faster because it is on one line." (The speed has nothing to do with being on one line - it is about C-level optimization)

---

## Question 3: Explain the difference between a mutable and immutable data structure.

### What the interviewer is looking for:
- Clear definition with concrete examples
- Understands the practical implications (dict keys, thread safety, unintended side effects)
- Can connect it to database concepts

### Strong Answer:

"A **mutable** data structure can be changed after creation - you can add, remove, or modify elements. Lists, dicts, and sets are mutable. An **immutable** data structure cannot be changed after creation - any 'modification' actually creates a new object. Tuples, strings, and frozensets are immutable.

The practical implications matter more than the definition:

First, only immutable types can be used as dict keys or set elements. That is because dicts and sets use hashing internally, and a mutable object could change its hash after being stored, which would corrupt the data structure. This is why you can use a tuple `(host, port)` as a dict key but not a list.

Second, immutability prevents accidental modification. If I return a tuple from a function, the caller cannot accidentally change the data. If I return a list, they could `.append()` to it and affect shared state. As a DBA, I think of it like the difference between a table and a read-only view.

Third, immutable objects are inherently thread-safe since they cannot be modified. This matters in concurrent programs.

I use tuples for fixed-structure data like `(host, port, dbname)` where the shape is known and should not change. I use lists when the collection needs to grow, shrink, or be reordered."

### Weak Answer:

"Mutable means you can change it, immutable means you cannot. Lists are mutable, tuples are immutable." (Correct but misses the *why it matters* - practical implications are what separates junior from senior)

---

## Question 4: How would you find duplicate entries in a large dataset efficiently?

### What the interviewer is looking for:
- Multiple approaches with tradeoff analysis
- Awareness of time complexity (Big O)
- Practical thinking about memory vs speed

### Strong Answer:

"There are several approaches depending on what I need:

**Approach 1: Set-based detection (O(n) time, O(n) space).** Iterate through the data, maintaining a `seen` set and a `dupes` set. For each item, check if it is in `seen`. If yes, add it to `dupes`. If no, add it to `seen`. This is the fastest general approach because set lookups are O(1).

```python
seen = set()
dupes = set()
for item in data:
    if item in seen:
        dupes.add(item)
    seen.add(item)
```

**Approach 2: Counting with a dict (O(n) time, O(n) space).** Build a frequency dict, then filter for count > 1. This is useful when I also need to know HOW MANY times each duplicate appears - like `GROUP BY + HAVING COUNT(*) > 1`.

```python
counts = {}
for item in data:
    counts[item] = counts.get(item, 0) + 1
dupes = {k: v for k, v in counts.items() if v > 1}
```

**Approach 3: Sort first (O(n log n) time, O(1) extra space).** Sort the data, then check adjacent items. Duplicates will be next to each other. Uses less memory but is slower. Like running a query with `ORDER BY` then scanning for adjacent matches.

For a DBA, this is analogous to choosing between a hash join (set-based, needs memory) and a sort-merge approach (sort first, then scan). The hash approach is typically faster but uses more memory."

### Weak Answer:

"I would loop through the list and for each item, check if it appears anywhere else in the list." (This is O(n^2) - a nested loop. Like a nested loop join without an index. Unacceptable for large datasets.)

---

## Question 5: What is Big O notation and how does it relate to database query performance?

### What the interviewer is looking for:
- Can explain Big O without getting lost in math
- Can map Big O to real database operations
- Demonstrates practical experience with performance optimization

### Strong Answer:

"Big O notation describes how the work an algorithm does scales as the input grows. It is not about exact speed - it is about the *growth rate*. The same way I do not care if a query takes 5ms or 10ms on 100 rows - I care about whether it will take 10ms or 10 minutes on 10 million rows.

The key complexities map directly to database operations:

- **O(1)** - constant time. A hash index lookup or a dict/set lookup in Python. No matter how many rows or items, it takes the same time.
- **O(log n)** - logarithmic. A B-tree index lookup. Doubling the data adds one more step. A million rows needs about 20 lookups.
- **O(n)** - linear. A sequential scan or a Python list scan. If the data doubles, the work doubles.
- **O(n log n)** - sorting. The `Sort` node in an EXPLAIN plan, or `sorted()` in Python.
- **O(n^2)** - quadratic. A nested loop join without an index, or a nested for loop in Python. If data goes from 1,000 to 10,000 rows, the work goes from 1M to 100M operations. This is the one that kills you in production.

As a DBA, I see this every day. When someone complains a query is slow, I run EXPLAIN ANALYZE. If I see a Seq Scan on a large table inside a Nested Loop, I know it is O(n^2). Adding an index on the join column converts it to O(n log n) or better.

In Python, the equivalent optimization is converting a list to a dict or set for lookups. `if x in my_list` is O(n). `if x in my_set` is O(1). Same logic, same fix - add an index."

### Weak Answer:

"Big O is how you measure algorithm efficiency. O(1) is best, O(n^2) is worst." (Too abstract. No connection to practical work. Does not demonstrate understanding of *why* it matters.)
