#!/usr/bin/env bash
set -euo pipefail

if ! command -v createrepo_c >/dev/null 2>&1; then
  echo "createrepo_c is required to create YUM/DNF repository metadata." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${ROOT_DIR}/dist"
RPM_REPO_DIR="${DIST_DIR}/repo/rpm"

mkdir -p "${RPM_REPO_DIR}"
find "${DIST_DIR}/rpmbuild/RPMS" -name "*.rpm" -exec cp -f {} "${RPM_REPO_DIR}/" \;

if ! compgen -G "${RPM_REPO_DIR}/*.rpm" >/dev/null; then
  echo "No RPM packages found in ${DIST_DIR}/rpmbuild/RPMS. Run scripts/build-rpm.sh first." >&2
  exit 1
fi

createrepo_c "${RPM_REPO_DIR}" >/dev/null

echo "YUM/DNF repo staged at ${RPM_REPO_DIR}"
echo "Host ${RPM_REPO_DIR} over HTTPS and add a .repo file pointing to that baseurl."
