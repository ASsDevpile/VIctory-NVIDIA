# The XENITH launcher's front end: the window whose layout is xenith.xaml (next
# to this file), with all of its behavior here. Everything underneath goes
# through the launcher's back end, xenith-core.ps1 (dot-sourced): this file
# never sets VICTORY_* variables, never assembles run arguments, and only
# touches xenith.ini through Get-XenithConfig and Set-XenithConfig. Windows
# PowerShell 5.1, WPF, nothing to install. Start it with xenith-ui.cmd or
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File scripts\xenith-ui.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $PSScriptRoot
. .\xenith-core.ps1
Pop-Location

$window = [Windows.Markup.XamlReader]::Parse((Get-Content (Join-Path $PSScriptRoot 'xenith.xaml') -Raw))

$ui = @{}
foreach ($n in @('NavOverview', 'NavNotes', 'NavConsole', 'NavWebsite', 'GpuBadge', 'NoticeBar', 'NoticeText', 'NoticeClose', 'ViewOverview', 'ViewNotes', 'ViewConsole', 'ViewSettings', 'StateDot', 'StateTitle', 'StateSub', 'PreloadStage', 'PreloadProgress', 'BtnPlay', 'BtnStop', 'BtnSettings', 'HealthList', 'VersionText', 'BtnCommunity', 'LinkAllNotes', 'CardSetup', 'CardSetupTitle', 'CardSetupBody', 'CardRun', 'CardRunTitle', 'CardRunBody', 'CardNotes', 'CardNotesTitle', 'CardNotesBody', 'NotesList', 'LogPath', 'BtnLogSave', 'BtnLogCopy', 'BtnLogFolder', 'LogBox', 'TxtGame', 'BtnGameBrowse', 'CmbConsole', 'CmbRes', 'CmbBuild', 'CmbAdapter', 'BtnDetect', 'CmbUpscaler', 'ChkQuality', 'ChkRay', 'ChkPreload', 'ChkPortGuard', 'ChkPortRT', 'ChkMinimize', 'ChkPerfLog', 'TxtPerfInterval', 'TxtCache', 'OpenCache', 'PickCache', 'TxtSaves', 'OpenSaves', 'PickSaves', 'TxtDlss', 'OpenDlss', 'PickDlss', 'TxtLogDir', 'OpenLogDir', 'PickLogDir', 'BtnSave', 'BtnRevert', 'BtnBack', 'SettingsMsg', 'LinkSupport', 'LinkPolicy', 'FooterVer')) {
    $ui[$n] = $window.FindName($n)
}

$script:Brushes = New-Object System.Windows.Media.BrushConverter
$script:BrushOk = $script:Brushes.ConvertFromString('#9BF0CF')
$script:BrushBad = $script:Brushes.ConvertFromString('#FF7B81')
$script:BrushText = $script:Brushes.ConvertFromString('#EEF0F7')

$script:RunId = 0
$script:RunLog = ''
$script:PerfLog = ''
$script:LogKey = ''
$script:RepoUrl = 'https://github.com/ASsDevpile/VIctory-NVIDIA'
$script:Starting = $false
$script:Stopping = $false
$script:PreloadActive = $false
$script:PreloadState = $null
$script:Starter = $null
$script:StartHandle = $null

# --- the small helpers ------------------------------------------------------

function Show-Notice {
    param([string]$Text)
    $ui.NoticeText.Text = $Text
    $ui.NoticeBar.Visibility = 'Visible'
}

function Hide-Notice {
    $ui.NoticeBar.Visibility = 'Collapsed'
}

function Set-View {
    param([string]$Name)
    foreach ($v in @('Overview', 'Notes', 'Console', 'Settings')) {
        if ($v -eq $Name) { $ui[('View' + $v)].Visibility = 'Visible' } else { $ui[('View' + $v)].Visibility = 'Collapsed' }
    }
    foreach ($v in @('Overview', 'Notes', 'Console')) {
        if ($v -eq $Name) { $ui[('Nav' + $v)].Tag = 'active' } else { $ui[('Nav' + $v)].Tag = '' }
    }
}

