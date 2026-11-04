# Module 07 - Provisioning an Aurora PostgreSQL Cluster

Part of the Terraform for DBAs track: learn Terraform from scratch to provision and import real AWS database infrastructure as code.

**Environment:** one CentOS Stream 9 server (tf-lab-1, t3.small) with Terraform and the AWS CLI, and an attached IAM role that can manage RDS, Aurora, S3, Secrets Manager, CloudWatch and EC2 networking in the learner's own AWS account. Every lab creates real AWS resources and tears them down with `terraform destroy` at the end.

## Build
- Provisioning an Aurora PostgreSQL Cluster with Terraform on AWS
