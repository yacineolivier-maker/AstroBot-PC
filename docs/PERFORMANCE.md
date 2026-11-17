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
- **Most of that "busy" time is disguised waiting** (sampling profiler `KYTY_MAIN_CPU_SAMPLER=1`, 16 Nov): per frame
  the game's own code takes about 16 to 18 ms; the rest is the game's task-scheduler wait loop (yield and pause),
  blocking waits on a game semaphore and on a timed condition, Windows time in lock release and thread wake-ups
  (about 4 ms), and the guest libc (about 4 ms). Write faults cost the main thread only 0.1 to 0.2 ms per frame.
  The real cadence floats between 40 and 67 ms per frame rather than showing isolated spikes.
- **Bimodal runs**: with identical settings, a run gives about 20 fps or about 24.8 fps; in the slow mode the whole
  main thread is about 10 % slower at the same CPU clock. Suspected cause: thread placement on SMT siblings (the
  emulator sets no ideal processor for its heavy threads). An experimental fix is in `astrobot-experiments`
  (`KYTY_IDEAL_LAYOUT=1`, with `KYTY_THREAD_LAYOUT_LOG=1` to log it), not measured yet.
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
| A whole physical core reserved for the game's main thread (`KYTY_MAIN_THREAD_CORE`) | Worse (22.7 against 23.7, lower 5 % low) |
| Main-thread / command-processor / service thread priorities | Within noise (+0.5 fps at most) |
| Yield of the main thread replaced by a short spin (`KYTY_MAIN_YIELD_SPIN`) | The yield time becomes wait time: 23.9 against 24.8 |
| Progressive sleep for guest threads that yield in bursts (`KYTY_GUEST_YIELD_BACKOFF=8,200`) | Neutral on average; kept, no cost |
| Guest `usleep` calls | Negligible (at most 0.1 ms per frame) |

Two facts stand out. The main thread exchanges about 1,300 semaphore round trips per frame with another game thread
(`SystemWakeup`), each about 4 µs. The game's threads also take about 135 write faults per frame on GPU-tracked
memory. Both look expensive. Yet making either much cheaper did not raise the frame rate, so neither is on the
critical path of a frame.

## What helped

- `KYTY_AMD_RSQRT=fast` on Intel CPUs (up to about 2x on some levels, see [STATUS.md](STATUS.md)).
- `KYTY_DRAW_PREP_WORKERS=3`: about +0.8 fps.
- `KYTY_HOST_MUTEX_SRW=1` (branch `perf/host-mutex-srw`, patch `0006`): emulator mutexes on SRW locks. **About +1.7
  fps and a much better 5 % low** (22 against 16 to 20), 3 alternating pairs out of 3, identical captures.
- Lighter graphics rules (`patches/game/graphics-light.txt`): LOD x0.35, draw distance 300 m, shorter reflections,
  shadow range 20. About +1 to +3 fps on Aerial Garden (5 % low 20 instead of 15 to 19); the image was checked by
  eye and judged unchanged. The GPU stays 58 to 72 % busy.
- Crash of the EU 1.019 build at guest pc +0x4a0c3e: fixed by extending `KYTY_ASTRO_CB_SCALE` (patch `0007`).
- A CPU-tuned build (`-march=alderlake` plus profile-guided optimisation): a few percent.

## Next step

Experiments of 17 Nov 2026, coded after a static audit and **not measured yet** (all off by default, branch
`astrobot-experiments` of the Jetsku fork; see `ASTROBOT-BRANCHES.md` there):

- guest semaphores: direct hand-off of the signal, wake-up after unlocking and only if the waiter sleeps
  (`KYTY_SEMA_HANDOFF`), no allocation per blocking wait, sub-millisecond timed waits (`KYTY_COND_SUBMS`, with
  `KYTY_COND_STATS` to see whether they matter);
- thread placement against the bimodal runs (`KYTY_IDEAL_LAYOUT`), Windows power throttling off (`KYTY_NO_THROTTLE`);
- GPU thread: blocked queues re-examined only after a real signal (`KYTY_CP_BLOCKED_WAKE_GEN`), draw-prep workers that
  park after idle spins (`KYTY_DRAW_PREP_SPIN_ADAPT`);
- descriptors: a reuse wrongly marked "fresh" (`KYTY_UPLOAD_LAST_REUSED`, patch `0008`) and push descriptors that
  re-encode only the changed elements (`KYTY_PUSH_DELTA`; dynamic offsets are not allowed with push descriptors);
- game settings, from the game's own code: the lighter rules did not reach the heavy levels whose scene files lack
  the tags; the experimental `patches/game/experimental-audit-17-11.txt` adds them. Note: the grass
  `ActivateDistanceFromHero` value is a lower bound of the activation radius; raising it would add work.

A frame-drop journal for long sessions (`KYTY_FLUIDITE=1`) records each drop with its probable cause, a per-frame
black box, a thumbnail and the camera, so that each place can be studied afterwards (`tools/fluidite-bilan.py`).
