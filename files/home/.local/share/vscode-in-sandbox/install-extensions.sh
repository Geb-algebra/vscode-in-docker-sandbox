#!/usr/bin/env bash
set -euo pipefail

extensions_file="/home/agent/.config/vscode-in-sandbox/extensions.txt"
extensions_dir="/home/agent/.vscode-server/extensions"

mkdir -p "${extensions_dir}"

while IFS= read -r extension_id; do
  case "${extension_id}" in
    ''|'#'*) continue ;;
  esac
  printf '[vscode-in-sandbox:extensions] installing %s\n' "${extension_id}" >&2
  code --extensions-dir "${extensions_dir}" --install-extension "${extension_id}" --force
done < "${extensions_file}"

installed="$(code --extensions-dir "${extensions_dir}" --list-extensions)"
while IFS= read -r extension_id; do
  case "${extension_id}" in
    ''|'#'*) continue ;;
  esac
  if ! printf '%s\n' "${installed}" | grep -Fxiq "${extension_id}"; then
    printf 'Extension was not installed: %s\n' "${extension_id}" >&2
    exit 1
  fi
done < "${extensions_file}"