function ConvertTo-OnOff {
    param([bool]$On)
    if ($On) { 'on' } else { 'off' }
}

function Get-ComboTag {
    param($Combo)
    $item = $Combo.SelectedItem
    if ($item -and $null -ne $item.Tag) { return [string]$item.Tag }
    return ''
}

function Select-ComboByTag {
    param($Combo, [string]$Tag)
    foreach ($item in $Combo.Items) {
        if ([string]$item.Tag -eq $Tag) { $Combo.SelectedItem = $item; return }
    }
    if ($Combo.Items.Count -gt 0) { $Combo.SelectedIndex = 0 }
}

function Get-Commit {
    try {
        $sha = & git -C $repo rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $sha) { return [string]$sha }
    } catch { }
    return 'unknown'
}

function Add-HealthRow {
    param([string]$Label, [bool]$Ok)
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 8
    $dot.Height = 8
    $dot.VerticalAlignment = 'Center'
    if ($Ok) { $dot.Fill = $script:BrushOk } else { $dot.Fill = $script:BrushBad }
    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = $Label
    $text.Margin = '10,0,0,0'
    $text.Foreground = $script:BrushText
    $text.TextWrapping = 'Wrap'
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Orientation = 'Horizontal'
    $panel.Margin = '0,4,0,4'
    $panel.Children.Add($dot) | Out-Null
    $panel.Children.Add($text) | Out-Null
    $ui.HealthList.Children.Add($panel) | Out-Null
}

function Open-LocalPage {
    param([string]$File, [string]$Anchor)
    $page = (Join-Path $repo $File) -replace '\\', '/'
    $url = 'file:///' + $page
    if ($Anchor) { $url = $url + '#' + $Anchor }
    Start-Process $url
}

# --- what the window shows --------------------------------------------------

function Update-Adapters {
    $cards = @(Get-XenithAdapters)
    $selected = [string]$ui.CmbAdapter.SelectedItem
    $ui.CmbAdapter.Items.Clear()
    foreach ($card in $cards) { $ui.CmbAdapter.Items.Add([string]$card.name) | Out-Null }
    if ($cards.Count -gt 0) {
        $ui.GpuBadge.Text = ('{0}  (driver {1})' -f $cards[0].name, $cards[0].driver)
        $want = $selected
        if (-not $want) { $want = [string](Get-XenithConfig)['ADAPTER'] }
        if ($want -and @($cards | Where-Object { $_.name -eq $want }).Count -gt 0) {
            $ui.CmbAdapter.SelectedItem = $want
        } else {
            $ui.CmbAdapter.SelectedIndex = 0
        }
    } else {
        $ui.GpuBadge.Text = 'no graphics card found'
    }
}

