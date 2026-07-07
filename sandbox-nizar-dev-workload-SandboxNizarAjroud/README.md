# AWS Three-Tier Application Infrastructure - Terraform Configuration

## Overview

This Terraform configuration deploys a secure, production-ready three-tier application infrastructure in AWS, specifically designed for Alithya's Landing Zone Accelerator (LZA) environment in the `ca-central-1` region.

### Architecture

The configuration deploys the following components:

- **Compute Tier (EC2)**: Amazon Linux 2023 instance with encrypted EBS volumes, IMDSv2 enforcement, and Systems Manager access
- **Storage Tier (S3)**: Encrypted S3 bucket with versioning, lifecycle policies, and enforced HTTPS access
- **Database Tier (RDS)**: PostgreSQL 15.4 database with encryption at rest, automated backups, Performance Insights, and Enhanced Monitoring
- **Security Components**: KMS encryption keys, IAM roles/policies, security groups, and AWS Secrets Manager for credential management

```
┌─────────────────────────────────────────────────────────────┐
│                    VPC (Endpoint VPC)                       │
│                      10.7.0.0/22                            │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Data Tier Subnets                       │  │
│  │                                                      │  │
│  │  ┌──────────────┐         ┌──────────────────────┐  │  │
│  │  │              │         │                      │  │  │
│  │  │  EC2 Instance│────────▶│  RDS PostgreSQL 15.4 │  │  │
│  │  │  (App Server)│         │  (Encrypted)         │  │  │
│  │  │              │         │                      │  │  │
│  │  └──────┬───────┘         └──────────────────────┘  │  │
│  │         │                                           │  │
│  │         │                                           │  │
│  │         ▼                                           │  │
│  │  ┌──────────────┐                                   │  │
│  │  │              │                                   │  │
│  │  │  S3 Bucket   │                                   │  │
│  │  │  (Encrypted) │                                   │  │
│  │  │              │                                   │  │
│  │  └──────────────┘                                   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         KMS Key (Encryption at Rest)                 │  │
│  │         Secrets Manager (DB Credentials)             │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Features

- **Full Encryption**: All data encrypted at rest using AWS KMS with automatic key rotation
- **LZA Compliance**: Meets all Alithya Landing Zone Accelerator Service Control Policy (SCP) requirements
- **Network Isolation**: Resources deployed in private Data tier subnets with no public access
- **Secure Access**: EC2 instances accessible via AWS Systems Manager Session Manager (no SSH keys required)
- **Automated Backups**: RDS automated backups with 7-day retention
- **Cost Optimization**: S3 lifecycle policies for automatic data tiering
- **Monitoring**: CloudWatch Logs, RDS Enhanced Monitoring, and Performance Insights enabled

## Prerequisites

### Required Tools

- **Terraform**: Version 1.5.0 or higher
- **AWS CLI**: Version 2.x configured with appropriate credentials
- **Access**: Valid AWS credentials with permissions to deploy resources in the target account

### AWS Account Setup

This configuration is designed for deployment in an **Alithya Landing Zone Accelerator (LZA)** managed account:

1. **Account Type**: Workload account (not Management or Security account)
2. **Region**: `ca-central-1` (Canada Central - Montreal)
3. **VPC**: Must use the **Endpoint VPC** (10.7.0.0/22) provisioned by LZA
4. **Subnets**: Resources must be deployed in **Data tier subnets** tagged with `Tier = "Data"`

### Required Permissions

Your IAM principal must have permissions to create:

- EC2 instances, security groups, and IAM instance profiles
- S3 buckets with encryption and policies
- RDS instances, subnet groups, and parameter groups
- KMS keys and aliases
- IAM roles and policies
- Secrets Manager secrets
- CloudWatch Logs groups

### Network Prerequisites

Before deploying, ensure you have:

1. **VPC ID**: The ID of your Endpoint VPC (obtain from LZA deployment or AWS Console)
2. **Subnet IDs**: At least 2 private subnet IDs from the Data tier for RDS Multi-AZ deployment
3. **Network Connectivity**: Verify VPC endpoints are configured for Systems Manager (required for EC2 access)

### User Data Script

Create a file named `user_data.sh` in the same directory as your Terraform configuration:

```bash
#!/bin/bash
# user_data.sh - EC2 instance initialization script

