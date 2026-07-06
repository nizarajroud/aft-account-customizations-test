# AWS Landing Zone Terraform Configuration

## Overview

This Terraform configuration deploys a production-ready AWS landing zone with a three-tier architecture spanning multiple availability zones. The infrastructure includes compute (EC2), storage (S3), and database (RDS) services with comprehensive security controls, encryption, and monitoring.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS Region                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                      │  │
│  │                                                           │  │
│  │  ┌─────────────────────┐  ┌─────────────────────┐       │  │
│  │  │   Availability      │  │   Availability      │       │  │
│  │  │   Zone A            │  │   Zone B            │       │  │
│  │  │                     │  │                     │       │  │
│  │  │  ┌──────────────┐   │  │  ┌──────────────┐   │       │  │
│  │  │  │Public Subnet │   │  │  │Public Subnet │   │       │  │
│  │  │  │              │   │  │  │              │   │       │  │
│  │  │  │  NAT Gateway │   │  │  │  NAT Gateway │   │       │  │
│  │  │  └──────────────┘   │  │  └──────────────┘   │       │  │
│  │  │         │           │  │         │           │       │  │
│  │  │  ┌──────────────┐   │  │  ┌──────────────┐   │       │  │
│  │  │  │Private Subnet│   │  │  │Private Subnet│   │       │  │
│  │  │  │              │   │  │  │              │   │       │  │
│  │  │  │  EC2 Instance│   │  │  │  EC2 Instance│   │       │  │
│  │  │  └──────────────┘   │  │  └──────────────┘   │       │  │
│  │  │         │           │  │         │           │       │  │
│  │  │  ┌──────────────┐   │  │  ┌──────────────┐   │       │  │
│  │  │  │Database      │   │  │  │Database      │   │       │  │
│  │  │  │Subnet        │   │  │  │Subnet        │   │       │  │
│  │  │  │              │   │  │  │              │   │       │  │
│  │  │  │  RDS (Multi-AZ)  │  │  │              │   │       │  │
│  │  │  └──────────────┘   │  │  └──────────────┘   │       │  │
│  │  └─────────────────────┘  └─────────────────────┘       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    S3 Buckets                             │  │
│  │  ┌──────────────────┐  ┌──────────────────┐              │  │
│  │  │ Application      │  │ Logs Bucket      │              │  │
│  │  │ Bucket           │  │                  │              │  │
│  │  └──────────────────┘  └──────────────────┘              │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Components Deployed

- **Networking**: VPC with public, private, and database subnets across 2 AZs
- **Compute**: EC2 instances in private subnets with SSM access
- **Storage**: Encrypted S3 buckets with versioning and lifecycle policies
- **Database**: RDS PostgreSQL with automated backups and encryption
- **Security**: KMS encryption, security groups, IAM roles, VPC Flow Logs
- **Monitoring**: CloudWatch Logs for VPC Flow Logs

## Prerequisites

### Required Tools

- **Terraform**: >= 1.5.0
- **AWS CLI**: >= 2.0 (configured with appropriate credentials)
- **Git**: For version control

### AWS Permissions

The IAM user/role executing this Terraform configuration requires the following permissions:

- EC2: Full access (VPC, Subnets, Security Groups, Instances, NAT Gateways)
- S3: Full access (Bucket creation, policies, encryption)
- RDS: Full access (Instance creation, subnet groups, parameter groups)
- IAM: Create and manage roles, policies, and instance profiles
- KMS: Create and manage encryption keys
- CloudWatch: Create log groups and configure logging
- Secrets Manager: Create and manage secrets

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. **Configure AWS credentials**:
   ```bash
   aws configure
   # Or use environment variables
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_DEFAULT_REGION="us-east-1"
   ```

3. **Create a `terraform.tfvars` file**:
   ```hcl
   aws_region         = "us-east-1"
   environment        = "dev"
   project_name       = "my-project"
   ec2_instance_count = 2
   rds_multi_az       = false  # Set to true for production
   ```

