# flagxs-dev-local-env-bootstrap

開発環境構築の最初のインストール作業を行うスクリプトです。
Ubuntu (WSL2 を含む) に、環境構築を進めるうえで最低限必要なツールをインストールします。

## 使い方

```bash
curl -fsSL https://raw.githubusercontent.com/sevend-dev/flagxs-dev-local-env-bootstrap/main/install.sh | bash
```

実行後の手順はスクリプトの完了時に表示されます。
再実行しても安全です。インストール済みのものはスキップされます。

## 前提

- Ubuntu 系のディストリビューション
- `sudo` が実行できる、普段使うユーザー (root では実行しないでください)
