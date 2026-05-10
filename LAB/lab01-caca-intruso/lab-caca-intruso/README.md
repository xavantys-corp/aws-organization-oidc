# Lab 01 — Caça ao Intruso
## Guia Completo do Professor

---

## Estrutura do Projeto

```
lab-caca-intruso/
│
├── deploy.sh                        # Script principal: up / down / credentials
│
├── logs/
│   ├── generate_logs.py             # Gera os logs com anomalias plantadas
│   └── output/                      # Criado ao rodar o script
│       ├── cloudtrail_lab01_cenario_A.json.gz
│       ├── cloudtrail_lab01_cenario_B.json.gz
│       ├── cloudtrail_lab01_cenario_C.json.gz
│       ├── cloudtrail_lab01_cenario_A.json    ← versão legível para debug
│       ├── cloudtrail_lab01_cenario_B.json
│       ├── cloudtrail_lab01_cenario_C.json
│       └── GABARITO_PROFESSOR.json            ← 🔒 NÃO COMPARTILHE
│
├── terraform/
│   ├── main.tf                      # S3, Athena, Glue, IAM
│   ├── variables.tf                 # Variáveis (região, lista de alunos)
│   ├── outputs.tf                   # Credenciais e instruções formatadas
│   └── terraform.tfvars.example     # Exemplo — copie para terraform.tfvars
│
└── material/
    ├── briefing-aluno.html          # Apresentação visual (abrir no browser)
    └── guia-aluno.md                # Guia com todas as queries (distribuir)
```

---

## Pré-Requisitos

| Ferramenta | Versão | Instalação |
|---|---|---|
| Terraform | >= 1.5 | https://developer.hashicorp.com/terraform/install |
| Python 3 | >= 3.8 | https://python.org |
| AWS CLI | >= 2.0 | https://aws.amazon.com/cli |
| Conta AWS | Free Tier OK | https://aws.amazon.com/free |

---

## Deploy Passo a Passo

### 1. Configure as credenciais AWS
```bash
aws configure
# AWS Access Key ID: SUA_KEY
# AWS Secret Access Key: SUA_SECRET
# Default region name: us-east-1
# Default output format: json
```

### 2. Configure os alunos
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com os nomes dos alunos
```

### 3. Faça o deploy
```bash
chmod +x deploy.sh
./deploy.sh up
```

O script vai:
1. Gerar os logs CloudTrail com anomalias
2. Inicializar e aplicar o Terraform
3. Criar o bucket S3 e fazer upload dos logs
4. Criar o Athena workgroup + database + tabela
5. Criar usuários IAM para cada aluno
6. Exibir as credenciais e instruções

### 4. Distribua as credenciais
```bash
./deploy.sh credentials
# Saída: usuario,senha para cada aluno
```

Envie cada usuário/senha **individualmente** (pelo chat da videoconferência, privado).
Alunos serão obrigados a trocar a senha no primeiro acesso.

### 5. Destrua após a aula
```bash
./deploy.sh down
# Digite DESTRUIR para confirmar
```

---

## Distribuição dos Cenários

| Alunos (ou duplas) | Cenário | Anomalias |
|---|---|---|
| Grupo 1 | A | Root sem MFA + backdoor IAM |
| Grupo 2 | B | Session hijack + exfiltração S3 |
| Grupo 3 | C | Brute force + cobertura de rastros |
| (repetir para turmas maiores) | A, B, C... | |

Para distribuir: no início da aula, informe privadamente a cada aluno/dupla qual
cenário recebeu. Não revele para a turma até o final.

---

## Material para os Alunos

Distribua **antes da aula** (via Moodle, Google Classroom, etc.):

- `material/guia-aluno.md` — Guia completo com todas as queries
- `material/briefing-aluno.html` — Abrir no browser como briefing visual da missão

**NÃO distribua:** `GABARITO_PROFESSOR.json`

---

## Custos AWS Estimados

| Recurso | Free Tier | Custo estimado (1 aula) |
|---|---|---|
| S3 (armazenamento) | 5 GB grátis | ~$0.00 |
| S3 (requests) | 20K GET grátis | ~$0.00 |
| Athena (queries) | - | ~$0.01 por TB escaneado |
| Glue Data Catalog | 1M obj grátis | ~$0.00 |
| IAM (usuários) | Gratuito | $0.00 |
| **Total estimado** | | **< $0.50 por aula** |

> Use `./deploy.sh down` imediatamente após a aula para evitar custos recorrentes.

---

## Gabarito dos Cenários

### Cenário A — Backdoor IAM
1. **Root login sem MFA** às 03:17 UTC de IP `185.220.101.47` (Tor exit node)
2. **CreateUser**: usuário `svc-monitor` criado às 03:21
3. **AttachUserPolicy**: `AdministratorAccess` anexado às 03:23
4. **CreateAccessKey**: chave programática criada às 03:24

*Técnica MITRE:* T1136.003 (Create Cloud Account) + T1098 (Account Manipulation)

### Cenário B — Exfiltração de Dados
1. Login legítimo de `lucas.financeiro` às 09:12 de IP brasileiro
2. **Session hijack**: mesmo usuário loga de `45.142.212.100` às 11:19 **sem MFA**
3. **ListBuckets** (reconhecimento) às 11:20
4. **30 GetObject** no bucket `empresa-dados-financeiros-prod` em ~4 minutos

*Técnica MITRE:* T1539 (Steal Web Session Cookie) + T1530 (Data from Cloud Storage)

### Cenário C — Cobertura de Rastros
1. **5 logins falhos** para `admin` de `91.108.56.200` a partir de 01:44
2. Login **bem-sucedido** às 01:56 **sem MFA** (senha fraca)
3. Criação de `backup-automation` + chave de acesso (persistência)
4. **DeleteTrail + StopLogging** às 02:04 — tentativa de apagar evidências

*Técnica MITRE:* T1110 (Brute Force) + T1562.008 (Disable Cloud Logs)

---

## Perguntas para Discussão ao Final

1. **Por que o CloudTrail ainda tinha os logs se o atacante tentou deletar?**  
   → Logs já estavam no S3. DeleteTrail não apaga retroativamente o S3.

2. **Como o MFA teria impedido os incidentes A, B e C?**

3. **Qual seria a ação imediata de contenção em cada cenário?**  
   → A: Revogar chaves + deletar `svc-monitor` + ativar MFA root  
   → B: Revogar sessão + rotacionar credenciais de `lucas.financeiro`  
   → C: Bloquear IP + deletar `backup-automation` + forçar reset de `admin`

4. **Como o AWS GuardDuty detectaria esses eventos automaticamente?**  
   → Introdução para o Lab 02!

---

## Dicas Pedagógicas

- **Não dê as respostas cedo demais.** Deixe os alunos ficarem perdidos por ~15 min. 
  A frustração de investigar é parte do aprendizado.
- **Checkpoint aos 30 min**: pergunte "quem já encontrou algo suspeito?" 
  sem revelar a resposta.
- **Breakout rooms** (Zoom/Teams): coloque duplas em salas separadas para evitar 
  que copiem uns dos outros (cenários diferentes ajudam muito nisso).
- **O momento de revelar o gabarito** ao final, depois que todos apresentaram, 
  é o mais impactante da aula. Reserve 10 min para isso.
