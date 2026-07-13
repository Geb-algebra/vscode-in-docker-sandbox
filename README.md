# VS Code in a Codex Docker Sandbox

Docker Sandboxes標準のCodex templateを土台に、VS Code Tunnelと共通開発環境を焼き込んだローカルtemplateです。network egressだけは小さなmixin Kitで追加します。

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

`spec.yaml` の `caps.network.allow` には、balancedでカバーされないVS Code Tunnelとツール導入用domainだけを追加しています。Kitにはdeny ruleはありませんが、組織のgovernance policyやsandbox profileで設定されたdeny ruleがある場合は、そちらが優先されます。

## 導入されるツール

```text
Node.js 24.18.0
pnpm 11.11.0
Python 3.14.6
uv 0.11.28
VS Code stable（CLI / Tunnelを含む）
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
- Docker Sandboxes / `sbx` CLI
- ローカルのVS Code
- VS CodeのRemote - Tunnels拡張
- Docker account
- Codexを利用できるOpenAI account
- Tunnel認証に使用するGitHub account

## Host側の初期設定

Docker Sandboxesへloginし、global network policyをbalancedで初期化してから、Codex OAuth認証をhostへ保存します。

```bash
sbx login
sbx policy init balanced
sbx secret set -g openai --oauth
```

OAuth flowはhost上で実行されます。認証結果はOS Keychainに保存され、実tokenはsandboxへ渡されません。

global secretは新しく作成するsandboxにだけ適用されます。認証設定より前に作成したsandboxがある場合は、そのsandboxを削除して作り直してください。

次の情報をKitやworkspaceへ置かないでください。

- `OPENAI_API_KEY`
- OAuth token
- hostの `~/.codex/auth.json`

Codex拡張内でも追加のChatGPT loginは行わないでください。拡張独自の認証情報がsandbox内へ保存される可能性があります。

## ローカルtemplateのbuild

最初に一度、またはDockerfile・ツール・設定・拡張を変更したときに実行します。

```bash
cd /path/to/vscode-in-sandbox
./build-template.sh
```

このスクリプトは次の処理を行います。

1. `local/vscode-codex:1` をDockerでbuildする。
2. `vscode-in-sandbox/.vscode-codex-template.tmp.tar` へ一時的に `docker image save` する。
3. `sbx template load` でDocker Sandboxes側のローカルimage storeへ取り込む。
4. load完了後に一時tarを削除する。

remote registryへのpushは行いません。Node.js、pnpm、Python、uv、VS Code、共通拡張はimageに入るため、sandbox起動のたびにinstallされません。buildしたhostのCPU architectureに対応するimageが作られます。

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

1. workspaceのディレクトリ名（先頭10文字）と絶対pathのSHA-256 hash（先頭8文字）から `<dirname>-<hash>` 形式のsandbox名を生成する。最大19文字に収まり、VS Code Tunnelの20文字制限を超えない。同名ディレクトリでも絶対pathが異なれば別sandboxになる。ディレクトリ名にTunnel名で使用できない文字がある場合は `-` に置き換える。
2. workspaceがGit linked worktreeの場合、Gitの共通ディレクトリ（元リポジトリの `.git`）を自動検出する。
3. 未作成の場合、ローカルtemplateとnetwork mixin Kitを使ってCodex sandboxを作成する。linked worktreeでは共通 `.git` もhostと同じ絶対pathへread-writeで追加mountする。
4. 既存の場合は同名sandboxを再利用する。
5. hostと同じ絶対pathへmountされたworkspaceを作業ディレクトリとして、`sbx exec` でsandbox内の `code tunnel` を対話的に起動する。

Docker Sandboxesのdirect mountはhost workspaceをsandbox内でも同じ絶対pathへmountします。Codex agentとVS Code Tunnelは、どちらもこのmount先を作業ディレクトリとして起動します。`~/workspace` は使用しません。

linked worktreeの判定には `git rev-parse --git-dir --git-common-dir` を使用します。worktree固有のGit directoryと共通Git directoryが異なる場合にだけ、共通 `.git` を追加mountします。commit、index、branchなどのGit管理情報を更新できるよう、この追加mountはread-writeです。元リポジトリの作業ツリー自体はmountしません。通常のGitリポジトリやGit管理外のworkspaceでは追加mountされません。

既存sandboxのmount構成は変更できません。この機能を追加する前に作成したlinked worktree用sandboxでは、ログに表示されるsandbox名を確認してから削除し、再作成してください。

```bash
sbx rm <sandbox-name>
sbx-vscode /path/to/linked-worktree
```

表示されたGitHub device-login URLを開き、codeを入力します。その後、ローカルVS CodeのRemote Explorerから同じGitHub accountでsign inし、表示されたTunnelへ接続してください。接続後に空の `~/workspace` が表示された場合は、そのwindowを閉じ、`File: Open Folder...` から起動ログに表示された絶対pathのworkspaceを開きます。

起動ログには、Tunnelの準備完了後にhost側で実行できる `code` コマンドも表示されます。hostで `code` コマンドが利用可能な場合はTunnelの準備完了を自動検出し、このコマンドを実行します。Tunnelへ接続した新しいVS Code windowでmount済みworkspaceが直接開きます。ローカルVS CodeにRemote - Tunnels拡張がinstallされ、Tunnelと同じGitHub accountで認証されている必要があります。

```bash
code --new-window --remote tunnel+<sandbox-name> /absolute/path/to/workspace
```

GUIを自動起動せずコマンド表示だけにする場合は、`SBX_AUTO_OPEN=0` を指定します。

```bash
SBX_AUTO_OPEN=0 sbx-vscode /path/to/workspace
```

## 起動設定の上書き

環境変数でworkspace、sandbox名、governance profileを上書きできます。

```bash
SBX_NAME=vsc-project \
SBX_PROFILE=profile-name \
SBX_TEMPLATE_NAME=local/vscode-codex:1 \
SBX_AUTO_OPEN=0 \
/path/to/vscode-in-sandbox/sbx-vscode /path/to/project
```

```text
SBX_NAME       sandbox名
SBX_WORKSPACE  workspaceの絶対path。第1引数より優先される
SBX_PROFILE    Docker Sandboxesのgovernance profile
SBX_TEMPLATE_NAME  sbxへload済みのtemplate名
SBX_AUTO_OPEN  `0` の場合はTunnel準備完了後のローカルVS Code自動起動を無効化
```

## Codex拡張の認証制約

Tunnel接続後、Codex拡張が追加loginなしで動作するか確認します。

拡張がDocker Sandboxesのhost-managed認証を認識しない場合は、拡張からloginしないでください。Remote VS Codeのterminalを開き、Docker標準imageに含まれるCodex CLIを使用します。

```bash
codex
```

安全性を優先し、この場合はCodex CLIだけを利用できるという制約を受け入れます。

## 永続化範囲

- Codex OAuth: hostのOS Keychainに保存され、sandboxを削除しても残る
- VS Code TunnelのGitHub認証: sandbox内に保存され、sandbox削除時に消える
- imageへ焼き込んだツール・拡張・共通設定: sandboxを作り直してもtemplateから復元される
- VS Code Serverの実行時state: sandboxが存在する間はstop/startをまたいで残る

認証とsandbox stateを削除するコマンド:

```bash
sbx rm <sandbox-name>
sbx secret rm -g openai
```

`sbx reset` はsandbox stateに加えて保存済みsecretも削除するため、実行後はOAuth設定が再度必要です。

## 共通設定の変更

共通設定と拡張一覧は次のファイルで管理します。

```text
files/home/.vscode-server/data/Machine/settings.json
files/home/.config/vscode-in-sandbox/extensions.txt
```

変更後はtemplateをbuild/loadし直します。

```bash
cd /path/to/vscode-in-sandbox
./build-template.sh
```

既存sandboxは古いimage layerを使い続けるため、自動更新されません。反映するには既存sandboxを削除し、`sbx-vscode` で新規作成してください。workspace自体はhost側にあるため削除されませんが、sandbox内だけにあるVS Code TunnelのGitHub認証や実行時stateは失われます。

## 検証

Kitディレクトリで静的検証を実行します。

```bash
cd /path/to/vscode-in-sandbox

sbx kit validate .
bash -n ./build-template.sh
bash -n ./sbx-vscode
bash -n ./files/home/.local/share/vscode-in-sandbox/install-tools.sh
bash -n ./files/home/.local/share/vscode-in-sandbox/install-extensions.sh
```

sandbox作成後は、実際に導入されたversionと拡張を確認します。

```bash
sbx exec <sandbox-name> node --version
sbx exec <sandbox-name> pnpm --version
sbx exec <sandbox-name> python3 --version
sbx exec <sandbox-name> uv --version
sbx exec -u agent <sandbox-name> code --extensions-dir /home/agent/.vscode-server/extensions --list-extensions
```

期待値:

```text
node:   v24.18.0
pnpm:   11.11.0
python: Python 3.14.6
uv:     uv 0.11.28
```
