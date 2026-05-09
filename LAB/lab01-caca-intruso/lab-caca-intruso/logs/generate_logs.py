#!/usr/bin/env python3
"""
Gerador de logs CloudTrail com anomalias plantadas para o Lab 01 — Caça ao Intruso
Gera 3 cenários diferentes para evitar que alunos copiem uns dos outros.
Execute: python3 generate_logs.py
Saída: pasta output/ com os arquivos .json e .json.gz para upload no S3
"""
import json, gzip, random, uuid, os
from datetime import datetime, timezone, timedelta

def ts(dt): return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
def rid(): return str(uuid.uuid4()).replace("-","")[:16].upper()

LEGIT_IPS   = ["189.40.12.88","177.23.55.101","200.156.34.9","187.77.22.14"]
ATTACK_IP_A = "185.220.101.47"   # Tor exit node
ATTACK_IP_B = "45.142.212.100"   # Known C2
ATTACK_IP_C = "91.108.56.200"    # Datacenter estrangeiro
ACCOUNT     = "123456789012"

# ─── Helpers de eventos ────────────────────────────────────────────────────────

def make_login_event(dt, ip, user, success=True, mfa=True, user_type="IAMUser"):
    base_identity = {
        "type": user_type,
        "principalId": rid(),
        "arn": f"arn:aws:iam::{ACCOUNT}:user/{user}",
        "accountId": ACCOUNT,
        "userName": user
    }
    if user_type == "Root":
        base_identity = {"type":"Root","principalId":ACCOUNT,
                         "arn":f"arn:aws:iam::{ACCOUNT}:root","accountId":ACCOUNT}
    return {
        "eventVersion": "1.08",
        "userIdentity": base_identity,
        "eventTime": ts(dt),
        "eventSource": "signin.amazonaws.com",
        "eventName": "ConsoleLogin",
        "awsRegion": "us-east-1",
        "sourceIPAddress": ip,
        "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "requestParameters": None,
        "responseElements": {
            "ConsoleLogin": "Success" if success else "Failure",
            "MFAUsed": "Yes" if mfa else "No"
        },
        "additionalEventData": {
            "LoginTo": "https://console.aws.amazon.com/console/home",
            "MobileVersion": "No", "MFAUsed": "Yes" if mfa else "No"
        },
        "eventID": rid(), "eventType": "AwsConsoleSignIn",
        "managementEvent": True, "readOnly": False,
        "recipientAccountId": ACCOUNT
    }

def make_iam_event(dt, ip, actor, event_name, req_params, resp_elements=None):
    return {
        "eventVersion": "1.08",
        "userIdentity": {"type":"IAMUser","principalId":rid(),
                         "arn":f"arn:aws:iam::{ACCOUNT}:user/{actor}",
                         "accountId":ACCOUNT,"userName":actor},
        "eventTime": ts(dt), "eventSource": "iam.amazonaws.com",
        "eventName": event_name, "awsRegion": "us-east-1",
        "sourceIPAddress": ip, "userAgent": "aws-cli/2.13.0 Python/3.11",
        "requestParameters": req_params, "responseElements": resp_elements,
        "eventID": rid(), "eventType": "AwsApiCall",
        "managementEvent": True, "readOnly": False,
        "recipientAccountId": ACCOUNT
    }

def make_s3_event(dt, ip, actor, event_name, bucket, key=None, read_only=True):
    req = {"bucketName": bucket}
    if key: req["key"] = key
    e = {
        "eventVersion": "1.08",
        "userIdentity": {"type":"IAMUser","principalId":rid(),
                         "arn":f"arn:aws:iam::{ACCOUNT}:user/{actor}",
                         "accountId":ACCOUNT,"userName":actor},
        "eventTime": ts(dt), "eventSource": "s3.amazonaws.com",
        "eventName": event_name, "awsRegion": "sa-east-1",
        "sourceIPAddress": ip, "userAgent": "python-boto3/1.34.0",
        "requestParameters": req, "responseElements": None,
        "eventID": rid(), "eventType": "AwsApiCall",
        "managementEvent": False if key else True,
        "readOnly": read_only, "recipientAccountId": ACCOUNT
    }
    if key: e["resources"] = [{"ARN":f"arn:aws:s3:::{bucket}/{key}",
                                "accountId":ACCOUNT,"type":"AWS::S3::Object"}]
    return e

