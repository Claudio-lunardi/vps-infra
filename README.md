# vps-infra

Servidor Minecraft Java com Paper no K3s, fixado na versão `26.3` e build Paper `262`, no namespace `laboratorio`.

## Organização

```text
namespaces/laboratorio.yaml
apps/minecraft/deployment.yaml
apps/minecraft/service.yaml
apps/minecraft/storage.yaml
apps/minecraft/datapacks.yaml
apps/minecraft/essentials.yaml
apps/minecraft/server-icon.yaml
apps/minecraft/assets/server-icon.png
```

- Deployment: executa um servidor, com heap Java inicial de 512 MB e máximo de 75% da memória disponível detectada pela JVM. Não há teto de CPU nem limite Kubernetes de memória para o container.
- Service: publica TCP 25565 pelo ServiceLB incluído na instalação padrão do K3s.
- Storage: solicita 10 GiB para o mundo e configurações em `/data`, usando a StorageClass `local-path` do K3s.
- Datapacks: ConfigMap com a seleção do Vanilla Tweaks para Minecraft 26.3. A imagem instala Timber, Graves e Fast Leaf Decay no mundo ao iniciar, sem exigir instalação dos jogadores.
- Ícone: PNG de 64x64 do Os Brian incluído no ConfigMap `minecraft-server-icon`. A imagem copia o arquivo para o servidor usando `ICON` e `OVERRIDE_ICON=TRUE`, sem baixar arte de sites externos.

Cada pasta em `apps/` representa uma aplicação. O Kubernetes não acompanha a pasta ou o Git: `kubectl apply` lê os YAMLs e envia os recursos ao cluster. Depois de editar, aplique novamente. Remover um YAML do Git não exclui seu recurso do cluster.

## Deploy automático pelo GitHub

O workflow `.github/workflows/deploy-minecraft.yaml` executa no GitHub e faz o deploy por SSH na VPS, sem runner instalado nela. A preparação manual do usuário, chave SSH, permissões Kubernetes e Secrets está em [docs/github-actions.md](docs/github-actions.md). O job só executa na `main` com a variável `ENABLE_DEPLOY=true`.

Depois da preparação, mudanças em `apps/minecraft/` enviadas à `main` aplicam os manifests e aguardam o rollout. O script `apps/minecraft/deploy.sh` inclui um hash dos YAMLs no Pod para recarregar também mudanças nos ConfigMaps, sem reiniciar ao reaplicar os mesmos arquivos. Atualizações interrompem brevemente o jogo e preservam o PVC existente. Os comandos manuais abaixo continuam disponíveis; a configuração SSH e o primeiro deploy pela pipeline ainda precisam ser validados na VPS.

## Requisitos

K3s padrão funcionando, porta TCP 25565 disponível e espaço em disco para o mundo. A capacidade depende da RAM e CPU disponíveis, dos jogadores e do mundo. O agendamento solicita 1 GiB de memória e 0,5 CPU; esses valores não são o teto de uso.

