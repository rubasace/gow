# GOW — Games on Whales images

[![Build images](https://github.com/rubasace/gow/actions/workflows/build-images.yml/badge.svg)](https://github.com/rubasace/gow/actions/workflows/build-images.yml)

A personal collection of [Wolf](https://github.com/games-on-whales/wolf) app images — extra
[Games-on-Whales](https://github.com/games-on-whales/gow) apps to stream from a remote host through
Moonlight.

Each image is built on the Games-on-Whales [`base-app`](https://github.com/games-on-whales/gow)
contract and published to the **GitHub Container Registry (GHCR)**. The idea is to keep these ports —
which upstream `gow` doesn't ship — packaged the same way the official images are, so they drop into an
existing Wolf setup with no extra glue.

Every image has its own README explaining how to use it (linked in the table below).

## Images

| Image | What it is | GHCR | Status |
| - | - | - | - |
| [Ship of Harkinian](images/soh/README.md) | Native PC port of *The Legend of Zelda: Ocarina of Time* | `ghcr.io/rubasace/soh` | ✅ available |
| [2 Ship 2 Harkinian](images/2s2h/README.md) | Native PC port of *The Legend of Zelda: Majora's Mask* | `ghcr.io/rubasace/2s2h` | ✅ available |
| OpenGOAL | Native PC port of *Jak and Daxter* | — | 🚧 coming soon |
| EmulationStation (custom) | Front-end to launch the rest | — | 🗒️ planned |

## Tags

Each image is published under two kinds of tag (mirroring the Games-on-Whales convention):

- **`edge`** — the latest successful build of `main`.
- **`<version>`** — the exact upstream app version baked into the image (e.g. `soh:9.2.3`), so
  deployments can pin to a release and updates stay explicit.

```bash
docker pull ghcr.io/rubasace/soh:edge      # latest build of main
docker pull ghcr.io/rubasace/soh:9.2.3     # pinned to that SoH release
```

## Building & contributing

How the build pipeline works (parallel multi-image CI, image signing, version bumps via Renovate),
how to add a new image, and the one-time GHCR setup are documented in
[CONTRIBUTING.md](CONTRIBUTING.md).
