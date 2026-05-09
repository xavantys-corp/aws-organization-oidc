# ══════════════════════════════════════════════════════════════════════════════
# outputs.tf — Lab 01 Caça ao Intruso
# Exibe tudo que o professor precisa enviar aos alunos
# ══════════════════════════════════════════════════════════════════════════════

output "bucket_logs" {
  description = "Bucket S3 com os logs CloudTrail do lab"
  value       = aws_s3_bucket.logs.bucket
}

output "bucket_athena_results" {
  description = "Bucket S3 de resultados das queries Athena"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_workgroup" {
  description = "Nome do workgroup Athena — alunos devem selecionar este"
  value       = aws_athena_workgroup.lab.name
}

output "athena_database" {
  description = "Nome do banco de dados no Athena"
  value       = aws_athena_database.lab.name
}

output "athena_table" {
  description = "Nome da tabela CloudTrail no Athena"
  value       = aws_glue_catalog_table.cloudtrail.name
}

output "console_url" {
  description = "URL do console AWS para enviar aos alunos"
  value       = "https://console.aws.amazon.com/athena/home?region=${var.aws_region}"
}

output "credenciais_alunos" {
  description = "Usuários IAM criados com senhas aleatórias"
  sensitive   = true
  value = {
    for username, info in local.alunos_map : username => {
      nome_completo = info.nome_completo
      senha_inicial = random_password.aluno[username].result
      deve_trocar   = true
    }
  }
}

# ─── Output markdown para gerar acesso.md ─────────────────────────────────────
output "acesso_md" {
  description = "Conteúdo markdown formatado com usuario | senha | url_console — salve como acesso.md"
  sensitive   = true
  value = <<-EOT
    # Lab 01 — Caça ao Intruso | Credenciais de Acesso

    | Usuário | Senha | URL do Console |
    |---------|-------|----------------|
    %{ for username, info in local.alunos_map ~}
    | ${username} | ${random_password.aluno[username].result} | https://console.aws.amazon.com |
    %{ endfor ~}

    ---
    **Instruções:**
    - Acesse a URL do console com seu usuário e senha
    - Troque a senha no primeiro login
    - Região: ${var.aws_region}
    - Athena Workgroup: ${aws_athena_workgroup.lab.name}
    - Database: ${aws_athena_database.lab.name}
    - Tabela: cloudtrail_logs
  EOT
}

output "instrucoes_aluno" {
  description = "Bloco de texto pronto para enviar aos alunos"
  value = <<-EOT
    ╔══════════════════════════════════════════════════════════════╗
    ║          LAB 01 — CAÇA AO INTRUSO | ACESSO AWS              ║
    ╠══════════════════════════════════════════════════════════════╣
    ║  Console: https://console.aws.amazon.com                             ║
    ║  Região : ${var.aws_region}                                          ║
    ║                                                              ║
    ║  Athena Workgroup : ${aws_athena_workgroup.lab.name}
    ║  Database         : ${aws_athena_database.lab.name}
    ║  Tabela           : cloudtrail_logs                         ║
    ║                                                              ║
    ║  ⚠ Você receberá seu usuário e senha separadamente           ║
    ║  ⚠ Troque a senha no primeiro acesso                        ║
    ╚══════════════════════════════════════════════════════════════╝
  EOT
}

output "query_primeiro_acesso" {
  description = "Query para testar se o ambiente está funcionando"
  value       = "SELECT COUNT(*) as total_eventos FROM ${aws_athena_database.lab.name}.cloudtrail_logs;"
}
