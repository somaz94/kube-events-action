#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-latest}"

# Determine OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "${ARCH}" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  arm64)   ARCH="arm64" ;;
  *)       echo "::error::Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

case "${OS}" in
  linux)  OS="linux" ;;
  darwin) OS="darwin" ;;
  *)      echo "::error::Unsupported OS: ${OS}"; exit 1 ;;
esac

# Resolve version
if [[ "${VERSION}" == "latest" ]]; then
  echo "::group::Resolving latest kube-events version"
  VERSION=$(curl -sL https://api.github.com/repos/somaz94/kube-events/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  if [[ -z "${VERSION}" ]]; then
    echo "::error::Failed to resolve latest version"
    exit 1
  fi
  echo "Resolved version: ${VERSION}"
  echo "::endgroup::"
fi

# Strip leading 'v' for filename
VERSION_NUM="${VERSION#v}"

FILENAME="kube-events_${VERSION_NUM}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/somaz94/kube-events/releases/download/${VERSION}/${FILENAME}"

echo "::group::Installing kube-events ${VERSION} (${OS}/${ARCH})"
echo "Downloading: ${URL}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

if ! curl -sL -o "${TMPDIR}/kube-events.tar.gz" "${URL}"; then
  echo "::error::Failed to download kube-events from ${URL}"
  exit 1
fi

tar -xzf "${TMPDIR}/kube-events.tar.gz" -C "${TMPDIR}"

if [[ ! -f "${TMPDIR}/kube-events" ]]; then
  echo "::error::kube-events binary not found in archive"
  exit 1
fi

chmod +x "${TMPDIR}/kube-events"
sudo mv "${TMPDIR}/kube-events" /usr/local/bin/kube-events

echo "Installed: $(kube-events version)"
echo "::endgroup::"
