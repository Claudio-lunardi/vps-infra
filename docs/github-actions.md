# Deploy pelo GitHub Actions via SSH

O Actions executa no GitHub, envia os arquivos do commit por SSH e roda `apps/minecraft/deploy.sh` na VPS. Não instala runner nem precisa clonar o repositório na VPS. A preparação abaixo é manual e feita uma vez. Não presuma que ela já foi executada após reinstalar a VPS.

O deploy atual atende Minecraft no namespace `laboratorio`. Outras aplicações podem ter seus próprios workflows, namespaces e credenciais. Não há aplicação recursiva de todos os serviços nem exclusão automática de recursos removidos do Git.

## 1. Conferir a VPS

Na VPS, como root:

```bash
kubectl get nodes
kubectl get storageclass
getent passwd github-deploy
```

O nó deve estar Ready e deve existir a StorageClass `local-path`. Se o último comando não mostrar nada, o usuário ainda não existe.

## 2. Criar o usuário de deploy

Como root, apenas se ainda não existir:

```bash
adduser github-deploy
install -d -m 700 -o github-deploy -g github-deploy /home/github-deploy/.ssh
install -d -m 700 -o github-deploy -g github-deploy /home/github-deploy/.kube
```

Não conceda sudo e não copie o kubeconfig de administrador do K3s para esse usuário. Ele usará uma credencial própria. O nome `github-deploy` não depende do antigo usuário `github-runner`.

## 3. Criar a chave SSH da pipeline

No PowerShell do seu computador, gere uma chave exclusiva fora do repositório. Se o arquivo já existir, não o sobrescreva; escolha outro nome e ajuste os comandos seguintes.

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.ssh" | Out-Null
ssh-keygen -t ed25519 -C "deploy-vps" -f "$env:USERPROFILE\.ssh\deploy-vps"
```

Deixe a passphrase vazia para a execução sem interação da pipeline. O arquivo sem extensão é a chave privada: não envie ao chat, não faça commit e não use a chave pessoal do seu SSH.

Leia apenas a chave pública:

```powershell
Get-Content "$env:USERPROFILE\.ssh\deploy-vps.pub"
```

Na VPS, como root, abra o arquivo:

```bash
nano /home/github-deploy/.ssh/authorized_keys
```

Adicione uma linha com `restrict ` seguido da chave pública completa, por exemplo `restrict ssh-ed25519 AAAA... deploy-vps`. Preserve outras chaves existentes. `restrict` impede encaminhamento de portas/agente e terminal interativo; permite os comandos de deploy. Depois:

```bash
chown github-deploy:github-deploy /home/github-deploy/.ssh/authorized_keys
chmod 600 /home/github-deploy/.ssh/authorized_keys
```

O SSH da VPS precisa aceitar autenticação por chave. A pipeline precisa alcançar a porta SSH pelo firewall; não é necessário publicar a API Kubernetes (6443).

## 4. Dar acesso ao Kubernetes

O arquivo `cluster/access/minecraft.yaml` cria namespace, ServiceAccount, Role, RoleBinding e Secret do token, sem conceder acesso a outros namespaces. A Role permite aplicar manifests e consultar o rollout, mas não ler Secrets nem excluir PVCs. Permissão de criar Deployments ainda permite executar containers no namespace; mantenha escrita no repositório e os Secrets restritos a pessoas confiáveis.

No PowerShell, dentro do repositório, substitua `IP_OU_DOMINIO` pelo endereço da VPS (use `-p PORTA` no SSH se necessário):

```powershell
Get-Content -Raw cluster/access/minecraft.yaml | ssh root@IP_OU_DOMINIO 'kubectl apply -f -'
```

Esse comando transmite somente o YAML de permissões ao `kubectl` remoto. É uma preparação administrativa, não o deploy da aplicação. O namespace `laboratorio` deve ser o mesmo do servidor existente; não migre nem apague seu PVC.

Na VPS, como root, espere o preenchimento do token:

```bash
kubectl -n laboratorio wait --for=jsonpath='{.data.token}' secret/github-deployer-token --timeout=60s
```

Monte o kubeconfig do usuário. Não execute com `set -x` e não envie esse arquivo ao Git ou ao chat:

```bash
umask 077
kubectl --kubeconfig=/home/github-deploy/.kube/config config set-cluster local --server=https://127.0.0.1:6443 --certificate-authority=/var/lib/rancher/k3s/server/tls/server-ca.crt --embed-certs=true
kubectl --kubeconfig=/home/github-deploy/.kube/config config set-credentials github-deployer --token="$(kubectl -n laboratorio get secret github-deployer-token -o jsonpath='{.data.token}' | base64 -d)"
kubectl --kubeconfig=/home/github-deploy/.kube/config config set-context laboratorio --cluster=local --user=github-deployer --namespace=laboratorio
kubectl --kubeconfig=/home/github-deploy/.kube/config config use-context laboratorio
chown github-deploy:github-deploy /home/github-deploy/.kube/config
chmod 600 /home/github-deploy/.kube/config
```

Confira, como root:

```bash
sudo -u github-deploy env KUBECONFIG=/home/github-deploy/.kube/config kubectl auth can-i patch deployments -n laboratorio
sudo -u github-deploy env KUBECONFIG=/home/github-deploy/.kube/config kubectl auth can-i get secrets -n laboratorio
sudo -u github-deploy env KUBECONFIG=/home/github-deploy/.kube/config kubectl auth can-i patch deployments -n default
```

O esperado é `yes`, `no`, `no`. O token é persistente e fica na VPS. Para revogá-lo, exclua o Secret como administrador e monte novamente a credencial antes de retomar os deploys. Para revogar o acesso SSH, remova a chave pública de `authorized_keys`.

## 5. Cadastrar a conexão no GitHub

Em Settings > Secrets and variables > Actions, cadastre nas **Variables**:

| Nome | Valor |
| --- | --- |
| `VPS_HOST` | IPv4 ou domínio da VPS, sem `ssh://` e sem usuário |
| `VPS_PORT` | Porta SSH; opcional, padrão `22` |
| `VPS_USER` | Opcional, padrão `github-deploy` |
| `ENABLE_DEPLOY` | Comece com `false`; altere para `true` após conferir a preparação |

