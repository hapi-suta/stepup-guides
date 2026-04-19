# BUILD 05 - Cloud SQL for PostgreSQL: Security and Networking

## What You Will Build

A secure Cloud SQL setup with IAM database authentication, Cloud SQL Auth Proxy, Private IP with VPC, SSL/TLS enforcement, authorized networks, customer-managed encryption keys (CMEK), and audit logging.

---

## Prerequisites

- Completed BUILD 01 (instance `suta-pg-lab` exists and is running)
- `gcloud` CLI authenticated and project set
- Owner or Editor role on the GCP project
- A VPC network (we will use the default or create one)

---

## Step 1 - Understand Cloud SQL Security Layers

Cloud SQL has multiple security layers:

| Layer | What It Does | How |
|---|---|---|
| Network | Controls who can reach the instance | Private IP, Authorized Networks, Auth Proxy |
| Authentication | Verifies identity | PostgreSQL passwords, IAM auth, Auth Proxy |
| Encryption in transit | Protects data on the wire | SSL/TLS certificates |
| Encryption at rest | Protects stored data | Google-managed or customer-managed keys |
| Audit | Tracks who did what | Cloud Audit Logs, pg_audit |

---

## Step 2 - Configure Private IP (VPC)

Private IP keeps your database traffic inside Google's network. No public internet exposure.

Enable the Service Networking API. This is required for Private IP.

```bash
gcloud services enable servicenetworking.googleapis.com
```

Allocate an IP range for Cloud SQL in your VPC. The `--global` flag makes it available across regions. The `--prefix-length` sets the CIDR size (/20 gives 4096 IPs).

```bash
gcloud compute addresses create cloudsql-private-range \
  --global \
  --purpose=VPC_PEERING \
  --prefix-length=20 \
  --network=default
```

Expected output (yours will differ):

```
Created [https://www.googleapis.com/compute/v1/projects/my-project/global/addresses/cloudsql-private-range].
```

Create a private connection between your VPC and Cloud SQL.

```bash
gcloud services vpc-peerings connect \
  --service=servicenetworking.googleapis.com \
  --ranges=cloudsql-private-range \
  --network=default
```

Expected output (yours will differ):

```
Operation "operations/pssn.p24-123456789-abc123" finished successfully.
```

This takes 1-3 minutes. It creates a VPC peering connection.

Now assign a private IP to your instance.

```bash
gcloud sql instances patch suta-pg-lab --network=default --no-assign-ip
```

The `--network` flag specifies the VPC. The `--no-assign-ip` flag removes the public IP.

WARNING: If you remove the public IP, you can only connect via Private IP or the Auth Proxy. Make sure you have access before doing this in production.

To keep BOTH public and private IP:

```bash
gcloud sql instances patch suta-pg-lab --network=default
```

Verify the network configuration.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(ipAddresses)"
```

Expected output (yours will differ):

```yaml
ipAddresses:
- ipAddress: 34.71.123.45
  type: PRIMARY
- ipAddress: 10.20.30.40
  type: PRIVATE
```

The PRIVATE address (10.x.x.x) is only reachable from within the VPC.

---

## Step 3 - Configure Authorized Networks

Authorized networks whitelist specific IPs or CIDR ranges for public IP access.

Add your office IP range. The `--authorized-networks` flag accepts a comma-separated list of CIDR ranges.

IMPORTANT: Setting this flag REPLACES all existing authorized networks. Include all IPs you want to keep.

```bash
gcloud sql instances patch suta-pg-lab \
  --authorized-networks="203.0.113.0/24,198.51.100.10/32"
```

The first entry is a /24 range (256 IPs - your office). The second is a /32 single IP.

Verify authorized networks.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.ipConfiguration.authorizedNetworks)"
```

Expected output (yours will differ):

```yaml
settings:
  ipConfiguration:
    authorizedNetworks:
    - kind: sql#aclEntry
      value: 203.0.113.0/24
    - kind: sql#aclEntry
      value: 198.51.100.10/32
```

To remove all authorized networks (block all public access):

```bash
gcloud sql instances patch suta-pg-lab --clear-authorized-networks
```

---

## Step 4 - Set Up Cloud SQL Auth Proxy (Service Account)

The Auth Proxy is the recommended way to connect. It handles encryption, authentication, and authorization via IAM.

Create a service account for the proxy.

```bash
gcloud iam service-accounts create cloudsql-proxy \
  --display-name="Cloud SQL Proxy Service Account"
```

Expected output (yours will differ):

```
Created service account [cloudsql-proxy].
```

Grant the service account the Cloud SQL Client role. This lets it connect to Cloud SQL instances.

```bash
gcloud projects add-iam-policy-binding [PROJECT_ID] \
  --member="serviceAccount:cloudsql-proxy@[PROJECT_ID].iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"
```

