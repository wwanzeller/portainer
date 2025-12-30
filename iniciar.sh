#!/usr/bin/env bash
set -euo pipefail

# Inicializa Traefik + Portainer usando um .env.
# - Garante Swarm ativo
# - Cria networks padrão
# - (Opcional) Aplica labels de tier no node local
# - Faz deploy do Traefik e Portainer
#
# Uso: ./iniciar.sh --env-file .env

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
ENV_EXAMPLE="$ROOT/.env.example"
PORTAINER_BOOTSTRAP_NAME="${PORTAINER_BOOTSTRAP_NAME:-portainer-bootstrap}"
APPLY_LABELS=true
SKIP_ENV_CHECK=false

usage() {
  cat <<EOF
Uso: $0 [--env-file PATH] [--env-example PATH] [--no-labels] [--skip-env-check]
  --env-file PATH     Caminho para o arquivo .env (default: $ENV_FILE)
  --env-example PATH  Caminho para o .env.example (default: $ENV_EXAMPLE)
  --no-labels         Não aplica labels de tier no node local
  --skip-env-check    Não valida o .env (evita prompt duplicado)
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
    --skip-env-check)
      SKIP_ENV_CHECK=true
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

prompt_yes_no() {
  local question="$1"
  local answer=""
  if [ ! -r /dev/tty ]; then
    echo "Sem TTY para prompt. Use --env-file ou crie o .env manualmente." >&2
    exit 1
  fi
  read -r -p "${question} [S/n]: " answer < /dev/tty || true
  case "${answer}" in
    [nN][aA][oO]|[nN])
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

prompt_value() {
  local label="$1"
  local default="$2"
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
      printf '%s' "$value"
      return
    fi
  done
}

create_env_from_example() {
  if [ ! -f "$ENV_EXAMPLE" ]; then
    echo "Arquivo .env.example não encontrado: $ENV_EXAMPLE" >&2
    exit 1
  fi
  echo "Arquivo .env ausente ou incompleto. Vamos criar/atualizar via prompt..."
  local required_keys=()
  if prompt_yes_no "O domínio já está apontado para este servidor"; then
    echo "Ok. Vamos pedir DOMINIO e EMAIL_GERAL."
    required_keys+=(DOMINIO EMAIL_GERAL)
  else
    echo "Sem domínio configurado. Usando valores padrão do .env.example para DOMINIO/EMAIL."
  fi
  mkdir -p "$(dirname "$ENV_FILE")"
  if [ -f "$ENV_FILE" ] && [ ! -w "$ENV_FILE" ]; then
    chmod u+w "$ENV_FILE" 2>/dev/null || { echo "Sem permissao para escrever em $ENV_FILE"; exit 1; }
  fi
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
      local should_prompt=false
      for required in "${required_keys[@]}"; do
        if [ "$key" = "$required" ]; then
          should_prompt=true
          break
        fi
      done
      if [ -n "$existing" ]; then
        value="$existing"
      elif [ "$should_prompt" = true ]; then
        value="$(prompt_value "$key" "$default")"
      else
        value="$default"
      fi
      value="$(format_env_value "$value")"
      env_lines+=("${key}=${value}")
    fi
  done < "$ENV_EXAMPLE"
  printf '%s\n' "${env_lines[@]}" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Arquivo criado: $ENV_FILE"
}


env_has_extra_keys() {
  [ -f "$ENV_FILE" ] || return 1
  [ -f "$ENV_EXAMPLE" ] || return 1
  local line
  local key
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#${line%%[![:space:]]*}}"
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      key="${line%%=*}"
      if ! grep -q "^${key}=" "$ENV_EXAMPLE"; then
        return 0
      fi
    fi
  done < "$ENV_FILE"
  return 1
}

env_needs_rebuild() {
  if [ ! -f "$ENV_FILE" ]; then
    return 0
  fi
  set -a
  source "$ENV_FILE"
  set +a
  if [ -z "${DOMINIO:-}" ] || [ -z "${EMAIL_GERAL:-}" ] || [ -z "${TRAEFIK_DASHBOARD_HOST:-}" ] || [ -z "${PORTAINER_HOST:-}" ]; then
    return 0
  fi
  if env_has_extra_keys; then
    return 0
  fi
  return 1
}

command -v docker >/dev/null 2>&1 || { echo "Falta o comando 'docker'."; exit 1; }

if [ "$SKIP_ENV_CHECK" = true ]; then
  if [ ! -f "$ENV_FILE" ]; then
    create_env_from_example
  fi
elif env_needs_rebuild; then
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

if [ -n "${DOMINIO:-}" ]; then
  echo "Pronto. Traefik e Portainer estão no ar. Acesse portainer.${DOMINIO} via Traefik."
else
  echo "Pronto. Traefik e Portainer estão no ar. Defina DOMINIO no .env para acessar portainer.DOMINIO."
fi