4. **Create `user_data.sh` file** (referenced in ec2.tf):
   ```bash
   #!/bin/bash
   # Basic user data script
   yum update -y
   yum install -y amazon-cloudwatch-agent
   
   # Configure CloudWatch agent
   echo "Environment: ${environment}" > /etc/environment
   echo "Region: ${region}" >> /etc/environment
   ```

## Usage

### Initialize Terraform

```bash
terraform init
```

This command downloads the required providers and initializes the backend.

### Plan the Deployment

```bash
terraform plan -out=tfplan
```

Review the planned changes carefully. This will show you all resources that will be created.

### Apply the Configuration

```bash
terraform apply tfplan
```

Or apply directly with approval prompt:

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

### Deployment Time

Expected deployment time: **15-20 minutes**

- VPC and networking: 5-7 minutes
- EC2 instances: 3-5 minutes
- RDS instance: 8-12 minutes
- S3 buckets and IAM: 1-2 minutes

### Destroy Infrastructure

To tear down all resources:

```bash
terraform destroy
```

**Warning**: This will delete all resources including data in S3 and RDS. Ensure you have backups before proceeding.

## Variables

### Input Variables

| Variable | Type | Default | Description | Required |
|----------|------|---------|-------------|----------|
| `aws_region` | string | `us-east-1` | AWS region for resource deployment | No |
| `environment` | string | `dev` | Environment name (dev, staging, prod) | No |
| `project_name` | string | `landing-zone` | Project name for resource tagging | No |
| `vpc_cidr` | string | `10.0.0.0/16` | CIDR block for VPC | No |
| `availability_zones` | list(string) | `["us-east-1a", "us-east-1b"]` | List of availability zones | No |
| `ec2_instance_type` | string | `t3.micro` | EC2 instance type | No |
| `ec2_ami` | string | `""` | AMI ID for EC2 instances (auto-detected if empty) | No |
| `ec2_instance_count` | number | `2` | Number of EC2 instances to create | No |
| `s3_bucket_prefix` | string | `landing-zone` | Prefix for S3 bucket names | No |
| `enable_s3_versioning` | bool | `true` | Enable versioning for S3 buckets | No |
| `rds_instance_class` | string | `db.t3.micro` | RDS instance class | No |
| `rds_engine` | string | `postgres` | RDS database engine | No |
| `rds_engine_version` | string | `15.4` | RDS engine version | No |
| `rds_allocated_storage` | number | `20` | Allocated storage for RDS in GB | No |
| `rds_database_name` | string | `appdb` | Name of the initial database | No |
| `rds_master_username` | string | `dbadmin` | Master username for RDS | No |
| `rds_backup_retention_period` | number | `7` | Number of days to retain backups | No |
| `rds_multi_az` | bool | `false` | Enable Multi-AZ deployment for RDS | No |

### Variable Validation

The configuration includes validation rules:

- **environment**: Must be one of `dev`, `staging`, or `prod`
- **rds_master_password**: Automatically generated with 32 characters

### Environment-Specific Configurations

**Development**:
```hcl
environment        = "dev"
ec2_instance_count = 1
rds_multi_az       = false
rds_instance_class = "db.t3.micro"
```

**Staging**:
```hcl
environment        = "staging"
ec2_instance_count = 2
rds_multi_az       = false
rds_instance_class = "db.t3.small"
```

**Production**:
```hcl
environment        = "prod"
ec2_instance_count = 4
rds_multi_az       = true
rds_instance_class = "db.t3.medium"
```

## Outputs

The configuration provides the following outputs (add to `outputs.tf`):

| Output | Description |
|--------|-------------|
| `vpc_id` | ID of the created VPC |
| `vpc_cidr` | CIDR block of the VPC |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `database_subnet_ids` | List of database subnet IDs |
| `ec2_instance_ids` | List of EC2 instance IDs |
| `ec2_private_ips` | Private IP addresses of EC2 instances |
| `s3_application_bucket_name` | Name of the application S3 bucket |
| `s3_application_bucket_arn` | ARN of the application S3 bucket |
| `s3_logs_bucket_name` | Name of the logs S3 bucket |
| `rds_endpoint` | RDS instance endpoint |
| `rds_database_name` | Name of the RDS database |
| `rds_secret_arn` | ARN of the Secrets Manager secret containing RDS credentials |
| `kms_key_id` | ID of the KMS encryption key |
| `kms_key_arn` | ARN of the KMS encryption key |

