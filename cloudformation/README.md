# CloudFormation StackSet — GitHub Actions OIDC

Template CloudFormation para criar provedor de identidade OIDC e IAM Role que permitem ao GitHub Actions acessar recursos AWS **sem chaves de acesso de longa duração**.

## O que este template faz

Cria dois recursos em cada conta AWS da organização:

1. **OIDC Provider** — Conecta o GitHub (`token.actions.githubusercontent.com`) como provedor de identidade confiável na AWS
2. **IAM Role (`GitHubActionsOIDCRole`)** — Role assumível via OIDC com permissões scoped para o lab (S3, Athena, Glue, IAM, CloudWatch Logs)

## Por que OIDC é melhor que chaves de acesso

| Critério | Access Keys (AKIA...) | OIDC |
|----------|----------------------|------|
| Rotação | Manual ou via script | Automática (token de 5 min) |
| Armazenamento | Secret no GitHub (risco de vazamento) | Nenhum secret armazenado |
| Escopo | Fixo até revogado | Restrito por repo, branch, ambiente |
| Auditoria | Difícil rastrear origem | Cada assume tem `sub` com repo + ref |
| Expiração | Nunca expira (até revogar) | Token expira em 5 minutos |
| Blast radius | Comprometimento = acesso total | Comprometimento = acesso limitado ao repo |

**OIDC elimina o problema de gerenciar, rotacionar e proteger chaves de acesso.** O GitHub gera um JWT token por execução de workflow, a AWS valida o token e concede acesso temporário.

## Pré-requisitos

- **Conta master da AWS Organization** — StackSet é criado a partir da conta gerenciadora
- **Permissões de StackSet** — A conta master precisa de permissão para criar stacks nas contas membro (service-managed ou self-managed)
- **Repositório GitHub** — O repo configurado nos parâmetros deve existir
- **Região `us-east-1`** — OIDC Providers são recursos globais, mas o StackSet precisa de uma região alvo

## Passo a passo — Criar o StackSet no Console AWS

### 1. Acessar StackSets

1. Faça login na **conta master** da AWS Organization
2. Navegue para **CloudFormation → StackSets**
3. Clique em **Create StackSet**

### 2. Selecionar template

1. Escolha **Upload a template file**
2. Faça upload do arquivo `github-oidc-stackset.yaml`
3. Clique em **Next**

### 3. Definir parâmetros

| Parâmetro | Valor padrão | Descrição |
|-----------|-------------|-----------|
| `GitHubOrg` | `xavantys-corp` | Organização GitHub dona do repositório |
| `GitHubRepo` | `lab-resposta-incidentes-fatec` | Nome do repositório GitHub |
| `LabPrefix` | `fatec-lab01` | Prefixo para recursos do lab |

Ajuste conforme necessário. Clique em **Next**.

### 4. Configurar opções de deployment

- **Deployment targets**: Selecione **Deploy to organization**
- **Region**: `us-east-1` (N. Virginia)
- **Deployment options**:
  - Maximum concurrent accounts: `1` (ou mais conforme tamanho da org)
  - Failure tolerance: `0` (falha em uma conta para o deployment)
  - Region concurrency: `SEQUENTIAL`

Clique em **Next**.

### 5. Revisar e criar

1. Revise as configurações
2. Confirme que o template cria recursos IAM
3. Clique em **Submit**

### 6. Auto-deployment para novas contas

Para que novas contas que ingressarem na Organization recebam automaticamente o StackSet:

1. No StackSet criado, vá para a aba **Settings**
2. Em **Auto-deployment**, selecione **Auto-deploy to new accounts**
3. Isso garante que toda conta nova na Organization recebe o OIDC Provider e a Role automaticamente

## Provisionamento automático

Quando uma nova conta é adicionada à AWS Organization:

```
Nova conta na Organization
    ↓
StackSet detecta nova conta (auto-deployment enabled)
    ↓
Cria stack na nova conta (us-east-1)
    ↓
Cria OIDC Provider (reutiliza se já existir)
    ↓
Cria IAM Role GitHubActionsOIDCRole
    ↓
Anexa política de permissões scoped ao LabPrefix
    ↓
Conta pronta para receber deployments do GitHub Actions
```

## Configuração de Secrets no GitHub

No repositório GitHub, configure em **Settings → Secrets and variables → Actions**:

| Secret | Obrigatório | Descrição |
|--------|-------------|-----------|
| `AWS_TARGET_ACCOUNT_ID` | Sim | ID da conta AWS onde o lab será provisionado (ex: `123456789012`) |

**Remova os secrets antigos** (se existirem):
- `AWS_ACCESS_KEY_ID` — não é mais necessário
- `AWS_SECRET_ACCESS_KEY` — não é mais necessário

### Como adicionar

```bash
# Via GitHub CLI
gh secret set AWS_TARGET_ACCOUNT_ID --body "123456789012"
```

Ou manualmente:
1. Acesse o repositório no GitHub
2. **Settings → Secrets and variables → Actions**
3. **New repository secret**
4. Nome: `AWS_TARGET_ACCOUNT_ID`
5. Valor: ID da conta AWS (12 dígitos)

