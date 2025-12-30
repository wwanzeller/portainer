# Infraestrutura Bootstrap (Traefik + Portainer)

Repositório público mínimo para subir apenas **Traefik** e **Portainer** no Docker Swarm.
O restante das stacks deve ser instalado pelo Portainer usando o repositório principal (privado).

## Pré-requisitos
- Docker instalado
- Acesso de usuário com permissão para executar Docker

## Configuração
1) Renomeie `.env.example` para `.env` e ajuste os valores:
   - `DOMINIO`
   - `EMAIL_GERAL`
   - `TRAEFIK_DASHBOARD_HOST`
   - `PORTAINER_HOST`

## Iniciar (Traefik + Portainer)
```bash
./scripts/iniciar.sh --env-file .env
```

O script:
- Inicia o Swarm (se ainda não estiver ativo)
- Cria as redes `traefik_public`, `wanzeller_network`, `agent_network`
- Cria os volumes `traefik_certificates` e `portainer_data`
- Faz o deploy de Traefik e Portainer

## Atualizar (Traefik + Portainer)
```bash
./scripts/atualizar.sh --env-file .env
```

## Executar direto da internet (sem clonar)
```bash
curl -fsSL https://raw.githubusercontent.com/wwanzeller/portainer/main/scripts/iniciar.sh \
| bash -s -- --env-file /caminho/absoluto/.env
```

## Notas
- Se usar outro repositório/ref, passe `--repo-url` e `--repo-ref` nos scripts.
- Para o repositório privado no Portainer, use autenticação (Username + Personal Access Token).