function Update-State {
    $setup = Test-XenithSetup
    $cfg = Get-XenithConfig
    $ui.VersionText.Text = ('the runtime: {0}' -f $setup.runtime)

    $ui.HealthList.Children.Clear()
    Add-HealthRow 'the game exe' ([bool]$setup.game_ok)
    Add-HealthRow ('the runtime (target\{0})' -f $setup.build) ([bool]$setup.runtime_ok)
    Add-HealthRow 'the RT skip list (scripts\rt_off_hashes.txt)' ([bool]$setup.rt_list_ok)
    if ($cfg.UPSCALER -eq 'dlss') {
        Add-HealthRow 'the NGX runtime (nvngx_dlss.dll)' ([bool]$setup.dlss_ok)
    }
    if ($cfg.CACHE_DIR) { Add-HealthRow 'the cache folder' (Test-Path $cfg.CACHE_DIR) }
    if ($cfg.SAVES_DIR) { Add-HealthRow 'the saves folder' (Test-Path $cfg.SAVES_DIR) }
    if ($cfg.LOG_DIR) { Add-HealthRow 'the log folder' (Test-Path $cfg.LOG_DIR) }

    $missing = @()
    if (-not $setup.game_ok) { $missing += 'the game exe (Settings > Title)' }
    if (-not $setup.runtime_ok) {
        if ($cfg.UPSCALER -eq 'dlss') {
            $missing += 'the DLSS runtime: set VICTORY_DLSS_SDK to the NVIDIA SDK root, then cargo build --locked --profile diag -p victory --features diagnostics,dlss'
        } else {
            $missing += 'the runtime: cargo build --locked --profile diag -p victory --features diagnostics'
        }
    }
    if (-not $setup.rt_list_ok) { $missing += 'the RT skip list: scripts\rt_off_hashes.txt' }

    if ($missing.Count -eq 0) {
        $ui.StateDot.Fill = $script:BrushOk
        $ui.StateTitle.Text = 'Ready to play'
        $ui.StateSub.Text = 'Everything a run needs is in place. The console view shows the log while it plays.'
        $ui.CardSetupTitle.Text = 'Ready to play'
        $ui.CardSetupBody.Text = 'The title, the runtime and the skip list are all found.'
    } else {
        $ui.StateDot.Fill = $script:BrushBad
        $ui.StateTitle.Text = 'Needs setup'
        $ui.StateSub.Text = ($missing -join '; ')
        $ui.CardSetupTitle.Text = 'Needs setup'
        $ui.CardSetupBody.Text = ($missing -join '; ')
    }
    $ui.BtnPlay.IsEnabled = ($missing.Count -eq 0)

    if ($cfg.UPSCALER -eq 'dlss') {
        if (-not $setup.dlss_ok) {
            Show-Notice ('DLSS requires a --features diagnostics,dlss build with VICTORY_DLSS_SDK. nvngx_dlss.dll was not found in {0}, so the title''s FFX upscaler will run; set Settings to a folder containing the NVIDIA runtime DLL to enable DLSS.' -f $setup.dlss_dir)
        } else {
            Show-Notice 'DLSS Super Resolution is experimental. The runtime must be built with --features diagnostics,dlss and VICTORY_DLSS_SDK; failures fall back to the title''s FFX upscaler. Frame Generation is not included.'
        }
    } else {
        Hide-Notice
    }
}

function Update-PlayCard {
    $set = Get-XenithPlaySet
    $cfg = Get-XenithConfig
    $which = 'Series S'
    if ($set.series_x) { $which = 'Series X' }
    $up = 'the fork''s own upscaler'
    if ($cfg.UPSCALER -eq 'dlss') { $up = 'DLSS SR (experimental; FFX fallback)' }
    elseif ($cfg.UPSCALER) { $up = $cfg.UPSCALER }
    $rtPort = ''
    if ($cfg.PORT_RT -eq 'on') { $rtPort = '; experimental RT ordering on' }
    $ui.CardRunTitle.Text = ('{0}, rendering at {1}p' -f $which, $cfg.RESOLUTION)
    $ui.CardRunBody.Text = ('render scale {0}, {1}{2}; play set mirrored from play-nvidia.ps1' -f $set.render_scale, $up, $rtPort)
}

function Update-Notes {
    $rows = @()
    try {
        $raw = & git -C $repo log -20 --date=short --pretty=format:'%cs|%h|%s' 2>$null
        if ($LASTEXITCODE -eq 0) { $rows = @($raw) }
    } catch { $rows = @() }

    $ui.NotesList.Children.Clear()
    $first = $true
    foreach ($row in $rows) {
        $i1 = $row.IndexOf('|')
        $i2 = $row.IndexOf('|', $i1 + 1)
        if ($i1 -lt 1 -or $i2 -lt 0) { continue }
        $date = $row.Substring(0, $i1)
        $hash = $row.Substring($i1 + 1, $i2 - $i1 - 1)
        $what = $row.Substring($i2 + 1)

        $head = New-Object System.Windows.Controls.TextBlock
        $run = New-Object System.Windows.Documents.Run
        $run.Text = $hash
        $run.Foreground = $script:BrushOk
        $head.Inlines.Add($run) | Out-Null
        $head.Inlines.Add(('   {0}' -f $date)) | Out-Null
        $head.Opacity = 0.75
        $head.FontSize = 12

        $body = New-Object System.Windows.Controls.TextBlock
        $body.Text = $what
        $body.TextWrapping = 'Wrap'
        $body.Margin = '0,2,0,0'

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.Children.Add($head) | Out-Null
        $stack.Children.Add($body) | Out-Null

        $border = New-Object System.Windows.Controls.Border
        $border.BorderBrush = $script:Brushes.ConvertFromString('#25263D')
        $border.BorderThickness = '0,0,0,1'
        $border.Padding = '0,12'
        $border.Child = $stack
        $ui.NotesList.Children.Add($border) | Out-Null

        if ($first) {
            $ui.CardNotesTitle.Text = $what
            $ui.CardNotesBody.Text = ('{0}   {1}' -f $date, $hash)
            $first = $false
        }
    }
    if ($first) {
        $ui.CardNotesTitle.Text = 'No notes yet'
        $ui.CardNotesBody.Text = ''
    }
}

