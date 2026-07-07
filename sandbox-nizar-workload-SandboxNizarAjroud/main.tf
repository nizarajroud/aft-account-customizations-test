# Complete AWS Landing Zone Terraform Configuration
# This configuration deploys a secure, multi-tier architecture with EC2, S3, and RDS

# ============================================================================
# versions.tf - Provider and Terraform version constraints
# ============================================================================

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

  # Backend configuration for state management
  # Uncomment and configure for production use
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "landing-zone/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      CostCenter  = var.cost_center
    }
  }
}

# ============================================================================
# variables.tf - Input variables with sensible defaults
# ============================================================================

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = "engineering"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t3.medium"
}

variable "ec2_ami_id" {
  description = "AMI ID for EC2 instances (Amazon Linux 2023 recommended)"
  type        = string
  # Default to latest Amazon Linux 2023 - should be overridden with specific AMI
  default = ""
}

variable "rds_engine" {
  description = "RDS Aurora engine (aurora-postgresql or aurora-mysql)"
  type        = string
  default     = "aurora-postgresql"
  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.rds_engine)
    error_message = "RDS engine must be aurora-postgresql or aurora-mysql."
  }
}

variable "rds_engine_version" {
  description = "RDS Aurora engine version"
  type        = string
  default     = "15.4" # PostgreSQL 15.4
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "rds_master_username" {
  description = "Master username for RDS cluster"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "rds_backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  validation {
    condition     = var.rds_backup_retention_days >= 7
    error_message = "Backup retention must be at least 7 days."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}

variable "s3_lifecycle_glacier_days" {
  description = "Days before transitioning S3 objects to Glacier"
  type        = number
  default     = 90
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to bastion hosts"
  type        = list(string)
  default     = [] # Empty by default - must be explicitly set
}

# ============================================================================
# NETWORKING - VPC Module
# ============================================================================

# Deploy VPC with standard subnet tiers (Web, App, Data, Mgmt)
# This creates a secure network foundation with proper segmentation
module "vpc" {
  source  = "organization/vpc/aws"
  version = "~> 5.0"

  cidr_block   = var.vpc_cidr_block
  environment  = var.environment
  project_name = var.project_name

  # Enable VPC Flow Logs for audit compliance
  enable_flow_logs           = true
  flow_logs_retention_days   = var.environment == "prod" ? 90 : 30
  flow_logs_traffic_type     = "ALL"

  # Enable DNS support for private hosted zones
  enable_dns_hostnames = true
  enable_dns_support   = true

  # NAT Gateway configuration - use single NAT for dev, multi-AZ for prod
  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod"

  # Network segmentation using NACLs between tiers
  enable_network_acls = true

  tags = {
    Compliance = "SOC2"
  }
}

# ============================================================================
# SECURITY GROUPS
# ============================================================================

# Security group for application tier EC2 instances
# Allows traffic only from web tier and management access from bastion
resource "aws_security_group" "app_tier" {
  name_prefix = "${var.project_name}-${var.environment}-app-"
  description = "Security group for application tier EC2 instances"
  vpc_id      = module.vpc.vpc_id

  # Allow inbound from web tier on application port
  ingress {
    description     = "Application traffic from web tier"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web_tier.id]
  }

  # Allow SSH from management tier only
  ingress {
    description     = "SSH from management tier"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.mgmt_tier.id]
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-sg"
    Tier = "Application"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for web tier (ALB or web servers)
resource "aws_security_group" "web_tier" {
  name_prefix = "${var.project_name}-${var.environment}-web-"
  description = "Security group for web tier load balancers"
  vpc_id      = module.vpc.vpc_id

  # Allow HTTPS from internet
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP (redirect to HTTPS)
  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-web-sg"
    Tier = "Web"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for management tier (bastion hosts)
resource "aws_security_group" "mgmt_tier" {
  name_prefix = "${var.project_name}-${var.environment}-mgmt-"
  description = "Security group for management tier bastion hosts"
  vpc_id      = module.vpc.vpc_id

  # Allow SSH from approved CIDR blocks only
  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidr_blocks) > 0 ? [1] : []
    content {
      description = "SSH from approved networks"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidr_blocks
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-mgmt-sg"
    Tier = "Management"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for RDS Aurora cluster
resource "aws_security_group" "database" {
  name_prefix = "${var.project_name}-${var.environment}-db-"
  description = "Security group for RDS Aurora cluster"
  vpc_id      = module.vpc.vpc_id

  # Allow PostgreSQL/MySQL from application tier only
  ingress {
    description     = "Database access from application tier"
    from_port       = var.rds_engine == "aurora-postgresql" ? 5432 : 3306
    to_port         = var.rds_engine == "aurora-postgresql" ? 5432 : 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app_tier.id]
  }

  # No outbound rules needed for database
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-db-sg"
    Tier = "Data"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM role for EC2 instances with SSM access (no SSH keys needed)
resource "aws_iam_role" "ec2_instance_role" {
  name_prefix = "${var.project_name}-${var.environment}-ec2-"
  description = "IAM role for EC2 instances with SSM and CloudWatch access"

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
    Name = "${var.project_name}-${var.environment}-ec2-role"
  }
}

# Attach AWS managed policy for SSM access (secure shell alternative)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach AWS managed policy for CloudWatch agent
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for S3 access (least privilege)
resource "aws_iam_role_policy" "ec2_s3_access" {
  name_prefix = "s3-access-"
  role        = aws_iam_role.ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${module.app_data_bucket.bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          module.app_data_bucket.bucket_arn
        ]
      }
    ]
  })
}

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${var.project_name}-${var.environment}-ec2-"
  role        = aws_iam_role.ec2_instance_role.name

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-profile"
  }
}

