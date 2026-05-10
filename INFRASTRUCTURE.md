# Infrastructure — CloudFormation OIDC StackSet

## Escopo deste Repositório

Este repositório contém **apenas**:
- Conteúdo do lab (exercícios, scripts, Terraform)
- Workflows do GitHub Actions (`.github/workflows/`)
- Configuração de repositório (`repo-config.yml`)

## CloudFormation StackSet — Repositório Externo

O template CloudFormation StackSet para provisionamento da IAM Role OIDC (`github_role`) é mantido em um repositório separado de infraestrutura da organização:

> **`<ORG_INFRA_REPO>`**

### Por que separado?

- **Separação de responsabilidades**: infraestrutura da organização vs. conteúdo do lab
- **Reuso**: o mesmo StackSet pode ser usado por múltiplos repositórios
- **Controle de acesso**: mudanças no template OIDC exigem aprovação de infra, não de autores do lab
- **Versionamento independente**: o template de infra evolui em seu próprio ciclo de release

## Pré-requisitos para os Workflows

Os workflows neste repositório (`deploy-lab.yml`, `destroy-lab.yml`) esperam que:

1. A IAM Role `github_role` **já exista** na conta AWS de destino
2. A role foi provisionada pelo StackSet CloudFormation mantido em `<ORG_INFRA_REPO>`
3. O OIDC Provider (`token.actions.githubusercontent.com`) está configurado na conta

Se a role não existir, os workflows falharão com `Role not found`. Nesse caso, solicite ao time de infraestrutura que execute o StackSet na conta alvo.

## Fluxo de Provisionamento

```
<ORG_INFRA_REPO>                    atividades_alunos (este repo)
├── CloudFormation StackSet         ├── GitHub Actions workflows
│   └── Provisiona github_role      │   └── Assume github_role via OIDC
└── OIDC Provider config            └── Terraform (lab resources)
```

1. Time de infra deploya StackSet de `<ORG_INFRA_REPO>` na conta AWS
2. StackSet cria `github_role` + OIDC Provider
3. Workflows neste repo assumem `github_role` via OIDC
4. Terraform provisiona recursos do lab
