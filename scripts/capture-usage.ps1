# Measurements for a run: samples the machine and the run process once a
# second and writes them to a CSV, so a frame-time claim on the RTX card has
# a usage line beside it (the watchlist's RTX2080 line keeps this habit; the
# script here is ours). Ctrl+C stops it; the CSV is written as it goes.
#   scripts\capture-usage.ps1                                 run's usage-<date>.csv
#   scripts\capture-usage.ps1 -Name victory_sm -Out D:\run.csv -Every 2
# The counters come from CIM (Win32_PerfFormattedData_*), not Get-Counter,
# so they read the same on a Windows of any language. Run beside the game,
# not as administrator; a normal window is enough.
param(
    # The run process's name, without .exe (the script starts a victory_sm.exe
    # copy by default, so the sample catches either).
    [string]$Name = 'victory',
    # Where the CSV goes. Default: usage-<date>.csv in the current folder.
    [string]$Out = '',
    # Seconds between samples.
    [int]$Every = 1
)

if (-not $Out) {
    $Out = "usage-$(Get-Date -Format yyyyMMdd-HHmmss).csv"
}

function Find-Run([string]$name) {
    Get-Process -Name $name -ErrorAction SilentlyContinue |
        Sort-Object StartTime | Select-Object -Last 1
}

# The engine counts of one sample, added up over every instance that is
# really working (the name carries the pid and the engine type).
function Get-GpuPct {
    $sum = 0.0
    foreach ($e in Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction SilentlyContinue) {
        if ($e.UtilizationPercentage -gt 0.5) { $sum += $e.UtilizationPercentage }
    }
    [math]::Min(100, $sum)
}

# The card's memory in use, added up over the shared sections (dedicated +
# shared) of every process on the card.
function Get-GpuMb {
    $sum = 0.0
    foreach ($m in Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory -ErrorAction SilentlyContinue) {
        $sum += $m.LocalUsage
    }
    [math]::Round($sum / 1MB)
}

# The run's part of one CPU core, from the process's own formatted counter.
function Get-RunCpuPct($run) {
    if (-not $run) { return '' }
    $inst = (Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "IDProcess=$($run.Id)" -ErrorAction SilentlyContinue)
    if ($inst) { [math]::Round(($inst | Measure-Object PercentProcessorTime -Sum).Sum / [math]::Max(1, $env:NUMBER_OF_PROCESSORS), 1) } else { '' }
}

# One row a tick: the machine and the run side by side.
"sample,time,cpu_pct,ram_used_mb,ram_free_mb,gpu_pct,vram_mb,run_pid,run_cpu_pct,run_ram_mb" | Set-Content -Path $Out
$n = 0
Write-Host "Sampling every $Every s; the run is '$name*'; Ctrl+C stops. -> $Out"
while ($true) {
    $run = Find-Run $Name
    $os = Get-CimInstance Win32_OperatingSystem
    $totalMb = [math]::Round($os.TotalVisibleMemorySize / 1KB)
    $freeMb = [math]::Round($os.FreePhysicalMemory / 1KB)
    $row = [pscustomobject]@{
        sample      = $n
        time        = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        cpu_pct     = ''        # filled below, one counter query a tick
        ram_used_mb = $totalMb - $freeMb
        ram_free_mb = $freeMb
        gpu_pct     = Get-GpuPct
        vram_mb     = Get-GpuMb
        run_pid     = if ($run) { $run.Id } else { '' }
        run_cpu_pct = Get-RunCpuPct $run
        run_ram_mb  = if ($run) { [math]::Round($run.WorkingSet64 / 1MB) } else { '' }
    }
    $cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
    $row.cpu_pct = if ($cpu) { $cpu.PercentProcessorTime } else { '' }
    $row | Export-Csv -Path $Out -Append -NoTypeInformation
    $n++
    Start-Sleep -Seconds $Every
}
