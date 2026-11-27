# VIctory on an RTX card

A fork of [VIctory](https://github.com/Marvisak/VIctory), a compatibility layer
that runs an Xbox Series title natively on Windows from files the user supplies.

## The goal

**A stable 30 fps or more without ray tracing, then as high a frame rate and as
low frame times as the PC allows**, on NVIDIA RTX cards first and on PCs with
32 GB (later 16 GB) of RAM. The work before this one was done on an AMD RX
7900 XTX; what the port to RTX changes and what is still to be measured there
is in [docs/rtx.md](docs/rtx.md).

The way there is **porting, not emulating**: patching the title's renderer so it
behaves the way a PC renderer does, rather than having the layer watch and copy
the console's shared memory every frame. Shaders are translated ahead of time
into a versioned store that is kept between builds. Ray tracing stays optional
and off by default. The picture comes after the frame rate: texture pop-in and
lighting that is too bright or too dark when walking indoors are next in line.

**This repository contains no game files, code or assets.** You need your own
copy of the game. It is not affiliated with or endorsed by the game's developer
or publisher.

## Where it stands (2026-11-26)

The card figures below are of the AMD build, the one machine it was tested on:
Windows 11, Intel i9-12900K, 64 GB RAM, Radeon RX 7900 XTX, the Series X
profile, ray tracing off. On RTX they are not measured yet (nor has anything
here been known to hang one); the Radeon table is kept until RTX numbers are.

On RTX, tests of this repository that make D3D12 devices run on any hardware
that answers (WARP included): the translator's waves of 32, the clamped view
heaps and the every-thread group barriers are what an RTX card asks for, and
the path an RTX card takes is the one those tests exercise.

| RX 7900 XTX | |
|---|---|
| City street, renderer patches 1+2 on | about 53 ms a frame (about 19 fps) |
| Same scene before the patches | 57-75 ms (13-17 fps) |
| Shaders the title uses that translate | all of them (25,790 of 25,985; the rest are unused geometry shaders) |
| Memory | about 35 GB of private memory: **64 GB of RAM recommended** for now |

It started at 280 ms a frame in the same scenes three days earlier. On RTX the
title's traces need the same 35 GB of RAM; the card's part of the shared memory
is set by `VICTORY_MEMORY_CARD_MB` (4,096 MB, sized for a 24 GB card).

### Renderer patches (off by default while they are tested)

| Switch | What it does |
|---|---|
| `VICTORY_PORT_CONSTANTS=1` | The title's 174 MB constants heap is read by the card where the title writes it: no uploads, no fills |
| `VICTORY_PORT_DESCRIPTORS=1` | The title's descriptor-table stores are patched (byte-checked) to report the slots they write, instead of a scan of ~600,000 slots a frame |
| `VICTORY_PORT_GUARD=1` | Experimental renderer port 6: coordinates write-watch faults and refreshes with per-block claims, and avoids kernel queries for known view memory. Measured on an RX 7900 XTX, not yet on NVIDIA; test with `scripts\play-nvidia.ps1 -PortGuard` or the Xenith setting before enabling it in a play profile. |

What is known to be wrong:

- Trees, signs and far objects flicker in the distance in some places.
- Lighting is too bright or too dark after walking indoors, until the title has
  run for a while; rooms with little direct light are too dark without `-RayTracing`.
- Textures of what just came into view appear late while the title streams.
- The first run of a new build stutters while the driver makes pipelines
  (`victory warm` makes them ahead).
- Recording a frame in the world makes the title's own watchdog end it.
- On RTX, tile lists past 65,535 groups run as asked now ([docs/rtx.md](docs/rtx.md));
  when the card cuts them instead, patches of the picture go blocky again.

## How to run it

You need Windows 10/11 x64, a CPU with AVX2, a Direct3D 12 GPU with shader
model 6.6 and mesh shaders, Rust (the toolchain is pinned), the MSVC build
tools, and your own dump of the title.

```powershell
git clone https://github.com/ASsDevpile/VIctory-NVIDIA
cd VIctory-NVIDIA
copy victory.example.toml victory.toml      # then set your paths, outside this folder
cargo build --locked --profile diag -p victory --features diagnostics
scripts\play.ps1 -Exe <path of your copy's executable>
```

Or use the launcher: `xenith.cmd` (a menu; a special copy of the
[Xenith VI](https://github.com/ASsDevpile/XenithVI) launcher, changed for
this fork) or its window, `xenith-ui.cmd`. Both keep their settings in
`xenith.ini` (title path, console Series S or X, render height, the card,
quality, the upscaler, shader and pipeline preload, and where the cache, the saves and
the DLSS files live) and start through `scripts\play-nvidia.ps1`. The card
is found for you (the fastest is picked by default; the window names yours
and lets you pick another). The upscaler row picks FSR (the title's own) or
DLSS: set, the title runs its FSR path and a DLSS proxy - yours to supply,
like the rest of the NVIDIA files - speaks DLSS to the driver. The proxy and
its NGX DLLs live in a folder of their own (`dlss\` next to the launcher,
or name any folder with `VICTORY_DLSS_DIR`); the game's folder is never
touched. When preload is enabled, the window asks before each launch and shows
the current phase. It translates shader code and warms host pipelines before
the run (minutes on the first pass or after a cache refresh); it does not
bulk-load streamed game assets into VRAM. The project's website is
[docs/index.html](docs/index.html) (GitHub Pages serves it from `docs/`).

`scripts\play.ps1 -Safe` leaves out the newest, faster ways; try it first when
something is wrong. `-RayTracing` turns the title's ray-traced indirect light on.

On a hybrid-graphics PC, the runtime and offline pipeline checks prefer a
high-performance adapter with Shader Model 6.6. The runtime logs its adapter
name, PCI vendor and device IDs, and dedicated VRAM. Set
`VICTORY_D3D12_ADAPTER` to a zero-based DXGI index or part of the adapter's
name to select it explicitly. With the launcher, pass
`-More @{VICTORY_D3D12_ADAPTER='NVIDIA'}`. On an RTX card nothing needs
turning: the console's wave64 programs are translated for the card's waves of
32, the float rules of the console's own hardware stay off, and view heaps
stay under the heap size the driver takes ([docs/rtx.md](docs/rtx.md)).

Before the first run, ahead of time (both can be stopped and go on later):

```powershell
target\diag\victory.exe shaders <the shader archives>   # every shader translated, minutes
target\diag\victory.exe warm --used                     # pipelines earlier runs drew with, for a new driver or build
```

Commands, debugging switches and upstream's own description:
[docs/README-fxceless.md](docs/README-fxceless.md). Every `VICTORY_...` switch is
described in a comment where it is read.

## What is different here

In short; the reasons and the measurements are in [docs/findings.md](docs/findings.md).

- **List calls are written down, not carried out, on the title's threads**
  (`VICTORY_THIN`): eight threads of ours translate them.
- **Submissions are prepared by a thread of ours and joined**
  (`VICTORY_ASYNC_SUBMIT`, `VICTORY_JOIN_PARTS`), with what can be spread over
  threads spread: refreshes, compares (AVX2), descriptor records, landings.
- **What shaders wrote comes back beside the write guards**, by the dwords that
  changed, on a thread of its own (`VICTORY_RELAY`, `VICTORY_LAND`).
- **Buffer fills that need bytes still on the card are done on the card**
  (`VICTORY_CARD_STEPS`) instead of waiting for it.
- **The title's writes are caught more cheaply**: one view opened at a fault,
  blocks that rest, places in the title's code that look before they write.
- **Textures go up on a copy queue of their own** and a slot shows one only after
  its upload ran, which also ended a device loss that came every 15 minutes or so.
- **Boats float**: textures that shaders write and the title's CPU reads go back
  to title memory (from fxceless and Geckomacabre, on by default here).
- **Taken from the RTX forks**: dynamic slots that answer the card's capped view
  heap, the render-scale, upscaler and watchdog title patches, the ray-tracing
  passes skipped for the known-hanging pipelines, ray walks that end at the root
  when the structure builder is off, and constant buffer views of the sizes the
  card takes. The switches and where each came from are in
  [docs/rtx.md](docs/rtx.md).
- **Frame record and replay** with per-pass times and shader variants compared
  turn by turn ([docs/replay.md](docs/replay.md)).

## Credits

This is a tree of other people's work with more on top. The history is kept, and
commits taken from elsewhere name the commit and its author.

- **[VIctory](https://github.com/Marvisak/VIctory)** by Marvisak and its
  contributors: the loader, the runtime services, the Direct3D 12 back end and
  the shader recompiler.
- **[fxceless/victory-fork](https://github.com/fxceless/victory-fork)**: the fork
  this one started from, and the people whose pull requests it carries.
- **[trustno1-coder/VIctory-NVIDIA](https://github.com/trustno1-coder/VIctory-NVIDIA)**:
  the RTX run this fork rides on (dynamic slots on a capped view heap, the title
  patches, the ray-tracing skip list, the launchers); its commits are here with
  their names kept.
- **[soldsawn/victory-nvidia-8gb](https://github.com/soldsawn/victory-nvidia-8gb)**:
  the constant view sizes (with fxceless PR #1206) and the clamps' waits.
- **[DexNom/VIctory](https://github.com/DexNom/VIctory)**: ray tracing fixes,
  cube gradients, sparse textures.
- **[Belobug/VIctory-Belobug-AMD](https://github.com/Belobug/VIctory-Belobug-AMD)**:
  the ambient light idea, pipeline workers, and work by romainhedouin.
- **[FQY55kai/ZJOU-VICTORY](https://github.com/FQY55kai/ZJOU-VICTORY)**.
- **[myokex/victory-amd](https://github.com/myokex/victory-amd)**: the guard over
  every view of a page (with Spexivus, joroyt and tightfall), and Joshua Odom's
  reads into title memory.
- **Geckomacabre** and **cxy0072019-sketch**: the texture read-back.
- **[XCL](https://github.com/ivall/xcl)** (GPL-2.0-only) was read for how the same
  title behaves under another layer; no code of it is here.
- This fork's changes were made with [Claude Code](https://claude.com/claude-code).

## License

GPL-3.0-or-later, as VIctory. See [LICENSE](LICENSE); the one file that is not
covered is named in [docs/asset-policy.md](docs/asset-policy.md).
