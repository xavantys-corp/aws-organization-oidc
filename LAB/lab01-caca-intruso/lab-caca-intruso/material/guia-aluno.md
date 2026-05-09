# 🔍 Lab 01 — Caça ao Intruso
## Guia do Aluno | Incidentes de Segurança da Informação — FATEC

---

## Contexto

Você é analista de segurança de uma empresa brasileira. O time de TI identificou
comportamentos estranhos na conta AWS nas últimas 24h. Você recebeu acesso aos
logs do CloudTrail e precisa investigar o que aconteceu.

**Seu objetivo:** encontrar o incidente, reconstruir a timeline e preencher o
Formulário de Registro de Incidente ao final.

---

## Acesso ao Ambiente

| Item | Valor |
|---|---|
| Console AWS | https://console.aws.amazon.com |
| Região | `us-east-1` |
| Serviço | **Amazon Athena** |
| Workgroup | _(informado pelo professor)_ |
| Database | `lab_cloudtrail` |
| Tabela | `cloudtrail_logs` |
| Usuário IAM | _(informado pelo professor)_ |

> ⚠️ Troque sua senha no primeiro acesso. Nunca compartilhe suas credenciais.

---

## Como Acessar o Athena

1. Acesse o [Console AWS](https://console.aws.amazon.com) com suas credenciais
2. Pesquise **Athena** na barra de serviços
3. No menu lateral, clique em **Workgroups** e selecione o workgroup do lab
4. Clique em **Query editor**
5. No seletor de **Database**, escolha `lab_cloudtrail`
6. Você está pronto para investigar!

---

## Queries de Investigação

Use as queries abaixo em ordem. Leia os resultados com atenção.
Anote tudo que parecer suspeito.

### 🔎 Etapa 1 — Visão Geral dos Logs

```sql
-- Quantos eventos existem no total?
SELECT COUNT(*) AS total_eventos
FROM cloudtrail_logs;
```

```sql
-- Quais tipos de eventos existem?
SELECT eventname, COUNT(*) AS qtd
FROM cloudtrail_logs
GROUP BY eventname
ORDER BY qtd DESC;
```

```sql
-- Quais usuários realizaram ações?
SELECT useridentity.username AS usuario,
       COUNT(*) AS total_acoes
FROM cloudtrail_logs
WHERE useridentity.username IS NOT NULL
GROUP BY useridentity.username
ORDER BY total_acoes DESC;
```

---

### 🔎 Etapa 2 — Análise de Logins

```sql
-- Todos os eventos de login (sucesso e falha)
SELECT eventtime,
       useridentity.username AS usuario,
       sourceipaddress        AS ip_origem,
       responseelements
FROM cloudtrail_logs
WHERE eventname = 'ConsoleLogin'
ORDER BY eventtime;
```

```sql
-- Logins COM FALHA — possível brute force ou tentativa de acesso não autorizado
SELECT eventtime,
       useridentity.username AS usuario,
       sourceipaddress        AS ip_origem,
       responseelements
FROM cloudtrail_logs
WHERE eventname = 'ConsoleLogin'
  AND responseelements LIKE '%Failure%'
ORDER BY eventtime;
```

```sql
-- Logins SEM MFA — alto risco!
SELECT eventtime,
       useridentity.username AS usuario,
       useridentity.type     AS tipo_usuario,
       sourceipaddress        AS ip_origem
FROM cloudtrail_logs
WHERE eventname = 'ConsoleLogin'
  AND additionaleventdata LIKE '%No%'
ORDER BY eventtime;
```

```sql
-- Logins fora do horário comercial (antes das 8h ou após as 19h)
SELECT eventtime,
       useridentity.username AS usuario,
       sourceipaddress        AS ip_origem,
       responseelements
FROM cloudtrail_logs
WHERE eventname = 'ConsoleLogin'
  AND (
    CAST(substr(eventtime, 12, 2) AS INTEGER) < 8
    OR CAST(substr(eventtime, 12, 2) AS INTEGER) >= 19
  )
ORDER BY eventtime;
```

---

### 🔎 Etapa 3 — Análise de Ações IAM

```sql
-- Todas as ações de gerenciamento de identidade (IAM)
SELECT eventtime,
       eventname,
       useridentity.username AS feito_por,
       sourceipaddress        AS ip_origem,
       requestparameters
FROM cloudtrail_logs
WHERE eventsource = 'iam.amazonaws.com'
ORDER BY eventtime;
```

```sql
-- Criação de usuários — backdoors?
SELECT eventtime,
       useridentity.username AS criado_por,
       sourceipaddress        AS ip_origem,
       requestparameters
FROM cloudtrail_logs
WHERE eventname = 'CreateUser'
ORDER BY eventtime;
```

```sql
-- Políticas anexadas a usuários — escalada de privilégios?
SELECT eventtime,
       useridentity.username AS feito_por,
       sourceipaddress        AS ip_origem,
       requestparameters
FROM cloudtrail_logs
WHERE eventname = 'AttachUserPolicy'
ORDER BY eventtime;
```

```sql
-- Criação de chaves de acesso — exfiltração via API?
SELECT eventtime,
       useridentity.username AS feito_por,
       sourceipaddress        AS ip_origem,
       requestparameters,
       responseelements
FROM cloudtrail_logs
WHERE eventname = 'CreateAccessKey'
ORDER BY eventtime;
```

---

### 🔎 Etapa 4 — Análise de Acesso ao S3

```sql
-- Operações em buckets S3
SELECT eventtime,
       eventname,
       useridentity.username AS usuario,
       sourceipaddress        AS ip_origem,
       requestparameters
FROM cloudtrail_logs
WHERE eventsource = 's3.amazonaws.com'
ORDER BY eventtime;
```

```sql
-- Downloads de objetos (GetObject) — exfiltração?
SELECT eventtime,
       useridentity.username AS usuario,
       sourceipaddress        AS ip_origem,
       requestparameters
FROM cloudtrail_logs
WHERE eventname = 'GetObject'
ORDER BY eventtime;
```

```sql
-- Quantos downloads por IP? (volume suspeito)
SELECT sourceipaddress AS ip_origem,
       COUNT(*) AS total_downloads,
       MIN(eventtime) AS primeiro_acesso,
       MAX(eventtime) AS ultimo_acesso
FROM cloudtrail_logs
WHERE eventname = 'GetObject'
GROUP BY sourceipaddress
ORDER BY total_downloads DESC;
```

---

### 🔎 Etapa 5 — Análise de Cobertura de Rastros

```sql
-- Tentativas de desabilitar o CloudTrail (cobertura de rastros!)
SELECT eventtime,
       eventname,
       useridentity.username AS usuario,
       sourceipaddress        AS ip_origem,
       requestparameters
FROM cloudtrail_logs
WHERE eventsource = 'cloudtrail.amazonaws.com'
  AND eventname IN ('DeleteTrail','StopLogging','UpdateTrail','DeleteEventDataStore')
ORDER BY eventtime;
```

---

### 🔎 Etapa 6 — Investigação por IP Suspeito

> Substitua `'IP_SUSPEITO'` pelo IP que você identificou como suspeito nas etapas anteriores.

```sql
-- Todas as ações de um IP específico
SELECT eventtime,
       eventname,
       eventsource,
       useridentity.username AS usuario,
       requestparameters
FROM cloudtrail_logs
WHERE sourceipaddress = 'IP_SUSPEITO'
ORDER BY eventtime;
```

```sql
-- Timeline completa do atacante
SELECT eventtime,
       eventname,
       eventsource,
       useridentity.username AS usuario,
       useridentity.type     AS tipo,
       requestparameters
FROM cloudtrail_logs
WHERE sourceipaddress = 'IP_SUSPEITO'
ORDER BY eventtime ASC;
```

---

## 📋 Formulário de Registro de Incidente

Preencha ao final da investigação:

```
╔══════════════════════════════════════════════════════════════════════╗
║              FORMULÁRIO DE REGISTRO DE INCIDENTE                    ║
║                     Lab 01 — FATEC 2024                             ║
╠══════════════════════════════════════════════════════════════════════╣

IDENTIFICAÇÃO
─────────────────────────────────────────────────────────────────────
Nome do analista  : _______________________________________________
Data/hora análise : _______________________________________________
Cenário recebido  : [  ] A    [  ] B    [  ] C

DETECÇÃO
─────────────────────────────────────────────────────────────────────
1. Como o incidente foi detectado?
   _______________________________________________________________

2. Qual foi o PRIMEIRO evento suspeito encontrado?
   Horário : ____________________________________________________
   Evento  : ____________________________________________________
   IP      : ____________________________________________________
   Usuário : ____________________________________________________

ANÁLISE
─────────────────────────────────────────────────────────────────────
3. Classifique o tipo de incidente:
   [  ] Acesso não autorizado
   [  ] Escalada de privilégios
   [  ] Exfiltração de dados
   [  ] Criação de backdoor
   [  ] Cobertura de rastros (anti-forense)
   [  ] Outro: __________________________________________________

4. Descreva a TIMELINE do ataque em ordem cronológica:

   Horário          | Evento                    | IP
   ─────────────────┼───────────────────────────┼──────────────────
   ________________ | _________________________ | ________________
   ________________ | _________________________ | ________________
   ________________ | _________________________ | ________________
   ________________ | _________________________ | ________________
   ________________ | _________________________ | ________________

5. Indicadores de Comprometimento (IoCs) identificados:
   IP(s) suspeito(s) : ___________________________________________
   Usuário(s) criado(s) pelo atacante : __________________________
   Chave(s) de acesso criada(s) : ________________________________
   Buckets/objetos acessados : ___________________________________

IMPACTO
─────────────────────────────────────────────────────────────────────
6. O que o atacante conseguiu fazer? (Selecione todos que se aplicam)
   [  ] Acessou o console AWS
   [  ] Criou usuário permanente (backdoor)
   [  ] Concedeu privilégios administrativos
   [  ] Baixou dados sensíveis do S3
   [  ] Tentou apagar evidências
   [  ] Gerou chaves de acesso programático

7. Severidade do incidente (sua avaliação):
   [  ] BAIXA    [  ] MÉDIA    [  ] ALTA    [  ] CRÍTICA

CONTENÇÃO (o que você faria?)
─────────────────────────────────────────────────────────────────────
8. Ações imediatas de contenção:
   _______________________________________________________________
   _______________________________________________________________

9. Ações de remediação de longo prazo:
   _______________________________________________________________
   _______________________________________________________________

LIÇÕES APRENDIDAS
─────────────────────────────────────────────────────────────────────
10. O que poderia ter PREVENIDO este incidente?
    _______________________________________________________________
    _______________________________________________________________

╚══════════════════════════════════════════════════════════════════════╝
```

---

## ⏱️ Cronograma Sugerido

| Tempo | Atividade |
|---|---|
| 0–10 min | Acesso ao ambiente + query de visão geral |
| 10–30 min | Etapas 2 e 3 — análise de logins e IAM |
| 30–45 min | Etapas 4 e 5 — S3 e cobertura de rastros |
| 45–60 min | Etapa 6 — timeline do atacante |
| 60–75 min | Preenchimento do formulário |
| 75–90 min | Apresentação para a turma (5 min cada grupo) |

---

## 💡 Dicas

- **Tome notas** de cada query e resultado — você vai precisar para o formulário
- Se uma query retornar muitos resultados, adicione `LIMIT 20` ao final
- O horário nos logs está em **UTC** — considere isso na análise
- Nem todo evento suspeito é o incidente principal — procure o **padrão**
- Dúvidas? Pergunte ao professor antes de desistir de uma pista

---

*FATEC — Disciplina de Incidentes de Segurança da Informação*
