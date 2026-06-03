# 2 Ship 2 Harkinian for Wolf (Games on Whales)

Wolf image that **packages the official Linux release** of 2 Ship 2 Harkinian — the *Majora's Mask*
PC port — with no compiling. It is the [`soh`](../soh) image with the game-specific bits swapped: the
binary is `2s2h.elf`, the baked archive is `2ship.o2r`, the ROM archive is `mm.o2r`, and there's **no
Master Quest**. State lives in three places:

- **the binary** is baked into the image, matched to the version;
- **settings and saves** stay **per-user** in the home Wolf auto-mounts;
- **the ROM** and the derived **`mm.o2r`** live in a **shared folder** you manage on the host.

Updating is just bumping the image tag and rebuilding — saves are untouched and the ROM isn't
re-extracted, except on a major version jump (handled automatically, see [Updating](#updating)).

## Where things live

| Lives in | What | Persistence |
| - | - | - |
| **Image** (`/opt/2s2h`, read-only) | `2s2h.elf` + libs + `2ship.o2r` + `assets` | ships with the release |
| **Wolf home** (`/home/retro`, auto) | `2ship2harkinian.json`, `Save/`, `mods/` | **per-user** (Wolf mounts it per profile) |
| **Shared** (`/mnt/wolf/shared/2ship2harkinian` → `/roms`) | ROM `.z64`, common `mm.o2r`, `mods/` | **shared** across profiles, you manage it |

You only ever provide the **ROM `.z64`**. The `mm.o2r` is derived from it — either drop one in the
shared folder yourself (e.g. the one from your Windows setup) or let the container generate it on first
launch.

## Usage

1. **Build** on the Wolf host (so the image stays local — Wolf launches containers through the host's
   docker socket), from this folder:
   ```bash
   docker build -t 2s2h:wolf .
   # pin a version: docker build --build-arg S2H_VERSION=4.0.2 -t 2s2h:wolf .
   ```
2. **Shared folder + ROM** on the host:
   ```bash
   sudo mkdir -p /mnt/wolf/shared/2ship2harkinian
   sudo cp "your-rom.z64" /mnt/wolf/shared/2ship2harkinian/   # MUST be NTSC-U (see Supported ROMs)
   # optional: drop an already-generated mm.o2r here to skip generation entirely
   # to let the container generate + share the mm.o2r itself, make the folder writable:
   sudo chown 1000:1000 /mnt/wolf/shared/2ship2harkinian
   ```
3. Paste `wolf/config.snippet.toml` into Wolf's `config.toml` and restart Wolf. It shows up in Moonlight.
4. **First connection:** if you didn't provide an `mm.o2r`, the container builds it from the ROM and
   shares it back. This is **hands-free** — it does NOT use 2S2H's in-app extractor (which is gated
   behind blocking SDL dialogs and a file picker a gamepad can't dismiss); instead it runs the bundled
   **ZAPD** asset processor directly (`assets/extractor/ZAPD.out`, the exact invocation 2S2H uses
   internally). You see the desktop for a moment while it extracts, then the game starts. Settings and
   saves go to your per-user home.

## Supported ROMs

2S2H accepts **only NTSC-U** dumps (from upstream's [`supportedHashes.json`](https://github.com/HarbourMasters/2ship2harkinian/blob/master/docs/supportedHashes.json)):

| Version | sha1 |
| - | - |
| **NTSC-U 1.0** (N64) | `d6133ace5afaa0882cf214cf88daba39e266c078` |
| **NTSC-U GC** | `9743aa026e9269b339eb0e3044cd5830a440c1fd` |

**PAL/Europe and JP ROMs are not supported** and extraction will fail on them — there's no PAL/JP
config in the extractor. Verify your dump at <https://2ship.equipment/>. ZAPD's output streams to the
container logs; if extraction fails the container logs the error and **exits** (no silent hang on a GUI
prompt) — fix the ROM and reconnect.

## Updating

Bump the image tag and rebuild. Whether the ROM is re-extracted depends on the version jump:

- **`0.0.X` / `0.X.0`** (patch / feature) → the common `mm.o2r` is reused. Just rebuild and redeploy.
- **`X.0.0`** (major) → the `mm.o2r` may be outdated; the container detects it and **regenerates it
  automatically and hands-free** from the ROM, then shares the fresh one back. You still only provide
  the `.z64`. (Needs the shared folder writable; on a read-only mount it warns instead.)

The version pin (`ARG S2H_VERSION` in the Dockerfile) is kept up to date by Renovate — see
[CONTRIBUTING](../../CONTRIBUTING.md).

## Settings and mods

- **Settings:** the image ships a default `2ship2harkinian.json` (fullscreen, match refresh rate,
  OpenGL, a pre-mapped controller), seeded into a profile **only on first launch**. After that the
  user's own changes persist per-profile.
- **Mods:** drop `.o2r` / `.otr` files in `/mnt/wolf/shared/2ship2harkinian/mods/`; they're symlinked
  into each profile's `mods/` on launch (shared once, not duplicated per profile). To enable one by
  default its filename must match the enabled-mods list in the JSON; disabling is a toggle in 2S2H's
  menu, saved per-profile.

## Notes

- **No Master Quest:** Majora's Mask has a single ROM archive (`mm.o2r`), so there's no `oot-mq.o2r`
  equivalent.
- **Extraction differs from `soh`:** SoH can extract by passing the ROM as an argument; 2S2H 4.0.2
  removed that path (it only has a GUI extractor gated behind blocking dialogs + a file picker), so
  this image generates `mm.o2r` itself by invoking the bundled ZAPD CLI headlessly instead.
- **NVIDIA:** keep `/dev/nvidia*` in `GOW_REQUIRED_DEVICES` (already in the snippet); on Intel/AMD
  base-app's Mesa is enough.
- **Not tested end-to-end** (no Docker in the authoring environment): built against the official 4.0.2
  release, the `gow` base-app contract, and inspection of the AppImage.
- Implementation details (build stages, the hands-free extraction flow, how the `mm.o2r` is bridged in)
  live in the commented `Dockerfile` and `scripts/`.
