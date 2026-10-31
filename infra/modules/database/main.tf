# RDS PostgreSQL module — private subnets, free tier eligible
# ponytail: single-AZ, no Multi-AZ. Enable multi_az=true when budget allows (~$26/mo extra).

variable "project" { type = string }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "ecs_sg_id" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "db_username" {
  type    = string
  default = "appuser"
}
variable "db_name" {
  type    = string
  default = "appdb"
}

# DB subnet group — RDS must span 2 AZs even if single-AZ instance
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = { Name = "${var.project}-db-subnet-group" }
}

# Security group — allow 5432 from ECS only
resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Allow PostgreSQL from ECS only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.ecs_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-rds-sg" }
}

# RDS PostgreSQL — free tier: db.t3.micro, 20GB gp2, 750hrs/mo
resource "aws_db_instance" "main" {
  identifier        = "${var.project}-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  skip_final_snapshot = true  # ponytail: set false + final_snapshot_identifier in prod
  deletion_protection = false # ponytail: set true in prod

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  tags = { Name = "${var.project}-postgres" }
}

output "db_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = true
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "rds_sg_id" {
  value = aws_security_group.rds.id
}

