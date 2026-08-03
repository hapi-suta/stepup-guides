# Module 01 - AWS Foundations and Aurora Architecture
## Guide 05: Cost Awareness

**Objective:** Understand how Aurora pricing works, set up AWS Budgets and cost alerts so you never get surprised by a bill, and learn the habits that keep your lab costs low throughout this training track.
**Time:** 20 minutes
**Prerequisites:** Guide 01 (AWS Account Setup) completed. AWS CLI configured.
**Infrastructure:** None created in this guide. You will configure billing alerts only. No cost.

---

## 1. Why Cost Awareness Matters Early

Cloud databases cost money every minute they run. Unlike a local PostgreSQL installation (which costs nothing after setup), Aurora charges you for compute time, storage, and I/O operations. A single forgotten Aurora cluster can cost $5-10 per day - and that adds up fast if you leave it running over a weekend or holiday.

This guide exists so you develop the right habits before you create any paid resources. You will learn how Aurora pricing works, set up alerts to catch unexpected charges, and build the discipline of cleaning up after every lab session.

---

## 2. How Aurora Pricing Works

Aurora charges for three things: compute (instances), storage, and I/O operations.

### Instance Hours (Compute)

You pay for every hour your Aurora instances are running. The price depends on the instance type (size) and your region.

| Instance Type | vCPUs | RAM | Price (us-east-1, on-demand) |
|--------------|-------|-----|------------------------------|
| db.t3.medium | 2 | 4 GB | ~$0.082/hour (~$60/month) |
| db.t4g.medium | 2 | 4 GB | ~$0.073/hour (~$53/month) |
| db.r6g.large | 2 | 16 GB | ~$0.277/hour (~$200/month) |
| db.r6g.xlarge | 4 | 32 GB | ~$0.554/hour (~$400/month) |

> **Cost warning:** These are ON-DEMAND prices. Your Aurora cluster costs this amount for every hour it exists - even if no queries are running. The meter starts when you create the cluster and stops when you delete it. Stopping is not enough for long-term savings - stopped Aurora clusters automatically restart after 7 days.

### Storage

Aurora storage costs $0.10 per GB per month. Storage grows automatically as your data grows - you do not provision it. You only pay for what you use.

For this training track, your storage will likely stay under 5 GB, costing less than $0.50/month.

### I/O Operations

Aurora charges $0.20 per million I/O requests. Every read and write to the storage layer counts as an I/O operation.

For lab workloads with small datasets, I/O costs are negligible - usually less than $1/month. For production workloads with millions of transactions, I/O can become the largest cost component.

> **Alternative:** Aurora I/O-Optimized pricing eliminates per-I/O charges in exchange for a higher instance price (~30% more). This is better for I/O-heavy production workloads but not relevant for lab exercises.

### Backup Storage

Aurora continuously backs up your data to S3. Backup storage equal to your database size is free. Storage beyond that costs $0.021 per GB per month. For lab purposes, backup costs will be zero.

---

## 3. Free Tier - Important Distinction

**RDS for PostgreSQL IS eligible for the AWS Free Tier:**
- 750 hours of db.t3.micro per month
- 20 GB of storage
- 20 GB of backup storage
- Valid for 12 months after account creation

**Aurora PostgreSQL is NOT eligible for the AWS Free Tier.**

Every Aurora resource you create will cost money from the moment it exists. This is why cost awareness is so important for this track.

---

## 4. Cost Estimate for This Training Track

Here is what you can expect to spend if you follow the lab exercises and clean up after each session:

| Resource | Usage Pattern | Estimated Cost |
|----------|--------------|---------------|
| Aurora writer instance (db.t3.medium) | ~4 hours/week for 8 weeks | ~$2.60/week |
| Aurora reader instance (db.t3.medium) | ~2 hours/week for 4 weeks | ~$0.65/week |
| Storage (under 5 GB) | Continuous while cluster exists | ~$0.50/month |
| I/O operations | Light lab usage | ~$0.50/month |
| **Total estimated cost** | **Over the full track** | **$20-40** |

