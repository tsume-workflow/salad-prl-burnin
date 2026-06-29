# Salad PRL Burn-in

Runner separado para medir hashrate real de PRL na Salad sem misturar com a calculadora nem com a mineracao local.

Estado de seguranca:

- O CLI usa `GET/POST` de leitura para disponibilidade e gera plano em dry-run por padrao.
- `create`, `start`, `stop` e `delete` exigem `--execute --confirm <container_group_name>`.
- O payload de criacao usa `autostart_policy=false` e `restart_policy=never`.
- O WildRig encerra com `BURNIN_SECONDS`; depois disso o container fica idle por padrao, aguardando `stop/delete` externo do container group.
- Para operacao continua, use `BURNIN_SECONDS=0` ou `BURNIN_SECONDS=continuous`.
- Nenhum `SALAD_API_KEY` fica dentro da imagem ou dos arquivos deste diretorio.
- Planos salvos em `plans/*.json` podem conter a wallet no payload de ambiente; a pasta esta no `.gitignore`.

Fontes usadas:

- Salad Create Container Group: https://docs.salad.com/reference/saladcloud-api/container-groups/create-container-group
- Salad OpenAPI: https://github.com/SaladTechnologies/salad-cloud-docs/blob/main/api-specs/salad-cloud.yaml
- Pearlhash HiveOS config: https://pearlhash.xyz/hiveos
- WildRig releases: https://github.com/andru-kun/wildrig-multi/releases

## Imagem

Build local:

```bash
docker build -t salad-prl-burnin:0.1.4 .
```

Para Salad, a imagem precisa estar em um registry acessivel pela Salad:

```bash
docker tag salad-prl-burnin:0.1.4 REGISTRY/salad-prl-burnin:0.1.4
docker push REGISTRY/salad-prl-burnin:0.1.4
```

Depois salve o nome:

```bash
export SALAD_BURNIN_IMAGE=REGISTRY/salad-prl-burnin:0.1.4
```

## Burn-in

Ver disponibilidade dos alvos:

```bash
node salad-burnin.js availability
```

Listar estado atual do projeto operacional:

```bash
node salad-burnin.js list
```

Gerar plano da 5090 Laptop em Lowest/batch por 20 minutos:

```bash
node salad-burnin.js plan \
  --gpu "RTX 5090 Laptop (24 GB)" \
  --priority batch \
  --minutes 20 \
  --image "$SALAD_BURNIN_IMAGE" \
  --save
```

Executar so depois de revisar o JSON:

```bash
node salad-burnin.js create --plan plans/prl-burnin-...json --execute --confirm prl-burnin-...
node salad-burnin.js start --name prl-burnin-... --execute --confirm prl-burnin-...
node salad-burnin.js instances --name prl-burnin-...
node salad-burnin.js stop --name prl-burnin-... --execute --confirm prl-burnin-...
node salad-burnin.js delete --name prl-burnin-... --execute --confirm prl-burnin-...
```

## Matriz inicial

Prioridade A:

- RTX 5090 Laptop (24 GB)
- RTX 5090 (32 GB)
- RTX 4090 (24 GB)

Prioridade B:

- RTX 5080 (16 GB)
- RTX 5070 Ti (16 GB)
- RTX 4080 (16 GB)
- RTX 4070 Ti Super (16 GB)
- RTX 3060 Ti (8 GB)
