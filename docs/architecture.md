# Architecture Document

## Overview

Production-grade AWS infrastructure hosting a .NET 8 REST API. Designed for Cloud/DevOps portfolio demonstration — shows end-to-end ownership from IaC to CI/CD to monitoring.

**Region**: `us-east-2` (Ohio) — forced by AWS Organization SCP  
**Account**: `382218653410`  
**GitHub**: https://github.com/fanalis90/aws-production-architecture

---

## Network Design

```
VPC: 10.0.0.0/16
├── Public Subnets
│   ├── 10.0.1.0/24 (us-east-2a) — ALB, ECS tasks
│   └── 10.0.2.0/24 (us-east-2b) — ALB, ECS tasks
└── Private Subnets
    ├── 10.0.3.0/24 (us-east-2a) — RDS
    └── 10.0.4.0/24 (us-east-2b) — RDS
```

**Why ECS in public subnets?**  
Private subnets require NAT Gateway (~\$32/mo) or VPC endpoints for ECR access. Public subnet + `assign_public_ip=true` eliminates this cost for portfolio use. RDS stays in private subnets — only ECS SG can reach port 5432.

**Upgrade path**: Add ECR + S3 VPC endpoints, move ECS to private subnets, set `assign_public_ip=false`.

---

## Security Model

| Resource | Allowed inbound | Allowed outbound |
|----------|----------------|-----------------|
| ALB SG | 0.0.0.0/0 port 80 | ECS SG port 8080 |
| ECS SG | ALB SG port 8080 | 0.0.0.0/0 (ECR pull) |
| RDS SG | ECS SG port 5432 | 0.0.0.0/0 |

**IAM — least privilege:**
- `ecs-execution` role: only `AmazonECSTaskExecutionRolePolicy` (pull ECR, write CloudWatch logs)
- `ecs-task` role: empty by default — add app-specific permissions (S3, etc.) as needed

---

## Data Flow

```
Internet
  → ALB (port 80, public subnet)
    → Target Group (port 8080, health check /health)
      → ECS Fargate task (.NET 8 API, port 8080)
        → RDS PostgreSQL (port 5432, private subnet)
```

---

## Terraform Module Structure

### `vpc` module
- Creates VPC, 2 public + 2 private subnets across 2 AZs
- Internet Gateway + public route table
- No NAT Gateway (cost decision — see above)

### `iam` module
- ECS execution role (ECR pull + CloudWatch logs)
- ECS task role (application permissions — empty, extend per app)

### `security` module
- ALB security group (internet → ALB)
- ECS security group (ALB → ECS only)

### `ecr` module
- Private ECR repository
- `scan_on_push = true` — vulnerability scanning on every image push

### `compute` module
- ALB with HTTP listener (port 80) → target group (port 8080)
- ECS cluster (Fargate)
- ECS service (desired=1, rolling deploy)
- ECS task definition (0.25 vCPU / 0.5GB RAM — smallest Fargate size)
- CloudWatch log group (7-day retention)

### `database` module
- RDS PostgreSQL 16, `db.t3.micro`, 20GB gp2
- Storage encrypted (KMS)
- Private subnets only, `publicly_accessible=false`
- `skip_final_snapshot=true` (portfolio — set false for prod)
- DB subnet group spans both AZs (AWS requirement even for single-AZ)

### `monitoring` module
- SNS topic `aws-prod-arch-alarms`
- Email subscription (confirmed)
- CloudWatch alarms (conditional — only created when ECS/RDS running):
  - ECS CPU > 80% for 10min
  - ECS Memory > 80% for 10min
  - RDS connections > 80 for 10min

---

## CI/CD Pipeline

### Infrastructure Pipeline (`deploy-infra.yml`)
```
PR opened → terraform fmt check → validate → plan (comment on PR)
Merged to main → terraform apply
```

### Application Pipeline (`deploy-app.yml`)
```
Push to main (app/ changes) → docker build → ECR push → ecs update-service
```

**Secrets** stored in GitHub Environment `AWS`:
- `AWS_ACCESS_KEY_ID` — IAM user `cli-admin`
- `AWS_SECRET_ACCESS_KEY`
- `DB_PASSWORD`

---

## Cost Breakdown

### Always-on (between sessions): **\$0.00/month**
VPC, IGW, subnets, IAM roles, SGs, ECR repo, S3 tfstate, DynamoDB lock, SNS topic — all free.

### Demo session costs (destroy after):
| Service | Rate | 1hr session |
|---------|------|-------------|
| ALB | \$0.022/hr | ~\$0.022 |
| ECS Fargate (0.25vCPU/0.5GB) | ~\$0.009/hr | ~\$0.009 |
| RDS db.t3.micro | Free tier | \$0.00 |
| **Total per session** | | **~\$0.03** |

---

## Technology Choices vs Azure Equivalents

| AWS | Azure | Notes |
|-----|-------|-------|
| ECS Fargate | Azure Container Apps / AKS | Simpler than K8s for single service |
| ALB | Azure Application Gateway / Load Balancer | Layer 7 routing |
| RDS PostgreSQL | Azure Database for PostgreSQL | Managed, same concept |
| ECR | Azure Container Registry | Private container registry |
| CloudWatch | Azure Monitor + Log Analytics | Logs + metrics + alarms |
| SNS | Azure Service Bus / Event Grid | Pub/sub notifications |
| IAM | Azure AD + RBAC | Identity and access management |
| Terraform | Terraform (same) | Multi-cloud IaC |
| GitHub Actions | GitHub Actions (same) | CI/CD |
