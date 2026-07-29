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
find /etc/apt -type f \( -name '*.list' -o -name '*.sources' \) -exec \
  sed -i \
    -e 's|http://ports.ubuntu.com/ubuntu-ports|https://mirrors.ocf.berkeley.edu/ubuntu-ports|g' \
    -e 's|https://ports.ubuntu.com/ubuntu-ports|https://mirrors.ocf.berkeley.edu/ubuntu-ports|g' \
    -e 's|http://archive.ubuntu.com|https://archive.ubuntu.com|g' \
    -e 's|http://security.ubuntu.com|https://security.ubuntu.com|g' \
    {} +
apt-get -o DPkg::Lock::Timeout=300 update
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  git \
  openssh-server \
  pkg-config \
  zsh

# Generate unique host keys when each sandbox first starts, not in the shared image.
rm -f /etc/ssh/ssh_host_*

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
cp -a "${playwright_skill_dir}" \
  /home/agent/.agents/skills/
chown -R agent:agent /home/agent/.agents/skills/playwright-cli

rm -rf /var/lib/apt/lists/*

log "verifying installed versions"
test "$(node --version)" = "v24.18.0"
test "$(bun --version)" = "1.3.14"
test "$(python3 --version)" = "Python 3.14.6"
test "$(uv --version | awk '{print $2}')" = "0.11.28"
test "$(terraform version -json | awk -F '\"' '/terraform_version/ { print $4 }')" = "1.15.8"
command -v codex >/dev/null
command -v playwright-cli >/dev/null
playwright-cli install-browser --list | grep -q chromium
playwright-cli open about:blank
playwright-cli close
test -f /home/agent/.agents/skills/playwright-cli/SKILL.md
