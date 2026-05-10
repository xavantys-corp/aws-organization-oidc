> ⚠️ **LEGACY DOCUMENT** — O template CloudFormation StackSet para provisionamento OIDC foi movido para o repositório de infraestrutura da organização: `<ORG_INFRA_REPO>`. Este documento permanece neste repositório apenas como referência histórica sobre como o OIDC funciona. Para o template atualizado, consulte `<ORG_INFRA_REPO>`.

# Configuração OIDC + StackSet para o Lab

## Visão Geral

### Por que OIDC é melhor que Access Keys

| Critério | Access Keys (antigo) | OIDC (novo) |
|---|---|---|
| **Duração** | Permanentes até rotação manual | Temporárias (1h máximo) |
| **Risco** | Vazamento = acesso indefinido | Expiração automática |
| **Gestão** | Rotação manual, propenso a erro | Zero gestão de secrets |
| **Auditoria** | Difícil rastrear origem | CloudTrail registra identidade GitHub |
| **Escala** | Secrets por conta | StackSet provisiona N contas automaticamente |

**OIDC elimina o problema de secrets de longa duração.** O GitHub gera um token JWT por execução de workflow. A AWS valida esse token e emite credenciais temporárias. Sem chaves para armazenar, rotacionar ou vazar.

---

## Pré-requisitos

- [ ] **Conta AWS Organization master** — acesso à conta gerenciadora da Organization
- [ ] **Permissão para criar StackSets** — política `AWSOrganizationsFullAccess` ou equivalente
- [ ] **Repositório GitHub existente** — `xavantys-corp/lab-resposta-incidentes-fatec`
- [ ] **Template CloudFormation** — arquivo disponível em `<ORG_INFRA_REPO>` (anteriormente em `cloudformation/github-oidc-role.yaml`)

---

## Passo 1: Criar StackSet na Conta Master

### 1.1 Acessar CloudFormation

1. Faça login na **conta master** da AWS Organization
2. Navegue até **CloudFormation** → **StackSets** (região `us-east-1`)
3. Clique em **Create StackSet**

### 1.2 Configurar Template

1. Em **Specify template**, selecione **Upload a template file**
2. Faça upload do arquivo obtido em `<ORG_INFRA_REPO>`:
   ```
   <ORG_INFRA_REPO>/cloudformation/github-oidc-role.yaml
   ```
3. Clique em **Next**

### 1.3 Definir Parâmetros

| Parâmetro | Valor | Descrição |
|---|---|---|
| `GitHubOrg` | `xavantys-corp` | Organização GitHub proprietária do repo |
| `GitHubRepo` | `lab-resposta-incidentes-fatec` | Nome do repositório |
| `LabPrefix` | `fatec-lab01` | Prefixo para nomear recursos criados |

### 1.4 Selecionar Contas de Destino

1. Em **Deployment targets**, selecione:
   - **Deploy to organization** — para todas as contas da Organization, **ou**
   - **Deploy to organizational units (OUs)** — para OU específica (ex: `ou-labs`)
2. Selecione as contas ou OU desejadas

### 1.5 Definir Região e Opções

- **Region**: `us-east-1` (N. Virginia)
- **Stack deployment options**:
  - Concurrency: `1` (sequencial, mais seguro)
  - Failure tolerance: `0` (falha em qualquer conta para o deploy)
- **IAM permissions**:
  - Role name: `AWSCloudFormationStackSetAdministrationRole` (criar se não existir)
  - Execution role name: `AWSCloudFormationStackSetExecutionRole`

### 1.6 Revisar e Criar

1. Revise as configurações
2. Confirme os recursos IAM que serão criados
3. Clique em **Submit**

> **Resultado esperado:** StackSet cria em cada conta alvo:
> - IAM Role com trust policy para o GitHub OIDC provider
> - IAM OIDC Provider (`token.actions.githubusercontent.com`)
> - Policy anexada com permissões do lab

---

## Passo 2: Configurar Secrets no GitHub

### 2.1 Adicionar Secret Obrigatório

No repositório GitHub → **Settings** → **Secrets and variables** → **Actions**:

| Secret | Valor | Exemplo |
|---|---|---|
| `AWS_TARGET_ACCOUNT_ID` | ID da conta AWS de destino | `449014188319` |

### 2.2 Remover Secrets Antigos (Access Keys)