# ============================================================================
# EC2 INSTANCES
# ============================================================================

# Data source to get latest Amazon Linux 2023 AMI if not specified
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

# Launch template for application tier EC2 instances
# Uses IMDSv2 for enhanced security
resource "aws_launch_template" "app_tier" {
  name_prefix   = "${var.project_name}-${var.environment}-app-"
  description   = "Launch template for application tier EC2 instances"
  image_id      = var.ec2_ami_id != "" ? var.ec2_ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type = var.ec2_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  vpc_security_group_ids = [aws_security_group.app_tier.id]

  # Enable detailed monitoring for production
  monitoring {
    enabled = var.environment == "prod"
  }

  # Enforce IMDSv2 for enhanced security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Enable EBS encryption by default
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 50
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
      iops                  = 3000
      throughput            = 125
    }
  }

  # User data script for initial configuration
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment  = var.environment
    project_name = var.project_name
    region       = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.environment}-app-instance"
      Tier = "Application"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-${var.environment}-app-volume"
      Tier = "Application"
    }
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-lt"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group for application tier
# Provides high availability and automatic scaling
resource "aws_autoscaling_group" "app_tier" {
  name_prefix         = "${var.project_name}-${var.environment}-app-"
  vpc_zone_identifier = module.vpc.app_subnet_ids
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.environment == "prod" ? 2 : 1
  max_size         = var.environment == "prod" ? 6 : 2
  desired_capacity = var.environment == "prod" ? 2 : 1

  launch_template {
    id      = aws_launch_template.app_tier.id
    version = "$Latest"
  }

  # Enable instance refresh for zero-downtime updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-app-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Tier"
    value               = "Application"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# Auto Scaling Policy - Target Tracking based on CPU
resource "aws_autoscaling_policy" "app_tier_cpu" {
  name                   = "${var.project_name}-${var.environment}-app-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.app_tier.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# ============================================================================
# APPLICATION LOAD BALANCER
# ============================================================================

# Application Load Balancer for web tier
# Terminates SSL and distributes traffic to application instances
resource "aws_lb" "web" {
  name_prefix        = substr("${var.environment}-", 0, 6)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_tier.id]
  subnets            = module.vpc.web_subnet_ids

  # Enable deletion protection for production
  enable_deletion_protection = var.enable_deletion_protection && var.environment == "prod"

  # Enable access logs to S3
  access_logs {
    bucket  = module.alb_logs_bucket.bucket_id
    prefix  = "alb-logs"
    enabled = true
  }

  # Drop invalid headers for security
  drop_invalid_header_fields = true

  tags = {
    Name = "${var.project_name}-${var.environment}-web-alb"
    Tier = "Web"
  }
}

# Target group for application instances
resource "aws_lb_target_group" "app" {
  name_prefix = substr("${var.environment}-", 0, 6)
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  # Deregistration delay for graceful shutdown
  deregistration_delay = 30

  # Enable stickiness for stateful applications
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-app-tg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS listener (requires ACM certificate)
# Note: You must create an ACM certificate and update the certificate_arn
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# HTTP listener - redirects to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Placeholder ACM certificate (replace with actual certificate request)
resource "aws_acm_certificate" "main" {
  domain_name       = "${var.environment}.${var.project_name}.example.com"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.environment}.${var.project_name}.example.com"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cert"
  }
}

# ============================================================================
# S3 BUCKETS
# ============================================================================

# Application data bucket using organization module
# Stores application data with versioning and lifecycle policies
module "app_data_bucket" {
  source  = "organization/s3-bucket/aws"
  version = "~> 4.0"

  bucket_name = "${var.project_name}-${var.environment}-app-data-${data.aws_caller_identity.current.account_id}"
  environment = var.environment

  # Enable versioning for data protection
  enable_versioning = true

