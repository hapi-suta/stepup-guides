# Use: The Terraform Core Loop Exercises (20 min)

These exercises build on the BUILD tutorial, where you ran the full Terraform core loop -
`init`, `plan`, `apply`, `destroy` - to create and tear down a real AWS resource. You should have:

- A working `~/terraform-lab` project that applied cleanly at least once
- Comfort reading a `terraform plan` (the `+`, `-`, and `~` symbols)

Work on **tf-lab-1**, as **ec2-user**, in VS Code over Remote-SSH. To keep AWS costs at zero,
most of these use `plan` (which never creates anything). Only Exercise 3 applies, and you destroy
at the end.

---

## Exercise 1: Predict the plan before you read it (6 min)

**Goal:** Build the habit every safe DBA has - predict what Terraform will do, then check.

On **tf-lab-1**, as **ec2-user**, open your `main.tf` and find the resource you created in the
tutorial. Add one tag to it in VS Code, for example inside the resource's `tags = { ... }` block
add:

```
Environment = "practice"
```

Before running anything, **write down**: will Terraform create, change, or destroy? How many
resources?

Now run the plan.

```bash
cd ~/terraform-lab && terraform plan
```

**Expected output (yours will differ):**
```
  # aws_... will be updated in-place
  ~ resource "aws_..." "..." {
      ~ tags = {
          + "Environment" = "practice"
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

- Did your prediction match? What do `~`, `+`, and the words "updated in-place" mean?
- Which change would instead say "must be replaced" (destroy + create)? Why is that dangerous for a
  database?

---

## Exercise 2: Read a destroy plan without destroying (4 min)

**Goal:** See exactly what a destroy would remove before you ever type `yes`.

On **tf-lab-1**, as **ec2-user**:

```bash
terraform plan -destroy
```

**Expected output (yours will differ):**
```
  # aws_... will be destroyed
  - resource "aws_..." "..." {
      ...
    }

Plan: 0 to add, 0 to change, 1 to destroy.
```

- This command made no changes. How is `plan -destroy` safer than running `destroy` and reading
  the prompt?
- For a real database, what single setting would make Terraform refuse to destroy it? (You will
  build this in a later topic - name the concept.)

---

## Exercise 3: The full loop, start to finish (10 min)

**Goal:** Run one clean create-and-remove cycle and prove the resource existed, then was gone.

On **tf-lab-1**, as **ec2-user**, apply.

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

Prove it exists in state.

```bash
terraform state list
```

**Expected output (yours will differ):**
```
aws_...
```

Now tear it down so nothing keeps costing money.

```bash
terraform destroy
```

Type `yes` when prompted.

**Expected output (yours will differ):**
```
Destroy complete! Resources: 1 destroyed.
```

Confirm state is now empty.

```bash
terraform state list
```

**Check it worked:** The command returns nothing - state is empty, the resource is gone.

---

## What you should be able to say now

- What each symbol in a plan means: `+` create, `-` destroy, `~` change in place, `-/+` replace.
- Why you always read a plan before applying, and read `plan -destroy` before destroying.
- Why `destroy` at the end of every practice session keeps your AWS bill at zero.
- What "the state" is and how `terraform state list` proves what Terraform is managing.
