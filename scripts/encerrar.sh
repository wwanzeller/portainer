#!/usr/bin/env bash
set -euo pipefail

# Remove as stacks do bootstrap (traefik/portainer) ou uma lista específica.
# Uso:
#   Remover padrão:    ./scripts/encerrar.sh
#   Remover específicas: ./scripts/encerrar.sh infra_traefik infra_portainer

DEFAULT_STACKS=(
  infra_traefik
  infra_portainer
)

usage() {
  cat <<EOF
Uso: $0 [STACK ...]
  Sem argumentos: remove as stacks padrão (${DEFAULT_STACKS[*]})
  Com argumentos: remove apenas as stacks listadas
EOF
  exit 1
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
fi

stacks=("$@")
if [ ${#stacks[@]} -eq 0 ]; then
  stacks=("${DEFAULT_STACKS[@]}")
fi

command -v docker >/dev/null 2>&1 || { echo "Falta o comando 'docker'."; exit 1; }

for stack in "${stacks[@]}"; do
  echo "Removendo stack: ${stack}"
  docker stack rm "${stack}" || true
done

echo "Pronto. Stacks solicitadas removidas. Aguarde os serviços encerrarem."