def make_ct_event(dt, ip, actor, event_name, trail_name):
    return {
        "eventVersion": "1.08",
        "userIdentity": {"type":"IAMUser","principalId":rid(),
                         "arn":f"arn:aws:iam::{ACCOUNT}:user/{actor}",
                         "accountId":ACCOUNT,"userName":actor},
        "eventTime": ts(dt), "eventSource": "cloudtrail.amazonaws.com",
        "eventName": event_name, "awsRegion": "us-east-1",
        "sourceIPAddress": ip, "userAgent": "aws-cli/2.13.0",
        "requestParameters": {"name": trail_name}, "responseElements": None,
        "eventID": rid(), "eventType": "AwsApiCall",
        "managementEvent": True, "readOnly": False,
        "recipientAccountId": ACCOUNT
    }

def generate_normal_events(base_date, num=45):
    """Gera eventos de uso legítimo durante horário comercial"""
    events = []
    users = ["joao.silva","maria.santos","carlos.dev","ana.ops","pedro.sec"]
    for _ in range(num):
        hour = random.randint(8, 18)
        minute = random.randint(0, 59)
        day_offset = random.randint(0, 4)
        dt = base_date.replace(hour=hour, minute=minute, second=random.randint(0,59))
        dt = dt + timedelta(days=day_offset)
        ip = random.choice(LEGIT_IPS)
        user = random.choice(users)
        kind = random.randint(0,3)
        if kind == 0:
            events.append(make_login_event(dt, ip, user, True, True))
        elif kind == 1:
            events.append(make_s3_event(dt, ip, user, "ListBuckets", "N/A", None, True))
        elif kind == 2:
            events.append(make_iam_event(dt, ip, user, "ListUsers", {}, None))
        else:
            events.append(make_iam_event(dt, ip, user, "GetUser",
                                         {"userName": user}, {"user":{"userName":user}}))
    return events

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO A — Root login noturno + criação de backdoor IAM
# ══════════════════════════════════════════════════════════════════════════════
def scenario_a():
    base = datetime(2024, 3, 15, tzinfo=timezone.utc)
    events = generate_normal_events(base)
    anomalias = []

    # A1: root login às 3h17 sem MFA de IP estrangeiro
    t1 = base.replace(hour=3, minute=17, second=22)
    events.append(make_login_event(t1, ATTACK_IP_A, "root", True, False, "Root"))
    anomalias.append({"tipo":"Root login sem MFA","horario":ts(t1),"ip":ATTACK_IP_A,
                      "evento":"ConsoleLogin","usuario":"root","severidade":"CRITICA"})

    # A2: cria usuário backdoor
    t2 = t1 + timedelta(minutes=4, seconds=11)
    events.append(make_iam_event(t2, ATTACK_IP_A, "root", "CreateUser",
                                 {"userName":"svc-monitor"},
                                 {"user":{"userName":"svc-monitor","arn":f"arn:aws:iam::{ACCOUNT}:user/svc-monitor"}}))
    anomalias.append({"tipo":"Criação de usuário suspeito","horario":ts(t2),"ip":ATTACK_IP_A,
                      "evento":"CreateUser","usuario_criado":"svc-monitor","severidade":"ALTA"})

    # A3: anexa AdministratorAccess
    t3 = t2 + timedelta(minutes=1, seconds=44)
    events.append(make_iam_event(t3, ATTACK_IP_A, "root", "AttachUserPolicy",
                                 {"userName":"svc-monitor",
                                  "policyArn":"arn:aws:iam::aws:policy/AdministratorAccess"}))
    anomalias.append({"tipo":"AdministratorAccess concedido a usuário novo","horario":ts(t3),
                      "ip":ATTACK_IP_A,"evento":"AttachUserPolicy","severidade":"CRITICA"})

    # A4: gera chave de acesso programática
    t4 = t3 + timedelta(minutes=0, seconds=53)
    ak = f"AKIA{rid()[:16]}"
    events.append(make_iam_event(t4, ATTACK_IP_A, "root", "CreateAccessKey",
                                 {"userName":"svc-monitor"},
                                 {"accessKey":{"accessKeyId":ak,"status":"Active",
                                               "userName":"svc-monitor","createDate":ts(t4)}}))
    anomalias.append({"tipo":"Chave programática criada para backdoor","horario":ts(t4),
                      "ip":ATTACK_IP_A,"evento":"CreateAccessKey","accessKeyId":ak,"severidade":"ALTA"})

    random.shuffle(events)
    return events, anomalias

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO B — Session hijack + exfiltração massiva de S3
# ══════════════════════════════════════════════════════════════════════════════
def scenario_b():
    base = datetime(2024, 3, 15, tzinfo=timezone.utc)
    events = generate_normal_events(base)
    anomalias = []
    bucket = "empresa-dados-financeiros-prod"

    # Login legítimo do usuário comprometido
    t0 = base.replace(hour=9, minute=12, second=5)
    events.append(make_login_event(t0, LEGIT_IPS[0], "lucas.financeiro", True, True))

    # B1: mesmo usuário loga de IP diferente (sessão sequestrada) sem MFA
    t1 = t0 + timedelta(hours=2, minutes=7, seconds=18)
    events.append(make_login_event(t1, ATTACK_IP_B, "lucas.financeiro", True, False))
    anomalias.append({"tipo":"Mesmo usuário logado de dois IPs distintos (session hijack)",
                      "horario":ts(t1),"ip_legitimo":LEGIT_IPS[0],"ip_suspeito":ATTACK_IP_B,
                      "usuario":"lucas.financeiro","sem_mfa":True,"severidade":"CRITICA"})

    # B2: reconhecimento — ListBuckets
    t2 = t1 + timedelta(minutes=1, seconds=3)
    events.append(make_s3_event(t2, ATTACK_IP_B, "lucas.financeiro", "ListBuckets", "N/A"))
    anomalias.append({"tipo":"ListBuckets via IP suspeito (reconhecimento)","horario":ts(t2),
                      "ip":ATTACK_IP_B,"severidade":"MEDIA"})

    # B3: exfiltração massiva (28 GetObject em 4 minutos)
    sensitive_files = [
        "relatorios/balanco_2023_Q4.xlsx","relatorios/projecao_2024.xlsx",
        "clientes/base_crm_completa.csv","clientes/contratos_ativos.zip",
        "folha/pagamentos_marco_2024.xlsx","folha/senhas_sistemas.txt",
        "juridico/nda_fornecedores.pdf","juridico/processos_sigilosos.pdf",
        "ti/credenciais_producao.env","ti/diagrama_rede_interna.pdf"
    ]
    t3 = t2 + timedelta(minutes=1)
    for i, fname in enumerate(sensitive_files * 3):
        t = t3 + timedelta(seconds=i*8)
        events.append(make_s3_event(t, ATTACK_IP_B, "lucas.financeiro",
                                    "GetObject", bucket, fname, True))
    anomalias.append({"tipo":"30 GetObject em sequência (exfiltração de dados)",
                      "horario_inicio":ts(t3),"ip":ATTACK_IP_B,
                      "bucket":bucket,"arquivos_afetados":len(sensitive_files)*3,
                      "severidade":"CRITICA"})

    random.shuffle(events)
    return events, anomalias

