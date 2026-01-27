# Terraform - AWS | EKS Production Setup 🚀
Production-ready **AWS EKS cluster** built using **Terraform modules**, following AWS and DevOps best practices.

## Why I Built This
In most teams I’ve worked with, setting up EKS usually starts with good intentions but quickly turns messy.

Sometimes the cluster is created using the AWS console, sometimes with half-written Terraform code copied from different blogs. Networking decisions (VPC, subnets, NAT) are made without thinking about long-term scalability or security. IAM roles grow over time with overly permissive policies. CI/CD and observability are “future tasks” that never really get standardized.

The real problem isn’t creating an EKS cluster — it’s creating one that:

is repeatable

follows security best practices

can be understood by the next engineer

and is safe enough for production workloads

I built this project to solve that exact gap.

This repository is my attempt to create a clean, production-ready EKS baseline using Terraform — something I would personally be comfortable deploying in a real environment. The goal is not to cover every possible feature, but to provide a solid foundation that teams can extend confidently without re-architecting everything later.

## Architecture Overview
The architecture follows a modular and least-privilege design, keeping security, maintainability, and scalability in mind.

At a high level, the setup includes:

VPC with public and private subnets
Public subnets are used only for load balancers and NAT gateways. All EKS worker nodes run in private subnets, reducing direct exposure to the internet.

Amazon EKS control plane
The Kubernetes control plane is managed by AWS, which offloads etcd management, control plane patching, and high availability.

Managed Node Groups
Worker nodes are created using EKS managed node groups to simplify upgrades, scaling, and lifecycle management while still allowing flexibility in instance types and scaling policies.

IAM with least privilege
Separate IAM roles are defined for:

EKS cluster

Worker nodes
This avoids over-permissioned roles and keeps access boundaries clear and auditable.

Terraform modular structure
Networking, IAM, and EKS are split into independent modules. This makes the setup:

easier to understand

easier to test

easier to extend (IRSA, autoscaling, observability, etc.)

This architecture is intentionally simple but production-oriented. It’s designed to be a starting point that reflects how real teams operate, not just how tutorials demonstrate EKS.

## Terraform Design Decisions
- Modules
- Security
- Scalability

## 📂 Project Structure
```text
└── terraform-aws-eks-production
    ├── create-eks-terraform.sh
    ├── main.tf
    ├── modules
    │   ├── eks
    │   │   ├── main.tf
    │   │   ├── outputs.tf
    │   │   └── variables.tf
    │   ├── iam
    │   │   ├── main.tf
    │   │   ├── outputs.tf
    │   │   └── variables.tf
    │   └── vpc
    │       ├── main.tf
    │       ├── outputs.tf
    │       └── variables.tf
    ├── outputs.tf
    ├── providers.tf
    ├── README.md
    ├── terraform.tfvars.example
    ├── variables.tf
    └── versions.tf
```

## Key Best Practices
- Private subnets
- IAM
- State handling

## ✨ Features
- Modular Terraform architecture
- AWS VPC with public & private subnets
- EKS cluster with managed node groups
- IAM roles & policies (least privilege)
- Ready for CI/CD & GitOps
- Clean, scalable, and extensible

## How to Use This Repo
(terraform init/plan/apply)

## Who This Is For
(DevOps, SREs, Learners)

## GitHub Repository
👉 https://github.com/devopsfaisal/terraform-aws-eks-production




