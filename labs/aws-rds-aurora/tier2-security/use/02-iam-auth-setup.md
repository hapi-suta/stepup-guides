# Use 02 - IAM Auth Setup for an Application Team

**Time:** 25 minutes
**Prerequisite:** Build 02 (IAM Database Authentication)

---

## Scenario

The backend team at [COMPANY] is deploying a new microservice on EC2. The security team has mandated: "No database passwords stored anywhere. Use IAM authentication."

The team lead asks you to set up everything. They give you:
- EC2 instance ID: `i-0abc123456def7890` (running in the same VPC as RDS)
- Application database user name they want: `orders_service`
- Database: `orders_db`
- Schema: `orders`
- Required access: SELECT, INSERT, UPDATE on `orders.shipments` and `orders.items`. SELECT only on `orders.products`.

Your job is to:
1. Set up the PostgreSQL side (role with rds_iam)
2. Set up the AWS side (IAM policy on the EC2 instance role)
3. Test that the EC2 instance can connect using an IAM token
4. Document the connection string for the development team

---

## Setup

Make sure IAM auth is enabled on your RDS instance. If you did Build 02, it already is. If not:

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --enable-iam-database-authentication \
  --apply-immediately \
  --region [REGION]

aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --region [REGION]
```

---

## Task 1 - Set Up the PostgreSQL Side

Connect as master user and create the database, schema, and tables:

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres"
```

```sql
CREATE DATABASE orders_db;
\c orders_db

CREATE SCHEMA orders;

CREATE TABLE orders.shipments (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    status TEXT NOT NULL,
    shipped_at TIMESTAMPTZ,
    carrier TEXT
);

CREATE TABLE orders.items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price NUMERIC(10,2)
);

CREATE TABLE orders.products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    sku TEXT UNIQUE,
    price NUMERIC(10,2)
);
```

Now create the IAM-authenticated role:

```sql
CREATE ROLE orders_service WITH LOGIN;
GRANT rds_iam TO orders_service;
```

Grant exactly the permissions specified:

```sql
GRANT CONNECT ON DATABASE orders_db TO orders_service;
GRANT USAGE ON SCHEMA orders TO orders_service;

-- shipments and items: read and write
GRANT SELECT, INSERT, UPDATE ON orders.shipments TO orders_service;
GRANT SELECT, INSERT, UPDATE ON orders.items TO orders_service;
GRANT USAGE, SELECT ON SEQUENCE orders.shipments_id_seq TO orders_service;
GRANT USAGE, SELECT ON SEQUENCE orders.items_id_seq TO orders_service;

-- products: read only
GRANT SELECT ON orders.products TO orders_service;
```

Verify the setup:

```sql
SELECT grantee, table_name, string_agg(privilege_type, ', ') AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'orders_service'
  AND table_schema = 'orders'
GROUP BY grantee, table_name
ORDER BY table_name;
```

Confirm the output matches the requirements:
- `items` - INSERT, SELECT, UPDATE
- `products` - SELECT only
- `shipments` - INSERT, SELECT, UPDATE

---

## Task 2 - Get the EC2 Instance's IAM Role

Find the IAM role attached to the EC2 instance:

```bash
export EC2_INSTANCE_ID="i-0abc123456def7890"
export AWS_REGION="us-east-1"

aws ec2 describe-instances \
  --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text \
  --region $AWS_REGION
```

Expected output (yours will differ):

```
arn:aws:iam::123456789012:instance-profile/orders-service-profile
```

Extract the role name from the instance profile:

```bash
export INSTANCE_PROFILE_ARN=$(aws ec2 describe-instances \
  --instance-ids $EC2_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
  --output text \
  --region $AWS_REGION)

export EC2_ROLE_NAME=$(aws iam get-instance-profile \
  --instance-profile-name $(basename $INSTANCE_PROFILE_ARN) \
  --query 'InstanceProfile.Roles[0].RoleName' \
  --output text)

echo "EC2 Role: $EC2_ROLE_NAME"
```

