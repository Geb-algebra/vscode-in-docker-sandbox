# VS Code in a Codex Docker Sandbox

Docker Sandboxes標準のCodex templateを土台に、公式SSH accessを使うVS Code Remote - SSHと共通開発環境を組み込むmixin Kitです。

このディレクトリは対象プロジェクトの中に置く必要はありません。`vscode-in-sandbox` と開発対象のworkspaceを別ディレクトリとして管理し、起動時にworkspaceのpathを指定します。

```text
任意の配置場所/
├── vscode-in-sandbox/       # このKit
├── project-a/               # 開発対象
└── project-b/               # 開発対象
```

CodexのOAuth認証はhostのOS Keychainに保存され、Docker Sandboxesのcredential proxyを通して利用されます。OpenAIのtokenやAPI keyをKit、workspace、sandbox内へ意図的に保存しません。

## Network egress

このKitは、hostのglobal network policyが `balanced` で初期化されていることを前提とします。

```bash
sbx policy init balanced
```

`balanced` は一度だけ初期化できます。すでに初期化済みの場合、このコマンドを再実行する必要はありません。現在のpolicyは次のコマンドで確認できます。

```bash
sbx policy ls --type network
```

balanced設定には次のカテゴリが含まれます。

- AI services
- package managers
- source code / container registries
- cloud infrastructure
- OS package repositories
- certificate validation

`spec.yaml` の `caps.network.allow` には、balancedでカバーされないVS Codeとツール導入用domainだけを追加しています。Kitにはdeny ruleはありませんが、組織のgovernance policyやsandbox profileで設定されたdeny ruleがある場合は、そちらが優先されます。

`--no-firewall` を指定したsandboxには、専用mixin Kitから `**` のallow ruleを追加し、すべてのoutbound network trafficを許可します。この指定はsandbox固有であり、hostのglobal `balanced` policyや通常版sandboxのpolicyは変更しません。Docker Sandboxesの通信経路自体を迂回するものではなく、組織のgovernance policyやsandbox profileのdeny ruleは引き続き優先されます。

## 導入されるツール

```text
mise 2026.7.11
Node.js 24.18.0（mise）
Bun 1.3.14（mise）
Python 3.14.6（mise binary）
uv 0.11.28（mise）
Terraform 1.15.8（mise）
Codex CLI 0.144.6（mise/npm）
Playwright CLI 0.1.17（mise/npm）
pre-commit（Ubuntu package）
OpenSSH client
zsh / oh-my-zsh（theme: pmcgee）
```

共通のVS Code拡張:

```text
eamodio.gitlens
openai.chatgpt
```

Nord theme拡張はRemote側へinstallしません。`workbench.colorTheme: "Nord"` を使う場合はローカルVS Code側へinstallします。

人間がVS Codeで開くintegrated terminalはlogin zshとoh-my-zshを使用します。VS Code taskや拡張などのautomation terminalは `/bin/bash` のままです。Codex agentのshellも変更しません。

プロジェクト固有の推奨拡張は、各workspaceの `.vscode/extensions.json` で管理します。

## 前提条件

- Docker Desktop
- Docker Sandboxes / `sbx` CLI 0.43.0以降
- ローカルのVS Code
- VS CodeのRemote - SSH拡張（`ms-vscode-remote.remote-ssh`）
- hostのOpenSSH client
- Docker account
- Codexを利用できるOpenAI account

初回利用時とtool version変更時には、Dockerでnative architecture用のtoolchain artifactを生成します。

```bash
cd /path/to/vscode-in-sandbox
./build-toolchain-artifact.sh
```

生成物はKit直下の `artifacts/` に保存されます。数百MB規模になるためGit管理外です。sbx 0.37ではKit static fileへ大容量binaryを投入できないため、launcherがartifact directoryを追加direct mountします。このmountはsbxのworkspace mount仕様上read-writeですが、startup hookはSHA-256検証後の読み取りにだけ使用します。artifact directoryにはcredentialsやprivate filesを置かないでください。

## Host側の初期設定

Docker Sandboxesへloginし、global network policyをbalancedで初期化してから、公式SSH accessとCodex OAuth認証をhostへ設定します。

```bash
sbx login
sbx policy init balanced
sbx setup ssh
sbx secret set -g openai --oauth
```

OAuth flowはhost上で実行されます。認証結果はOS Keychainに保存され、実tokenはsandboxへ渡されません。

`sbx setup ssh` はDocker Sandboxesが管理する `Host *.sbx` blockをhostのSSH client設定へ追加します。接続は `ProxyCommand` でlocalのDocker Sandboxes daemonへ中継され、network port、専用SSH key、sandbox内のSSH serverは使用しません。

