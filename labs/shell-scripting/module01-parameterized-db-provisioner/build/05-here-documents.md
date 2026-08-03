---
layout: default
title: "BUILD 05 - Here Documents"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 7
---

# BUILD 05: Here Documents (30 min)

In this guide you will learn about here documents (heredocs) - a shell feature that lets you embed multi-line text directly inside a script. As a DBA, this is how you will send SQL statements to psql from within a shell script without needing separate .sql files.

---

## Why This Matters

Right now, your SQL provisioning script is a standalone .sql file. To turn it into a parameterized shell script, you need a way to embed SQL inside bash and have shell variables expand into the SQL. Heredocs are exactly the tool for this.

---

## Step 1: Create a Practice Directory

On **pg-lab**, as **ec2-user**:

```bash
mkdir -p ~/scripts/heredoc-practice
```

This creates a directory to hold your practice scripts. The `-p` flag means "create parent directories if needed and do not error if the directory already exists."

---

## Step 2: Your First Heredoc

A heredoc lets you write multi-line text inline. The syntax is `<<MARKER` where MARKER is any word you choose. The text continues until a line contains only that MARKER word.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/heredoc-practice/first-heredoc.sh
```

Type the following into the file:

```bash
#!/bin/bash

cat <<EOF
Hello, Beverly.
This text spans multiple lines.
The heredoc ends when the shell sees EOF alone on a line.
EOF
```

Save and exit vi (`:wq`).

Make the script executable.

```bash
chmod +x ~/scripts/heredoc-practice/first-heredoc.sh
```

The `chmod +x` command adds execute permission so you can run the script directly.

Run it.

```bash
~/scripts/heredoc-practice/first-heredoc.sh
```

Expected output (yours will differ):
```
Hello, Beverly.
This text spans multiple lines.
The heredoc ends when the shell sees EOF alone on a line.
```

The word `EOF` is just a convention. You could use `END`, `SQL`, `DONE` - any word. But `EOF` (End Of File) is the most common, and `SQL` is a good choice when writing SQL blocks.

---

## Step 3: Variable Expansion in Heredocs

The real power of heredocs for DBAs: shell variables expand inside them automatically.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/heredoc-practice/variable-heredoc.sh
```

Type the following:

```bash
#!/bin/bash

DB_NAME="promos"
OWNER="postgres"

cat <<EOF
CREATE DATABASE "${DB_NAME}" OWNER "${OWNER}";
GRANT CONNECT ON DATABASE "${DB_NAME}" TO "${DB_NAME}_read_group";
EOF
```

Save and exit vi (`:wq`).

Make it executable and run it.

```bash
chmod +x ~/scripts/heredoc-practice/variable-heredoc.sh
```

```bash
~/scripts/heredoc-practice/variable-heredoc.sh
```

Expected output (yours will differ):
```
CREATE DATABASE "promos" OWNER "postgres";
GRANT CONNECT ON DATABASE "promos" TO "promos_read_group";
```

Notice how `${DB_NAME}` became `promos` and `${OWNER}` became `postgres`. The shell replaced the variables before `cat` ever saw the text. This is exactly how you will inject parameters into SQL.

---

## Step 4: Preventing Variable Expansion

Sometimes you do NOT want variables to expand - you want the text printed literally. Quoting the marker with single quotes (`<<'EOF'`) prevents all expansion.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/heredoc-practice/quoted-heredoc.sh
```

Type the following:

```bash
#!/bin/bash

DB_NAME="promos"

echo "=== Without quotes (variables expand) ==="
cat <<EOF
Database: ${DB_NAME}
EOF

echo ""
echo "=== With quotes (variables stay literal) ==="
cat <<'EOF'
Database: ${DB_NAME}
EOF
```

Save and exit vi (`:wq`).

Make it executable and run it.

```bash
chmod +x ~/scripts/heredoc-practice/quoted-heredoc.sh
```

```bash
~/scripts/heredoc-practice/quoted-heredoc.sh
```

Expected output (yours will differ):
```
=== Without quotes (variables expand) ===
Database: promos

=== With quotes (variables stay literal) ===
Database: ${DB_NAME}
```

The rule is simple:

- `<<EOF` - variables expand (you want this when building SQL with parameters)
- `<<'EOF'` - variables stay literal (you want this when printing usage examples or documentation)

---

## Step 5: Indented Heredocs with <<-

When heredocs appear inside functions or if-blocks, the text sits at column 1 and looks ugly. The `<<-` syntax (note the dash) strips leading **tabs** (not spaces) from each line.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/heredoc-practice/indented-heredoc.sh
```

Type the following. IMPORTANT - you must use actual tab characters for the indentation, not spaces. In vi, tabs are the default when you press the Tab key.

```bash
#!/bin/bash

create_message() {
	cat <<-EOF
	This line has a leading tab that gets stripped.
	So does this one.
	The output will be left-aligned.
	EOF
}

create_message
```

Save and exit vi (`:wq`).

Make it executable and run it.

```bash
chmod +x ~/scripts/heredoc-practice/indented-heredoc.sh
```

```bash
~/scripts/heredoc-practice/indented-heredoc.sh
```