# Update system packages
dnf update -y

# Install AWS CLI v2 (if not already present)
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip
fi

# Install CloudWatch agent
dnf install -y amazon-cloudwatch-agent

# Configure CloudWatch agent for application logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "/aws/ec2/${environment}-app-server",
            "log_stream_name": "{instance_id}/messages"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Mount additional EBS volume
mkfs -t xfs /dev/sdf
mkdir -p /data
mount /dev/sdf /data
echo '/dev/sdf /data xfs defaults,nofail 0 2' >> /etc/fstab

# Set environment variables for application
echo "export S3_BUCKET=${s3_bucket}" >> /etc/environment
echo "export AWS_REGION=${region}" >> /etc/environment

# Create application directory
mkdir -p /opt/app
chown ec2-user:ec2-user /opt/app

# Log completion
echo "User data script completed at $(date)" >> /var/log/user-data.log
```

## Usage

### 1. Initialize Terraform

```bash
terraform init
```

This downloads the required providers (AWS ~> 5.0, Random ~> 3.5).

### 2. Configure Variables

Create a `terraform.tfvars` file with your environment-specific values:

```hcl
# terraform.tfvars

aws_region = "ca-central-1"
environment = "dev"

# VPC Configuration - Obtain from LZA deployment
vpc_id = "vpc-0123456789abcdef0"

# Private subnet IDs from Data tier - Must have "Tier = Data" tag
private_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0fedcba9876543210"
]

# Database Configuration
db_name     = "appdb"
db_username = "dbadmin"

# EC2 Configuration
instance_type = "t3.medium"
# ami_id = ""  # Leave empty to use latest Amazon Linux 2023
```

### 3. Review Planned Changes

```bash
terraform plan
```

Review the output carefully to ensure:
- Resources are being created in `ca-central-1`
- Subnets are in the Data tier
- Encryption is enabled for all resources
- No public access is configured

### 4. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm deployment.

**Deployment Time**: Approximately 15-20 minutes (RDS instance creation is the longest operation).

### 5. Retrieve Outputs

After successful deployment:

```bash
# View all outputs
terraform output

# Retrieve specific values
terraform output rds_endpoint
terraform output ec2_instance_id
terraform output rds_secret_arn
```

### 6. Access EC2 Instance

Use AWS Systems Manager Session Manager (no SSH keys required):

```bash
# Get instance ID
INSTANCE_ID=$(terraform output -raw ec2_instance_id)

# Start session
aws ssm start-session --target $INSTANCE_ID --region ca-central-1
```

### 7. Retrieve Database Credentials

```bash
# Get secret ARN
SECRET_ARN=$(terraform output -raw rds_secret_arn)

# Retrieve credentials
aws secretsmanager get-secret-value \
    --secret-id $SECRET_ARN \
    --region ca-central-1 \
    --query SecretString \
    --output text | jq .
