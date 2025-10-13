#!/usr/bin/env bash
set -euo pipefail

# Load shared defaults from .env but respect existing env overrides.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
USER_OUT="${OUT-}"
USER_ARCH="${ARCH-}"
USER_BUILD="${BUILD-}"
USER_PKGNAME="${PKGNAME-}"
USER_MAINTAINER="${MAINTAINER-}"
USER_IMAGE="${SLACKWARE_IMAGE-}"
USER_PLATFORM="${PLATFORM-}"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/.env"
  set +a
fi
OUT="${USER_OUT:-${OUT:-dist}}"
ARCH="${USER_ARCH:-${ARCH:-x86_64}}"
BUILD="${USER_BUILD:-${BUILD:-1_unraid}}"
PKGNAME="${USER_PKGNAME:-${PKGNAME:-stress-ng-gpu-unraid}}"
MAINTAINER="${USER_MAINTAINER:-${MAINTAINER:-you@example.com}}"
SLACKWARE_IMAGE="${USER_IMAGE:-${SLACKWARE_IMAGE:-slackware/slackware64:15.0}}"
PLATFORM="${USER_PLATFORM:-${PLATFORM:-linux/amd64}}"

cd "${ROOT_DIR}"

IN_BUNDLE=""
VER="0.0.0"
REPO_DIR=""

usage() {
  cat <<EOF
Usage: $0 --in <PATH/dist/stress-ng-gpu-glibc-bundle.tar.gz> [--ver <version>] [--out <dir>] [--repo <dir>]

Create a Slackware-style .txz package from the self-contained bundle produced by build.sh.
Packaging is performed inside the official Slackware image via 'makepkg'.

Options:
  --in         Path to the bundle tar.gz (required)
  --ver        Version string to embed in package name (default: ${VER})
  --out        Output directory for the .txz (default: ${OUT})
  --repo       Directory to receive repository metadata (PACKAGES.TXT, CHECKSUMS.md5)
  --maintainer Override maintainer string (default: ${MAINTAINER})
  --arch       Override target architecture label (default: ${ARCH})
  --build      Override build suffix (default: ${BUILD})
  --pkgname    Override package base name (default: ${PKGNAME})
  --image      Override Slackware Docker image (default: ${SLACKWARE_IMAGE})
  --platform   Override Docker platform (default: ${PLATFORM})

Environment variables with the same names also work and override .env.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in) IN_BUNDLE="$2"; shift 2;;
    --ver) VER="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --repo) REPO_DIR="$2"; shift 2;;
    --maintainer) MAINTAINER="$2"; shift 2;;
    --arch) ARCH="$2"; shift 2;;
    --build) BUILD="$2"; shift 2;;
    --pkgname) PKGNAME="$2"; shift 2;;
    --image) SLACKWARE_IMAGE="$2"; shift 2;;
    --platform) PLATFORM="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$IN_BUNDLE" || ! -f "$IN_BUNDLE" ]]; then
  echo "ERROR: --in bundle not provided or missing: $IN_BUNDLE" >&2
  exit 1
fi

mkdir -p "${OUT}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PKGROOT="${WORK}/PKGROOT"
BINDIR="${PKGROOT}/opt/stress-ng-gpu"
INSTALLDIR="${PKGROOT}/install"
TEMPLATES_DIR="${ROOT_DIR}/templates"
SLACK_DESC_TEMPLATE="${TEMPLATES_DIR}/slack-desc"
DOINST_TEMPLATE="${TEMPLATES_DIR}/doinst.sh"

if [[ ! -f "${SLACK_DESC_TEMPLATE}" ]]; then
  echo "ERROR: Missing template ${SLACK_DESC_TEMPLATE}" >&2
  exit 1
fi
if [[ ! -f "${DOINST_TEMPLATE}" ]]; then
  echo "ERROR: Missing template ${DOINST_TEMPLATE}" >&2
  exit 1
fi

