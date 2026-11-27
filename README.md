# vps-infra

Servidor Minecraft Java com Paper no K3s, fixado na versão `26.3` e build Paper `262`, no namespace `laboratorio`.

## Organização

```text
namespaces/laboratorio.yaml
cluster/argocd/applicationset.yaml
apps/minecraft/deployment.yaml
apps/minecraft/service.yaml
apps/minecraft/storage.yaml
```

- Deployment: executa um servidor, com heap Java inicial de 512 MB e máximo de 75% da memória disponível detectada pela JVM. Não há teto de CPU nem limite Kubernetes de memória para o container.
- Service: publica TCP 25565 pelo ServiceLB incluído na instalação padrão do K3s.
- Storage: solicita 10 GiB para o mundo e configurações em `/data`, usando a StorageClass `local-path` do K3s.

Cada pasta diretamente em `apps/` representa uma aplicação. O Kubernetes sozinho não acompanha o Git: no deploy manual, `kubectl apply` lê os YAMLs e envia os recursos ao cluster. Com o ApplicationSet ativado, o Argo CD descobre essas pastas e aplica suas alterações automaticamente após o merge na `main`.

## Validação pelo GitHub

O workflow `.github/workflows/deploy-minecraft.yaml` agora apenas valida os manifests, sem acessar a VPS. O deploy automático é feito pelo Argo CD. Os detalhes e a retirada do acesso antigo estão em [docs/github-actions.md](docs/github-actions.md).

## Argo CD

O ApplicationSet em `cluster/argocd/applicationset.yaml` descobre cada pasta de `apps/*` e gera seu cadastro com sincronização automática. O destino padrão é `laboratorio`. A ativação e a transição estão em [docs/argocd.md](docs/argocd.md).

O Minecraft usa apenas Deployment, Service e PVC. Os ConfigMaps e a instalação de plugins, datapacks e ícone personalizado foram retirados desta configuração.

O script `apps/minecraft/deploy.sh` permanece apenas como alternativa manual usando `kubectl apply -f`; não é usado pelo workflow nem deve concorrer com o Argo. Antes de ativar o ApplicationSet, desativar o deploy antigo no GitHub e aguardar qualquer execução terminar. A regra ainda não foi aplicada ao cluster.

## Requisitos

K3s padrão funcionando, porta TCP 25565 disponível e espaço em disco para o mundo. A capacidade depende da RAM e CPU disponíveis, dos jogadores e do mundo. O agendamento solicita 1 GiB de memória e 0,5 CPU; esses valores não são o teto de uso.

