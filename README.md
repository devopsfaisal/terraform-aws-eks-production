# Terraform - AWS | EKS Production Setup 🚀

[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D%201.9.0-623CE4?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-ap--south--1-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-1.36-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![GitOps](https://img.shields.io/badge/GitOps-GitHub%20Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![Portfolio](https://img.shields.io/badge/Portfolio-faisal.host-00B4D8?style=for-the-badge&logo=google-chrome&logoColor=white)](https://faisal.host)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-clumsyfaisal-0077B5?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/clumsyfaisal/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=for-the-badge)](LICENSE)

Production-ready, enterprise-grade **AWS EKS Cluster** built using **Terraform modular architecture**, deployed to **AWS `ap-south-1` (Mumbai)** following CIS Benchmark, AWS Well-Architected Framework, and automated **GitOps CI/CD validation pipelines**.

---

## 📖 Table of Contents
- [Why I Built This](#why-i-built-this)
- [Architecture Overview](#architecture-overview)
- [Terraform Design Decisions](#terraform-design-decisions)
- [📂 Project Structure](#-project-structure)
- [Key Best Practices](#key-best-practices)
- [GitOps CI/CD Pipeline Checkpoints](#gitops-cicd-pipeline-checkpoints)
- [How to Use This Repo](#how-to-use-this-repo)
- [🎓 Learning Path & Interview Prep](#-learning-path--interview-prep)
- [Who This Is For](#who-this-is-for)
- [👨‍💻 Author & Connect](#-author--connect)

---

## Why I Built This
In most teams I’ve worked with, setting up EKS usually starts with good intentions but quickly turns messy.

Sometimes the cluster is created using the AWS console, sometimes with half-written Terraform code copied from different blogs. Networking decisions (VPC, subnets, NAT) are made without thinking about long-term scalability or security. IAM roles grow over time with overly permissive policies. CI/CD and observability are “future tasks” that never really get standardized.

The real problem isn’t creating an EKS cluster — it’s creating one that:
- ✅ Is **repeatable and idempotent** across environments.
- 🛡 Follows **strict security best practices** (zero direct node internet exposure, IMDSv2, KMS envelope encryption).
- 🧩 Can be **easily understood and maintained** by the next engineer.
- 🚀 Is **safe enough for mission-critical production workloads**.

I built this project to solve that exact gap: a battle-tested baseline that engineering teams can extend confidently without re-architecting everything later.

---

## Architecture Overview
The architecture follows a modular and least-privilege design:

```
                            Internet
                               │
                      ┌────────▼────────┐
                      │ Internet Gateway│
                      └────────┬────────┘
                               │
  ┌────────────────────────────┼────────────────────────────────────────────────────────┐
  │ VPC: 10.0.0.0/16           │                                      AWS ap-south-1    │
  │                            │                                                        │
  │  ┌─────────────────────────▼───────────┐                                            │
  │  │ Public Subnets (3 AZs)              │ ──> Public ALBs & NAT Gateways             │
  │  │ Tag: kubernetes.io/role/elb = 1     │                                            │
  │  └─────────────────────────┬───────────┘                                            │
  │                            │                                                        │
  │                   NAT Outbound Internet                                             │
  │                            │                                                        │
  │  ┌─────────────────────────▼───────────┐                                            │
  │  │ Private Subnets (3 AZs)             │                                            │
  │  │ Tag: kubernetes.io/role/internal = 1│                                            │
  │  │                                     │                                            │
  │  │   ┌──────────────────────────────┐  │    ┌───────────────────────────────────┐   │
  │  │   │ EKS Managed Node Groups      │  │    │ Amazon EKS Control Plane          │   │
  │  │   │  - t3.medium Instances       │◄─┼───►│ (AWS Managed, Highly Available)   │   │
  │  │   │  - IMDSv2 Enforced           │  │    │  - Full Audit / API Logs          │   │
  │  │   │  - AWS SSM Access (No SSH)   │  │    │  - KMS Secrets Envelope Encrypt   │   │
  │  │   │  - Microservices & Pods      │  │    └───────────────────────────────────┘   │
  │  │   └──────────────────────────────┘  │                                            │
  │  └─────────────────────────────────────┘                                            │
  └─────────────────────────────────────────────────────────────────────────────────────┘
```

1. **VPC with Public and Private Subnets across 3 AZs**:
   - Public subnets host only the Internet Gateway, external Load Balancers, and NAT Gateways.
   - All EKS worker nodes run inside isolated private subnets.
2. **Amazon EKS Control Plane**:
   - Managed by AWS, high availability etcd, control plane log streams enabled (`api`, `audit`, `authenticator`, etc.).
3. **Managed Node Groups**:
   - Zero-downtime rolling upgrades (`max_unavailable = 1`).
   - Launch templates enforcing IMDSv2 metadata tokens and AWS Systems Manager (SSM) agent support.
4. **Least-Privilege IAM & IRSA**:
   - Separate IAM roles for cluster control plane and worker nodes.
   - OpenID Connect (OIDC) identity provider enabled for pod-level IAM roles (IRSA).

---

## Terraform Design Decisions
- **Strict Modularity**: Networking (`modules/vpc`), Security (`modules/iam`), and Compute (`modules/eks`) are separated into self-contained modules.
- **Dynamic Cost vs. HA NAT Toggle**: Switch between single NAT (`enable_ha_nat_gateway = false`) for dev/lab cost savings, and 3 AZ multi-NAT (`enable_ha_nat_gateway = true`) for production resilience.
- **Provider Authentication via AWS Exec**: `providers.tf` configures the Kubernetes and Helm providers using `aws eks get-token` exec plugin to prevent expired auth tokens in state files.
- **Autoscaler Preservation**: Node group lifecycle ignores changes to `desired_size` so Cluster Autoscaler or Karpenter actions are not overwritten on subsequent Terraform runs.

---

## 📂 Project Structure
```text
└── terraform-aws-eks-production
    ├── .github
    │   └── workflows
    │       ├── terraform-ci.yml        # Checkpoint 1-3: Fmt, Trivy scan, validate & PR plan
    │       ├── terraform-apply.yml     # Checkpoint 4: Gated Production Apply (Manual dispatch)
    │       └── terraform-destroy.yml   # Protected Manual Teardown (Confirmation & approval gated)
    ├── bootstrap
    │   └── main.tf                     # S3 bucket + DynamoDB remote state storage bootstrapper
    ├── docs
    │   ├── LEARNING_PATH.md            # English guide (Global & Recruiter Standard)
    │   ├── LEARNING_PATH.hi.md         # Hinglish guide (Conversational learning)
    │   └── LEARNING_PATH.ar.md         # Arabic guide (الدليل الشامل باللغة العربية)
    ├── modules
    │   ├── eks                         # EKS 1.36, KMS, SGs, OIDC, Node Groups, Add-ons
    │   │   ├── main.tf
    │   │   ├── outputs.tf
    │   │   └── variables.tf
    │   ├── iam                         # Control Plane & Node least-privilege IAM roles
    │   │   ├── main.tf
    │   │   ├── outputs.tf
    │   │   └── variables.tf
    │   └── vpc                         # 3-AZ VPC, subnets, IGW, NAT Gateways, routing
    │       ├── main.tf
    │       ├── outputs.tf
    │       └── variables.tf
    ├── scripts
    │   ├── auto-bootstrap.sh           # Auto-creates S3 state bucket & DynamoDB lock table
    │   └── teardown.sh                 # Guaranteed reverse-dependency AWS resource cleanup & Total Wipeout
    ├── .gitignore
    ├── main.tf                         # Root composition module
    ├── outputs.tf                      # Cluster endpoint, kubeconfig command, SG IDs
    ├── providers.tf                    # AWS (ap-south-1), Kubernetes & Helm providers
    ├── README.md                       # Documentation & architecture summary
    ├── terraform.tfvars.example        # Production example configurations with comments
    ├── variables.tf                    # Root inputs with type constraints & validations
    └── versions.tf                     # Pinned Terraform >= 1.9 and provider versions
```

---

## Key Best Practices
- 🔒 **Private Subnet Isolation**: No public IPs on worker nodes.
- 🛡 **IMDSv2 Enforced**: Launch template blocks SSRF attacks and credential exfiltration.
- 🔑 **KMS Envelope Encryption**: Kubernetes secrets stored in `etcd` are encrypted at rest with AWS KMS Customer Managed Keys.
- 📊 **Auditing & Compliance**: All 5 EKS control plane log types exported to CloudWatch.
- 🔐 **SSM Session Manager**: Zero open SSH port 22; node management authenticated via IAM.
- 🏷 **Kubernetes Discovery Tagging**: Subnets tagged with `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` for automated Ingress routing.

---

## GitOps CI/CD Pipeline Checkpoints
Our repository enforces a multi-gate GitOps review process before any code touches AWS:

| Checkpoint | Gate | Tool / Command | Purpose |
| :--- | :--- | :--- | :--- |
| **Checkpoint 1** | Code Quality | `terraform fmt -check -diff` | Enforces uniform HCL styling |
| **Checkpoint 2** | DevSecOps Scan | Trivy IaC Scanner | Detects misconfigurations & CVEs |
| **Checkpoint 3** | Validation & Plan | `terraform validate` & PR plan | Validates provider schema & comments diff on PR |
| **Checkpoint 4** | Production Apply | Gated `workflow_dispatch` | Human-approved deployment with confirmation check |
| **Protected Teardown** | Safe Teardown | `terraform-destroy.yml` | Requires string `DESTROY-PRODUCTION` + environment approval |

---

## How to Use This Repo

### 1. Prerequisites
- **AWS CLI v2** configured (`aws configure` with credentials in region `ap-south-1`).
- **Terraform `>= 1.9.0`** (or OpenTofu).
- **kubectl** installed.

### 2. Quickstart
```bash
# 1. Clone the repository
git clone https://github.com/devopsfaisal/terraform-aws-eks-production.git
cd terraform-aws-eks-production

# 2. Prepare variables
cp terraform.tfvars.example terraform.tfvars

# 3. Auto-bootstrap state backend (S3 & DynamoDB) & initialize
chmod +x scripts/*.sh
./scripts/auto-bootstrap.sh
terraform fmt -recursive
terraform init

# 4. Review the deployment plan
terraform plan -out=tfplan

# 5. Provision the cluster
terraform apply tfplan
```

### 3. Connect to Your New Cluster
After `terraform apply` finishes, run the output command:
```bash
aws eks update-kubeconfig --region ap-south-1 --name eks-production-cluster

# Verify nodes are Ready
kubectl get nodes -o wide
```

### 4. Cleanup / Total Wipeout
```bash
# Option A: Standard Terraform Destroy (Preserves S3 bucket & DynamoDB)
terraform destroy -auto-approve

# Option B: Complete Total Wipeout (Destroys EKS, VPC, IAM + S3 & DynamoDB)
./scripts/teardown.sh
```

---

## 🎓 Learning Path & Interview Prep (Trilingual / متعدد اللغات)
Looking to understand the architectural "why", networking mechanics, or prepare for DevOps/SRE interviews? Choose your preferred language:

| Language | Guide Link | Focus & Target Audience |
| :--- | :--- | :--- |
| 🇬🇧 **English** | **[docs/LEARNING_PATH.md](docs/LEARNING_PATH.md)** | Global & Recruiter Standard, Enterprise Technical English |
| 🇮🇳 **Hinglish** | **[docs/LEARNING_PATH.hi.md](docs/LEARNING_PATH.hi.md)** | Hindi in Roman Script, Conversational & Step-by-Step Learning |
| 🇸🇦 **العربية (Arabic)** | **[docs/LEARNING_PATH.ar.md](docs/LEARNING_PATH.ar.md)** | الدليل المعماري الشامل باللغة العربية الفصحى لمجتمع مهندسي السحابة في الخليج والشرق الأوسط |

Each guide includes:
- Deep-dive into VPC CNI secondary IP mechanics & IMDSv2 anti-SSRF defense.
- Pod IAM credential flow using OIDC and AWS STS (`AssumeRoleWithWebIdentity`).
- **Top 17 Real-World DevOps / SRE Interview Questions & Detailed Answers**.
- **Section 10: Real-World Production War Stories & Case Studies** (Cross-job scoping bugs, orphaned state traps, and auto-bootstrap solutions).

---

## Who This Is For
- **DevOps Engineers & SREs**: Ready-to-adapt production baseline for real workloads.
- **Platform Architects**: Reusable, compliant Terraform blueprint for AWS EKS.
- **Cloud Practitioners & Learners**: Complete pedagogical journey covering modern GitOps, Terraform 1.16+, and Kubernetes security.

---

## 👨‍💻 Author & Connect
Architected and crafted with ❤️ by **Faisal Ansari**.

- 🌐 **Portfolio**: [https://faisal.host](https://faisal.host)
- 💼 **LinkedIn**: [linkedin.com/in/clumsyfaisal](https://www.linkedin.com/in/clumsyfaisal/)