**DELETE os seguintes secrets se existirem:**

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_ROLE_TO_ASSUME`

> **Importante:** Manter esses secrets causa confusão e risco de segurança. O workflow OIDC não os utiliza.

### 2.3 Verificar

A lista de secrets deve conter **apenas**:

```
AWS_TARGET_ACCOUNT_ID  →  449014188319
```

---

## Passo 3: Executar GitHub Actions

### 3.1 Workflow Atualizado

O arquivo `.github/workflows/deploy.yml` já está configurado para OIDC. Trecho relevante:

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write    # Necessário para OIDC
      contents: read

    steps:
      - name: Configure AWS Credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_TARGET_ACCOUNT_ID }}:role/fatec-lab01-github-oidc-role
          aws-region: us-east-1
```

### 3.2 Executar

1. Vá para **Actions** no repositório GitHub
2. Selecione o workflow **Deploy Lab Infrastructure**
3. Clique em **Run workflow**
4. Aguarde a conclusão

### 3.3 Verificar Sucesso

- Status verde no workflow
- Recursos criados na conta AWS (verifique no Console AWS)
- Logs do CloudTrail registram `AssumeRoleWithWebIdentity`

---

## Como Funciona: Fluxo OIDC

```
┌─────────────────┐
│   GitHub Actions │
│   (workflow)     │
└────────┬────────┘
         │ 1. Workflow inicia
         ▼
┌─────────────────┐
│  GitHub gera    │
│  token JWT      │────── subject: repo:xavantys-corp/lab-resposta-incidentes-fatec:ref:refs/heads/main
│  (por execução) │────── aud: sts.amazonaws.com
└────────┬────────┘
         │ 2. Envia token para AWS STS
         ▼
┌─────────────────────────────────────────────────────┐
│              AWS STS (us-east-1)                     │
│                                                     │
│  AssumeRoleWithWebIdentity(                         │
│    RoleArn: arn:aws:iam::449014188319:role/         │
│             fatec-lab01-github-oidc-role,           │
│    WebIdentityToken: <JWT do GitHub>                │
│  )                                                  │
│                                                     │
│  Valida:                                            │
│  ✓ Token assinado por GitHub                        │
│  ✓ issuer = token.actions.githubusercontent.com     │
│  ✓ subject corresponde à trust policy               │
│  ✓ aud = sts.amazonaws.com                          │
└────────┬────────────────────────────────────────────┘
         │ 3. Retorna credenciais temporárias
         ▼
┌─────────────────────────────────────────────────────┐
│  Credenciais Temporárias (máx 1h):                  │
│  - AccessKeyId: ASIA...                             │
│  - SecretAccessKey: ...                             │
│  - SessionToken: FwoGZXIvYXdzE...                   │
│  - Expiration: 2026-05-09T15:30:00Z                 │
└────────┬────────────────────────────────────────────┘
         │ 4. Usa credenciais para criar recursos
         ▼
┌─────────────────┐
│  AWS Services   │
│  (EC2, S3, etc) │
└─────────────────┘
```

### Detalhamento do Fluxo

| Etapa | O que acontece | Quem executa |
|---|---|---|
| **1** | Workflow GitHub Actions inicia | GitHub |
| **2** | GitHub gera JWT com claims do repo/branch | GitHub |
| **3** | `configure-aws-credentials` envia JWT para STS | Action |
| **4** | STS valida JWT contra OIDC Provider | AWS |
| **5** | STS verifica trust policy da role | AWS |
| **6** | STS emite credenciais temporárias | AWS |
| **7** | Workflow usa credenciais para operar AWS | GitHub Actions |

---

## Troubleshooting

### Erro: `Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Causa:** Trust policy da role não corresponde ao token JWT recebido.

**Verificar:**

```bash
# Na conta AWS de destino, verifique a trust policy:
aws iam get-role \
  --role-name fatec-lab01-github-oidc-role \
  --query 'Role.AssumeRolePolicyDocument'
```

**Trust policy esperada:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:sub": "repo:xavantys-corp/lab-resposta-incidentes-fatec:ref:refs/heads/main",
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

**Correção:** Recrie o StackSet ou atualize a trust policy manualmente.

---

### Erro: `Could not assume role` / `Role not found`

**Causa:** Role não existe na conta de destino.

**Verificar:**

```bash
# Verificar se a role existe:
aws iam get-role --role-name fatec-lab01-github-oidc-role

# Listar roles com prefixo do lab:
aws iam list-roles --query 'Roles[?contains(RoleName, `fatec-lab01`)]'
```

**Correção:**

1. Verifique se o StackSet foi deployado na conta correta
2. No Console AWS → CloudFormation → StackSets → verifique status
3. Se falhou, delete e recrie o StackSet
4. Verifique se a conta de destino está na OU selecionada

