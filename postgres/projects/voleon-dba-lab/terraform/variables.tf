variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "lab_name" {
  type    = string
  default = "voleon-lab"
}

variable "ami_id" {
  type        = string
  default     = "ami-0dd5887d49587d8e9"
  description = "CentOS Stream 9 x86_64 20260615 - owner 125523088429"
}

variable "ssh_user" {
  type    = string
  default = "ec2-user"
}

variable "key_name" {
  type    = string
  default = "voleon-lab"
}

variable "public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "nodes" {
  type = map(object({
    instance_type = string
    hostname      = string
  }))
  default = {
    primary = {
      instance_type = "t3.medium"
      hostname      = "pg-primary"
    }
    replica = {
      instance_type = "t3.medium"
      hostname      = "pg-replica"
    }
    container = {
      instance_type = "t3.medium"
      hostname      = "pg-container"
    }
    ops = {
      instance_type = "t3.small"
      hostname      = "pg-ops"
    }
  }
}
