#!/usr/bin/env bash
set -euo pipefail

# Atualiza/reinicia stacks.
# - Se nenhuma stack for informada, reinicia todas as stacks ativas.
# - Se informar stacks, reinicia apenas as passadas.
# - Para Traefik/Portainer, aplica o YAML local (docker stack deploy).
#
# Uso:
#   ./atualizar.sh --env-file .env
#   ./atualizar.sh --env-file .env infra_traefik infra_portainer

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
ENV_EXAMPLE="$ROOT/.env.example"

usage() {
  cat <<EOF
Uso: $0 [--env-file PATH] [--env-example PATH] [STACK ...]
  --env-file PATH     Caminho para o .env (default: $ENV_FILE)
  --env-example PATH  Caminho para o .env.example (default: $ENV_EXAMPLE)
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
    -h|--help)
      usage
      ;;
    *)
      break
      ;;
  esac
done

STACKS=("$@")

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
  read -r -p "${question} [s/N]: " answer < /dev/tty || true
  case "${answer}" in
    [sS][iI][mM]|[sS])
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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
  local required_keys=(USUARIO SENHA_GERAL)
  if prompt_yes_no "O domínio já está apontado para este servidor"; then
    echo "Ok. Vamos pedir DOMINIO, EMAIL_GERAL e PORTAINER_HOST."
    required_keys+=(DOMINIO EMAIL_GERAL PORTAINER_HOST)
  else
    echo "Sem domínio configurado. Usando valores padrão do .env.example para DOMINIO/EMAIL/PORTAINER_HOST."
  fi
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
        prompt_value value "$key" "$default"
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

command -v docker >/dev/null 2>&1 || { echo "Falta o comando 'docker'."; exit 1; }

if [ ! -f "$ENV_FILE" ]; then
  create_env_from_example
fi

# Exporta variáveis do .env para o deploy (docker stack usa o ambiente atual)
set -a
source "$ENV_FILE"
set +a

if [ ${#STACKS[@]} -eq 0 ]; then
  mapfile -t STACKS < <(docker stack ls --format '{{.Name}}')
fi

if [ ${#STACKS[@]} -eq 0 ]; then
  echo "Nenhuma stack encontrada para atualizar."
  exit 0
fi

restart_services() {
  local stack="$1"
  local services
  services="$(docker stack services --format '{{.Name}}' "$stack" 2>/dev/null || true)"
  if [ -z "$services" ]; then
    echo "Stack não encontrada ou sem serviços: $stack"
    return
  fi
  while IFS= read -r service; do
    [ -z "$service" ] && continue
    echo "==> Reiniciando serviço ${service}"
    docker service update --force "$service" >/dev/null
  done <<< "$services"
}

for stack in "${STACKS[@]}"; do
  case "$stack" in
    infra_traefik)
      if [ -f "$ROOT/infra/traefik.yaml" ]; then
        echo "==> Atualizando stack ${stack} (traefik.yaml)"
        docker stack deploy --with-registry-auth -c "$ROOT/infra/traefik.yaml" infra_traefik
        continue
      fi
      ;;
    infra_portainer)
      if [ -f "$ROOT/infra/portainer.yaml" ]; then
        echo "==> Atualizando stack ${stack} (portainer.yaml)"
        docker stack deploy --with-registry-auth -c "$ROOT/infra/portainer.yaml" infra_portainer
        continue
      fi
      ;;
  esac
  restart_services "$stack"
done

echo "Feito."
