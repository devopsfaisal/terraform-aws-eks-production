#!/bin/bash
set -e

echo "📁 Initializing Terraform AWS EKS project structure..."

# Root files (README.md is intentionally NOT touched)
touch versions.tf providers.tf variables.tf outputs.tf main.tf terraform.tfvars.example .gitignore

# Directories
mkdir -p modules/{vpc,eks,iam}
mkdir -p .github/workflows

# Module files
touch modules/vpc/{main.tf,variables.tf,outputs.tf}
touch modules/eks/{main.tf,variables.tf,outputs.tf}
touch modules/iam/{main.tf,variables.tf,outputs.tf}

echo "✅ Terraform project structure initialized successfully!"