# ══════════════════════════════════════════════════════════════════════════════
# CENÁRIO C — Brute force + escalada + cobertura de rastros
# ══════════════════════════════════════════════════════════════════════════════
def scenario_c():
    base = datetime(2024, 3, 15, tzinfo=timezone.utc)
    events = generate_normal_events(base)
    anomalias = []

    # C1: brute force — 5 logins falhos seguidos
    t1 = base.replace(hour=1, minute=44, second=0)
    for i in range(5):
        events.append(make_login_event(t1 + timedelta(minutes=i*2, seconds=random.randint(5,55)),
                                       ATTACK_IP_C, "admin", False, False))
    anomalias.append({"tipo":"5 logins falhos consecutivos (brute force)","horario_inicio":ts(t1),
                      "ip":ATTACK_IP_C,"usuario_alvo":"admin","tentativas":5,"severidade":"ALTA"})

    # C2: 6ª tentativa bem-sucedida (senha fraca quebrada)
    t2 = t1 + timedelta(minutes=12, seconds=17)
    events.append(make_login_event(t2, ATTACK_IP_C, "admin", True, False))
    anomalias.append({"tipo":"Login bem-sucedido após brute force, SEM MFA","horario":ts(t2),
                      "ip":ATTACK_IP_C,"usuario":"admin","severidade":"CRITICA"})

    # C3: cria usuário de persistência + chave
    t3 = t2 + timedelta(minutes=3, seconds=8)
    events.append(make_iam_event(t3, ATTACK_IP_C, "admin", "CreateUser",
                                 {"userName":"backup-automation"},
                                 {"user":{"userName":"backup-automation"}}))
    t3b = t3 + timedelta(minutes=1, seconds=22)
    ak = f"AKIA{rid()[:16]}"
    events.append(make_iam_event(t3b, ATTACK_IP_C, "admin", "CreateAccessKey",
                                 {"userName":"backup-automation"},
                                 {"accessKey":{"accessKeyId":ak,"status":"Active"}}))
    anomalias.append({"tipo":"Usuário 'backup-automation' + chave criados (persistência)",
                      "horario":ts(t3),"ip":ATTACK_IP_C,"accessKeyId":ak,"severidade":"ALTA"})

    # C4: tenta deletar CloudTrail (cobertura de rastros)
    t4 = t3 + timedelta(minutes=5, seconds=34)
    events.append(make_ct_event(t4, ATTACK_IP_C, "admin", "DeleteTrail", "main-trail"))
    t4b = t4 + timedelta(minutes=1)
    events.append(make_ct_event(t4b, ATTACK_IP_C, "admin", "StopLogging",
                                f"arn:aws:cloudtrail:us-east-1:{ACCOUNT}:trail/main-trail"))
    anomalias.append({"tipo":"DeleteTrail + StopLogging — COBERTURA DE RASTROS",
                      "horario":ts(t4),"ip":ATTACK_IP_C,"severidade":"CRITICA",
                      "nota":"Atacante tentou apagar evidências. Log já estava no S3."})

    random.shuffle(events)
    return events, anomalias

