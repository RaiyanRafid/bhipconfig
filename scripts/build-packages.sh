#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT_DIR}/scripts/build-deb.sh"

if command -v rpmbuild >/dev/null 2>&1; then
  "${ROOT_DIR}/scripts/build-rpm.sh"
else
  echo "Skipping RPM build because rpmbuild is not installed on this machine."
fi