## Como o workflow autentica com OIDC

O workflow usa a action `aws-actions/configure-aws-credentials@v4`:

```yaml
- name: Configure AWS Credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_TARGET_ACCOUNT_ID }}:role/GitHubActionsOIDCRole
    role-session-name: GitHubActions-DeployLab01
    aws-region: us-east-1
```

O que acontece internamente:

1. A action solicita um **JWT token** ao GitHub (OIDC token)
2. O token contém claims como `sub` (repo:org/repo:ref), `aud` (sts.amazonaws.com), `iss` (GitHub)
3. A action chama `sts:AssumeRoleWithWebIdentity` passando o JWT
4. A AWS valida o token contra o OIDC Provider configurado
5. Se válido, retorna **credenciais temporárias** (AccessKeyId, SecretAccessKey, SessionToken)
6. As credenciais são configuradas no ambiente para os passos seguintes

## Fluxo completo OIDC

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Actions                           │
│                                                                 │
│  ┌──────────────┐     ┌──────────────────────────────────────┐  │
│  │  Workflow    │────▶│ configure-aws-credentials@v4         │  │
│  │  dispara     │     │                                      │  │
│  └──────────────┘     │  1. Gera JWT token (OIDC)            │  │
│                       │     sub: repo:org/repo:ref           │  │
│                       │     aud: sts.amazonaws.com           │  │
│                       │     iss: token.actions.githubusercontent.com │
│                       └──────────────┬───────────────────────┘  │
│                                      │                          │
│                                      │ 2. AssumeRoleWithWebIdentity
│                                      │    (JWT + Role ARN)      │
└──────────────────────────────────────┼──────────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │              AWS STS                 │
                    │                                      │
                    │  3. Valida JWT contra OIDC Provider  │
                    │     - Verifica assinatura            │
                    │     - Verifica aud (sts.amazonaws.com)│
                    │     - Verifica sub (repo permitido)  │
                    │     - Verifica exp (não expirado)    │
                    │                                      │
                    │  4. Retorna credenciais temporárias  │
                    │     - AccessKeyId (ASIA...)          │
                    │     - SecretAccessKey                │
                    │     - SessionToken                   │
                    │     - Expiração: ~1h                 │
                    └──────────────────┬──────────────────┘
                                       │
                                       │ 5. Credenciais no ambiente
                                       │
                    ┌──────────────────▼──────────────────┐
                    │         GitHub Actions               │
                    │                                      │
                    │  6. terraform init/plan/apply        │
                    │     usa credenciais temporárias      │
                    │     para criar recursos AWS          │
                    └──────────────────────────────────────┘
```

## Troubleshooting

### AssumeRoleWithWebIdentity falha

**Erro:** `An error occurred (AccessDenied) when calling the AssumeRoleWithWebIdentity operation`

**Causas e soluções:**

| Causa | Verificação | Solução |
|-------|-------------|---------|
| OIDC Provider não existe | Console IAM → Identity Providers | Execute o StackSet na conta alvo |
| Thumbprint incorreto | Compare com `6938fd4e98bab3fa4317bcbae533e1e3c0036e3a` | Atualize o thumbprint no Provider |
| Role não existe | Console IAM → Roles → `GitHubActionsOIDCRole` | Execute o StackSet |
| Trust policy incorreta | Verifique `Condition` na Role | Use `StringLike` com `repo:org/repo:*` |
| `aud` não confere | Token deve ter `aud: sts.amazonaws.com` | Configure `audience: sts.amazonaws.com` na action |

### Role não encontrada

**Erro:** `Role not found: arn:aws:iam::123456789012:role/GitHubActionsOIDCRole`

**Solução:**
1. Verifique se o StackSet foi deployado na conta correta
2. No console CloudFormation → StackSets, veja o status da stack na conta alvo
3. Se falhou, veja os eventos da stack para identificar o erro
4. Se a conta foi adicionada depois, verifique se auto-deployment está habilitado

### Token validation failed

**Erro:** `Not authorized to perform sts:AssumeRoleWithWebIdentity`

**Causas:**
- O `sub` do token não bate com a condição na trust policy
- O repo configurado no StackSet é diferente do repo que executa o workflow

**Verificação:**
```bash
# No workflow, adicione este passo para debug:
- name: Debug OIDC token
  run: |
    echo "GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
    echo "GITHUB_REF: $GITHUB_REF"
    echo "Expected sub: repo:$GITHUB_REPOSITORY:$GITHUB_REF"
