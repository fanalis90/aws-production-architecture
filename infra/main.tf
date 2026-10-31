# Main infrastructure - composes all modules
# ponytail: single environment. Add workspaces/tfvars when multi-env needed.

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "aws-prod-arch-tfstate-382218653410"
    key            = "infra/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "aws-prod-arch-tflock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "project" {
  type    = string
  default = "aws-prod-arch"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "db_password" {
  type      = string
  sensitive = true
}

module "vpc" {
  source = "./modules/vpc"

  project     = var.project
  environment = var.environment
  region      = var.region
  vpc_cidr    = "10.0.0.0/16"
}

module "iam" {
  source = "./modules/iam"

  project     = var.project
  environment = var.environment
}

module "security" {
  source = "./modules/security"

  project = var.project
  vpc_id  = module.vpc.vpc_id
}

module "ecr" {
  source = "./modules/ecr"

  project = var.project
}

# --- Outputs ---
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "ecs_execution_role_arn" {
  value = module.iam.ecs_execution_role_arn
}

output "alb_sg_id" {
  value = module.security.alb_sg_id
}

output "ecs_sg_id" {
  value = module.security.ecs_sg_id
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

module "database" {
  source = "./modules/database"

  project            = var.project
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  ecs_sg_id          = module.security.ecs_sg_id
  db_password        = var.db_password
}

output "db_endpoint" {
  value     = module.database.db_endpoint
  sensitive = true
}

module "compute" {
  source = "./modules/compute"

  project                = var.project
  vpc_id                 = module.vpc.vpc_id
  public_subnet_ids      = module.vpc.public_subnet_ids
  private_subnet_ids     = module.vpc.private_subnet_ids
  alb_sg_id              = module.security.alb_sg_id
  ecs_sg_id              = module.security.ecs_sg_id
  ecs_execution_role_arn = module.iam.ecs_execution_role_arn
  ecs_task_role_arn      = module.iam.ecs_task_role_arn
  ecr_repository_url     = module.ecr.repository_url
}

output "alb_dns_name" {
  value = module.compute.alb_dns_name
}

module "monitoring" {
  source  = "./modules/monitoring"
  project = var.project
  region  = var.region
}


# ci-test
