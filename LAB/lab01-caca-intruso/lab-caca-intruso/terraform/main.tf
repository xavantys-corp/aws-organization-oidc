# ══════════════════════════════════════════════════════════════════════════════
# Lab 01 — Caça ao Intruso | Terraform Infrastructure
# Cria: S3 (logs + resultados Athena), Athena workgroup+database, IAM alunos
# ══════════════════════════════════════════════════════════════════════════════

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

  # ─── Backend S3 para estado remoto (descomente e ajuste) ────────────────────
  # backend "s3" {
  #   bucket         = "fatec-lab01-terraform-state"
  #   key            = "lab01-caca-intruso/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "fatec-lab01-terraform-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region
}

# ─── Sufixo aleatório para evitar conflito de nomes de bucket ─────────────────
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  prefix      = "fatec-lab01"
  suffix      = random_id.suffix.hex
  bucket_logs = "${local.prefix}-cloudtrail-logs-${local.suffix}"
  bucket_ath  = "${local.prefix}-athena-results-${local.suffix}"
  db_name     = "lab_cloudtrail"
  wg_name     = "${local.prefix}-workgroup"

  # ─── Transforma lista de nomes completos → map(username => nome_completo) ──
  # username = primeiro.segundo (lowercase, sem acentos)
  alunos_map = {
    for idx, nome in var.alunos :
    local.normalize_username(nome) => {
      nome_completo = nome
      index         = idx
    }
  }

  # Helper: "João da Silva" → "joao.silva"
  # Strips accents via chained replace, splits by space, takes first + last word
  normalize_username = (nome) => join(".", [
    lower(replace(
      split(" ", replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(nome, "á", "a"), "à", "a"), "â", "a"), "ã", "a"), "é", "e"), "è", "e"), "ê", "e"), "í", "i"), "ï", "i"), "ó", "o"), "ô", "o"), "õ", "o"), "ö", "o"), "ú", "u"), "ü", "u"), "ç", "c"), "Á", "A"), "À", "A"), "Â", "A"), "Ã", "A"), "É", "E"), "È", "E"), "Ê", "E"), "Í", "I"), "Ï", "I"), "Ó", "O"), "Ô", "O"), "Õ", "O"), "Ö", "O"), "Ú", "U"), "Ü", "U"), "Ç", "C"))
    [0], "/[^a-zA-Z0-9]/", "")),
    lower(replace(
      split(" ", replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(nome, "á", "a"), "à", "a"), "â", "a"), "ã", "a"), "é", "e"), "è", "e"), "ê", "e"), "í", "i"), "ï", "i"), "ó", "o"), "ô", "o"), "õ", "o"), "ö", "o"), "ú", "u"), "ü", "u"), "ç", "c"), "Á", "A"), "À", "A"), "Â", "A"), "Ã", "A"), "É", "E"), "È", "E"), "Ê", "E"), "Í", "I"), "Ï", "I"), "Ó", "O"), "Ô", "O"), "Õ", "O"), "Ö", "O"), "Ú", "U"), "Ü", "U"), "Ç", "C"))
    [1], "/[^a-zA-Z0-9]/", ""))
  ])
}

# ══════════════════════════════════════════════════════════════════════════════
# S3 — Bucket de Logs (onde ficam os .json.gz do CloudTrail)
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_s3_bucket" "logs" {
  bucket        = local.bucket_logs
  force_destroy = true  # facilita cleanup após a aula

  tags = {
    Lab  = "lab01-caca-intruso"
    Role = "logs"
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Estrutura de prefixos para cada cenário
resource "aws_s3_object" "cenario_a" {
  bucket = aws_s3_bucket.logs.id
  key    = "AWSLogs/123456789012/CloudTrail/us-east-1/2024/03/15/cloudtrail_lab01_cenario_A.json.gz"
  source = "${path.module}/../logs/output/cloudtrail_lab01_cenario_A.json.gz"
  etag   = filemd5("${path.module}/../logs/output/cloudtrail_lab01_cenario_A.json.gz")

  tags = { Cenario = "A", Lab = "lab01" }
}

resource "aws_s3_object" "cenario_b" {
  bucket = aws_s3_bucket.logs.id
  key    = "AWSLogs/123456789012/CloudTrail/us-east-1/2024/03/16/cloudtrail_lab01_cenario_B.json.gz"
  source = "${path.module}/../logs/output/cloudtrail_lab01_cenario_B.json.gz"
  etag   = filemd5("${path.module}/../logs/output/cloudtrail_lab01_cenario_B.json.gz")

  tags = { Cenario = "B", Lab = "lab01" }
}

resource "aws_s3_object" "cenario_c" {
  bucket = aws_s3_bucket.logs.id
  key    = "AWSLogs/123456789012/CloudTrail/us-east-1/2024/03/17/cloudtrail_lab01_cenario_C.json.gz"
  source = "${path.module}/../logs/output/cloudtrail_lab01_cenario_C.json.gz"
  etag   = filemd5("${path.module}/../logs/output/cloudtrail_lab01_cenario_C.json.gz")

  tags = { Cenario = "C", Lab = "lab01" }
}

# ══════════════════════════════════════════════════════════════════════════════
# S3 — Bucket de Resultados do Athena
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_s3_bucket" "athena_results" {
  bucket        = local.bucket_ath
  force_destroy = true

  tags = {
    Lab  = "lab01-caca-intruso"
    Role = "athena-results"
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    id     = "cleanup-query-results"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 7 }  # resultados expiram em 7 dias
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# Athena — Workgroup e Database
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_athena_workgroup" "lab" {
  name          = local.wg_name
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = { Lab = "lab01-caca-intruso" }
}

