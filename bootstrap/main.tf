# ==============================================================================
# Terraform Backend Bootstrap (S3 Bucket + DynamoDB State Locking)
# Region: ap-south-1 (Mumbai)
# ==============================================================================
# Run this once to provision your remote state storage and state lock table.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "eks-production-state-backend"
      ManagedBy = "Terraform"
    }
  }
}

variable "aws_region" {
  description = "AWS region for the remote backend."
  type        = string
  default     = "ap-south-1"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for storing terraform.tfstate."
  type        = string
  default     = "devopsfaisal-terraform-eks-state"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name used for state locking."
  type        = string
  default     = "devopsfaisal-terraform-eks-locks"
}

# 1. S3 Bucket for Terraform State Storage
resource "aws_s3_bucket" "state_bucket" {
  bucket        = var.bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning so you can restore previous states if corrupted
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-Side Encryption (SSE-S3 / AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access to state files (security best practice)
resource "aws_s3_bucket_public_access_block" "state_public_block" {
  bucket = aws_s3_bucket.state_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. DynamoDB Table for Distributed State Locking
# Crucial: Primary key MUST be named 'LockID' with type String (S) for Terraform to acquire locks
resource "aws_dynamodb_table" "state_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # Cost-effective: Zero cost when no terraform commands are running
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = var.dynamodb_table_name
  }
}

output "s3_bucket_name" {
  description = "S3 bucket name to put in versions.tf backend block."
  value       = aws_s3_bucket.state_bucket.id
}

output "dynamodb_table_name" {
  description = "DynamoDB table name to put in versions.tf backend block."
  value       = aws_dynamodb_table.state_locks.id
}
