# ==========================================
# DATA SOURCES E LOCALS
# ==========================================

# ID da conta, para montar ARNs exatos (sem curinga de conta)
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # ARNs do Aurora do projeto (nomes definidos no módulo rds: <projeto>-aurora-*)
  rds_arns = [
    "arn:aws:rds:${var.aws_region}:${local.account_id}:cluster:${var.project_name}-*",
    "arn:aws:rds:${var.aws_region}:${local.account_id}:db:${var.project_name}-*",
  ]

  # Fase 7: bucket (para ListBucket) + objetos dentro dele (Get/Put/Delete)
  s3_resources = concat(
    var.app_bucket_arns,
    [for arn in var.app_bucket_arns : "${arn}/*"],
  )
}

# ==========================================
# ROLE 1: EC2-ROLE
# ==========================================

# Trust policy: QUEM pode assumir a role (só o serviço EC2)
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

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

# S3: só os 3 buckets do projeto (ARNs exatos vindos do módulo storage)
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
        Resource = local.s3_resources
      }
    ]
  })
}

# RDS: Describe só nos recursos do projeto (L5).
# rds:DescribeDBSecurityGroups removido (L6): é do EC2-Classic, não existe em VPC.
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
          "rds:DescribeDBClusters"
        ]
        Resource = local.rds_arns
      }
    ]
  })
}

# CloudWatch Logs: só na região do projeto e só nos grupos /aws/ec2/*
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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/ec2/*"
      }
    ]
  })
}

# SSM: acesso à instância sem SSH (Session Manager)
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile: o "envelope" que liga a role à instância EC2
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

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ==========================================
# ROLE 3: LAMBDA-ROLE (preparada para processar arquivos do S3 no futuro)
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

# S3: só os 3 buckets do projeto
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
        Resource = local.s3_resources
      }
    ]
  })
}

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
        Resource = local.rds_arns
      }
    ]
  })
}

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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/*"
      }
    ]
  })
}

# Necessária para a Lambda rodar dentro da VPC (cria ENIs)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ==========================================
# FASE 5: EC2 LÊ A SENHA DO BANCO NO SECRETS MANAGER
# ==========================================

# Os segredos que o RDS cria sozinho têm nome começando com "rds!cluster-".
# Só GetSecretValue, só na região e conta do projeto, só segredos do RDS.
resource "aws_iam_role_policy" "ec2_db_secret" {
  name = "${var.project_name}-ec2-db-secret"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!cluster-*"
      }
    ]
  })
}

# ==========================================
# FASE 7: USAR A CHAVE KMS DO S3 (só via S3)
# ==========================================

# Bucket criptografado com chave própria: ler/gravar exige permissão no S3 E na chave.
# Resource = ARN exato da chave; kms:ViaService impede usar a chave fora do S3.
resource "aws_iam_role_policy" "ec2_kms_s3" {
  name = "${var.project_name}-ec2-kms-s3"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = var.s3_kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_kms_s3" {
  name = "${var.project_name}-lambda-kms-s3"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = var.s3_kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}