  # Lifecycle rules to optimize storage costs
  lifecycle_rules = [
    {
      id      = "transition-to-glacier"
      enabled = true
      transition = [
        {
          days          = var.s3_lifecycle_glacier_days
          storage_class = "GLACIER"
        }
      ]
    },
    {
      id      = "expire-old-versions"
      enabled = true
      noncurrent_version_expiration = {
        days = 90
      }
    }
  ]

  # Block all public access
  block_public_access = true

  # Enable server-side encryption with AWS managed keys
  enable_encryption = true
  kms_key_id        = aws_kms_key.s3.arn

  # Enable access logging
  enable_access_logging = true
  access_log_bucket     = module.audit_logs_bucket.bucket_id
  access_log_prefix     = "app-data-access-logs/"

  tags = {
    DataClassification = "Confidential"
    Compliance         = "SOC2"
  }
}

# ALB access logs bucket
module "alb_logs_bucket" {
  source  = "organization/s3-bucket/aws"
  version = "~> 4.0"

  bucket_name = "${var.project_name}-${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"
  environment = var.environment

  # Versioning not needed for logs
  enable_versioning = false

  # Lifecycle rules for log retention
  lifecycle_rules = [
    {
      id      = "expire-old-logs"
      enabled = true
      expiration = {
        days = var.environment == "prod" ? 90 : 30
      }
    }
  ]

  block_public_access = true
  enable_encryption   = true
  kms_key_id          = aws_kms_key.s3.arn

  # Allow ALB to write logs
  bucket_policy = data.aws_iam_policy_document.alb_logs.json

  tags = {
    DataClassification = "Internal"
    LogType            = "ALB"
  }
}

# Audit logs bucket for S3 access logs
module "audit_logs_bucket" {
  source  = "organization/s3-bucket/aws"
  version = "~> 4.0"

  bucket_name = "${var.project_name}-${var.environment}-audit-logs-${data.aws_caller_identity.current.account_id}"
  environment = var.environment

  enable_versioning = false

  lifecycle_rules = [
    {
      id      = "expire-old-audit-logs"
      enabled = true
      expiration = {
        days = var.environment == "prod" ? 365 : 90
      }
    }
  ]

  block_public_access = true
  enable_encryption   = true
  kms_key_id          = aws_kms_key.s3.arn

  tags = {
    DataClassification = "Confidential"
    LogType            = "Audit"
    Compliance         = "SOC2"
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for ALB service account (for access logs)
data "aws_elb_service_account" "main" {}

# IAM policy document for ALB logs bucket
data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid    = "AllowALBAccessLogs"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "arn:aws:s3:::${var.project_name}-${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}/*"
    ]
  }

  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "arn:aws:s3:::${var.project_name}-${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl"
    ]

    resources = [
      "arn:aws:s3:::${var.project_name}-${var.environment}-alb-logs-${data.aws_caller_identity.current.account_id}"
    ]
  }
}

# ============================================================================
# KMS KEYS FOR ENCRYPTION
# ============================================================================

# KMS key for S3 bucket encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption in ${var.environment}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-kms"
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-${var.environment}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# KMS key for RDS encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption in ${var.environment}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-kms"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-${var.environment}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ============================================================================
# RDS AURORA CLUSTER
# ============================================================================

# Generate random password for RDS master user
resource "random_password" "rds_master" {
  length  = 32
  special = true
  # Exclude characters that might cause issues in connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store RDS password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "rds_master_password" {
  name_prefix             = "${var.project_name}-${var.environment}-rds-master-"
  description             = "Master password for RDS Aurora cluster"
  recovery_window_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-master-password"
  }
}

resource "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id = aws_secretsmanager_secret.rds_master_password.id
  secret_string = jsonencode({
    username = var.rds_master_username
    password = random_password.rds_master.result
    engine   = var.rds_engine
    host     = module.rds_aurora.cluster_endpoint
    port     = var.rds_engine == "aurora-postgresql" ? 5432 : 3306
  })
}

# Deploy RDS Aurora cluster using organization module
module "rds_aurora" {
  source  = "organization/rds-aurora/aws"
  version = "~> 2.0"

  cluster_name    = "${var.project_name}-${var.environment}-aurora"
  engine          = var.rds_engine
  engine_version  = var.rds_engine_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.data_subnet_ids
  master_username = var.rds_master_username

  # Use password from Secrets Manager
  master_password = random_password.rds_master.result

  # Instance configuration
  instance_class = var.rds_instance_class
  instance_count = var.environment == "prod" ? 2 : 1

  # Security configuration
  vpc_security_group_ids = [aws_security_group.database.id]
  
  # Encryption at rest is mandatory
  storage_encrypted = true
  kms_key_id        = aws_kms_key.rds.arn

  # Backup configuration
  backup_retention_period      = var.rds_backup_retention_days
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"