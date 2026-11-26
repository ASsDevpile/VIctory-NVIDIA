# The white-window debug run: the fork's default play set, one probe at a
# time, each with a debug log of its own, each run kept to its window and
# killed there. Read this way, a silent white screen says exactly where it
# stopped instead of flashing a window.
#   scripts\debug-white.ps1 -Exe "D:\...\game_scarlett_master.exe"
#   scripts\debug-white.ps1 -Exe ... -Probes base,planes0 -Seconds 90
# The logs land in <repo>\debug-runs\<probe>.log (stderr, the runtime's own)
# and <probe>-out.txt (stdout); they are yours to send whole.
# Every run carries the play set's own RT skip list (rt_off_hashes.txt): the
# ray-miss light passes are a documented way to whiten rooms, so no probe runs
# without them by accident.
# The probes, in the order they run:
#   base      the play script's Series S set, untouched (own upscaler in charge)
#   planes0   + VICTORY_PLANES=0, the two-plane compose off
#   no-own    + VICTORY_OWN_UPSCALER=0, the title's own upscaler path
#   series-x  the Series X profile instead of S
# Every probe runs with VICTORY_LOG=debug, the panel on (F3 over the window
# tells you whether frames move even while the picture is white), and the
# render scale the 720p ask has on a 1080p output.
param(
    [Parameter(Mandatory)][string]$Exe,
    # Where the logs land, relative to the repository root.
    [string]$Out = 'debug-runs',
    # Seconds a run lives before it is killed.
    [int]$Seconds = 120,
    # Which of base,planes0,no-own,series-x to run. Read BEFORE anything else
    # shadows it: PowerShell variables are case-insensitive, so a local
    # "$probes" once overwrote this parameter and every probe was silently
    # filtered out of the run (nothing launched, nothing said why).
    [string]$Probes = 'base,planes0,no-own,series-x',
    # Wipe the derived cache (D:\VIctoryForkCache) before the first probe.
    [switch]$Purge
)

$ErrorActionPreference = 'Continue'
Write-Host ("PowerShell {0}" -f $PSVersionTable.PSVersion)

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$victory = Join-Path $repo 'target\diag\victory.exe'
if (-not (Test-Path $victory)) { Write-Host "No $victory. Build first: cargo build --locked --profile diag -p victory --features diagnostics"; exit 1 }
if (-not (Test-Path $Exe)) { Write-Host "No $Exe."; exit 1 }
$Exe = (Resolve-Path $Exe).Path
$dir = Join-Path $repo $Out
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$dir = (Resolve-Path $dir).Path
Write-Host "logs land in $dir"

if ($Purge) {
    Write-Host "purging the derived cache (retranslation takes minutes on the first run)"
    Remove-Item 'D:\VIctoryForkCache' -Recurse -Force -ErrorAction SilentlyContinue
}

# The play script's Series S set, verbatim, so the probes differ only where
# they mean to.
$rtList = Join-Path $PSScriptRoot 'rt_off_hashes.txt'
$skipPipelines = 'none'
if (Test-Path $rtList) { $skipPipelines = (Get-Content $rtList -Raw).Trim() }
else { Write-Host "no ${rtList}: the probes run without the RT skip list" }

