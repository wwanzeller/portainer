#!/usr/bin/env bash
set -euo pipefail

# Inicializa Traefik + Portainer usando um .env.
# - Garante Swarm ativo
# - Cria networks padrão
# - (Opcional) Aplica labels de tier no node local
# - Faz deploy do Traefik e Portainer
#
# Uso: ./scripts/iniciar.sh --env-file .env

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
ENV_EXAMPLE="$ROOT/.env.example"
PORTAINER_BOOTSTRAP_NAME="${PORTAINER_BOOTSTRAP_NAME:-portainer-bootstrap}"
APPLY_LABELS=true

usage() {
  cat <<EOF
Uso: $0 [--env-file PATH] [--env-example PATH] [--no-labels]
  --env-file PATH     Caminho para o arquivo .env (default: $ENV_FILE)
  --env-example PATH  Caminho para o .env.example (default: $ENV_EXAMPLE)
  --no-labels         Não aplica labels de tier no node local
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --env-example)
      ENV_EXAMPLE="${2:-}"
      shift 2
      ;;
    --no-labels)
      APPLY_LABELS=false
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

strip_quotes() {
  local value="$1"
  if [[ "$value" =~ ^".*"$ ]] || [[ "$value" =~ ^'.*'$ ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

format_env_value() {
  local value="$1"
  if [[ "$value" =~ [^A-Za-z0-9_./-] ]]; then
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
  else
    printf '%s' "$value"
  fi
}

get_env_var() {
  local key="$1"
  eval "printf '%s' \"\${$key-}\""
}

prompt_value() {
  local __var="$1"
  local label="$2"
  local default="$3"
  local value=""
  if [ ! -r /dev/tty ]; then
    echo "Sem TTY para prompt. Defina $label como variável de ambiente ou crie o .env manualmente." >&2
    exit 1
  fi
  while true; do
    if [ -n "$default" ]; then
      read -r -p "${label} [${default}]: " value < /dev/tty || true
      value="${value:-$default}"
    else
      read -r -p "${label}: " value < /dev/tty || true
    fi
    if [ -n "$value" ]; then
      printf -v "$__var" '%s' "$value"
      return
    fi
  done
}

create_env_from_example() {
  if [ ! -f "$ENV_EXAMPLE" ]; then
    echo "Arquivo .env.example não encontrado: $ENV_EXAMPLE" >&2
    exit 1
  fi
  echo "Arquivo .env não encontrado. Vamos criar via prompt..."
  mkdir -p "$(dirname "$ENV_FILE")"
  local env_lines=()
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#${line%%[![:space:]]*}}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      local key="${line%%=*}"
      local default="${line#*=}"
      default="$(strip_quotes "$default")"
      local existing
      existing="$(get_env_var "$key")"
      local value=""
      if [ -n "$existing" ]; then
        value="$existing"
      else
        prompt_value value "$key" "$default"
      fi
      value="$(format_env_value "$value")"
      env_lines+=("${key}=${value}")
    fi
  done < "$ENV_EXAMPLE"
  printf '%s\n' "${env_lines[@]}" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Arquivo criado: $ENV_FILE"
}

command -v docker >/dev/null 2>&1 || { echo "Falta o comando 'docker'."; exit 1; }

if [ ! -f "$ENV_FILE" ]; then
  create_env_from_example
fi

# Ativa Swarm se ainda não estiver ativo
if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -qw active; then
  docker swarm init
fi
LOCAL_NODE_ID="$(docker info --format '{{.Swarm.NodeID}}')"

# Exporta variáveis do .env para substituição nos YAML
set -a
source "$ENV_FILE"
set +a

# Cria networks padrão se faltarem
for net in traefik_public wanzeller_network agent_network; do
  docker network inspect "$net" >/dev/null 2>&1 || docker network create --driver overlay --attachable "$net"
done

# Cria volumes necessários se faltarem
for vol in traefik_certificates portainer_data; do
  docker volume inspect "$vol" >/dev/null 2>&1 || docker volume create "$vol" >/dev/null
done

if [ "$APPLY_LABELS" = true ]; then
  echo "==> Aplicando labels de tier no node local (gateway, db, app)"
  for label in tier=gateway tier=db tier=app; do
    docker node update --label-add "$label" "$LOCAL_NODE_ID" >/dev/null
  done
fi

deploy_stack() {
  local file="$1"
  local name="$2"
  if [ ! -f "$file" ]; then
    echo "Arquivo não encontrado: $file" >&2
    exit 1
  fi
  echo "==> Deploy ${name} (${file})"
  docker stack deploy --with-registry-auth -c "$file" "$name"
}

deploy_stack "$ROOT/infra/traefik.yaml" infra_traefik
deploy_stack "$ROOT/infra/portainer.yaml" infra_portainer

if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_BOOTSTRAP_NAME}$"; then
  echo "==> Removendo contêiner bootstrap ${PORTAINER_BOOTSTRAP_NAME}"
  docker rm -f "$PORTAINER_BOOTSTRAP_NAME" >/dev/null
fi

echo "Pronto. Traefik e Portainer estão no ar. Acesse ${PORTAINER_HOST:-portainer}.${DOMINIO:-example.com} via Traefik."
