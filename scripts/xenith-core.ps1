# The launcher's back end: everything a launcher front end needs from this
# fork, and nothing about how it looks. Dot-source it for the functions, or
# run it as a CLI and read JSON:
#   . .\scripts\xenith-core.ps1                          (functions)
#   powershell -File scripts\xenith-core.ps1 status      (CLI, JSON out)
#   powershell -File scripts\xenith-core.ps1 start
# Commands: status, config, adapters, playset, start, stop, tail, open,
#           save-log, version
# The front end must not set VICTORY_* variables, assemble run arguments, or
# touch the cache layout itself: everything of that kind goes through here, so
# the play set lives in one place (this file mirrors scripts\play-nvidia.ps1;
# when one moves, the other moves with it).

$script:XenithDefaults = @{
    GAME        = ''
    RESOLUTION  = '720'
    ADAPTER     = ''
    QUALITY     = 'off'
    RAYTRACING  = 'off'
    BUILD       = 'diag'
    SKIP        = 'none'
    UPSCALER    = ''
    CONSOLE     = 'S'
    PRELOAD     = 'off'
    CACHE_DIR   = ''
    SAVES_DIR   = ''
    DLSS_DIR    = ''
    LOG_DIR     = ''
    LOG_LEVEL   = 'info'
}

function Get-XenithRepo {
    (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-XenithConfigPath {
    Join-Path (Get-XenithRepo) 'xenith.ini'
}

function Get-XenithConfig {
    $cfg = @{}
    foreach ($k in $script:XenithDefaults.Keys) { $cfg[$k] = $script:XenithDefaults[$k] }
    $path = Get-XenithConfigPath
    if (Test-Path $path) {
        foreach ($line in Get-Content $path) {
            $t = $line.Trim()
            if ($t.Length -eq 0 -or $t.StartsWith('#') -or -not $t.Contains('=')) { continue }
            $k = $t.Substring(0, $t.IndexOf('=')).Trim().ToUpperInvariant()
            $v = $t.Substring($t.IndexOf('=') + 1).Trim()
            $cfg[$k] = $v
        }
    }
    $cfg
}

function Set-XenithConfig {
    param([hashtable]$Setting)
    $cfg = Get-XenithConfig
    foreach ($k in $Setting.Keys) { $cfg[$k.ToUpperInvariant()] = [string]$Setting[$k] }
    $lines = @('# Xenith launcher configuration')
    foreach ($k in ($cfg.Keys | Sort-Object)) { $lines += ("{0}={1}" -f $k, $cfg[$k]) }
    Set-Content -Path (Get-XenithConfigPath) -Value $lines -Encoding ASCII
    $cfg
}

function Get-XenithAdapters {
    $gpus = @(Get-CimInstance -ClassName Win32_VideoController | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            driver = $_.DriverVersion
            nvidia = ($_.Name -match 'NVIDIA')
        }
    })
    @($gpus | Sort-Object -Property @{Expression = 'nvidia'; Descending = $true}, @{Expression = 'name'; Descending = $false}) | ForEach-Object { $_ }
}

