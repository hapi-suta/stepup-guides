# Survive: A secret that will not resolve (15 min)

## The Scenario

A teammate's Terraform project reads the database login from AWS Secrets Manager instead of
holding a password. This morning `terraform plan` stopped working and the pipeline is red. You
have been asked to find out why Terraform cannot read the secret and fix it, without ever
pasting the password into a file. There are three separate faults hiding in the config - you will
meet them one at a time, the way you would in real life.

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. The only thing that costs
money is one small Secrets Manager secret, which you delete in Step 6.

---

## Step 1: Create the secret the project is supposed to read

On **tf-lab-1**, as **ec2-user**, first generate a random value into a shell variable. This keeps
the password out of your command history and out of any file.

```bash
PW=$(openssl rand -base64 18 | tr -d '/+=')
```

`openssl rand -base64 18` makes random text. `tr -d '/+='` deletes characters that can upset a
connection string. `$( ... )` captures the result into the variable `PW`.

Create the secret with a JSON body, the same shape the BUILD tutorial used.

```bash
aws secretsmanager create-secret --name tf-survive-appdb --secret-string "{\"username\":\"dbadmin\",\"password\":\"$PW\"}" --region us-east-1
```

`create-secret` makes a named slot in Secrets Manager. `--secret-string` is the content. The
shell fills in `$PW` before the command runs.

**Expected output (yours will differ):**
```
{
    "ARN": "arn:aws:secretsmanager:us-east-1:...:secret:tf-survive-appdb-AbCdEf",
    "Name": "tf-survive-appdb",
    "VersionId": "..."
}
```

Clear the variable so it does not linger in your shell.

```bash
unset PW
```

**Check it worked:** You see an ARN and `"Name": "tf-survive-appdb"`.

---

## Step 2: Fault one - the wrong secret name

On **tf-lab-1**, as **ec2-user**, make a scratch project.

```bash
mkdir -p ~/survive-secret && cd ~/survive-secret
```

Open `main.tf` with vi.

```bash
vi main.tf
```

Press `i`, paste this, then `Esc` and `:wq`. Notice the name has a typo: `appdb` should be
`tf-survive-appdb`.

```
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = "appdb"
}

output "db_user" {
  value     = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)["username"]
  sensitive = true
}
```

Initialise, then run validate.

```bash
terraform init
```

```bash
terraform validate
```

**Expected output (yours will differ):**
```
Success! The configuration is valid.
```

Validate **passes**. It only checks that the syntax is well-formed - it has no idea whether a
secret named `appdb` exists. Now plan, which makes Terraform actually call AWS to read the data
source.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: reading Secrets Manager Secret Version ...
│
│   with data.aws_secretsmanager_secret_version.db,
│   on main.tf line 14, in data "aws_secretsmanager_secret_version" "db":
│
│ ResourceNotFoundException: Secrets Manager can't find the specified secret.
╵
```

**What the message is telling you:** The block that failed is named in the `with` line, and the
AWS error code is `ResourceNotFoundException` - the name does not exist. Before changing
anything, prove what does exist by listing secrets (read-only, names only).

```bash
aws secretsmanager list-secrets --region us-east-1 --query "SecretList[?starts_with(Name,'tf-survive')].Name" --output text
```

`--query` filters the answer with a JMESPath expression; `--output text` prints plain text.

**Expected output (yours will differ):**
```
tf-survive-appdb
```

Fix the name in `main.tf`: change `secret_id = "appdb"` to `secret_id = "tf-survive-appdb"`.

```bash
vi main.tf
```

---

## Step 3: Fault two - the key does not exist inside the JSON

On **tf-lab-1**, as **ec2-user**, run plan again with the name fixed.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
data.aws_secretsmanager_secret_version.db: Read complete after 0s [id=...]

Changes to Outputs:
  + db_user = (sensitive value)
```

It works, so we will plant fault two on purpose. The secret body is a JSON **string**, and
`jsondecode()` turns it into something you can index by key. Open `main.tf` and mistype the key:
change `["username"]` to `["usernme"]`.

