# ASTRO BOT on KytyPS5: status on one Windows PC

A game status report, written in the spirit of KytyPS5's "Game Emulation Status Report", but kept in this repository.
Every figure below was measured on the machine described here. Your results will differ, especially with another
CPU.

## Setup

| Item | Value |
|---|---|
| Game | ASTRO BOT, PPSA21567, **European release 1.019**, your own decrypted dump (`eboot.bin`, `sce_sys`, `sce_module`, `data`) |
| Emulator | [Jetsku/KytyPS5](https://github.com/Jetsku/KytyPS5) at `744705ee` ("Release notes: int21", 24 Oct 2026, the "U59" build), plus the five patches in [`patches/kytyps5-u59`](../patches/kytyps5-u59) |
| CPU / GPU / RAM | Intel Core i5-12400F (6 cores, 12 threads) / NVIDIA RTX 3060 12 GB / 32 GB |
| OS | Windows 11 Pro |
| Output | 1080p, frame pacing at 30 (`--vblank-frequency 30`), Xbox controller (XInput) |
| Emulator settings | Jetsku's `tools/u59-preset.json`, plus `KYTY_AMD_RSQRT=fast`, `KYTY_LABEL_MODE=record`, `KYTY_FSR3_FG=0`, `KYTY_CPU_RESERVE=off`, and the shadow-distance substitution [`patches/game/ombres-allegees.txt`](../patches/game/ombres-allegees.txt) through `KYTY_APP0_SUBST` |

## What works

- Boots, menus, hub (Crashsite) and every main level that was tried. Each of the 24 main levels was loaded directly
  and played for its first 45 seconds or more. The owner plays it with an Xbox controller.
- Stable in general: dozens of automated launches in a row closed cleanly. Over all our testing, the known in-level
  crash at `pc=0x9004a0c3e` (the game's own command-buffer check) happened twice. See
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
- Optional: A/B/X/Y button prompts in place of the PlayStation symbols (`tools/xbox-icons`, through the
  `KYTY_APP0_OVERLAY` patch).

## Frame rate (1080p, target 30)

Measured on 12 Nov 2026 over 45 to 60 seconds after each level start, with the camera mostly still:

- **At 30 (or 29.5 and above with short dips)**: Crashsite hub, Snowy Canyon, Casino, Gulliver, Treasure Cave, Giants
  Garden, Atlantis, Day and Night, Iceberg, Final Shooting, Final Stage, Pirate Island, Monster Cave, Hourglass, Big
  Tornado, Space Station.
- **Below 30**: Mana Tree (about 28.7), Construction (about 27.4), Sky Aztec (about 26.9), Horror Time (about 24.8),
  Lava Ship (about 23.7), Aerial Garden (about 23.4), Clock Tower (about 23.3), Dirty Bath (about 23.3).

The worst case was measured on 16 Nov while Astro moved, from a fixed spot facing the whole island in Aerial Garden:
**23 to 24 fps**, with the 5 % lows around 20 to 22.

## Settings that mattered

- **`KYTY_AMD_RSQRT=fast` on Intel CPUs.** The game uses AMD-specific behaviour of the `rsqrt` instructions. With
  exact emulation, some levels collapse on an Intel CPU: Big Tornado ran at 15.6 fps with the exact mode and 29.6 with
  `fast`. The patch is [`0005-amd-rsqrt-modes.patch`](../patches/kytyps5-u59/0005-amd-rsqrt-modes.patch).
- **`KYTY_FSR3_FG=0`.** FSR 3 frame generation doubled the displayed frames but lowered the computed ones (13 to 17
  fps) and **froze in the middle of a level**. Keep it off.
- **`KYTY_DRAW_PREP_WORKERS=3`** (in the experimental branches): about +0.8 fps in the heavy levels.

## Other builds tried on this PC

- The official KytyPS5 release `2026-11-14-3e226bf` (unmodified, `--amd-cpu`), tried on 14 Nov 2026 with the camera
  still: the hub averaged 22.5 fps with freezes. Aerial Garden ran at 3 fps and Clock Tower at 12. Dirty Bath, Lava
  Ship, Horror Time, Sky Aztec and Construction stopped the emulator; Dirty Bath, for example, stopped with
  "unsupported texture mip view changes physical layout" (`descriptors.cpp:611`). Upstream moves fast, so this may
  already be different.

## Known problems

- The heavy levels listed above stay under 30 on this CPU. See [PERFORMANCE.md](PERFORMANCE.md) for what limits them.
- The first start of each level is slow (about a minute) while shaders and pipelines are built. Later starts reuse
  the cache.
- Not checked: DualSense-specific features (touchpad, gyro, speaker, microphone are mapped or off), every secret
  level, the whole story in one go.
