```hcl
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ClientName       = "Alithya"
      MaintainersTeam  = "IO"
      ManagedBy        = "Terraform"
      Environment      = var.environment
    }
  }
}

# Variables with real organization values
variable "aws_region" {
  description = "AWS region for resource deployment - organization home region"
  type        = string
  default     = "ca-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID - use Endpoint VPC (10.7.0.0/22) for workload resources"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for RDS and EC2 placement - must be Data tier subnets"
  type        = list(string)
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ami_id" {
  description = "AMI ID for EC2 instance - leave empty to use latest Amazon Linux 2023"
  type        = string
  default     = ""
}

# Data sources for existing infrastructure
data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Tier = "Data"
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# KMS key for encryption (SCP requires encryption for all resources)
resource "aws_kms_key" "main" {
  description             = "KMS key for encrypting EC2, S3, and RDS resources"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.environment}-main-kms-key"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.environment}-main-key"
  target_key_id = aws_kms_key.main.key_id
}

# S3 Bucket - SCP enforces encryption and public access block
resource "aws_s3_bucket" "app_data" {
  bucket = "${var.environment}-alithya-app-data-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.environment}-app-data-bucket"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket encryption - MANDATORY per SCP
resource "aws_s3_bucket_server_side_encryption_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

# S3 bucket versioning for data protection
resource "aws_s3_bucket_versioning" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 public access block - MANDATORY per SCP
resource "aws_s3_bucket_public_access_block" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy to enforce HTTPS - MANDATORY per SCP
resource "aws_s3_bucket_policy" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.app_data.arn,
          "${aws_s3_bucket.app_data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# S3 lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }
  }
}

# EC2 Security Group
resource "aws_security_group" "ec2_app" {
  name_prefix = "${var.environment}-ec2-app-"
  description = "Security group for application EC2 instances"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-ec2-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for EC2 instance with SSM access
resource "aws_iam_role" "ec2_app" {
  name_prefix = "${var.environment}-ec2-app-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-ec2-app-role"
  }
}

# Attach SSM managed policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "ec2_s3_access" {
  name_prefix = "${var.environment}-ec2-s3-"
  role        = aws_iam_role.ec2_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app_data.arn,
          "${aws_s3_bucket.app_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_app" {
  name_prefix = "${var.environment}-ec2-app-"
  role        = aws_iam_role.ec2_app.name

  tags = {
    Name = "${var.environment}-ec2-app-profile"
  }
}

# EC2 Instance with encrypted EBS and IMDSv2 enforced
resource "aws_instance" "app" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_app.name

  # IMDSv2 enforcement - MANDATORY per Config rule
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Encrypted root volume - MANDATORY per SCP
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true

    tags = {
      Name = "${var.environment}-app-root-volume"
    }
  }

  # Additional encrypted data volume
  ebs_block_device {
    device_name           = "/dev/sdf"
    volume_type           = "gp3"
    volume_size           = 100
    encrypted             = true
    kms_key_id            = aws_kms_key.main.arn
    delete_on_termination = true

    tags = {
      Name = "${var.environment}-app-data-volume"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    s3_bucket = aws_s3_bucket.app_data.id
    region    = var.aws_region
  }))

  tags = {
    Name = "${var.environment}-app-server"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# RDS Security Group - only accessible from EC2 app tier
resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-rds-"
  description = "Security group for RDS database - Data tier only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from application servers"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_app.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Subnet Group - must use Data tier subnets only
resource "aws_db_subnet_group" "main" {
  name_prefix = "${var.environment}-rds-"
  subnet_ids  = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : data.aws_subnets.private.ids
  description = "Subnet group for RDS in Data tier"

  tags = {
    Name = "${var.environment}-rds-subnet-group"
  }
}

# RDS Parameter Group for PostgreSQL optimization
resource "aws_db_parameter_group" "postgres" {
  name_prefix = "${var.environment}-postgres15-"
  family      = "postgres15"
  description = "Custom parameter group for PostgreSQL 15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${var.environment}-postgres-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Generate random password for RDS
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Store RDS password in Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  name_prefix             = "${var.environment}-rds-password-"
  description             = "RDS database master password"
  recovery_window_in_days = 30
  kms_key_id              = aws_kms_key.main.id

  tags = {
    Name = "${var.environment}-rds-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
  })
}

# RDS PostgreSQL Instance - encrypted storage MANDATORY per SCP
resource "aws_db_instance" "main" {
  identifier_prefix = "${var.environment}-postgres-"
  
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = "db.t3.medium"
  allocated_storage    = 100
  max_allocated_storage = 500
  storage_type         = "gp3"
  storage_encrypted    = true
  kms_key_id           = aws_kms_key.main.arn

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  # IAM database authentication enabled per organization best practice
  iam_database_authentication_enabled = true

  # Never publicly accessible - must remain in Data tier
  publicly_accessible = false

  # Backup configuration
  backup_retention_period   = 7
  backup_window             = "03:00-04:00"
  maintenance_window        = "mon:04:00-mon:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.environment}-postgres-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Enhanced monitoring
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.rds_monitoring.arn

  # Performance Insights with encryption
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.main.arn
  performance_insights_retention_period = 7

  # Deletion protection for production
  deletion_protection = var.environment == "prod" ? true : false

  # Auto minor version upgrade
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.environment}-postgres-db"
  }

  lifecycle {
    ignore_changes = [password]
  }
}

# IAM role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name_prefix = "${var.environment}-rds-monitoring-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Outputs
output "s3_bucket_id" {
  description = "S3 bucket ID"
  value       = aws_s3_bucket.app_data.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.app_data.arn
}

output "ec2_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "ec2_instance_private_ip" {
  description = "EC2 instance private IP address"
  value       = aws_instance.app.private_ip
}

output "ec2_instance_profile_arn" {
  description = "EC2 IAM instance profile ARN"
  value       = aws_iam_instance_profile.ec2_app.arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "RDS instance address"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.main.db_name
}

output "rds_secret_arn" {
  description = "ARN of Secrets Manager secret containing RDS credentials"
  value       = aws_secretsmanager_secret.db_password.arn
}

output "kms_key_id" {
  description = "KMS key ID used for encryption"
  value       = aws_kms_key.main.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  value       = aws_kms_key.main.arn
}

output "ec2_security_group_id" {
  description = "EC2 security group ID"
  value       = aws_security_group.ec2_app.id
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}
```