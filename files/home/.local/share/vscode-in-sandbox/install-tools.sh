#!/usr/bin/env bash
set -euo pipefail

MISE_VERSION="2026.10.22"

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
  ca-certificates curl git libatomic1 openssh-client pre-commit xz-utils zsh

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

for tool_bin in node npm npx corepack bun python python3 pip3 uv uvx terraform playwright-cli; do
  case "${tool_bin}" in
    npm|npx)
      tool_path="$(mise which --tool npm:npm@12.2.1 "${tool_bin}")"
      printf '#!/bin/sh\nexec %s "$@"\n' "${tool_path}" > "/usr/local/bin/${tool_bin}"
      chmod 0755 "/usr/local/bin/${tool_bin}"
      ;;
    corepack)
      tool_path="$(mise which --tool npm:corepack@0.36.0 "${tool_bin}")"
      printf '#!/bin/sh\nexec %s "$@"\n' "${tool_path}" > "/usr/local/bin/${tool_bin}"
      chmod 0755 "/usr/local/bin/${tool_bin}"
      ;;
    *)
      tool_path="$(mise which "${tool_bin}")"
      ln -sfn "${tool_path}" "/usr/local/bin/${tool_bin}"
      ;;
  esac
done

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
verify_version() {
  local name="$1" actual="$2" expected="$3"
  log "${name}: ${actual}"
  test "${actual}" = "${expected}"
}
verify_version mise "$(mise --version | awk '{print $1}')" "${MISE_VERSION}"
verify_version node "$(node --version)" "v26.13.0"
verify_version npm "$(npm --version)" "12.2.1"
verify_version corepack "$(corepack --version)" "0.36.0"
verify_version bun "$(bun --version)" "1.4.4"
verify_version python "$(python3 --version)" "Python 3.15.2"
verify_version uv "$(uv --version | awk '{print $2}')" "0.13.6"
verify_version terraform "$(terraform version -json | awk -F '\"' '/terraform_version/ { print $4 }')" "1.17.1"
command -v codex >/dev/null
codex --version >/dev/null
command -v pre-commit >/dev/null
command -v playwright-cli >/dev/null
playwright-cli install-browser --list | grep -q chromium
test -f /home/agent/.oh-my-zsh/oh-my-zsh.sh
