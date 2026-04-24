#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
PACKAGE_NAME="bhipconfig"
ARCH="${DEB_ARCH:-all}"
DIST_DIR="${ROOT_DIR}/dist"
STAGE_DIR="${DIST_DIR}/deb-stage"
PACKAGE_DIR="${STAGE_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}"
OUTPUT_DEB="${DIST_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"
MAINTAINER="${MAINTAINER:-Bahari Network Team <packages@bahari.local>}"

mkdir -p "${PACKAGE_DIR}/DEBIAN"
mkdir -p "${PACKAGE_DIR}/usr/bin"
mkdir -p "${PACKAGE_DIR}/usr/share/doc/${PACKAGE_NAME}"
rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/DEBIAN" "${PACKAGE_DIR}/usr/bin" "${PACKAGE_DIR}/usr/share/doc/${PACKAGE_NAME}"

install -m 755 "${ROOT_DIR}/bhipconfig" "${PACKAGE_DIR}/usr/bin/${PACKAGE_NAME}"
install -m 644 "${ROOT_DIR}/README.md" "${PACKAGE_DIR}/usr/share/doc/${PACKAGE_NAME}/README.md"

cat > "${PACKAGE_DIR}/DEBIAN/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: python3
Maintainer: ${MAINTAINER}
Description: Futuristic CLI network manager for Linux servers
 A dependency-light interactive network control surface for Linux.
 It wraps iproute2 and resolver tooling behind a safer terminal UI
 with rollback protection for disruptive network changes.
EOF

dpkg-deb --build --root-owner-group "${PACKAGE_DIR}" "${OUTPUT_DEB}" >/dev/null
echo "Built ${OUTPUT_DEB}"