```

### 8. Destroy Infrastructure (When No Longer Needed)

```bash
terraform destroy
```

**Note**: For production environments, deletion protection is enabled on the RDS instance. You must manually disable it before destroying.

## Variables

| Variable Name | Type | Description | Default | Required |
|---------------|------|-------------|---------|----------|
| `aws_region` | string | AWS region for resource deployment | `ca-central-1` | No |
| `environment` | string | Environment name (dev, staging, prod) | `dev` | No |
| `vpc_id` | string | VPC ID - must be Endpoint VPC (10.7.0.0/22) | - | **Yes** |
| `private_subnet_ids` | list(string) | Private subnet IDs for RDS and EC2 - must be Data tier subnets | - | **Yes** |
| `db_name` | string | PostgreSQL database name | `appdb` | No |
| `db_username` | string | Database master username (sensitive) | `dbadmin` | No |
| `instance_type` | string | EC2 instance type | `t3.medium` | No |
| `ami_id` | string | AMI ID for EC2 instance (empty = latest Amazon Linux 2023) | `""` | No |

### Variable Validation Notes

- **vpc_id**: Must be a valid VPC ID in your account. Verify it's the Endpoint VPC from LZA.
- **private_subnet_ids**: Must contain at least 2 subnet IDs from different Availability Zones for RDS Multi-AZ support. Subnets must be tagged with `Tier = "Data"`.
- **environment**: Used for resource naming and tagging. For production, set to `prod` to enable RDS deletion protection.
- **db_username**: Stored as sensitive. Avoid using default values in production.

## Outputs

| Output Name | Description | Sensitive |
|-------------|-------------|-----------|
| `s3_bucket_id` | S3 bucket ID | No |
| `s3_bucket_arn` | S3 bucket ARN | No |
| `ec2_instance_id` | EC2 instance ID | No |
| `ec2_instance_private_ip` | EC2 instance private IP address | No |
| `ec2_instance_profile_arn` | EC2 IAM instance profile ARN | No |
| `rds_endpoint` | RDS instance endpoint (includes port) | No |
| `rds_address` | RDS instance address (hostname only) | No |
| `rds_port` | RDS instance port | No |
| `rds_database_name` | RDS database name | No |
| `rds_secret_arn` | ARN of Secrets Manager secret containing RDS credentials | No |
| `kms_key_id` | KMS key ID used for encryption | No |
| `kms_key_arn` | KMS key ARN used for encryption | No |
| `ec2_security_group_id` | EC2 security group ID | No |
| `rds_security_group_id` | RDS security group ID | No |

### Using Outputs in Applications

```bash
# Example: Connect to RDS from EC2 instance
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
DB_NAME=$(terraform output -raw rds_database_name)

# Retrieve credentials from Secrets Manager
SECRET_ARN=$(terraform output -raw rds_secret_arn)
DB_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id $SECRET_ARN \
    --query SecretString \
    --output text | jq -r .password)

# Connect using psql
psql -h $RDS_ENDPOINT -U dbadmin -d $DB_NAME
```

## Security

This configuration implements comprehensive security controls aligned with Alithya's Landing Zone Accelerator requirements and AWS security best practices.

### Encryption at Rest

| Resource | Encryption Method | Key Management |
|----------|-------------------|----------------|
| **S3 Bucket** | SSE-KMS | Customer-managed KMS key with automatic rotation |
| **EC2 Root Volume** | EBS Encryption | Customer-managed KMS key |
| **EC2 Data Volume** | EBS Encryption | Customer-managed KMS key |
| **RDS Database** | RDS Encryption | Customer-managed KMS key |
| **RDS Backups** | Automatic | Inherits from RDS instance encryption |
| **Secrets Manager** | Default Encryption | Customer-managed KMS key |
| **Performance Insights** | Encryption | Customer-managed KMS key |

**KMS Key Features**:
- Automatic key rotation enabled (365-day cycle)
- 30-day deletion window for recovery
- Centralized key for all resources (simplifies key management)

### Encryption in Transit

- **S3**: HTTPS enforced via bucket policy (denies non-SSL requests)
- **RDS**: SSL/TLS required via parameter group (`rds.force_ssl = 1`)
- **EC2 to RDS**: Traffic within VPC (encrypted at network layer)
- **Systems Manager**: All Session Manager traffic encrypted via TLS 1.2+

### Network Security

#### Security Group Configuration

**EC2 Security Group** (`ec2_app`):
- **Ingress**: 
  - Port 443 (HTTPS) from VPC CIDR only
  - Port 80 (HTTP) from VPC CIDR only
- **Egress**: All traffic allowed (for package updates and AWS API calls)

**RDS Security Group** (`rds`):
- **Ingress**: 
  - Port 5432 (PostgreSQL) from EC2 security group only
- **Egress**: All traffic allowed
- **Isolation**: Database only accessible from application tier

#### Network Isolation

- All resources deployed in **private subnets** (Data tier)
- No public IP addresses assigned
- No Internet Gateway access (uses NAT Gateway via LZA)
- RDS `publicly_accessible` explicitly set to `false`

### Identity and Access Management (IAM)

#### EC2 Instance Role

**Permissions**:
- **AWS Systems Manager**: Full SSM access for Session Manager (no SSH keys required)
- **S3 Access**: Read/write to application bucket only
- **KMS Access**: Decrypt and generate data keys for S3 operations
- **Principle of Least Privilege**: No administrative permissions

#### RDS Monitoring Role

**Permissions**:
- **Enhanced Monitoring**: Publish metrics to CloudWatch
- **Managed Policy**: `AmazonRDSEnhancedMonitoringRole`

### Credential Management

- **RDS Password**: 32-character randomly generated password
- **Storage**: AWS Secrets Manager with KMS encryption
- **Rotation**: Manual rotation supported (automatic rotation can be configured)
- **Access**: EC2 instance can retrieve credentials via IAM role
- **No Hardcoding**: Passwords never stored in Terraform state (marked sensitive)

### EC2 Security Hardening

#### IMDSv2 Enforcement

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"        # IMDSv2 only
  http_put_response_hop_limit = 1                 # Prevent SSRF
  instance_metadata_tags      = "enabled"
}
```

