#!/usr/bin/env python3
"""
generar_usuarios.py — Lê alunos.txt e gera:
  1. terraform.tfvars  (lista de strings para Terraform)
  2. alunos.json       (mesmos dados em JSON)

Formato esperado de alunos.txt (um por linha):
    Primeiro Segundo
    Maria Silva
    Joao Santos

O Terraform gera username automaticamente como primeiro.segundo (lowercase, sem acentos).
Senhas aleatórias são geradas pelo resource random_password do Terraform.
"""

import json
import sys
from pathlib import Path


def read_alunos(path: Path) -> list[str]:
    """Lê alunos.txt e retorna lista de nomes completos."""
    if not path.exists():
        print(f"ERRO: arquivo não encontrado: {path}", file=sys.stderr)
        sys.exit(1)

    alunos = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # Valida mínimo 2 palavras
            partes = line.split()
            if len(partes) < 2:
                print(f"AVISO: nome precisa de pelo menos 2 partes, ignorando: '{line}'", file=sys.stderr)
                continue
            alunos.append(line)
    return alunos


def generate_tfvars(alunos: list[str]) -> str:
    """Gera conteúdo do terraform.tfvars no formato list(string)."""
    lines = [
        "# ═══════════════════════════════════════════════════════════════════",
        "# terraform.tfvars — Gerado automaticamente por generar_usuarios.py",
        "# NÃO EDITAR MANUALMENTE — regenere com o script",
        "# Formato: lista de nomes completos — username gerado auto (primeiro.segundo)",
        "# ═══════════════════════════════════════════════════════════════════",
        "",
        f"alunos = [  # {len(alunos)} alunos",
    ]
    for nome in alunos:
        lines.append(f'  "{nome}",')
    lines.append("]")
    lines.append("")
    return "\n".join(lines)


def generate_json(alunos: list[str]) -> str:
    """Gera JSON com a lista de nomes dos alunos."""
    return json.dumps(alunos, indent=2, ensure_ascii=False) + "\n"


def main():
    # Paths
    script_dir = Path(__file__).resolve().parent
    project_dir = script_dir.parent
    alunos_txt = project_dir / "alunos.txt"
    tfvars_path = project_dir / "LAB" / "lab01-caca-intruso" / "lab-caca-intruso" / "terraform" / "terraform.tfvars"
    json_path = script_dir / "alunos.json"

    # Read
    print(f"Lendo {alunos_txt} ...")
    alunos = read_alunos(alunos_txt)
    print(f"  → {len(alunos)} alunos lidos")

    # Generate tfvars
    tfvars_content = generate_tfvars(alunos)
    tfvars_path.parent.mkdir(parents=True, exist_ok=True)
    tfvars_path.write_text(tfvars_content, encoding="utf-8")
    print(f"  → terraform.tfvars gerado: {tfvars_path}")

    # Generate JSON
    json_content = generate_json(alunos)
    json_path.write_text(json_content, encoding="utf-8")
    print(f"  → alunos.json gerado: {json_path}")

    # Summary
    print("\nResumo:")
    for nome in alunos:
        partes = nome.lower().split()
        username = f"{partes[0]}.{partes[1]}"
        print(f"  {nome:<50} → {username}")


if __name__ == "__main__":
    main()