### Accessing Outputs

```bash
# View all outputs
terraform output

# View specific output
terraform output rds_endpoint

# Output in JSON format
terraform output -json
```

### Retrieving RDS Credentials

```bash
# Get the secret ARN
SECRET_ARN=$(terraform output -raw rds_secret_arn)

# Retrieve credentials from Secrets Manager
aws secretsmanager get-secret-value --secret-id $SECRET_ARN --query SecretString --output text | jq .
```

## Security

This configuration implements comprehensive security controls following AWS best practices:

### Encryption at Rest

- **KMS Encryption**: All data is encrypted using AWS KMS with automatic key rotation enabled
  - EBS volumes (EC2 root volumes)
  - RDS database storage
  - S3 buckets (application and logs)
  - CloudWatch Logs
  - Secrets Manager secrets

### Encryption in Transit

- **RDS**: SSL/TLS enforced for all database connections (`rds.force_ssl = 1`)
- **S3**: Bucket policies deny non-HTTPS requests
- **EC2**: IMDSv2 required for instance metadata access

### Network Security

- **Network Segmentation**: Three-tier architecture with isolated subnets
  - Public subnets: NAT Gateways only
  - Private subnets: Application servers (no direct internet access)
  - Database subnets: Completely isolated (no internet access)

- **Security Groups**: Least-privilege access controls
  - ALB: Accepts HTTP/HTTPS from internet
  - EC2: Only accepts traffic from ALB
  - RDS: Only accepts traffic from EC2 instances on port 5432

- **VPC Flow Logs**: All network traffic logged to CloudWatch for audit and analysis

### Identity and Access Management

- **IAM Roles**: EC2 instances use IAM roles (no long-term credentials)
- **Least Privilege**: EC2 role has minimal permissions:
  - SSM Session Manager access (no SSH keys required)
  - Read-only access to application S3 bucket
  
- **Instance Metadata Service**: IMDSv2 enforced (prevents SSRF attacks)

### Data Protection

- **S3 Bucket Policies**:
  - Block all public access
  - Require secure transport (HTTPS)
  - Restrict access to specific IAM roles

- **S3 Versioning**: Enabled on application bucket for data recovery
- **RDS Backups**: Automated daily backups with 7-day retention
- **RDS Multi-AZ**: Optional high availability configuration

### Secrets Management

- **Secrets Manager**: RDS master password stored securely
- **Automatic Rotation**: Can be configured for password rotation
- **Encryption**: Secrets encrypted with KMS

### Monitoring and Logging

- **VPC Flow Logs**: Network traffic monitoring
- **RDS Query Logging**: All SQL statements logged
- **CloudWatch Logs**: Centralized log aggregation
- **S3 Access Logging**: Audit trail for bucket access

### Compliance Features

- **Deletion Protection**: Enabled for RDS in production environments
- **Final Snapshots**: Automatic snapshot before RDS deletion (production)
- **Tag Enforcement**: All resources tagged with environment and project
- **Audit Trail**: CloudTrail integration ready (add separately)

## Cost Estimation

Approximate monthly costs for **ca-central-1** region (Canadian pricing in USD):

### Development Environment

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| **EC2** | 1x t3.micro (730 hours) | $8.76 |
| **EBS** | 20 GB gp3 | $2.00 |
| **NAT Gateway** | 2x NAT Gateways | $64.60 |
| **NAT Data Transfer** | ~100 GB | $4.50 |
| **RDS** | 1x db.t3.micro (730 hours) | $14.60 |
| **RDS Storage** | 20 GB gp3 | $2.76 |
| **RDS Backup** | 20 GB backup storage | $2.00 |
| **S3 Storage** | 50 GB Standard | $1.38 |
| **S3 Requests** | 100K PUT, 1M GET | $0.55 |
| **KMS** | 1 key + 10K requests | $1.10 |
| **Secrets Manager** | 1 secret | $0.40 |
| **CloudWatch Logs** | 5 GB ingestion + storage | $2.65 |
| **VPC Flow Logs** | ~10 GB/month | $0.50 |
| **Data Transfer** | 50 GB outbound | $4.50 |
| **Total** | | **~$110/month** |

