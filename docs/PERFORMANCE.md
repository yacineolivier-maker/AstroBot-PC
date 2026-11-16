# What limits ASTRO BOT's frame rate on KytyPS5 (Intel i5-12400F + RTX 3060)

These are notes from about a week of measurements on the heavy levels, mostly Aerial Garden. They are meant to save
other people the dead ends. Each result is an A/B comparison between runs, alternated and repeated at least twice.
The game window was captured at the same moment of each run, so it is known that every run showed the same view.

## How it was measured

- `tools/mesure-courte.ps1` launches a level and waits until it is really loaded: the loading screen itself holds 30
  fps, so a run that never leaves it is cancelled. It then moves Astro for 120 s with `tools/pilote.ps1`, which sends
  keys to the game window only, and reads the emulator's per-second fps log.
- Moving matters. With side steps, the camera turned towards a lighter view and inflated the fps by up to 4. Even
  plain forward and back drifted between runs (end of the path or the railing, a 5 fps difference). The final route
  backs Astro into the island's railing first, then repeats 2 s forward and 2.6 s back, so every run ends in the same
  spot.
- Before comparing anything, check that nothing else is using the disk. A backup verification on the same drive made
  the level take 4 times longer to load, and an early version of the script ended up measuring the loading screen.

## Diagnosis

- **The game's main thread sets the pace.** A wait graph of the guest threads (`KYTY_WAIT_GRAPH=1`, branch
  `diag/wait-graph`) shows that in Aerial Garden `MainThread` only waits about 8 ms per frame (18 % of the time). It is
  busy for the remaining 82 %, at 22 to 24 fps.
- The GPU is not the limit (it is far from fully used). The CPU as a whole is busy (9 to 10 of 12 logical cores), but
  freeing CPU elsewhere did not help: see below.
- A frame-path probe (`KYTY_FRAME_PATH=1`) showed that the game never blocks on the command processor
  (`AgcSuspendPoint` waits at 0). The 18 to 20 ms of submission queue time is the normal frame pacing.

## Tried, no gain (all measured while moving, from the same spot)

| Change | Result |
|---|---|
| Parallel command-list translation (`KYTY_CP_PAR=2b`, several lanes) | Stable after several fixes, but not faster |
| 720p instead of 1080p | No gain (the limit is not the GPU) |
| Reserving cores for the emulator threads (`KYTY_CPU_RESERVE`) | Same or worse |
| Shorter busy-wait spins in the emulator threads (sequencer, draw prep, recorder) | Within noise |
| Write-fault handling: lock split per page range (`KYTY_PAGE_HOST_LOCK_SLICES=4`) | Fault handler time cut from about 36 to 17 ms per frame, summed over threads, **with no fps gain** (21.0 and 22.5 against 23.9 and 24.4) |
| Write-fault handling: smaller read-ahead window (`KYTY_FAULT_AHEAD_ADAPT=256`) | Within noise |
| "Hot pages" kept writable and compared with a shadow copy | About 11 fps (the comparisons cost far more) |
| Lighter guest kernel semaphores (`KYTY_GUEST_SEMA_LIGHT`) | Within noise |
| Busy-wait before blocking on guest kernel semaphores (`KYTY_GUEST_SEMA_SPIN_US=30`) | Works as intended (95 % of waits served without a sleep), but +0.6 fps only, within noise |
| Shadow distance, LOD and cascade cuts | 1 fps or less (one mild shadow-distance cut is kept, see `patches/game`) |
| FSR 3 frame generation | Fewer computed frames, then a freeze |

Two facts stand out. The main thread exchanges about 1,300 semaphore round trips per frame with another game thread
(`SystemWakeup`), each about 4 µs. The game's threads also take about 135 write faults per frame on GPU-tracked
memory. Both look expensive. Yet making either much cheaper did not raise the frame rate, so neither is on the
critical path of a frame.

## What helped

- `KYTY_AMD_RSQRT=fast` on Intel CPUs (up to about 2x on some levels, see [STATUS.md](STATUS.md)).
- `KYTY_DRAW_PREP_WORKERS=3`: about +0.8 fps.
- A CPU-tuned build (`-march=alderlake` plus profile-guided optimisation): a few percent.

## Next step

Profile where `MainThread`'s busy time goes: the game's own code, or emulator code running on that thread (HLE calls,
trapped instructions). The sampler in `tools/sampler` (`echantillonneur.exe <pid> <thread name> <seconds> 1 <out>`)
gives symbolised stacks for emulator frames. Game frames appear as raw addresses.