```

**Solução:** Garanta que os parâmetros `GitHubOrg` e `GitHubRepo` no StackSet correspondem ao repositório real.

### Access Denied nos recursos

**Erro:** `User: arn:aws:sts::... is not authorized to perform: s3:CreateBucket`

**Causas:**
- A política anexada à Role não cobre o recurso
- O `LabPrefix` na política não bate com o nome do bucket

**Solução:**
1. Verifique o `LabPrefix` configurado no StackSet
2. Confirme que os recursos Terraform usam o mesmo prefixo
3. A política usa `${LabPrefix}-*` como escopo — ajuste se necessário

### StackSet falha no deployment

**Erro:** StackSet mostra status `FAILED` em uma ou mais contas

**Solução:**
1. No console CloudFormation → StackSets, clique no StackSet
2. Vá para a aba **Instances**
3. Clique na stack com status `FAILED`
4. Vá para a aba **Events** para ver o erro específico
5. Erros comuns:
   - **IAM already exists**: OIDC Provider já existe — o template deve usar `DependsOn` ou verificar existência
   - **Permissions boundary**: A conta tem permissions boundary que bloqueia criação de roles IAM
   - **SCP (Service Control Policy)**: A Organization tem SCP bloqueando ações IAM

## Tabela de referência

| Item | Valor |
|------|-------|
| OIDC Provider URL | `https://token.actions.githubusercontent.com` |
| OIDC Thumbprint | `6938fd4e98bab3fa4317bcbae533e1e3c0036e3a` |
| Role Name | `GitHubActionsOIDCRole` |
| Policy Name | `GitHubActionsLabPolicy` |
| Audience | `sts.amazonaws.com` |
| Subject pattern | `repo:${GitHubOrg}/${GitHubRepo}:*` |
| Região | `us-east-1` |
| Tipo de deployment | Organization StackSet |
| Auto-deployment | Habilitado para novas contas |
| Token duration | ~5 minutos (GitHub) |
| Session duration | ~1 hora (AWS STS default) |

## Migração do template antigo para o novo

Existe um template legado em `LAB/infrastructure/cloudformation/github-oidc-role.yaml` que cria uma role chamada **`fatec-lab01-GitHubActionsRole`**. O novo template (`cloudformation/github-oidc-stackset.yaml`) cria uma role chamada **`GitHubActionsOIDCRole`**, que é o nome referenciado nos workflows em `.github/workflows/`.

### ⚠️ Importante: deletar o stack antigo antes

A AWS permite **apenas um OIDC Provider** com a URL `https://token.actions.githubusercontent.com` por conta. Se o stack antigo ainda estiver ativo, o deployment do novo StackSet vai falhar com erro *"already exists"*.

**Antes de deployar o novo StackSet:**

1. Vá ao console CloudFormation → Stacks
2. Localize o stack criado pelo template antigo (`github-oidc-role.yaml`)
3. Delete o stack

### Preservar o OIDC Provider (opcional)

Se a role antiga precisa ser mantida temporariamente, delete o stack antigo com política **Retain** no OIDC Provider:

1. No console CloudFormation, abra o stack antigo
2. Vá para a aba **Resources**
3. Identifique o recurso do OIDC Provider
4. Antes de deletar, altere a política de deleção para `Retain` (ou edite o template original)
5. Delete o stack — o Provider permanece, a role é removida

Porém, a abordagem mais limpa é **deletar tudo e redeployar** com o novo template.

### Após o deployment

Os workflows em `.github/workflows/` já referenciam `GitHubActionsOIDCRole`:

```yaml
role-to-assume: arn:aws:iam::${{ secrets.AWS_TARGET_ACCOUNT_ID }}:role/GitHubActionsOIDCRole
```

Após o StackSet ser deployado com sucesso, os workflows funcionam imediatamente — nenhuma alteração adicional é necessária.

## Migração de Access Keys para OIDC

### Antes (Access Keys)

```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: us-east-1
```

### Depois (OIDC)

```yaml
permissions:
  id-token: write    # Necessário para OIDC
  contents: read

- name: Configure AWS Credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::${{ secrets.AWS_TARGET_ACCOUNT_ID }}:role/GitHubActionsOIDCRole
    role-session-name: GitHubActions-DeployLab01
    aws-region: us-east-1
```

### Passos da migração

1. **Deploy do StackSet** — Crie o StackSet com o template `github-oidc-stackset.yaml`
2. **Adicionar secret** — Configure `AWS_TARGET_ACCOUNT_ID` no repositório GitHub
3. **Atualizar workflow** — Troque a configuração de credentials para OIDC (exemplo acima)
4. **Adicionar permissions** — Adicione `id-token: write` nas permissions do workflow
5. **Testar** — Execute o workflow e verifique com `aws sts get-caller-identity`
6. **Remover secrets antigos** — Delete `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` do repositório
7. **Desabilitar/deletar IAM User** — Remova o usuário IAM de CI/CD que usava as access keys

### Verificação pós-migração

```bash
# No workflow, após configure-aws-credentials:
aws sts get-caller-identity
# Deve mostrar algo como:
# {
#   "UserId": "AROA...:GitHubActions-DeployLab01",
#   "Account": "123456789012",
#   "Arn": "arn:aws:sts::123456789012:assumed-role/GitHubActionsOIDCRole/GitHubActions-DeployLab01"
# }
```

O `assumed-role/GitHubActionsOIDCRole` confirma que a autenticação OIDC está funcionando corretamente.