---

## Task 3 - Create and Attach the IAM Policy

Get the DB resource ID:

```bash
export DB_RESOURCE_ID=$(aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].DbiResourceId' \
  --output text \
  --region $AWS_REGION)

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "DB Resource ID: $DB_RESOURCE_ID"
```

Create the policy:

```bash
cat > /tmp/orders-service-iam-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:${AWS_REGION}:${AWS_ACCOUNT_ID}:dbuser:${DB_RESOURCE_ID}/orders_service"
    }
  ]
}
EOF
```

```bash
aws iam create-policy \
  --policy-name OrdersServiceRDSPolicy \
  --policy-document file:///tmp/orders-service-iam-policy.json
```

Attach the policy to the EC2 role:

```bash
aws iam attach-role-policy \
  --role-name $EC2_ROLE_NAME \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrdersServiceRDSPolicy"
```

---

## Task 4 - Download the CA Certificate on the EC2 Instance

SSH into the EC2 instance:

```bash
ssh ec2-user@[EC2-PUBLIC-IP]
```

Download the certificate bundle:

```bash
curl -o /etc/ssl/certs/rds-ca-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

---

## Task 5 - Test the Connection from EC2

Still on the EC2 instance, generate a token and connect:

```bash
export RDS_HOST="your-instance.abc123.us-east-1.rds.amazonaws.com"
export AWS_REGION="us-east-1"

export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname $RDS_HOST \
  --port 5432 \
  --region $AWS_REGION \
  --username orders_service)
```

Connect:

```bash
psql \
  "host=$RDS_HOST \
   port=5432 \
   dbname=orders_db \
   user=orders_service \
   sslmode=verify-full \
   sslrootcert=/etc/ssl/certs/rds-ca-bundle.pem"
```

Test the permissions:

```sql
-- Should succeed
INSERT INTO orders.shipments (order_id, status, carrier)
VALUES (1001, 'pending', 'UPS');

-- Should succeed
SELECT * FROM orders.products LIMIT 5;

-- Should fail with permission denied
DELETE FROM orders.products WHERE id = 1;
```

Verify `DELETE` is denied:

```
ERROR:  permission denied for table products
```

---

## Task 6 - Write the Connection Documentation

Write a short handoff note for the backend team. Include:

1. The connection string they should use (substitute the real values)
2. How to generate the IAM token in code (choose Python or Node.js from Build 02)
3. What happens when the token expires and how their code should handle it
4. Which permissions the `orders_service` role has on each table

Template:

```
IAM Auth Setup - orders-service
================================

RDS Host:     [YOUR-RDS-HOST]
Port:         5432
Database:     orders_db
DB Username:  orders_service
Auth method:  IAM token (NOT password)

Token generation command (for testing):
  aws rds generate-db-auth-token \
    --hostname [RDS-HOST] \
    --port 5432 \
    --region [REGION] \
    --username orders_service

Permissions:
  orders.shipments  - SELECT, INSERT, UPDATE
  orders.items      - SELECT, INSERT, UPDATE
  orders.products   - SELECT only

Token expiration: 15 minutes. Generate a new token for each connection.
SSL: Required. Use sslmode=verify-full with the global CA bundle.
```

---

## Stretch Challenge

If the EC2 instance does NOT have an IAM role attached, how would you attach one?

Research the commands:
- `aws iam create-instance-profile`
- `aws iam add-role-to-instance-profile`
- `aws ec2 associate-iam-instance-profile`

---

## Clean Up

```sql
-- In psql as master user
\c postgres
DROP DATABASE orders_db;
DROP ROLE orders_service;
```

```bash
# In the terminal
aws iam detach-role-policy \
  --role-name $EC2_ROLE_NAME \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrdersServiceRDSPolicy"

aws iam delete-policy \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrdersServiceRDSPolicy"
```
