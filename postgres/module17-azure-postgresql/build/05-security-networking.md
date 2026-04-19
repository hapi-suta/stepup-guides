# BUILD 05 - Security and Networking for Azure Database for PostgreSQL Flexible Server

## Overview

In this guide you will configure security and networking for your Flexible Server. You will set up Azure AD (Entra ID) authentication, configure SSL/TLS, set up Private Link and VNet integration, manage firewall rules, enable Microsoft Defender for PostgreSQL, and configure customer-managed encryption keys.

---

## Prerequisites

- Completed BUILD 01 (server created and accessible)
- Azure CLI authenticated
- An Azure AD (Entra ID) user account for testing
- psql client installed locally

---

## Step 1 - Understand Networking Options

Flexible Server supports three networking modes. You choose one at creation time and cannot change it later.

| Mode | Description | Use Case |
|------|-------------|----------|
| Public access | Internet-accessible with firewall rules | Dev/test, simple setups |
| VNet integration | Server inside a delegated subnet | Production, private networking |
| Private Link | Private endpoint in your VNet | Multi-VNet, hub-spoke topologies |

**Public access** - The server gets a public IP. Firewall rules control who can connect.

**VNet integration** - The server is placed directly into a subnet. No public IP. All traffic stays in the VNet.

**Private Link** - Creates a private endpoint in your VNet that maps to the server's private IP. Works across VNets and subscriptions.

---

## Step 2 - Configure Firewall Rules (Public Access)

If your server uses public access, manage firewall rules to control access. List existing rules.

```bash
az postgres flexible-server firewall-rule list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

Add a rule for a specific IP range. The `--start-ip-address` and `--end-ip-address` flags define the allowed range.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --rule-name office-network \
  --start-ip-address 10.0.0.1 \
  --end-ip-address 10.0.0.254
```

Allow access from all Azure services. This uses the special IP range 0.0.0.0 to 0.0.0.0.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --rule-name allow-azure-services \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0
```

Delete a firewall rule.

```bash
az postgres flexible-server firewall-rule delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --rule-name office-network \
  --yes
```

---

## Step 3 - SSL/TLS Configuration

SSL is enforced by default on Flexible Server. Check the current SSL setting.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name require_secure_transport \
  --query "{Name:name, Value:value}" \
  --output table
```

Expected output (yours will differ):

```
Name                       Value
-------------------------  -----
require_secure_transport   on
```

This parameter enforces that all connections use SSL/TLS. Never disable it in production.

Check the minimum TLS version.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name ssl_min_protocol_version \
  --query "{Name:name, Value:value}" \
  --output table
```

Expected output (yours will differ):

```
Name                        Value
--------------------------  --------
ssl_min_protocol_version    TLSv1.2
```

Set the minimum TLS version to 1.3 for stronger security.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name ssl_min_protocol_version \
  --value TLSv1.3
```

---

## Step 4 - Download the Azure CA Certificate

To verify the server's SSL certificate, download the Azure root CA.

```bash
curl -o /tmp/DigiCertGlobalRootCA.crt.pem https://dl.cacerts.digicert.com/DigiCertGlobalRootCA.crt.pem
```

This downloads the DigiCert Global Root CA certificate that Azure uses. The `-o` flag saves it to the specified path.

Verify the download.

```bash
ls -la /tmp/DigiCertGlobalRootCA.crt.pem
```

Expected output (yours will differ):

```
-rw-r--r--  1 user  staff  1338 Apr 19 15:30 /tmp/DigiCertGlobalRootCA.crt.pem
```

