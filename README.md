# vps-infra

Manifests das aplicações do laboratório K3s, publicados pelo Argo CD.

## Organização

```text
cluster/argocd/application.yaml
cluster/argocd/applicationset.yaml
apps/minecraft/deployment.yaml
apps/minecraft/service.yaml
apps/minecraft/storage.yaml
```

Cada tipo de recurso tem seu próprio arquivo: `application.yaml` define a Application principal `infra`; `applicationset.yaml` define o ApplicationSet `apps`.

Cada pasta diretamente em `apps/` representa uma aplicação. O ApplicationSet descobre `apps/*` na branch `main`, gera as Applications e habilita a sincronização automática. Não há pipeline nem script de deploy neste repositório.

## Publicar uma aplicação

Criar `apps/nome-do-projeto/` com os manifests Kubernetes e publicar na `main`. O Argo descobre a pasta e aplica os recursos; não é necessário cadastrar cada aplicação pela interface nem executar outro comando na VPS.

O destino padrão é `laboratorio`, criado pelo Argo se necessário. As novas aplicações podem omitir `metadata.namespace` ou usar `laboratorio`; manter os nomes dos recursos únicos nesse namespace compartilhado. Pastas vazias não executam aplicações.

A consulta ao Git ocorre a cada 60 segundos, mas caches e os ciclos dos controllers podem aumentar o tempo até o cadastro ou deploy aparecer. O Argo também detecta Kustomize e Helm quando configurados na pasta da aplicação.

O merge na `main` libera o deploy. A pipeline de um futuro projeto pode testar, publicar sua imagem e abrir um PR neste repositório com a versão desejada. Ela não precisa acessar a VPS.

## Configuração inicial e recuperação

Com Argo CD instalado em `argocd`, cadastrar a Application principal uma vez:

```bash
kubectl apply -f https://raw.githubusercontent.com/Claudio-lunardi/vps-infra/main/cluster/argocd/application.yaml
kubectl -n argocd get applicationset,applications
```

A Application `infra` acompanha os YAMLs diretamente em `cluster/argocd`, incluindo seu próprio cadastro e o ApplicationSet. Depois do cadastro inicial, alterações nesses arquivos na `main` são sincronizadas automaticamente. Quem já aplicou o ApplicationSet pode cadastrar `infra` para que ela passe a gerenciar o mesmo recurso, sem excluí-lo ou recriá-lo.

Novas pastas em `apps/` continuam sendo descobertas pelo ApplicationSet. Após perder o cluster, reinstalar K3s e Argo e reaplicar `application.yaml` recupera os cadastros pelo Git; credenciais privadas e dados persistentes precisam de recuperação separada. Restringir alterações em `cluster/argocd` aos responsáveis pelo cluster, pois essa pasta controla o Argo e suas regras de deploy.

`prune: false` mantém desativada a exclusão automática de recursos. Remover uma pasta pode apagar seu cadastro no Argo, mas `preserveResourcesOnDeletion: true` preserva as cargas. Retirar um arquivo do Git não garante sua desinstalação do cluster.

## Minecraft

- Paper `26.3`, build `262`, uma réplica e estratégia `Recreate`.
- Service LoadBalancer publicando TCP `25565` pelo ServiceLB do K3s.
- PVC `minecraft-data`, solicitando 10 GiB com `local-path`, montado em `/data`.
- Heap inicial de 512 MB e máximo de 75% da memória detectada pela JVM. Sem limite Kubernetes de CPU ou memória; revisar ao adicionar outras cargas.
- Sem ConfigMaps nem instalação de plugins, datapacks ou ícone personalizado nos manifests atuais. Arquivos anteriormente copiados ao volume não são apagados por isso.

Entrar pelo Minecraft Java na versão do servidor usando `IP_DA_VPS:25565` ou seu domínio, com TCP 25565 liberada no firewall. O modo online exige conta válida. `EULA=TRUE` declara aceitação da [EULA do Minecraft](https://www.minecraft.net/en-us/eula).

Para alterar configurações, editar o Deployment e publicar no Git. Cada atualização do Deployment pode interromper brevemente o jogo, reutilizando o PVC. Manter uma réplica para evitar escrita simultânea no mundo.

`LEVEL` seleciona a pasta do mundo: mantê-lo para continuar o mesmo mundo. `SEED` só é usada ao gerar um mundo novo. Não excluir PVC, namespace ou diretórios para alterar configurações. A borda do Overworld é reaplicada ao iniciar pelos comandos RCON do Deployment.

A imagem base usa `latest`, separadamente da versão fixada do jogo e do Paper. Para atualizar o jogo, conferir compatibilidade, fazer backup consistente e alterar `VERSION` e `PAPER_BUILD`. Não fazer downgrade de um mundo já atualizado.

O `local-path` guarda os dados no disco da VPS; não é backup nem armazenamento replicado. A solicitação de 10 GiB não garante quota rígida nesse provisionador. O mundo exige backup separado.

## Diagnóstico

```bash
kubectl -n argocd get applicationset,applications
kubectl -n argocd describe applicationset apps
kubectl -n laboratorio get pods,services,pvc
kubectl -n laboratorio logs -f deployment/minecraft
```

Esperar `Done` nos logs antes de entrar no jogo. `Pending` pode indicar recursos ou volume pendente. Falhas em `manage-users` exigem conferir os nomes em `OPS` e `WHITELIST`.

## Acesso anterior da pipeline

O manifesto antigo foi retirado do Git. Isso não revoga ServiceAccount, token, Role ou RoleBinding existentes na VPS. Esse acesso também foi usado pelo K9s; revisar seus consumidores antes de revogá-lo. A chave SSH e eventuais Secrets antigos do GitHub também precisam de remoção separada. O Argo usa sua própria identidade e não depende desse acesso.

## Referências

- [ApplicationSet com gerador Git](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/)
- [Preservação de recursos](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Application-Deletion/)
- [Minecraft e Paper](https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/server-types/paper/)
