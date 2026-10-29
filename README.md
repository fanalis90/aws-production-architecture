# AWS Production Architecture

Production-grade AWS infrastructure built with Terraform modules. Demonstrates Cloud Engineer competency: networking, IAM, containers, CI/CD, and monitoring.

## Architecture

```
Internet → ALB (public subnets) → ECS Fargate (private subnets) → RDS PostgreSQL (private subnets)
```

- **Region**: us-east-2 (Ohio)
- **High Availability**: 2 AZs (us-east-2a, us-east-2b)
- **IaC**: Terraform with modular structure and S3 remote state

## Tech Stack

| Layer | Service |
|-------|---------|
| Networking | VPC, 4 subnets (2 public + 2 private), IGW |
| Compute | ECS Fargate (coming) |
| Database | RDS PostgreSQL (coming) |
| Container Registry | ECR |
| Load Balancer | ALB (coming) |
| CI/CD | GitHub Actions (coming) |
| Monitoring | CloudWatch + SNS (coming) |
| IaC | Terraform with S3 backend + DynamoDB lock |

## Project Structure

```
infra/
├── main.tf                 # Root module
├── backend-setup/          # S3 + DynamoDB for remote state
└── modules/
    ├── vpc/                # Multi-AZ VPC networking
    ├── iam/                # ECS task execution + task roles
    ├── security/           # ALB + ECS security groups
    ├── ecr/                # Docker image registry
    ├── compute/            # ALB + ECS Fargate (coming)
    ├── database/           # RDS PostgreSQL (coming)
    └── monitoring/         # CloudWatch alarms (coming)
app/                        # .NET 8 API (coming)
.github/workflows/          # CI/CD pipelines (coming)
```

## Cost

Designed for AWS Free Tier. Current monthly cost: **$0.00**

## Author

Senior .NET/Azure developer transitioning to AWS Cloud Engineering. 5 years experience with .NET, Azure, Kubernetes.
