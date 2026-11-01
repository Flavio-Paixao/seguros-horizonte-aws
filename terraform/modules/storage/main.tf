# ==========================================
# BUCKET 1: DADOS DA APLICAÇÃO
# ==========================================

# bucket_prefix: o Terraform acrescenta um sufixo aleatório.
# (Nomes de bucket são únicos no mundo; um nome fixo poderia já estar em uso.)
resource "aws_s3_bucket" "app_data" {
  bucket_prefix = "${var.project_name}-app-data-"

  tags = {
    Name = "${var.project_name}-app-data"
  }
}

# Bloqueio de acesso público (as 4 travas)
resource "aws_s3_bucket_public_access_block" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versionamento: guarda o histórico de cada arquivo
resource "aws_s3_bucket_versioning" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Criptografia em repouso com a NOSSA chave KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true # reduz chamadas ao KMS (e o custo)
  }
}

# Ciclo de vida: versões antigas esfriam e depois expiram
resource "aws_s3_bucket_lifecycle_configuration" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  rule {
    id     = "arquivar-versoes-antigas"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 2555 # 7 anos
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # O ciclo de vida de versões precisa que o versionamento já exista
  depends_on = [aws_s3_bucket_versioning.app_data]
}

# ==========================================
# BUCKET 2: BACKUPS
# ==========================================

resource "aws_s3_bucket" "backups" {
  bucket_prefix = "${var.project_name}-backups-"

  tags = {
    Name = "${var.project_name}-backups"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "apagar-backups-antigos"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

# ==========================================
# BUCKET 3: LOGS (sem versionamento)
# ==========================================

resource "aws_s3_bucket" "logs" {
  bucket_prefix = "${var.project_name}-logs-"

  tags = {
    Name = "${var.project_name}-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "arquivar-e-apagar-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = var.log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ==========================================
# POLICY: NEGAR QUALQUER ACESSO SEM HTTPS (nos 3 buckets)
# ==========================================

locals {
  # Mapa "apelido => bucket". Usado pelo for_each abaixo para não repetir código 3 vezes.
  buckets = {
    app_data = aws_s3_bucket.app_data
    backups  = aws_s3_bucket.backups
    logs     = aws_s3_bucket.logs
  }
}

data "aws_iam_policy_document" "tls_only" {
  for_each = local.buckets

  statement {
    sid     = "NegarTrafegoSemTLS"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      each.value.arn,
      "${each.value.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  for_each = local.buckets

  bucket = each.value.id
  policy = data.aws_iam_policy_document.tls_only[each.key].json

  # A policy só é aplicada depois do bloqueio de acesso público (evita conflito de ordem)
  depends_on = [
    aws_s3_bucket_public_access_block.app_data,
    aws_s3_bucket_public_access_block.backups,
    aws_s3_bucket_public_access_block.logs,
  ]
}
