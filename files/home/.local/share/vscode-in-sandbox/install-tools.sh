#!/usr/bin/env bash
set -euo pipefail

MISE_VERSION="2026.7.11"

log() { printf '[vscode-in-sandbox:install] %s\n' "$*" >&2; }

case "$(uname -m)" in
  x86_64) mise_arch="x64" ;;
  aarch64|arm64) mise_arch="arm64" ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
export MISE_SYSTEM_DATA_DIR=/usr/local/share/mise
export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

install -D -m 0644 \
  /home/agent/.local/share/vscode-in-sandbox/mise-config.toml \
  /etc/mise/config.toml

log "installing system packages"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git openssh-client pre-commit xz-utils zsh

log "installing mise ${MISE_VERSION}"
mise_download_dir="$(mktemp -d)"
curl -fsSL --connect-timeout 15 --max-time 900 --retry 3 --retry-all-errors \
  "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${mise_arch}.tar.xz" \
  -o "${mise_download_dir}/mise.tar.xz"
tar -xJf "${mise_download_dir}/mise.tar.xz" -C "${mise_download_dir}"
mise_binary="$(find "${mise_download_dir}" -type f -name mise -print -quit)"
test -n "${mise_binary}"
install -m 0755 "${mise_binary}" /usr/local/bin/mise
rm -rf "${mise_download_dir}"

log "installing tools from mise config"
mise install --system

for tool_bin in node npm npx corepack bun python python3 pip3 uv uvx terraform codex playwright-cli; do
  tool_path="$(mise which "${tool_bin}")"
  ln -sfn "${tool_path}" "/usr/local/bin/${tool_bin}"
done
codex_path="$(mise which codex)"
ln -sfn "${codex_path}" /usr/local/share/npm-global/bin/codex

log "installing Playwright Chromium and runtime dependencies"
mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"
playwright-cli install-browser --with-deps chromium

log "installing oh-my-zsh"
git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /home/agent/.oh-my-zsh
rm -rf /home/agent/.oh-my-zsh/.git
chown -R agent:agent /home/agent/.oh-my-zsh "${PLAYWRIGHT_BROWSERS_PATH}"

rm -rf \
  /root/.cache \
  /root/.config/mise \
  /root/.local/share/mise \
  /usr/local/share/mise/downloads \
  /usr/local/share/mise/cache \
  /var/lib/apt/lists/*

log "verifying installed versions"
test "$(mise --version | awk '{print $1}')" = "${MISE_VERSION}"
test "$(node --version)" = "v24.18.0"
test "$(bun --version)" = "1.3.14"
test "$(python3 --version)" = "Python 3.14.6"
test "$(uv --version | awk '{print $2}')" = "0.11.28"
test "$(terraform version -json | awk -F '\"' '/terraform_version/ { print $4 }')" = "1.15.8"
test "$(codex --version)" = "codex-cli 0.144.6"
command -v pre-commit >/dev/null
command -v playwright-cli >/dev/null
playwright-cli install-browser --list | grep -q chromium
test -f /home/agent/.oh-my-zsh/oh-my-zsh.sh