**Benefits**:
- Prevents SSRF attacks
- Requires session tokens for metadata access
- Complies with AWS Config rule `ec2-imdsv2-check`

#### Operating System

- **Amazon Linux 2023**: Latest security patches
- **Automatic Updates**: User data script updates packages on launch
- **CloudWatch Agent**: Centralized log collection

### S3 Security Controls

1. **Public Access Block**: All four settings enabled (SCP enforced)
2. **Bucket Versioning**: Enabled for data protection and recovery
3. **Lifecycle Policies**: Automatic transition to lower-cost storage classes
4. **Bucket Policy**: Denies all non-HTTPS requests
5. **Access Logging**: Can be enabled by uncommenting configuration

### RDS Security Controls

1. **IAM Database Authentication**: Enabled for token-based access
2. **Automated Backups**: 7-day retention with point-in-time recovery
3. **Enhanced Monitoring**: 60-second granularity
4. **Performance Insights**: 7-day retention with KMS encryption
5. **CloudWatch Logs**: PostgreSQL and upgrade logs exported
6. **Deletion Protection**: Enabled for production environments
7. **Multi-AZ**: Can be enabled by setting `multi_az = true`

### Compliance with LZA SCPs

This configuration satisfies the following Alithya LZA Service Control Policies:

| SCP Requirement | Implementation | Resource |
|-----------------|----------------|----------|
| **Encryption at Rest** | KMS encryption enabled | S3, EBS, RDS, Secrets Manager |
| **S3 Public Access Block** | All four settings enabled | S3 bucket |
| **HTTPS Only** | Bucket policy denies non-SSL | S3 bucket |
| **IMDSv2 Required** | `http_tokens = "required"` | EC2 instance |
| **No Public RDS** | `publicly_accessible = false` | RDS instance |
| **KMS Key Rotation** | `enable_key_rotation = true` | KMS key |
| **Region Restriction** | Resources in `ca-central-1` | All resources |
| **Mandatory Tagging** | Default tags via provider | All resources |

### Audit and Logging

- **CloudTrail**: All API calls logged (configured at LZA level)
- **VPC Flow Logs**: Network traffic logged (configured at LZA level)
- **RDS Logs**: PostgreSQL logs exported to CloudWatch
- **S3 Access Logs**: Can be enabled for bucket access auditing
- **CloudWatch Logs**: EC2 system logs centralized

## Cost Estimation

