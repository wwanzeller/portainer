#!/usr/bin/env bash
set -euo pipefail

# Instalador para bootstrap (clona o repo e cria o .env via prompt).
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/wwanzeller/portainer/main/instalar.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/wwanzeller/portainer/main/instalar.sh | bash -s -- --dir /opt

REPO_URL="${REPO_URL:-https://github.com/wwanzeller/portainer.git}"
REPO_REF="${REPO_REF:-main}"
INSTALL_DIR=""
ENV_FILE=""
ENV_EXAMPLE=""
FORCE_ENV=false

usage() {
  cat <<EOF
Uso: $0 [--dir PATH] [--repo-url URL] [--repo-ref REF] [--env-file PATH] [--env-example PATH] [--force-env]
  --dir PATH         Diretório base ou completo (cria <PATH>/infraestrutura se não terminar com infraestrutura)
  --repo-url URL     URL do repositório Git (default: $REPO_URL)
  --repo-ref REF     Branch/tag/commit (default: $REPO_REF)
  --env-file PATH    Caminho para o .env (default: <dir>/infraestrutura/.env)
  --env-example PATH Caminho para o .env.example (default: <dir>/infraestrutura/.env.example)
  --force-env        Recria o .env via prompt mesmo se já existir
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --repo-ref)
      REPO_REF="${2:-}"
      shift 2
      ;;
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --env-example)
      ENV_EXAMPLE="${2:-}"
      shift 2
      ;;
    --force-env)
      FORCE_ENV=true
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

normalize_install_dir() {
  local dir="$1"
  if [ -z "$dir" ]; then
    dir="$PWD"
  fi
  if [ "$(basename "$dir")" != "infraestrutura" ]; then
    dir="${dir%/}/infraestrutura"
  fi
  printf '%s' "$dir"
}

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
  echo "Criando .env via prompt..."
  echo "Vamos pedir DOMINIO, EMAIL_GERAL, USUARIO e SENHA_GERAL; os demais usam o padrão do .env.example."
  mkdir -p "$(dirname "$ENV_FILE")"
  local required_keys=(DOMINIO EMAIL_GERAL USUARIO SENHA_GERAL)
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

command -v git >/dev/null 2>&1 || { echo "Falta o comando 'git'."; exit 1; }

INSTALL_DIR="$(normalize_install_dir "$INSTALL_DIR")"

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "Atualizando repositório em $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch --all --prune
  git -C "$INSTALL_DIR" checkout "$REPO_REF" >/dev/null 2>&1 || true
  git -C "$INSTALL_DIR" pull --ff-only origin "$REPO_REF" || git -C "$INSTALL_DIR" pull --ff-only
elif [ -e "$INSTALL_DIR" ]; then
  echo "Diretório já existe e não é um repositório Git: $INSTALL_DIR" >&2
  echo "Escolha outro com --dir ou remova o diretório atual." >&2
  exit 1
else
  echo "Clonando repositório em $INSTALL_DIR"
  git clone --branch "$REPO_REF" "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR"/scripts/*.sh

ENV_FILE="${ENV_FILE:-$INSTALL_DIR/.env}"
ENV_EXAMPLE="${ENV_EXAMPLE:-$INSTALL_DIR/.env.example}"

if [ ! -f "$ENV_FILE" ] || [ "$FORCE_ENV" = true ]; then
  create_env_from_example
else
  echo "Usando .env existente em $ENV_FILE"
fi

echo "Instalação concluída."
echo "Próximo passo:"
echo "  cd $INSTALL_DIR"
echo "  ./scripts/iniciar.sh --env-file $ENV_FILE"
