# Astro Bot on KytyPS5: known problems and what worked for us

*Written 2026-11-16. Based on 128 GitHub issues about Astro Bot in
[KytyPS5/KytyPS5](https://github.com/KytyPS5/KytyPS5/issues) and [Jetsku/KytyPS5](https://github.com/Jetsku/KytyPS5/issues),
and on our own test notes. No game files, keys or firmware are provided or linked here.*

## Read this first

- **One machine.** Everything marked "worked for us" was seen on a single PC: Intel Core i5-12400F (6 cores /
  12 threads), NVIDIA RTX 3060 12 GB, 32 GB RAM, Windows 11, Astro Bot **PPSA21567 01.019.000** (EU), emulator
  **Jetsku/KytyPS5 U59 int21** (`744705e`) with our five small patches (see the end). It may not transfer to AMD
  GPUs, Linux, other game versions or other builds.
- **Evidence levels used below:**
  - **Measured**: we measured or observed it, with notes, logs or source code to back it.
  - **Plausible**: consistent with our data or with the source code, but we did not test the case in the issue.
  - **Nothing**: we have nothing reliable to add; see the linked issues.
- **Game patches are version-specific.** A patch file written for 01.007 or 01.018 does not apply to 01.019, and
  the emulator does not always say so clearly. Check the version in each patch file.
- Where an issue says "fixed in build X", we report it as the issue says; we did not re-test it.

## Our working setup (for reference)

| Item | Value |
|---|---|
| Emulator | Jetsku U59 int21 (`744705e`) + our patches 0001-0005 |
| Preset | the `u59-preset.json` shipped with int21, loaded by our launcher |
| Overrides | `KYTY_AMD_RSQRT=fast`, `KYTY_LABEL_MODE=record`, `KYTY_FSR3_FG=0`, `KYTY_CPU_RESERVE=off` |
| Command line | `--shader-validation false`, `--vblank-frequency 30`, `--game-patch <30 fps logic patch>`, 1920x1080 |
| Game patches | our "30 fps engine target" patch for 01.019 (not published here: it holds bytes of the game's code) and a shadow-range text substitution (`patches/game`); **no non-RT patch** |
| Controller | Xbox 360 pad |
| Result | playable through the levels we tested; 30 fps on most levels; about 23-25 fps on the heaviest ones (Aerial Garden, Clock Tower, Horror Time, Sky Aztec, Construction) with our `-march`/PGO build |

---

## 1. The game crashes at startup or before the main menu

Most Astro Bot reports fall here (55 issues). Several different causes produce the same generic line
`Unhandled host exception ... in src/loader/runtimeLinker.cpp:7xx`. That line is only the crash reporter; the
`--- Guest fault context ---` block printed just above it is what identifies the cause.

| What the log shows | Likely cause (from the issues) | What is known to help | Issues |
|---|---|---|---|
| `access=1 address=0x...18` or `0x...58` right after the first shaders compile (official builds, Oct. 2026) | null resource-table pointer read by the shader recompiler | official builds from `2026-10-24-8291cfe` on get past it, per the reports; the Jetsku fork also boots | [#1268](https://github.com/KytyPS5/KytyPS5/issues/1268), [#1623](https://github.com/KytyPS5/KytyPS5/issues/1623), [#1868](https://github.com/KytyPS5/KytyPS5/issues/1868), [#1511](https://github.com/KytyPS5/KytyPS5/issues/1511) |
| `unsupported family=MIMG opcode=0xe6` (Sept. 2026 builds) | ray-tracing (BVH) instruction not implemented at the time | newer builds; at the time, a "non-RT" game patch | [#544](https://github.com/KytyPS5/KytyPS5/issues/544), [#281](https://github.com/KytyPS5/KytyPS5/issues/281) |
| crash in thread `SceSndzAudioOutMain` after the logo, Intel CPU | AMD-only CPU instructions not emulated | official builds: start with `--amd-cpu` | [#687](https://github.com/KytyPS5/KytyPS5/issues/687), [#1081](https://github.com/KytyPS5/KytyPS5/issues/1081), [#2215](https://github.com/KytyPS5/KytyPS5/issues/2215) |
| `SPIR-V validation failed` (Jetsku int21) | shader validation rejects a valid shader | turn shader validation off (global settings, debug tab) | [Jetsku#77](https://github.com/Jetsku/KytyPS5/issues/77), [Jetsku#84](https://github.com/Jetsku/KytyPS5/issues/84) |
| `SPIR-V validation failed ... descriptor groups do not match` after an upgrade | `_PipelineCache` from another build | delete `_PipelineCache` | [Jetsku#23](https://github.com/Jetsku/KytyPS5/issues/23), [#1675](https://github.com/KytyPS5/KytyPS5/issues/1675) |
| `unsupported texture mip view changes physical layout` (official builds, Nov. 2026) | mip view past the image's last level | open PR [#2172](https://github.com/KytyPS5/KytyPS5/pull/2172) | [#1993](https://github.com/KytyPS5/KytyPS5/issues/1993), [#2196](https://github.com/KytyPS5/KytyPS5/issues/2196), [#2222](https://github.com/KytyPS5/KytyPS5/issues/2222) |

What worked for us:
- **Fixed (16 Nov 2026):** the buffer doubling extended to 01.019.000, patch
  [`0007-fix-astro-cb-scale-01019.patch`](../patches/kytyps5-u59/0007-fix-astro-cb-scale-01019.patch) (the table is
  searched in memory and patched only when found exactly once). No cost measured; not seen again in our test runs.
- **Measured:** Jetsku U59 int21 boots and plays 01.019 on our Intel + RTX 3060 machine.
- **Measured:** the official build `KytyPS5-2026-11-14-3e226bf`, used as released, stopped on our machine in 5 of
  the 8 levels we tried (Dirty Bath, Lava Ship, Horror Time, Sky Aztec, Construction), for example with
  `unsupported texture mip view changes physical layout` (`descriptors.cpp:611`). U59 int21 runs those levels without
  stopping, at about 19-26 fps as released and 23-30 fps with our `-march`/PGO build (static camera). We have not
  tried PR #2172.
- **Measured:** on our Intel CPU the official build needs `--amd-cpu`; U59 applies its AMD-instruction patch on its
  own (the console prints `AMD instruction patch: ...`).
- **Plausible:** we run U59 with `--shader-validation false`. We did not test with validation on, so we cannot
  say it would crash on our machine.

## 2. Black screen, black textures, or no lighting in game

Older builds did not emulate the game's ray-traced lighting; two game patches ("Select the existing non-tiled
deferred-lighting renderer", "Disable GI probes and lighting shaders") or newer builds with software ray tracing
fixed it. Issues: [#853](https://github.com/KytyPS5/KytyPS5/issues/853),
[#1011](https://github.com/KytyPS5/KytyPS5/issues/1011), [Jetsku#2](https://github.com/Jetsku/KytyPS5/issues/2),
[Jetsku#19](https://github.com/Jetsku/KytyPS5/issues/19), [Jetsku#24](https://github.com/Jetsku/KytyPS5/issues/24).

What worked for us:
- **Fixed (16 Nov 2026):** the buffer doubling extended to 01.019.000, patch
  [`0007-fix-astro-cb-scale-01019.patch`](../patches/kytyps5-u59/0007-fix-astro-cb-scale-01019.patch) (the table is
  searched in memory and patched only when found exactly once). No cost measured; not seen again in our test runs.
- **Measured:** with U59 int21 and its preset (`KYTY_RT_SOFTWARE=auto`), 01.019 renders correctly on our RTX 3060
  **without** any non-RT patch (checked on screenshots).
- **Measured:** forcing `KYTY_RT_SOFTWARE=0` gave us a black image (lighting gone) and no fps gain. We do not
  recommend it.
- **Nothing** for AMD RDNA4 black lighting ([Jetsku#8](https://github.com/Jetsku/KytyPS5/issues/8)): not tested.

## 3. Crashes during a level or while loading one

| What the log shows | Likely cause (from the issues) | What is known to help | Issues |
|---|---|---|---|
| `pc=0x00000009004a0c3e`, often in thread `Draw Geometry` / `Draw Extra Geometry` / `Draw Shadow`; sometimes `command_buffer_writer.ppr.cpp:31 ... too many objects/batches` | the game's own assertion: a draw thread's command buffer ran full after the thread fell a frame behind | U59 int21 doubles these buffers (`KYTY_ASTRO_CB_SCALE=2`) **for 01.018.000 only**; `KYTY_LABEL_MODE=completion` got one player past it (slower); one report only saw it at 3840x2160 | [Jetsku#32](https://github.com/Jetsku/KytyPS5/issues/32), [Jetsku#76](https://github.com/Jetsku/KytyPS5/issues/76), [#1993](https://github.com/KytyPS5/KytyPS5/issues/1993) |
| thread `ProductNextLoad_ATQT`, address `0xffffffffffffffff`, 2nd world or Tentacle System | a failed file mapping read during the arrival cutscene | a save from after that point; reported gone in int19 for one player | [Jetsku#34](https://github.com/Jetsku/KytyPS5/issues/34), [Jetsku#78](https://github.com/Jetsku/KytyPS5/issues/78) |
| `occlusion.cpp:405` | accurate occlusion queries | turn off "accurate texture synchronization" and "accurate occlusion queries" | [Jetsku#31](https://github.com/Jetsku/KytyPS5/issues/31) |
| `mesh draw exceeds host workgroup limits` | a mesh draw larger than the host limit | local fix mentioned in #1511; not merged at the time | [#624](https://github.com/KytyPS5/KytyPS5/issues/624) |
| crash in `amdvlk64.dll` in the loading tunnel | AMD driver crash on a pipeline | fixed in Jetsku AMD test 5 (int18.1) | [Jetsku#22](https://github.com/Jetsku/KytyPS5/issues/22) |

What worked for us:
- **Fixed (16 Nov 2026):** the buffer doubling extended to 01.019.000, patch
  [`0007-fix-astro-cb-scale-01019.patch`](../patches/kytyps5-u59/0007-fix-astro-cb-scale-01019.patch) (the table is
  searched in memory and patched only when found exactly once). No cost measured; not seen again in our test runs.
- **Measured:** we hit the `pc=0x9004a0c3e` crash twice on **01.019** (once with `KYTY_LABEL_MODE=split`, once with
  `record` on an experimental build). `KYTY_LABEL_MODE=record` therefore does not prevent it. It is rare for us,
  but we have no crash rate over long sessions.
- **Measured (source code):** in int21 the buffer doubling is gated on `APP_VER == 01.018.000`
  (`src/loader/gamePatch.cpp`), and none of our logs contains
  `Game patch: Astro Bot draw-thread command buffers x2`. **On 01.019 this protection is not active.**
- **Plausible, untested:** extending the buffer doubling to 01.019.000 should make this crash rarer for 01.019
  players. On 01.018 the doubling is active but does not always suffice (Jetsku#76).
- **Nothing** for the other rows: we did not hit them in the levels we measured.

## 4. GPU device lost, driver timeout

Issues: [#713](https://github.com/KytyPS5/KytyPS5/issues/713), [#831](https://github.com/KytyPS5/KytyPS5/issues/831),
[#879](https://github.com/KytyPS5/KytyPS5/issues/879), [#1498](https://github.com/KytyPS5/KytyPS5/issues/1498),
[#1511](https://github.com/KytyPS5/KytyPS5/issues/1511), [#2215](https://github.com/KytyPS5/KytyPS5/issues/2215),
[Jetsku#5](https://github.com/Jetsku/KytyPS5/issues/5), [Jetsku#47](https://github.com/Jetsku/KytyPS5/issues/47),
[Jetsku#71](https://github.com/Jetsku/KytyPS5/issues/71). Causes discussed there: helper lanes in EXEC (commit
5429888d upstream), LDS emulation on NVIDIA, 32-wide subgroups on Intel Arc (`INTEL_SIMD_DEBUG=cs32`), a recent AMD
driver.

What worked for us:
- **Fixed (16 Nov 2026):** the buffer doubling extended to 01.019.000, patch
  [`0007-fix-astro-cb-scale-01019.patch`](../patches/kytyps5-u59/0007-fix-astro-cb-scale-01019.patch) (the table is
  searched in memory and patched only when found exactly once). No cost measured; not seen again in our test runs.
- **Measured, limited:** our only documented device losses came from our own experiment (letting the GPU read guest
  memory directly). Jetsku#71 (RTX 3060, int20) was reported fixed in int21; we play int21 on an RTX 3060 without
  device losses in our test runs. That says nothing about other GPUs.
- **Measured:** `KYTY_DEVICE_FAULT_DIAGNOSTICS=1` distorts performance; turn it on only to file a report.

## 5. Out of video memory or RAM

Issues: [#1797](https://github.com/KytyPS5/KytyPS5/issues/1797), [#2001](https://github.com/KytyPS5/KytyPS5/issues/2001),
[Jetsku#57](https://github.com/Jetsku/KytyPS5/issues/57), [Jetsku#92](https://github.com/Jetsku/KytyPS5/issues/92)
(`ErrorOutOfDeviceMemory`, `failed to create image`, `video memory full`).

What worked for us:
- **Fixed (16 Nov 2026):** the buffer doubling extended to 01.019.000, patch
  [`0007-fix-astro-cb-scale-01019.patch`](../patches/kytyps5-u59/0007-fix-astro-cb-scale-01019.patch) (the table is
  searched in memory and patched only when found exactly once). No cost measured; not seen again in our test runs.
- **Measured:** in a level the emulator uses **11.9-13.5 GB of RAM** and about **6 GB of VRAM** on our machine.
  When another program held about 9 GB of VRAM, the emulator's Vulkan budget dropped to 5.8 GB, and with RAM nearly
  exhausted the game fell to 1.7 fps.
- **Plausible:** close programs that use VRAM (local AI models, browsers with many tabs) before playing. 8 GB cards
  and 16 GB RAM systems look tight; we have not tested them.

## 6. Low fps, or the game runs in slow motion

The game's logic follows the frame rate, so below its target it runs in slow motion
([Jetsku#80](https://github.com/Jetsku/KytyPS5/issues/80), [Jetsku#99](https://github.com/Jetsku/KytyPS5/issues/99),
[#1931](https://github.com/KytyPS5/KytyPS5/issues/1931)). Reports agree that the limit is the CPU, not the GPU
([Jetsku#99](https://github.com/Jetsku/KytyPS5/issues/99), [Jetsku#30](https://github.com/Jetsku/KytyPS5/issues/30),
[#1081](https://github.com/KytyPS5/KytyPS5/issues/1081)).

What worked for us:
- **Fixed (16 Nov 2026):** the buffer doubling extended to 01.019.000, patch
  [`0007-fix-astro-cb-scale-01019.patch`](../patches/kytyps5-u59/0007-fix-astro-cb-scale-01019.patch) (the table is
  searched in memory and patched only when found exactly once). No cost measured; not seen again in our test runs.

| Change | Effect on our machine | Evidence |
|---|---|---|
| **Intel CPUs:** `KYTY_AMD_RSQRT=fast` (our patch 0005: the AMD `VRSQRTPS` instruction emulated in single precision instead of the exact double-precision trampoline) | Big Tornado 15.6 → 29.6 fps; 7 of 24 levels at 30 fps before, 11 at 30 and 5 close to 30 after | Measured |
| Build U59 with `-march=<your CPU>` and the int21 PGO profile | +1 to +6 fps depending on the level (static camera) | Measured (consistent with Jetsku#99: +2-3 fps with a local PGO build) |
| `KYTY_DRAW_PREP_WORKERS=3` (6-core CPU) | +0.7 to +0.9 fps | Measured |
| Launch through the launcher so that `u59-preset.json` is applied | we always do; see [Jetsku#55](https://github.com/Jetsku/KytyPS5/issues/55) for a 2x difference | Plausible (no A/B on our side) |
| 01.019 only: our "30 fps engine target" game patch + `--vblank-frequency 30` | the game targets 30 fps of logic instead of 60, so at 30 fps it is not in slow motion by design; below 30 it still slows down | Setting we use; game speed not formally measured |

What did **not** help us (measured, so you can skip these):
- 1280x720 instead of 1920x1080: no gain (CPU-bound).
- Lower shadows, draw distance, LOD, shadow cascades: 1 fps or less.
- `KYTY_CPU_RESERVE=cp`: no gain; `cp+recorder`: drops to 0 fps.
- Splitting the command processor over several threads (experimental): stable but not faster.
- Page-fault and semaphore tuning, spin-waits: no gain.
- FSR 3 frame generation (`KYTY_FSR3_FG`): doubles displayed frames but lowers real ones and froze mid-game.
- We did not try Lossless Scaling (LSFG); [Jetsku#98](https://github.com/Jetsku/KytyPS5/issues/98) and
  [#2087](https://github.com/KytyPS5/KytyPS5/issues/2087) report that it slows the game.

Our diagnosis, for those who profile: on our 6-core CPU about 9 of 12 logical cores are busy; the game's main
thread computes about 82% of the time; the GPU works about 6 ms per frame.

## 7. Controllers

- **Switch Pro / 8BitDo / other mono-LED pads: fps drops, choppy sound.** The game sets the light bar every time it
  reads the pad; SDL waits for those pads to answer. Fixed upstream by
  [PR #2116](https://github.com/KytyPS5/KytyPS5/pull/2116) (official builds from `4c890e9` on). Issues:
  [#2013](https://github.com/KytyPS5/KytyPS5/issues/2013), [#1996](https://github.com/KytyPS5/KytyPS5/issues/1996),
  [Jetsku#29](https://github.com/Jetsku/KytyPS5/issues/29). **Nothing** from us: we use an Xbox pad and do not know
  whether U59 int21 has this fix.
- **No gyroscope (Xbox pad, generic pad), or gyro offset.** **Measured:** the game's own option *Options →
  Accessibility → Controller Tilt Assist = On* moves tilt sections to the left stick; we used it to free the Dual
  Speeder. A workaround for [#2126](https://github.com/KytyPS5/KytyPS5/issues/2126) and
  [Jetsku#41](https://github.com/Jetsku/KytyPS5/issues/41), not a fix.
- Adaptive triggers too strong, launcher left open with rumble stuck, DualSense disconnects during the ship rebuild
  ([Jetsku#54](https://github.com/Jetsku/KytyPS5/issues/54), [Jetsku#96](https://github.com/Jetsku/KytyPS5/issues/96),
  [Jetsku#86](https://github.com/Jetsku/KytyPS5/issues/86)): **Nothing**.

## 8. Graphics glitches and text

Water corruption with an LDS warning, visible polygon edges, grass turning black when touched, flashing distant
water, dark HDR, `???` instead of Chinese text, fonts too small
([Jetsku#16](https://github.com/Jetsku/KytyPS5/issues/16), [Jetsku#60](https://github.com/Jetsku/KytyPS5/issues/60),
[Jetsku#94](https://github.com/Jetsku/KytyPS5/issues/94), [Jetsku#90](https://github.com/Jetsku/KytyPS5/issues/90),
[Jetsku#89](https://github.com/Jetsku/KytyPS5/issues/89), [Jetsku#38](https://github.com/Jetsku/KytyPS5/issues/38),
[Jetsku#73](https://github.com/Jetsku/KytyPS5/issues/73)). **Nothing** from us: our notes do not record these on our
NVIDIA setup.

## 9. Unsupported hardware

macOS / MoltenVK, RDNA1 GPUs (no mesh shaders), Intel integrated GPUs
([#1319](https://github.com/KytyPS5/KytyPS5/issues/1319), [#1416](https://github.com/KytyPS5/KytyPS5/issues/1416),
[#2140](https://github.com/KytyPS5/KytyPS5/issues/2140)). **Nothing** to add.

---

## Our emulator patches (U59 int21)

| Patch | What it does | Why |
|---|---|---|
| 0001 | Esc leaves fullscreen | convenience |
| 0002 | `KYTY_APP0_OVERLAY` / `KYTY_APP0_SUBST`: replace or edit a game file in memory, without touching the game folder | level selection for tests, shadow-range setting |
| 0003 | Windows thread names | profiling |
| 0004 | per-render-pass timing (diagnostic, off by default) | profiling |
| 0005 | `KYTY_AMD_RSQRT=exact` (default) / `fast` / `native` | Intel CPU performance (section 6) |

## How to report a crash usefully

- Attach the whole `_kyty.txt` (or at least the `--- Guest fault context ---` block above the error), the game
  version (`APP_VER`), the exact emulator build, CPU, GPU and driver.
- For `pc=0x9004a0c3e`, U59 documents `KYTY_AGC_CB_WATERMARK=1` (see its `docs/EXPERIMENTAL.md`).
- For device losses on int21, attach `_device_fault.nv-gpudmp` if one was written.