$settings = @{
    VICTORY_TEXTURE_NO_WAIT   = '1'; VICTORY_RELAY              = '2'; VICTORY_CARD_STEPS        = '2'
    VICTORY_WIDE_BACK         = '1'; VICTORY_CARD_REHASH_RUNS   = '1'
    VICTORY_JOIN_COPIES       = '1'; VICTORY_INDIRECT_WINDOW    = '1'; VICTORY_RELAY_COPY        = '1'
    VICTORY_INDIRECT_BATCH    = '2'; VICTORY_MAP_THREADS        = '1'; VICTORY_TITLE_PRIORITIES  = '0'; VICTORY_CARD_AWAKE = '1'
    VICTORY_SHOW_AFTER        = '1'; VICTORY_AMBIENT            = '0.8'; VICTORY_D3D12_DRED       = 'light'
    VICTORY_SKIP_PIPELINES    = $skipPipelines
    VICTORY_THIN              = '1'; VICTORY_JOIN_PARTS         = '8'; VICTORY_UPLOAD_AHEAD       = '1'
    VICTORY_AMBIENT_AIR       = '1.5'; VICTORY_AMBIENT_MOST      = '2'; VICTORY_NAN_SCRUB         = '1'
    VICTORY_PIPELINE_WAIT_MS  = '10000'; VICTORY_DYNAMIC_SLOTS    = '524288'
    VICTORY_RENDER_SCALE      = '0.6667'; VICTORY_OWN_UPSCALER    = '1'; VICTORY_PANEL             = '1'
    VICTORY_BVH_MISS          = '1'
    VICTORY_CARD_BUFFERS_MIN_MB = '1'; VICTORY_CARD_BUFFERS_MB    = '1536'
    VICTORY_COMPOSE           = '1'
    VICTORY_CACHE_DIR         = 'D:\VIctoryForkCache'; VICTORY_SAVES_DIR   = 'D:\VIctoryForkData'
}

# The list is built one variable at a time and joined on a single line: a
# hashtable with a trailing comma at a line's end is a parsing trap this
# script fell into once.
$probeBase    = @{ name = 'base';     extra = @('--console', 'series-s'); over = @{} }
$probePlanes0 = @{ name = 'planes0';  extra = @('--console', 'series-s'); over = @{ VICTORY_PLANES = '0' } }
$probeNoOwn   = @{ name = 'no-own';   extra = @('--console', 'series-s'); over = @{ VICTORY_OWN_UPSCALER = '0' } }
$probeSeriesX = @{ name = 'series-x'; extra = @();                        over = @{} }
$probeList = @($probeBase, $probePlanes0, $probeNoOwn, $probeSeriesX)

$wanted = @($Probes.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
Write-Host ("probes built: {0}; asked for: {1}" -f (($probeList | ForEach-Object { $_.name }) -join ', '), ($wanted -join ', '))
if ($probeList.Count -eq 0) { Write-Host 'no probes were built; nothing to run'; exit 1 }
if ($wanted.Count -eq 0) { Write-Host "no probe names in '$Probes' (expected base,planes0,no-own,series-x)"; exit 1 }

foreach ($p in $probeList) {
    if ($wanted -notcontains $p.name) { continue }
    Write-Host "`n=== probe $($p.name) : $Seconds s ==="
    Get-ChildItem Env:VICTORY_* -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item ("Env:" + $_.Name) -ErrorAction SilentlyContinue }
    $env:VICTORY_LOG = 'debug'
    foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }
    foreach ($k in $p.over.Keys) { Set-Item "Env:$k" $p.over[$k] }
    $errLog = Join-Path $dir ($p.name + '.log')
    $outLog = Join-Path $dir ($p.name + '-out.txt')
    $proc = Start-Process -FilePath $victory -ArgumentList @('run', ('"' + $Exe + '"'), '--execute') + $p.extra `
        -WorkingDirectory $repo -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
        -PassThru
    if (-not $proc) { Write-Host '  the runtime did not start (Start-Process failed); its error is above'; continue }
    $alive = $true
    for ($i = 0; $i -lt $Seconds; $i++) {
        Start-Sleep -Seconds 1
        if ($proc.HasExited) { $alive = $false; break }
    }
    if ($alive) {
        Write-Host "  still running at ${Seconds}s: killing (the window stayed white? for this probe, that is the answer)"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  exited itself after $($i + 1)s, code $($proc.ExitCode)"
    }
    $last = @(Get-Content $errLog -Tail 6 -ErrorAction SilentlyContinue)
    $lines = (Get-Content $errLog -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
    Write-Host "  log: $lines lines -> $errLog"
    Write-Host '  last lines:'
    $last | ForEach-Object { Write-Host "    $_" }
}
Write-Host "`ndone. Send the whole files under $dir, and say for each probe whether F3 showed the frames moving."
