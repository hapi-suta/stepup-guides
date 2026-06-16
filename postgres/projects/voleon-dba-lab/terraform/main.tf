terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Key pair
# ---------------------------------------------------------------------------
resource "aws_key_pair" "lab" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

# ---------------------------------------------------------------------------
# Security group - all nodes in same SG, open internally + SSH from anywhere
# ---------------------------------------------------------------------------
resource "aws_security_group" "lab" {
  name        = "${var.lab_name}-sg"
  description = "Voleon DBA lab - PG, Redis, PgBouncer, Prometheus, Grafana, Docker, SSH"

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # PostgreSQL
  ingress {
    from_port   = 5432
    to_port     = 5433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PostgreSQL (5432 native, 5433 docker)"
  }

  # PgBouncer
  ingress {
    from_port   = 6432
    to_port     = 6432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "PgBouncer"
  }

  # Redis
  ingress {
    from_port   = 6379
    to_port     = 6380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Redis (6379 native, 6380 docker)"
  }

  # MySQL (Docker)
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "MySQL (docker)"
  }

  # Prometheus
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Prometheus"
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Grafana"
  }

  # Node exporter
  ingress {
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "node_exporter"
  }

  # Postgres exporter
  ingress {
    from_port   = 9187
    to_port     = 9187
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "postgres_exporter"
  }

  # Internal: all traffic between lab nodes
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "All internal traffic"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.lab_name}-sg"
  }
}

# ---------------------------------------------------------------------------
# EC2 instances
# ---------------------------------------------------------------------------
resource "aws_instance" "node" {
  for_each = var.nodes

  ami                    = var.ami_id
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.lab.key_name
  vpc_security_group_ids = [aws_security_group.lab.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname ${each.value.hostname}
    echo "${each.value.hostname}" > /etc/hostname
  EOF

  tags = {
    Name = "${var.lab_name}-${each.value.hostname}"
    Lab  = var.lab_name
    Role = each.key
  }
}