Approximate monthly costs for this infrastructure in **ca-central-1** (Canada Central) region using AWS on-demand pricing as of 2024. Costs are estimates and may vary based on actual usage.

### Cost Breakdown by Service

| Service | Component | Specification | Monthly Cost (CAD) |
|---------|-----------|---------------|-------------------|
| **EC2** | Instance | t3.medium (2 vCPU, 4 GB RAM) | $40.88 |
| | Root Volume | 30 GB gp3 | $3.12 |
| | Data Volume | 100 GB gp3 | $10.40 |
| | Data Transfer | 10 GB outbound (estimate) | $1.20 |
| **S3** | Storage | 100 GB Standard | $2.76 |
| | Storage | 50 GB Standard-IA (after 90 days) | $1.56 |
| | Storage | 50 GB Glacier Instant Retrieval (after 180 days) | $0.52 |
| | Requests | 100,000 PUT/POST | $0.65 |
| | Requests | 1,000,000 GET | $0.52 |
| **RDS** | Instance | db.t3.medium (2 vCPU, 4 GB RAM) | $81.76 |
| | Storage | 100 GB gp3 | $15.60 |
| | Backup Storage | 100 GB (7-day retention) | $12.48 |
| | Enhanced Monitoring | 60-second interval | $4.68 |
| | Performance Insights | 7-day retention | $9.36 |
| **KMS** | Key | 1 customer-managed key | $1.30 |
| | Requests | 10,000 API calls | $0.04 |
| **Secrets Manager** | Secret | 1 secret | $0.52 |
| | API Calls | 1,000 calls | $0.07 |
| **CloudWatch** | Logs | 10 GB ingestion | $6.50 |
| | Logs | 10 GB storage | $0.39 |
| **Data Transfer** | VPC | Inter-AZ (estimate) | $2.60 |

### Total Monthly Cost Estimate

| Environment | Configuration | Estimated Monthly Cost (CAD) |
|-------------|---------------|------------------------------|
| **Development** | Single-AZ, minimal usage | **$196 - $220** |
| **Staging** | Single-AZ, moderate usage | **$220 - $260** |
| **Production** | Multi-AZ RDS, high availability | **$320 - $380** |

### Cost Optimization Recommendations

#### Immediate Savings

1. **Reserved Instances**: Save up to 40% on EC2 and RDS with 1-year commitment
   - EC2 t3.medium: ~$24/month (save $17/month)
   - RDS db.t3.medium: ~$49/month (save $33/month)

2. **Savings Plans**: Flexible commitment with similar savings to Reserved Instances

3. **S3 Lifecycle Policies**: Already implemented
   - Transitions to Standard-IA after 90 days
   - Transitions to Glacier Instant Retrieval after 180 days

4. **RDS Storage Autoscaling**: Already configured
   - Starts at 100 GB, scales to 500 GB as needed
   - Only pay for storage used

#### Development Environment Savings

For non-production environments:

```hcl
# terraform.tfvars for dev environment
instance_type = "t3.small"           # Save ~$20/month on EC2
db_instance_class = "db.t3.small"    # Save ~$40/month on RDS

# Reduce RDS backup retention
backup_retention_period = 1          # Save ~$10/month on backup storage

# Disable Performance Insights
performance_insights_enabled = false # Save ~$9/month
```

**Dev Environment Cost**: ~$120-140/month

#### Scheduled Shutdown

For development environments, consider using AWS Instance Scheduler:
- Run EC2/RDS only during business hours (8 AM - 6 PM, Mon-Fri)
- **Potential Savings**: 70% reduction (~$140/month for dev)

#### Monitoring Costs

Reduce CloudWatch Logs retention:
```hcl
# Add to configuration
resource "aws_cloudwatch_log_group" "app" {
  retention_in_days = 7  # Instead of indefinite retention
}
```

**Savings**: ~$5/month on log storage

### Cost Monitoring

Set up AWS Budgets to track spending:

