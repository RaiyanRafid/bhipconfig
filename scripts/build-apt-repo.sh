#!/usr/bin/env bash
set -euo pipefail

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
  echo "dpkg-scanpackages is required to create APT repository metadata." >&2
  exit 1
fi

if ! command -v apt-ftparchive >/dev/null 2>&1; then
  echo "apt-ftparchive is required to generate a proper Release file." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION")"
PACKAGE_NAME="bhipconfig"
DIST_DIR="${ROOT_DIR}/dist"
DEB_PATH="${DIST_DIR}/${PACKAGE_NAME}_${VERSION}_all.deb"
REPO_DIR="${DIST_DIR}/repo/apt"
POOL_DIR="${REPO_DIR}/pool/main/b/${PACKAGE_NAME}"
SUITE="${APT_SUITE:-stable}"
COMPONENT="${APT_COMPONENT:-main}"
ARCHES="${APT_ARCHES:-amd64 arm64}"
KEY_DIR="${REPO_DIR}/keyrings"
PUBLIC_KEY_ASC="${KEY_DIR}/bhipconfig-archive-keyring.asc"
PUBLIC_KEY_GPG="${KEY_DIR}/bhipconfig-archive-keyring.gpg"
ORIGIN="${APT_ORIGIN:-Bahari}"
LABEL="${APT_LABEL:-Bahari}"
DESCRIPTION="${APT_DESCRIPTION:-Bahari APT repository for bhipconfig}"
CODENAME="${APT_CODENAME:-$SUITE}"
SIGN_APT_REPO="${SIGN_APT_REPO:-0}"
GPG_KEY_ID="${APT_GPG_KEY_ID:-${GPG_KEY_ID:-}}"

if [[ ! -f "${DEB_PATH}" ]]; then
  echo "Debian package not found: ${DEB_PATH}" >&2
  echo "Run scripts/build-deb.sh first." >&2
  exit 1
fi

rm -rf "${REPO_DIR}"
mkdir -p "${POOL_DIR}" "${KEY_DIR}"
cp "${DEB_PATH}" "${POOL_DIR}/"

for arch in ${ARCHES}; do
  dist_meta_dir="${REPO_DIR}/dists/${SUITE}/${COMPONENT}/binary-${arch}"
  mkdir -p "${dist_meta_dir}"
  (
    cd "${REPO_DIR}"
    dpkg-scanpackages --arch all pool /dev/null > "dists/${SUITE}/${COMPONENT}/binary-${arch}/Packages"
  )
  gzip -kf "${dist_meta_dir}/Packages"
done

apt-ftparchive \
  -o "APT::FTPArchive::Release::Origin=${ORIGIN}" \
  -o "APT::FTPArchive::Release::Label=${LABEL}" \
  -o "APT::FTPArchive::Release::Suite=${SUITE}" \
  -o "APT::FTPArchive::Release::Codename=${CODENAME}" \
  -o "APT::FTPArchive::Release::Architectures=${ARCHES}" \
  -o "APT::FTPArchive::Release::Components=${COMPONENT}" \
  -o "APT::FTPArchive::Release::Description=${DESCRIPTION}" \
  release "${REPO_DIR}/dists/${SUITE}" > "${REPO_DIR}/dists/${SUITE}/Release"

rm -f "${REPO_DIR}/dists/${SUITE}/InRelease" "${REPO_DIR}/dists/${SUITE}/Release.gpg"

if [[ "${SIGN_APT_REPO}" == "1" ]]; then
  if [[ -z "${GPG_KEY_ID}" ]]; then
    echo "SIGN_APT_REPO=1 requires APT_GPG_KEY_ID or GPG_KEY_ID." >&2
    exit 1
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg is required to sign the APT repository." >&2
    exit 1
  fi

  gpg --batch --yes --armor --output "${PUBLIC_KEY_ASC}" --export "${GPG_KEY_ID}"
  gpg --batch --yes --output "${PUBLIC_KEY_GPG}" --export "${GPG_KEY_ID}"
  gpg --batch --yes --default-key "${GPG_KEY_ID}" --clearsign \
    --output "${REPO_DIR}/dists/${SUITE}/InRelease" "${REPO_DIR}/dists/${SUITE}/Release"
  gpg --batch --yes --default-key "${GPG_KEY_ID}" --detach-sign --armor \
    --output "${REPO_DIR}/dists/${SUITE}/Release.gpg" "${REPO_DIR}/dists/${SUITE}/Release"
fi

echo "APT repo staged at ${REPO_DIR}"
if [[ "${SIGN_APT_REPO}" == "1" ]]; then
  echo "Repository signing enabled with key: ${GPG_KEY_ID}"
  echo "Public key exported to:"
  echo "  ${PUBLIC_KEY_ASC}"
  echo "  ${PUBLIC_KEY_GPG}"
else
  echo "Repository is currently unsigned. For production use:"
  echo "  SIGN_APT_REPO=1 APT_GPG_KEY_ID=<your-key-id> ./scripts/build-apt-repo.sh"
fi
echo "Host ${REPO_DIR} over HTTPS and add a source entry such as:"
echo "deb [signed-by=/etc/apt/keyrings/bhipconfig-archive-keyring.gpg] https://your-domain.example/apt ${SUITE} ${COMPONENT}"
