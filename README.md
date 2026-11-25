# vps-infra

Servidor Minecraft Java com Paper no K3s, fixado na versão `26.3` e build Paper `262`, no namespace `laboratorio`.

## Organização

```text
namespaces/laboratorio.yaml
apps/minecraft/deployment.yaml
apps/minecraft/service.yaml
apps/minecraft/storage.yaml
apps/minecraft/datapacks.yaml
apps/minecraft/server-icon.yaml
apps/minecraft/assets/server-icon.png
```

- Deployment: executa um servidor, com heap Java inicial de 512 MB e máximo de 75% da memória disponível detectada pela JVM. Não há teto de CPU nem limite Kubernetes de memória para o container.
- Service: publica TCP 25565 pelo ServiceLB incluído na instalação padrão do K3s.
- Storage: solicita 10 GiB para o mundo e configurações em `/data`, usando a StorageClass `local-path` do K3s.
- Datapacks: ConfigMap com a seleção do Vanilla Tweaks para Minecraft 26.3. A imagem instala Timber, Graves e Fast Leaf Decay no mundo ao iniciar, sem exigir instalação dos jogadores.
- Ícone: PNG de 64x64 do Os Brian incluído no ConfigMap `minecraft-server-icon`. A imagem copia o arquivo para o servidor usando `ICON` e `OVERRIDE_ICON=TRUE`, sem baixar arte de sites externos.

Cada pasta em `apps/` representa uma aplicação. O Kubernetes não acompanha a pasta ou o Git: `kubectl apply` lê os YAMLs e envia os recursos ao cluster. Depois de editar, aplique novamente. Remover um YAML do Git não exclui seu recurso do cluster.

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

Não é necessário habilitar o UFW para o exemplo. O ServiceLB do K3s precisa estar habilitado e a porta 25565 livre. RCON está desabilitado.

## Configuração e atualizações

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

`SEED=2048005618087379093`: ilha cercada por montanhas de cerejeiras, com uma vila próxima. A [lista consultada para Java 26.3](https://gamingroute.com/best-minecraft-seeds/) informa uma vila aproximadamente em X=-272, Z=112. A paisagem foi escolhida pela pesquisa; não foi testada localmente no jogo.

A seed só é usada ao gerar um mundo novo. Se `/data/world` já existe, aplicar o YAML não muda esse mundo. Para testar sem apagar o anterior, escolha um nome novo em `LEVEL` e aplique novamente; o mundo antigo permanece no volume. Isso inicia outro mundo e exige espaço adicional em disco.

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

## Referências

- [Paper na imagem de Minecraft](https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/server-types/paper/)
- [Migração do mundo para Paper](https://docs.papermc.io/paper/migration/)

- [Imagem Minecraft Java e armazenamento](https://docker-minecraft-server.readthedocs.io/en/latest/)
- [Versões do Minecraft](https://docker-minecraft-server.readthedocs.io/en/latest/versions/minecraft/)
- [Memória inicial, máxima e percentuais](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/jvm-options/)
- [ServiceLB do K3s](https://docs.k3s.io/networking/networking-services)
- [Aplicar YAMLs e diretórios](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
