# USE 06 - Azure AD (Entra ID) Authentication

## Objective

Configure Azure AD authentication on your Flexible Server, create an Azure AD-mapped PostgreSQL user, connect using a token, and revoke access.

---

## Exercise

### Task 1 - Find the Azure AD User's Object ID

Look up the Azure AD user you want to set as admin. Replace `[AD_USER_UPN]` with the user's email (UPN).

```bash
az ad user show --id [AD_USER_UPN] --query "{DisplayName:displayName, UPN:userPrincipalName, ObjectID:id}" --output table
```

Expected output (yours will differ):

```
DisplayName    UPN                    ObjectID
-------------  ---------------------  ------------------------------------
Happy Afopezi  happy@contoso.com      xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Copy the ObjectID value.

---

### Task 2 - Set Azure AD Admin

Set the Azure AD user as the server admin. Replace `[AD_USER_UPN]` and `[OBJECT_ID]` with your values.

```bash
az postgres flexible-server ad-admin create \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --display-name [AD_USER_UPN] \
  --object-id [OBJECT_ID] \
  --type User
```

Expected output (yours will differ):

```json
{
  "objectId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "principalName": "happy@contoso.com",
  "principalType": "User"
}
```

---

### Task 3 - Verify Azure AD Admin

Confirm the admin is set.

```bash
az postgres flexible-server ad-admin list \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --query "[].{Name:principalName, Type:principalType, ObjectID:objectId}" \
  --output table
```

Expected output (yours will differ):

```
Name               Type  ObjectID
-----------------  ----  ------------------------------------
happy@contoso.com  User  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

---

### Task 4 - Get an Access Token

Get an Azure AD access token for PostgreSQL. The `--resource-type oss-rdbms` flag requests a token scoped to Azure Database for PostgreSQL.

```bash
az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv
```

Expected output (yours will differ):

```
eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik...
```

This token expires in approximately 1 hour.

---

### Task 5 - Connect with Azure AD Token

Set the token as your password and connect.

```bash
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)
```

The `export` command sets the environment variable so psql can use it.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=[AD_USER_UPN] sslmode=require"
```

Verify your identity.

```sql
SELECT current_user, session_user;
```

Expected output (yours will differ):

```
   current_user    |   session_user
-------------------+-------------------
 happy@contoso.com | happy@contoso.com
```

---

### Task 6 - Create an Azure AD PostgreSQL User

While connected as the Azure AD admin, create a role for another Azure AD user. Replace `[OTHER_USER_UPN]` with the other user's email.

```sql
SELECT * FROM pgaadauth_create_principal('[OTHER_USER_UPN]', false, false);
```

The function parameters:
- First argument: the Azure AD user's UPN (email)
- Second argument: `false` means this is NOT a service principal
- Third argument: `false` means this is NOT a managed identity

Expected output (yours will differ):

```
 pgaadauth_create_principal
----------------------------
 Created role for "user2@contoso.com"
```

Grant the user access to a database.

```sql
GRANT CONNECT ON DATABASE postgres TO "[OTHER_USER_UPN]";
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "[OTHER_USER_UPN]";
```

Verify the role exists.

```sql
SELECT rolname, rolcanlogin
FROM pg_roles
WHERE rolname LIKE '%contoso%';
```

Expected output (yours will differ):

```
       rolname        | rolcanlogin
----------------------+-------------
 happy@contoso.com    | t
 user2@contoso.com    | t
```

Exit psql.

```sql
\q
```

---

### Task 7 - Test the New User's Access

The other user would need to get their own token. For testing purposes, if you have access to their account:

```bash
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)
```

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=[OTHER_USER_UPN] sslmode=require"
```

If you do not have access to the other user's account, skip this verification. In production, the other user runs these commands themselves.

---

### Task 8 - Revoke Azure AD User Access

Connect as the Azure AD admin.

```bash
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)
```

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=[AD_USER_UPN] sslmode=require"
```

Revoke all privileges from the user.

```sql
REVOKE ALL ON DATABASE postgres FROM "[OTHER_USER_UPN]";
```

```sql
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM "[OTHER_USER_UPN]";
```

Drop the role.

```sql
SELECT * FROM pgaadauth_drop_principal('[OTHER_USER_UPN]');
```

Expected output (yours will differ):

```
 pgaadauth_drop_principal
--------------------------
 Dropped role for "user2@contoso.com"
```

Verify the role is gone.

```sql
SELECT rolname FROM pg_roles WHERE rolname = '[OTHER_USER_UPN]';
```

Expected output:

```
 rolname
---------
(0 rows)
```

Exit psql.

```sql
\q
```

---

### Task 9 - Clean Up

Clear the password variable.

```bash
unset PGPASSWORD
```

Optionally, remove the Azure AD admin. Replace `[OBJECT_ID]` with the object ID from Task 1.

```bash
az postgres flexible-server ad-admin delete \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --object-id [OBJECT_ID] \
  --yes
```

---

## Checklist

- [ ] Azure AD user's object ID retrieved
- [ ] Azure AD admin set on the server
- [ ] Admin assignment verified via CLI
- [ ] Access token obtained
- [ ] Connected to server using Azure AD token
- [ ] Created a new Azure AD-mapped PostgreSQL role
- [ ] Granted permissions to the new role
- [ ] Revoked all permissions from the role
- [ ] Dropped the Azure AD role
- [ ] Cleaned up environment variable and admin assignment