function Get-XenithVictoryExe {
    param([string]$Build = 'diag')
    Join-Path (Get-XenithRepo) ("target\" + $Build + "\victory.exe")
}

function Test-XenithSetup {
    $cfg = Get-XenithConfig
    $repo = Get-XenithRepo
    $exe = Get-XenithVictoryExe -Build $cfg.BUILD
    $rtList = Join-Path $PSScriptRoot 'rt_off_hashes.txt'
    $dlssOk = $true
    $dlssDir = $cfg.DLSS_DIR
    if ($cfg.UPSCALER -eq 'dlss') {
        if (-not $dlssDir) { $dlssDir = Join-Path $repo 'dlss' }
        $dlssOk = (Test-Path (Join-Path $dlssDir 'nvngx_dlss.dll')) -and (Test-Path (Join-Path $dlssDir 'nvngx.dll'))
    }
    [pscustomobject]@{
        game_ok        = ($cfg.GAME -and (Test-Path $cfg.GAME))
        runtime_ok     = (Test-Path $exe)
        runtime        = $exe
        rt_list_ok     = (Test-Path $rtList)
        dlss_ok        = $dlssOk
        dlss_dir       = $dlssDir
        cache_dir      = $cfg.CACHE_DIR
        saves_dir      = $cfg.SAVES_DIR
        log_dir        = $cfg.LOG_DIR
        game           = $cfg.GAME
        build          = $cfg.BUILD
        console        = $cfg.CONSOLE
    }
}

function Get-XenithPlaySet {
    $cfg = Get-XenithConfig
    $seriesX = ($cfg.CONSOLE -eq 'X')
    $outHeight = 1080
    if ($seriesX) { $outHeight = 2160 }
    $settings = @{
        VICTORY_TEXTURE_NO_WAIT = '1'; VICTORY_RELAY = '2'; VICTORY_CARD_STEPS = '2'
        VICTORY_WIDE_BACK = '1'; VICTORY_CARD_REHASH_RUNS = '1'
        VICTORY_JOIN_COPIES = '1'; VICTORY_INDIRECT_WINDOW = '1'; VICTORY_RELAY_COPY = '1'
        VICTORY_INDIRECT_BATCH = '2'; VICTORY_MAP_THREADS = '1'; VICTORY_TITLE_PRIORITIES = '0'; VICTORY_CARD_AWAKE = '1'
        VICTORY_SHOW_AFTER = '1'; VICTORY_AMBIENT = '0.8'; VICTORY_D3D12_DRED = 'light'; VICTORY_SKIP_PIPELINES = 'none'
        VICTORY_THIN = '1'; VICTORY_JOIN_PARTS = '8'; VICTORY_UPLOAD_AHEAD = '1'
        VICTORY_AMBIENT_AIR = '1.5'; VICTORY_AMBIENT_MOST = '2'; VICTORY_NAN_SCRUB = '1'
        VICTORY_PIPELINE_WAIT_MS = '10000'; VICTORY_DYNAMIC_SLOTS = '524288'
        VICTORY_RENDER_SCALE = '0.5'; VICTORY_OWN_UPSCALER = '1'
        VICTORY_BVH_MISS = '1'
        VICTORY_CARD_BUFFERS_MIN_MB = '1'; VICTORY_CARD_BUFFERS_MB = '1536'
        VICTORY_COMPOSE = '1'
    }
    $rtList = Join-Path $PSScriptRoot 'rt_off_hashes.txt'
    if ($cfg.RAYTRACING -ne 'on' -and (Test-Path $rtList)) {
        $settings.VICTORY_SKIP_PIPELINES = (Get-Content $rtList -Raw).Trim()
    }
    if ($cfg.QUALITY -eq 'on') {
        $settings.VICTORY_RELAY = '1'; $settings.VICTORY_CARD_STEPS = '0'; $settings.VICTORY_TEXTURE_NO_WAIT = '0'
    }
    if ($cfg.RESOLUTION) {
        $settings.VICTORY_RENDER_SCALE = ([int]$cfg.RESOLUTION / $outHeight).ToString('0.####', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($cfg.UPSCALER) { $settings.VICTORY_UPSCALER = $cfg.UPSCALER.ToLowerInvariant() }
    if ($cfg.ADAPTER) { $settings.VICTORY_D3D12_ADAPTER = $cfg.ADAPTER }
    if ($cfg.CACHE_DIR) { $settings.VICTORY_CACHE_DIR = $cfg.CACHE_DIR }
    if ($cfg.SAVES_DIR) { $settings.VICTORY_SAVES_DIR = $cfg.SAVES_DIR }
    [pscustomobject]@{
        settings = $settings
        exe      = (Get-XenithVictoryExe -Build $cfg.BUILD)
        series_x = $seriesX
        render_scale = $settings.VICTORY_RENDER_SCALE
    }
}

function Start-XenithRun {
    param([switch]$Preload)
    $cfg = Get-XenithConfig
    $setup = Get-XenithPlaySet
    $exe = $setup.exe
    if (-not (Test-Path $exe)) { throw ("no runtime at {0}: build first" -f $exe) }
    if (-not ($cfg.GAME -and (Test-Path $cfg.GAME))) { throw 'no game exe in the configuration' }
    $game = (Resolve-Path $cfg.GAME).Path
    $repo = Get-XenithRepo
    $logDir = $cfg.LOG_DIR
    if (-not $logDir) { $logDir = Join-Path $repo 'debug-runs' }
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $logFile = Join-Path $logDir ("victory-run-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    Get-ChildItem Env:VICTORY_* -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item ("Env:" + $_.Name) -ErrorAction SilentlyContinue }
    $logLevel = $cfg.LOG_LEVEL
    if (-not $logLevel) { $logLevel = 'info' }
    $env:VICTORY_LOG = $logLevel.ToLowerInvariant()
    foreach ($k in $setup.settings.Keys) { Set-Item ("Env:" + $k) $setup.settings[$k] }
    $sm = Join-Path (Split-Path $exe) 'victory_sm.exe'
    if (-not (Test-Path $sm) -or (Get-Item $sm).LastWriteTime -lt (Get-Item $exe).LastWriteTime) {
        Copy-Item $exe $sm -Force
    }
    $victory = $sm
    if ($Preload -or $cfg.PRELOAD -eq 'on') {
        $env:VICTORY_GAME_DIR = Split-Path $game
        $warm = Start-Process -FilePath $victory -ArgumentList 'translate' -WorkingDirectory $repo -NoNewWindow -Wait -PassThru
        if ($warm.ExitCode -ne 0) { throw ("translate failed with code {0}" -f $warm.ExitCode) }
        $warm = Start-Process -FilePath $victory -ArgumentList 'warm' -WorkingDirectory $repo -NoNewWindow -Wait -PassThru
        if ($warm.ExitCode -ne 0) { throw ("warm failed with code {0}" -f $warm.ExitCode) }
    }
    $runArgs = @('run', ('"' + $game + '"'), '--execute')
    if (-not $setup.series_x) { $runArgs += @('--console', 'series-s') }
    $proc = Start-Process -FilePath $victory -ArgumentList $runArgs -WorkingDirectory $repo -NoNewWindow -RedirectStandardOutput ($logFile + '.out') -RedirectStandardError $logFile -PassThru
    [pscustomobject]@{
        pid      = $proc.Id
        exe      = $victory
        log      = $logFile
        started  = (Get-Date)
        render_scale = $setup.render_scale
    }
}

function Stop-XenithRun {
    param([int]$Id)
    $procs = @(Get-Process -Id $Id -ErrorAction SilentlyContinue)
    foreach ($p in $procs) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    if ($procs.Count -eq 0) { throw ("no running process with id {0}" -f $Id) }
    Get-Process victory*, victory_sm* -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    [pscustomobject]@{ stopped = $Id }
}

function Get-XenithRunLog {
    param([string]$Path, [int]$Tail = 40)
    if (-not $Path) {
        $cfg = Get-XenithConfig
        $logDir = $cfg.LOG_DIR
        if (-not $logDir) { $logDir = Join-Path (Get-XenithRepo) 'debug-runs' }
        $latest = @(Get-ChildItem $logDir -Filter 'victory-run-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($latest.Count -eq 0) { throw 'no run logs yet' }
        $Path = $latest[0].FullName
    }
    [pscustomobject]@{
        path = $Path
        lines = @(Get-Content $Path -Tail $Tail -ErrorAction SilentlyContinue)
    }
}

function Save-XenithLog {
    param([string]$Destination, [string]$Path)
    $log = Get-XenithRunLog -Path $Path -Tail 0
    Copy-Item $log.path $Destination -Force
    [pscustomobject]@{ saved_to = (Resolve-Path $Destination).Path }
}

function Open-XenithFolder {
    param([ValidateSet('cache','saves','dlss','game','log','repo')][string]$Name)
    $cfg = Get-XenithConfig
    $repo = Get-XenithRepo
    $target = $repo
    if ($Name -eq 'cache') { $target = $cfg.CACHE_DIR }
    if ($Name -eq 'saves') { $target = $cfg.SAVES_DIR }
    if ($Name -eq 'dlss') {
        $target = $cfg.DLSS_DIR
        if (-not $target) { $target = Join-Path $repo 'dlss' }
    }
    if ($Name -eq 'game') { $target = Split-Path $cfg.GAME }
    if ($Name -eq 'log') {
        $target = $cfg.LOG_DIR
        if (-not $target) { $target = Join-Path $repo 'debug-runs' }
    }
    if (-not ($target -and (Test-Path $target))) { throw ("the {0} folder does not exist yet" -f $Name) }
    Start-Process explorer.exe $target
    [pscustomobject]@{ opened = (Resolve-Path $target).Path }
}

# Run as a CLI (not dot-sourced): every command answers in JSON so a front end
# in any language can call this file with powershell -File and read the answer.
if ($MyInvocation.InvocationName -ne '.') {
    $cmd = $args[0]
    try {
        $out = $null
        if ($cmd -eq 'status') { $out = Test-XenithSetup }
        elseif ($cmd -eq 'config') {
            if ($args[1] -eq 'set') {
                $patch = @{}
                foreach ($pair in ($args | Select-Object -Skip 2)) {
                    $i = $pair.IndexOf('=')
                    if ($i -gt 0) { $patch[$pair.Substring(0, $i)] = $pair.Substring($i + 1) }
                }
                $out = Set-XenithConfig -Setting $patch
            } else { $out = Get-XenithConfig }
        }
        elseif ($cmd -eq 'adapters') { $out = Get-XenithAdapters }
        elseif ($cmd -eq 'playset') { $out = Get-XenithPlaySet }
        elseif ($cmd -eq 'start') { $out = Start-XenithRun }
        elseif ($cmd -eq 'stop') { $out = Stop-XenithRun -Id ([int]$args[1]) }
        elseif ($cmd -eq 'tail') {
            $tailCount = 40
            if ($args[1]) { $tailCount = [int]$args[1] }
            $out = Get-XenithRunLog -Tail $tailCount
        }
        elseif ($cmd -eq 'open') { $out = Open-XenithFolder -Name $args[1] }
        elseif ($cmd -eq 'save-log') { $out = Save-XenithLog -Destination $args[1] }
        elseif ($cmd -eq 'version') {
            $out = [pscustomobject]@{
                core = 'xenith-core 1'
                repo = (Get-XenithRepo)
            }
        }
        else { throw ("unknown command '{0}' (status, config, adapters, playset, start, stop, tail, open, save-log, version)" -f $cmd) }
        $out | ConvertTo-Json -Depth 4
    } catch {
        [pscustomobject]@{ error = $_.Exception.Message } | ConvertTo-Json -Depth 4
        exit 1
    }
}
