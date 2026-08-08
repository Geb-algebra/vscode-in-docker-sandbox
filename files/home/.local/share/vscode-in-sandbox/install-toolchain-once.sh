#!/usr/bin/env bash
set -euo pipefail

state_dir="/home/agent/.local/state/vscode-in-sandbox"
ready_file="${state_dir}/toolchain.ready"
failed_file="${state_dir}/toolchain.failed"
log_file="${state_dir}/toolchain-install.log"
install_script="/home/agent/.local/share/vscode-in-sandbox/install-tools.sh"

install -d -m 0755 -o agent -g agent "${state_dir}"

if [ -f "${ready_file}" ]; then
  exit 0
fi

rm -f "${failed_file}"
touch "${log_file}"
chown agent:agent "${log_file}"

record_failure() {
  status="$?"
  trap - EXIT
  if [ "${status}" -ne 0 ]; then
    printf 'install-tools.sh exited with status %s\n' "${status}" > "${failed_file}"
    chown agent:agent "${failed_file}"
  fi
  exit "${status}"
}
trap record_failure EXIT

exec > >(tee -a "${log_file}") 2>&1

printf '[vscode-in-sandbox:install-once] installing toolchain\n'
bash "${install_script}"
touch "${ready_file}"
chown agent:agent "${ready_file}"
rm -f "${failed_file}"
printf '[vscode-in-sandbox:install-once] toolchain is ready\n'
