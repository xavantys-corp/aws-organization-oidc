#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# deploy.sh — Script de deploy e cleanup do Lab 01
# Uso: ./deploy.sh [up|down|credentials|status]
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
LOGS_DIR="$SCRIPT_DIR/logs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[→]${NC} $1"; }

check_deps() {
  command -v terraform >/dev/null 2>&1 || err "Terraform não encontrado. Instale: https://developer.hashicorp.com/terraform/install"
  command -v python3   >/dev/null 2>&1 || err "Python3 não encontrado."
  command -v aws       >/dev/null 2>&1 || err "AWS CLI não encontrado."
  aws sts get-caller-identity >/dev/null 2>&1 || err "AWS não autenticado. Execute: aws configure"
  log "Dependências OK"
}

generate_logs() {
  info "Gerando logs CloudTrail com anomalias plantadas..."
  cd "$LOGS_DIR"
  python3 generate_logs.py
  log "Logs gerados em $LOGS_DIR/output/"
}

deploy() {
  check_deps

  # Gera os logs se não existirem
  if [ ! -f "$LOGS_DIR/output/cloudtrail_lab01_cenario_A.json.gz" ]; then
    generate_logs
  else
    warn "Logs já existem. Pulando geração. Para regenerar: rm -rf logs/output && ./deploy.sh up"
  fi

  # Cria tfvars se não existir
  if [ ! -f "$TF_DIR/terraform.tfvars" ]; then
    warn "terraform.tfvars não encontrado. Usando terraform.tfvars.example como base."
    cp "$TF_DIR/terraform.tfvars.example" "$TF_DIR/terraform.tfvars"
    warn "Edite $TF_DIR/terraform.tfvars com os nomes dos alunos antes de continuar."
    read -p "Pressione ENTER após editar o arquivo (ou CTRL+C para cancelar)..."
  fi

  info "Inicializando Terraform..."
  cd "$TF_DIR" && terraform init -upgrade

  info "Validando configuração..."
  terraform validate

  info "Planejando infraestrutura..."
  terraform plan -out=tfplan

  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  warn "ATENÇÃO: Isso criará recursos na sua conta AWS."
  warn "Recursos têm custo baixo (Free Tier cobre a maioria)."
  warn "Execute './deploy.sh down' ao final da aula para destruir tudo."
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
  echo ""
  read -p "Confirma o deploy? (s/N): " confirm
  [[ "$confirm" =~ ^[Ss]$ ]] || { warn "Deploy cancelado."; exit 0; }

  info "Aplicando infraestrutura..."
  terraform apply tfplan

  echo ""
  log "Deploy concluído!"
  echo ""
  info "Credenciais dos alunos (guarde com segurança):"
  terraform output -json credenciais_alunos | python3 -c "
import json, sys
data = json.load(sys.stdin)
print()
for nome, creds in data.items():
    print(f'  👤 {creds[\"usuario\"]:30s} | Senha: {creds[\"senha_inicial\"]}')
print()
" 2>/dev/null || terraform output credenciais_alunos

  echo ""
  info "Instruções para os alunos:"
  terraform output instrucoes_aluno
  terraform output query_primeiro_acesso
}

destroy() {
  check_deps
  cd "$TF_DIR"

  if [ ! -f "terraform.tfstate" ] && [ ! -f ".terraform/terraform.tfstate" ]; then
    err "Nenhum estado Terraform encontrado. O lab já foi destruído?"
  fi

  echo ""
  echo -e "${RED}${BOLD}⚠ ATENÇÃO: Isso DESTRUIRÁ toda a infraestrutura do lab!${NC}"
  echo -e "${RED}Buckets S3, usuários IAM e recursos Athena serão deletados permanentemente.${NC}"
  echo ""
  read -p "Digite 'DESTRUIR' para confirmar: " confirm
  [[ "$confirm" == "DESTRUIR" ]] || { warn "Cancelado."; exit 0; }

  info "Destruindo infraestrutura..."
  terraform destroy -auto-approve

  warn "Removendo arquivos locais de logs (os gabaritos foram salvos)..."
  # Mantém o gabarito do professor mas remove os .gz
  find "$LOGS_DIR/output" -name "*.gz" -delete 2>/dev/null || true

  log "Infraestrutura destruída. Nenhum custo adicional será gerado."
}

show_credentials() {
  check_deps
  cd "$TF_DIR"
  info "Credenciais dos alunos:"
  terraform output -json credenciais_alunos | python3 -c "
import json, sys
data = json.load(sys.stdin)
for nome, creds in data.items():
    print(f'{creds[\"usuario\"]},{creds[\"senha_inicial\"]}')
" 2>/dev/null
}

status() {
  check_deps
  cd "$TF_DIR"
  info "Estado atual da infraestrutura:"
  terraform output 2>/dev/null || warn "Nenhuma infraestrutura detectada. Execute './deploy.sh up'"
}

case "${1:-help}" in
  up)          deploy ;;
  down)        destroy ;;
  credentials) show_credentials ;;
  status)      status ;;
  logs)        generate_logs ;;
  *)
    echo ""
    echo -e "${BOLD}Lab 01 — Caça ao Intruso | Deploy Script${NC}"
    echo ""
    echo "  ./deploy.sh up          — Sobe toda a infraestrutura"
    echo "  ./deploy.sh down        — Destrói tudo (use ao final da aula)"
    echo "  ./deploy.sh credentials — Lista usuários e senhas dos alunos"
    echo "  ./deploy.sh status      — Mostra estado atual"
    echo "  ./deploy.sh logs        — Regenera os arquivos de log"
    echo ""
    ;;
esac