# ─── MAIN ─────────────────────────────────────────────────────────────────────
os.makedirs("output", exist_ok=True)

scenarios = [
    ("A", scenario_a),
    ("B", scenario_b),
    ("C", scenario_c),
]

gabarito = {}

for label, fn in scenarios:
    events, anomalias = fn()
    wrapper = {"Records": sorted(events, key=lambda e: e["eventTime"])}

    # JSON legível
    with open(f"output/cloudtrail_lab01_cenario_{label}.json", "w") as f:
        json.dump(wrapper, f, indent=2)

    # .json.gz — formato real do CloudTrail (para upload no S3)
    with gzip.open(f"output/cloudtrail_lab01_cenario_{label}.json.gz", "wb") as f:
        f.write(json.dumps(wrapper).encode())

    gabarito[f"Cenário {label}"] = {
        "total_eventos": len(events),
        "anomalias_plantadas": anomalias
    }
    print(f"✅  Cenário {label}: {len(events)} eventos | {len(anomalias)} anomalias plantadas")

with open("output/GABARITO_PROFESSOR.json", "w", encoding="utf-8") as f:
    json.dump(gabarito, f, indent=2, ensure_ascii=False)

print("\n📁  Arquivos gerados em ./output/")
print("🔒  GABARITO_PROFESSOR.json — APENAS PARA O PROFESSOR")
print("📤  Suba os .json.gz no S3 com: aws s3 cp output/ s3://SEU_BUCKET/logs/ --recursive")
