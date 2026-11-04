# Module 03 - Variables, for_each and Clean Config

Part of the Terraform for DBAs track: learn Terraform from scratch to provision and import real AWS database infrastructure as code.

**Environment:** one CentOS Stream 9 server (tf-lab-1, t3.small) with Terraform and the AWS CLI, and an attached IAM role that can manage RDS, Aurora, S3, Secrets Manager, CloudWatch and EC2 networking in the learner's own AWS account. Every lab creates real AWS resources and tears them down with `terraform destroy` at the end.

## Concepts
- Everyday Terraform: fmt, validate, locals, functions, and workspaces

## Build
- Reusable Security Groups with Terraform Variables and for_each
