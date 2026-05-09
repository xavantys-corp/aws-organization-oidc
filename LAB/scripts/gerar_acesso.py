#!/usr/bin/env python3
"""
gerar_acesso.py — Lê o output JSON do Terraform (credenciais_alunos)
e gera acesso.md com tabela markdown de credenciais.

Formato do output Terraform (credenciais_alunos):
{
  "joao.silva": {
    "nome_completo": "Joao Silva",
    "senha_inicial": "senha_aleatoria",
    "deve_trocar": true
  },
  ...
}

Uso:
    terraform output -json credenciais_alunos > credenciais.json
    python scripts/gerar_acesso.py credenciais.json

Ou sem argumento (usa path padrão):
    python scripts/gerar_acesso.py
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_credenciais(path: Path) -> dict:
    """Carrega JSON de credenciais_alunos do Terraform."""
    if not path.exists():
        print(f"ERRO: arquivo não encontrado: {path}", file=sys.stderr)
        print("Execute: terraform output -json credenciais_alunos > credenciais.json", file=sys.stderr)
        sys.exit(1)

    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Terraform output -json wraps values in {"value": ..., "sensitive": ...}
    if isinstance(data, dict) and "value" in data:
        data = data["value"]

    return data


def generate_acesso_md(
    credenciais: dict,
    console_url: str = "https://console.aws.amazon.com",
    athena_info: dict | None = None,
) -> str:
    """Gera markdown com tabela de acesso."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    if athena_info is None:
        athena_info = {}

    wg = athena_info.get("workgroup", "fatec-lab01-workgroup")
    db = athena_info.get("database", "lab_cloudtrail")
    table = athena_info.get("table", "cloudtrail_logs")

    lines = [
        "# 🔐 Acesso ao Lab AWS — Caça ao Intruso",
        "",
        f"> **Gerado em:** {now}",
        f"> **Console:** <{console_url}>",
        "> **Região:** us-east-1",
        "",
        "## Instruções para os Alunos",
        "",
        f"1. Acesse o [AWS Console]({console_url})",
        "2. Faça login com seu **usuário** e **senha** da tabela abaixo",
        "3. **Troque a senha** no primeiro acesso (obrigatório)",
        "4. Navegue até o serviço **Amazon Athena**",
        f"5. Selecione o workgroup: `{wg}`",
        "6. Execute as queries do lab",
        "",
        "⚠️ **Não compartilhe suas credenciais com colegas.**",
        "",
        "---",
        "",
        "## Credenciais",
        "",
        "| # | Usuário | Senha | Nome Completo | Trocar Senha |",
        "|---|---------|-------|---------------|--------------|",
    ]

    for idx, (username, creds) in enumerate(sorted(credenciais.items()), start=1):
        nome_completo = creds.get("nome_completo", "N/A")
        senha = creds.get("senha_inicial", "N/A")
        deve_trocar = "Sim" if creds.get("deve_trocar", True) else "Não"
        lines.append(f"| {idx} | `{username}` | `{senha}` | {nome_completo} | {deve_trocar} |")

    lines.extend([
        "",
        "---",
        "",
        "## Athena — Informações do Ambiente",
        "",
        "```",
        f"Workgroup : {wg}",
        f"Database  : {db}",
        f"Tabela    : {table}",
        "```",
        "",
        "## Query de Teste",
        "",
        "```sql",
        f"SELECT COUNT(*) as total_eventos FROM {db}.{table};",
        "```",
        "",
    ])

    return "\n".join(lines)


def main():
    script_dir = Path(__file__).resolve().parent
    project_dir = script_dir.parent

    # Input: credenciais.json (argumento ou path padrão)
    if len(sys.argv) > 1:
        cred_path = Path(sys.argv[1])
    else:
        cred_path = script_dir / "credenciais.json"

    print(f"Lendo credenciais: {cred_path}")
    credenciais = load_credenciais(cred_path)
    print(f"  → {len(credenciais)} alunos encontrados")

    # Output: acesso.md
    output_path = project_dir / "lab01-caca-intruso" / "acesso.md"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    md_content = generate_acesso_md(credenciais)
    output_path.write_text(md_content, encoding="utf-8")
    print(f"  → acesso.md gerado: {output_path}")

    # Print preview
    print("\n--- Preview ---")
    for line in md_content.split("\n")[:20]:
        print(line)
    print("...")


if __name__ == "__main__":
    main()
