#!/usr/bin/env bash
#
# flagxs 開発環境構築のブートストラップスクリプト。
# Ansible、GitHub CLI、Claude Code を Ubuntu にインストールする。
#
# 使い方:
#   curl -fsSL https://raw.githubusercontent.com/sevend-dev/flagxs-dev-local-env-bootstrap/main/install.sh | bash
#
# 実行後は構成管理リポジトリを clone して playbook を実行すること。
#
set -euo pipefail

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

add_ansible_ppa() {
  if [[ -n "$(find /etc/apt/sources.list.d -name '*ansible*' -print -quit 2>/dev/null)" ]]; then
    log "Ansible の PPA は既に追加済みのためスキップします"
    return
  fi

  log "Ansible の PPA を追加します"
  sudo add-apt-repository --yes --update ppa:ansible/ansible
}

install_ansible() {
  log "Ansible をインストールします"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible
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

print_next_steps() {
  cat <<'MSG'

セットアップが完了しました。続けて以下を実行してください。

  1. GitHub の認証を済ませる
       gh auth login

  2. Claude Code にログインする
       claude

  3. 構成管理リポジトリを clone し、README の手順に従って playbook を実行する

MSG
}

main() {
  check_prerequisites
  authenticate_sudo
  install_apt_packages
  add_ansible_ppa
  install_ansible
  add_github_cli_repository
  install_github_cli
  install_claude_code

  log "インストールされた Ansible: $(ansible --version | head -n 1)"
  log "インストールされた GitHub CLI: $(gh --version | head -n 1)"
  warn_if_local_bin_not_in_path
  print_next_steps
}

main "$@"
