#!/usr/bin/env bash
set -euo pipefail

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "rpmbuild is required to create the AlmaLinux/RHEL package." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
PACKAGE_NAME="bhipconfig"
RELEASE="${RPM_RELEASE:-1}"
DIST_DIR="${ROOT_DIR}/dist"
RPM_ROOT="${DIST_DIR}/rpmbuild"
TARBALL="${RPM_ROOT}/SOURCES/${PACKAGE_NAME}-${VERSION}.tar.gz"
SOURCE_DIR="${RPM_ROOT}/SOURCES/${PACKAGE_NAME}-${VERSION}"

rm -rf "${RPM_ROOT}"
mkdir -p "${RPM_ROOT}/BUILD" "${RPM_ROOT}/BUILDROOT" "${RPM_ROOT}/RPMS" "${RPM_ROOT}/SOURCES" "${RPM_ROOT}/SPECS" "${RPM_ROOT}/SRPMS"
mkdir -p "${SOURCE_DIR}"

install -m 755 "${ROOT_DIR}/bhipconfig" "${SOURCE_DIR}/bhipconfig"
install -m 644 "${ROOT_DIR}/README.md" "${SOURCE_DIR}/README.md"
install -m 644 "${ROOT_DIR}/VERSION" "${SOURCE_DIR}/VERSION"
tar -C "${RPM_ROOT}/SOURCES" -czf "${TARBALL}" "${PACKAGE_NAME}-${VERSION}"

sed "s/@RELEASE@/${RELEASE}/g" "${ROOT_DIR}/packaging/rpm/bhipconfig.spec" > "${RPM_ROOT}/SPECS/bhipconfig.spec"

rpmbuild \
  --define "_topdir ${RPM_ROOT}" \
  --define "version ${VERSION}" \
  --define "release ${RELEASE}" \
  -ba "${RPM_ROOT}/SPECS/bhipconfig.spec" >/dev/null

find "${RPM_ROOT}/RPMS" -name "*.rpm" -print
