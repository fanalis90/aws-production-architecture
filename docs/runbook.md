# Runbook — aws-production-architecture

Operational procedures for on-call engineers.

---

## Service Overview

| Component | Identifier |
|-----------|-----------|
| ECS Cluster | `aws-prod-arch-cluster` |
| ECS Service | `aws-prod-arch-service` |
| ALB | `aws-prod-arch-alb` |
| RDS | `aws-prod-arch-postgres` |
| CloudWatch Logs | `/ecs/aws-prod-arch` |
| SNS Alerts | `aws-prod-arch-alarms` → `fanalis90@gmail.com` |
| Region | `us-east-2` |

---

## Health Check

```bash
# ALB health
curl http://<alb-dns>/health
# Expected: {"status":"healthy","service":"aws-prod-arch-api","timestamp":"..."}

# ECS service status
aws ecs describe-services \
  --cluster aws-prod-arch-cluster \
  --services aws-prod-arch-service \
  --query 'services[0].{running:runningCount,desired:desiredCount,status:status}'

# RDS status
aws rds describe-db-instances \
  --db-instance-identifier aws-prod-arch-postgres \
  --query 'DBInstances[0].DBInstanceStatus'
```

---

## Incident Response

### 1. ALB 503 — No Healthy Targets

**Symptom**: All requests return 503  
**Cause**: ECS task crashed or health check failing

```bash
# Check ECS task count
aws ecs describe-services --cluster aws-prod-arch-cluster --services aws-prod-arch-service

# Check stopped tasks for failure reason
aws ecs list-tasks --cluster aws-prod-arch-cluster --desired-status STOPPED
aws ecs describe-tasks --cluster aws-prod-arch-cluster --tasks <task-arn>
# Look at: stoppedReason, containers[].reason

# Check logs
aws logs tail /ecs/aws-prod-arch --follow
```

**Fix**: Force new deployment
```bash
aws ecs update-service \
  --cluster aws-prod-arch-cluster \
  --service aws-prod-arch-service \
  --force-new-deployment
```

---

### 2. ECS Task Fails to Start (ECR Pull Error)

**Symptom**: Task stops with `CannotPullContainerError`  
**Cause**: ECS can't reach ECR (network/IAM issue)

```bash
# Verify execution role has ECR permissions
aws iam list-attached-role-policies --role-name aws-prod-arch-ecs-execution

# Verify image exists in ECR
aws ecr describe-images \
  --repository-name aws-prod-arch-api \
  --query 'imageDetails[*].{tag:imageTags,pushed:imagePushedAt}'
```

**Fix**: Re-push image
```bash
aws ecr get-login-password --region us-east-2 | \
  docker login --username AWS --password-stdin \
  382218653410.dkr.ecr.us-east-2.amazonaws.com

docker push 382218653410.dkr.ecr.us-east-2.amazonaws.com/aws-prod-arch-api:latest
```

---

### 3. RDS Connection Refused

**Symptom**: API returns 500, logs show PostgreSQL connection error  
**Cause**: RDS not running, wrong SG, wrong credentials

```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier aws-prod-arch-postgres \
  --query 'DBInstances[0].DBInstanceStatus'

# Verify ECS SG allowed in RDS SG
aws ec2 describe-security-groups --group-ids sg-0d1725f19bbb41ae4
```

---

### 4. GitHub Actions Failure

**Symptom**: Push to main doesn't deploy  
**Check**: https://github.com/fanalis90/aws-production-architecture/actions

Common causes:
- **Credentials expired** → rotate `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` in GitHub Environment secrets
- **Terraform state lock** → `aws dynamodb delete-item --table-name aws-prod-arch-tflock --key '{"LockID":{"S":"infra/terraform.tfstate"}}'`
- **ECR image too large** → check Docker build output

---

## Deploy Procedures

### Deploy Infrastructure
```bash
cd infra
terraform init
terraform apply -var="db_password=$DB_PASSWORD"
```

### Deploy Application
```bash
# Build and push
cd app
docker build -t 382218653410.dkr.ecr.us-east-2.amazonaws.com/aws-prod-arch-api:latest .
docker push 382218653410.dkr.ecr.us-east-2.amazonaws.com/aws-prod-arch-api:latest

# Trigger ECS rolling deploy
aws ecs update-service \
  --cluster aws-prod-arch-cluster \
  --service aws-prod-arch-service \
  --force-new-deployment
```

### Teardown (after demo session)
```bash
cd infra
# Always destroy in this order:
terraform destroy -target=module.compute -auto-approve
terraform destroy -target=module.database -auto-approve
# monitoring module (SNS) is free — leave it
```

---

## Useful Queries

```bash
# Tail app logs
aws logs tail /ecs/aws-prod-arch --follow --format short

# List recent ECS task stops with reasons
aws ecs list-tasks --cluster aws-prod-arch-cluster --desired-status STOPPED \
  --query 'taskArns' | xargs -I{} aws ecs describe-tasks \
  --cluster aws-prod-arch-cluster --tasks {} \
  --query 'tasks[*].{reason:stoppedReason,container:containers[0].reason}'

# Current Terraform state resources
aws s3 cp s3://aws-prod-arch-tfstate-382218653410/infra/terraform.tfstate - | python -m json.tool | grep '"type"'
```
