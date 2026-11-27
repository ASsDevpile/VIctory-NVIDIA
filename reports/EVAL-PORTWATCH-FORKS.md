# The forks the trackers rank, taken or declined

2026-11-27. What came over from the code forks behind
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


## Sweep of the fork network (the white-window round)

Every fork's tip checked against the last sweep (upstream and the boards
re-read the same day); three moved.

- **trustno1-coder/VIctory-NVIDIA** (`033be27` -> `7480e96`, two GPU fixes
  from jeremygold02's pull requests, both ported now):
  - **The ambient depth binds only to a matching SRV** (`c05b44b`): the
    stand-in for the indirect light took the depth view wherever it found
    one, even for the Radiance and Air passes (which have no depth, so the
    image stood in for it), and never checked the depth's size against the
    image's. Now the depth is optional (`ambient.rs`), only the Resolve pass
    binds it, only when its dimensions match the image's, and a missing or
    mismatched depth stands the pass down with its own note in the log.
  - **The buffer compare submits on its own** (`d1fe0bd`): the compare of
    copies in the card's memory rode inside the submission's list batch. A
    title list can leave a buffer promoted to COPY_DEST, and buffers decay
    to COMMON between ExecuteCommandLists calls - so a compare inside a
    later batch of the same submission could read a decayed buffer. It goes
    in its own ExecuteCommandLists, just before the submission's fence
    (`host.rs`, both the late and the timed paths). The `Timed::Compare`
    timing kind went with it (the compare no longer rides the timed list
    sequence; its card time was already in the compare's own query).
- **fxceless/victory-fork** (`ceb9e1f` -> `58de9bf`): two commits. `a20809d`
  is off-by-default diagnostics (card and page-mapping meters, a dump of the
  console's native pipelines) on their fork line - a candidate if we ever
  want the native-pipeline dump, not portable as a drive-by. `58de9bf` is
  the mouth-move fix: 16-bit values through a table's typed views as they
  are (their pull request 927), SDWA sign extension of 16-bit results
  (upstream #3124), plus two off-by-default switches and 488 lines of their
  valu tests. 2,446 insertions across 26 files of the shader lower - the
  same lower ours grew from, but two years of drift deeper; parked until
  someone can measure the mouths on a Windows machine, per the standing
  rule.
- **DoubleGhosty/cool_fox** (`f4b48ad` -> `caec503`, "leave the unused LOD
  slot of an array texture query undefined"): already in this tree - the
  level query takes no array slice and the unused coordinate slots stay
  undefined (`emit/lower.rs`, the cube-sample block), carried on our line
  under the name `read`.
- **Marvisak/VIctory** (the upstream), **soldsawn/victory-nvidia-8gb**,
  **GiovannaSGuerrera/Victory-RTX2080**,
  **Dolberthi/neptune-dolberth-nvidia-8gb**: nothing new since the last
  sweep.

The probes ran this round too (`scripts/debug-white.ps1`): with the fork's
own play set (no upscaler forced), the title presents frames steadily
(~3,300 frames in a 120 s window, ~27 FPS on the RTX 3060) - the white
window tracks the forced-upscaler path, and with the title's FSR in charge
the run dies in seconds on an unimplemented command-queue method (slot
`0xb8`), the same allocation-shape wall the DLSS round hit from the other
side.


## The perf round: the tracker's standings, and renderer port 5

Five to ten FPS with the launcher turned out to have a cause of our own first:
the launcher's back end forced `VICTORY_LOG=debug` on every run (the
command-line play script never did), so each frame printed a full resource
description for every texture a shader reads - half a gigabyte of formatted
lines in a nine-minute run. Runs now log at `info` unless `LOG_LEVEL` says
otherwise, and the per-frame texture line only exists at `trace`.

Then the whole network was swept again, this time by the names the
[recomp race tracker](https://gta6recomp.com/repo) uses (several of our old
sweep names 404: the repos live under different owners), and the tracker's
standings as of today:

- CGBJ (cool_fox) 58% - 25 FPS avg on NVIDIA, 80% story (mirror at
  DoubleGhosty/cool_fox)
- avatarmanz/VIctory-7900XTX 55% - 19-22 FPS boat mission, faster preparing
  and texture read-back
- Belobug 50% (AMD; indirect light stand-in, heavy scenes 225 ms -> 80 ms)
- Vice-Tay 45% (CGBJ's code on an RTX 4090, 15.2 FPS mean over 56 minutes)
- Hyphen (fxceless/victory-fork) 35.5% - freeze-free map ride on NVIDIA
- our line (VIctory-NVIDIA) 29% - about 20-22 FPS Series S half-scale on an
  RTX 5070

Ported this round, both opt-in and off by default:

- **Renderer port 5** (`VICTORY_PORT_CBV=1`), avatarmanz's measurement
  carried by cool_fox (`fad4e53`): translated shaders read constant buffers
  as raw bytes through their twins in the title's own memory instead of the
  per-submission copies - about 23,000 copies a frame of the city, ~9 MB,
  gone to zero when the switch is on. The shader cache keys on the switch.
  Ported with three small conflicts resolved (our `refresh_in_runs` cache
  call, our `port` module names, our wider re-export list, which keeps
  `constant_marks` and gains `constants_raw`).
- **trustno1-coder's paired-wave diagnostics** (`f110b57`,
  `VICTORY_PAIRED_SHADER_DIR`): diagnostics builds may load matching paired
  Wave32 bytecode when the normal translation confirms the bindings.
  Their other new commit (`fdc8bbc`, buffer comparisons back inside the GPU
  timings) reworks the same check-submit path this tree just rewrote its own
  way (Timed::Compare retired in the fork-sweep round); parked, not needed
  for speed.

Also on the shelf from this sweep, in the order the tracker makes them
interesting:

- avatarmanz's renderer ports 6 and 7 (`VICTORY_PORT_GUARD=1`,
  `VICTORY_PORT_JOURNAL=1`): 47.2 -> 45.1 ms measured on the 7900 XTX;
  additive, opt-in, but each touches the guard/journal internals this tree
  grew separately - port one at a time, measured.
- cool_fox's frame-rate switches (`VICTORY_FRAME_INTERVAL_MS`,
  `VICTORY_OUTPUT`): uncaps/retimes the title's 30 fps limiter; byte-checked
  offsets, off by default.
- shadowdog00/rorodev6's faster card-copy hashing (64 threads, a kilobyte
  each) and pooled GPU memory: worth a measurement round against our card
  steps.
- soldsawn's `VICTORY_TEXTURE_DROP_MIPS=2`: the 8 GB VRAM fit lever; only
  matters if the card spills (the 3060's 12 GB probably does not).

## The morning after port 5: the network's new tips, and what of them is ours already

The tips that moved since the last sweep (tracker names): trustno1-coder
`0ef2b99` -> `02a47cd`, cool_fox `c3e5c37` -> `ab113ff`, fxceless
`93db653` -> `e4245f3`. The rest held still (avatarmanz `c9c932c`,
rorodev6 `8604369`, Marvisak `63bcca4`, soldsawn `c09a44e`).

- **Port 5 measured**: 1 -> 5-8 FPS on the 3060 (the reporter's words: a
  500-800% improvement), and smooth.
- **fxceless's big squashed commit** (`e4245f3`): the headline win,
  `VICTORY_CARD_HASH_WIDE` (-10 ms of card a frame on a 4070), is the wide
  hash form this tree already carries - our `CARD_COMPARE` is one group of
  64 threads a piece with an eight-unrolled load loop (after fork #1014 and
  cool_fox `641835a4`); their -10 ms was the narrow -> wide step we made
  long ago. `VICTORY_GATHER_SEGMENTS` measured neutral on their side.
- **Ported from it**: upstream #3198 (a texture the card had no room for
  waits a second and is asked again on a later use, instead of staying
  without a host copy the whole run - the missing-texture and black-surface
  class) and fork #589 (a dropped descriptor heap's run of title-memory
  views is forgotten, so a heap made later at the same address does not
  find stale views). Both self-contained; the rest of the commit (4 KiB
  dirty tracking, the made-due-again recheck, the translator fixes of
  #646/#1002/#1112 and `VICTORY_WAVE_WIDE_ONLY`) is entangled with their
  write-watch journal and translator refactor - on the shelf until a
  Windows measurement machine takes it piece by piece.
- **trustno1-coder's diagnostics commit** (`b8fcd99`, descriptor view-table
  usage by kind): probe-grade, no speed; parked.
