terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
  }

  # Production Best Practice: Uncomment after creating S3 bucket & DynamoDB table in ap-south-1
  # backend "s3" {
  #   bucket         = "devopsfaisal-terraform-eks-state"
  #   key            = "eks/production/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "devopsfaisal-terraform-eks-locks"
  # }
}