mkdir -p "${BINDIR}" "${INSTALLDIR}"

echo "==> Staging package at: ${PKGROOT}"
tar -xzf "${IN_BUNDLE}" -C "${BINDIR}"

cat > "${BINDIR}/LICENSE" <<'EOF'
GNU GENERAL PUBLIC LICENSE, Version 2 (GPL-2.0)
Full text: https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
This package redistributes stress-ng (GPL-2.0). See upstream for source code:
https://github.com/ColinIanKing/stress-ng
EOF

install -m 0755 "${DOINST_TEMPLATE}" "${INSTALLDIR}/doinst.sh"

escape_sed_replacement() {
  local val="$1"
  val="${val//\\/\\\\}"
  val="${val//&/\\&}"
  val="${val//\//\\/}"
  printf '%s' "$val"
}

ESC_PKGNAME="$(escape_sed_replacement "${PKGNAME}")"
ESC_MAINTAINER="$(escape_sed_replacement "${MAINTAINER}")"
ESC_ARCH="$(escape_sed_replacement "${ARCH}")"
sed \
  -e "s/{{PKGNAME}}/${ESC_PKGNAME}/g" \
  -e "s/{{MAINTAINER}}/${ESC_MAINTAINER}/g" \
  -e "s/{{ARCH}}/${ESC_ARCH}/g" \
  "${SLACK_DESC_TEMPLATE}" > "${INSTALLDIR}/slack-desc"

PKG_FILENAME="${PKGNAME}-${VER}-${ARCH}-${BUILD}.txz"

echo "==> Running makepkg inside ${SLACKWARE_IMAGE}"
docker run --rm -t \
  --platform="${PLATFORM}" \
  -v "${WORK}:/work" \
  -w /work/PKGROOT \
  "${SLACKWARE_IMAGE}" \
  /bin/sh -c "makepkg -l y -c n /work/${PKG_FILENAME}"

PKG_PATH="${WORK}/${PKG_FILENAME}"
if [[ ! -f "${PKG_PATH}" ]]; then
  echo "ERROR: makepkg did not produce ${PKG_PATH}" >&2
  exit 1
fi

mv "${PKG_PATH}" "${OUT}/${PKG_FILENAME}"
echo "==> Created: ${OUT}/${PKG_FILENAME}"

if [[ -n "${REPO_DIR}" ]]; then
  echo "==> Building Slackware repo at: ${REPO_DIR}"
  mkdir -p "${REPO_DIR}"
  cp -v "${OUT}/${PKG_FILENAME}" "${REPO_DIR}/"

  SIZEC_K=$(du -k "${REPO_DIR}/${PKG_FILENAME}" | awk '{print $1}')
  TMPU="$(mktemp -d)"
  tar -Jxvf "${REPO_DIR}/${PKG_FILENAME}" -C "${TMPU}" >/dev/null
  SIZEU_K=$(du -sk "${TMPU}" | awk '{print $1}')
  rm -rf "${TMPU}"

  DESC_INDENTED=$(sed 's/^/  /' "${INSTALLDIR}/slack-desc")

  {
    echo "PACKAGE NAME:  ${PKG_FILENAME}"
    echo "PACKAGE LOCATION:  ."
    echo "PACKAGE SIZE (compressed):  ${SIZEC_K} K"
    echo "PACKAGE SIZE (uncompressed):  ${SIZEU_K} K"
    echo "PACKAGE DESCRIPTION:"
    echo "${DESC_INDENTED}"
    echo ""
  } >> "${REPO_DIR}/PACKAGES.TXT"

  ( cd "${REPO_DIR}" && md5sum *.txz > CHECKSUMS.md5 )

  echo "==> Repo files:"
  ls -l "${REPO_DIR}/" | sed 's/^/   /'
fi

echo "Install on Unraid (as root):"
echo "  upgradepkg --install-new ${OUT}/${PKG_FILENAME}  ||  installpkg ${OUT}/${PKG_FILENAME}"
