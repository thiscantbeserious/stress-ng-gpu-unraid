# stress-ng-gpu-unraid

A reproducible build environment for producing a **GPU-enabled `stress-ng` binary bundle** for **Unraid** — using a simple `docker run` flow (no Docker Compose/BuildKit).
The bundle includes the binary, the glibc loader, and all required `.so` libraries (EGL, GBM, GLES, DRM, etc.) in a flat `lib/` folder.

# 20.10.2025: On Hold due to CUDA being a ...

After getting this to work with Mesa I noticed that no matter what I do getting this to work with CUDA is litterally a nightmare. I have tried several different ways and in the end decided. 

---

## 🧰 Prerequisites

- Docker
- Internet access to fetch sources and base images
- `make` (or you execute the scripts yourself in `./scripts`)

---

## 🚀 Quick Start (Everything via `make`)

```bash
# Build artifacts
make

# Package a Slackware .txz for un-get
make pack REF=v0.19.05

# Build + create a minimal repo (PACKAGES.TXT + CHECKSUMS.md5) in ./repo
make repo REF=v0.19.05
```

The Makefile calls scripts in `./scripts/`:
- `scripts/build.sh` → builds the binary bundle into `./dist`
- `scripts/pack-txz.sh` → creates `.txz` and (optionally) repo metadata

Artifacts appear in `./dist/`:
```
dist/
├─ stress-ng-gpu-glibc-bundle.tar.gz   # bundle (binary + loader + libs)
└─ stress-ng                           # convenience copy of the binary
```

You can pass variables:
```bash
make REF=v0.19.05
make OUT=outdir
make PLATFORM=linux/amd64
make REPO=myrepo
```

First-time setup? Pull the required Docker images up front:

```bash
make ensure-images
```

---

## ⚙️ Configuration Variables

All baseline settings live in `.env`. The Makefile and helper scripts load this file automatically, so it acts as the single source of truth for values such as `REF`, `OUT`, `PLATFORM`, and packaging metadata. 

### Key entries in `.env`:
| Name | Description |
| --- | --- |
| `REF` | Default stress-ng ref (branch/tag/sha) fetched inside the build container. |
| `OUT` | Output directory for bundle artifacts and packages. |
| `PLATFORM` | Docker platform passed to `docker run` (e.g. `linux/amd64`). |
| `REPO` | Target directory for generated Slackware repo metadata. |
| `ARCH` | Architecture label embedded in the Slackware package filename. |
| `BUILD` | Build suffix appended to the Slackware package filename. |
| `PKGNAME` | Base name for the Slackware package. |
| `MAINTAINER` | Packager contact injected into the rendered `slack-desc`. |
| `SLACKWARE_IMAGE` | Docker image used to run Slackware’s `makepkg` when packaging. |
| `BUILD_IMAGE` | Docker image used by `scripts/build.sh` for compiling the bundle. |

#### Overriding Examples
```bash
#OVERRIDE REF
make REF=v0.19.05

#OVERRIDE OUT
OUT=custom scripts/build.sh

#OVERRIDE out and dist
./scripts/pack-txz.sh --out custom-dist --in dist/stress-ng-gpu-glibc-bundle.tar.gz
```


Command-line flags always win over environment variables, which in turn override `.env`.

---

## 🧪 Use on Unraid (Host, no Docker needed)

Copy to your server and extract:

```bash
scp dist/stress-ng-gpu-glibc-bundle.tar.gz root@UNRAID:/boot/
ssh root@UNRAID
mkdir -p /boot/stress-ng-gpu 
tar -C /boot/stress-ng-gpu -xzf /boot/stress-ng-gpu-glibc-bundle.tar.gz
cd /boot/stress-ng-gpu
./stress-ng --version 
ls -l /dev/dri/renderD* || true
```

Run a GPU test (Intel/AMD via DRM/GBM/EGL):

```bash
ssh root@UNRAID
cd /boot/stress-ng-gpu
./stress-ng --gpu 1\ 
            --gpu-devnode /dev/dri/renderD128\               
            --gpu-frag 500\
            --gpu-tex-size 4096\
            --gpu-upload 1\
            --timeout 5m\
            --metrics
```

> NVIDIA proprietary driver stacks typically do not expose a GBM/EGL path compatible with `--gpu`; use compute-specific tools (CUDA/OpenCL) in that case.

---

## 🧭 Platform Notes

Unraid is x86_64, so the default target is `linux/amd64`.
If you need a different target for testing, adjust:
```bash
make PLATFORM=linux/amd64   # default
```

On Apple Silicon, Docker will emulate amd64 when you pass `--platform linux/amd64` (handled by `scripts/build.sh`).

---

## 📦 Slackware .txz (for un-get) & Repos

Create a package:
```bash
make pack REF=v0.19.05
```

Build a tiny repo (for un-get) in `./repo/`:
```bash
make repo REF=v0.19.05
# repo/
# ├─ stress-ng-gpu-unraid-v0.19.05-x86_64-1_unraid.txz
# ├─ PACKAGES.TXT
# └─ CHECKSUMS.md5
```

You can host this folder on any static site (GitHub Pages / raw URLs) and add it to un-get sources.

---

## 📜 License & Credits

- This project bundles binaries of [stress-ng](https://github.com/ColinIanKing/stress-ng), licensed under the **GNU General Public License v2 (GPL-2.0)**.  
- If you distribute these binaries, include the GPLv2 license and provide the corresponding source on request (or link to upstream if unmodified).  
- See [LICENSE](LICENSE) for the full text.