The key to staying in this range: **delete your Aurora cluster after each lab session** and recreate it when you need it. The guides will remind you to do this.

> **Cost warning:** If you forget to delete an Aurora cluster with a db.t3.medium instance, it costs roughly $2/day or $60/month. Always check your running resources before ending a study session.

---

## 5. Set Up AWS Budgets

AWS Budgets sends you an alert when your spending approaches a threshold you define. Set this up now - before you create any paid resources.

**In your terminal** (local machine):

```bash
aws budgets create-budget --account-id $(aws sts get-caller-identity --query "Account" --output text) --budget '{"BudgetName":"aurora-lab-monthly","BudgetLimit":{"Amount":"50","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' --notifications-with-subscribers '[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80,"ThresholdType":"PERCENTAGE"},"Subscribers":[{"SubscriptionType":"EMAIL","Address":"YOUR_EMAIL@example.com"}]}]'
```

**Before running this command**, replace `YOUR_EMAIL@example.com` with your actual email address.

Let's break down what this does:
- `create-budget` - creates a new budget in AWS Budgets
- `--account-id` - your AWS account ID (pulled automatically from your CLI credentials)
- `BudgetName` - a name for this budget. Use something descriptive
- `BudgetLimit` - the dollar amount that represents your budget ceiling. $50 gives you plenty of headroom for lab work
- `TimeUnit` - MONTHLY means the budget resets each month
- `BudgetType` - COST means you are tracking actual spending (not usage)
- `NotificationType` - ACTUAL means it alerts on real spending (not forecasted)
- `Threshold` - 80 means you get alerted when spending hits 80% of your budget ($40 in this case)
- `Address` - the email where alerts are sent

Expected output (yours will differ):
```
(no output on success)
```

No output means the budget was created successfully.

### Add a Second Alert at 50%

You can also set an earlier warning at 50% ($25) so you have more time to react:

**In the AWS Console** (Billing > Budgets):

1. In the top search bar, type `Budgets` and click **AWS Budgets**.
2. Click on `aurora-lab-monthly` in the budget list.
3. Click **Edit**.
4. Scroll down to **Configure alerts**.
5. Click **Add alert threshold**.
6. Set the threshold to `50` percent of budgeted amount.
7. Enter your email address.
8. Click **Save**.

Now you will get notified at both 50% and 80% of your monthly budget.

---

## 6. Enable Cost Explorer

Cost Explorer gives you a visual dashboard of your AWS spending over time. It is free to use but needs to be enabled.

**In the AWS Console** (Billing > Cost Explorer):

1. In the top search bar, type `Cost Explorer` and click **AWS Cost Explorer**.
2. If this is your first time, you will see a page that says **Enable Cost Explorer**. Click the button to enable it.
3. It takes up to 24 hours for data to appear. Come back tomorrow to see your first cost data.

Once enabled, Cost Explorer shows spending broken down by service, region, instance type, and time period. You can use it to answer questions like:
- How much did my Aurora cluster cost last week?
- Which service is my biggest cost driver?
- Am I trending higher this month compared to last month?

---

## 7. Check Costs from the CLI

You can also check your costs from the terminal using the `aws ce` (Cost Explorer) commands.

### Get current month's costs by service

**In your terminal** (local machine):

```bash
aws ce get-cost-and-usage --time-period Start=2026-06-01,End=2026-06-09 --granularity MONTHLY --metrics "UnblendedCost" --group-by Type=DIMENSION,Key=SERVICE
```

**Before running this command**, update the `Start` and `End` dates to match the current month. `Start` is the first day of the month. `End` is today's date.

- `ce get-cost-and-usage` - queries Cost Explorer for spending data
- `--time-period` - the date range to query. Format is `YYYY-MM-DD`
- `--granularity MONTHLY` - aggregates costs by month (other options: DAILY, HOURLY)
- `--metrics "UnblendedCost"` - shows the actual cost you will be billed (not amortized or blended)
- `--group-by Type=DIMENSION,Key=SERVICE` - breaks down costs by AWS service

