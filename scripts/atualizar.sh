#!/usr/bin/env bash
set -euo pipefail

# Atualiza Traefik e Portainer (ou apenas um, se especificado).
# Usa o .env informado para preencher os YAMLs.
# Baixa os YAMLs direto do repositório (sem clone).
#
# Uso:
#   Atualizar ambos:  ./scripts/atualizar.sh --env-file .env
#   Atualizar um:     ./scripts/atualizar.sh --env-file .env infra/traefik.yaml infra_traefik

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
REPO_URL="${REPO_URL:-https://github.com/wwanzeller/portainer.git}"
REPO_REF="${REPO_REF:-main}"
REPO_RAW_BASE="${REPO_RAW_BASE:-}"
REPO_TOKEN="${REPO_TOKEN:-}"

usage() {
  cat <<EOF
Uso:
  $0 [--env-file PATH]                   # atualiza Traefik e Portainer
  $0 [--env-file PATH] <compose> <name>  # atualiza apenas a stack informada
  --env-file PATH     Caminho para o .env (default: $ENV_FILE)
  --repo-url URL      URL do repositório Git (default: $REPO_URL)
  --repo-ref REF      Branch/tag/commit (default: $REPO_REF)
  --raw-base URL      Base RAW (default: derivado do GitHub)
  --repo-token TOKEN  Token para repositório privado (ou use REPO_TOKEN)
Exemplos:
  $0 --env-file .env
  $0 --env-file .env infra/traefik.yaml infra_traefik
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
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
    --raw-base)
      REPO_RAW_BASE="${2:-}"
      shift 2
      ;;
    --repo-token)
      REPO_TOKEN="${2:-}"
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

COMPOSE_FILE="${1:-}"
STACK_NAME="${2:-}"

command -v docker >/dev/null 2>&1 || { echo "Falta o comando 'docker'."; exit 1; }

if [ ! -f "$ENV_FILE" ]; then
  echo "Arquivo de ambiente não encontrado: $ENV_FILE"
  exit 1
fi

if [ -z "$REPO_RAW_BASE" ]; then
  REPO_PATH="${REPO_URL#https://github.com/}"
  REPO_PATH="${REPO_PATH%.git}"
  REPO_PATH="${REPO_PATH%/}"
  if [ "$REPO_PATH" = "$REPO_URL" ]; then
    echo "Repo URL não reconhecida. Informe --raw-base."
    exit 1
  fi
  REPO_RAW_BASE="https://raw.githubusercontent.com/${REPO_PATH}/${REPO_REF}"
fi
REPO_RAW_BASE="${REPO_RAW_BASE%/}"

if command -v curl >/dev/null 2>&1; then
  DOWNLOAD_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOAD_TOOL="wget"
else
  echo "Falta 'curl' ou 'wget' para baixar os YAMLs."
  exit 1
fi

# Exporta variáveis do .env para o deploy (docker stack usa o ambiente atual)
set -a
source "$ENV_FILE"
set +a

download_stack() {
  local path="$1"
  local dest="$2"
  local url="${REPO_RAW_BASE}/${path}"
  echo "==> Baixando ${url}"
  if [ "$DOWNLOAD_TOOL" = "curl" ]; then
    if [ -n "$REPO_TOKEN" ]; then
      curl -fsSL -H "Authorization: token ${REPO_TOKEN}" "$url" -o "$dest"
    else
      curl -fsSL "$url" -o "$dest"
    fi
  else
    if [ -n "$REPO_TOKEN" ]; then
      wget -qO "$dest" --header="Authorization: token ${REPO_TOKEN}" "$url"
    else
      wget -qO "$dest" "$url"
    fi
  fi
}

deploy() {
  local compose_path="$1"
  local name="$2"
  local dest="$TMP_DIR/$(echo "$compose_path" | tr '/' '_')"
  download_stack "$compose_path" "$dest"
  echo "==> Atualizando stack ${name} com ${compose_path}"
  docker stack deploy --with-registry-auth -c "$dest" "$name"
}

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ -n "$COMPOSE_FILE" ] && [ -n "$STACK_NAME" ]; then
  deploy "$COMPOSE_FILE" "$STACK_NAME"
else
  deploy "infra/traefik.yaml" infra_traefik
  deploy "infra/portainer.yaml" infra_portainer
fi

echo "Feito."
