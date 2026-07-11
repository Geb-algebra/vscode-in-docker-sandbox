#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_NAME="${SBX_TEMPLATE_NAME:-local/vscode-codex:1}"
TEMPLATE_TAR="${SCRIPT_DIR}/.vscode-codex-template.tmp.tar"

cleanup() {
  rm -f "${TEMPLATE_TAR}"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build the sandbox template." >&2
  exit 1
fi

if ! command -v sbx >/dev/null 2>&1; then
  echo "sbx is required to load the sandbox template." >&2
  exit 1
fi

printf '[build-template] building %s\n' "${TEMPLATE_NAME}" >&2
docker build --tag "${TEMPLATE_NAME}" "${SCRIPT_DIR}"

printf '[build-template] exporting image to temporary tar\n' >&2
docker image save "${TEMPLATE_NAME}" --output "${TEMPLATE_TAR}"

printf '[build-template] loading image into Docker Sandboxes\n' >&2
sbx template load "${TEMPLATE_TAR}"

printf '[build-template] loaded %s\n' "${TEMPLATE_NAME}" >&2