Create a key file for the service account. This is used by the proxy to authenticate.

```bash
gcloud iam service-accounts keys create /tmp/cloudsql-proxy-key.json \
  --iam-account=cloudsql-proxy@[PROJECT_ID].iam.gserviceaccount.com
```

Expected output (yours will differ):

```
created key [abc123def456] of type [json] as [/tmp/cloudsql-proxy-key.json] for [cloudsql-proxy@my-project.iam.gserviceaccount.com]
```

Start the proxy using the service account key.

```bash
cloud-sql-proxy --credentials-file=/tmp/cloudsql-proxy-key.json [CONNECTION_NAME]
```

In production, use Workload Identity instead of key files. Key files are a security risk if leaked.

---

## Step 5 - Enable IAM Database Authentication

IAM authentication lets GCP users and service accounts connect to PostgreSQL using their IAM identity instead of a password.

Enable IAM authentication on the instance.

```bash
gcloud sql instances patch suta-pg-lab --database-flags=cloudsql.iam_authentication=on
```

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

Create an IAM database user. The username is the email address WITHOUT the domain suffix for users, or the full service account email for service accounts.

For a user account (e.g., user@example.com):

```bash
gcloud sql users create user@example.com \
  --instance=suta-pg-lab \
  --type=CLOUD_IAM_USER
```

For a service account:

```bash
gcloud sql users create cloudsql-proxy@[PROJECT_ID].iam \
  --instance=suta-pg-lab \
  --type=CLOUD_IAM_SERVICE_ACCOUNT
```

Expected output (yours will differ):

```
Creating Cloud SQL user...done.
```

Grant the IAM user permissions in PostgreSQL. Connect as the postgres user first.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "user@example.com";
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "user@example.com";
```

Type `\q` to exit psql.

```
\q
```

Connect using IAM authentication. The proxy handles the token exchange automatically.

```bash
cloud-sql-proxy --auto-iam-authn [CONNECTION_NAME]
```

In a new terminal, connect without a password. The proxy provides the IAM token.

```bash
psql "host=127.0.0.1 user=user@example.com dbname=suta_lab sslmode=disable"
```

---

## Step 6 - Enforce SSL/TLS

Cloud SQL automatically creates server certificates. You can enforce that all connections use SSL.

Check the current SSL configuration.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.ipConfiguration.requireSsl,serverCaCert)"
```

Require SSL for all connections. The `--require-ssl` flag rejects any non-SSL connection.

```bash
gcloud sql instances patch suta-pg-lab --require-ssl
```

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

Download the server CA certificate. You need this to verify the server's identity.

```bash
gcloud sql ssl server-ca-certs list --instance=suta-pg-lab --format="value(cert)" > /tmp/server-ca.pem
```

Create a client certificate for mutual TLS (mTLS). The `--common-name` is a label for the certificate.

```bash
gcloud sql ssl client-certs create client-cert /tmp/client-key.pem --instance=suta-pg-lab
```

Expected output (yours will differ):

```
Created client certificate.
```

Download the client certificate.

```bash
gcloud sql ssl client-certs describe client-cert --instance=suta-pg-lab --format="value(cert)" > /tmp/client-cert.pem
```

Set proper permissions on the key file.

```bash
chmod 0600 /tmp/client-key.pem
```

Connect with full SSL verification.

```bash
psql "host=34.71.123.45 user=postgres dbname=suta_lab sslmode=verify-ca sslrootcert=/tmp/server-ca.pem sslcert=/tmp/client-cert.pem sslkey=/tmp/client-key.pem"
```

Connection string parameters:
- `sslmode=verify-ca`: Verify the server certificate is signed by the CA
- `sslrootcert`: Path to the server CA certificate
- `sslcert`: Path to the client certificate
- `sslkey`: Path to the client private key

Once connected, verify SSL is active.

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output (yours will differ):

```
 ssl | version |         cipher
-----+---------+-------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

Type `\q` to exit psql.

```
\q
```

NOTE: When using the Cloud SQL Auth Proxy, SSL is handled automatically. You do not need to manage certificates.

---

## Step 7 - Rotate SSL Certificates

Cloud SQL server certificates expire. You should rotate them before expiration.

List current server CA certificates.

```bash
gcloud sql ssl server-ca-certs list --instance=suta-pg-lab
```

Create a new server CA certificate.

```bash
gcloud sql ssl server-ca-certs create --instance=suta-pg-lab
```

Rotate to the new certificate.

```bash
gcloud sql ssl server-ca-certs rotate --instance=suta-pg-lab
```

After rotation, download the new CA cert and update your application configuration.

```bash
gcloud sql ssl server-ca-certs list --instance=suta-pg-lab --format="value(cert)" > /tmp/server-ca-new.pem
```

---

## Step 8 - Customer-Managed Encryption Keys (CMEK)

By default, Cloud SQL encrypts data at rest with Google-managed keys. CMEK lets you control the encryption key via Cloud KMS.

Enable the Cloud KMS API.

```bash
gcloud services enable cloudkms.googleapis.com
```

Create a key ring. The `--location` must match your Cloud SQL region.

```bash
gcloud kms keyrings create cloudsql-keyring --location=us-central1
```

Create an encryption key.

```bash
gcloud kms keys create cloudsql-key \
  --location=us-central1 \
  --keyring=cloudsql-keyring \
  --purpose=encryption
