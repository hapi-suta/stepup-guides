# SURVIVE: IAM Misconfiguration Exposes S3 and a Model Endpoint

Your AI application's cloud identity is wildly over-privileged - its IAM policy
grants full wildcard access (`bedrock:*`, `s3:*` on `*`) - and the bucket holding
model inputs is world-readable. This is the single most common cloud AI exposure:
not a clever attack, just a misconfigured policy and an open bucket (Concepts
13.1). If exploited, an attacker with the app's credentials could touch every
Bedrock model and every S3 object in the account, and anyone on the internet
could read the input documents.

In this runbook you will detect the exposure, diagnose the real cause
(least-privilege was never applied), and fix it by scoping both policies down.

**No real cloud and no credentials are involved.** The IAM policy and the bucket
policy are LOCAL JSON files that a checker script evaluates - the same thing an
AWS security review or IAM Access Analyzer would flag - so you fix the security
LOGIC for free.

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - find the real cause.
3. Fix and verify - repair it and prove the repair.

---

## Layer 1: Detect

First run the injector so you can see the exposure.

On your lab server, as ec2-user:

```
bash inject.sh
```

`bash` runs the script. It builds the working directory, writes a misconfigured
IAM policy and bucket policy, and a checker, then evaluates them.

Expected output (yours will differ):

```
==> Creating working directory: /home/ec2-user/survive-iam-misconfig
...
==> Running check_iam.py so you can see the exposure:
-------------------------------------------------------------
EXPOSED
 - IAM: wildcard action ['bedrock:*', 's3:*']
 - IAM: wildcard resource '*'
 - BUCKET: public principal '*' can read objects
-------------------------------------------------------------
```

`EXPOSED` with wildcard actions and a public bucket principal is the finding. The
app can do anything, and the bucket is open to the world.

---

## Layer 2: Diagnose

Move into the working directory.

On your lab server, as ec2-user:

```
cd ~/survive-iam-misconfig
```

Look at the IAM policy.

Still on your lab server, as ec2-user:

```
cat iam_policy.json
```

`cat` prints the file.

Expected output (yours will differ):

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AppPermissions",
      "Effect": "Allow",
      "Action": ["bedrock:*", "s3:*"],
      "Resource": "*"
    }
  ]
}
```

The `Action` grants every Bedrock and every S3 action, and `Resource` is `*` -
every resource in the account. That is the opposite of least privilege
(Concepts 13.1). Now the bucket policy.

Still on your lab server, as ec2-user:

```
cat bucket_policy.json
```

Expected output (yours will differ):

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::client-ai-inputs/*"
    }
  ]
}
```

`"Principal": "*"` on an `Allow` means anyone, with no credentials at all, can
read every object in the bucket. The real cause is not one typo - it is that
least privilege was never applied. A resilient, secure deployment grants only the
exact actions on the exact resources the app needs, and never makes a data bucket
public.

---

## Layer 3: Fix and verify

Scope the IAM policy down to only what the app needs: invoke the one model, read
the one bucket prefix.

Still on your lab server, as ec2-user, open the IAM policy:

```
vi iam_policy.json
```

Press `i` to enter insert mode. Replace the whole file with a least-privilege
version (the model ARN and bucket name are examples - use the client's real ones):

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AppPermissions",
      "Effect": "Allow",
      "Action": ["bedrock:InvokeModel", "s3:GetObject"],
      "Resource": [
        "arn:aws:bedrock:us-east-1::foundation-model/anthropic.claude-3-sonnet",
        "arn:aws:s3:::client-ai-inputs/*"
      ]
    }
  ]
}
```

Press `Esc`, type `:wq`, press Enter. Now remove the public access from the bucket
policy - grant read only to the app's role.

Still on your lab server, as ec2-user:

```
vi bucket_policy.json
```

Press `i`, replace the whole file with:

```
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AppRoleReadOnly",
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789012:role/ai-app-role"},
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::client-ai-inputs/*"
    }
  ]
}
```

Press `Esc`, type `:wq`, press Enter. The `Principal` is now the app's IAM role,
not `*`. Re-run the checker.

Still on your lab server, as ec2-user:

```
python3 check_iam.py
```

Expected output (yours will differ):

```
LOCKED_DOWN: no wildcard IAM and no public bucket access
```

Signs of a secure deployment:

- No wildcard actions - the app can invoke the one model and read the one bucket,
  nothing else (least privilege, Concepts 13.1).
- No wildcard resources - permissions are scoped to specific ARNs.
- No public principal - only the app's role can read the bucket.

In a real AWS account you would additionally turn on account-level Block Public
Access on S3 so a bucket cannot be made public even by accident, and prefer an
IAM role over long-lived keys.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It re-evaluates both policies and checks that neither
grants wildcard access nor public read.

Expected output (yours will differ):

```
Evaluating the IAM and bucket policies ...
LOCKED_DOWN: no wildcard IAM and no public bucket access
PASS: IAM is least-privilege and the bucket is not publicly readable.
```

If you see `PASS`, you are done.

---

Prof. Happy (SUTA Labs)
