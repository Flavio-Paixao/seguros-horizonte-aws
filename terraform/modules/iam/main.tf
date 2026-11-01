# ==========================================
# DATA SOURCES - Get AWS Account ID
# ==========================================

data "aws_caller_identity" "current" {}

# ==========================================
# ROLE 1: EC2-ROLE
# ==========================================

# Assume role policy (quem pode usar)
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Create the role
resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# ==========================================
# EC2 POLICIES
# ==========================================

# Policy: S3 Access
resource "aws_iam_role_policy" "ec2_s3_access" {
  name = "${var.project_name}-ec2-s3-access"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      }
    ]
  })
}

# Policy: RDS Access
resource "aws_iam_role_policy" "ec2_rds_access" {
  name = "${var.project_name}-ec2-rds-access"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:DescribeDBSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# Policy: CloudWatch Logs
resource "aws_iam_role_policy" "ec2_cloudwatch_logs" {
  name = "${var.project_name}-ec2-cloudwatch-logs"
  role = aws_iam_role.ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/*"
      }
    ]
  })
}

# Policy: SSM (para conectar na instância)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile (para associar role com EC2)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ==========================================
# ROLE 2: RDS-ENHANCED-MONITORING
# ==========================================

data "aws_iam_policy_document" "rds_monitoring_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring_role" {
  name               = "${var.project_name}-rds-monitoring-role"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json

  tags = {
    Name = "${var.project_name}-rds-monitoring-role"
  }
}

# Attach AWS managed policy for RDS monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ==========================================
# ROLE 3: LAMBDA-ROLE
# ==========================================

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# Lambda: S3 Access
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${var.project_name}-lambda-s3-access"
  role = aws_iam_role.lambda_role.id
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
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      }
    ]
  })
}

# Lambda: RDS Access
resource "aws_iam_role_policy" "lambda_rds_access" {
  name = "${var.project_name}-lambda-rds-access"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda: CloudWatch Logs
resource "aws_iam_role_policy" "lambda_cloudwatch_logs" {
  name = "${var.project_name}-lambda-cloudwatch-logs"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      }
    ]
  })
}

# Lambda: VPC Execution
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}