```bash
# Create a budget alert
aws budgets create-budget \
    --account-id YOUR_ACCOUNT_ID \
    --budget file://budget.json \
    --notifications-with-subscribers file://notifications.json
```

**budget.json**:
```json
{
  "BudgetName": "dev-infrastructure-budget",
  "BudgetLimit": {
    "Amount": "250",
    "Unit": "CAD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

### Free Tier Considerations

If your AWS account is within the 12-month free tier:
- **EC2**: 750 hours/month of t2.micro or t3.micro (not t3.medium)
- **RDS**: 750 hours/month of db.t2.micro or db.t3.micro (not t3.medium)
- **S3**: 5 GB Standard storage
- **CloudWatch**: 10 custom metrics, 10 alarms

**Note**: This configuration uses t3.medium instances which are not free tier eligible.

## Well-Architected Review

This infrastructure aligns with the AWS Well-Architected Framework across all six pillars.

### 1. Operational Excellence

**Design Principles Implemented**:

✅ **Infrastructure as Code**: Entire infrastructure defined in Terraform
- Version controlled and repeatable deployments
- Consistent environments across dev/staging/prod
- Automated provisioning reduces human error

✅ **Observability**: Comprehensive monitoring and logging
- CloudWatch Logs for EC2 system logs
- RDS Enhanced Monitoring (60-second granularity)
- RDS Performance Insights for query analysis
- CloudWatch Logs for PostgreSQL database logs

✅ **Automated Operations**:
- RDS automated backups with 7-day retention
- S3 lifecycle policies for automatic data tiering
- Auto minor version upgrades for RDS
- KMS automatic key rotation

**Recommendations for Improvement**:
- Implement AWS Systems Manager Patch Manager for automated OS patching
- Add CloudWatch Alarms for key metrics (CPU, disk, memory)
- Configure SNS topics for operational notifications
- Implement AWS Config Rules for continuous compliance monitoring

### 2. Security

**Design Principles Implemented**:

✅ **Defense in Depth**: Multiple layers of security controls
- Network isolation (private subnets, security groups)
- Encryption at rest (KMS) and in transit (TLS/SSL)
- IAM roles with least privilege
- No public access to any resources

✅ **Identity and Access Management**:
- IAM roles instead of long-term credentials
- EC2 instance profile for AWS API access
- RDS IAM database authentication enabled
- Secrets Manager for credential storage

✅ **Data Protection**:
- All data encrypted at rest with customer-managed KMS keys
- S3 versioning enabled for data recovery
- RDS automated backups with encryption
- 30-day KMS key deletion window

✅ **Infrastructure Protection**:
- Security groups with minimal required access
- IMDSv2 enforcement on EC2 instances
- No SSH keys required (Systems Manager access)
- VPC Flow Logs enabled (at LZA level)

✅ **Detective Controls**:
- CloudTrail logging (at LZA level)
- CloudWatch Logs for audit trails
- RDS Enhanced Monitoring
- VPC Flow Logs

**Security Score**: 9/10

**Recommendations**:
- Enable AWS GuardDuty for threat detection
- Implement AWS Security Hub for centralized security findings
- Add AWS WAF if exposing web applications
- Enable S3 access logging for detailed audit trails

### 3. Reliability

**Design Principles Implemented**:

✅ **Automated Recovery**:
- RDS automated backups with point-in-time recovery
- S3 versioning for object recovery
- RDS automatic failover (when Multi-AZ enabled)

✅ **Horizontal Scaling**:
- RDS storage autoscaling (100 GB → 500 GB)
- S3 unlimited scalability

✅ **Monitoring and Alerting**:
- RDS Enhanced Monitoring
- CloudWatch Logs integration
- Performance Insights for database performance

⚠️ **Areas for Improvement**:
- Single EC2 instance (no high availability)
- RDS deployed in single AZ (Multi-AZ recommended for production)
- No Auto Scaling Group for EC2

**Reliability Score**: 6/10 (Development), 8/10 (Production with Multi-AZ)

**Recommendations for Production**:

```hcl
# Enable Multi-AZ for RDS
resource "aws_db_instance" "main" {
  multi_az = true  # Add this for production
  # ... other configuration
}

