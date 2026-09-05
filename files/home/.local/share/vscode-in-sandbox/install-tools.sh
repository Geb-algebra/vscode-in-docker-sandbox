#!/usr/bin/env bash
set -euo pipefail

log() { printf '[vscode-in-sandbox:install] %s\n' "$*" >&2; }

wait_for_apt() {
  local timeout=300 elapsed=0
  while pgrep -x apt-get >/dev/null 2>&1 || pgrep -x apt >/dev/null 2>&1 \
    || pgrep -x dpkg >/dev/null 2>&1 || pgrep -x unattended-upgr >/dev/null 2>&1; do
    if [ "${elapsed}" -ge "${timeout}" ]; then
      log "timed out waiting for another apt/dpkg process after ${timeout}s"
      return 1
    fi
    if [ $((elapsed % 10)) -eq 0 ]; then log "waiting for another apt/dpkg process (${elapsed}s)"; fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
}

case "$(uname -m)" in
  x86_64) artifact_arch="amd64" ;;
  aarch64|arm64) artifact_arch="arm64" ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

artifact_path_file="/home/agent/.local/share/vscode-in-sandbox/artifact-path"
artifact_dir="$(sed -n '1p' "${artifact_path_file}")"
case "${artifact_dir}" in
  /*) ;;
  *) log "artifact directory must be an absolute mounted path"; exit 1 ;;
esac
artifact_name="toolchain-linux-${artifact_arch}.tar.zst"
artifact_path="${artifact_dir}/${artifact_name}"
checksum_path="${artifact_path}.sha256"
test -r "${artifact_path}"
test -r "${checksum_path}"

log "verifying prebuilt toolchain artifact"
expected_hash="$(awk 'NR == 1 { print $1 }' "${checksum_path}")"
actual_hash="$(sha256sum "${artifact_path}" | awk '{print $1}')"
if ! printf '%s' "${expected_hash}" | grep -Eq '^[0-9a-f]{64}$' \
  || [ "${actual_hash}" != "${expected_hash}" ]; then
  log "artifact checksum mismatch"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
log "installing runtime system packages"
wait_for_apt
apt-get -o DPkg::Lock::Timeout=300 update
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
  ca-certificates git openssh-client pre-commit zsh zstd

# Reject absolute paths, traversal, and additions outside the deliberately
# small root-relative payload before extracting as root.
if tar --zstd -tf "${artifact_path}" | awk '
  /^\// || /(^|\/)\.\.($|\/)/ { bad = 1 }
  !/^(usr(\/local(\/(bin(\/mise)?|share(\/(mise(\/.*)?|vscode-in-sandbox(\/toolchain\.env)?))?))?)?|ms-playwright(\/.*)?|home(\/agent(\/(\.agents(\/skills(\/playwright-cli(\/.*)?)?)?|\.oh-my-zsh(\/.*)?))?)?)\/?$/ { bad = 1 }
  END { exit bad ? 0 : 1 }
'; then
  log "artifact contains an unsafe or unexpected path"
  exit 1
fi

log "extracting prebuilt toolchain"
tar --zstd -xpf "${artifact_path}" -C /
install -D -m 0644 /home/agent/.local/share/vscode-in-sandbox/mise-config.toml /etc/mise/config.toml

export MISE_SYSTEM_DATA_DIR=/usr/local/share/mise
export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
for tool_bin in node npm npx corepack bun python python3 pip3 uv uvx terraform codex playwright-cli; do
  tool_path="$(mise which "${tool_bin}")"
  ln -sfn "${tool_path}" "/usr/local/bin/${tool_bin}"
done
codex_path="$(mise which codex)"
ln -sfn "${codex_path}" /usr/local/share/npm-global/bin/codex

log "installing Playwright runtime dependencies"
# Chromium is already in PLAYWRIGHT_BROWSERS_PATH, so this installs Linux
# runtime packages without downloading the browser again.
playwright-cli install-browser --with-deps chromium

chown -R agent:agent /home/agent/.oh-my-zsh /home/agent/.agents/skills/playwright-cli /ms-playwright
rm -rf /var/lib/apt/lists/*

log "verifying installed versions"
artifact_mise_version="$(sed -n 's/^mise_version=//p' /usr/local/share/vscode-in-sandbox/toolchain.env)"
test -n "${artifact_mise_version}"
test "$(mise --version | awk '{print $1}')" = "${artifact_mise_version}"
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
test -f /home/agent/.oh-my-zsh/oh-my-zsh.sh
