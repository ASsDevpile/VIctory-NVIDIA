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
| `VICTORY_D3D12_ADAPTER` | which adapter makes the device |

## Not known on an RTX card

- Every frame-time figure of the README is the Radeon's (its table is kept
  until there are RTX numbers).
- That an RTX card runs past 65,535 groups of an indirect dispatch (above).
- That the translated shaders stay inside the wave registers an RTX card has
  for programs the console ran in waves of 64: they pass on waves of 32 here
  in twice the work, and the registers per thread are shared out otherwise.
- The driver's own pipeline cache behaviour with this many made-ahead
  pipelines; `victory warm` should be given a new driver as a new build.
