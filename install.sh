#!/usr/bin/env bash
#
# flagxs 開発環境構築のブートストラップスクリプト。
# GitHub CLI、mise、Claude Code を Ubuntu にインストールする。
#
# 実行コマンドを含む手順は社内の開発ドキュメントに記載している。
# 開発に必要なツールの残りは、実行後に社内の開発ドキュメントの手順で入れる。
#
set -euo pipefail

# software-properties-common は add-apt-repository のため。後段の手順で PPA を追加するのに使う
readonly APT_PACKAGES=(
  software-properties-common
  curl
)

readonly GITHUB_CLI_KEYRING=/etc/apt/keyrings/githubcli-archive-keyring.gpg
readonly GITHUB_CLI_SOURCE_LIST=/etc/apt/sources.list.d/github-cli.list

log() {
  printf '\033[1;34m==>\033[0m %s\n' "$*"
}

abort() {
  printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

check_prerequisites() {
  [[ "$(uname -s)" == "Linux" ]] || abort "このスクリプトは Linux (Ubuntu) 専用です。"
  command -v apt-get >/dev/null 2>&1 || abort "apt-get が見つかりません。Ubuntu 系のディストリビューションで実行してください。"
  command -v sudo >/dev/null 2>&1 || abort "sudo が見つかりません。"

  # root で実行すると Claude Code などが /root 配下に入ってしまう
  [[ "$(id -u)" -ne 0 ]] || abort "root ではなく、普段使うユーザーで実行してください。"
}

# sudo のパスワード入力を最初にまとめて済ませ、以降の処理を待たせない
authenticate_sudo() {
  if ! sudo -n true 2>/dev/null; then
    log "sudo のパスワードを入力してください"
    sudo -v
  fi
}

install_apt_packages() {
  log "apt パッケージインデックスを更新します"
  sudo apt-get update -y

  log "必要な apt パッケージをインストールします: ${APT_PACKAGES[*]}"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_PACKAGES[@]}"
}

# GitHub CLI は公式 apt リポジトリから取得する
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md
add_github_cli_repository() {
  if [[ -f "$GITHUB_CLI_KEYRING" && -f "$GITHUB_CLI_SOURCE_LIST" ]]; then
    log "GitHub CLI の apt リポジトリは既に追加済みのためスキップします"
    return
  fi

  log "GitHub CLI の apt リポジトリを追加します"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
    sudo tee "$GITHUB_CLI_KEYRING" >/dev/null
  sudo chmod go+r "$GITHUB_CLI_KEYRING"

  printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" "$GITHUB_CLI_KEYRING" |
    sudo tee "$GITHUB_CLI_SOURCE_LIST" >/dev/null

  sudo apt-get update -y
}

install_github_cli() {
  log "GitHub CLI をインストールします"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gh
}

# mise は公式インストーラで導入する。~/.local/bin/mise に配置される。
# 言語ランタイムや CLI ツールのバージョン管理に使うため、ユーザー権限で入れる。
# https://mise.jdx.dev/installing-mise.html
install_mise() {
  if command -v mise >/dev/null 2>&1; then
    log "mise は既にインストール済みのためスキップします: $(mise --version)"
    return
  fi

  log "mise をインストールします"
  curl -fsSL https://mise.run | sh
}

# mise をシェルで有効にするための設定を ~/.bashrc に追記する。
# 既に記述があればスキップする。
readonly MISE_ACTIVATE_LINE='eval "$($HOME/.local/bin/mise activate bash)"'

activate_mise_in_bashrc() {
  local bashrc="$HOME/.bashrc"

  if [[ -f "$bashrc" ]] && grep -Fq 'mise activate bash' "$bashrc"; then
    log "mise の有効化設定は既に ~/.bashrc にあるためスキップします"
    return
  fi

  log "mise の有効化設定を ~/.bashrc に追記します"
  printf '\n# mise\n%s\n' "$MISE_ACTIVATE_LINE" >>"$bashrc"
}

# Claude Code はネイティブインストーラで導入する。
# ~/.local/share/claude 配下にバージョンごとに配置され、自動アップデートが有効になる。
# root で実行するとホームディレクトリの配置先が変わるため sudo は使わない。
# https://code.claude.com/docs/en/setup
install_claude_code() {
  if command -v claude >/dev/null 2>&1; then
    log "Claude Code は既にインストール済みのためスキップします: $(claude --version)"
    return
  fi

  log "Claude Code をインストールします"
  curl -fsSL https://claude.ai/install.sh | bash
}

# インストーラは ~/.local/bin に claude を配置する。
# Ubuntu 標準の ~/.profile はこのディレクトリを PATH に追加するが、
# 反映にはログインし直しが必要なため、通っていない場合は案内する。
warn_if_local_bin_not_in_path() {
  case ":$PATH:" in
  *":$HOME/.local/bin:"*) return ;;
  esac

  log "注意: \$HOME/.local/bin が PATH に含まれていません。シェルを開き直すと有効になります。"
}

main() {
  check_prerequisites
  authenticate_sudo
  install_apt_packages
  add_github_cli_repository
  install_github_cli
  install_mise
  activate_mise_in_bashrc
  install_claude_code

  log "インストールされた GitHub CLI: $(gh --version | head -n 1)"
  log "インストールされた mise: $("$HOME/.local/bin/mise" --version)"
  warn_if_local_bin_not_in_path
  log '社内の開発ドキュメントの手順に従って、続きを進めてください'
}

main "$@"