Expected output (yours will differ):
```json
{
    "ResultsByTime": [
        {
            "TimePeriod": {
                "Start": "2026-06-01",
                "End": "2026-06-09"
            },
            "Groups": [
                {
                    "Keys": ["Amazon Relational Database Service"],
                    "Metrics": {
                        "UnblendedCost": {
                            "Amount": "3.28",
                            "Unit": "USD"
                        }
                    }
                }
            ]
        }
    ]
}
```

> **Note:** If you just enabled Cost Explorer, this command may return empty results for the first 24 hours. That is normal.

### Get yesterday's costs (quick daily check)

**In your terminal** (local machine):

```bash
aws ce get-cost-and-usage --time-period Start=2026-06-08,End=2026-06-09 --granularity DAILY --metrics "UnblendedCost"
```

Update the dates to yesterday and today. This gives you a quick answer to: "How much did AWS charge me yesterday?"

---

## 8. Cost Habits for This Training Track

These habits will keep your costs predictable and low:

### Before every lab session
1. Check for any running Aurora clusters from previous sessions:

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters --query "DBClusters[*].{Name:DBClusterIdentifier,Status:Status,Engine:Engine}" --output table
```

- `describe-db-clusters` - lists all Aurora clusters in your default region
- If this returns any clusters you are not actively using, delete them

### After every lab session
2. Delete your Aurora cluster and instances when you are done studying:

**In your terminal** (local machine):

```bash
aws rds describe-db-instances --query "DBInstances[*].{Name:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" --output table
```

- `describe-db-instances` - lists all RDS/Aurora instances in your region
- You will learn the delete commands in Module 02. For now, just know that checking is the first step

### Weekly
3. Check your costs every Monday:

**In your terminal** (local machine):

```bash
aws ce get-cost-and-usage --time-period Start=2026-06-02,End=2026-06-09 --granularity DAILY --metrics "UnblendedCost" --group-by Type=DIMENSION,Key=SERVICE
```

Update the dates to cover the last 7 days. This becomes your weekly cost review.

### Do NOT do these things
- Do not leave Aurora clusters running overnight unless a lab specifically requires it
- Do not create db.r6g or larger instances for lab exercises - db.t3.medium is sufficient
- Do not create more than 2 instances (1 writer + 1 reader) unless a lab requires it
- Do not forget to check billing after creating any new resource

---

## 9. What If You See Unexpected Charges?

If your bill is higher than expected:

1. **Check for running instances immediately:**

**In your terminal** (local machine):

```bash
aws rds describe-db-instances --query "DBInstances[*].{Name:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass,Engine:Engine}" --output table
```

2. **Check ALL regions.** A common mistake is creating resources in a region you forgot about. The command above only checks your default region. To check another region:

**In your terminal** (local machine):

```bash
aws rds describe-db-instances --region us-west-2 --query "DBInstances[*].{Name:DBInstanceIdentifier,Status:DBInstanceStatus}" --output table
```

- `--region us-west-2` - checks Oregon instead of your default region. Repeat for any region you might have used

3. **Check Cost Explorer** for a breakdown by service and date to identify exactly when the charge started.

4. **Delete any resources you are not using.** You will learn the specific delete commands in Module 02.

---

## Summary

- Aurora pricing has three components: instance hours (compute), storage ($0.10/GB/month), and I/O ($0.20/million requests).
- Aurora is NOT eligible for the AWS Free Tier. Every Aurora resource costs money from the moment it exists.
- Expected cost for this training track: $20-40 total, if you clean up after each session.
- Set up AWS Budgets with email alerts at 50% and 80% of a $50 monthly budget.
- Use Cost Explorer (console) and `aws ce get-cost-and-usage` (CLI) to track spending.
- Build the habit: check for running instances before and after every lab session.
- A forgotten db.t3.medium Aurora cluster costs roughly $2/day or $60/month. Always clean up.

**Next:** Module 02 - Launching Your First Aurora Cluster
