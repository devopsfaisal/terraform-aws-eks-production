# 🎓 Terraform AWS EKS Production Mastery Guide & Learning Path (English)

> 🌐 **Language Selector / مبدّل اللغات / भाषा चुनें**:  
> **[🇬🇧 English (Current)]** • [🇮🇳 Hinglish](LEARNING_PATH.hi.md) • [🇸🇦 العربية](LEARNING_PATH.ar.md)

> **Author**: [Faisal Ansari](https://faisal.host) • [LinkedIn](https://www.linkedin.com/in/clumsyfaisal/)  
> **Target Region**: AWS `ap-south-1` (Mumbai)  
> **Terraform Engine**: `>= 1.9.0` (Tested on `v1.16.3`)  
> **Kubernetes Version**: `1.36` (Latest Modern EKS Release)  
> **Design Pattern**: 100% "One-Go Apply" Compatible (Zero Manual Intervention)

---

## 📑 Table of Contents
1. [Terraform 101: Core Fundamentals & Lifecycle](#1-terraform-101-core-fundamentals--lifecycle)
2. [The "One-Go Apply" Engineering Architecture](#2-the-one-go-apply-engineering-architecture)
3. [Architecture Blueprint & Traffic Flow](#3-architecture-blueprint--traffic-flow)
4. [Module 1: Networking Layer (VPC & Subnets)](#4-module-1-networking-layer-vpc--subnets)
5. [Module 2: Identity & Security Layer (IAM & IRSA)](#5-module-2-identity--security-layer-iam--irsa)
6. [Module 3: Compute & Kubernetes Orchestration (EKS 1.36)](#6-module-3-compute--kubernetes-orchestration-eks-136)
7. [Module 4: GitOps CI/CD Pipeline & Quality Gates](#7-module-4-gitops-cicd-pipeline--quality-gates)
8. [Top 17 Real-World DevOps/SRE Interview Questions & Answers](#8-top-17-real-world-devopssre-interview-questions--answers)
9. [Hands-On Practice & Operational Commands](#9-hands-on-practice--operational-commands)
10. [Real-World Production Troubleshooting & War Stories (Case Studies)](#10-real-world-production-troubleshooting--war-stories-case-studies)

---

## 1. Terraform 101: Core Fundamentals & Lifecycle

For cloud engineers, platform architects, and developers, Infrastructure as Code (IaC) is the industry foundation for repeatable cloud management.

### What is Infrastructure as Code (IaC)?
Historically, cloud infrastructure was provisioned manually via the AWS Management Console ("ClickOps").  
**The Failure Modes of ClickOps**:
- High vulnerability to human error and misconfiguration.
- Absence of version control, audit trails, and review mechanisms.
- Configuration drift between Staging and Production environments.

**The Solution: Infrastructure as Code (IaC)**  
Terraform uses a declarative language (HashiCorp Configuration Language - HCL) where you define your target state. Terraform analyzes the delta between reality and configuration, generating an execution plan to converge them safely.

### Core Terraform Building Blocks

| Concept | Definition | Real-World Analogy |
| :--- | :--- | :--- |
| **Provider** (`providers.tf`) | Plugin translating Terraform actions into AWS API calls. | Device driver or API translation client. |
| **Resource** (`resource "aws_vpc"`) | Discrete infrastructure unit created in AWS. | Building block (e.g., room, wall, or foundation). |
| **Variable** (`variables.tf`) | Dynamic input parameters enabling environment parametrization. | Function arguments in application programming. |
| **Output** (`outputs.tf`) | Post-execution exported attributes (e.g., cluster endpoints, subnet IDs). | Function return values. |
| **Module** (`modules/vpc`) | Encapsulated, reusable package of related infrastructure components. | Reusable software library or class. |
| **State File** (`terraform.tfstate`) | The single source of truth mapping Terraform resources to real AWS IDs. | Architectural blueprint reflecting actual site construction. |

### The 5 Lifecycle Phases of Terraform

```text
 [1. terraform fmt]      ──► Enforces standardized HCL indentation & syntax
         │
         ▼
 [2. terraform init]     ──► Downloads provider plugins and initializes remote backend
         │
         ▼
 [3. terraform validate] ──► Verifies internal consistency and attribute types
         │
         ▼
 [4. terraform plan]     ──► Refreshes remote state and computes execution diff
         │
         ▼
 [5. terraform apply]    ──► Dispatches authenticated API calls to converge AWS state
```

---

## 2. The "One-Go Apply" Engineering Architecture

### The "Chicken-and-Egg" Problem in Kubernetes IaC
Many EKS Terraform repositories fail when run against an empty AWS account in a single `terraform apply`.  
**The Reason**: The Kubernetes (`hashicorp/kubernetes`) or Helm (`hashicorp/helm`) provider configuration often depends on cluster attributes (such as `cluster_endpoint` and `cluster_certificate_authority_data`) that do not exist until the cluster is provisioned. Terraform attempts to authenticate during the initial planning phase and fails.

### How This Project Achieves 100% "One-Go Apply":
1. **Native AWS Provider Resources**: We manage Kubernetes bootstrap add-ons (`vpc-cni`, `kube-proxy`, `coredns`) using `aws_eks_addon` instead of third-party Helm or Kubernetes providers.
2. **Explicit Dependency Graph**:
   ```hcl
   module "eks" {
     source = "./modules/eks"
     depends_on = [module.vpc, module.iam]
   }
   ```
3. **Dynamic Exec Authentication**: In `providers.tf`, Kubernetes providers authenticate dynamically using `aws eks get-token` via the AWS CLI exec plugin, preventing static token expiration during plan/apply execution.

---

## 3. Architecture Blueprint & Traffic Flow

```text
                                  Internet
                                     │
                           ┌─────────▼─────────┐
                           │  Internet Gateway │
                           └─────────┬─────────┘
                                     │
   ┌─────────────────────────────────┼────────────────────────────────────────────────────────┐
   │ VPC CIDR: 10.0.0.0/16           │                                      AWS ap-south-1    │
   │                                 │                                                        │
   │  ┌──────────────────────────────▼───────────┐                                            │
   │  │ Public Subnets (3 AZs: 1a, 1b, 1c)       │ ──► Public ALBs & NAT Gateways             │
   │  │ Tag: kubernetes.io/role/elb = 1          │                                            │
   │  └──────────────────────────────┬───────────┘                                            │
   │                                 │                                                        │
   │                        NAT Outbound Egress                                               │
   │                                 │                                                        │
   │  ┌──────────────────────────────▼───────────┐                                            │
   │  │ Private Subnets (3 AZs: 1a, 1b, 1c)      │                                            │
   │  │ Tag: kubernetes.io/role/internal-elb = 1 │                                            │
   │  │                                          │                                            │
   │  │   ┌───────────────────────────────────┐  │    ┌───────────────────────────────────┐   │
   │  │   │ EKS Managed Node Groups           │  │    │ Amazon EKS Control Plane          │   │
   │  │   │  - t3.medium Worker Nodes         │◄─┼───►│ (AWS Managed, Highly Available)   │   │
   │  │   │  - IMDSv2 Enforced                │  │    │  - CloudWatch Audit / API Logs    │   │
   │  │   │  - AWS SSM Agent (Zero SSH Port 22│  │    │  - KMS Secrets Envelope Encrypt   │   │
   │  │   │  - Microservices & Pod Workloads  │  │    └───────────────────────────────────┘   │
   │  │   └───────────────────────────────────┘  │                                            │
   │  └──────────────────────────────────────────┘                                            │
   └──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Module 1: Networking Layer (VPC & Subnets)

Located in `modules/vpc`:
- **CIDR Block**: `10.0.0.0/16` (providing 65,536 private IP addresses).
- **Multi-AZ Availability**: Spanned across `ap-south-1a`, `ap-south-1b`, and `ap-south-1c`.
- **Public Subnets** (`10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`):
  - Hosts the Internet Gateway, NAT Gateways, and public Application Load Balancers.
  - Tagged with `kubernetes.io/role/elb = 1` for AWS Load Balancer Controller automatic subnet discovery.
- **Private Subnets** (`10.0.11.0/24`, `10.0.12.0/24`, `10.0.13.0/24`):
  - Dedicated exclusively to Kubernetes worker nodes and pods.
  - Zero public IP allocation. All outbound internet egress is routed securely through the NAT Gateway.
  - Tagged with `kubernetes.io/role/internal-elb = 1` for internal microservice load balancers.
- **Cost vs. HA Optimization**:
  - `enable_ha_nat_gateway = false` (default): Deploys a single NAT Gateway in AZ 1a for lab/staging to reduce AWS NAT hourly costs.
  - Set `enable_ha_nat_gateway = true` in production for independent multi-AZ NAT resilience.

---

## 5. Module 2: Identity & Security Layer (IAM & IRSA)

Located in `modules/iam`:
- **Role Separation**: Dedicated, isolated IAM roles for the EKS Cluster control plane and the EKS Worker Nodes.
- **Node Hardening via AWS Systems Manager**:
  - The node role includes `AmazonSSMManagedInstanceCore`.
  - Engineers debug nodes securely via AWS Session Manager (IAM-authenticated and audited), eliminating the need for SSH keys or opening inbound Port 22.
- **IAM Roles for Service Accounts (IRSA)**:
  - Provisions an OpenID Connect (OIDC) identity provider.
  - Individual Kubernetes pods assume scoped AWS IAM roles via `AssumeRoleWithWebIdentity` using short-lived AWS STS tokens, eliminating dangerous EC2 instance profile shared credentials.

---

## 6. Module 3: Compute & Kubernetes Orchestration (EKS 1.36)

Located in `modules/eks`:
- **Control Plane**: Amazon EKS running modern Kubernetes **1.36**.
- **Observability**: CloudWatch log export enabled for `api`, `audit`, `authenticator`, `controllerManager`, and `scheduler`.
- **Secrets Envelope Encryption**: Kubernetes secrets stored in `etcd` are encrypted at rest using an AWS KMS Customer Managed Key (CMK).
- **Managed Node Groups**:
  - Compute: Scalable `t3.medium` instances running Amazon Linux.
  - Rolling Upgrades: `max_unavailable = 1` ensures zero-downtime cluster upgrades.
  - Anti-SSRF Protection: Launch template strictly enforces **IMDSv2** (`http_tokens = "required"` with `http_put_response_hop_limit = 2`).

---

## 7. Module 4: GitOps CI/CD Pipeline & Quality Gates

Our repository enforces automated GitOps review gates before any code touches AWS:

| Checkpoint | Workflow | Gate / Command | Purpose |
| :--- | :--- | :--- | :--- |
| **Checkpoint 1** | `terraform-ci.yml` | `terraform fmt -check -diff` | Enforces uniform code styling across all PRs |
| **Checkpoint 2** | `terraform-ci.yml` | Trivy IaC Scanner | Detects security misconfigurations and CVEs |
| **Checkpoint 3** | `terraform-ci.yml` | `terraform validate` & PR Summary | Verifies HCL schema and posts automated status comment |
| **Checkpoint 4** | `terraform-apply.yml` | Gated `workflow_dispatch` | Requires human confirmation (`APPLY`) before deploying |
| **Protected Teardown** | `terraform-destroy.yml`| Confirmation + Environment Gate | Requires `DESTROY-PRODUCTION` string and approval |

---

## 8. Top 17 Real-World DevOps/SRE Interview Questions & Answers

### Q1: Why should Kubernetes worker nodes be deployed exclusively in private subnets?
**Answer**: Worker nodes must never be exposed directly to the public internet. Running nodes in private subnets behind a NAT Gateway protects them from external network scans, brute force attacks, and zero-day ingress exploits.

### Q2: How does the AWS VPC CNI work, and why does it require a large VPC CIDR?
**Answer**: Unlike overlay networks (like Flannel or Calico VXLAN) that encapsulate packets, the AWS VPC CNI assigns native secondary private IPv4 addresses from the host's VPC subnet directly to pods. Pods communicate at native VPC wire speed without NAT overhead. However, because each pod consumes an actual VPC IP, clusters require generous VPC CIDRs (e.g., `/16`).

### Q3: What is IRSA, and why is it superior to EC2 Instance Profiles?
**Answer**: IAM Roles for Service Accounts (IRSA) uses an OIDC federated identity provider. Pods present a signed JSON Web Token (JWT) to AWS STS to assume dedicated, fine-grained IAM roles (`AssumeRoleWithWebIdentity`). Without IRSA, any pod running on a node inherits the full permissions of the node's instance profile, violating the Principle of Least Privilege.

### Q4: Why is IMDSv2 mandatory for Kubernetes worker nodes?
**Answer**: Instance Metadata Service Version 1 (IMDSv1) is vulnerable to Server-Side Request Forgery (SSRF) exploits where a compromised pod or ingress proxy could query `http://169.254.169.254/latest/meta-data/` to steal the node's IAM security credentials. IMDSv2 mandates a session-oriented `PUT` request with a security token, neutralizing SSRF credential exfiltration.

### Q5: What is the purpose of subnet tags `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb`?
**Answer**: The AWS Load Balancer Controller automatically queries AWS EC2 APIs for these specific tags. Tag `kubernetes.io/role/elb = 1` directs internet-facing ALBs to public subnets, while `kubernetes.io/role/internal-elb = 1` directs private ALBs to private subnets.

### Q6: How do you achieve zero-downtime rolling upgrades on EKS Managed Node Groups?
**Answer**: EKS uses the `update_config { max_unavailable = 1 }` strategy. AWS provisions a new node with the updated AMI/version, drains pods gracefully from the old node respecting Pod Disruption Budgets (PDB), waits for new pods to report Ready, and only then terminates the decommissioned node.

### Q7: What is KMS Envelope Encryption for EKS secrets?
**Answer**: By default, EKS encrypts worker node EBS volumes, but Kubernetes secrets stored in `etcd` require application-layer encryption. With KMS envelope encryption, AWS EKS generates a unique Data Encryption Key (DEK) to encrypt secrets in `etcd`, while the DEK itself is encrypted using an AWS KMS Customer Managed Key (CMK).

### Q8: Why should SSH Port 22 be disabled on production worker nodes?
**Answer**: Managing SSH key pairs introduces credential rotation overhead, risk of private key leakage, and requires opening Port 22 in security groups. Using AWS Systems Manager (SSM) Session Manager provides IAM-authenticated, browser-based or CLI-based shell access with full CloudTrail audit logging and zero open inbound ports.

### Q9: Why is `backend "s3"` coupled with DynamoDB mandatory in enterprise Terraform?
**Answer**: S3 provides encrypted, versioned remote storage so team members and CI/CD runners share identical state. DynamoDB provides distributed state locking via a `LockID` string attribute, preventing race conditions and state corruption when two engineers or CI pipelines run operations simultaneously.

### Q10: What is the difference between `capacity_type = "ON_DEMAND"` and `"SPOT"`?
**Answer**: On-Demand instances provide guaranteed capacity for stateful or critical workloads. Spot instances offer up to 90% cost savings by utilizing spare EC2 capacity, but can be reclaimed by AWS with a 2-minute interruption notice. Production architectures typically use On-Demand for core system services and Spot for stateless, auto-scaling worker nodes.

### Q11: How do you prevent Terraform from overriding Kubernetes Cluster Autoscaler modifications?
**Answer**: By applying the `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` meta-argument to `aws_eks_node_group`. This ensures Terraform provisions the baseline node count without fighting the Kubernetes Cluster Autoscaler or Karpenter when traffic scales horizontally.

### Q12: What is the difference between single NAT Gateway and multi-AZ NAT Gateways?
**Answer**: A single NAT Gateway routes traffic from all AZs through one availability zone, saving ~$64/month in AWS charges, but creates a single point of failure if that AZ experiences an outage. Multi-AZ NAT deploys an independent NAT Gateway in every AZ for full high-availability compliance.

### Q13: Why does `main.tf` specify `depends_on = [module.vpc, module.iam]`?
**Answer**: The EKS control plane API requires active VPC subnets, route tables, and fully propagated IAM roles before it can successfully provision. Without explicit dependencies, race conditions during initial apply can cause AWS API deployment failures.

### Q14: What is the technical difference between `terraform validate` and `terraform plan`?
**Answer**: `terraform validate` performs static analysis of syntax, argument names, and types locally without connecting to cloud APIs. `terraform plan` connects to the cloud provider, refreshes current infrastructure state, and calculates the exact execution delta.

### Q15: In what sequence does Terraform delete resources during a teardown?
**Answer**: Terraform executes reverse-dependency ordering: EKS Add-ons and Node Groups are deleted first, followed by the EKS Cluster control plane, KMS keys, IAM roles, NAT Gateways, Elastic IPs, Subnets, and finally the VPC.

### Q16: How do you share variables and step outcomes between separate GitHub Actions jobs?
**Answer**: The `steps` context in GitHub Actions is strictly isolated to its parent job. To pass data to downstream jobs, the producing job must expose explicit job-level `outputs` (`outputs: { fmt_outcome: ${{ steps.fmt.outcome }} }`). The consuming job declares `needs: [producer_job]` and accesses the value using `${{ needs.producer_job.outputs.fmt_outcome }}`.

### Q17: What occurs if `terraform apply` runs on an ephemeral CI runner without a remote backend?
**Answer**: When the runner VM terminates, the local `terraform.tfstate` is permanently lost. Cloud resources (EKS, VPC, NAT Gateway) remain running as "Ghost Infrastructure," generating ongoing hourly costs. Subsequent `terraform destroy` executions initialize an empty state and report "0 destroyed." Mitigation requires remote S3 state with DynamoDB locking, approval-gated CD triggers, and deterministic API-based teardown fallbacks.

---

## 9. Hands-On Practice & Operational Commands

### 1. Auto-Bootstrap State & Plan Locally
```bash
# Auto-bootstrap S3 state bucket & DynamoDB lock table (Zero manual setup)
chmod +x scripts/*.sh
./scripts/auto-bootstrap.sh

# Format code
terraform fmt -recursive

# Initialize modules & providers with remote S3 backend
terraform init

# Validate syntax
terraform validate

# Dry-run execution plan
terraform plan -out=tfplan
```

### 2. Deploy in One Go
```bash
terraform apply tfplan
```

### 3. Connect and Verify Cluster
```bash
# Update local kubectl configuration
aws eks update-kubeconfig --region ap-south-1 --name eks-production-cluster

# Check Kubernetes version and nodes
kubectl get nodes -o wide

# Check system pods running on nodes
kubectl get pods -n kube-system
```

### 4. Teardown / Total Wipeout
```bash
# Option A: Standard Terraform Destroy (Preserves S3 bucket & DynamoDB)
terraform destroy -auto-approve

# Option B: Guaranteed AWS Total Wipeout (Cleans EKS, VPC, IAM + S3 Bucket & DynamoDB)
./scripts/teardown.sh
```

---

## 10. Real-World Production Troubleshooting & War Stories (Case Studies)

### ⚠️ Case Study 1: GitHub Actions Cross-Job Context Scoping Bug

* **Error Observed**:
  ```text
  Context access might be invalid: fmt @[.github/workflows/terraform-ci.yml:L100]
  ```
* **Root Cause**:
  The CI workflow was split into 3 independent jobs: `code-quality`, `security-scan`, and `terraform-plan`. The PR status script in `terraform-plan` attempted to evaluate `${{ steps.fmt.outcome }}`. Because `steps` is scoped strictly to the current job, the reference evaluated to `null`.
* **Production Resolution**:
  1. Exposed job output on `code-quality`:
     ```yaml
     code-quality:
       outputs:
         fmt_outcome: ${{ steps.fmt.outcome }}
     ```
  2. Declared dependency on `terraform-plan`:
     ```yaml
     terraform-plan:
       needs: [code-quality, security-scan]
     ```
  3. Referenced via the `needs` context:
     ```yaml
     - 🖌 **Format**: `${{ needs.code-quality.outputs.fmt_outcome || 'Passed' }}`
     ```

---

### 🚨 Case Study 2: Ephemeral CI Runner & The "Ghost Cluster" Trap

* **Incident Scenario**:
  During automated merge deployments, `terraform apply` succeeded on a GitHub Actions runner. However, because `backend "s3"` was commented out, `terraform.tfstate` was stored on the runner's ephemeral disk and destroyed when the VM terminated.
* **The Business Impact**:
  When a teardown workflow was executed later, Terraform initialized a fresh empty state and reported `0 destroyed`. The AWS EKS cluster ($0.10/hr) and NAT Gateway ($0.045/hr) continued running unnoticed, accumulating unwarranted cloud costs.
* **Production Resolution**:
  1. **Strict CI Gating**: Production apply was restricted to manual `workflow_dispatch` with approval confirmation (`APPLY`).
  2. **Auto-Bootstrap Script (`scripts/auto-bootstrap.sh`)**: Integrated before `terraform init` to guarantee S3 and DynamoDB availability.
  3. **Total Wipeout Teardown Script (`scripts/teardown.sh`)**: Deterministically queries AWS APIs by project tags and deletes resources in reverse-dependency order, culminating in the permanent deletion of DynamoDB tables and versioned S3 state buckets.