A imagem comunitária `itzg/minecraft-server` baixa e executa o Paper com `TYPE=PAPER`. O Deployment usa `EULA=TRUE`: iniciar o servidor aceita a [EULA do Minecraft](https://www.minecraft.net/en-us/eula). O modo online está habilitado e exige conta válida do Minecraft Java.

## Aplicar na VPS

Se já estiver rodando vanilla, faça backup de todo o volume `/data` com o servidor parado antes da primeira troca para Paper. A mudança reinicia o servidor e o Paper pode reorganizar os diretórios das dimensões. Os YAMLs mantêm o mesmo PVC e a mesma seed; não exclua o volume nem o namespace. Depois da migração, teste farms, redstone e os três datapacks: este repositório foi validado localmente, mas a execução no jogo precisa ser verificada na VPS.

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
kubectl apply -R -f apps/
```

## Entrar no jogo

No Minecraft Java, abra **Multijogador → Adicionar servidor** e informe `IP_DA_VPS:25565`. Use a mesma versão de Minecraft indicada nos logs do servidor.

Libere entrada TCP 25565 no firewall do provedor e no firewall do Linux, caso exista. Se o UFW já estiver ativo, adicione a regra:

```bash
ufw allow 25565/tcp
```

Não é necessário habilitar o UFW para o exemplo. O ServiceLB do K3s precisa estar habilitado e a porta 25565 livre. RCON está habilitado internamente para aplicar a borda ao iniciar; sua porta não é publicada pelo Service, e a imagem gera a senha em tempo de execução.

## Configuração e atualizações

### WorldEdit

WorldEdit `7.4.6` estável foi adicionado à variável `PLUGINS` com URL de versão fixa. A publicação oficial no Modrinth declara suporte a Paper 26.3 e não lista dependências obrigatórias. O arquivo é a edição Bukkit/Paper, não o mod Fabric/Forge. Os jogadores não precisam instalar nada.

Os operadores do servidor têm acesso ao WorldEdit por padrão. Não liberamos permissões de edição para jogadores comuns. Para conferir após aplicar e reiniciar, use `/worldedit version` no jogo. `//wand` fornece a ferramenta de seleção: clique esquerdo marca o primeiro canto, e direito marca o segundo. `//set stone` preenche a seleção com pedra; `//undo` desfaz sua última edição. Comece com seleções pequenas, pois edições grandes podem consumir muitos recursos, e mantenha backup das construções.

A configuração padrão do plugin é criada no volume em `/data/plugins/WorldEdit`; não adicionamos outro initContainer. Para atualizar, altere a URL na lista `PLUGINS` para outra versão compatível e aplique o Deployment.

Referências: [arquivo oficial 7.4.6](https://modrinth.com/plugin/worldedit/version/YFnqiUlL), [guia inicial](https://worldedit.enginehub.org/en/latest/quickstart/) e [permissões](https://worldedit.enginehub.org/en/latest/permissions/).

### Pedidos de teleporte (EssentialsX)

O servidor baixa a build oficial fixada `2.22.1-dev+28-f8724e2` (Jenkins 1833). O canal de desenvolvimento inclui suporte a Minecraft 26.3; a versão estável 2.22.0 declara suporte até 26.1.2. Não usamos um link móvel de última build. SHA-256 do JAR verificado: `5b8a1feb7c40a45d81e516bd077a7272d833c76cf829098743211999abd95929`.

Todos os jogadores recebem apenas estas permissões do EssentialsX pela lista `player-commands`; não precisam de OP, mod ou resource pack:

| Comando | Ação |
| --- | --- |
| `/tpa NomeDoJogador` | Pede para ir até o jogador |
| `/tpaccept` | Aceita o pedido recebido |
| `/tpdeny` | Recusa o pedido recebido |
| `/tpacancel` | Cancela seu pedido pendente |

Pedidos expiram em 60 segundos. O teleporte tem espera de 3 segundos (mover-se ou sofrer ataque pode cancelá-lo) e intervalo de 10 segundos entre teleportes. Não habilitamos aceite automático. Operadores continuam com as permissões administrativas do plugin.

`essentials.yaml` contém a configuração em um ConfigMap. Um initContainer copia esse arquivo para `/data/plugins/Essentials/config.yml` antes de cada inicialização. Esse arquivo é gerenciado pelo repositório: alterações manuais nele na VPS serão substituídas ao recriar o Pod. O initContainer não remove os outros arquivos de dados do plugin. Para alterar a configuração, edite o ConfigMap, aplique a pasta e reinicie o Deployment. Se futuramente instalar um gerenciador de permissões, como LuckPerms, migre as permissões para ele.

```bash
kubectl apply -f apps/minecraft/
kubectl -n laboratorio rollout status deployment/minecraft --timeout=900s
kubectl -n laboratorio logs -f deployment/minecraft
```

Após carregar, confira `/plugins` como administrador e teste `/tpa` com um jogador sem OP, incluindo aceitar e recusar. Se alterar apenas o ConfigMap depois da primeira aplicação, execute `kubectl -n laboratorio rollout restart deployment/minecraft` para recopiá-lo. A instalação foi preparada e validada localmente; o funcionamento no jogo deve ser confirmado na VPS.

Referências: [EssentialsX e versões suportadas](https://github.com/EssentialsX/Essentials), [build oficial 1833](https://ci.ender.zone/job/EssentialsX/1833/), [configuração oficial](https://github.com/EssentialsX/Essentials/blob/2.x/Essentials/src/main/resources/config.yml).

### Ícone na lista de servidores

A arte tem um creeper, uma espada de diamante e as iniciais OB. Foi gerada com a ferramenta de imagens integrada e exportada em 64x64 pixels. O prompt está em `apps/minecraft/assets/icon-prompt.txt`.

O arquivo `server-icon.yaml` contém os bytes do PNG e é aplicado junto dos outros YAMLs. O Kubernetes monta o arquivo em `/config/server-icon/server-icon.png`; a imagem o instala como `/data/server-icon.png`. A primeira aplicação da mudança no Deployment reinicia o servidor para mostrar o ícone.

Para trocar a arte, substitua `apps/minecraft/assets/server-icon.png` por outro PNG de 64x64 e execute no PowerShell do Windows, na raiz do repositório:

```powershell
./apps/minecraft/update-icon.ps1
```

Esse comando só atualiza o ConfigMap local. Envie o YAML atualizado à VPS, aplique a pasta e reinicie o servidor para copiar a nova imagem:

```bash
kubectl apply -f apps/minecraft/
kubectl -n laboratorio rollout restart deployment/minecraft
```

Não basta substituir o PNG no Git: regenere também `server-icon.yaml`. Depois, atualize a lista de servidores no jogo. Referência: [ícone do servidor na imagem Minecraft](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/server-properties/#server-icon).

### Melhorias instaladas só no servidor

A seleção em `apps/minecraft/datapacks.yaml` usa o catálogo oficial do Vanilla Tweaks para 26.3:

- **Timber:** corta a árvore com um machado no survival. `/trigger TimberToggle` alterna o recurso para o jogador; `/function timber:help` mostra ajuda.
- **Graves:** guarda os itens em uma sepultura ao morrer. Clique com o botão direito ou esquerdo na sepultura para recuperar. Administradores podem configurar com `/function graves:config`.
- **Fast Leaf Decay:** acelera a decomposição das folhas depois de cortar árvores no survival.

São datapacks, não plugins de Paper nem mods de cliente. Eles foram mantidos na configuração do Paper e os jogadores usam Minecraft Java normal. A imagem lê o JSON montado pelo ConfigMap via `VANILLATWEAKS_FILE`, baixa os pacotes do site oficial e instala em `/data/<mundo>/datapacks`. Também funciona em um mundo já existente, sem trocar a seed ou apagar o mapa. Confira o carregamento e o comportamento após a migração.

Na primeira aplicação, a alteração do Deployment já reinicia o servidor. Ao mudar somente o ConfigMap posteriormente, aplique e reinicie explicitamente:

```bash
kubectl apply -f apps/minecraft/
kubectl -n laboratorio rollout restart deployment/minecraft
kubectl -n laboratorio rollout status deployment/minecraft --timeout=900s
```

Depois da inicialização, um administrador pode conferir no chat com `/datapack list enabled`. A instalação usa a versão dos pacotes disponibilizada pelo Vanilla Tweaks para 26.3 e depende de acesso ao site na inicialização; os arquivos dos pacotes não estão fixados no Git. Não habilitamos remoção geral dos datapacks existentes. Remover um nome do JSON não garante sua desinstalação do mundo: use o procedimento do pacote, especialmente para Graves se ainda houver itens em sepulturas.

Referências: [catálogo 26.3](https://vanillatweaks.net/assets/resources/json/26.3/dpcategories.json) e [integração da imagem com Vanilla Tweaks](https://docker-minecraft-server.readthedocs.io/en/latest/misc/world-data/#vanillatweaks).

### Variáveis e recursos

Edite as variáveis em `apps/minecraft/deployment.yaml` e aplique a pasta novamente.

O bloco `env` contém comentários com opções comuns: tipo de servidor, modo de jogo, dificuldade, PvP, whitelist, administradores, mundo e plugins. As opções comentadas são exemplos, não configurações ativas nem uma lista completa. Para ativar uma delas, remova o `#` das linhas `- name` e `value`, ajuste o valor e aplique novamente. Confira a compatibilidade com sua versão na documentação da imagem. Comentar uma variável já aplicada não necessariamente desfaz seu efeito: algumas configurações ficam salvas em `/data`.

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

`SEED=8500081009970950196`: escolhida para um survival compacto com variedade de biomas e estruturas. A [fonte consultada para Java 26.3](https://mcseedmaps.com/seed/8500081009970950196-java-26-3) informa 45 biomas a até 1.000 blocos do spawn e estruturas como vila, mansão, cidade ancestral e stronghold nas proximidades. Não é garantia de todos os recursos ou estruturas das três dimensões; a seed foi pesquisada, não validada localmente no jogo.

A seed só é usada ao gerar um mundo novo. O Deployment agora usa `LEVEL=brian-limitado` para gerar outro mundo no mesmo volume, preservando `/data/world` e as dimensões antigas. Jogadores começam no novo mundo, com progresso e construções separados. Os dados globais dos plugins continuam no mesmo volume. Mantenha o nome `brian-limitado` nos próximos deploys; apenas a primeira inicialização gera o novo mundo. Se já houver um mundo com esse nome, ele será reutilizado, e a seed não será substituída.

### Borda do mundo

`RCON_CMDS_STARTUP` aplica automaticamente uma borda de 10.000 × 10.000 blocos no Overworld, centrada em X=0, Z=0, após iniciar. São 5.000 blocos para cada lado; essa configuração não limita separadamente Nether e End. Não há remoção de chunks nem pré-geração do mapa inteiro. A borda é reaplicada em cada reinício; para mudar o tamanho permanentemente, altere o YAML.

Antes da primeira aplicação, faça backup do volume com o servidor parado. Atualize o repositório na VPS e aplique:

```bash
kubectl apply -f apps/minecraft/
kubectl -n laboratorio rollout status deployment/minecraft --timeout=900s
kubectl -n laboratorio logs -f deployment/minecraft
```

Depois de aparecer `Done` e a execução dos comandos de inicialização, confirme no chat `/seed` e `/worldborder get`. O retorno esperado para a borda é 10000. Não é necessário executar outro `rollout restart` após a mudança no Deployment. No novo mundo, confira também `/datapack list enabled`.

Para voltar ao mundo anterior, restaure `LEVEL=world` e aplique novamente; não apague nenhum PVC ou diretório. O novo mundo permanece no volume. O mesmo conjunto de plugins é compartilhado, então referências salvas por plugins (como homes e warps) podem precisar de revisão ao trocar de mundo.

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