resource "aws_athena_database" "lab" {
  name   = local.db_name
  bucket = aws_s3_bucket.athena_results.bucket

  force_destroy = true
  encryption_configuration {
    encryption_option = "SSE_S3"
  }
}

# Tabela CloudTrail no Glue Data Catalog (usada pelo Athena)
resource "aws_glue_catalog_table" "cloudtrail" {
  name          = "cloudtrail_logs"
  database_name = aws_athena_database.lab.name
  description   = "Logs CloudTrail para Lab 01 - Caça ao Intruso"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"            = "TRUE"
    "serialization.format" = "1"
    "projection.enabled"  = "false"
    "classification"      = "json"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.logs.bucket}/AWSLogs/"
    input_format  = "com.amazon.emr.cloudtrail.CloudTrailInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "com.amazon.emr.hive.serde.CloudTrailSerde"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "eventversion"
      type = "string"
    }
    columns {
      name = "useridentity"
      type = "struct<type:string,principalid:string,arn:string,accountid:string,invokedby:string,accesskeyid:string,username:string,sessioncontext:struct<attributes:struct<mfaauthenticated:string,creationdate:string>,sessionissuer:struct<type:string,principalid:string,arn:string,accountid:string,username:string>>>"
    }
    columns {
      name = "eventtime"
      type = "string"
    }
    columns {
      name = "eventsource"
      type = "string"
    }
    columns {
      name = "eventname"
      type = "string"
    }
    columns {
      name = "awsregion"
      type = "string"
    }
    columns {
      name = "sourceipaddress"
      type = "string"
    }
    columns {
      name = "useragent"
      type = "string"
    }
    columns {
      name = "errorcode"
      type = "string"
    }
    columns {
      name = "errormessage"
      type = "string"
    }
    columns {
      name = "requestparameters"
      type = "string"
    }
    columns {
      name = "responseelements"
      type = "string"
    }
    columns {
      name = "additionaleventdata"
      type = "string"
    }
    columns {
      name = "requestid"
      type = "string"
    }
    columns {
      name = "eventid"
      type = "string"
    }
    columns {
      name = "readonly"
      type = "boolean"
    }
    columns {
      name = "resources"
      type = "array<struct<arn:string,accountid:string,type:string>>"
    }
    columns {
      name = "eventtype"
      type = "string"
    }
    columns {
      name = "managementevent"
      type = "boolean"
    }
    columns {
      name = "recipientaccountid"
      type = "string"
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# IAM — Política e Usuários dos Alunos
# ══════════════════════════════════════════════════════════════════════════════

# Política mínima necessária para o lab (somente leitura + Athena + S3 específico)
resource "aws_iam_policy" "lab_policy" {
  name        = "${local.prefix}-aluno-policy"
  description = "Permissões mínimas para Lab 01 — Caça ao Intruso"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaQueryAccess"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:ListQueryExecutions",
          "athena:GetWorkGroup"
        ]
        Resource = aws_athena_workgroup.lab.arn
      },
      {
        Sid    = "AthenaCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:*:catalog",
          "arn:aws:glue:${var.aws_region}:*:database/${local.db_name}",
          "arn:aws:glue:${var.aws_region}:*:table/${local.db_name}/*"
        ]
      },
      {
        Sid    = "S3LogsReadOnly"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.logs.arn,
          "${aws_s3_bucket.logs.arn}/*"
        ]
      },
      {
        Sid    = "S3AthenaResultsReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.athena_results.arn,
          "${aws_s3_bucket.athena_results.arn}/*"
        ]
      },
      {
        Sid    = "ConsoleBucketList"
        Effect = "Allow"
        Action = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        Sid    = "AllowAthenaConsole"
        Effect = "Allow"
        Action = [
          "athena:ListWorkGroups",
          "athena:ListDataCatalogs",
          "athena:ListDatabases",
          "athena:ListTableMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─── Senhas aleatórias para cada aluno ────────────────────────────────────────
resource "random_password" "aluno" {
  for_each = local.alunos_map

  length           = 16
  special          = true
  override_special = "!@#$%&*_-+="
}

# Cria usuário IAM para cada aluno
resource "aws_iam_user" "aluno" {
  for_each = local.alunos_map

  name          = each.key
  force_destroy = true

  tags = {
    Lab   = "lab01-caca-intruso"
    Aluno = each.value.nome_completo
  }
}

# Perfil de login (acesso ao console) — usa senha aleatória
resource "aws_iam_user_login_profile" "aluno" {
  for_each = local.alunos_map

  user                    = aws_iam_user.aluno[each.key].name
  password                = random_password.aluno[each.key].result
  password_reset_required = true
}

# ─── Grupo IAM para os alunos ────────────────────────────────────────────────
resource "aws_iam_group" "lab" {
  name = "grupo_lab_incid_26"
  path = "/labs/"
}

# ─── Adiciona usuários ao grupo ─────────────────────────────────────────────
resource "aws_iam_group_membership" "aluno" {
  name  = "lab01-alunos-membership"
  group = aws_iam_group.lab.name
  users = [for u in aws_iam_user.aluno : u.name]
}

# ─── Anexa a política ao grupo (não aos usuários individualmente) ────────────
resource "aws_iam_group_policy_attachment" "lab" {
  group      = aws_iam_group.lab.name
  policy_arn = aws_iam_policy.lab_policy.arn
}