### Production Environment

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| **EC2** | 4x t3.small (730 hours) | $70.08 |
| **EBS** | 80 GB gp3 (4x 20 GB) | $8.00 |
| **NAT Gateway** | 2x NAT Gateways | $64.60 |
| **NAT Data Transfer** | ~500 GB | $22.50 |
| **RDS** | 1x db.t3.medium Multi-AZ | $116.80 |
| **RDS Storage** | 100 GB gp3 | $13.80 |
| **RDS Backup** | 100 GB backup storage | $10.00 |
| **S3 Storage** | 500 GB Standard | $13.80 |
| **S3 Requests** | 1M PUT, 10M GET | $5.40 |
| **KMS** | 1 key + 100K requests | $1.30 |
| **Secrets Manager** | 1 secret | $0.40 |
| **CloudWatch Logs** | 50 GB ingestion + storage | $26.50 |
| **VPC Flow Logs** | ~50 GB/month | $2.50 |
| **Data Transfer** | 500 GB outbound | $45.00 |
| **Total** | | **~$400/month** |

### Cost Optimization Recommendations

1. **NAT Gateway**: Largest cost component
   - Consider using NAT instances for dev/staging
   - Use VPC endpoints for AWS services (S3, DynamoDB)
   - Consolidate to single NAT Gateway for non-production

2. **RDS**:
   - Use Aurora Serverless for variable workloads
   - Consider Reserved Instances for production (40-60% savings)
   - Disable Multi-AZ in non-production environments

3. **EC2**:
   - Use Savings Plans or Reserved Instances (up to 72% savings)
   - Right-size instances based on actual usage
   - Use Auto Scaling to match demand

4. **S3**:
   - Implement lifecycle policies (already configured)
   - Use S3 Intelligent-Tiering for unpredictable access patterns
   - Enable S3 Transfer Acceleration only if needed

5. **Data Transfer**:
   - Use CloudFront for content delivery
   - Keep data transfer within same region
   - Use VPC endpoints to avoid NAT Gateway charges

### Budget Alerts

Set up AWS Budgets to monitor costs:

```bash
aws budgets create-budget \
  --account-id <account-id> \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json
```

## Well-Architected Review

This configuration aligns with the AWS Well-Architected Framework across all six pillars:

### 1. Operational Excellence

**Design Principles Implemented**:

- ✅ **Infrastructure as Code**: Entire infrastructure defined in Terraform
- ✅ **Annotated Documentation**: Comprehensive inline comments and README
- ✅ **Frequent, Small Changes**: Modular design enables incremental updates
- ✅ **Monitoring**: CloudWatch Logs, VPC Flow Logs, RDS query logging
- ✅ **Failure Anticipation**: Multi-AZ deployment option, automated backups

**Best Practices**:
- Consistent tagging strategy for resource organization
- Version control ready (Git)
- Automated deployment process
- Separate environments (dev/staging/prod)

**Recommendations**:
- Implement AWS Systems Manager for operational insights
- Add CloudWatch dashboards and alarms
- Configure SNS notifications for critical events
- Implement automated testing (Terratest)

### 2. Security

**Design Principles Implemented**:

- ✅ **Strong Identity Foundation**: IAM roles with least privilege
- ✅ **Traceability**: VPC Flow Logs, S3 access logs, RDS query logs
- ✅ **Security at All Layers**: Network, application, and data layer controls
- ✅ **Encryption**: KMS encryption for all data at rest and in transit
- ✅ **Automated Security**: Security groups, NACLs, bucket policies
- ✅ **Data Protection**: Versioning, backups, Multi-AZ option

**Best Practices**:
- No hardcoded credentials (Secrets Manager)
- IMDSv2 enforced on EC2 instances
- Private subnets for application and database tiers
- Security group rules follow least privilege
- S3 buckets block all public access

