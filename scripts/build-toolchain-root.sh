#!/usr/bin/env bash
set -euo pipefail

MISE_VERSION="2026.7.11"

case "$(uname -m)" in
  x86_64) mise_arch="x64" ;;
  aarch64|arm64) mise_arch="arm64" ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
export MISE_SYSTEM_DATA_DIR=/usr/local/share/mise

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git xz-utils zstd
install -D -m 0644 \
  /home/agent/.local/share/vscode-in-sandbox/mise-config.toml \
  /etc/mise/config.toml

mise_download_dir="$(mktemp -d)"
curl -fsSL --connect-timeout 15 --max-time 900 --retry 3 --retry-all-errors \
  "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${mise_arch}.tar.xz" \
  -o "${mise_download_dir}/mise.tar.xz"
tar -xJf "${mise_download_dir}/mise.tar.xz" -C "${mise_download_dir}"
mise_binary="$(find "${mise_download_dir}" -type f -name mise -print -quit)"
test -n "${mise_binary}"
install -m 0755 "${mise_binary}" /usr/local/bin/mise
rm -rf "${mise_download_dir}"
mise install --system

mkdir -p /ms-playwright
playwright_cli="$(mise which playwright-cli)"
"${playwright_cli}" install-browser chromium

install -d -m 0755 -o agent -g agent /home/agent/.agents/skills
playwright_package_dir="$(mise where 'npm:@playwright/cli')"
playwright_skill_dir="$(find "${playwright_package_dir}" -type d -path '*/skills/playwright-cli' -print -quit)"
test -n "${playwright_skill_dir}"
cp -a "${playwright_skill_dir}" /home/agent/.agents/skills/

git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /home/agent/.oh-my-zsh
rm -rf /home/agent/.oh-my-zsh/.git
chown -R agent:agent /home/agent/.agents /home/agent/.oh-my-zsh /ms-playwright

rm -rf \
  /root/.cache \
  /root/.config/mise \
  /root/.local/share/mise \
  /usr/local/share/mise/downloads \
  /usr/local/share/mise/cache \
  /var/lib/apt/lists/*

install -d /artifact-root/usr/local/bin /artifact-root/usr/local/share/vscode-in-sandbox
install -d /artifact-root/home/agent/.agents/skills /artifact-root/ms-playwright
cp -a /usr/local/bin/mise /artifact-root/usr/local/bin/mise
cp -a /usr/local/share/mise /artifact-root/usr/local/share/mise
cp -a /ms-playwright/. /artifact-root/ms-playwright/
cp -a /home/agent/.agents/skills/playwright-cli /artifact-root/home/agent/.agents/skills/
cp -a /home/agent/.oh-my-zsh /artifact-root/home/agent/.oh-my-zsh
chown -R agent:agent /artifact-root/home/agent /artifact-root/ms-playwright
printf 'mise_version=%s\n' "${MISE_VERSION}" \
  > /artifact-root/usr/local/share/vscode-in-sandbox/toolchain.env

test -x /artifact-root/usr/local/bin/mise
test -d /artifact-root/usr/local/share/mise/installs
test -f /artifact-root/home/agent/.agents/skills/playwright-cli/SKILL.md
test -f /artifact-root/home/agent/.oh-my-zsh/oh-my-zsh.sh
test -n "$(find /artifact-root/ms-playwright -maxdepth 1 -type d -name 'chromium-*' -print -quit)"
