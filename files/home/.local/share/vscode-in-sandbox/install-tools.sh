#!/usr/bin/env bash
set -euo pipefail

NODE_VERSION="24.18.0"
PNPM_VERSION="11.11.0"
PYTHON_VERSION="3.14.6"
UV_VERSION="0.11.28"
PLAYWRIGHT_CLI_PACKAGE="@playwright/cli@latest"

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
    node_arch="x64"
    uv_arch="x86_64"
    vscode_arch="x64"
    ;;
  aarch64|arm64)
    node_arch="arm64"
    uv_arch="aarch64"
    vscode_arch="arm64"
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
  libbz2-dev \
  libexpat1-dev \
  libffi-dev \
  libgdbm-compat-dev \
  libgdbm-dev \
  liblzma-dev \
  libncursesw5-dev \
  libreadline-dev \
  libsqlite3-dev \
  libssl-dev \
  libxml2-dev \
  libxmlsec1-dev \
  openssh-server \
  pkg-config \
  tk-dev \
  uuid-dev \
  xz-utils \
  zsh \
  zlib1g-dev

# Generate unique host keys when each sandbox first starts, not in the shared image.
rm -f /etc/ssh/ssh_host_*

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

log "installing Node.js ${NODE_VERSION}"
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
  -o "${tmp_dir}/node.tar.xz"
rm -rf "/opt/node-v${NODE_VERSION}"
mkdir -p "/opt/node-v${NODE_VERSION}"
tar -xJf "${tmp_dir}/node.tar.xz" -C "/opt/node-v${NODE_VERSION}" --strip-components=1
ln -sfn "/opt/node-v${NODE_VERSION}/bin/node" /usr/local/bin/node
ln -sfn "/opt/node-v${NODE_VERSION}/bin/npm" /usr/local/bin/npm
ln -sfn "/opt/node-v${NODE_VERSION}/bin/npx" /usr/local/bin/npx
ln -sfn "/opt/node-v${NODE_VERSION}/bin/corepack" /usr/local/bin/corepack

log "installing pnpm ${PNPM_VERSION}"
"/opt/node-v${NODE_VERSION}/bin/npm" install --global --prefix /usr/local "pnpm@${PNPM_VERSION}"

log "installing Playwright CLI"
"/opt/node-v${NODE_VERSION}/bin/npm" install --global --prefix /usr/local "${PLAYWRIGHT_CLI_PACKAGE}"

log "installing Playwright browser"
export PLAYWRIGHT_BROWSERS_PATH="/ms-playwright"
mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}"
playwright-cli install-browser --with-deps
chown -R agent:agent "${PLAYWRIGHT_BROWSERS_PATH}"

log "installing Playwright CLI skill"
install -d -m 0755 -o agent -g agent /home/agent/.agents/skills
cp -a /usr/local/lib/node_modules/@playwright/cli/skills/playwright-cli \
  /home/agent/.agents/skills/
chown -R agent:agent /home/agent/.agents/skills/playwright-cli

log "building CPython ${PYTHON_VERSION}"
curl -fsSL "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" \
  -o "${tmp_dir}/python.tgz"
mkdir -p "${tmp_dir}/python-source"
tar -xzf "${tmp_dir}/python.tgz" -C "${tmp_dir}/python-source" --strip-components=1
(
  cd "${tmp_dir}/python-source"
  ./configure \
    --prefix="/opt/python-${PYTHON_VERSION}" \
    --with-ensurepip=install
  make -j"$(nproc)"
  make install
)
ln -sfn "/opt/python-${PYTHON_VERSION}/bin/python3" /usr/local/bin/python3
ln -sfn "/opt/python-${PYTHON_VERSION}/bin/python3" /usr/local/bin/python
ln -sfn "/opt/python-${PYTHON_VERSION}/bin/pip3" /usr/local/bin/pip3

log "installing uv ${UV_VERSION}"
curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${uv_arch}-unknown-linux-gnu.tar.gz" \
  -o "${tmp_dir}/uv.tar.gz"
mkdir -p "${tmp_dir}/uv"
tar -xzf "${tmp_dir}/uv.tar.gz" -C "${tmp_dir}/uv" --strip-components=1
install -m 0755 "${tmp_dir}/uv/uv" /usr/local/bin/uv
install -m 0755 "${tmp_dir}/uv/uvx" /usr/local/bin/uvx

log "installing stable VS Code"
curl -fsSL "https://update.code.visualstudio.com/latest/linux-deb-${vscode_arch}/stable" \
  -o "${tmp_dir}/vscode.deb"
apt-get -o DPkg::Lock::Timeout=300 install -y "${tmp_dir}/vscode.deb"
rm -rf /var/lib/apt/lists/*

log "verifying installed versions"
test "$(node --version)" = "v${NODE_VERSION}"
test "$(pnpm --version)" = "${PNPM_VERSION}"
test "$(python3 --version)" = "Python ${PYTHON_VERSION}"
test "$(uv --version | awk '{print $2}')" = "${UV_VERSION}"
command -v code >/dev/null
command -v playwright-cli >/dev/null
playwright-cli install-browser --list | grep -q chromium
test -f /home/agent/.agents/skills/playwright-cli/SKILL.md