```

Get the Cloud SQL service account for your project. Cloud SQL needs permission to use your key.

```bash
gcloud sql instances describe suta-pg-lab --format="value(serviceAccountEmailAddress)"
```

Expected output (yours will differ):

```
p123456789-abc123@gcp-sa-cloud-sql.iam.gserviceaccount.com
```

Grant the Cloud SQL service account permission to use the key.

```bash
gcloud kms keys add-iam-policy-binding cloudsql-key \
  --location=us-central1 \
  --keyring=cloudsql-keyring \
  --member="serviceAccount:p123456789-abc123@gcp-sa-cloud-sql.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

NOTE: CMEK must be set at instance creation time. You cannot add it to an existing instance. To use CMEK, create a new instance with the `--disk-encryption-key` flag:

```bash
gcloud sql instances create suta-pg-cmek \
  --database-version=POSTGRES_16 \
  --tier=db-custom-2-7680 \
  --region=us-central1 \
  --disk-encryption-key=projects/[PROJECT_ID]/locations/us-central1/keyRings/cloudsql-keyring/cryptoKeys/cloudsql-key
```

Verify the encryption key on an instance.

```bash
gcloud sql instances describe suta-pg-cmek --format="value(diskEncryptionConfiguration.kmsKeyName)"
```

---

## Step 9 - Enable pgAudit for Fine-Grained Auditing

pgAudit logs detailed database activity (SELECT, INSERT, UPDATE, DELETE, DDL).

Enable the pgaudit extension via database flags.

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=cloudsql.enable_pgaudit=on,pgaudit.log=all,log_min_duration_statement=1000,log_statement=ddl,log_connections=on,log_disconnections=on,log_lock_waits=on
```

REMEMBER: You must include ALL flags you want active. This includes the flags from BUILD 04.

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

Connect and activate the extension.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

Configure audit logging for a specific role.

```sql
CREATE ROLE auditor;
```

```sql
ALTER ROLE auditor SET pgaudit.log = 'read, write, ddl';
```

```sql
GRANT auditor TO postgres;
```

Verify pgaudit is active.

```sql
SHOW pgaudit.log;
```

Expected output (yours will differ):

```
 pgaudit.log
-------------
 all
(1 row)
```

Type `\q` to exit psql.

```
\q
```

View audit logs in Cloud Logging.

```bash
gcloud logging read 'resource.type="cloudsql_database" AND textPayload:"AUDIT"' \
  --limit=10 \
  --format="table(timestamp,textPayload)"
```

---

## Step 10 - Security Best Practices Checklist

Run these checks on your instance.

Check if public IP is enabled (should be disabled for production).

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(ipAddresses)"
```

Check if SSL is required.

```bash
gcloud sql instances describe suta-pg-lab --format="value(settings.ipConfiguration.requireSsl)"
```

Check if IAM auth is enabled.

```bash
gcloud sql instances describe suta-pg-lab --format="value(settings.databaseFlags)"
```

Check authorized networks (should be minimal or empty).

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.ipConfiguration.authorizedNetworks)"
```

Check backup encryption.

```bash
gcloud sql instances describe suta-pg-lab --format="value(diskEncryptionConfiguration)"
```

---

## Summary

| Task | Command |
|---|---|
| Enable Private IP | `gcloud sql instances patch --network=default` |
| Require SSL | `gcloud sql instances patch --require-ssl` |
| Create client cert | `gcloud sql ssl client-certs create` |
| Enable IAM auth | `--database-flags=cloudsql.iam_authentication=on` |
| Create IAM user | `gcloud sql users create --type=CLOUD_IAM_USER` |
| Rotate SSL certs | `gcloud sql ssl server-ca-certs rotate` |
| Enable pgAudit | `--database-flags=cloudsql.enable_pgaudit=on` |
| CMEK at creation | `--disk-encryption-key=projects/.../cryptoKeys/...` |

You now have a security-hardened Cloud SQL instance with IAM authentication, SSL/TLS, Private IP, audit logging, and encryption key management.
