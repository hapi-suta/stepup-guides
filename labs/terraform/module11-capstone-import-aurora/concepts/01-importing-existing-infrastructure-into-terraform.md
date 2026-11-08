# Importing Existing Infrastructure into Terraform

This explains why a DBA imports infrastructure that already exists, what the `terraform import`
command does, and what a safe import looks like. It is reading only - the commands are in the
BUILD guide.

## What it is

Importing means telling Terraform "this database already exists - start managing it." Terraform
writes a record of the real object into its **state**, so from then on it can plan changes to it,
detect drift, and eventually destroy it like anything else it manages.

## Why a DBA needs it

Most real databases were not born in Terraform. Someone clicked through the console, ran a
script, or inherited the cluster from another team. This is called **brownfield** infrastructure
(greenfield is brand new). You cannot ask the business to delete a production Aurora cluster so
you can recreate it in code. Import is how you bring it under code without touching it:

- **Reviewed changes** - a backup window or instance size change becomes a pull request.
- **Drift detection** - hand changes in the console show up in the next plan.
- **Rebuild and DR** - once captured as code, the setup is reproducible in another region.
- **Audit** - the config shows exactly how the database is set up.

## What import does and does not do

Import does exactly one thing: it adds an entry to the **state file** linking a resource address
in your code to a real ID in AWS. It does not change AWS. It does **not** write your configuration
for you (the classic CLI command, at least) and it cannot read secrets back - a database master
password is never returned by AWS, so Terraform cannot know it.

## The two inputs: address and ID

- **Address** - where the resource lives in your code, such as `aws_rds_cluster.legacy`. That
  `resource` block must already exist.
- **ID** - how AWS identifies the real object. For RDS and Aurora this is usually the identifier
  you named it, like `legacy-aurora`. The correct ID format differs for each resource type, and the
  provider documentation lists it at the bottom of each resource page.

A wrong address gives "does not exist in the configuration". A wrong ID gives "non-existent remote
object".

## The workflow

1. Write a `resource` block that describes the existing object as best you can.
2. Import it so state links the address to the real ID.
3. Read the real values back with `terraform state show`.
4. Edit your config to match reality, then `terraform plan`.
5. Repeat until the plan shows **no destroy and no replace**. A small in-place `~` change is
   usually fine; a `-/+` is a stop sign.

## The golden rule: never get a destroy

If your config disagrees with a setting that cannot be changed in place - an identifier, the
engine, the subnet group, sometimes the storage encryption - Terraform plans a **replace**
(`-/+`, "forces replacement"). On a database that means deleting it and building an empty new one.
The config is the thing you adjust to match reality, never the other way round. Protective
settings help here: `deletion_protection = true` makes AWS refuse the delete, and a
`lifecycle { prevent_destroy = true }` block makes Terraform refuse to plan it.

## Things that look scary but are normal

- A `+ master_password (sensitive value)` in the plan after importing a cluster - import cannot
  read the password, so your config sets it.
- Newly shown defaults like write-forwarding flags - the provider fills in values AWS did not
  return during import.
- A `~` in-place update - it changes an attribute, it does not recreate the database.

## Destroy still means destroy

Once a resource is imported, it is fully managed. `terraform destroy` will really delete the
production database. Teach that to anyone you hand the code to, and keep deletion protection on.

## Where this goes next

The next module imports many resources at once using declarative `import` blocks and generated
configuration, so you are not writing every block by hand.