Expected output (yours will differ):
```
This line has a leading tab that gets stripped.
So does this one.
The output will be left-aligned.
```

The `<<-` variant only strips tabs, never spaces. If your editor converts tabs to spaces, the stripping will not work. This is a common gotcha.

---

## Step 6: Using Heredoc with psql

This is the pattern you will use constantly as a DBA - sending SQL to psql via heredoc.

On **pg-lab**, as **ec2-user**:

```bash
sudo su - postgres
```

Now as **postgres** on **pg-lab**:

```bash
vi ~/heredoc-psql-test.sh
```

Type the following:

```bash
#!/bin/bash

TABLE_NAME="heredoc_test"

psql -d postgres <<SQL
CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
    id serial PRIMARY KEY,
    name text NOT NULL,
    created_at timestamptz DEFAULT now()
);
SQL

echo "Table ${TABLE_NAME} created (or already existed)."
```

Save and exit vi (`:wq`).

Make it executable and run it.

```bash
chmod +x ~/heredoc-psql-test.sh
```

```bash
~/heredoc-psql-test.sh
```

Expected output (yours will differ):
```
CREATE TABLE
Table heredoc_test created (or already existed).
```

The heredoc sent the entire SQL block to psql as if you had typed it at the psql prompt. The variable `${TABLE_NAME}` was expanded by bash before psql received the text.

---

## Step 7: Verify the Table Exists

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -c "\d heredoc_test"
```

Expected output (yours will differ):
```
                                        Table "public.heredoc_test"
   Column   |           Type           | Collation | Nullable |                 Default
------------+--------------------------+-----------+----------+------------------------------------------
 id         | integer                  |           | not null | nextval('heredoc_test_id_seq'::regclass)
 name       | text                     |           | not null |
 created_at | timestamp with time zone |           |          | now()
...
```

Run the script a second time to confirm it is idempotent (the `IF NOT EXISTS` clause prevents an error).

```bash
~/heredoc-psql-test.sh
```

Expected output (yours will differ):
```
CREATE TABLE
Table heredoc_test created (or already existed).
```

No error. The `CREATE TABLE IF NOT EXISTS` saw the table already existed and did nothing.

---

## Step 8: Heredoc Quoting - The Critical Detail

When combining shell variables with SQL that contains dollar signs (like `$$` or `$1` in PL/pgSQL), you must be careful. Bash will try to expand anything that looks like a variable.

Still as **postgres** on **pg-lab**:

```bash
vi ~/heredoc-quoting-demo.sh
```

Type the following:

```bash
#!/bin/bash

SCHEMA="public"

echo "=== PROBLEM: bash eats the dollar signs ==="
cat <<EOF
CREATE FUNCTION ${SCHEMA}.add(a int, b int) RETURNS int AS $$
BEGIN
    RETURN a + b;
END;
$$ LANGUAGE plpgsql;
EOF

echo ""
echo "=== SOLUTION 1: escape each dollar sign ==="
cat <<EOF
CREATE FUNCTION ${SCHEMA}.add(a int, b int) RETURNS int AS \$\$
BEGIN
    RETURN a + b;
END;
\$\$ LANGUAGE plpgsql;
EOF

echo ""
echo "=== SOLUTION 2: use quoted heredoc (but loses variable expansion) ==="
cat <<'EOF'
CREATE FUNCTION public.add(a int, b int) RETURNS int AS $$
BEGIN
    RETURN a + b;
END;
$$ LANGUAGE plpgsql;
EOF
```

Save and exit vi (`:wq`).

Make it executable and run it.

```bash
chmod +x ~/heredoc-quoting-demo.sh
```

```bash
~/heredoc-quoting-demo.sh
```

The takeaway: if your SQL contains `$$` delimiters (common in functions and triggers), you have two options:

1. Escape every `$` as `\$` - keeps variable expansion working but is ugly
2. Use `<<'EOF'` - cleaner SQL but you cannot use shell variables

For the provisioner script you are building, you will not need PL/pgSQL functions, so plain `<<EOF` (unquoted) will work fine.

---

## Step 9: Clean Up

Still as **postgres** on **pg-lab**:

```bash
psql -d postgres -c "DROP TABLE IF EXISTS heredoc_test;"
```

```bash
rm ~/heredoc-psql-test.sh ~/heredoc-quoting-demo.sh
```

Exit back to ec2-user.

```bash
exit
```

On **pg-lab**, as **ec2-user**:

You can keep the practice directory for reference or remove it.

```bash
rm -rf ~/scripts/heredoc-practice
```

---

## What You Learned

- A heredoc (`<<EOF ... EOF`) lets you embed multi-line text in a script
- Unquoted `<<EOF` expands shell variables - this is how you parameterize SQL
- Quoted `<<'EOF'` preserves text literally - use this for documentation or when SQL has `$$`
- `<<-EOF` strips leading tabs for cleaner indentation inside functions
- Piping a heredoc to `psql` is the standard way to run inline SQL from bash
- Dollar signs in SQL need escaping (`\$`) when using unquoted heredocs

In the next guide, you will learn additional patterns for integrating psql into shell scripts - including error handling, the `-v` flag for safe variable passing, and idempotent checks.
