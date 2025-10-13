#!/usr/bin/env bash
set -euo pipefail

# Load shared defaults from .env (project root), but let env vars override.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
USER_REF="${REF-}"
USER_OUT="${OUT-}"
USER_PLATFORM="${PLATFORM-}"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ROOT_DIR}/.env"
  set +a
fi
REF="${USER_REF:-${REF:-master}}"
OUT="${USER_OUT:-${OUT:-dist}}"
PLATFORM="${USER_PLATFORM:-${PLATFORM:-linux/amd64}}"

cd "${ROOT_DIR}"

usage() {
  cat <<EOF
Usage: $0 [--ref <tag|branch|sha>] [--out <dir>] [--platform <docker-platform>]

Build a GPU-enabled, glibc-dynamic stress-ng bundle using docker run (no Compose/BuildKit).
Artifacts are written to <out>/ as:
  - stress-ng-gpu-glibc-bundle.tar.gz  (binary + loader + libs)
  - stress-ng                           (convenience copy of the binary)

Defaults:
  --ref       ${REF}
  --out       ${OUT}
  --platform  ${PLATFORM}

Examples:
  $0
  $0 --ref v0.19.05
  $0 --platform linux/amd64 --out dist
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --platform) PLATFORM="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

mkdir -p "${OUT}"

echo "==> Building stress-ng (ref=${REF}) for platform ${PLATFORM}"
echo "==> Output directory: ${OUT}"

docker run --rm -t \
  --platform="${PLATFORM}" \
  -e STRESS_NG_REF="${REF}" \
  -v "$(pwd)/${OUT}:/out" \
  debian:bookworm bash -exc '
    set -euo pipefail
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates curl build-essential git pkg-config patchelf file \
      libdrm-dev libgbm-dev libegl1-mesa-dev libgles2-mesa-dev
    update-ca-certificates

    echo "==> Fetching stress-ng sources: ${STRESS_NG_REF}"
    mkdir -p /src
    curl -L -o /tmp/stress-ng.tar.gz \
      "https://github.com/ColinIanKing/stress-ng/archive/refs/heads/${STRESS_NG_REF}.tar.gz" || {
        echo "Ref ${STRESS_NG_REF} not found as a branch; trying tags..."
        curl -L -o /tmp/stress-ng.tar.gz \
          "https://github.com/ColinIanKing/stress-ng/archive/refs/tags/${STRESS_NG_REF}.tar.gz"
      }
    tar -xzf /tmp/stress-ng.tar.gz -C /src --strip-components=1

    echo "==> Building (dynamic glibc, GPU enabled)"
    cd /src && make clean && make -j"$(nproc)"
    /src/stress-ng --version || true

    echo "==> Bundling loader + libs"
    mkdir -p /bundle/lib /out
    cp -v /src/stress-ng /bundle/stress-ng

    # Copy amd64 glibc loader
    if [ -f /lib64/ld-linux-x86-64.so.2 ]; then
      cp -v /lib64/ld-linux-x86-64.so.2 /bundle/ld-linux-x86-64.so.2
    elif [ -f /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 ]; then
      cp -v /lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 /bundle/ld-linux-x86-64.so.2
    else
      echo "ERROR: x86_64 loader not found. Did you build with --platform=linux/amd64?" >&2
      exit 1
    fi

    # Flatten dependencies into /bundle/lib
    libs=$(ldd /bundle/stress-ng | awk "/=>/ {print \$3} /^[[:space:]]*\\// {print \$1}" | sort -u)
    for so in $libs; do
      [ -f "$so" ] || continue
      real=$(readlink -f "$so")
      base=$(basename "$real")
      cp -v "$real" "/bundle/lib/$base" || true
      # create a SONAME symlink if needed
      soname=$(basename "$so")
      if [ "$soname" != "$base" ]; then ln -sfn "$base" "/bundle/lib/$soname" || true; fi
    done

    # Ensure Mesa/DRM libs are present (and their SONAMEs)
    for extra in \
      /usr/lib/x86_64-linux-gnu/libgbm.so.1 \
      /usr/lib/x86_64-linux-gnu/libEGL.so.1 \
      /usr/lib/x86_64-linux-gnu/libGLESv2.so.2 \
      /usr/lib/x86_64-linux-gnu/libdrm.so.2 \
      /usr/lib/x86_64-linux-gnu/libGLdispatch.so.0 \
      /usr/lib/x86_64-linux-gnu/libexpat.so.1 \
      /usr/lib/x86_64-linux-gnu/libffi.so.8 \
      /usr/lib/x86_64-linux-gnu/libwayland-server.so.0 \
    ; do
      if [ -f "$extra" ]; then
        real=$(readlink -f "$extra")
        base=$(basename "$real")
        cp -vn "$real" "/bundle/lib/$base" || true
        ln -sfn "$base" "/bundle/lib/$(basename "$extra")" || true
      fi
    done

    echo "==> Patching interpreter + RPATH"
    patchelf --set-interpreter \$ORIGIN/ld-linux-x86-64.so.2 /bundle/stress-ng
    patchelf --set-rpath       \$ORIGIN/lib                 /bundle/stress-ng
    strip -s /bundle/stress-ng || true

    echo "==> Packaging"
    tar -C /bundle -czf /out/stress-ng-gpu-glibc-bundle.tar.gz .
    cp -v /bundle/stress-ng /out/stress-ng

    echo "==> Done. Artifacts written to /out"
  '

echo ""
echo "Artifacts are in ${OUT}/"
ls -l "${OUT}"
