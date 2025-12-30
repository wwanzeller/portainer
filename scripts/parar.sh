#!/usr/bin/env bash
set -euo pipefail

# Para stacks (remove do Swarm, sem apagar volumes).
# Uso:
#   ./scripts/parar.sh                 # para todas as stacks
#   ./scripts/parar.sh infra_traefik   # para stacks específicas

usage() {
  cat <<EOF
Uso: $0 [STACK ...]
  Sem argumentos: remove todas as stacks ativas
  Com argumentos: remove apenas as stacks listadas
EOF
  exit 1
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
fi

command -v docker >/dev/null 2>&1 || { echo "Falta o comando 'docker'."; exit 1; }

stacks=("$@")
if [ ${#stacks[@]} -eq 0 ]; then
  mapfile -t stacks < <(docker stack ls --format '{{.Name}}')
fi

if [ ${#stacks[@]} -eq 0 ]; then
  echo "Nenhuma stack encontrada para parar."
  exit 0
fi

for stack in "${stacks[@]}"; do
  echo "Parando stack: ${stack}"
  docker stack rm "${stack}" || true
done

echo "Pronto. Volumes não foram removidos."
