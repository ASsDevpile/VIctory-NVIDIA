# The forks the trackers rank, taken or declined

2026-11-26. What came over from the code forks behind
[portwatch-vi.xyz](https://portwatch-vi.xyz/) and
[gta6recomp.com/repo](https://gta6recomp.com/repo), and what did not. The
trackers themselves rank READMEs and numbers; the code of the ranked trees is
what was compared.

## Taken

From `trustno1-coder/VIctory-NVIDIA` (which sits on this tree's own line, so
its commits came over as they were, names kept):

- `VICTORY_DYNAMIC_SLOTS` on a view heap capped at the card's 1,000,000 views
  (tables otherwise refused were drops a frame).
- Title patches in the loader, byte-checked against 1.0.2.1: render scale,
  our own upscaler, the watchdog taken out.
- `VICTORY_BVH_MISS`: ray walks end at the root and miss, so a ray pass
  cannot hang with the structure builder off (~10 ms less a frame claimed).
- "Faces move, ray tracing mostly off, intro video fix, picture fixes": the
  pipeline skip list (`VICTORY_SKIP_PIPELINES` and
  `scripts/rt_off_hashes.txt`), `VICTORY_AMBIENT_MOST`, `VICTORY_NAN_SCRUB`,
  `VICTORY_PIPELINE_WAIT_ONCE`, the marks of constant buffer slots
  (`VICTORY_CONSTANT_MARKS`, fxceless PR #1216 by GamingRipperDoc), the
  16-bit-half buffer loads (`emit/halves.rs`, PR #927 halves by
  tippythetaidum), the intro video texture fix, capture with F9, and the
  launchers (`play-nvidia.ps1` with quality, ray tracing and adapter picks;
  per console and resolution).
- Adapter picks (`VICTORY_D3D12_ADAPTER` was ours already; the launcher got
  the `-Adapter` flag, naming our switch).

From `soldsawn/victory-nvidia-8gb` and `fxceless/victory-fork`:

- A constant buffer view of no bytes stays one (soldsawn 619b2dc; fxceless
  PR #1260 by LeonardoS11): 256 bytes of whatever lay at the address in the
  host copy is what a size-0 view read before; view floors flickered.
- The cap before the rounding, sizes within 255 of 64 KiB no longer round to
  0 bytes (fxceless PR #1206).
- `VICTORY_CLAMP_WAITS=0`, the indirect clamps' two global waits (soldsawn
  830ca05, clamp half).

## Declined, and why

- `VICTORY_XMEM_PERSISTENT_VIEW` (912d5c5 and its two follow-ups): this tree
  keeps one view of a section already, `VICTORY_SECTION_WINDOW`, on by
  default).
- `VICTORY_TEXTURE_DROP_MIPS` (b4ff304 and family, and 830ca05's UI half):
  our levels-on-demand mode (`VICTORY_LEVELS_ON_DEMAND=1`) is the same shape
  and further along; theirs is woven through a texture struct this tree has
  since rebuilt.
- Texture copy floor at a third of the budget (a360025): ours caps the floor
  at a quarter already (`texture_floor_bytes`).
- Free runs across the search cursor in dynamic slots (4d0c634): ours has
  the search (test `dynamic_search_can_find_a_run_across_the_cursor`).
- The parallel card compare (1cd8f73, and fxceless 5557224): our
  `CARD_COMPARE` shader runs 64 threads on a 64 KiB piece already.
- The lookup cache counting fix (bc6ee68) and `4d0c634`'s refused-table
  counters: ours has no lookup cache of that shape; the counters came with
  their diagnostics rewrite.
- The heap worker for textures picked by index (`VICTORY_HEAP_WORKER`,
  233a65f/d4a528b, PR #1007) and the table stage and heap lock switches
  (5d659e0): real wins on their 8 GB card, but threaded through their
  record, list and texture paths, which have moved 536 commits from ours.
  Porting them blind, with no Windows machine in reach to run the game, is
  how a fork grows a bug no one can find; they stay out until someone can
  measure them here.
- Parked unmapped watch blocks (e277b98), `VICTORY_TEXTURE_NO_WAIT` and the
  rest of its watch rework: same reason, the branch's watch code ours grew
  past.
