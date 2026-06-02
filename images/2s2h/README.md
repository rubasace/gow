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
   sudo cp "your-rom.z64" /mnt/wolf/shared/2ship2harkinian/   # Majora's Mask NTSC US recommended
   # optional: drop an already-generated mm.o2r here to skip generation entirely
   # to let the container generate + share the mm.o2r itself, make the folder writable:
   sudo chown 1000:1000 /mnt/wolf/shared/2ship2harkinian
   ```
3. Paste `wolf/config.snippet.toml` into Wolf's `config.toml` and restart Wolf. It shows up in Moonlight.
4. **First connection:** if you didn't provide an `mm.o2r`, 2S2H extracts it from the ROM and shares it
   back. This is **hands-free** — you see a brief extraction screen and an automatic restart, no clicks
   (so a Moonlight gamepad user never gets stuck on a keyboard prompt). Settings and saves go to your
   per-user home.

## Updating

Bump the image tag and rebuild. Whether the ROM is re-extracted depends on the version jump:

- **`0.0.X` / `0.X.0`** (patch / feature) → the common `mm.o2r` is reused. Just rebuild and redeploy.
- **`X.0.0`** (major) → the `mm.o2r` may be outdated; the container detects it and **regenerates it
  automatically and hands-free** from the ROM, then shares the fresh one back. You still only provide
  the `.z64`. (Needs the shared folder writable; on a read-only mount it warns instead.)

The version pin (`ARG S2H_VERSION` in the Dockerfile) is kept up to date by Renovate — see
[CONTRIBUTING](../../CONTRIBUTING.md).

## Settings and mods

- **Settings:** unlike `soh`, **no default `2ship2harkinian.json` ships yet** — the seeding is wired up
  but inert, so the first launch uses 2S2H's own defaults. To bake your own defaults: boot once,
  configure it (fullscreen, OpenGL, controller mapping…), then copy the generated `2ship2harkinian.json`
  from the home into `configs/` and commit it.
- **Mods:** drop `.o2r` / `.otr` files in `/mnt/wolf/shared/2ship2harkinian/mods/`; they're symlinked
  into each profile's `mods/` on launch (shared once, not duplicated per profile). To enable one by
  default its filename must match the enabled-mods list in the JSON; disabling is a toggle in 2S2H's
  menu, saved per-profile.

## Notes

- **No Master Quest:** Majora's Mask has a single ROM archive (`mm.o2r`), so there's no `oot-mq.o2r`
  equivalent. That's the only structural difference from `soh`'s o2r handling.
- **NVIDIA:** keep `/dev/nvidia*` in `GOW_REQUIRED_DEVICES` (already in the snippet); on Intel/AMD
  base-app's Mesa is enough.
- **Not tested end-to-end** (no Docker in the authoring environment): built against the official 4.0.2
  release, the `gow` base-app contract, and inspection of the AppImage.
- Implementation details (build stages, the hands-free extraction flow, how the `mm.o2r` is bridged in)
  live in the commented `Dockerfile` and `scripts/`.
