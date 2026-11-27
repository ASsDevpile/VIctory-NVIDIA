# The launcher's back end: xenith-core

The split of labor for the new launcher: the **front end** owns how it looks and
how it feels (layout, tabs, styling, interactions). The **back end** owns
everything underneath: configuration, the play set, launching, stopping, logs,
and folders. That back end is `scripts/xenith-core.ps1`.

A front end consumes it in one of two ways and must not bypass it:

1. **CLI + JSON** (works from any language or framework):
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\xenith-core.ps1 <command> [args]`
   Every command prints a single JSON document. On failure it prints
   `{"error": "..."}` and exits 1.
2. **Dot-sourced functions** (for a PowerShell front end such as the WPF one):
   `. .\scripts\xenith-core.ps1` then call the `*-Xenith*` functions directly.

## Rules for a front end

- Never set `VICTORY_*` environment variables, never assemble run arguments,
  never touch the cache or NGX layout. The play set lives in `Get-XenithPlaySet`
  (mirrored from `scripts/play-nvidia.ps1`); when one moves, the other moves.
- `xenith.ini` is read and written only through `config` / `Set-XenithConfig`.
  Unknown keys survive a write, so a front end may store its own keys
  (e.g. `THEME=dark`) alongside the ones below.
- Launches return a process id; stopping uses that id. A stopped id, a missing
  runtime, or a missing game all come back as JSON errors, never as dialogs.

## Configuration (`xenith.ini`, next to the repo root, gitignored)

| key | meaning |
|---|---|
| `GAME` | path to the title's exe |
| `RESOLUTION` | render height ask (e.g. 720; the scale is computed against the console's output) |
| `ADAPTER` | GPU name substring (e.g. `NVIDIA GeForce RTX 3060`), empty = fastest |
| `QUALITY` | `on` = the quality trade (relay 1, no card steps, waited textures; costs fps) |
| `RAYTRACING` | `on`/`off`; off applies `scripts/rt_off_hashes.txt` |
| `BUILD` | `diag` or `release` (which `target\<build>\victory.exe` to run) |
| `SKIP` | pipeline skip preset (diagnostics) |
| `UPSCALER` | empty (fork's own) or `dlss` (placeholder only; the title still uses FSR) |
| `CONSOLE` | `S` (1080p out) or `X` (2160p out) |
| `PRELOAD` | `on` = translate + warm before every launch (minutes, once) |
| `CACHE_DIR`, `SAVES_DIR`, `DLSS_DIR`, `LOG_DIR` | where those live; empty = defaults |
| `LOG_LEVEL` | how much the runtime logs during a run: `info` (the default, cheap), `debug` (the per-frame diagnostics spam; measurable fps) or `trace`; the white-screen probes need `debug` |
| `PORT_RT` | `on` enables the experimental placed-copy ordering optimization (`VICTORY_PORT_RT=1`); off by default, compare with a matched run before keeping it on |
| `PERF_LOG` | `on` = sample CPU, RAM and GPU usage for the whole run into a `victory-perf-<date>.csv` in the log folder (`scripts/capture-usage.ps1` follows the run's process id) |
| `PERF_INTERVAL` | seconds between performance samples (1-60, default 1; used when `PERF_LOG` is on) |

## Commands

| command | args | returns |
|---|---|---|
| `status` | – | setup check: `game_ok`, `runtime_ok` + `runtime` path, `rt_list_ok`, `dlss_ok` + `dlss_dir`, the dirs, `build`, `console` |
| `config` | – | the full configuration as JSON (defaults filled in) |
| `config set` | `KEY=VALUE ...` | the configuration after writing |
| `adapters` | – | GPU list, NVIDIA first: `name`, `driver`, `nvidia` |
| `playset` | – | what a launch would set: `settings` (the VICTORY_* table), `exe`, `series_x`, `render_scale`. For showing "Series S, rendering at 720p (render scale 0.6667)" |
| `start` | – | launches: `pid`, `exe`, `log` (the run's stderr log), `started`, `render_scale`. Honors `PRELOAD` |
| `stop` | `<pid>` | stops that run and any victory runtime left over: `stopped` |
| `tail` | `[lines=40]` | the latest run log's last lines: `path`, `lines[]` |
| `open` | `cache`saves`dlss`game`log`repo` | opens the folder in Explorer: `opened` |
| `save-log` | `<destination>` | copies the latest run log there: `saved_to` |
| `version` | – | `core`, `repo` |

## Front-end checklist against the back end

- PLAY button = `start`; keep the returned `pid` for STOP.
- Status line = `playset` for the "Series S, rendering at Np (render scale X)" text.
- Log box = poll `tail 100` every second or two; SAVE = `save-log`, COPY = copy
  the lines you already have.
- Settings page = `config`, edit fields, `config set` on save. Adapter dropdown
  = `adapters` (first NVIDIA entry is the default pick).
- Health/first-run wizard = `status`; every `*_ok` false gets a human message
  and, where one exists, an `open` target to fix it in.
