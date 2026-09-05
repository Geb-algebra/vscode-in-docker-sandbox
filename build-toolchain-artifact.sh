#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACT_DIR="${SCRIPT_DIR}/artifacts"
ARTIFACT_PATH_FILE="${SCRIPT_DIR}/files/home/.local/share/vscode-in-sandbox/artifact-path"
IMAGE_NAME="vscode-in-sandbox-toolchain:local"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build the toolchain artifact." >&2
  exit 1
fi

case "$(uname -m)" in
  arm64|aarch64)
    artifact_arch="arm64"
    docker_platform="linux/arm64"
    ;;
  x86_64|amd64)
    artifact_arch="amd64"
    docker_platform="linux/amd64"
    ;;
  *)
    printf 'Unsupported host architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

artifact_name="toolchain-linux-${artifact_arch}.tar.zst"
artifact_path="${ARTIFACT_DIR}/${artifact_name}"
checksum_path="${artifact_path}.sha256"
mkdir -p "${ARTIFACT_DIR}"

printf '[build-toolchain-artifact] building for %s\n' "${docker_platform}" >&2
docker build \
  --platform "${docker_platform}" \
  --file "${SCRIPT_DIR}/Dockerfile.toolchain" \
  --tag "${IMAGE_NAME}" \
  "${SCRIPT_DIR}"

printf '[build-toolchain-artifact] exporting %s\n' "${artifact_name}" >&2
docker run --rm --platform "${docker_platform}" \
  --user "$(id -u):$(id -g)" \
  --volume "${ARTIFACT_DIR}:/out" \
  "${IMAGE_NAME}"
mv "${ARTIFACT_DIR}/toolchain.tar.zst" "${artifact_path}"

if command -v sha256sum >/dev/null 2>&1; then
  artifact_hash="$(sha256sum "${artifact_path}" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  artifact_hash="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
else
  echo "sha256sum or shasum is required to checksum the artifact." >&2
  exit 1
fi
printf '%s  %s\n' "${artifact_hash}" "${artifact_name}" > "${checksum_path}"

printf '%s\n' "${ARTIFACT_DIR}" > "${ARTIFACT_PATH_FILE}"

printf '[build-toolchain-artifact] wrote %s\n' "${artifact_path}" >&2
printf '[build-toolchain-artifact] wrote %s\n' "${checksum_path}" >&2
printf '[build-toolchain-artifact] wrote %s\n' "${ARTIFACT_PATH_FILE}" >&2