- **cool_fox's two port-1 commits**: already this tree's port 1, address
  order included (`xmem.rs` carries the same slices-in-address-order run).

## The 2026-11-26 live tip sweep

Checked again after the morning-after sweep; five named tips moved:

- **trustno1-coder** `02a47cd` -> `85a529b`: low-memory launcher and 16 GB
  BAR fixes are now in the launch surfaces. The runtime switch
  `VICTORY_WINDOWS_BAR_MB=3072` is selected automatically for systems below
  24 GB of RAM, and `0` or a configuration value can turn or tune it.
- **cool_fox** `ab113ff` -> `3277b15`: port 5 and port 1 are already in this
  tree; a later commit only enables those switches by default in that fork,
  so it is declined here because all Victory switches stay opt-in or are
  explicitly mirrored elsewhere.
- **fxceless** `e4245f3` -> `52ac4ec`: the cache collision and pipeline
  lifetime changes overlap machinery already here or conflicted with newer
  local structure. Its split-submission slot fix is ported now: a split
  submission releases descriptor-table slots after both host command-list
  halves execute. The alias pin and pipeline-panic follow-ups remain
  parked where they require machinery not present here.
- **avatarmanz** `c9c932c`: unchanged; ports 6 and 7 stay one-at-a-time
  watchlist items, with Windows measurement required.
