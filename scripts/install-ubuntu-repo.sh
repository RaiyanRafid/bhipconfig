#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <apt_repo_base_url> [key_url]" >&2
  echo "Example: $0 https://repo.example.com/apt" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required on the target Ubuntu host." >&2
  exit 1
fi

APT_REPO_BASE_URL="${1%/}"
KEY_URL="${2:-${APT_REPO_BASE_URL}/keyrings/bhipconfig-archive-keyring.gpg}"
KEYRING_PATH="/etc/apt/keyrings/bhipconfig-archive-keyring.gpg"
SOURCE_PATH="/etc/apt/sources.list.d/bhipconfig.sources"
SUITE="${APT_SUITE:-stable}"
COMPONENT="${APT_COMPONENT:-main}"

sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL "${KEY_URL}" | sudo tee "${KEYRING_PATH}" >/dev/null

cat <<EOF | sudo tee "${SOURCE_PATH}" >/dev/null
Types: deb
URIs: ${APT_REPO_BASE_URL}
Suites: ${SUITE}
Components: ${COMPONENT}
Signed-By: ${KEYRING_PATH}
EOF

sudo apt update
echo "Ubuntu APT repository configured."
echo "Install with: sudo apt install bhipconfig"
