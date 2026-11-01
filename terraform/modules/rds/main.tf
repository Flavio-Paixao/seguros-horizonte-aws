# ==========================================
# VERSÃO DO MOTOR (fixa, conferida na AWS)
# ==========================================
# A versão vem da variável engine_version (ver DECISIONS 4.9). Antes ela era
# descoberta por um data source (aws_rds_engine_version), mas as duas
# tentativas falharam na API real (KAN-9): primeiro com
# "InvalidParameterCombination" e depois com "no RDS engine versions found",
# embora `aws rds describe-db-engine-versions` liste a família 15 em sa-east-1.
# Fixar a versão tira essa consulta do caminho e deixa o plan reproduzível.

# ==========================================
# CLASSE DA INSTÂNCIA (conferida na AWS)
# ==========================================
# O plan não confere se a classe existe para este motor nesta região: esse
# erro só apareceria no apply. Este data source pergunta à AWS (no plan) se
# a combinação motor + versão + classe pode ser criada em sa-east-1 e se ela
# suporta o que usamos (Performance Insights e Enhanced Monitoring).
# Se não puder, o plan falha aqui, com uma mensagem clara.
data "aws_rds_orderable_db_instance" "aurora" {
  engine         = "aurora-postgresql"
  engine_version = var.engine_version

  # Lista com um item só: o Aurora devolve uma opção por tipo de storage
  # (aurora e aurora-iopt1); a lista faz o data source aceitar a primeira.
  preferred_instance_classes = [var.instance_class]

  supports_performance_insights = true
  supports_enhanced_monitoring  = true
}

# ==========================================
# SUBNET GROUP (onde o banco pode ficar)
# ==========================================
# Lista as subnets privadas. Precisa de 2 AZs diferentes.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ==========================================
# PARAMETER GROUP DO CLUSTER (configurações do PostgreSQL)
# ==========================================
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project_name}-aurora-cluster-pg"
  family      = "aurora-postgresql15"
  description = "Parametros customizados do Aurora PostgreSQL"

  # Registra no log apenas comandos que alteram estrutura (CREATE, ALTER, DROP).
  # "all" geraria log gigante e custo no CloudWatch.
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  # Registra consultas que demoram mais de 1 segundo (valor em milissegundos)
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = {
    Name = "${var.project_name}-aurora-cluster-pg"
  }
}

# ==========================================
# CLUSTER AURORA
# ==========================================
resource "aws_rds_cluster" "aurora" {
  #checkov:skip=CKV2_AWS_8:Backup nativo do Aurora (7 dias) em vez de AWS Backup (DECISIONS 4.11)
  #checkov:skip=CKV_AWS_139:Projeto de estudo precisa poder ser destruido (DECISIONS 4.8, pendencia 5)
  cluster_identifier = "${var.project_name}-aurora-cluster"
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version
  database_name      = var.db_name

  # SENHA: a AWS gera e guarda no Secrets Manager. Nada de senha no código.
  master_username             = var.db_username
  manage_master_user_password = true

  # Rede
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id] # SG do banco: só aceita 5432 vindo do SG da app

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  # Backup e manutenção (horários em UTC; não podem se sobrepor)
  backup_retention_period      = 7
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  # Logs do PostgreSQL vão para o CloudWatch
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Criptografia em repouso com a NOSSA chave
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Autenticação por token IAM (opcional, fica habilitada)
  iam_database_authentication_enabled = true

  # PROJETO DE ESTUDO: permite destruir sem travar.
  # EM PRODUÇÃO REAL: deletion_protection = true e skip_final_snapshot = false
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "${var.project_name}-aurora-cluster"
  }

  # A AWS atualiza versões menores sozinha; sem isto o Terraform "brigaria" com ela.
  lifecycle {
    ignore_changes = [engine_version]
  }
}

# ==========================================
# INSTÂNCIAS DO CLUSTER
# ==========================================
# A primeira instância criada vira a primária (escrita).
resource "aws_rds_cluster_instance" "primary" {
  identifier         = "${var.project_name}-aurora-primary"
  cluster_identifier = aws_rds_cluster.aurora.id
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  instance_class     = data.aws_rds_orderable_db_instance.aurora.instance_class
  availability_zone  = var.azs[0] # writer na 1a

  db_subnet_group_name       = aws_db_subnet_group.main.name
  publicly_accessible        = false # sem IP público; e as subnets privadas não têm rota para o IGW
  auto_minor_version_upgrade = true

  # Enhanced Monitoring: métricas do sistema operacional a cada 60 s
  monitoring_interval = 60
  monitoring_role_arn = var.rds_monitoring_role_arn

  # Performance Insights: painel que mostra quais consultas pesam mais
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn # mesma chave do banco (checkov CKV_AWS_354)

  tags = {
    Name = "${var.project_name}-aurora-primary"
  }

  lifecycle {
    ignore_changes = [engine_version]
  }
}

# Réplica de leitura. Se a primária cair, ela assume (promotion_tier = 1).
resource "aws_rds_cluster_instance" "replica" {
  identifier         = "${var.project_name}-aurora-replica"
  cluster_identifier = aws_rds_cluster.aurora.id
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  instance_class     = data.aws_rds_orderable_db_instance.aurora.instance_class
  availability_zone  = var.azs[1] # reader na 1b

  db_subnet_group_name       = aws_db_subnet_group.main.name
  publicly_accessible        = false # sem IP público; e as subnets privadas não têm rota para o IGW
  auto_minor_version_upgrade = true
  promotion_tier             = 1

  monitoring_interval = 60
  monitoring_role_arn = var.rds_monitoring_role_arn

  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn # mesma chave do banco (checkov CKV_AWS_354)

  tags = {
    Name = "${var.project_name}-aurora-replica"
  }

  # Garante que a primária seja criada primeiro (vira a escritora)
  depends_on = [aws_rds_cluster_instance.primary]

  lifecycle {
    ignore_changes = [engine_version]
  }
}
