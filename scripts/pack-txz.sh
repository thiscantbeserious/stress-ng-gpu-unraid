#!/usr/bin/env bash
set -euo pipefail

IN_BUNDLE=""
OUT_DIR="dist"
VER="0.0.0"
ARCH="x86_64"
BUILD="1_unraid"
PKGNAME="stress-ng-gpu-unraid"
REPO_DIR=""

usage() {
  cat <<EOF
Usage: $0 --in <PATH/dist/stress-ng-gpu-glibc-bundle.tar.gz> [--ver <version>] [--out <dir>] [--repo <repo-dir>]

Create a Slackware-style .txz package from the self-contained bundle produced by build.sh.
Optionally, also generate a minimal Slackware repository (PACKAGES.TXT + CHECKSUMS.md5).

Options:
  --in       Path to the bundle tar.gz (required)
  --ver      Version string to embed in package name (default: ${VER})
  --out      Output directory for the .txz (default: ${OUT_DIR})
  --repo     Directory to receive a repo layout (will be created). When provided,
             the .txz is copied there and PACKAGES.TXT + CHECKSUMS.md5 are generated.

Output:
  <out>/${PKGNAME}-${VER}-${ARCH}-${BUILD}.txz
  (and optionally a repo at <repo>/ with PACKAGES.TXT and CHECKSUMS.md5)
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --in) IN_BUNDLE="$2"; shift 2;;
    --ver) VER="$2"; shift 2;;
    --out) OUT_DIR="$2"; shift 2;;
    --repo) REPO_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$IN_BUNDLE" || ! -f "$IN_BUNDLE" ]]; then
  echo "ERROR: --in bundle not provided or missing: $IN_BUNDLE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

WORK="$(mktemp -d)"
PKGROOT="${WORK}/PKGROOT"
BINDIR="${PKGROOT}/opt/stress-ng-gpu"
INSTALLDIR="${PKGROOT}/install"

echo "==> Staging package at: $PKGROOT"
mkdir -p "$BINDIR" "$INSTALLDIR"

# 1) Unpack the bundle into /opt/stress-ng-gpu
tar -xzf "$IN_BUNDLE" -C "$BINDIR"

# 2) License (embed GPLv2 so the package is self-contained)
cat > "${BINDIR}/LICENSE" <<'EOF'
GNU GENERAL PUBLIC LICENSE, Version 2 (GPL-2.0)
Full text: https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
This package redistributes stress-ng (GPL-2.0). See upstream for source code:
https://github.com/ColinIanKing/stress-ng
EOF

# 3) install scripts
cat > "${INSTALLDIR}/doinst.sh" <<'EOF'
#!/bin/sh
# Create or refresh a symlink so users can just run "stress-ng"
mkdir -p /usr/local/bin
ln -sfn /opt/stress-ng-gpu/stress-ng /usr/local/bin/stress-ng
EOF
chmod +x "${INSTALLDIR}/doinst.sh"

cat > "${INSTALLDIR}/slack-desc" <<'EOF'
stress-ng-gpu-unraid: stress-ng (GPU-enabled bundle for Unraid)
stress-ng-gpu-unraid:
stress-ng-gpu-unraid: Self-contained stress-ng with glibc loader + Mesa/DRM/EGL/GLES libs.
stress-ng-gpu-unraid: Installs to /opt/stress-ng-gpu and provides /usr/local/bin/stress-ng.
stress-ng-gpu-unraid:
stress-ng-gpu-unraid: Upstream: https://github.com/ColinIanKing/stress-ng (GPL-2.0)
stress-ng-gpu-unraid:
stress-ng-gpu-unraid: Packager: <you@example.com>
stress-ng-gpu-unraid:
stress-ng-gpu-unraid: Architecture: x86_64
stress-ng-gpu-unraid:
EOF

# 4) Create .txz (Slackware packages are tar.xz with this layout)
PKG="${PKGNAME}-${VER}-${ARCH}-${BUILD}.txz"
( cd "${PKGROOT}" && tar --owner=0 --group=0 -Jcvf "${PWD}/${PKG}" . ) >/dev/null

# 5) Move to out dir
mkdir -p "${OUT_DIR}"
mv "${PKGROOT}/${PKG}" "${OUT_DIR}/${PKG}"
echo "==> Created: ${OUT_DIR}/${PKG}"

# 6) Optional: create a minimal Slackware repo (copy package + generate metadata)
if [[ -n "$REPO_DIR" ]]; then
  echo "==> Building Slackware repo at: $REPO_DIR"
  mkdir -p "$REPO_DIR"
  cp -v "${OUT_DIR}/${PKG}" "$REPO_DIR/"

  # Compute sizes
  SIZEC_K=$(du -k "${REPO_DIR}/${PKG}" | awk '{print $1}')
  # Rough unpacked size: expand to temp and measure (clean up after)
  TMPU="$(mktemp -d)"
  tar -Jxvf "${REPO_DIR}/${PKG}" -C "$TMPU" >/dev/null
  SIZEU_K=$(du -sk "$TMPU" | awk '{print $1}')
  rm -rf "$TMPU"

  # Pull description (indent by two spaces per Slackware convention)
  DESC_INDENTED="  stress-ng-gpu-unraid: stress-ng (GPU-enabled bundle for Unraid)"
  if [[ -f "${INSTALLDIR}/slack-desc" ]]; then
    DESC_INDENTED=$(sed 's/^/  /' "${INSTALLDIR}/slack-desc")
  fi

  # Generate PACKAGES.TXT (append mode)
  {
    echo "PACKAGE NAME:  ${PKG}"
    echo "PACKAGE LOCATION:  ."
    echo "PACKAGE SIZE (compressed):  ${SIZEC_K} K"
    echo "PACKAGE SIZE (uncompressed):  ${SIZEU_K} K"
    echo "PACKAGE DESCRIPTION:"
    echo "${DESC_INDENTED}"
    echo ""
  } >> "${REPO_DIR}/PACKAGES.TXT"

  # Generate/update CHECKSUMS.md5
  ( cd "$REPO_DIR" && md5sum *.txz > CHECKSUMS.md5 )

  echo "==> Repo files:"
  ls -l "${REPO_DIR}/" | sed 's/^/   /'
fi