- **upstream, rorodev6 and soldsawn**: no code move beyond already-recorded
  tips. Separate 8 GB texture and DirectStorage work stays declined for a
  12 GB RTX 3060 card.

## Belobug renderer port 6

Belobug's `a-publier` line reports about 22 fps (roughly 45 ms per frame) on
an AMD RX 7900 XTX with renderer ports 1, 2, 5, 6, and 7. That is not an
NVIDIA measurement. Port 6 (`VICTORY_PORT_GUARD=1`) is now ported here as an
experimental, off-by-default option; its write-watch synchronization and
parallel refresh planning still need an NVIDIA Windows A/B and stability run.
The `VICTORY_GUARD_HOT` extension stays off because Belobug measured it as
worse (45.6 to 47.8 ms per frame in run `guard-6`). Port 7's journal sharding
is deferred: it changes more synchronization and should not be combined with
port 6 before measuring the latter on NVIDIA.

## The port 6 A/B on the RTX 3060, and the 2026-11-27 tip sweep

The A/B the port 6 section asked for is done, on the reporter's RTX 3060 12 GB
(Windows 11, 1080p out, own upscaler at its minimum scale, the play set as the
launcher writes it). Two runs of about five minutes in the same place of the
game, one with the launcher's port 6 checkbox on and one with it off, each with
its usage CSV beside the log:

- with port 6: 4.25 fps steady-state mean (median 3.3), GPU 74.9% busy,
  324 faults a frame opened under the shared lock, 0.37 ms a frame waiting
  for it; the run's own thread at 20% of a core.
- without: 4.89 fps steady-state mean (median 3.7), GPU 86.5% busy, the same
  draw load (about 3,200-5,900 draws a frame in both).

Port 6 measures slower on this card, not faster; the guard's shared lock costs
more than its refresh planning gives back at this draw count. It stays off by
default and the checkbox stays for retests. The A/B also says what a frame
waits for here: of about 310 ms a frame only 37 are the host's preparing and
18 the copying back - the rest is the card executing the translated draws. The
lever for this card is cheaper translated work and fewer draws, not more host
synchronization; port 7 stays deferred.

The sweep of the tips the same morning:

- **Belobug's `main` line** (their `a-publier`, the 22 fps line, has none of
  it): the clean-up passes over translated shaders (`ae75a66a`) are already
  this tree's `emit/bitcode/opt.rs`, ours carrying the later FIRST and WIDE
  constants on top. `VICTORY_ASYNC_SUBMIT` by default is already ours in
  effect - the play set's `VICTORY_THIN=1` turns the same path on, and the
  logs show the submissions sent ahead with 0.0 ms waiting for the card. The
  views table's read-write lock (`ff920f22`) is already in this tree's
  `descriptor.rs`. The least-level-of-detail views (`5d7bd16d`) change nothing
  for this title by their own measurement. The bindless-plan rebuild fix and
  the ambient-sky work (`705a2d09` and around) are one entangled commit - on
  the shelf with their screen-probes program skip (`6986a571`, which this
  tree can carry on `Shader.container`'s bytes with `VICTORY_RAYS` as the
  escape, but which needs eyes on the picture before it defaults here).
- **kelvaroq** (stellarr-studio, the public NVIDIA leader at 10 fps on a
  4090) `e062a82e`: their new work is a unified-memory layer and DXR, shipped
  as 16 patch files (`native/patches/0049`-`0064`, 20,660 lines) against
  their own tree, all off by default. Not portable piecemeal. The one idea
  aimed at exactly this tree's bottleneck is their indirect batching
  (`0051-indirect`: several of the title's indirect records clamped into one
  scratch batch instead of one host pass each) - studied in full and
  superseded: this tree's `indirect/batch.rs` (play-set mode `2`) already
  does more (256 lanes to their 64, four batch sources to their one,
  tile-class dedup, budget charged per executions), so the port is dropped.
- **The chase for 24 fps**: Belobug's number is an RX 9070 XT, a card several
  times this one at raster. With the host's share of the frame already at
  12%, the realistic order for this 3060 is whatever the next sweep finds in
  translated-shader cost (avatarmanz's port-RT part 1 and
  `VICTORY_PORT_CONSTANTS_ORDER` are the port-5-family candidates), and on
  the user's side the output height (`RESOLUTION` 720 or 540 in the
  launcher), since the card is already at its minimum render scale.
- **The port 5 miss**: checking fxceless's `VICTORY_INPLACE_CONSTANTS` led
  back to our own renderer port 5 (`VICTORY_PORT_CBV`) and to the discovery
  that no script, doc, or launcher key ever carried it - off by default in
  `emit/shader.rs`, absent from every play set since its merge (proven
  against the uploaded captures: no "renderer port 5" log lines, no
  `VICTORY_PORT_CBV` in the environment echoes). The measured 1 to 5-8 fps
  win has therefore not been running. The play sets now carry it (PR #26);
  first launch retranslates the shader cache once, since the cache keys on
  the switch.