Connect with full SSL verification using the `sslrootcert` parameter. The `sslmode=verify-full` mode validates the server certificate AND verifies the hostname matches.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=verify-full sslrootcert=/tmp/DigiCertGlobalRootCA.crt.pem"
```

Expected output (yours will differ):

```
psql (16.3, server 16.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

Exit psql.

```sql
\q
```

---

## Step 5 - Configure Azure AD (Entra ID) Authentication

Azure AD authentication lets users log in with their Microsoft identity instead of a PostgreSQL password.

First, set an Azure AD administrator on the server. Replace `[AD_USER_UPN]` with the Azure AD user's principal name (their email) and `[AD_USER_OBJECT_ID]` with their object ID.

Find the user's object ID.

```bash
az ad user show --id [AD_USER_UPN] --query id --output tsv
```

Expected output (yours will differ):

```
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Set this user as the Azure AD admin for the server.

```bash
az postgres flexible-server ad-admin create \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --display-name [AD_USER_UPN] \
  --object-id [AD_USER_OBJECT_ID] \
  --type User
```

Expected output (yours will differ):

```json
{
  "objectId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "principalName": "user@contoso.com",
  "principalType": "User",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

---

## Step 6 - Connect with Azure AD Token

Get an Azure AD access token for PostgreSQL. The `--resource-type` flag specifies that you want a token for Azure OSSRDBMS (Open Source Relational Database Management Service).

```bash
az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv
```

Expected output (yours will differ):

```
eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsIng1dCI6Ik...very-long-token...
```

This token is valid for approximately 1 hour. Use it as the password when connecting with psql.

```bash
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)
```

This sets the `PGPASSWORD` environment variable. The `export` command makes it available to psql.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=[AD_USER_UPN] sslmode=require"
```

Expected output (yours will differ):

```
psql (16.3, server 16.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

Exit psql.

```sql
\q
```

Clear the password variable for security.

```bash
unset PGPASSWORD
```

---

## Step 7 - Create an Azure AD PostgreSQL User

While connected as the Azure AD admin, create a PostgreSQL role mapped to another Azure AD user. Connect first as the AD admin (using the token method from Step 6).

```bash
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)
```

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=[AD_USER_UPN] sslmode=require"
```

Once connected, create a role for another Azure AD user. Replace `[OTHER_USER_UPN]` with the other user's email.

```sql
SELECT * FROM pgaadauth_create_principal('[OTHER_USER_UPN]', false, false);
```

The `pgaadauth_create_principal` function creates a PostgreSQL role mapped to an Azure AD identity. The first `false` means this is not a service principal. The second `false` means this is not a managed identity.

Grant permissions to the new user.

```sql
GRANT ALL ON DATABASE pitr_test TO "[OTHER_USER_UPN]";
```

Verify the role was created.

```sql
SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = '[OTHER_USER_UPN]';
```

Expected output (yours will differ):

```
       rolname        | rolcanlogin
----------------------+-------------
 user2@contoso.com    | t
```

Exit psql.

```sql
\q
```

---

## Step 8 - Revoke Azure AD Access

Remove an Azure AD user's access. Connect as the AD admin.

```bash
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken --output tsv)
```

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=[AD_USER_UPN] sslmode=require"
```

Revoke permissions and drop the role.

```sql
REVOKE ALL ON DATABASE pitr_test FROM "[OTHER_USER_UPN]";
```

```sql
SELECT * FROM pgaadauth_drop_principal('[OTHER_USER_UPN]');
```

Exit psql.

```sql
\q
```

```bash
unset PGPASSWORD
```

Remove the Azure AD admin assignment.

```bash
az postgres flexible-server ad-admin delete \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --object-id [AD_USER_OBJECT_ID] \
  --yes
```

---

## Step 9 - Set Up Private Link

Private Link creates a private endpoint in your VNet that connects to the server through the Microsoft backbone network. This works for servers with public access (unlike VNet integration which is set at creation).

Create a VNet and subnet for the private endpoint.

```bash
az network vnet create \
  --name suta-pg-plink-vnet \
  --resource-group suta-pg-lab-rg \
  --location eastus \
  --address-prefix 10.1.0.0/16
```

```bash
az network vnet subnet create \
  --name suta-pg-plink-subnet \
  --resource-group suta-pg-lab-rg \
  --vnet-name suta-pg-plink-vnet \
  --address-prefix 10.1.1.0/24
```

Disable private endpoint network policies on the subnet. This is required for private endpoint creation.

```bash
az network vnet subnet update \
  --name suta-pg-plink-subnet \
  --resource-group suta-pg-lab-rg \
  --vnet-name suta-pg-plink-vnet \
  --disable-private-endpoint-network-policies true
```

Create the private endpoint. The `--private-connection-resource-id` flag specifies the server. The `--group-ids` flag specifies the sub-resource (postgresqlServer for Flexible Server).

```bash
az network private-endpoint create \
  --name suta-pg-private-endpoint \
  --resource-group suta-pg-lab-rg \
  --vnet-name suta-pg-plink-vnet \
  --subnet suta-pg-plink-subnet \
  --private-connection-resource-id "/subscriptions/[SUBSCRIPTION_ID]/resourceGroups/suta-pg-lab-rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/suta-pg-lab-server" \
  --group-ids postgresqlServer \
  --connection-name suta-pg-private-connection
```

Expected output (yours will differ):

```json
{
  "id": "/subscriptions/.../privateEndpoints/suta-pg-private-endpoint",
  "location": "eastus",
  "name": "suta-pg-private-endpoint",
  "privateLinkServiceConnections": [
    {
      "groupIds": ["postgresqlServer"],
      "name": "suta-pg-private-connection",
      "privateLinkServiceConnectionState": {
        "status": "Approved"
      }
    }
  ]
}
```

---

## Step 10 - Configure Private DNS Zone

For private endpoints to resolve correctly, set up a private DNS zone.

```bash
az network private-dns zone create \
  --resource-group suta-pg-lab-rg \
  --name privatelink.postgres.database.azure.com
```

Link the DNS zone to your VNet. The `--registration-enabled` flag set to `false` means VMs in this VNet will not auto-register DNS records.

```bash
az network private-dns link vnet create \
  --resource-group suta-pg-lab-rg \
  --zone-name privatelink.postgres.database.azure.com \
  --name suta-pg-dns-link \
  --virtual-network suta-pg-plink-vnet \
  --registration-enabled false
```

Create a DNS record group for the private endpoint.

```bash
az network private-endpoint dns-zone-group create \
  --resource-group suta-pg-lab-rg \
  --endpoint-name suta-pg-private-endpoint \
  --name suta-pg-dns-zone-group \
  --private-dns-zone privatelink.postgres.database.azure.com \
  --zone-name postgres
```

---

## Step 11 - Verify Private Link

Check the private endpoint's IP address.

```bash
az network private-endpoint show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-private-endpoint \
  --query "customDnsConfigs[0].{FQDN:fqdn, IPAddress:ipAddresses[0]}" \
  --output table
```

Expected output (yours will differ):

```
FQDN                                                        IPAddress
----------------------------------------------------------  ----------
suta-pg-lab-server.privatelink.postgres.database.azure.com  10.1.1.4
```

From a VM inside the VNet, you can now connect using the private IP. The DNS zone resolves the server FQDN to the private IP automatically.

---

## Step 12 - Enable Microsoft Defender for PostgreSQL

Microsoft Defender detects anomalous database activities and potential security threats.

```bash
az postgres flexible-server threat-protection-policy update \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --state Enabled
```

Expected output (yours will differ):

```json
{
  "creationTime": "2026-04-19T16:00:00.000Z",
  "state": "Enabled"
}
```

Defender monitors for:
- SQL injection attempts
- Brute force login attacks
- Anomalous access patterns
- Data exfiltration indicators

Alerts appear in Azure Security Center and can be sent via email.

---

## Step 13 - Configure Data Encryption with Customer-Managed Keys

By default, Azure encrypts data at rest with Microsoft-managed keys. For regulatory requirements, you can use your own keys via Azure Key Vault.

Create a Key Vault. The `--enable-purge-protection` flag prevents permanent deletion of keys (required for CMK encryption).

```bash
az keyvault create \
  --name suta-pg-lab-kv \
  --resource-group suta-pg-lab-rg \
  --location eastus \
  --enable-purge-protection true
```

Create an encryption key. The `--kty` flag specifies the key type (RSA). The `--size` flag sets the key length.

```bash
az keyvault key create \
  --vault-name suta-pg-lab-kv \
  --name suta-pg-encryption-key \
  --kty RSA \
  --size 2048
```

Expected output (yours will differ):

```json
{
  "key": {
    "kid": "https://suta-pg-lab-kv.vault.azure.net/keys/suta-pg-encryption-key/xxxxxxxx",
    "kty": "RSA",
    "n": "..."
  }
}
```

To use this key with your server, you need to create a managed identity and grant it access to the key. This is a multi-step process best done during server creation. See the Azure documentation for the full setup.

---

## Step 14 - Audit Logging

Enable audit logging to track who does what on your server.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name pgaudit.log \
  --value "write, ddl, role"
```

The `pgaudit.log` parameter controls what gets audited:
- `write` - INSERT, UPDATE, DELETE
- `ddl` - CREATE, ALTER, DROP
- `role` - GRANT, REVOKE, CREATE ROLE

Enable the pgaudit extension.

```bash
az postgres flexible-server parameter set \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name shared_preload_libraries \
  --value pgaudit
```

This is a static parameter - the server restarts automatically.

---

## Step 15 - Verify Security Configuration

Run a security checklist.

Check SSL enforcement.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name require_secure_transport \
  --query value \
  --output tsv
```

Expected output:

```
on
```

Check minimum TLS version.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name ssl_min_protocol_version \
  --query value \
  --output tsv
```

Expected output:

```
TLSv1.3
```

Check audit logging.

```bash
az postgres flexible-server parameter show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --name pgaudit.log \
  --query value \
  --output tsv
```

Expected output:

```
write, ddl, role
```

Check Defender status.

```bash
az postgres flexible-server threat-protection-policy show \
  --resource-group suta-pg-lab-rg \
  --server-name suta-pg-lab-server \
  --query state \
  --output tsv
```

Expected output:

```
Enabled
```

---

## Summary

You have completed the following:

- Understood three networking modes (public access, VNet integration, Private Link)
- Managed firewall rules for public access servers
- Configured SSL/TLS enforcement and minimum TLS version
- Downloaded the Azure CA certificate for SSL verification
- Set up Azure AD authentication with admin and user roles
- Connected using Azure AD tokens
- Created a Private Link endpoint with DNS configuration
- Enabled Microsoft Defender for threat detection
- Created a Key Vault for customer-managed encryption keys
- Enabled pgAudit for database audit logging

Key takeaway: Defense in depth - use network isolation (VNet/Private Link), strong authentication (Azure AD), encryption (SSL + CMK), and monitoring (Defender + pgAudit) together. No single security measure is sufficient.