# --- starting, stopping, the log ---------------------------------------------

function Set-Running {
    param([bool]$On)
    if ($On) {
        $ui.BtnPlay.Visibility = 'Collapsed'
        $ui.BtnStop.Visibility = 'Visible'
    } else {
        $ui.BtnStop.Visibility = 'Collapsed'
        $ui.BtnPlay.Visibility = 'Visible'
    }
}

function Start-Run {
    if ($script:Starting) { return }
    $skipPreload = $false
    if ((Get-XenithConfig).PRELOAD -eq 'on') {
        $answer = [System.Windows.MessageBox]::Show(
            $window,
            'Run shader translation and warm the pipeline cache before starting? Existing cache entries are reused; the first pass or a cache refresh can take several minutes. Choose No to launch without preloading this time.',
            'Preload before launch',
            [System.Windows.MessageBoxButton]::YesNoCancel,
            [System.Windows.MessageBoxImage]::Question
        )
        if ($answer -eq [System.Windows.MessageBoxResult]::Cancel) { return }
        $skipPreload = $answer -eq [System.Windows.MessageBoxResult]::No
    }
    $script:Starting = $true
    $script:Stopping = $false
    $script:PreloadActive = ((Get-XenithConfig).PRELOAD -eq 'on') -and -not $skipPreload
    $script:PreloadState = [hashtable]::Synchronized(@{ phase = 'preparing' })
    $ui.BtnPlay.IsEnabled = $false
    $ui.StateTitle.Text = 'Starting...'
    $ui.StateSub.Text = 'the back end is preparing the run'
    if ($script:PreloadActive) {
        $ui.PreloadStage.Text = 'Preparing shader and pipeline caches...'
        $ui.PreloadStage.Visibility = 'Visible'
        $ui.PreloadProgress.Visibility = 'Visible'
    } else {
        $ui.PreloadStage.Visibility = 'Collapsed'
        $ui.PreloadProgress.Visibility = 'Collapsed'
    }
    $script:Starter = [powershell]::Create()
    $script:Starter.Runspace = [runspacefactory]::CreateRunspace()
    $script:Starter.Runspace.Open() | Out-Null
    [void]$script:Starter.AddScript('param($dir, $state, $skip); Set-Location $dir; . .\xenith-core.ps1; Start-XenithRun -ProgressState $state -SkipPreload:$skip')
    [void]$script:Starter.AddArgument($PSScriptRoot)
    [void]$script:Starter.AddArgument($script:PreloadState)
    [void]$script:Starter.AddArgument($skipPreload)
    $script:StartHandle = $script:Starter.BeginInvoke()
    $startTimer.Start()
}