---

### Erro: `Token validation failed` / `InvalidIdentityToken`

**Causa:** OIDC Provider não existe ou está mal configurado.

**Verificar:**

```bash
# Listar OIDC Providers na conta:
aws iam list-open-id-connect-providers

# Verificar provider específico:
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com
```

**Provider esperado:**

- **URL:** `https://token.actions.githubusercontent.com`
- **Client ID list:** `sts.amazonaws.com`
- **Thumbprints:** `6938fd4d98bab03faadb97b34396831e3780aea1`

**Correção:**

1. O StackSet deve criar o OIDC Provider automaticamente
2. Se não criou, crie manualmente:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

---

### Erro: `Access Denied` ao criar recursos

**Causa:** Policy anexada à role não tem permissões suficientes.

**Verificar:**

```bash
# Verificar policies anexadas:
aws iam list-attached-role-policies \
  --role-name fatec-lab01-github-oidc-role

# Verificar policy inline:
aws iam get-role-policy \
  --role-name fatec-lab01-github-oidc-role \
  --policy-name GitHubOIDCLabPolicy
```

**Correção:** Atualize a policy no template CloudFormation e recrie o StackSet.

---

### Erro: `StackSet operation failed`

**Causa:** StackSet falhou em uma ou mais contas.

**Verificar:**

1. Console AWS → CloudFormation → StackSets → selecione seu StackSet
2. Aba **Operations** → veja a operação falha
3. Aba **Instances** → veja qual conta falhou e o motivo

**Correção:**

1. Corrija o problema na conta específica
2. Clique em **Retry** na operação falha
3. Ou delete e recrie o StackSet

---

## Vantagens da Arquitetura OIDC + StackSet

### 1. Sem Secrets de Longa Duração

- Access keys tradicionais nunca expiram (até rotação manual)
- Credenciais OIDC expiram em **1 hora** no máximo
- Zero risco de chave vazada no repositório ou logs

### 2. Escalável para N Contas

- StackSet provisiona role + provider em **todas as contas** da Organization
- Adicionar nova conta = adicionar à OU (automático)
- Sem configuração manual por conta

### 3. Rotação Automática

- Cada execução de workflow gera **novo token JWT**
- Credenciais temporárias expiram automaticamente
- Sem cron jobs de rotação, sem alertas de expiração

### 4. Auditável via CloudTrail

Cada assume role gera evento CloudTrail:

```json
{
  "eventName": "AssumeRoleWithWebIdentity",
  "userIdentity": {
    "type": "WebIdentityUser",
    "principalId": "token.actions.githubusercontent.com:repo:xavantys-corp/lab-resposta-incidentes-fatec",
    "identityProvider": "arn:aws:iam::449014188319:oidc-provider/token.actions.githubusercontent.com"
  },
  "sourceIPAddress": "GitHub Actions",
  "requestParameters": {
    "roleArn": "arn:aws:iam::449014188319:role/fatec-lab01-github-oidc-role",
    "roleSessionName": "GitHubActions"
  }
}
```

**Visível em:** CloudTrail → Event history → filtrar por `AssumeRoleWithWebIdentity`

### 5. Princípio do Menor Privilégio

- Trust policy restringe por **repo + branch**
- Policy da role limita ações ao escopo do lab
- Sem acesso root ou admin desnecessário

---

## Referência Rápida

| Item | Valor |
|---|---|
| **Template** | `<ORG_INFRA_REPO>/cloudformation/github-oidc-role.yaml` |
| **GitHub Org** | `xavantys-corp` |
| **GitHub Repo** | `lab-resposta-incidentes-fatec` |
| **Lab Prefix** | `fatec-lab01` |
| **Região** | `us-east-1` |
| **Role Name** | `fatec-lab01-github-oidc-role` |
| **OIDC Provider** | `token.actions.githubusercontent.com` |
| **Secret GitHub** | `AWS_TARGET_ACCOUNT_ID` |

---

## Migração de Access Keys para OIDC

Se o lab já estava funcionando com access keys:

1. **Deploy StackSet** (Passo 1)
2. **Adicionar secret** `AWS_TARGET_ACCOUNT_ID` (Passo 2)
3. **Remover secrets antigos** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ROLE_TO_ASSUME`
4. **Rodar workflow** (Passo 3)
5. **Verificar** recursos criados e logs CloudTrail
6. **Rotacionar** access keys antigas (desabilitar no IAM)
