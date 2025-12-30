# Infraestrutura Bootstrap (Traefik + Portainer)

Repositório público mínimo para subir apenas **Traefik** e **Portainer** no Docker Swarm.
O restante das stacks deve ser instalado pelo Portainer usando o repositório principal (privado).

## Pré-requisitos
- Docker instalado
- Acesso de usuário com permissão para executar Docker

## Instalar (via curl)
O instalador clona este repositório para um diretório chamado **infraestrutura** e cria o `.env` via prompt.
Ele pergunta `DOMINIO`, `EMAIL_GERAL`, `USUARIO` e `SENHA_GERAL`; o restante usa o padrão do `.env.example`.

Exemplo padrão (cria `./infraestrutura` no diretório atual):
```bash
curl -fsSL https://raw.githubusercontent.com/wwanzeller/portainer/main/instalar.sh \
| bash
```

Após rodar, o diretório ficará em `./infraestrutura` e o `.env` em `./infraestrutura/.env`.

## Iniciar (Traefik + Portainer)
```bash
cd infraestrutura
./scripts/iniciar.sh --env-file .env
```

## Atualizar (reiniciar serviços)
- Todas as stacks ativas:
```bash
./scripts/atualizar.sh --env-file .env
```
- Apenas stacks específicas:
```bash
./scripts/atualizar.sh --env-file .env infra_traefik infra_portainer
```

## Parar (remover stacks)
- Todas:
```bash
./scripts/parar.sh
```
- Específicas:
```bash
./scripts/parar.sh infra_traefik infra_portainer
```

## Desinstalar (remove o diretório)
```bash
./scripts/desinstalar.sh
```

> **Volumes não são removidos** em nenhuma etapa.

## Notas
- O `.env` gerado aqui pode ser reutilizado nas stacks do repositório principal.
- Para o repositório privado no Portainer, use autenticação (Username + Personal Access Token).
