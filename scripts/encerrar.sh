#!/usr/bin/env bash
set -euo pipefail

# Compatibilidade: redireciona para parar.sh
# Uso:
#   ./scripts/encerrar.sh [STACK ...]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -x "$ROOT/scripts/parar.sh" ]; then
  exec "$ROOT/scripts/parar.sh" "$@"
fi

echo "Arquivo parar.sh não encontrado." >&2
exit 1