```bash
vi main.tf
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: Invalid index
│
│   on main.tf line 19, in output "db_user":
│   19:   value = jsondecode(...)["usernme"]
│
│ The given key does not identify an element in this collection value.
╵
```

**What the message is telling you:** Secrets Manager read fine - the fault is now in your code.
Terraform cannot guess which key you meant. To see the **key names** without printing the
password, ask AWS for the secret and print only the keys.

```bash
aws secretsmanager get-secret-value --secret-id tf-survive-appdb --region us-east-1 --query SecretString --output text | python3 -c "import sys, json; print(list(json.load(sys.stdin).keys()))"
```

`get-secret-value` fetches the secret body. The `python3 -c` part reads that JSON and prints only
the key names, so the password never appears on screen.

**Expected output (yours will differ):**
```
['username', 'password']
```

Fix the key back to `["username"]`.

```bash
vi main.tf
```

---

## Step 4: Fault three - the output that leaks

On **tf-lab-1**, as **ec2-user**, remove `sensitive = true` from the output block.

```bash
vi main.tf
```

Then plan.

```bash
terraform plan
```

**Expected output (yours will differ):**
```
╷
│ Error: Output refers to sensitive values
│
│   on main.tf line 18:
│   18: output "db_user" {
│
│ To represent that this is intended, mark the output as sensitive...
╵
```

**The lesson:** Terraform will not let a value that came from a secret be printed by accident.
Everything derived from `secret_string` is sensitive. Put `sensitive = true` back, then confirm the
clean plan returns.

```bash
vi main.tf
```

```bash
terraform plan
```

**Expected output (yours will differ):**
```
Changes to Outputs:
  + db_user = (sensitive value)
```

**Check it worked:** The plan is clean again and no password appears anywhere on screen.

A fourth fault you may meet in real life but cannot reproduce on this box: if the error says
`AccessDeniedException` instead of `ResourceNotFoundException`, the name is right but the **IAM
role** cannot read it. The fix is an IAM permission (`secretsmanager:GetSecretValue`), never a
hardcoded password.

---

## Step 5: Confirm Terraform created nothing

On **tf-lab-1**, as **ec2-user**, this project only reads, so state is empty. We still run the
destroy habit.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
No changes. No objects need to be destroyed.

Destroy complete! Resources: 0 destroyed.
```

---

## Step 6: Delete the practice secret

This step permanently deletes the secret, so check first that you are deleting the right one.
On **tf-lab-1**, as **ec2-user**:

```bash
aws secretsmanager describe-secret --secret-id tf-survive-appdb --region us-east-1 --query Name --output text
```

**Expected output (yours will differ):**
```
tf-survive-appdb
```

Only if it printed exactly `tf-survive-appdb`, delete it in this separate step.

```bash
aws secretsmanager delete-secret --secret-id tf-survive-appdb --force-delete-without-recovery --region us-east-1
```

`--force-delete-without-recovery` skips the normal 7 to 30 day waiting period so no cost lingers.
Never use it on a real production secret.

**Expected output (yours will differ):**
```
{
    "ARN": "arn:aws:secretsmanager:us-east-1:...",
    "Name": "tf-survive-appdb",
    "DeletionDate": "..."
}
```

Clean up the scratch directory.

```bash
cd ~ && rm -rf ~/survive-secret
```

**Check it worked:** the `list-secrets` command from Step 2 now returns nothing.

---

## What you practised

- Reading the first lines of a Terraform error to learn which block and which AWS error caused it.
- Knowing `validate` passes with a wrong secret name - only `plan` (which calls AWS) catches it.
- Telling a missing secret (`ResourceNotFoundException`) from a code mistake (`Invalid index`) from a
  permission problem (`AccessDeniedException`).
- Why secret-derived outputs must be `sensitive = true`, and how to inspect key names without
  printing the password.
- Cleaning up a billable secret in its own gated step.