公式設定の `SendEnv *` がhost環境変数を提示しても、daemonは `ssh.acceptEnv` allowlistに含まれる変数だけを受け入れます。Kitからallowlistを追加することはありません。

global secretは新しく作成するsandboxにだけ適用されます。認証設定より前に作成したsandboxがある場合は、そのsandboxを削除して作り直してください。

次の情報をKitやworkspaceへ置かないでください。

- `OPENAI_API_KEY`
- OAuth token
- hostの `~/.codex/auth.json`

Codex拡張内でも追加のChatGPT loginは行わないでください。拡張独自の認証情報がsandbox内へ保存される可能性があります。

## Toolchainのinstallと一時workaround

通常はcustom templateへtoolchainを焼き込みますが、sbx 0.37.xのrootfs regression [docker/sbx-releases#366](https://github.com/docker/sbx-releases/issues/366) を避けるため、現在のlauncherはsbx組み込みの `codex-docker` templateを使用します。`build-template.sh` は当面の起動手順では使用しません。

ローカルDockerで、mise toolchain、Playwright Chromium、oh-my-zshを完成済みartifactとして生成します。Playwright CLI skillはhostで `sbx skills add microsoft/playwright-cli --skill playwright-cli` を実行して共有skillsストアに登録します。sbx 0.43.0以降では、このストアがsandbox内の `/home/agent/.agents/skills` に読み取り専用でマウントされます。Kitのmarker付きstartup hookは、sandbox新規作成時にartifactを検証・展開し、Ubuntu runtime packageとPlaywrightのsystem dependencyだけをaptで導入します。sandbox内ではmise install、browser download、oh-my-zsh cloneを行いません。startup hook自体は起動ごとに呼ばれますが、同じsandboxでは永続markerを確認して即終了します。

sbx 0.37.0では `commands.install` がKitの静的ファイル配置より先に実行され、同梱したlocal install scriptを参照できません。このため、静的ファイル配置後に呼ばれるstartup hookを使用し、launcherが完了markerを待ってからVS Codeを開きます。

install logはsandbox内の `/home/agent/.local/state/vscode-in-sandbox/toolchain-install.log` に保存されます。起動時のnetwork installは、標準templateの公式sourceから取得するapt packageだけです。artifactのchecksum不一致、architecture不一致、想定外pathは展開前にエラーになります。

`mise-config.toml`、mise自体のversion、またはartifactに含めるツールを変更した場合は、artifactを再生成して既存sandboxを削除してください。

```bash
./build-toolchain-artifact.sh
sbx rm <sandbox-name>
sbx-vscode /path/to/workspace
```

背景と、#366修正後にcustom templateへ戻す範囲は [`docs/temporary-sbx-0.37-template-layer-workaround.md`](docs/temporary-sbx-0.37-template-layer-workaround.md) に記録しています。

## 起動方法

### Workspaceを引数で指定する

```bash
/path/to/vscode-in-sandbox/sbx-vscode /path/to/project
```

### 開発対象ディレクトリから起動する

引数を省略した場合は、コマンド実行時のカレントディレクトリをworkspaceとして使用します。

```bash
cd /path/to/project
/path/to/vscode-in-sandbox/sbx-vscode
```

### Firewallなしで起動する

任意のhostへのoutbound network trafficを許可する場合は、`--no-firewall` を指定します。通常版とは別のsandboxが作成されます。

```bash
sbx-vscode --no-firewall /path/to/project
```

firewallなし版の自動生成名は `nf-<dirname>-<hash>` 形式です。directory名は先頭7文字、絶対pathのSHA-256 hashは先頭8文字を使うため、最大19文字に収まります。たとえば通常版が `my-project-a1b2c3d4` の場合、firewallなし版は `nf-my-proj-a1b2c3d4` となり、両方を共存させられます。

`SBX_NAME` を指定した場合は、その値を切り詰めたりprefixを付けたりせず、最終的なsandbox名として使用します。通常版と共存させる場合は、異なる名前を明示してください。

```bash
SBX_NAME=project-nf sbx-vscode --no-firewall /path/to/project
```

起動時には、全outboundを許可していることを警告としてログへ表示します。

頻繁に利用する場合は、起動スクリプトをPATH上へsymlinkできます。

```bash
mkdir -p "$HOME/.local/bin"
ln -s /path/to/vscode-in-sandbox/sbx-vscode "$HOME/.local/bin/sbx-vscode"
```

以降は各プロジェクトから次のように起動できます。

```bash
cd /path/to/project
sbx-vscode
```

起動スクリプトは次の処理を行います。

1. `sbx` 0.37.0以降と、`sbx setup ssh` による公式SSH設定を確認する。
2. 通常版ではworkspaceのディレクトリ名（先頭10文字）と絶対pathのSHA-256 hash（先頭8文字）から `<dirname>-<hash>` 形式のsandbox名を生成する。firewallなし版では `nf-<dirname先頭7文字>-<hash先頭8文字>` 形式にする。同名ディレクトリでも絶対pathが異なれば別sandboxになる。sandbox名に使用できない文字がある場合は `-` に置き換える。
3. workspaceがGit linked worktreeの場合、Gitの共通ディレクトリ（元リポジトリの `.git`）を自動検出する。
4. 未作成の場合、native architecture用artifactとchecksumを検証し、artifact directoryを追加mountして、sbx組み込みの `codex-docker` templateとこのKitを使ってCodex sandboxを作成する。firewallなし版では全outboundを許可する専用Kitも追加する。Kitのmarker付きstartup hookがartifactを展開し、runtime packageを一度だけ導入する。linked worktreeでは共通 `.git` もhostと同じ絶対pathへread-writeで追加mountする。
5. 既存の場合は同名sandboxを再利用する。
6. Docker Sandboxes公式の `<sandbox-name>.sbx` targetへ接続できることを確認する。
7. toolchain installの完了markerを確認する。
8. mount済みworkspaceをVS Code Remote - SSHで開き、共通拡張をinstallしてlauncherを終了する。

Docker Sandboxesのdirect mountはhost workspaceをsandbox内でも同じ絶対pathへmountします。Codex agentとVS Codeは、どちらもこのmount先を使用します。`~/workspace` は使用しません。

linked worktreeの判定には `git rev-parse --git-dir --git-common-dir` を使用します。worktree固有のGit directoryと共通Git directoryが異なる場合にだけ、共通 `.git` を追加mountします。commit、index、branchなどのGit管理情報を更新できるよう、この追加mountはread-writeです。元リポジトリの作業ツリー自体はmountしません。通常のGitリポジトリやGit管理外のworkspaceでは追加mountされません。

既存sandboxのtemplate、Kit、mount構成は変更されません。自前OpenSSH版やcustom templateから作成したsandbox、またはlinked worktree mount追加前に作成したsandboxでは、ログに表示されるsandbox名を確認してから削除し、再作成してください。

```bash
sbx rm <sandbox-name>
sbx-vscode /path/to/linked-worktree
```

起動ログには、hostから直接接続できる `ssh` コマンドと、mount済みworkspaceを開く `code` コマンドが表示されます。

```bash
ssh <sandbox-name>.sbx
code --new-window --remote ssh-remote+<sandbox-name>.sbx /absolute/path/to/workspace
```

GUIを自動起動せずコマンド表示だけにする場合は、`SBX_AUTO_OPEN=0` を指定します。どちらの場合も接続準備ができた時点で `sbx-vscode` は終了し、sandboxは明示的に停止するまで利用可能なままです。

```bash
SBX_AUTO_OPEN=0 sbx-vscode /path/to/workspace
```

作業後はsandboxを停止します。stop/startではinstall済みtoolchainとVS Code Server stateが保持されます。

```bash
sbx stop <sandbox-name>
```

## 起動設定の上書き

環境変数でworkspace、sandbox名、governance profileを上書きできます。

```bash
SBX_NAME=vsc-project \
SBX_PROFILE=profile-name \
SBX_AUTO_OPEN=0 \
/path/to/vscode-in-sandbox/sbx-vscode /path/to/project
```

```text
SBX_NAME       sandbox名
SBX_WORKSPACE  workspaceの絶対path。第1引数より優先される
SBX_PROFILE    Docker Sandboxesのgovernance profile
SBX_TEMPLATE_NAME  任意のtemplate override。未指定時はsbx組み込みのCodex template
SBX_AUTO_OPEN  `0` の場合はローカルVS Code自動起動だけを無効化する
```

`--no-firewall` と `SBX_NAME` を併用した場合、`SBX_NAME` はそのまま最終名になります。通常版のsandbox名を指定すると既存の通常版sandboxが再利用されるため、firewallなし版には専用の名前を指定してください。

`SBX_TEMPLATE_NAME` は検証用途に残しています。#366の影響下ではcustom templateを指定しないでください。

### macOSでVS Codeが再接続を繰り返す場合

local VS Codeのuser settingsへ次を追加します。

```json
{
  "remote.SSH.useLocalServer": false
}
```

## Codex拡張の認証制約

SSH接続後のCodex拡張とRemote VS Codeのterminalで実行するCodex CLIは、どちらもDocker Sandboxesのhost-managed認証を使用します。拡張内で追加のChatGPT loginは行わないでください。

認証に失敗する場合もsandbox内へtokenを保存せず、host側のOAuth設定とsandboxのnetwork policyを確認します。

```bash
sbx secret ls
sbx policy ls --type network
```

自前OpenSSH版またはcustom templateで作成した既存sandboxには不要なsshd、22番port mapping、または不完全なcustom layerが残る可能性があります。既存sandboxを削除し、現在のlauncherで作り直してください。

```bash
sbx rm <sandbox-name>
sbx-vscode /path/to/workspace
```

## 自前SSH版からの移行

新しいsandboxで公式targetへ接続できることを確認します。

```bash
sbx setup ssh
sbx rm <sandbox-name>
sbx-vscode /path/to/workspace
ssh <sandbox-name>.sbx
```

確認後、旧launcherがhostへ作成した次の専用ファイルとdirectoryを手動で削除できます。

```text
~/.ssh/docker-sandbox-vscode_ed25519
~/.ssh/docker-sandbox-vscode_ed25519.pub
~/.ssh/docker-sandbox-vscode_known_hosts
~/.ssh/config.d/docker-sandbox-vscode/
```

さらに `~/.ssh/config` から次の1行だけを削除します。

```sshconfig
Include ~/.ssh/config.d/docker-sandbox-vscode/*.conf
```

## 永続化範囲

- Codex OAuth: hostのOS Keychainに保存され、sandboxを削除しても残る
- Docker Sandboxes公式SSH設定: hostの `~/.ssh/config` とDocker Sandboxes管理領域に保存される
- Kit artifactから展開したツール、Playwright browser、oh-my-zsh: sandbox内に保存され、stop/startをまたいで残る
- Kitの静的ファイルと共通設定: sandbox作成時に配置される
- VS Code Serverの実行時state: sandboxが存在する間はstop/startをまたいで残る

認証とsandbox stateを削除するコマンド:

```bash
sbx rm <sandbox-name>
sbx secret rm -g openai
```

`sbx reset` はsandbox stateと保存済みsecretを削除するため、実行後はOAuth設定が再度必要です。公式SSH設定は必要に応じて `sbx setup ssh` で再設定できます。

## 共通設定の変更

共通設定と拡張一覧は次のファイルで管理します。

```text
files/home/.vscode-server/data/Machine/settings.json
files/home/.config/vscode-in-sandbox/extensions.txt
files/home/.local/share/vscode-in-sandbox/mise-config.toml
```

toolchain設定の変更後は `./build-toolchain-artifact.sh` を実行し、既存sandboxを削除してから`sbx-vscode`で新規作成してください。Kitの静的ファイルとartifactはsandbox作成時に適用されます。workspace自体はhost側にあるため削除されませんが、sandbox内のtoolchainとVS Code Server実行時stateは失われます。

## 検証

Kitディレクトリで静的検証を実行します。

```bash
cd /path/to/vscode-in-sandbox

sbx kit validate .
bash -n ./build-toolchain-artifact.sh
bash -n ./build-template.sh
bash -n ./sbx-vscode
bash -n ./scripts/build-toolchain-root.sh
bash -n ./files/home/.local/share/vscode-in-sandbox/install-tools.sh
```

artifactを含む完全な検証では、生成後にarchiveの必須pathとchecksumも確認します。

```bash
./build-toolchain-artifact.sh
cd artifacts
shasum -a 256 -c toolchain-linux-arm64.tar.zst.sha256
```

sandbox作成後は、実際に導入されたversionと拡張を確認します。

```bash
sbx exec <sandbox-name> node --version
sbx exec <sandbox-name> bun --version
sbx exec <sandbox-name> python3 --version
sbx exec <sandbox-name> uv --version
sbx exec <sandbox-name> terraform version
sbx exec <sandbox-name> pre-commit --version
sbx exec <sandbox-name> ssh -V
ssh <sandbox-name>.sbx id -un
sbx exec <sandbox-name> sh -c '! command -v sshd'
sbx ports <sandbox-name>
```

`sbx ports`に22番のmappingがないことも確認します。

期待値:

```text
node:   v24.18.0
bun:    1.3.14
python: Python 3.14.6
uv:     uv 0.11.28
terraform: 1.15.8
```