A imagem comunitária `itzg/minecraft-server` baixa e executa o Paper com `TYPE=PAPER`. O Deployment usa `EULA=TRUE`: iniciar o servidor aceita a [EULA do Minecraft](https://www.minecraft.net/en-us/eula). O modo online está habilitado e exige conta válida do Minecraft Java.

## Aplicar na VPS

Se já estiver rodando vanilla, faça backup de todo o volume `/data` com o servidor parado antes da primeira troca para Paper. A mudança reinicia o servidor e o Paper pode reorganizar os diretórios das dimensões. Os YAMLs mantêm o mesmo PVC e a mesma seed; não exclua o volume nem o namespace. Depois da migração, confira a saúde do servidor e o mundo: este repositório foi validado localmente, mas a execução no jogo precisa ser verificada na VPS.

Atualize ou copie o repositório para a VPS por Git ou SFTP. Na sessão SSH como root, dentro de `vps-infra`:

```bash
kubectl get nodes
kubectl get storageclass
kubectl apply -f namespaces/
```

Se o exemplo antigo do Nginx foi aplicado, remova seus recursos. Apenas substituir os arquivos não os remove do cluster:

```bash
kubectl -n laboratorio delete deployment/site service/site --ignore-not-found
```

Suba o Minecraft:

```bash
kubectl apply -f apps/minecraft/
kubectl -n laboratorio rollout status deployment/minecraft --timeout=900s
kubectl -n laboratorio get pods,services,pvc
```

A primeira inicialização baixa o servidor e gera o mundo. Para acompanhar em outra sessão SSH:

```bash
kubectl -n laboratorio logs -f deployment/minecraft
```

Espere a mensagem `Done` antes de entrar. Ctrl+C encerra apenas o acompanhamento dos logs.

Para aplicar também futuras aplicações em subpastas:

```bash
kubectl apply -f namespaces/
kubectl apply -f apps/nome-do-projeto/
```

## Entrar no jogo

No Minecraft Java, abra **Multijogador → Adicionar servidor** e informe `IP_DA_VPS:25565`. Use a mesma versão de Minecraft indicada nos logs do servidor.

Libere entrada TCP 25565 no firewall do provedor e no firewall do Linux, caso exista. Se o UFW já estiver ativo, adicione a regra:

```bash
ufw allow 25565/tcp
```

Não é necessário habilitar o UFW para o exemplo. O ServiceLB do K3s precisa estar habilitado e a porta 25565 livre. RCON está habilitado internamente para aplicar a borda ao iniciar; sua porta não é publicada pelo Service, e a imagem gera a senha em tempo de execução.

## Configuração e atualizações

### Variáveis e recursos

Edite as variáveis em `apps/minecraft/deployment.yaml` e aplique a pasta novamente.

O bloco `env` contém comentários com opções comuns: tipo de servidor, modo de jogo, dificuldade, PvP, whitelist, administradores, mundo e permissões. As opções comentadas são exemplos, não configurações ativas nem uma lista completa. Para ativar uma delas, remova o `#` das linhas `- name` e `value`, ajuste o valor e aplique novamente. Confira a compatibilidade com sua versão na documentação da imagem. Comentar uma variável já aplicada não necessariamente desfaz seu efeito: algumas configurações ficam salvas em `/data`.

`INIT_MEMORY=512M` inicia o heap pequeno, e `MAX_MEMORY=75%` permite crescer conforme a demanda até esse percentual da memória detectada pela JVM. Não há reserva antecipada do máximo. Sem limite de memória no container, normalmente a JVM detecta a RAM do nó, considerando eventuais limites de cgroup do ambiente. O processo usa memória adicional fora do heap; 75% não é um limite para a memória total do container nem garante que os outros 25% fiquem livres para o sistema.

Sem limite de CPU, o servidor pode usar a capacidade livre do nó, compartilhando-a com os outros processos. Isso não garante ausência de lag: o desempenho também depende da CPU e do mundo. O teto percentual não acompanha a memória livre dos outros aplicativos; se adicionar outras cargas à VPS, revise o percentual ou defina um limite de memória para o container com folga acima do heap.

Mantenha `replicas: 1`. A estratégia `Recreate` encerra o Pod anterior antes de criar o próximo durante atualizações, evitando escrita simultânea no mundo.

`VERSION=26.3` fixa a versão do jogo e `PAPER_BUILD=262` fixa a build estável do Paper: reinícios não atualizam essas versões. A imagem base `itzg/minecraft-server:latest` continua recebendo atualizações próprias, separadas da versão do jogo. Para reiniciar mantendo a versão configurada:

```bash
kubectl -n laboratorio rollout restart deployment/minecraft
kubectl -n laboratorio rollout status deployment/minecraft --timeout=900s
```

Para atualizar o jogo, faça backup do mundo, altere `VERSION` e `PAPER_BUILD` para uma combinação disponível e aplique o Deployment novamente. Para atualizar só o Paper dentro da mesma versão do Minecraft, altere `PAPER_BUILD`. Não faça downgrade de um mundo já atualizado.

## Dados e remoção

### Seed escolhida

`SEED=2048005618087379093`: seed anterior do repositório, selecionada novamente para gerar um mundo zerado. A versão do jogo e a build do Paper continuam fixadas; a mudança é na seed e no nome da pasta do mundo.

A seed só é usada ao gerar um mundo novo. O Deployment usa `LEVEL=brian-cerejeiras-20261126` para gerar outro mundo no mesmo volume, preservando `/data/world`, `/data/brian-limitado` e suas dimensões. Jogadores começam no novo mundo, com progresso e construções separados. Os dados globais dos plugins continuam no mesmo volume. Mantenha o nome `brian-cerejeiras-20261126` nos próximos deploys; apenas a primeira inicialização gera o novo mundo. Se já houver um mundo com esse nome, ele será reutilizado, e a seed não será substituída.

### Borda do mundo

`RCON_CMDS_STARTUP` aplica automaticamente uma borda de 10.000 × 10.000 blocos no Overworld, centrada em X=0, Z=0, após iniciar. São 5.000 blocos para cada lado; essa configuração não limita separadamente Nether e End. Não há remoção de chunks nem pré-geração do mapa inteiro. A borda é reaplicada em cada reinício; para mudar o tamanho permanentemente, altere o YAML.

Antes da primeira aplicação, faça backup do volume com o servidor parado. Atualize o repositório na VPS e aplique:

```bash
kubectl apply -f apps/minecraft/
kubectl -n laboratorio rollout status deployment/minecraft --timeout=900s
kubectl -n laboratorio logs -f deployment/minecraft
```

Depois de aparecer `Done`, confira a seed e a borda do mundo no jogo.

Para voltar ao mundo imediatamente anterior, restaure `LEVEL=brian-limitado` e `SEED=8500081009970950196` e aplique novamente. Para selecionar o mundo mais antigo, use `LEVEL=world`. Não apague nenhum PVC ou diretório. O novo mundo permanece no volume. Arquivos e plugins já existentes no volume não são removidos por esta alteração de manifests.

Referência: [execução automática de comandos RCON pela imagem](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/auto-rcon-commands/).

O volume sobrevive à recriação do Pod ou Deployment. O `local-path` guarda os arquivos no disco de um nó; não é backup nem armazenamento replicado. A solicitação de 10 GiB não é garantia de quota rígida de disco nesse provisionador.

Para remover o servidor e o acesso, mantendo o mundo:

```bash
kubectl -n laboratorio delete deployment/minecraft service/minecraft
```

Para recriar, aplique a pasta novamente. Evite `kubectl delete -f apps/minecraft/` ou excluir o namespace se quer preservar o mundo: isso também remove o PVC e pode apagar os dados.

## Diagnóstico

```bash
kubectl -n laboratorio get pods,services,pvc
kubectl -n laboratorio describe deployment minecraft
kubectl -n laboratorio get events --sort-by=.metadata.creationTimestamp
```

Pod `Pending` pode indicar recursos insuficientes ou volume pendente. Se não conectar, confira a mensagem `Done`, versão do cliente, Service e firewalls.

Se a inicialização falhar em `manage-users` com `Could not resolve user`, confira os nomes em `OPS` e `WHITELIST`: devem ser perfis de Minecraft Java, que podem diferir do gamertag Xbox/Microsoft. Um nome inválido pode impedir a inicialização. `USER_API_PROVIDER=mojang` usa a API da Mojang em vez do PlayerDB; isso pode contornar falhas do provedor, mas não corrige nomes inexistentes. Consulte o [guia de resolução de usuários](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/server-properties/#changing-user-api-provider).

## Referências

- [Paper na imagem de Minecraft](https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/server-types/paper/)
- [Migração do mundo para Paper](https://docs.papermc.io/paper/migration/)

- [Imagem Minecraft Java e armazenamento](https://docker-minecraft-server.readthedocs.io/en/latest/)
- [Versões do Minecraft](https://docker-minecraft-server.readthedocs.io/en/latest/versions/minecraft/)
- [Memória inicial, máxima e percentuais](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/jvm-options/)
- [ServiceLB do K3s](https://docs.k3s.io/networking/networking-services)
- [Aplicar YAMLs e diretórios](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
