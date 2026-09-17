# 🎓 Terraform AWS EKS Production Mastery Guide & Learning Path

> **Author**: DevOps Faisal  
> **Target Region**: AWS `ap-south-1` (Mumbai)  
> **Terraform Engine**: `>= 1.9.0` (Tested on `v1.16.3`)  
> **Kubernetes Version**: `1.36` (Latest Modern EKS Release)  
> **Design Pattern**: 100% "One-Go Apply" Compatible (Zero Manual Intervention)

---

## 📑 Table of Contents
1. [Terraform 101: Scratch Se Samajhte Hain (Beginners Foundation)](#1-terraform-101-scratch-se-samajhte-hain-beginners-foundation)
2. [The "One-Go Apply" Engineering Architecture](#2-the-one-go-apply-engineering-architecture)
3. [Architecture Blueprint & Traffic Flow](#3-architecture-blueprint--traffic-flow)
4. [Module 1: Networking Layer (VPC & Subnets)](#4-module-1-networking-layer-vpc--subnets)
5. [Module 2: Identity & Security Layer (IAM & IRSA)](#5-module-2-identity--security-layer-iam--irsa)
6. [Module 3: Compute & Kubernetes Orchestration (EKS 1.36)](#6-module-3-compute--kubernetes-orchestration-eks-136)
7. [Module 4: GitOps CI/CD Pipeline & Checkpoints](#7-module-4-gitops-cicd-pipeline--checkpoints)
8. [Top 15 Real-World DevOps/SRE Interview Questions & Answers](#8-top-15-real-world-devopssre-interview-questions--answers)
9. [Hands-On Practice & Verification Commands](#9-hands-on-practice--verification-commands)

---

## 1. Terraform 101: Scratch Se Samajhte Hain (Beginners Foundation)

Agar aap ya koi learner Terraform bilkul pehli baar sikh raha hai, toh yeh section foundation banayega:

### IaC (Infrastructure as Code) Kya Hai?
Pehle cloud engineers AWS Console par ja kar buttons click karke VPC, EC2, ya EKS banate the (ClickOps).  
**Problems with ClickOps**:
- Galti hone ke chances (human error) bohot zyada hote hain.
- Koi documentation ya history nahi hoti ki kisne kya change kiya.
- Staging aur Production me configuration drift ho jata hai.

**Solution: Infrastructure as Code (IaC)**  
Terraform ek declarative code file (`.tf`) ke zariye describe karta hai ki aapko kya chahiye. Terraform automatically AWS API ko call karke resources create, update, ya destroy karta hai.

### Core Terraform Building Blocks

| Concept | Kya Hota Hai? | Real-Life Analogy |
| :--- | :--- | :--- |
| **Provider** (`providers.tf`) | Terraform ka plugin jo kisi specific cloud (AWS, Azure, GCP) ke API se baat karta hai. | Translator / Driver jo Terraform ko AWS ki language sikhata hai. |
| **Resource** (`resource "aws_vpc" "main"`) | Jo actual cheez aap cloud me banana chahte hain (e.g., VPC, Subnet, EKS Cluster). | Ghar ka kamra ya deewar jo aap banwa rahe hain. |
| **Variable** (`variables.tf`) | Dynamic input parameters taaki code hardcoded na ho. | Function arguments jo har environment (dev, prod) ke hisab se change ho sakein. |
| **Output** (`outputs.tf`) | Resource banne ke baad uski zaroori information display karna (e.g. Cluster endpoint, Subnet IDs). | Function ka return value. |
| **Module** (`modules/vpc`, etc.) | Related resources ka folder jisko ek unit ki tarah reuse kiya ja sake. | Programming me ek Class ya Reusable Library. |
| **State File** (`terraform.tfstate`) | Terraform ka "Brain". Yeh record rakhta hai ki cloud me abhi kaunse resources exist karte hain aur unki IDs kya hain. | Blueprint jisme mark hota hai ki zameen par kya ban chuka hai. |

### The 5 Golden Terraform Commands (Lifecycle)

```
 [1. terraform fmt]      ──► Code formatting standardise karta hai
         │
         ▼
 [2. terraform init]     ──► Plugins (AWS, TLS) aur modules download karta hai
         │
         ▼
 [3. terraform validate] ──► HCL syntax aur types check karta hai (bina AWS call kiye)
         │
         ▼
 [4. terraform plan]     ──► Dry-run preview: Batata hai kya ADD (+), CHANGE (~), ya DESTROY (-) hoga
         │
         ▼
 [5. terraform apply]    ──► Actually AWS par ja kar infrastructure bana deta hai
         │
         ▼
 [6. terraform destroy]  ──► Saare resources ko safely delete karta hai taaki bill na aaye
```

---

## 2. The "One-Go Apply" Engineering Architecture

Industry me bohot saare EKS Terraform projects do-teen baar fail hone ke baad bante hain (half-baked dependencies ki wajah se). Humne is project ko aise engineer kiya hai ki **pehli hi baar me (`terraform apply`) bina kisi error ke 100% succeed ho**.

### Humne "One-Go Apply" kaise guarantee kiya?

1. **IAM Policy Eventual Consistency Fix**:
   - *Problem*: AWS IAM globally distributed hota hai. Jab aap IAM role banate hain, toh policy attach hone me 3-5 seconds lag sakte hain. Agar EKS turant banne lage, toh AWS error deta hai: `The provided role cannot be assumed by EKS`.
   - *Fix*: Humne `modules/iam/outputs.tf` me `depends_on` use karke policy attachments ko output ke sath bind kiya hai. Isse EKS module tab tak shuru hi nahi hota jab tak policy attachments complete na ho jayein.

2. **Add-on Conflict Auto-Resolution**:
   - *Problem*: EKS Cluster banne ke sath AWS automatically default `vpc-cni`, `kube-proxy`, aur `coredns` install kar deta hai. Jab Terraform baad me unhe manage karne jata hai, toh fail hota hai: `AddonAlreadyExistsException`.
   - *Fix*: Humne har add-on par yeh parameters add kiye hain:
     ```hcl
     resolve_conflicts_on_create = "OVERWRITE"
     resolve_conflicts_on_update = "OVERWRITE"
     ```
   - Terraform bina kisi complaint ke unhe seamlessly adopt kar leta hai.

3. **CoreDNS Node Scheduling Dependency**:
   - *Problem*: CoreDNS tab tak `Running` state me nahi aa sakta jab tak cluster me kam se kam 1 Worker Node `Ready` na ho. Agar CoreDNS pehle ban jaye, toh apply timeout ho jata hai.
   - *Fix*: `aws_eks_addon.coredns` ke andar `depends_on = [aws_eks_node_group.nodes]` set kiya hai. Pehle EC2 worker nodes aate hain, fir CoreDNS smoothly start hota hai.

---

## 3. Architecture Blueprint & Traffic Flow

```
                                  Internet
                                     │
                           ┌─────────▼─────────┐
                           │ Internet Gateway  │
                           └─────────┬─────────┘
                                     │
  ┌──────────────────────────────────┼────────────────────────────────────────────────────────┐
  │ VPC: 10.0.0.0/16                 │                                      AWS ap-south-1    │
  │                                  │                                                        │
  │  ┌───────────────────────────────▼────────────────┐                                       │
  │  │ Public Subnets (10.0.1.0/24, 10.0.2.0/24, etc) │ ──> Public ALBs & NAT Gateways        │
  │  │ Tag: kubernetes.io/role/elb = 1                │                                       │
  │  └───────────────────────────────┬────────────────┘                                       │
  │                                  │                                                        │
  │                         NAT Gateway Outbound                                              │
  │                                  │                                                        │
  │  ┌───────────────────────────────▼────────────────┐                                       │
  │  │ Private Subnets (10.0.11.0/24, etc.)           │                                       │
  │  │ Tag: kubernetes.io/role/internal-elb = 1      │                                       │
  │  │                                                │                                       │
  │  │   ┌─────────────────────────────────────────┐  │    ┌──────────────────────────────┐   │
  │  │   │ EKS Managed Node Groups (v1.36)         │  │    │ EKS Control Plane (v1.36)    │   │
  │  │   │  - t3.medium Worker Instances           │◄─┼───►│ (AWS Managed, Multi-AZ)      │   │
  │  │   │  - IMDSv2 Enforced (Anti-SSRF)          │  │    │ - Audit / API CloudWatch Logs│   │
  │  │   │  - AWS SSM Agent (No SSH Keys Needed)   │  │    │ - KMS Secrets Encryption     │   │
  │  │   │  - Microservices & Pods                 │  │    └──────────────────────────────┘   │
  │  │   └─────────────────────────────────────────┘  │                                       │
  │  └────────────────────────────────────────────────┘                                       │
  └───────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Module 1: Networking Layer (VPC & Subnets)

### Subnets Design
- **3 Availability Zones**: `ap-south-1a`, `ap-south-1b`, `ap-south-1c` in Mumbai.
- **Public Subnets**: Internet Gateway se connected. Yahan sirf Load Balancers aur NAT Gateways rehte hain.
- **Private Subnets**: Inka internet se direct connection nahi hota. Worker nodes yahan safe rehte hain.

### Subnet Tags Ka Raaz (The "Why")
Kubernetes me jab aap Ingress ya Service of type `LoadBalancer` banate hain, toh AWS Load Balancer Controller kaise pehchanta hai ki kis subnet me ALB banana hai?
- `kubernetes.io/role/elb = "1"`: Controller ko batata hai ki yeh **Public Subnet** hai, external traffic ke liye ALB yahan banao.
- `kubernetes.io/role/internal-elb = "1"`: Batata hai ki yeh **Private Subnet** hai, internal microservices ke load balancer yahan banao.
- `karpenter.sh/discovery = var.cluster_name`: Karpenter autoscaler ko subnet auto-discover karne me help karta hai.

### Cost vs High-Availability (NAT Gateway)
- **Single NAT (`enable_ha_nat_gateway = false`)**:
  - Lab aur development ke liye best. Ek single NAT Gateway saare private subnets ko internet deta hai.
  - **Bachat**: Har mahine lagbhag ₹5,000 to ₹6,000 ($65-$70) ki bachat hoti hai.
- **Multi-AZ NAT (`enable_ha_nat_gateway = true`)**:
  - Strict Production ke liye: Har AZ me alag NAT Gateway hota hai taaki agar ek datacenter fail ho jaye toh baaki AZs chalti rahein.

---

## 5. Module 2: Identity & Security Layer (IAM & IRSA)

### Anti-Pattern: EC2 Instance Profile God-Roles
Agar hum node ke EC2 role me S3 ya DynamoDB ki permissions de dein, toh us node par chalne wala **har ek container pod** us S3 bucket ko read/write/delete kar sakega. Yeh bohot bada security risk hai.

### Right Pattern: IRSA (IAM Roles for Service Accounts)
Humne EKS me OIDC (OpenID Connect) provider enable kiya hai:
1. Pod ke liye Kubernetes `ServiceAccount` banta hai.
2. AWS IAM me role banta hai jo sirf us specific ServiceAccount ko assume karne ki permission deta hai (`AssumeRoleWithWebIdentity`).
3. Pod ko temporary STS credentials milte hain jo 1 ghante me expire ho jaate hain.

### SSM Session Manager: Goodbye SSH Keys!
Humne node role me `AmazonSSMManagedInstanceCore` add kiya hai.
- **Benefit**: Kisi bhi node ke andar login karne ke liye Port 22 open karne ya `.pem` key file download karne ki zaroorat nahi hai.
- AWS Console ya AWS CLI se directly secure, encrypted shell mil jata hai:
  ```bash
  aws ssm start-session --target <instance-id>
  ```

---

## 6. Module 3: Compute & Kubernetes Orchestration (EKS 1.36)

### IMDSv2 Security (SSRF Protection)
Launch Template me:
```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required" # IMDSv2 Mandatory
  http_put_response_hop_limit = 2          # Prevents Container Escape
}
```
- **IMDSv1 Vulnerability**: Agar kisi web app me SSRF bug tha, toh attacker `http://169.254.169.254/latest/meta-data/` par request bhej kar AWS keys chura leta tha.
- **IMDSv2 Protection**: Bina pehle `HTTP PUT` request bhej kar session token liye metadata nahi padha ja sakta.

### KMS Envelope Encryption
Kubernetes secrets by default `etcd` database me base64 encoded hote hain (jo plain text hi hota hai).
Humne AWS KMS Customer Managed Key create karke EKS ko de diya hai. Ab koi secret `etcd` me likhne se pehle hardware-backed KMS key se encrypt hota hai.

---

## 7. Module 4: GitOps CI/CD Pipeline & Checkpoints

Humne `.github/workflows` me pure GitOps workflow ko 4 clear checkpoints me divide kiya hai:

```
[Developer Git Push / PR]
          │
          ▼
[Checkpoint 1: Code Formatting] ──────► terraform fmt -check -diff -recursive
          │
          ▼
[Checkpoint 2: DevSecOps Scan] ───────► Trivy IaC Security Scan (catches security flaws)
          │
          ▼
[Checkpoint 3: Validation & Plan] ────► terraform init -backend=false
          │                             terraform validate
          │                             (Automated PR Summary Comment)
          ▼
[Human Review & PR Merge]
          │
          ▼
[Checkpoint 4: CD Production Apply] ──► terraform apply -auto-approve
                                        (Auto-exports kubectl connect command)
```

---

## 7. State Locking & DynamoDB Deep Dive (Multi-Developer Collaboration)

### Multiple Developers Ka Problem (Race Condition)
Maan lijiye aap aur aapke team member (Developer B) ek hi project par kaam kar rahe hain.
- **Scenario**: Developer A ne `terraform apply` dabaya VPC change karne ke liye.
- Theek usi second Developer B ne `terraform apply` dabaya ek naya Node Group add karne ke liye.
- **Consequence**: Dono ek hi `terraform.tfstate` file ko ek sath update karne lagenge. Isse state file corrupt ho jayegi, cloud resources orphaned ho jayenge aur disaster ho sakta hai.

### Solution: AWS S3 + DynamoDB State Locking

```
    Developer A                             Developer B
  [terraform apply]                       [terraform apply]
         │                                       │
         ▼                                       ▼
 1. Acquires Lock In DynamoDB             2. Tries to Acquire Lock
    (LockID = "eks/production/tfstate")     (DynamoDB checks: Lock already exists!)
         │                                       │
         ▼                                       ▼
 3. Status: 🔒 LOCKED                     4. ❌ BLOCKED!
    Terraform modifies AWS EKS               "Error: Error acquiring state lock:
         │                                    ConditionalCheckFailedException"
         ▼                                   (Protects state from corruption!)
 5. Releases Lock from DynamoDB
```

#### DynamoDB me Lock kaise store hota hai?
Terraform DynamoDB table me ek record insert karta hai:
- **Partition Key (`LockID`)**: `devopsfaisal-terraform-eks-state/eks/production/terraform.tfstate-md5`
- **Info Attribute (JSON)**:
  ```json
  {
    "ID": "b1a2c3d4-...",
    "Operation": "OperationTypeApply",
    "Info": "",
    "Who": "deadpool@macbook-pro.local",
    "Version": "1.16.3",
    "Created": "2026-09-17T13:00:00Z",
    "Path": "devopsfaisal-terraform-eks-state/eks/production/terraform.tfstate"
  }
  ```

#### Agar CI/CD Pipeline beech me crash ho jaye aur lock fasa reh jaye?
Kabhi-kabhi power cut ya GitHub Actions timeout ki wajah se lock DynamoDB me reh jata hai. Us case me Terraform error deta hai:
`Error: Error acquiring the state lock. Lock Info: ID: b1a2c3d4-...`
Isse unlock karne ke liye standard command hai:
```bash
terraform force-unlock b1a2c3d4-...
```

---

## 8. Human Approval Gates in CI/CD (Pooch Kar Apply Aur Destroy Karna)

Production me **automated apply** ya **accidental destroy** hona sabse bada dar hota hai. Humne isko 2 solid security layers se fix kiya hai:

### Layer 1: GitHub Environment Protection (Enterprise Approval)
Aapke repository me:
1. GitHub repo par jayiye: **Settings ➔ Environments ➔ New Environment (`production`)**.
2. **"Required reviewers"** checkmark enable kijiye aur apna GitHub username add kar lijiye.
3. Ab jab bhi koi code `main` branch me merge hoga ya workflow chalega:
   - Pipeline Checkpoint 1, 2, 3 pass karegi.
   - Par `terraform-apply` step par aate hi pipeline **PAUSE** ho jayegi (Yellow status).
   - Aapke email par notification aayega: *"devopsfaisal requested your review to deploy to production"*.
   - Jab tak aap GitHub Actions UI par ja kar **"Approve and deploy"** par click nahi karenge, ek bhi resource AWS par create ya change nahi hoga!

### Layer 2: Confirmation Word Gating (Zero-Accident Destroy)
Destroy ke liye humne automated trigger ko completely disable kar diya hai.
- File: `.github/workflows/terraform-destroy.yml`
- Yeh sirf **manual trigger (`workflow_dispatch`)** se hi chal sakta hai.
- Isme ek text box aayega jisme aapko exact word type karna hoga:
  `DESTROY-PRODUCTION`
- Agar koi galti se enter press kar de ya galat word type kare, toh script pehle hi step me fail ho jayegi aur AWS ko touch tak nahi karegi.

---

## 9. Top 15 Real-World DevOps/SRE Interview Questions & Answers

### Q1: Kubernetes worker nodes ko private subnet me kyu rakha jata hai?
**Answer**: Security isolation ke liye. Agar nodes public subnet me honge toh direct internet access aur cyber attacks ke risk badh jaate hain. Private subnet me nodes safe rehte hain, inbound traffic sirf monitored Application Load Balancer (ALB) ke through aata hai aur outbound traffic NAT Gateway ke through jata hai.

### Q2: Subnet me `kubernetes.io/role/elb = 1` tag nahi lagaya toh kya hoga?
**Answer**: AWS Load Balancer Controller public subnets ko discover nahi kar payega. Jab aap Ingress resource apply karenge, toh load balancer provision timeout error dega: `could not find any subnets with tag kubernetes.io/role/elb`.

### Q3: AWS VPC CNI kya karta hai aur use `AmazonEKS_CNI_Policy` kyu chahiye?
**Answer**: VPC CNI plugin pods ko virtual overlay IP ke bajaye direct VPC subnet ki native IP address deta hai. Is policy ke bina node AWS EC2 API call karke extra Elastic Network Interfaces (ENIs) aur secondary IPs allocate nahi kar sakta.

### Q4: IMDSv1 vs IMDSv2 me kya farq hai aur hop limit 2 kyu rakhte hain?
**Answer**: IMDSv1 me simple GET request se instance metadata aur IAM keys padhi ja sakti thi (SSRF attack prone). IMDSv2 me pehle session token lena padta hai PUT call se. Hop limit 2 isliye rakha jata hai taaki container pod ke andar se legitimate metadata calls ho sakein par external attackers proxy ke zariye access na kar sakein.

### Q5: EKS Cluster Security Group aur Node Security Group me kya farq hai?
**Answer**:
- **Cluster SG**: EKS managed control plane (API server port 443) ko protect karta hai.
- **Node SG**: Worker nodes ke beech inter-pod communication, kubelet (port 10250), aur outbound internet access ko govern karta hai.

### Q6: IRSA kya hai aur yeh Node instance role se better kyu hai?
**Answer**: IRSA (IAM Roles for Service Accounts) OIDC aur STS ke zariye pod-level par fine-grained permissions deta hai. Agar ek pod ko S3 access chahiye, toh sirf us pod ke ServiceAccount ko access milega, na ki pure EC2 worker node ko.

### Q7: Terraform state locking DynamoDB se kyu zaroori hai?
**Answer**: Agar do engineers ya do CI/CD pipeline runs ek sath `terraform apply` trigger kar dein, toh state file corrupt ho sakti hai (race condition). DynamoDB lock acquire karta hai jisse ek waqt me sirf ek hi execution chal sake.

### Q8: Node group me `ignore_changes = [scaling_config[0].desired_size]` ka kya fayda hai?
**Answer**: Production me Cluster Autoscaler ya Karpenter pods ke load ke hisab se nodes scale up/down karte hain. Agar `ignore_changes` nahi lagayenge, toh har baar jab aap `terraform apply` karenge, woh autoscaled nodes ko reset karke hardcoded initial count par le aayega, jisse production outage aa sakti hai.

### Q9: AWS KMS Envelope Encryption EKS me kya karta hai?
**Answer**: Kubernetes me `Secret` resource by default base64 encoded hota hai jo `etcd` me unencrypted rehta hai. KMS envelope encryption data key se secrets ko encrypt karta hai `etcd` me likhne se pehle, jo PCI-DSS aur CIS compliance requirement hai.

### Q10: SSH ke bajaye AWS SSM Session Manager use karne ka kya faayda hai?
**Answer**: Port 22 open nahi karna padta, bastion host ka kharcha bachta hai, `.pem` keys ka leak hone ka khatra khatam ho jata hai, aur har session AWS CloudTrail me audit ke liye log hota hai.

### Q11: EKS worker nodes ka zero-downtime rolling upgrade kaise hota hai?
**Answer**: `update_config { max_unavailable = 1 }` ke sath. EKS ek waqt me sirf ek node ko cordon aur drain karta hai, uske pods ko doosre nodes par shift karta hai, old node terminate karta hai, aur new version ka node spin up karta hai.

### Q12: Provider version ko `~> 5.60` aur Terraform ko `>= 1.9.0` pin karne ka reason kya hai?
**Answer**: Predictability aur stability. Agar major version pin nahi hoga, toh future breaking changes automated CI/CD pipeline ko break kar sakte hain. Tilde (`~>`) allow karta hai patch aur bugfix updates bina breaking changes ke.

### Q13: `main.tf` me `depends_on = [module.vpc, module.iam]` kyu lagaya hai?
**Answer**: EKS control plane ko start hone ke liye subnets aur IAM roles completely active aur propagated chahiye hote hain. Agar yeh pehle nahi bane honge toh EKS deployment API error throw karke fail ho jayegi.

### Q14: `terraform validate` aur `terraform plan` me technical difference kya hai?
**Answer**: `terraform validate` sirf code ki syntax, configuration validity aur internal consistency check karta hai bina cloud se connect kiye. `terraform plan` actual cloud provider se current state fetch karke execution diff generate karta hai.

### Q15: Pure setup ko destroy karte waqt resources kis order me delete hote hain?
**Answer**: Terraform reverse dependency order follow karta hai: Pehle EKS Add-ons aur Node Groups delete hote hain, fir EKS Cluster aur KMS keys, fir IAM roles, NAT Gateways, EIPs, Subnets, aur last me VPC delete hota hai.

---

## 9. Hands-On Practice & Verification Commands

### 1. Locally Check and Plan
```bash
# Format code
terraform fmt -recursive

# Initialize modules & providers
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

### 4. Teardown / Cleanup
```bash
terraform destroy -auto-approve
```
