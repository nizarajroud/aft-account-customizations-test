# AWS Multi-Tier Infrastructure with Terraform

## Overview

This Terraform configuration deploys a production-ready, secure multi-tier architecture on AWS with the following components:

### Architecture Components

- **Networking**: Multi-AZ VPC with public, private, and data subnets across availability zones
- **Compute**: Auto-scaling EC2 instances in private subnets with Application Load Balancer
- **Storage**: S3 buckets with encryption, versioning, and lifecycle policies
- **Database**: RDS Aurora cluster (PostgreSQL or MySQL) with automated backups and encryption
- **Security**: KMS encryption, IAM roles with least privilege, security groups, and network ACLs
- **Monitoring**: VPC Flow Logs, ALB access logs, and CloudWatch integration

### Architecture Diagram

```
Internet
    │
    ├─── Application Load Balancer (Public Subnets)
    │         │
    │         └─── HTTPS/HTTP
    │
    ├─── NAT Gateway (Public Subnets)
    │
    └─── VPC (10.0.0.0/16)
         │
         ├─── Web Tier (Public Subnets)
         │    └─── ALB
         │
         ├─── Application Tier (Private Subnets)
         │    └─── Auto Scaling Group (EC2 Instances)
         │         └─── Access to S3 via IAM roles
         │
         ├─── Data Tier (Private Subnets)
         │    └─── RDS Aurora Cluster (Multi-AZ)
         │
         └─── Management Tier (Private Subnets)
              └─── Bastion Hosts (Optional)
```

## Prerequisites

### Required Tools

