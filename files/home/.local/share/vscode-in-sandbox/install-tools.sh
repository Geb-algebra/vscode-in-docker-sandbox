#!/usr/bin/env bash
set -euo pipefail

MISE_VERSION="2026.7.11"

log() {
  printf '[vscode-in-sandbox:install] %s\n' "$*" >&2
}

wait_for_apt() {
  local timeout=300
  local elapsed=0

  while pgrep -x apt-get >/dev/null 2>&1 \
    || pgrep -x apt >/dev/null 2>&1 \
    || pgrep -x dpkg >/dev/null 2>&1 \
    || pgrep -x unattended-upgr >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${timeout}" ]; then
      log "timed out waiting for another apt/dpkg process after ${timeout}s"
      return 1
    fi
    if [ $((elapsed % 10)) -eq 0 ]; then
      log "waiting for another apt/dpkg process (${elapsed}s)"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
}

case "$(uname -m)" in
  x86_64)
    mise_arch="x64"
    ;;
  aarch64|arm64)
    mise_arch="arm64"
    ;;
  *)
    printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
log "installing system build dependencies"
wait_for_apt
install -D -m 0644 \
  /home/agent/.local/share/vscode-in-sandbox/mise-config.toml \
  /etc/mise/config.toml
apt-get -o DPkg::Lock::Timeout=300 update
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  openssh-client \
  pre-commit \
  pkg-config \
  zsh

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

log "installing mise ${MISE_VERSION}"
curl -fsSL "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-${mise_arch}" \
  -o /usr/local/bin/mise
chmod 0755 /usr/local/bin/mise

log "installing tools from mise config"
MISE_SYSTEM_DATA_DIR=/usr/local/share/mise mise install --system

for tool_bin in node npm npx corepack bun python python3 pip3 uv uvx terraform codex playwright-cli; do
  tool_path="$(MISE_SYSTEM_DATA_DIR=/usr/local/share/mise mise which "${tool_bin}")"
  ln -sfn "${tool_path}" "/usr/local/bin/${tool_bin}"
done

# The built-in codex-docker template puts its npm-global bin directory before
# /usr/local/bin. Replace only its Codex launcher so the pinned mise version is
# also used by SSH sessions and subsequent agent starts.
codex_path="$(MISE_SYSTEM_DATA_DIR=/usr/local/share/mise mise which codex)"
ln -sfn "${codex_path}" /usr/local/share/npm-global/bin/codex

log "installing Playwright browser"
export PLAYWRIGHT_BROWSERS_PATH="/ms-playwright"
mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"
playwright-cli install-browser --with-deps
chown -R agent:agent "${PLAYWRIGHT_BROWSERS_PATH}"

log "installing Playwright CLI skill"
install -d -m 0755 -o agent -g agent /home/agent/.agents/skills
playwright_package_dir="$(MISE_SYSTEM_DATA_DIR=/usr/local/share/mise mise where 'npm:@playwright/cli')"
playwright_skill_dir="$(find "${playwright_package_dir}" -type d -path '*/skills/playwright-cli' -print -quit)"
test -n "${playwright_skill_dir}"
rm -rf /home/agent/.agents/skills/playwright-cli
cp -a "${playwright_skill_dir}" \
  /home/agent/.agents/skills/
chown -R agent:agent /home/agent/.agents/skills/playwright-cli

log "installing oh-my-zsh"
if [ ! -f /home/agent/.oh-my-zsh/oh-my-zsh.sh ]; then
  rm -rf /home/agent/.oh-my-zsh
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /home/agent/.oh-my-zsh
fi
chown -R agent:agent /home/agent/.oh-my-zsh

rm -rf /var/lib/apt/lists/*

log "verifying installed versions"
test "$(node --version)" = "v24.18.0"
test "$(bun --version)" = "1.3.14"
test "$(python3 --version)" = "Python 3.14.6"
test "$(uv --version | awk '{print $2}')" = "0.11.28"
test "$(terraform version -json | awk -F '\"' '/terraform_version/ { print $4 }')" = "1.15.8"
test "$(codex --version)" = "codex-cli 0.144.6"
command -v pre-commit >/dev/null
command -v playwright-cli >/dev/null
playwright-cli install-browser --list | grep -q chromium
test -f /home/agent/.agents/skills/playwright-cli/SKILL.md
