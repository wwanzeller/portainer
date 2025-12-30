#!/usr/bin/env bash
set -euo pipefail

# Desinstala tudo: para stacks e remove o diretório infraestrutura.
# Não remove volumes.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""

usage() {
  cat <<EOF
Uso: $0 [--dir PATH]
  --dir PATH  Diretório base ou completo (usa <PATH>/infraestrutura se não terminar com infraestrutura)
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      TARGET_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

normalize_install_dir() {
  local dir="$1"
  if [ -z "$dir" ]; then
    dir="$ROOT"
  fi
  if [ "$(basename "$dir")" != "infraestrutura" ]; then
    dir="${dir%/}/infraestrutura"
  fi
  printf '%s' "$dir"
}

INSTALL_DIR="$(normalize_install_dir "$TARGET_DIR")"

if [ "$(basename "$INSTALL_DIR")" != "infraestrutura" ]; then
  echo "Diretório alvo inválido: $INSTALL_DIR" >&2
  exit 1
fi

if [ ! -d "$INSTALL_DIR" ]; then
  echo "Diretório não encontrado: $INSTALL_DIR" >&2
  exit 1
fi

if [ -x "$INSTALL_DIR/parar.sh" ]; then
  "$INSTALL_DIR/parar.sh"
else
  command -v docker >/dev/null 2>&1 || { echo "Falta o comando 'docker'."; exit 1; }
  mapfile -t stacks < <(docker stack ls --format '{{.Name}}')
  for stack in "${stacks[@]}"; do
    echo "Parando stack: ${stack}"
    docker stack rm "${stack}" || true
  done
fi

if [ "$INSTALL_DIR" = "/" ] || [ -z "$INSTALL_DIR" ]; then
  echo "Abortado: diretório inválido." >&2
  exit 1
fi

cd /
rm -rf "$INSTALL_DIR"

echo "Pronto. Diretório removido. Volumes não foram apagados."