- **Terraform**: >= 1.5.0 ([Installation Guide](https://developer.hashicorp.com/terraform/downloads))
- **AWS CLI**: >= 2.0 ([Installation Guide](https://aws.amazon.com/cli/))
- **Git**: For version control

### AWS Account Requirements

1. **AWS Account** with appropriate permissions
2. **IAM User/Role** with the following permissions:
   - EC2 (full access)
   - VPC (full access)
   - S3 (full access)
   - RDS (full access)
   - IAM (role and policy creation)
   - KMS (key management)
   - Secrets Manager (secret creation)
   - CloudWatch (logs and metrics)
   - Auto Scaling (full access)
   - Elastic Load Balancing (full access)
   - ACM (certificate management)

3. **AWS CLI Configuration**:
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, and default region
   ```

### Pre-Deployment Setup

1. **Create S3 Backend Bucket** (recommended for production):
   ```bash
   aws s3api create-bucket \
     --bucket your-terraform-state-bucket \
     --region us-east-1
   
   aws s3api put-bucket-versioning \
     --bucket your-terraform-state-bucket \
     --versioning-configuration Status=Enabled
   
   aws dynamodb create-table \
     --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region us-east-1
   ```

2. **Create VPC Module** (if using custom organization module):
   - Replace `organization/vpc/aws` with a public module like `terraform-aws-modules/vpc/aws`
   - Or create your own VPC resources

3. **Create S3 Bucket Module** (if using custom organization module):
   - Replace `organization/s3-bucket/aws` with `terraform-aws-modules/s3-bucket/aws`
   - Or use the AWS S3 bucket resources directly

4. **Create RDS Aurora Module** (if using custom organization module):
   - Replace `organization/rds-aurora/aws` with `terraform-aws-modules/rds-aurora/aws`
   - Or use AWS RDS cluster resources directly

5. **Create User Data Script**:
   ```bash
   cat > user_data.sh << 'EOF'
   #!/bin/bash
   # User data script for EC2 instances
   
   # Update system packages
   yum update -y
   
   # Install CloudWatch agent
   yum install -y amazon-cloudwatch-agent
   
   # Install SSM agent (pre-installed on Amazon Linux 2023)
   systemctl enable amazon-ssm-agent
   systemctl start amazon-ssm-agent
   
   # Install application dependencies
   yum install -y docker
   systemctl enable docker
   systemctl start docker
   
   # Configure application
   echo "Environment: ${environment}" > /etc/app-config
   echo "Project: ${project_name}" >> /etc/app-config
   echo "Region: ${region}" >> /etc/app-config
   EOF
   ```

## Usage

### 1. Clone and Initialize

```bash
# Clone the repository (or create a new directory)
mkdir aws-infrastructure && cd aws-infrastructure

# Copy the Terraform configuration files
# (Assuming you have main.tf with all the configuration)

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required Variables
project_name = "myapp"
environment  = "dev"  # or "staging", "prod"

# Optional Variables (with sensible defaults)
aws_region              = "us-east-1"
cost_center             = "engineering"
vpc_cidr_block          = "10.0.0.0/16"
ec2_instance_type       = "t3.medium"
rds_engine              = "aurora-postgresql"
rds_engine_version      = "15.4"
rds_instance_class      = "db.r6g.large"
rds_master_username     = "dbadmin"
rds_backup_retention_days = 7

# Security Configuration
enable_deletion_protection = true
allowed_ssh_cidr_blocks    = ["203.0.113.0/24"]  # Your office IP range

# Storage Configuration
s3_lifecycle_glacier_days = 90
```

### 3. Plan the Deployment

```bash
# Review the execution plan
terraform plan -out=tfplan

# Review the plan output carefully
# Verify resource counts and configurations
```

### 4. Apply the Configuration

```bash
# Apply the configuration
terraform apply tfplan

# Or apply directly (will prompt for confirmation)
terraform apply

# For production deployments, use:
terraform apply -var-file=production.tfvars
```

### 5. Verify Deployment

```bash
# Get outputs
terraform output

# Test ALB endpoint
curl -I https://$(terraform output -raw alb_dns_name)

# Connect to EC2 instance via SSM (no SSH keys needed)
aws ssm start-session --target $(terraform output -json ec2_instance_ids | jq -r '.[0]')
```

### 6. Destroy Resources (when needed)

```bash
# Destroy all resources
terraform destroy

# For production, disable deletion protection first
terraform apply -var="enable_deletion_protection=false"
terraform destroy
```

## Variables

### Required Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `project_name` | string | Project name for resource naming and tagging | **(required)** |
| `environment` | string | Environment name (dev, staging, prod) | **(required)** |

### Optional Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `aws_region` | string | AWS region for resource deployment | `us-east-1` |
| `cost_center` | string | Cost center for billing allocation | `engineering` |
| `vpc_cidr_block` | string | CIDR block for the VPC | `10.0.0.0/16` |
| `ec2_instance_type` | string | EC2 instance type for application servers | `t3.medium` |
| `ec2_ami_id` | string | AMI ID for EC2 instances (defaults to latest Amazon Linux 2023) | `""` (auto-detected) |
| `rds_engine` | string | RDS Aurora engine (aurora-postgresql or aurora-mysql) | `aurora-postgresql` |
| `rds_engine_version` | string | RDS Aurora engine version | `15.4` |
| `rds_instance_class` | string | RDS instance class | `db.r6g.large` |
| `rds_master_username` | string | Master username for RDS cluster | `dbadmin` |
| `rds_backup_retention_days` | number | Number of days to retain automated backups (minimum 7) | `7` |
| `enable_deletion_protection` | bool | Enable deletion protection for critical resources | `true` |
| `s3_lifecycle_glacier_days` | number | Days before transitioning S3 objects to Glacier | `90` |
| `allowed_ssh_cidr_blocks` | list(string) | CIDR blocks allowed to SSH to bastion hosts | `[]` (empty) |

## Outputs

The configuration provides the following outputs:

| Output | Description |
|--------|-------------|
| `vpc_id` | VPC ID |
| `vpc_cidr_block` | VPC CIDR block |
| `web_subnet_ids` | List of web tier subnet IDs |
| `app_subnet_ids` | List of application tier subnet IDs |
| `data_subnet_ids` | List of data tier subnet IDs |
| `alb_dns_name` | DNS name of the Application Load Balancer |
| `alb_zone_id` | Route53 zone ID of the ALB |
| `alb_arn` | ARN of the Application Load Balancer |
| `app_data_bucket_name` | Name of the application data S3 bucket |
| `app_data_bucket_arn` | ARN of the application data S3 bucket |
| `alb_logs_bucket_name` | Name of the ALB logs S3 bucket |
| `audit_logs_bucket_name` | Name of the audit logs S3 bucket |
| `rds_cluster_endpoint` | Writer endpoint for the RDS Aurora cluster |
| `rds_reader_endpoint` | Reader endpoint for the RDS Aurora cluster |
| `rds_cluster_id` | RDS Aurora cluster identifier |
| `rds_master_password_secret_arn` | ARN of the Secrets Manager secret containing RDS credentials |
| `ec2_instance_role_arn` | ARN of the IAM role for EC2 instances |
| `ec2_instance_profile_name` | Name of the IAM instance profile |
| `autoscaling_group_name` | Name of the Auto Scaling Group |
| `kms_s3_key_id` | KMS key ID for S3 encryption |
| `kms_rds_key_id` | KMS key ID for RDS encryption |

### Accessing Outputs

```bash
# Get all outputs
terraform output

# Get specific output
terraform output alb_dns_name

# Get output in JSON format
terraform output -json

# Use output in scripts
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "Application URL: https://$ALB_DNS"
```

## Security

This configuration implements multiple layers of security following AWS best practices:

### 1. Network Security

- **VPC Isolation**: Resources deployed in isolated VPC with private subnets
- **Security Groups**: Least-privilege security group rules
  - Web tier: Only ports 80/443 from internet
  - App tier: Only port 8080 from web tier
  - Database: Only database port from app tier
  - Management: SSH only from approved CIDR blocks
- **Network ACLs**: Additional network-level filtering between tiers
- **NAT Gateway**: Outbound internet access for private subnets without exposing instances
- **VPC Flow Logs**: Network traffic logging for audit and troubleshooting

### 2. Encryption

- **Data at Rest**:
  - S3 buckets encrypted with KMS customer-managed keys
  - RDS Aurora encrypted with KMS customer-managed keys
  - EBS volumes encrypted by default
  - Secrets Manager for sensitive data
- **Data in Transit**:
  - HTTPS/TLS 1.3 enforced on ALB
  - SSL/TLS for RDS connections
  - IMDSv2 enforced on EC2 instances

### 3. Identity and Access Management

- **IAM Roles**: EC2 instances use IAM roles (no long-term credentials)
- **Least Privilege**: Minimal permissions for each role
- **SSM Session Manager**: Secure shell access without SSH keys or bastion hosts
- **Instance Profiles**: Automatic credential rotation

### 4. Data Protection

- **S3 Versioning**: Enabled on application data bucket
- **S3 Block Public Access**: All buckets blocked from public access
- **RDS Automated Backups**: 7-30 day retention with point-in-time recovery
- **RDS Multi-AZ**: High availability in production
- **Deletion Protection**: Enabled for production databases and load balancers

### 5. Monitoring and Logging

- **CloudWatch Logs**: Application and system logs
- **VPC Flow Logs**: Network traffic analysis
- **ALB Access Logs**: HTTP request logging
- **S3 Access Logs**: Bucket access audit trail
- **CloudWatch Metrics**: Performance and health monitoring

### 6. Compliance Features

- **SOC2 Ready**: Encryption, logging, and access controls
- **Audit Trail**: Comprehensive logging to S3
- **Key Rotation**: Automatic KMS key rotation enabled
- **Password Complexity**: Strong random passwords for RDS

### Security Best Practices Checklist

- ✅ All data encrypted at rest and in transit
- ✅ No hardcoded credentials (using Secrets Manager)
- ✅ Least-privilege IAM policies
- ✅ Network segmentation with security groups
- ✅ Multi-AZ deployment for high availability
- ✅ Automated backups with retention policies
- ✅ Comprehensive logging and monitoring
- ✅ IMDSv2 enforced on EC2 instances
- ✅ Public access blocked on all S3 buckets
- ✅ TLS 1.3 enforced on load balancers

## Cost Estimation

### Monthly Cost Breakdown (ca-central-1 Region)

Based on on-demand pricing for ca-central-1 (Canada Central) as of 2024:

#### Development Environment

| Service | Configuration | Monthly Cost (CAD) |
|---------|--------------|-------------------|
| **EC2** | 1x t3.medium (730 hrs) | $40.15 |
| **EBS** | 50 GB gp3 | $5.50 |
| **ALB** | 1 ALB + LCU charges | $27.00 |
| **NAT Gateway** | 1 NAT Gateway + data transfer (100 GB) | $48.00 |
| **RDS Aurora** | 1x db.r6g.large (730 hrs) | $175.20 |
| **RDS Storage** | 100 GB | $13.00 |
| **RDS Backup** | 100 GB | $13.00 |
| **S3 Storage** | 100 GB Standard | $3.00 |
| **S3 Requests** | 1M PUT, 10M GET | $0.70 |
| **KMS** | 2 keys | $2.00 |
| **Secrets Manager** | 1 secret | $0.53 |
| **VPC Flow Logs** | 10 GB/day | $4.00 |
| **Data Transfer** | 100 GB outbound | $11.00 |
| **CloudWatch** | Logs and metrics | $10.00 |
| **Total (Dev)** | | **~$353/month** |

#### Production Environment

| Service | Configuration | Monthly Cost (CAD) |
|---------|--------------|-------------------|
| **EC2** | 2x t3.medium (730 hrs each) | $80.30 |
| **EBS** | 100 GB gp3 (2 instances) | $11.00 |
| **ALB** | 1 ALB + higher LCU charges | $45.00 |
| **NAT Gateway** | 2 NAT Gateways + data transfer (500 GB) | $144.00 |
| **RDS Aurora** | 2x db.r6g.large (730 hrs each) | $350.40 |
| **RDS Storage** | 500 GB | $65.00 |
| **RDS Backup** | 500 GB | $65.00 |
| **S3 Storage** | 1 TB Standard + Glacier | $35.00 |
| **S3 Requests** | 10M PUT, 100M GET | $7.00 |
| **KMS** | 2 keys | $2.00 |
| **Secrets Manager** | 1 secret | $0.53 |
| **VPC Flow Logs** | 50 GB/day | $20.00 |
| **Data Transfer** | 1 TB outbound | $110.00 |
| **CloudWatch** | Logs and metrics | $50.00 |
| **Total (Prod)** | | **~$985/month** |

### Cost Optimization Strategies

1. **Use Reserved Instances**: Save up to 72% on EC2 and RDS with 1-year or 3-year commitments
2. **Right-Size Instances**: Monitor CloudWatch metrics and adjust instance types
3. **S3 Lifecycle Policies**: Automatically transition to cheaper storage classes
4. **Spot Instances**: Use for non-critical workloads (up to 90% savings)
5. **Single NAT Gateway**: Use one NAT Gateway for dev/staging (not recommended for prod)
6. **Aurora Serverless**: Consider for variable workloads
7. **S3 Intelligent-Tiering**: Automatic cost optimization for S3
8. **Delete Unused Resources**: Regular cleanup of snapshots, old AMIs, and unused volumes

### Cost Monitoring

```bash
# Enable AWS Cost Explorer
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Environment

# Set up billing alerts
aws cloudwatch put-metric-alarm \
  --alarm-name billing-alarm \
  --alarm-description "Alert when charges exceed $1000" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 21600 \
  --evaluation-periods 1 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold
```

## Well-Architected Review

This infrastructure aligns with the AWS Well-Architected Framework across all six pillars:

### 1. Operational Excellence

**Design Principles Implemented:**
- ✅ **Infrastructure as Code**: All resources defined in Terraform
- ✅ **Annotated Documentation**: Comprehensive inline comments and README
- ✅ **Frequent, Small Changes**: Terraform enables incremental updates
- ✅ **Automated Responses**: Auto Scaling responds to load changes
- ✅ **Learn from Failures**: CloudWatch Logs and metrics for troubleshooting

**Best Practices:**
- Version-controlled infrastructure code
- Automated deployment with `terraform apply`
- CloudWatch monitoring and alerting
- VPC Flow Logs for network analysis
- ALB access logs for request tracking
- SSM Session Manager for secure access

**Recommendations:**
- Implement CI/CD pipeline for Terraform deployments
- Add CloudWatch dashboards for visualization
- Configure SNS notifications for Auto Scaling events
- Implement automated testing with Terratest

### 2. Security

**Design Principles Implemented:**
- ✅ **Strong Identity Foundation**: IAM roles with least privilege
- ✅ **Traceability**: Comprehensive logging (VPC Flow, ALB, S3 access)
- ✅ **Security at All Layers**: Network, application, and data encryption
- ✅ **Automate Security**: Automated encryption, patching via user data
- ✅ **Protect Data in Transit and at Rest**: KMS encryption, TLS 1.3
- ✅ **Keep People Away from Data**: SSM Session Manager, no SSH keys
- ✅ **Prepare for Security Events**: Logging and monitoring in place

**Security Controls:**
- Multi-layer network security (Security Groups + NACLs)
- KMS customer-managed keys for encryption
- Secrets Manager for credential management
- IMDSv2 enforced on EC2 instances
- S3 Block Public Access enabled
- Deletion protection for critical resources
- Automated backups with encryption

**Compliance Features:**
- SOC2-ready logging and encryption
- Audit trail in S3 with retention policies
- Network traffic logging with VPC Flow Logs
- Access logging for all S3 buckets

### 3. Reliability

**Design Principles Implemented:**
- ✅ **Automatic Recovery**: Auto Scaling replaces failed instances
- ✅ **Test Recovery Procedures**: RDS automated backups enable testing
- ✅ **Scale Horizontally**: Auto Scaling Group distributes load
- ✅ **Stop Guessing Capacity**: Auto Scaling based on metrics
- ✅ **Manage Change with Automation**: Terraform for consistent deployments

**High Availability Features:**
- Multi-AZ deployment across availability zones
- RDS Aurora with automated failover (2 instances in prod)
- Auto Scaling Group with health checks
- Application Load Balancer with health checks
- NAT Gateway redundancy in production
- Automated backups with 7-30 day retention

**Resilience Patterns:**
- Auto Scaling maintains desired capacity
- ALB distributes traffic across healthy instances
- RDS automated backups with point-in-time recovery
- S3 versioning for data protection
- Instance refresh for zero-downtime updates

**Recommendations:**
- Implement Route53 health checks
- Add cross-region replication for S3
- Configure RDS read replicas for read scaling
- Implement chaos engineering tests

### 4. Performance Efficiency

**Design Principles Implemented:**
- ✅ **Democratize Advanced Technologies**: Managed services (RDS, ALB, S3)
- ✅ **Go Global in Minutes**: Multi-region capable design
- ✅ **Use Serverless Architectures**: S3 for storage, potential Lambda integration
- ✅ **Experiment More Often**: Terraform enables quick testing
- ✅ **Mechanical Sympathy**: Right-sized instances for workload

**Performance Optimizations:**
- gp3 EBS volumes with 3000 IOPS baseline
- Application Load Balancer for efficient traffic distribution
- Auto Scaling based on CPU utilization (70% target)
- RDS Aurora for high-performance database
- CloudFront-ready architecture (ALB as origin)
- Instance types optimized for workload (t3.medium, db.r6g.large)

**Monitoring:**
- CloudWatch metrics for all services
- Detailed monitoring for production EC2 instances
- ALB target group health checks
- RDS Performance Insights (can be enabled)

**Recommendations:**
- Add CloudFront CDN for static content
- Implement ElastiCache for caching layer
- Use Aurora Serverless for variable workloads
- Enable RDS Performance Insights

### 5. Cost Optimization

**Design Principles Implemented:**
- ✅ **Implement Cloud Financial Management**: Tagging strategy for cost allocation
- ✅ **Adopt a Consumption Model**: Auto Scaling adjusts to demand
- ✅ **Measure Overall Efficiency**: CloudWatch metrics track utilization
- ✅ **Stop Spending on Undifferentiated Work**: Managed services (RDS, ALB)
- ✅ **Analyze and Attribute Expenditure**: Comprehensive tagging

**Cost Optimization Features:**
- Auto Scaling reduces costs during low demand
- S3 lifecycle policies transition to Glacier
- Single NAT Gateway for non-production
- gp3 volumes (cheaper than gp2 with better performance)
- Right-sized instances based on environment
- Automated cleanup of old backups and versions

**Tagging Strategy:**
- Environment tag for cost allocation
- Project tag for multi-project accounts
- CostCenter tag for chargeback
- ManagedBy tag for automation tracking

**Recommendations:**
- Purchase Reserved Instances for production
- Implement AWS Budgets and Cost Anomaly Detection
- Use Compute Savings Plans
- Enable S3 Intelligent-Tiering
- Consider Aurora Serverless for dev/staging

### 6. Sustainability

**Design Principles Implemented:**
- ✅ **Understand Your Impact**: CloudWatch metrics track resource utilization
- ✅ **Establish Sustainability Goals**: Right-sizing and Auto Scaling
- ✅ **Maximize Utilization**: Auto Scaling adjusts capacity to demand
- ✅ **Use Managed Services**: RDS, ALB, S3 (AWS optimizes efficiency)
- ✅ **Reduce Downstream Impact**: Efficient data transfer and caching

**Sustainability Features:**
- Auto Scaling prevents over-provisioning
- Graviton2 instances (db.r6g) for better performance per watt
- S3 lifecycle policies reduce storage footprint
- Efficient gp3 volumes
- Multi-AZ deployment reduces redundant resources in non-prod

**Recommendations:**
- Use Graviton3 instances (t4g, r7g) when available
- Implement data compression for S3 and RDS
- Use Aurora Serverless to minimize idle capacity
- Enable S3 Intelligent-Tiering
- Schedule non-production resources to stop during off-hours

---

## Troubleshooting

### Common Issues

#### 1. Module Not Found Errors

**Error**: `Module not installed` or `organization/vpc/aws` not found

**Solution**: Replace organization modules with public modules:

```hcl
# Replace this:
module "vpc" {
  source  = "organization/vpc/aws"
  version = "~> 5.0"
  # ...
}

# With this:
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr_block
  
  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = true
  single_nat_gateway = var.environment != "prod"
  enable_dns_hostnames = true
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
```

#### 2. ACM Certificate Validation

**Error**: Certificate stuck in "Pending Validation"

**Solution**: Add DNS validation records or use DNS validation automation:

```hcl
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}
```

#### 3. RDS Cluster Creation Timeout

**Error**: RDS cluster creation times out

**Solution**: Increase timeout or check security group rules:

```hcl
resource "aws_rds_cluster" "main" {
  # ... other configuration ...
  
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
```

#### 4. Insufficient Permissions

**Error**: `UnauthorizedOperation` or `AccessDenied`

**Solution**: Ensure IAM user/role has required permissions. Attach these policies:
- `AmazonEC2FullAccess`
- `AmazonS3FullAccess`
- `AmazonRDSFullAccess`
- `IAMFullAccess`
- `AmazonVPCFullAccess`

### Getting Help

```bash
# Enable Terraform debug logging
export TF_LOG=DEBUG
terraform apply

# Validate configuration
terraform validate

# Format configuration
terraform fmt -recursive

# Check state
terraform state list
terraform state show <resource>

# Refresh state
terraform refresh
```

## Maintenance

### Regular Maintenance Tasks

1. **Weekly**:
   - Review CloudWatch alarms and metrics
   - Check Auto Scaling activity
   - Review security group rules

2. **Monthly**:
   - Review and optimize costs
   - Update AMIs and apply patches
   - Review and rotate access logs
   - Check RDS backup retention

3. **Quarterly**:
   - Update Terraform provider versions
   - Review and update security policies
   - Conduct disaster recovery tests
   - Review and optimize instance types

### Updating the Infrastructure

```bash
# Update Terraform providers
terraform init -upgrade

# Plan changes
terraform plan -out=tfplan

# Apply changes during maintenance window
terraform apply tfplan

# Update Auto Scaling Group with zero downtime
terraform apply -target=aws_launch_template.app_tier
# ASG will automatically perform rolling update
```

### Backup and Disaster Recovery

**RDS Backups**:
- Automated daily backups with 7-30 day retention
- Manual snapshots before major changes
- Point-in-time recovery available

**S3 Versioning**:
- All application data versioned
- 90-day retention for old versions
- Cross-region replication (recommended for production)

**Infrastructure as Code**:
- Terraform state backed up in S3
- State file versioning enabled
- DynamoDB state locking prevents corruption

## Contributing

### Making Changes

1. Create a feature branch
2. Make changes and test in dev environment
3. Run `terraform fmt` and `terraform validate`
4. Create pull request with detailed description
5. Apply to staging for testing
6. Apply to production during maintenance window

### Code Standards

- Use consistent naming conventions
- Add comments for complex logic
- Tag all resources appropriately
- Follow least-privilege principle for IAM
- Enable encryption by default
- Use variables for configurable values

## License

This Terraform configuration is provided as-is for educational and production use.

## Support

For issues and questions:
- Review AWS documentation: https://docs.aws.amazon.com/
- Terraform documentation: https://www.terraform.io/docs
- AWS Support: https://console.aws.amazon.com/support/

---

**Last Updated**: 2024
**Terraform Version**: >= 1.5.0
**AWS Provider Version**: ~> 5.0