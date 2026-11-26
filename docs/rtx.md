# RTX cards: what the port to them changes, and what is not known yet

This fork's earlier work was done on an AMD RX 7900 XTX, whose waves of 64 and
its float rules are the console's own. An RTX card asks for none of that: its
waves are 32 lanes, its `f32tof16` rounds toward zero, it takes view heaps of
1,000,000 views, and a group barrier waits for every thread of the group. The
translator and the runtime already carried those paths (they ran in WARP, under
GPU-based validation, and on an RTX 4070 for the float rules); what the port
changed, and what to set when something goes wrong there, is below. Nothing on
an RTX card has been run yet, so nothing there is measured.

## What changes on an RTX card

| | AMD RDNA (before) | RTX (this port) |
|---|---|---|
| Waves | 32 and 64 lanes | 32 lanes; the runtime asks the card and tells the translator (`set_host_max_wave`), and console wave64 programs run as two host waves of 32, whose cross-lane code is translated for waves of 32 |
| Console float rules | `VICTORY_RDNA_FLOAT`, on (the card runs the console's instructions) | off without being set (`set_host_rdna`); every float operation is spelled out in the form every host agrees on |
| Indirect dispatches past 65,535 groups in x | run as asked | taken to run as asked; the clamp allows 2^20 (`VICTORY_INDIRECT_WIDE=0` puts the cut back to 65,535) |
| View heaps | 2^21 views, no cap | at most 1,000,000 views (the driver's cap, probed, not assumed), with the null-slot clamp set before the first shader is translated; dynamic tables come out of the title's slots above it |
| Group barriers | wait for the live lanes | wait for every thread of the group; `VICTORY_GROUP_SYNC=1` keeps only the waits every lane runs, and unset is the safe mode there |
| `f32tof16` | round to nearest | rounds toward zero; the translation of the console's half nearests spells it out (measured on an RTX 4070) |

## What already came from the card, not the vendor

- The shader cache keys on what the card says (widest wave, view-heap limit,
  raw views, RDNA float bits), so an RTX card's translations cannot inherit a
  Radeon build's.
- The title's ray-traced indirect light is not DXR: the builder and the traces
  run as translated compute, and the one ray/node test is emulated in DXIL, so
  it is the same program on any card; how fast an RTX card runs it is not
  known. `VICTORY_BVH_BUILDER=1` turns it on, and `-RayTracing` on the
  launcher's line.
- Pipelines are made ahead by `victory warm` for whatever card the checks
  find, so a first run on a new card or driver need not stutter.
- Hybrid-graphics PCs pick a high-performance shader-model-6.6 adapter first;
  `VICTORY_D3D12_ADAPTER` names one explicitly (a zero-based index or part of
  its name, e.g. `NVIDIA` or `4080`).

## Switches to reach for on an RTX card

| Switch | Does |
|---|---|
| `VICTORY_INDIRECT_WIDE=0` | dispatches are cut at 65,535 groups in x again; reach for it if patches of the picture go blocky or a dispatch hangs |
| `VICTORY_GROUP_SYNC` | barrier waits, 2 every group (safe), 1 only the ones every lane runs, 0 none |
| `VICTORY_MEMORY_CARD_MB` | the most of title memory on the card (4,096) |
| `VICTORY_HOST_RDNA` | must stay unset on RTX: `1` asks translator and host to follow the console's own float rules, which an RTX card does not run |
| `VICTORY_D3D12_ADAPTER` | which adapter makes the device (name part or index) |
| `VICTORY_DYNAMIC_SLOTS` | how many descriptor slots the host keeps for tables it makes afresh; on a heap capped at the RTX limit of 1,000,000 views it takes them from the title's own slots (at most half the heap) so tables are not refused and draws dropped |
| `VICTORY_RENDER_SCALE` | renders the picture at a part of the output's size (a share between 0.2 and 1.0, `0.5` at half): patches the title's upscaler constants, so the FSR pass stretches it back |
| `VICTORY_OWN_UPSCALER` | shows the upscaler the picture as our own pass leaves it rather than the title's (`VICTORY_OWN_UPSCALER=0` is the title's) |
| `VICTORY_NO_WATCHDOG` | takes the title's crash-on-a-stall watchdog out while it runs |
| `VICTORY_SKIP_PIPELINES` | never makes the pipelines whose 16-digit shader hashes it names (comma-separated), as `scripts/rt_off_hashes.txt` pre-fills; where a pipeline hangs the card, its draws are dropped; release builds ignore it |
| `VICTORY_BVH_MISS=1` | the translated ray tests end at the root and miss, so a ray-tracing pass cannot hang with the structure builder off; part of the shader cache key |
| `VICTORY_AMBIENT_MOST` | how many times the light the title's own resolve left may pass the estimate of the light around (4); less keeps rooms looking at a sky from going too bright without rays |
| `VICTORY_NAN_SCRUB=1` | colours and image stores carry no NaN to neighbours in the programs found so far; off until measured in the game |
| `VICTORY_CONSTANT_MARKS=1` | constant buffer slots are marked in the strides' buffer so a computed pick reads zeros through a slot with no buffer where it would fault; off until measured in the game |
| `VICTORY_PIPELINE_WAIT_ONCE=0` | a pipeline that outlasts its wait budget waits again every frame, as before; unset, one budget over the whole run, its draws dropped until it is made |
| `VICTORY_CLAMP_WAITS=0` | the indirect clamps keep their two global waits for earlier shader writes; unset they wait, where on a Radeon the waits were every clamp |
| `VICTORY_UPSCALER=dlss` | runs the title's FSR path with the levers in place of the own-upscaler force: a DLSS proxy DLL beside the game (yours to supply) speaks FSR to the title and DLSS to the driver; set, it wins over `VICTORY_OWN_UPSCALER` and the loader logs whether an NGX library (`nvngx*.dll`) sits beside the title |
| `VICTORY_SAVES_DIR` | where the title's saves live, instead of beside the persistent local storage in the data folder |

## The launchers and the script

`scripts/play-nvidia.ps1` also takes `-Console S|X` (the Series X profile; `-SeriesX` keeps working), `-Upscaler fsr|dlss`, `-Preload` (`victory translate` and `victory warm` run first: the shaders are translated and their pipelines made before the game starts, minutes once, hitches gone after), `-CacheDir` and `-SavesDir` (`VICTORY_CACHE_DIR` and `VICTORY_SAVES_DIR`). `xenith.cmd` and `xenith-ui.cmd` reach all of them from `xenith.ini`.

## Taken from the forks the trackers rank

[trustno1-coder/VIctory-NVIDIA](https://github.com/trustno1-coder/VIctory-NVIDIA) sits on this tree's
line; its commits are here as they were, `VICTORY_DYNAMIC_SLOTS` on the capped view heap, the title
patches (render scale, own upscaler, watchdog), `VICTORY_BVH_MISS`, the mostly-off ray tracing with
its skip list, the picture fixes and the launchers under `scripts/`. From
[soldsawn/victory-nvidia-8gb](https://github.com/soldsawn/victory-nvidia-8gb) and
[fxceless/victory-fork](https://github.com/fxceless/victory-fork) (where its parts come from, with
the PR authors credited at the switch): the constant views of no bytes that stay none, the cap
before rounding of a constant view past 64 KiB (PR #1206), `VICTORY_CLAMP_WAITS`, and the marks of
constant buffer slots (PR #1216). Not taken: `VICTORY_XMEM_PERSISTENT_VIEW` (ours keeps one view of
a section already, `VICTORY_SECTION_WINDOW`, on by default), the heap worker for textures picked by
index and the other switches of its 536-commit line (our texture and table parts have moved too far
from theirs to sit together), and `VICTORY_TEXTURE_DROP_MIPS` (the levels-on-demand mode takes the
card's memory level by level already, `VICTORY_LEVELS_ON_DEMAND=1`).

## Not known on an RTX card

- Every frame-time figure of the README is the Radeon's (its table is kept
  until there are RTX numbers).
- That an RTX card runs past 65,535 groups of an indirect dispatch (above).
- That the translated shaders stay inside the wave registers an RTX card has
  for programs the console ran in waves of 64: they pass on waves of 32 here
  in twice the work, and the registers per thread are shared out otherwise.
- The driver's own pipeline cache behaviour with this many made-ahead
  pipelines; `victory warm` should be given a new driver as a new build.