function Stop-Run {
    if ($script:RunId -gt 0) {
        try { Stop-XenithRun -Id $script:RunId | Out-Null } catch { }
    }
    Get-Process victory*, victory_sm* -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
    if ($script:Starting) { $script:Stopping = $true }
    $script:RunId = 0
    if ($script:PerfLog) {
        Show-Notice ('Performance CSV saved to {0}' -f $script:PerfLog)
        $script:PerfLog = ''
    }
    $timer.Stop()
    Set-Running $false
    Update-State
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    if ($script:RunId -gt 0) {
        $alive = @(Get-Process -Id $script:RunId -ErrorAction SilentlyContinue).Count -gt 0
        if (-not $alive) {
            $script:RunId = 0
            $perfLog = $script:PerfLog
            $script:PerfLog = ''
            $timer.Stop()
            Set-Running $false
            Update-State
            if ($perfLog) {
                Show-Notice ('Performance CSV saved to {0}' -f $perfLog)
            } else {
                Show-Notice 'The run ended. Its whole log is saved next to the console path above.'
            }
            return
        }
    }
    if ($script:RunLog) {
        try {
            $log = Get-XenithRunLog -Path $script:RunLog -Tail 120
            $key = ''
            if ($log.lines.Count -gt 0) { $key = ('{0}|{1}' -f $log.lines.Count, $log.lines[$log.lines.Count - 1]) }
            if ($key -ne $script:LogKey) {
                $script:LogKey = $key
                $ui.LogBox.Text = ($log.lines -join "`r`n")
                $ui.LogBox.CaretIndex = $ui.LogBox.Text.Length
                $ui.LogBox.ScrollToEnd()
            }
        } catch { }
    }
})

$startTimer = New-Object System.Windows.Threading.DispatcherTimer
$startTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$startTimer.Add_Tick({
    if (-not $script:StartHandle) { return }
    if (-not $script:StartHandle.IsCompleted) {
        if ($script:PreloadActive) {
            $phase = [string]$script:PreloadState['phase']
            switch ($phase) {
                'translating' { $ui.PreloadStage.Text = 'Translating shader cache...' }
                'warming' { $ui.PreloadStage.Text = 'Warming the pipeline cache...' }
                'launching' { $ui.PreloadStage.Text = 'Starting the game...' }
                default { $ui.PreloadStage.Text = 'Preparing shader and pipeline caches...' }
            }
        }
        return
    }
    $startTimer.Stop()
    $ui.PreloadProgress.Visibility = 'Collapsed'
    $ui.PreloadStage.Visibility = 'Collapsed'
    $script:PreloadActive = $false
    $run = $null
    $failed = ''
    try {
        $out = $script:Starter.EndInvoke($script:StartHandle)
        if ($out -and $out.Count -gt 0) { $run = $out[0] }
    } catch {
        $failed = $_.Exception.Message
    }
    if (-not $failed) {
        foreach ($e in $script:Starter.Streams.Error) { $failed = [string]$e; break }
    }
    $script:Starter.Dispose()
    $script:Starter = $null
    $script:StartHandle = $null
    $script:Starting = $false
    if ($run) {
        $script:RunId = [int]$run.pid
        $script:RunLog = [string]$run.log
        $script:PerfLog = ''
        if ($run.perf_log -and -not $run.perf_error) { $script:PerfLog = [string]$run.perf_log }
        $script:LogKey = ''
        $ui.LogPath.Text = $script:RunLog
        $ui.LogBox.Text = ''
        Set-Running $true
        Set-View 'Console'
        $timer.Start()
        if ($run.perf_log) {
            if ($run.perf_error) {
                Show-Notice ('The game started, but its performance sampler could not start: {0}' -f $run.perf_error)
            } else {
                Show-Notice ('Performance samples will be saved to {0}' -f $run.perf_log)
            }
        }
        if ((Get-XenithConfig)['MINIMIZE'] -eq 'on') { $window.WindowState = 'Minimized' }
    } else {
        if (-not $script:Stopping) { Show-Notice ('the run did not start: {0}' -f $failed) }
        $script:Stopping = $false
        Update-State
    }
})

# --- the console view ---------------------------------------------------------

function Save-RunLog {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.FileName = 'victory-run.log'
    $dlg.Filter = 'Log files (*.log)|*.log|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -eq $true) {
        try {
            Save-XenithLog -Destination $dlg.FileName -Path $script:RunLog | Out-Null
            $ui.SettingsMsg.Text = ''
            Show-Notice ('The log is saved at {0}.' -f $dlg.FileName)
        } catch {
            Show-Notice $_.Exception.Message
        }
    }
}

# --- the settings view ---------------------------------------------------------

