#!/usr/bin/env bash
set -euo pipefail

# Compatibilidade: redireciona para parar.sh
# Uso:
#   ./encerrar.sh [STACK ...]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -x "$ROOT/parar.sh" ]; then
  exec "$ROOT/parar.sh" "$@"
fi

echo "Arquivo parar.sh não encontrado." >&2
exit 1