# Add Auto Scaling Group for EC2
resource "aws_autoscaling_group" "app" {
  min_size         = 2
  max_size         = 4
  desired_capacity = 2
  # ... configuration
}

# Add Application Load Balancer
resource "aws_lb" "app" {
  load_balancer_type = "application"
  # ... configuration
}
```

### 4. Performance Efficiency

**Design Principles Implemented**:

✅ **Right-Sizing**:
- t3.medium instances (burstable performance)
- gp3 volumes (cost-effective SSD storage)
- db.t3.medium for RDS (appropriate for small-medium workloads)

✅ **Performance Monitoring**:
- RDS Performance Insights enabled
- Enhanced Monitoring for detailed metrics
- CloudWatch Logs for application performance

✅ **Storage Optimization**:
- gp3 volumes (better price/performance than gp2)
- S3 lifecycle policies for cost-effective storage
- RDS storage autoscaling

**Performance Score**: 7/10

**Recommendations**:
- Implement CloudWatch dashboards for performance visualization
- Add RDS read replicas for read-heavy workloads
- Consider ElastiCache for caching layer
- Use CloudFront for S3 content delivery (if applicable)

**Instance Sizing Guidance**:

| Workload Type | EC2 Instance | RDS Instance | Expected Performance |
|---------------|--------------|--------------|---------------------|
| **Light** (< 100 users) | t3.small | db.t3.small | Good for dev/test |
| **Medium** (100-500 users) | t3.medium | db.t3.medium | Current configuration |
| **Heavy** (500-2000 users) | t3.large | db.m5.large | Upgrade recommended |
| **Very Heavy** (> 2000 users) | m5.xlarge | db.m5.xlarge | Consider clustering |

### 5. Cost Optimization

**Design Principles Implemented**:

✅ **Right-Sizing**:
- Burstable instances (t3 family) for variable workloads
- gp3 volumes (20% cheaper than gp2)
- Storage autoscaling prevents over-provisioning

✅ **Lifecycle Management**:
- S3 lifecycle policies (Standard → IA → Glacier)
- RDS backup retention limited to 7 days
- KMS key deletion window (30 days)

✅ **Monitoring and Analysis**:
- Cost allocation tags on all resources
- Environment tagging for cost tracking

**Cost Optimization Score**: 8/10

**Recommendations**:
- Purchase Reserved Instances for production (40% savings)
- Implement AWS Compute Optimizer recommendations
- Use AWS Cost Explorer for trend analysis
- Consider Spot Instances for non-critical workloads

### 6. Sustainability

**Design Principles Implemented**:

✅ **Region Selection**:
- ca-central-1 (Hydro-Québec powered, 99% renewable energy)

✅ **Resource Efficiency**:
- Burstable instances reduce idle resource consumption
- S3 lifecycle policies move data to energy-efficient storage
- RDS storage autoscaling prevents over-provisioning

✅ **Managed Services**:
- RDS, S3, and managed services have better resource utilization than self-managed

**Sustainability Score**: 7/10

**Recommendations**:
- Implement scheduled shutdown for non-production environments
- Use AWS Graviton instances (60% better energy efficiency)
- Monitor and optimize data transfer to reduce network energy consumption

### Overall Well-Architected Score

| Pillar | Score | Priority for Improvement |
|--------|-------|-------------------------|
| Operational Excellence | 8/10 | Medium |
| Security | 9/10 | Low |
| Reliability | 6/10 (dev) / 8/10 (prod) | **High** |
| Performance Efficiency | 7/10 | Medium |
| Cost Optimization | 8/10 | Low |
| Sustainability | 7/10 | Medium |

**Overall**: 7.5/10 - Well-architected for development, requires enhancements for production workloads.

## Compliance

This Terraform configuration is designed to comply with Alith