function Update-SettingsUi {
    $cfg = Get-XenithConfig
    $ui.TxtGame.Text = [string]$cfg['GAME']
    Select-ComboByTag $ui.CmbConsole ([string]$cfg['CONSOLE'])
    Select-ComboByTag $ui.CmbRes ([string]$cfg['RESOLUTION'])
    Select-ComboByTag $ui.CmbBuild ([string]$cfg['BUILD'])
    Select-ComboByTag $ui.CmbUpscaler ([string]$cfg['UPSCALER'])
    $ui.ChkQuality.IsChecked = ([string]$cfg['QUALITY'] -eq 'on')
    $ui.ChkRay.IsChecked = ([string]$cfg['RAYTRACING'] -eq 'on')
    $ui.ChkPreload.IsChecked = ([string]$cfg['PRELOAD'] -eq 'on')
    $ui.ChkPortGuard.IsChecked = ([string]$cfg['PORT_GUARD'] -eq 'on')
    $ui.ChkPortRT.IsChecked = ([string]$cfg['PORT_RT'] -eq 'on')
    $ui.ChkMinimize.IsChecked = ([string]$cfg['MINIMIZE'] -eq 'on')
    $ui.ChkPerfLog.IsChecked = ([string]$cfg['PERF_LOG'] -eq 'on')
    $ui.TxtPerfInterval.Text = [string]$cfg['PERF_INTERVAL']
    $ui.TxtCache.Text = [string]$cfg['CACHE_DIR']
    $ui.TxtSaves.Text = [string]$cfg['SAVES_DIR']
    $ui.TxtDlss.Text = [string]$cfg['DLSS_DIR']
    $ui.TxtLogDir.Text = [string]$cfg['LOG_DIR']
    $want = [string]$cfg['ADAPTER']
    if ($want -and $ui.CmbAdapter.Items.Contains($want)) { $ui.CmbAdapter.SelectedItem = $want }
    $ui.SettingsMsg.Text = ''
}

function Save-Settings {
    $patch = @{}
    $patch['GAME'] = $ui.TxtGame.Text.Trim()
    $patch['CONSOLE'] = Get-ComboTag $ui.CmbConsole
    $patch['RESOLUTION'] = Get-ComboTag $ui.CmbRes
    $patch['BUILD'] = Get-ComboTag $ui.CmbBuild
    $patch['UPSCALER'] = Get-ComboTag $ui.CmbUpscaler
    $patch['ADAPTER'] = [string]$ui.CmbAdapter.SelectedItem
    $patch['QUALITY'] = ConvertTo-OnOff ([bool]$ui.ChkQuality.IsChecked)
    $patch['RAYTRACING'] = ConvertTo-OnOff ([bool]$ui.ChkRay.IsChecked)
    $patch['PRELOAD'] = ConvertTo-OnOff ([bool]$ui.ChkPreload.IsChecked)
    $patch['PORT_GUARD'] = ConvertTo-OnOff ([bool]$ui.ChkPortGuard.IsChecked)
    $patch['PORT_RT'] = ConvertTo-OnOff ([bool]$ui.ChkPortRT.IsChecked)
    $patch['MINIMIZE'] = ConvertTo-OnOff ([bool]$ui.ChkMinimize.IsChecked)
    $patch['PERF_LOG'] = ConvertTo-OnOff ([bool]$ui.ChkPerfLog.IsChecked)
    $perfEvery = 0
    $validPerfInterval = [int]::TryParse($ui.TxtPerfInterval.Text.Trim(), [ref]$perfEvery)
    if (-not $validPerfInterval -or $perfEvery -lt 1 -or $perfEvery -gt 60) {
        $ui.SettingsMsg.Text = 'Perf log interval must be 1-60 whole seconds'
        return
    }
    $patch['PERF_INTERVAL'] = [string]$perfEvery
    $patch['CACHE_DIR'] = $ui.TxtCache.Text.Trim()
    $patch['SAVES_DIR'] = $ui.TxtSaves.Text.Trim()
    $patch['DLSS_DIR'] = $ui.TxtDlss.Text.Trim()
    $patch['LOG_DIR'] = $ui.TxtLogDir.Text.Trim()
    try {
        Set-XenithConfig -Setting $patch | Out-Null
        $ui.SettingsMsg.Text = 'saved'
        Update-State
        Update-PlayCard
    } catch {
        $ui.SettingsMsg.Text = $_.Exception.Message
    }
}