**Recommendations**:
- Enable AWS GuardDuty for threat detection
- Implement AWS Config for compliance monitoring
- Add AWS WAF for application layer protection
- Enable AWS Security Hub for centralized security view
- Implement AWS Systems Manager Session Manager (already configured)

### 3. Reliability

**Design Principles Implemented**:

- ✅ **Automatic Recovery**: RDS automated backups, Multi-AZ option
- ✅ **Horizontal Scaling**: Multiple EC2 instances across AZs
- ✅ **Capacity Planning**: Configurable instance counts and sizes
- ✅ **Change Management**: Terraform state management

**Best Practices**:
- Multi-AZ deployment for high availability
- Automated backups with 7-day retention
- NAT Gateways in each AZ for redundancy
- S3 versioning for data recovery

**Recommendations**:
- Implement Application Load Balancer with health checks
- Add Auto Scaling Groups for EC2 instances
- Configure RDS read replicas for read-heavy workloads
- Implement Route 53 health checks and failover
- Add CloudWatch alarms for proactive monitoring

### 4. Performance Efficiency

**Design Principles Implemented**:

- ✅ **Advanced Technologies**: Managed services (RDS, S3)
- ✅ **Global Deployment**: Multi-AZ architecture
- ✅ **Serverless**: S3 for storage (serverless by nature)
- ✅ **Experimentation**: Easy to test different instance types

**Best Practices**:
- gp3 volumes for cost-effective performance
- Latest generation instance types (t3, db.t3)
- S3 lifecycle policies for storage optimization
- VPC endpoints ready for AWS service access

**Recommendations**:
- Implement CloudFront for content delivery
- Add ElastiCache for database caching
- Use RDS Performance Insights
- Implement Auto Scaling based on metrics
- Consider Aurora for better database performance

### 5. Cost Optimization

**Design Principles Implemented**:

- ✅ **Consumption-Based Pricing**: Pay only for what you use
- ✅ **Cost-Effective Resources**: t3/t3.micro instances for variable workloads
- ✅ **Expenditure Awareness**: Comprehensive tagging strategy
- ✅ **Right Sizing**: Configurable instance sizes per environment

**Best Practices**:
- S3 lifecycle policies (transition to IA and Glacier)
- gp3 volumes (20% cheaper than gp2)
- Separate environments to avoid over-provisioning
- KMS key reuse across services

**Recommendations**:
- Implement AWS Cost Explorer and Budgets
- Use Savings Plans or Reserved Instances for production
- Replace NAT Gateways with NAT instances in dev/staging
- Implement S3 Intelligent-Tiering
- Use Spot Instances for non-critical workloads

### 6. Sustainability

**Design Principles Implemented**:

- ✅ **Maximize Utilization**: Right-sized instances
- ✅ **Managed Services**: Offload operational burden to AWS
- ✅ **Reduce Downstream Impact**: Efficient data transfer patterns

**Best Practices**:
- Latest generation instances (better performance per watt)
- S3 lifecycle policies reduce storage footprint
- Multi-AZ deployment in same region (reduced data transfer)
- Efficient network design with private subnets

**Recommendations**:
- Implement Auto Scaling to match demand
- Use AWS Graviton instances (ARM-based, more efficient)
- Implement data compression for S3 and RDS
- Schedule non-production resources to run only during business hours
- Use AWS Compute Optimizer for right-sizing recommendations

## Troubleshooting

### Common Issues

**1. Terraform Init Fails**

```bash
Error: Failed to query available provider packages
```

**Solution**: Check internet connectivity and Terraform registry access:
```bash
terraform init -upgrade
```

**2. Insufficient IAM Permissions**

```bash
Error: creating EC2 Instance: UnauthorizedOperation
```

**Solution**: Verify IAM permissions include all required services. Review the Prerequisites section.

**3. Resource Already Exists**

```bash
Error: creating S3 Bucket: BucketAlreadyExists
```

**Solution**: S3 bucket names must be globally unique. The configuration uses random suffixes, but if you're re-applying after a failed destroy, wait 24 hours or change the `s3_bucket_prefix` variable.

**4. RDS Creation Timeout**

```bash
Error: waiting for RDS Instance creation: timeout
```

