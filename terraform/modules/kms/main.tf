# ==========================================
# DATA SOURCES (conta e região, para montar ARNs e condições exatas)
# ==========================================
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  account_root = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  region       = data.aws_region.current.name
}

# ==========================================
# KEY POLICY DE MÍNIMO PRIVILÉGIO
# ==========================================
# Duas regras em cada chave, separando QUEM ADMINISTRA de QUEM USA:
#
# 1) Administração: a conta (via IAM) pode gerenciar a chave (ver, rotacionar,
#    mudar a policy, agendar exclusão), mas NÃO pode criptografar/descriptografar
#    direto. Manter a conta aqui evita "chave órfã" (ninguém consegue mais mexer).
#
# 2) Uso: as operações de criptografia só valem quando a chamada passa pelo
#    serviço certo (kms:ViaService) e vem desta conta (kms:CallerAccount).
#    Chave do banco -> só via RDS. Chave do S3 -> só via S3.
#    Mesmo um usuário com kms:Decrypt no IAM não abre os dados chamando o KMS direto.

locals {
  key_admin_actions = [
    "kms:CreateAlias", # não "kms:Create*": isso incluiria CreateGrant sem as condições abaixo
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Put*",
    "kms:Update*",
    "kms:Revoke*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
  ]

  key_usage_actions = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
  ]
}

data "aws_iam_policy_document" "rds_key" {
  statement {
    sid       = "KeyAdministration"
    effect    = "Allow"
    actions   = local.key_admin_actions
    resources = ["*"] # numa key policy, "*" significa "esta chave"

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  statement {
    sid       = "UseOnlyThroughRDS"
    effect    = "Allow"
    actions   = local.key_usage_actions
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["rds.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }

  # O RDS cria "grants" para usar a chave em segundo plano (backups, réplicas).
  # Só permitimos grant quando é para um recurso da AWS, nunca para uma pessoa.
  statement {
    sid       = "AllowRDSGrants"
    effect    = "Allow"
    actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["rds.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "s3_key" {
  statement {
    sid       = "KeyAdministration"
    effect    = "Allow"
    actions   = local.key_admin_actions
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  statement {
    sid       = "UseOnlyThroughS3"
    effect    = "Allow"
    actions   = local.key_usage_actions
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }
}

# ==========================================
# CHAVE DO BANCO DE DADOS (RDS / Aurora)
# ==========================================
resource "aws_kms_key" "rds" {
  description             = "Chave KMS do banco Aurora (${var.project_name})"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true # troca o material criptográfico todo ano, sozinha
  policy                  = data.aws_iam_policy_document.rds_key.json

  tags = {
    Name = "${var.project_name}-rds-key"
  }
}

# O alias é um "apelido" legível. Sem ele, você só enxerga um ID tipo 1234abcd-....
resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ==========================================
# CHAVE DOS BUCKETS S3 (usada na Fase 7)
# ==========================================
# Chave separada da do banco: se uma vazar ou for desativada, a outra não é afetada
# (raio de impacto menor), e cada uma tem sua própria trilha no CloudTrail.
resource "aws_kms_key" "s3" {
  description             = "Chave KMS dos buckets S3 (${var.project_name})"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.s3_key.json

  tags = {
    Name = "${var.project_name}-s3-key"
  }
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.project_name}-s3"
  target_key_id = aws_kms_key.s3.key_id
}
