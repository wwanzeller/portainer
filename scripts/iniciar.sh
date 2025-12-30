#!/usr/bin/env bash
set -euo pipefail

# Inicializa somente Traefik + Portainer usando um .env.
# - Garante Swarm ativo
# - Cria networks padrão
# - (Opcional) Aplica labels de tier no node local
# - Baixa os YAMLs direto do repositório (sem clone)
# - Faz deploy do Traefik e Portainer
#
# Uso: ./scripts/iniciar.sh --env-file .env

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
PORTAINER_BOOTSTRAP_NAME="${PORTAINER_BOOTSTRAP_NAME:-portainer-bootstrap}"
APPLY_LABELS=true
REPO_URL="${REPO_URL:-https://github.com/wwanzeller/infraestrutura-bootstrap.git}"
REPO_REF="${REPO_REF:-main}"
REPO_RAW_BASE="${REPO_RAW_BASE:-}"
REPO_TOKEN="${REPO_TOKEN:-}"

usage() {
  cat <<EOF
Uso: $0 [--env-file PATH] [--no-labels] [--repo-url URL] [--repo-ref REF] [--raw-base URL] [--repo-token TOKEN]
  --env-file PATH     Caminho para o arquivo .env (default: $ENV_FILE)
  --no-labels         Não aplica labels de tier no node local
  --repo-url URL      URL do repositório Git (default: $REPO_URL)
  --repo-ref REF      Branch/tag/commit (default: $REPO_REF)
  --raw-base URL      Base RAW (default: derivado do GitHub)
  --repo-token TOKEN  Token para repositório privado (ou use REPO_TOKEN)
EOF
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --no-labels)
      APPLY_LABELS=false
      shift
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
      usage
      ;;
  esac
done

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
  echo "==> Deploy ${name} (${file})"
  docker stack deploy --with-registry-auth -c "$file" "$name"
}

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

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

download_stack "infra/traefik.yaml" "$TMP_DIR/traefik.yaml"
download_stack "infra/portainer.yaml" "$TMP_DIR/portainer.yaml"

deploy_stack "$TMP_DIR/traefik.yaml" infra_traefik
deploy_stack "$TMP_DIR/portainer.yaml" infra_portainer

if docker ps --format '{{.Names}}' | grep -q "^${PORTAINER_BOOTSTRAP_NAME}$"; then
  echo "==> Removendo contêiner bootstrap ${PORTAINER_BOOTSTRAP_NAME}"
  docker rm -f "$PORTAINER_BOOTSTRAP_NAME" >/dev/null
fi

echo "Pronto. Traefik e Portainer estão no ar. Acesse ${PORTAINER_HOST:-portainer}.${DOMINIO:-example.com} via Traefik."
