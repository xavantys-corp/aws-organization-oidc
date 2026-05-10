# GitHub Actions — Lab AWS Caça ao Intruso

Automatiza provisionamento AWS via Terraform com GitHub Actions usando **autenticação OIDC** (sem chaves de acesso de longa duração).

> **OIDC**: O GitHub Actions gera um token JWT por execução de workflow. A AWS valida o token e concede acesso temporário à role `github_role`. Nenhuma credencial é armazenada no repositório. O template CloudFormation StackSet que provisiona a role OIDC é mantido no repositório de infraestrutura da organização: `<ORG_INFRA_REPO>`.

## Fluxo

```
alunos.txt → generar_usuarios.py → terraform.tfvars → terraform apply → gerar_acesso.py → acesso.md
```

## Workflows

### 1. `deploy-lab.yml` — Deploy Completo

Dispara em push para `main` (com mudanças no lab) ou via `workflow_dispatch`.

Executa em 3 jobs:
1. **generate-logs** — Gera logs CloudTrail simulados (artifacts)
2. **terraform-deploy** — `terraform init` → `plan` → `apply`
3. **generate-access** — Extrai outputs do Terraform e gera `acesso.md`

**Gatilhos:**
- `push` em `main` com mudanças em `LAB/lab01-caca-intruso/**`
- `workflow_dispatch` com input opcional `alunos_json`

### 2. `destroy-lab.yml` — Destruição com Confirmação

Dispara via `workflow_dispatch`. Exige confirmação explícita digitando `DESTROY`.

**Gatilhos:** `workflow_dispatch` com input `confirm_destroy`

## Pré-requisitos

### Secrets do Repositório

Configure em **Settings → Secrets and variables → Actions**:

| Secret | Obrigatório | Descrição | Exemplo |
|--------|-------------|-----------|---------|
| `AWS_TARGET_ACCOUNT_ID` | Não | Fallback apenas se `repo-config.yml` estiver ausente | `123456789012` |
| `TF_VAR_ALUNOS_JSON` | Não | JSON array com nomes dos alunos (fallback se não usar workflow_dispatch) | `["Joao Silva","Maria Santos"]` |

> **Nota**: A autenticação usa OIDC — não é necessário configurar `AWS_ACCESS_KEY_ID` ou `AWS_SECRET_ACCESS_KEY`. A IAM Role `github_role` é provisionada pelo StackSet CloudFormation mantido no repositório de infraestrutura da organização (`<ORG_INFRA_REPO>`).

### Arquivo `repo-config.yml`

O account ID, região e nome da role são lidos do arquivo `repo-config.yml` na raiz do repositório:

```yaml
aws:
  account_id: "449014188319"
  region: "us-east-1"
  role_name: "github_role"

tags:
  environment: "lab"
  project: "resposta-incidentes-fatec"
  owner: "xavantys-corp"
  managed_by: "github-actions"
```

O secret `AWS_TARGET_ACCOUNT_ID` só é usado como fallback defensivo caso o arquivo esteja ausente.

## Como Usar

### Localmente

> **CI/CD usa OIDC** — os workflows no GitHub Actions autenticam via `github_role` (sem chaves). Para desenvolvimento local, configure credenciais AWS normalmente.

```bash
# 1. Edite alunos.txt com nomes reais (um por linha)
#    Formato: Primeiro Segundo
#    Exemplo: Joao Silva

# 2. Gere terraform.tfvars + alunos.json
python scripts/generar_usuarios.py

# 3. Configure AWS credentials (apenas para uso local)
#    Opção A: aws configure
aws configure
#    Opção B: variáveis de ambiente
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="wJalr..."
export AWS_DEFAULT_REGION="us-east-1"

# 4. Inicialize e aplique
cd LAB/lab01-caca-intruso/lab-caca-intruso/terraform
terraform init
terraform apply

# 5. Exporte credenciais e gere acesso.md
terraform output -json credenciais_alunos > ../../../../scripts/credenciais.json
cd ../../../../
python scripts/gerar_acesso.py scripts/credenciais.json

# 6. Envie acesso.md aos alunos
cat LAB/lab01-caca-intruso/acesso.md
```

### Via GitHub Actions

1. **Preencha `alunos.txt`** com nomes reais dos alunos
2. **Commit e push** para `main` → workflow `deploy-lab.yml` roda automaticamente
3. **Ou dispare manualmente** via `workflow_dispatch` passando `alunos_json`
4. **Baixe `acesso.md`** dos artifacts do job `generate-access`
5. **Para destruir**: dispare `destroy-lab.yml` com confirmação `DESTROY`

## Estrutura de Arquivos

```
atividades_alunos/
├── repo-config.yml                     ← Config AWS (account ID, região, tags)
├── alunos.txt                          ← Edite aqui (nomes dos alunos)
├── scripts/
│   ├── generar_usuarios.py             ← Gera tfvars + JSON (list(string))
│   ├── gerar_acesso.py                 ← Gera acesso.md
│   ├── alunos.json                     ← Gerado (lista de nomes)
│   └── credenciais.json                ← Gerado (output terraform)
├── LAB/
│   └── lab01-caca-intruso/
│       └── lab-caca-intruso/
│           ├── logs/
│           │   └── generate_logs.py    ← Gera logs CloudTrail simulados
│           └── terraform/
│               ├── main.tf
│               ├── variables.tf
│               ├── outputs.tf
│               └── terraform.tfvars    ← Gerado por generar_usuarios.py
│       └── acesso.md                   ← Gerado por gerar_acesso.py
└── .github/
    └── workflows/
        ├── deploy-lab.yml              ← Deploy completo (logs + apply + acesso.md)
        └── destroy-lab.yml             ← Destruição com confirmação
```

## Formato do alunos.txt

Uma linha por aluno. Mínimo 2 palavras (primeiro + segundo nome).

```
Joao Silva
Maria Santos
Pedro Oliveira
```

O script `generar_usuarios.py` gera automaticamente:
- **terraform.tfvars**: `alunos = ["Joao Silva", "Maria Santos", ...]`
- **alunos.json**: mesma lista em formato JSON

O Terraform faz o resto:
- **username**: `joao.silva` (primeiro.segundo, lowercase, sem acentos) — gerado via `local.normalize_username`
- **senha**: aleatória de 16 caracteres com símbolos — gerada via `random_password`
- **deve_trocar**: `true` — obrigatório trocar no primeiro login

## Troubleshooting

| Erro | Causa | Solução |
|------|-------|---------|
| `ERRO: arquivo não encontrado: alunos.txt` | Arquivo ausente | Crie `alunos.txt` na raiz do projeto |
| `Nome precisa de pelo menos 2 partes` | Linha com 1 palavra | Use formato "Primeiro Segundo" |
| `Error creating IAM user` | Permissões AWS insuficientes | Verifique secrets e política IAM |
| `Bucket already exists` | Nome de bucket em uso | O Terraform adiciona sufixo aleatório |
| `credenciais_alunos is sensitive` | Terraform oculta output | Use `terraform output -json credenciais_alunos` |
| `No alunos provided` | Secret ou input ausente | Configure `TF_VAR_ALUNOS_JSON` ou passe via workflow_dispatch |

## Cleanup

```bash
cd LAB/lab01-caca-intruso/lab-caca-intruso/terraform
terraform destroy -auto-approve
```

⚠️ **Destroi todos os recursos AWS criados pelo lab.**