Nas **Secrets**, cadastre:

| Nome | Conteúdo |
| --- | --- |
| `VPS_SSH_PRIVATE_KEY` | Todo o conteúdo de `deploy-vps`, incluindo BEGIN/END |
| `VPS_SSH_KNOWN_HOSTS` | Chave pública do servidor SSH associada ao endereço da VPS |

Para copiar a chave privada diretamente para a área de transferência, sem imprimi-la no terminal, use no PowerShell e cole no Secret:

```powershell
Get-Content -Raw "$env:USERPROFILE\.ssh\deploy-vps" | Set-Clipboard
```

Para obter a identidade do servidor, na sessão SSH confiável da VPS como root:

```bash
cat /etc/ssh/ssh_host_ed25519_key.pub
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

O conteúdo de `VPS_SSH_KNOWN_HOSTS` deve ser uma linha no formato abaixo, usando o mesmo endereço de `VPS_HOST` e os dois primeiros campos da chave pública acima (sem o comentário):

```text
IP_OU_DOMINIO ssh-ed25519 AAAA_CHAVE_PUBLICA_DO_SERVIDOR
```

Se a porta SSH for diferente de 22, o primeiro campo deve ser `[IP_OU_DOMINIO]:PORTA`. A pipeline exige essa identidade; ela não aceita automaticamente chaves obtidas da rede. Após reinstalar a VPS, confira a nova identidade por um acesso confiável antes de atualizar o Secret.

## 6. Testar e ativar

Do computador, teste a chave (ajuste endereço e porta):

```powershell
ssh -i "$env:USERPROFILE\.ssh\deploy-vps" -o IdentitiesOnly=yes github-deploy@IP_OU_DOMINIO 'KUBECONFIG=$HOME/.kube/config kubectl -n laboratorio get deployments'
```

Na primeira conexão, confira a impressão digital com a obtida na VPS antes de aceitar. O teste não deve solicitar a senha do usuário.

Envie os arquivos do workflow, script e documentação ao GitHub. Só então altere `ENABLE_DEPLOY` para `true`. Em Actions > Deploy Minecraft > Run workflow, selecione `main` e execute o primeiro deploy. A execução pode reiniciar o jogo; escolha um momento adequado e tenha uma cópia consistente do mundo fora da VPS antes de mudanças relevantes.

Após validar, pushes na `main` que alterem `apps/minecraft/` ou o workflow disparam o deploy. A pipeline envia os arquivos do próprio commit; a VPS não precisa de credencial para clonar o GitHub. Alterações só em README ou permissões não disparam deploy da aplicação.

O script inclui um hash dos YAMLs na configuração do Pod. Alterações nos ConfigMaps também recriam o Pod para recarregar plugins, datapacks e ícone. Reaplicar os mesmos YAMLs não força novo reinício. O volume continua sendo o mesmo; não há comando de exclusão ou backup automático.

Se falhar, confira os logs da execução no Actions. Erro de chave do host exige conferir `VPS_SSH_KNOWN_HOSTS`; `Permission denied (publickey)` exige conferir usuário e chave; `Forbidden` exige conferir Role/RoleBinding. Timeout de conexão exige conferir endereço, porta e firewall. `ENABLE_DEPLOY=false` bloqueia novos jobs, mas não cancela um em andamento.

Se ainda houver um runner antigo instalado, ele não é usado por este workflow. Pare/remova o serviço antigo apenas depois de confirmar que não atende outros projetos.

Referências: [Secrets do Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets) e [credenciais de ServiceAccounts](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/).
