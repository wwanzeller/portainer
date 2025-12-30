# Infraestrutura Bootstrap (Traefik + Portainer)

Repositório público mínimo para subir apenas **Traefik** e **Portainer** no Docker Swarm.
O restante das stacks deve ser instalado pelo Portainer usando o repositório principal (privado).

## Pré-requisitos
- Docker instalado
- Acesso de usuário com permissão para executar Docker

## Instalar (via curl)
O instalador clona este repositório para um diretório chamado **infraestrutura** e cria o `.env` via prompt.
Ele pergunta se o domínio já está configurado. Se sim, pede:
- `DOMINIO` (ex: suaempresa.com)
- `EMAIL_GERAL` (usado pelo Let's Encrypt do Traefik)

Os subdomínios padrão já vêm definidos no `.env`:
- `TRAEFIK_DASHBOARD_HOST=traefik`
- `PORTAINER_HOST=portainer`

No final, ele chama `./iniciar.sh` e sobe Traefik e Portainer.

Exemplo padrão (cria `./infraestrutura` no diretório atual):
```bash
curl -fsSL https://github.com/wwanzeller/portainer/raw/main/instalar.sh \
| bash
```

Após rodar, o diretório ficará em `./infraestrutura` e o `.env` em `./infraestrutura/.env`.

## Iniciar (Traefik + Portainer)
O instalador já executa este passo. Se quiser rodar novamente:
```bash
cd infraestrutura
./iniciar.sh --env-file .env
```

## Atualizar (reiniciar serviços)
- Todas as stacks ativas:
```bash
./atualizar.sh --env-file .env
```
- Apenas stacks específicas:
```bash
./atualizar.sh --env-file .env infra_traefik infra_portainer
```

## Parar (remover stacks)
- Todas:
```bash
./parar.sh
```
- Específicas:
```bash
./parar.sh infra_traefik infra_portainer
```

## Desinstalar (remove o diretório)
```bash
./desinstalar.sh
```

> **Volumes não são removidos** em nenhuma etapa.

## Notas
- Este `.env` é apenas para Traefik e Portainer.
- As demais stacks devem ser criadas no Portainer (Stack > Repository) usando o repositório principal e um `.env` próprio de cada stack.
- Para repositório privado, use autenticação (Username + Personal Access Token).
