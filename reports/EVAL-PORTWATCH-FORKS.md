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

## Sweep of the fork network (the DLSS round)

Checked with the tips of every fork named above and the upstream, fetched:

- **Marvisak/VIctory** (the upstream): two new GPU commits, `842b0cb` (the
  depth bounds test reaches the host, pull request 158) and `219878a` (a null
  shader view has no alias source). Both are follow-ups to machinery ours
  never had (upstream's texture-alias tables and a pipeline host ours rebuilt
  five hundred commits ago): not portable without taking that machinery too.
  The depth bounds port is a candidate for a later deliberate job.
- **fxceless/victory-fork**: nothing new past `f6a09d3`, already evaluated
  (its texture worker measures +40 % of world frames on their machine, but the
  heap worker stays a fork-line we cannot verify here). `6a42ed2`, a small
  saves fix, IS ported now: an older save version another program holds open
  (a virus scanner, a backup) no longer makes the container unreadable.
- **soldsawn/victory-nvidia-8gb**: three new commits, all meta for their 8 GB
  variant (their overlay's footer credit, their launcher, their README), plus
  their merge of fxceless pull request 999 (`VICTORY_TEXTURE_BACK`), which
  this tree already carries in `texback.rs` - with the water formats on by
  default, where theirs are off.
- **trustno1-coder/VIctory-NVIDIA**: nothing new; its tip is the commit our
  last port ended at (`033be27`).
- **DoubleGhosty/cool_fox**: nothing new; everything of it stays in the tree.


## Sweep of the fork network (after the conflict-marker fix)

Upstream `842b0cb` -> `63bcca4`, fxceless `f6a09d3` -> `ceb9e1f`, the rest of
the standing forks unchanged. Both trackers re-read the same day
(portwatch-vi.xyz and gta6recomp.com/repo).

- **Marvisak/VIctory**: `63bcca4` is a README update only. Nothing to port.
- **fxceless/victory-fork** landed two performance commits (`06702fe`,
  `ceb9e1f`), measured on their machine:
  - The **BC7 rotation fix** (upstream VIctory `#3111`: a channel rotation
    exists only in modes 4 and 5; ours applied the field to every mode, so
    garbage bits in other modes' control codes corrupted channel precisions)
    IS ported now, with their test, which passes here.
  - Their **dispatch spread across z** is declined: it keeps the 65,535
    groups cap and folds the rows through the z dimension; this tree lifts
    the cap on RTX directly (`widest`, the vendor-aware indirect window),
    which passed our measurements, and adding a second wide-dispatch shape
    invites bugs no one here can test.
  - Their **flight-room, texture-checks-on-helper-threads and view-heap
    timing** work stays declined, as the heap worker before it: 1,700 lines
    into a torn/host line ours rebuilt long ago, unverifiable in this
    sandbox.
- **soldsawn/victory-nvidia-8gb**: nothing new since the last sweep.
- **Newly spotted by PortWatch**:
  - `GiovannaSGuerrera/Victory-RTX2080`: a separate snapshot line ("Series
    S mode on NVIDIA 8 GB cards and older CPUs"), six commits, mostly docs
    and scripts, one opt-in heap-pass change - built on `heap_pass.rs`,
    machinery ours never had. Nothing portable; its measurement habit
    (a local usage capture script) is worth copying later.
  - `Dolberthi/neptune-dolberth-nvidia-8gb`: another separate snapshot
    line with real 8 GB fixes: wider texture-queue room and DirectStorage
    staging, F11/Alt+Enter borderless, and a revert of a half-views patch
    that stretched faces. Their texture-eviction deadlock fix names a
    `slot_evict` this tree does not have: our sweep holds the textures
    lock, but nothing inside it re-locks that mutex, so the bug's shape is
    not here. Nothing portable today.
- **The boards**: cool_fox (the DoubleGhosty mirror) holds the lead on both
  at about 25 FPS on NVIDIA, gameplay reported stable; this tracker entry
  (`trustno1-coder/VIctory-NVIDIA`, the source of our line) sits at 29 %,
  ranked tenth on gta6recomp. PortWatch's Nov 26 note says the original
  codec-d/cool_fox went 404 again - the mirrors hold the code.


## The watchlist, taken

The two habits the last sweep left on the watchlist are in, each in our own
code (their lines differ from ours; habits copied, not code):

- **The measurement habit (GiovannaSGuerrera/Victory-RTX2080)**:
  `scripts/capture-usage.ps1` samples the machine and the run once a second
  into a CSV (CPU, RAM, the card's utilization and memory, the run's own CPU
  and RAM), from CIM's formatted counters so the numbers read the same on a
  Windows of any language. A frame-time claim can now carry its usage line.
  Their `heap_pass.rs` lines stay unported, as before.
- **The borderless toggle (Dolberthi/neptune-dolberth-nvidia-8gb)**: F11 or
  Alt+Enter takes the title window's rims off and fills the screen's work
  area; again brings the rimmed window and its place back
  (`modules/lifecycle.rs`, our own window procedure, key first). Their
  texture-queue room, DirectStorage staging and `slot_evict` deadlock fix
  stay unported, as before: the bug's shape is not in this tree.
