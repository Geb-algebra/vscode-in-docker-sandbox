# VS Code in Docker Sandbox

隔離環境内でVSCodeを起動するためのdocker sandbox kit

開発時には、以下を守る

## 必ず守る

- Sandbox内に、リポジトリにpushしてはいけないファイルを配置しない
  - AIがどんなに誤作動しても、漏れてはいけない情報が漏れないようにするため。
  - 例外として、workspace内にユーザー自身が機密情報を置くことは許容する。workspace内に機密情報がないことを保証するのはユーザーであり、このsandboxシステムではない。

## 破る必要がある場合は、必ずユーザーに確認した上で、破っても良い

- network whitelistを追加しない