**Solution**: RDS creation can take 10-15 minutes. Increase timeout or check AWS console for specific errors.

**5. VPC CIDR Conflicts**

```bash
Error: creating VPC: InvalidVpc.Range
```

**Solution**: Ensure `vpc_cidr` doesn't conflict with existing VPCs in your account.

### Accessing EC2 Instances

**Using AWS Systems Manager Session Manager** (recommended):

```bash
# List instances
aws ec2 describe-instances --filters "Name=tag:Project,Values=landing-zone" \
  --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Start session
aws ssm start-session --target <instance-id>
```

**No SSH keys required!** Session Manager provides secure access without managing SSH keys.

### Retrieving RDS Connection Information

```bash
# Get RDS endpoint
terraform output rds_endpoint

# Get database credentials from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw rds_secret_arn) \
  --query SecretString \
  --output text | jq -r '.password'
```

### Viewing Logs

**VPC Flow Logs**:
```bash
aws logs tail /aws/vpc/landing-zone-dev-flow-logs --follow
```

**RDS Logs**:
```bash
aws rds describe-db-log-files --db-instance-identifier landing-zone-dev-postgres
aws rds download-db-log-file-portion --db-instance-identifier landing-zone-dev-postgres \
  --log-file-name error/postgresql.log.2024-01-15-00
```

## Maintenance

### Regular Tasks

**Weekly**:
- Review CloudWatch Logs for anomalies
- Check AWS Cost Explorer for unexpected charges
- Review VPC Flow Logs for security events

**Monthly**:
- Update Terraform providers: `terraform init -upgrade`
- Review and rotate IAM access keys
- Test RDS backup restoration
- Review S3 lifecycle policy effectiveness

**Quarterly**:
- Review and update AMIs
- Evaluate instance right-sizing opportunities
- Review and update security group rules
- Conduct disaster recovery drill

### Updating the Infrastructure

1. **Update variables** in `terraform.tfvars`
2. **Plan changes**: `terraform plan -out=tfplan`
3. **Review changes** carefully
4. **Apply changes**: `terraform apply tfplan`

### Backup and Disaster Recovery

**RDS Backups**:
- Automated daily backups (7-day retention)
- Manual snapshots before major changes:
  ```bash
  aws rds create-db-snapshot \
    --db-instance-identifier landing-zone-dev-postgres \
    --db-snapshot-identifier manual-backup-$(date +%Y%m%d)
  ```

**S3 Versioning**:
- Enabled on application bucket
- Recover deleted objects:
  ```bash
  aws s3api list-object-versions --bucket <bucket-name> --prefix <key>
  aws s3api get-object --bucket <bucket-name> --key <key> --version-id <version-id> <output-file>
  ```

**Terraform State**:
- Store in S3 with versioning enabled (configure backend)
- Enable state locking with DynamoDB
- Regular state backups:
  ```bash
  terraform state pull > terraform.tfstate.backup
  ```

## Contributing

### Making Changes

1. Create a feature branch
2. Make changes and test locally
3. Run `terraform fmt` to format code
4. Run `terraform validate` to check syntax
5. Submit pull request with description

### Code Standards

- Use meaningful resource names
- Add comments for complex logic
- Follow the existing naming convention: `${project}-${environment}-${resource}`
- Tag all resources appropriately
- Document all variables and outputs

## Support

### Getting Help

- **AWS Documentation**: https://docs.aws.amazon.com/
- **Terraform Documentation**: https://www.terraform.io/docs
- **AWS Support**: Open a support case in AWS Console
- **Community**: AWS re:Post, HashiCorp Discuss

### Reporting Issues

When reporting issues, include:
- Terraform version: `terraform version`
- AWS provider version
- Error messages (sanitize sensitive data)
- Steps to reproduce
- Expected vs actual behavior

## License

This configuration is provided as-is for educational and production use. Modify as needed for your specific requirements.

## Acknowledgments

- AWS Well-Architected Framework
- Terraform AWS Provider Documentation
- AWS Security Best Practices

---

**Last Updated**: January 2024  
**Terraform Version**: >= 1.5.0  
**AWS Provider Version**: ~> 5.0