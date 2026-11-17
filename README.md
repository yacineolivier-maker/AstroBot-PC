# ASTRO BOT on PC (KytyPS5)

Tools, patches and notes to play **ASTRO BOT** (PS5, PPSA21567, European release 1.019) on Windows with the
[KytyPS5](https://github.com/KytyPS5/KytyPS5) emulator, and to measure and improve its performance.

*Version française plus bas.*

> [!IMPORTANT]
> This repository contains **no game data, no game code, no keys and no firmware**. You need your own legally
> obtained, decrypted copy of the game. Nothing here downloads or unpacks the game for you.

## What is here

| Folder | Contents |
|---|---|
| [`docs/STATUS.md`](docs/STATUS.md) | What works, frame rate per level, the settings that mattered, problems seen |
| [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) | What limits the frame rate on an Intel + RTX PC, and the dead ends, measured |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Known ASTRO BOT problems reported by the community, and what worked for us |
| [`patches/kytyps5-u59`](patches/kytyps5-u59) | Eight patches for [Jetsku/KytyPS5](https://github.com/Jetsku/KytyPS5) `744705ee` (U59), to apply in order: Esc leaves full screen, `/app0` overlay and text substitutions, Windows thread names, render-pass statistics, **AMD `rsqrt` modes on Intel CPUs**, **SRW host mutexes (+1.7 fps)**, **fix of the 1.019 `pc=0x9004a0c3e` crash**, a descriptor reuse fix (not measured yet) |
| [`patches/game`](patches/game) | Substitution rules for `KYTY_APP0_SUBST` (shadow range 20; lighter graphics, +1 to +3 fps; an experimental extension); they only change text in memory, never the game files |
| [`launcher`](launcher) | `AstroBot.exe` launcher (C#): settings file, controller mapping, environment variables, per-second fps log |
| [`tools`](tools) | Measurement scripts (PowerShell): level run with automatic movement, per-thread CPU load, stack sampler (C++), A/B/X/Y button icon generator (Python), report of the frame-drop journal `KYTY_FLUIDITE` (Python, `fluidite-bilan.py`) |

The emulator branches live in two forks (no pull request was opened upstream):

- [yacineolivier-maker/KytyPS5-Jetsku-AstroBot](https://github.com/yacineolivier-maker/KytyPS5-Jetsku-AstroBot):
  - `astrobot-pc`, the playable setup ;
  - one branch per fix ;
  - `astrobot-experiments`, every experiment, all switches off by default.
- [yacineolivier-maker/KytyPS5](https://github.com/yacineolivier-maker/KytyPS5): the fixes that still apply, ported to
  the official code of 16 Nov 2026 (Esc and full screen, `/app0` overlay and substitutions, Windows thread names, AMD
  `rsqrt` on Intel, wait graph). They are build-checked only, not tested in game on that base. The targeted semaphore
  wake-up is already upstream.

Each fork lists its branches, and what was tested, in `ASTROBOT-BRANCHES.md` on its `astrobot-notes` branch.

## Layout expected by the launcher and tools

```
<root>\
  Jeu\AstroBot.exe            launcher (built from launcher\)
  Jeu\AstroBot.json           settings, created on first start
  Jeu\KytyPS5_U59\            emulator build (kyty_emulator.exe, u59-preset.json)
  Rom\PPSA21567-1.019\        your decrypted game dump
  Developpement\outils\       the scripts from tools\
  Outils_Claude\work\         temporary files
```

`<root>` is the folder above `Jeu`. You can also set it with the `ASTROBOT_ROOT` environment variable. The folder
names are French because the project is French. Script comments are in French too.

## Building

- Emulator: follow KytyPS5's own build instructions on the `astrobot-pc` branch, or apply the patches to Jetsku's
  `744705ee`.
- Launcher: `launcher\build.cmd` (uses the C# compiler that ships with Windows).
- Sampler: `tools\sampler\build.cmd` from a Visual Studio developer prompt.

## Credits and licence

- KytyPS5 by its authors (GPL-2.0-only). The U59 build is by Jetsku. The patches here are derived works under the
  same licence. This repository is licensed **GPL-2.0-only** (see `LICENSE` and `THIRD_PARTY.md`).
- Prepared with AI assistance (Claude, by Anthropic). The repository owner decided what to publish, and the results
  come from tests run on his PC.
- ASTRO BOT is a trademark of Sony Interactive Entertainment. This project is not affiliated with Sony or with the
  KytyPS5 team.

---

## Version française

Outils, correctifs et notes pour jouer à **ASTRO BOT** (PS5, version européenne 1.019) sur Windows avec l'émulateur
KytyPS5, et pour en mesurer et améliorer les performances.

**Aucune donnée ni aucun code du jeu, aucune clé, aucun firmware.** Il faut votre propre copie du jeu, obtenue
légalement et déchiffrée.

- **État du jeu**, niveau par niveau : `docs/STATUS.md`. En bref : jouable, stable, 30 i/s sur la plupart des niveaux
  et 23 à 28 sur les huit plus lourds, sur un i5-12400F avec une RTX 3060.
- **Ce qui limite les performances**, et les pistes essayées sans gain : `docs/PERFORMANCE.md`.
- **Problèmes connus** signalés par la communauté, et ce qui a marché chez nous : `docs/TROUBLESHOOTING.md`.
- **Correctifs de l'émulateur** : `patches/kytyps5-u59` et les deux forks cités plus haut. Aucune demande de fusion
  n'a été ouverte vers les dépôts d'origine.
- **Réglage clé sur processeur Intel** : `KYTY_AMD_RSQRT=fast`, jusqu'à deux fois plus d'images par seconde sur
  certains niveaux.
- **Depuis le 17/11** : verrous SRW (`0006`, environ +1,7 i/s), correctif du plantage `pc=0x9004a0c3e` en 1.019
  (`0007`), réglages graphiques allégés (`patches/game/graphics-light.txt`, +1 à +3 i/s) ; expériences non encore
  mesurées dans la branche `astrobot-experiments` du fork Jetsku.

Préparé avec l'aide d'une IA (Claude) ; essais réalisés sur le PC du propriétaire du dépôt.