function Pick-GameExe {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Game executables (*.exe)|*.exe|All files (*.*)|*.*'
    if ($dlg.ShowDialog() -eq $true) { $ui.TxtGame.Text = $dlg.FileName }
}

function Pick-Folder {
    param([System.Windows.Controls.TextBox]$Box)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $Box.Text = $dlg.SelectedPath }
}

function Open-Folder {
    param([string]$Name)
    try { Open-XenithFolder -Name $Name | Out-Null } catch { Show-Notice $_.Exception.Message }
}

# --- wire the window up ---------------------------------------------------------

$ui.NavOverview.Add_Click({ Set-View 'Overview' })
$ui.NavNotes.Add_Click({ Set-View 'Notes' })
$ui.NavConsole.Add_Click({ Set-View 'Console' })
$ui.NavWebsite.Add_Click({ Open-LocalPage 'docs\index.html' '' })
$ui.BtnSettings.Add_Click({ Update-SettingsUi; Set-View 'Settings' })
$ui.BtnBack.Add_Click({ Set-View 'Overview' })
$ui.BtnPlay.Add_Click({ Start-Run })
$ui.BtnStop.Add_Click({ Stop-Run })
$ui.NoticeClose.Add_Click({ Hide-Notice })
$ui.LinkAllNotes.Add_Click({ Set-View 'Notes' })
$ui.CardNotes.Add_MouseLeftButtonUp({ Set-View 'Notes' })
$ui.CardSetup.Add_MouseLeftButtonUp({ Update-SettingsUi; Set-View 'Settings' })
$ui.CardRun.Add_MouseLeftButtonUp({ Update-SettingsUi; Set-View 'Settings' })
$ui.BtnCommunity.Add_Click({ Start-Process $script:RepoUrl })

$ui.BtnLogSave.Add_Click({ Save-RunLog })
$ui.BtnLogCopy.Add_Click({
    try { [Windows.Clipboard]::SetText($ui.LogBox.Text) } catch { Show-Notice $_.Exception.Message }
})
$ui.BtnLogFolder.Add_Click({ Open-Folder 'log' })

$ui.BtnGameBrowse.Add_Click({ Pick-GameExe })
$ui.BtnDetect.Add_Click({ Update-Adapters; $ui.SettingsMsg.Text = 'cards found again' })
$ui.OpenCache.Add_Click({ Open-Folder 'cache' })
$ui.OpenSaves.Add_Click({ Open-Folder 'saves' })
$ui.OpenDlss.Add_Click({ Open-Folder 'dlss' })
$ui.OpenLogDir.Add_Click({ Open-Folder 'log' })
$ui.PickCache.Add_Click({ Pick-Folder $ui.TxtCache })
$ui.PickSaves.Add_Click({ Pick-Folder $ui.TxtSaves })
$ui.PickDlss.Add_Click({ Pick-Folder $ui.TxtDlss })
$ui.PickLogDir.Add_Click({ Pick-Folder $ui.TxtLogDir })
$ui.BtnSave.Add_Click({ Save-Settings })
$ui.BtnRevert.Add_Click({ Update-SettingsUi })

$ui.LinkSupport.Add_Click({ Open-LocalPage 'docs\index.html' 'troubleshooting' })
$ui.LinkPolicy.Add_Click({ Open-LocalPage 'docs\asset-policy.md' '' })

$window.Add_Closing({ $timer.Stop(); $startTimer.Stop() })

# --- first paint -----------------------------------------------------------------

Set-View 'Overview'
Update-Adapters
Update-State
Update-PlayCard
Update-Notes
$ui.FooterVer.Text = ('Xenith  |  xenith-core 1  |  commit {0}' -f (Get-Commit))
try {
    $latest = Get-XenithRunLog -Tail 1
    if (-not $script:RunLog) { $ui.LogPath.Text = [string]$latest.path }
} catch { }

[void]$window.ShowDialog()
