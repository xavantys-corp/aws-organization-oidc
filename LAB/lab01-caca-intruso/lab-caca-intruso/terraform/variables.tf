# ══════════════════════════════════════════════════════════════════════════════
# variables.tf — Lab 01 Caça ao Intruso
# ══════════════════════════════════════════════════════════════════════════════

variable "aws_region" {
  description = "Região AWS onde o lab será criado"
  type        = string
  default     = "us-east-1"
}

variable "alunos" {
  description = "Lista de nomes completos dos alunos (ex: 'João da Silva'). Username gerado automaticamente como primeiro.segundo."
  type        = list(string)
}
