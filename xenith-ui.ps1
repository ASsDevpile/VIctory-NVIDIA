# The graphical XENITH VI launcher, this fork's copy: the same settings and
# xenith.ini as xenith.cmd, in a window. Windows PowerShell 5.1, WPF, nothing
# to install. The modes of Xenith's own launcher become this fork's RTX
# settings; a run is scripts\play-nvidia.ps1, so its settings stay in one
# place.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# --- settings ------------------------------------------------------------

$IniPath = Join-Path $PSScriptRoot 'xenith.ini'
$Keys = @('GAME', 'RESOLUTION', 'ADAPTER', 'QUALITY', 'RAYTRACING', 'BUILD', 'SKIP')

function Read-Ini {
    $s = @{}
    foreach ($k in $Keys) { $s[$k] = '' }
    $s['QUALITY'] = 'on'
    $s['RAYTRACING'] = 'off'
    $s['BUILD'] = 'diag'
    if (Test-Path -LiteralPath $IniPath) {
        foreach ($line in Get-Content -LiteralPath $IniPath) {
            $i = $line.IndexOf('=')
            if ($i -lt 1) { continue }
            $key = $line.Substring(0, $i).Trim()
            if ($s.ContainsKey($key)) { $s[$key] = $line.Substring($i + 1) }
        }
    }
    return $s
}

function Save-Ini {
    param([hashtable]$s)
    $lines = foreach ($k in $Keys) { '{0}={1}' -f $k, $s[$k] }
    Set-Content -LiteralPath $IniPath -Value $lines -Encoding Default
}

# --- window --------------------------------------------------------------

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="XENITH VI for an RTX card" Height="620" Width="900"
        WindowStartupLocation="CenterScreen" Background="#0B0D14"
        Foreground="#E7E9F5" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="XENITH VI - RTX" FontSize="22" FontWeight="Bold" Margin="0,0,0,10">
      <TextBlock.Foreground>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
          <GradientStop Color="#4A90E2" Offset="0"/>
          <GradientStop Color="#9013FE" Offset="0.5"/>
          <GradientStop Color="#76B900" Offset="1"/>
        </LinearGradientBrush>
      </TextBlock.Foreground>
    </TextBlock>
    <GroupBox Grid.Row="1" Header="Settings" Foreground="#9AA1C0" Margin="0,0,0,10">
      <Grid Margin="8">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="110"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="90"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition/><RowDefinition/><RowDefinition/><RowDefinition/>
          <RowDefinition/><RowDefinition/>
        </Grid.RowDefinitions>
        <TextBlock Grid.Row="0" Grid.Column="0" Text="Game path" VerticalAlignment="Center"/>
        <TextBox Grid.Row="0" Grid.Column="1" x:Name="TxtGame" Margin="0,3"/>
        <Button Grid.Row="0" Grid.Column="2" x:Name="BtnGame" Content="Browse..." Margin="6,3,0,3"/>
        <TextBlock Grid.Row="1" Grid.Column="0" Text="Build" VerticalAlignment="Center"/>
        <ComboBox Grid.Row="1" Grid.Column="1" x:Name="CmbBuild" Margin="0,3" Width="160" HorizontalAlignment="Left">
          <ComboBoxItem Content="diag"/><ComboBoxItem Content="release"/>
        </ComboBox>
        <TextBlock Grid.Row="2" Grid.Column="0" Text="Render height" VerticalAlignment="Center"/>
        <ComboBox Grid.Row="2" Grid.Column="1" x:Name="CmbRes" Margin="0,3" Width="160" HorizontalAlignment="Left" IsEditable="True">
          <ComboBoxItem Content=""/><ComboBoxItem Content="2160"/><ComboBoxItem Content="1440"/>
          <ComboBoxItem Content="1080"/><ComboBoxItem Content="720"/><ComboBoxItem Content="540"/>
          <ComboBoxItem Content="480"/>
        </ComboBox>
        <TextBlock Grid.Row="3" Grid.Column="0" Text="Adapter" VerticalAlignment="Center"/>
        <TextBox Grid.Row="3" Grid.Column="1" x:Name="TxtAdapter" Margin="0,3"/>
        <TextBlock Grid.Row="4" Grid.Column="0" Text="Skip pipelines" VerticalAlignment="Center"/>
        <TextBox Grid.Row="4" Grid.Column="1" x:Name="TxtSkip" Margin="0,3"/>
        <StackPanel Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,3">
          <CheckBox x:Name="ChkQuality" Content="Quality patches" Foreground="#E7E9F5" Margin="0,0,24,0"
                    VerticalAlignment="Center"/>
          <CheckBox x:Name="ChkRay" Content="Ray tracing on" Foreground="#E7E9F5" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
    </GroupBox>
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,8">
      <Button x:Name="BtnRun" Content="Run" Width="120" Height="34" FontWeight="Bold"
              Background="#76B900" Foreground="White" BorderBrush="#76B900"/>
      <Button x:Name="BtnStop" Content="Stop" Width="90" Height="34" Margin="10,0,0,0" IsEnabled="False"/>
      <Button x:Name="BtnSave" Content="Save settings" Width="110" Height="34" Margin="10,0,0,0"/>
    </StackPanel>
    <TextBox Grid.Row="3" x:Name="LogBox" IsReadOnly="True"
             Background="#121527" BorderBrush="#262C4A" Foreground="#E7E9F5"
             FontFamily="Consolas" VerticalScrollBarVisibility="Auto"
             TextWrapping="NoWrap" AcceptsReturn="True"/>
    <TextBlock Grid.Row="4" x:Name="LegalNote" Margin="0,8,0,0" TextWrapping="Wrap" FontSize="11.5"
               Foreground="#7A80A3"
               Text="Bring your own files: this runtime runs a game you already own and supplies nothing of it - no game code, assets or keys. It is a compatibility layer, not affiliated with or endorsed by Microsoft, Rockstar Games or any publisher. Code: GPL-3.0-or-later."/>
  </Grid>
</Window>
'@

$Win = [Windows.Markup.XamlReader]::Parse($Xaml)
$S = Read-Ini

$Win.FindName('TxtGame').Text = $S['GAME']
$Win.FindName('TxtAdapter').Text = $S['ADAPTER']
$Win.FindName('TxtSkip').Text = $S['SKIP']
$Win.FindName('ChkQuality').IsChecked = ($S['QUALITY'] -ieq 'on')
$Win.FindName('ChkRay').IsChecked = ($S['RAYTRACING'] -ieq 'on')
$items = @('', '2160', '1440', '1080', '720', '540', '480')
$Win.FindName('CmbRes').SelectedIndex = [Math]::Max(0, $items.IndexOf($S['RESOLUTION']))
$Win.FindName('CmbBuild').SelectedIndex = [Math]::Max(0, @('diag', 'release').IndexOf($S['BUILD']))

# --- run state -----------------------------------------------------------

$script:Proc = $null
$script:Done = $true
$Buffer = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

function Collect-Settings {
    $S['GAME'] = $Win.FindName('TxtGame').Text.Trim()
    $S['ADAPTER'] = $Win.FindName('TxtAdapter').Text.Trim()
    $S['SKIP'] = $Win.FindName('TxtSkip').Text.Trim()
    $S['QUALITY'] = $(if ($Win.FindName('ChkQuality').IsChecked) { 'on' } else { 'off' })
    $S['RAYTRACING'] = $(if ($Win.FindName('ChkRay').IsChecked) { 'on' } else { 'off' })
    $S['RESOLUTION'] = @('', '2160', '1440', '1080', '720', '540', '480')[$Win.FindName('CmbRes').SelectedIndex]
    $S['BUILD'] = @('diag', 'release')[$Win.FindName('CmbBuild').SelectedIndex]
}

function Log-Line {
    param([string]$line)
    [void]$Win.FindName('LogBox').AppendText($line + [Environment]::NewLine)
    $Win.FindName('LogBox').ScrollToEnd()
}

function Info-Or-Error {
    param([string]$text)
    [void][System.Windows.MessageBox]::Show($Win, $text, 'XENITH VI')
}

# --- browsing ------------------------------------------------------------

$Win.FindName('BtnGame').Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Executables (*.exe)|*.exe|All files (*.*)|*.*'
    if ($dlg.ShowDialog($Win)) { $Win.FindName('TxtGame').Text = $dlg.FileName }
})

$Win.FindName('BtnSave').Add_Click({
    Collect-Settings
    Save-Ini $S
    Log-Line 'settings saved to xenith.ini'
})

# --- running -------------------------------------------------------------

function Start-Run {
    Collect-Settings
    Save-Ini $S
    if (-not $S['GAME']) { Info-Or-Error 'Set the game path first.'; return }
    $script = Join-Path $PSScriptRoot 'scripts\play-nvidia.ps1'
    if (-not (Test-Path -LiteralPath $script)) { Info-Or-Error ('No ' + $script + '. Run this from the repository root.'); return }

    $argList = New-Object 'System.Collections.Generic.List[string]'
    $argList.Add('-NoProfile')
    $argList.Add('-ExecutionPolicy'); $argList.Add('Bypass')
    $argList.Add('-File'); $argList.Add('"{0}"' -f $script)
    $argList.Add('-Exe'); $argList.Add('"{0}"' -f $S['GAME'])
    $argList.Add('-Build'); $argList.Add($S['BUILD'])
    if ($S['QUALITY'] -ieq 'on') { $argList.Add('-Quality') }
    if ($S['RAYTRACING'] -ieq 'on') { $argList.Add('-RayTracing') }
    if ($S['RESOLUTION']) { $argList.Add('-Resolution'); $argList.Add($S['RESOLUTION']) }
    if ($S['ADAPTER']) { $argList.Add('-Adapter'); $argList.Add('"{0}"' -f $S['ADAPTER']) }
    if ($S['SKIP']) { $argList.Add("-More @{VICTORY_SKIP_PIPELINES='{0}'}" -f $S['SKIP']) }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell'
    $psi.Arguments = ($argList -join ' ')
    $psi.WorkingDirectory = $PSScriptRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $Buffer.Clear()
    $script:Done = $false
    $script:Proc = [System.Diagnostics.Process]::Start($psi)
    $script:Proc.EnableRaisingEvents = $true
    $script:Proc.add_OutputDataReceived({ param($o, $e) if ($null -ne $e.Data) { [void]$Buffer.Add($e.Data) } })
    $script:Proc.add_ErrorDataReceived({ param($o, $e) if ($null -ne $e.Data) { [void]$Buffer.Add($e.Data) } })
    $script:Proc.add_Exited({ param($o, $e) $script:Done = $true })
    $script:Proc.BeginOutputReadLine()
    $script:Proc.BeginErrorReadLine()

    $Win.FindName('BtnRun').IsEnabled = $false
    $Win.FindName('BtnStop').IsEnabled = $true
    Log-Line ('run  ' + $S['GAME'])
    Log-Line ('build ' + $S['BUILD'] + ', quality ' + $S['QUALITY'] + ', ray tracing ' + $S['RAYTRACING'])
}

function Stop-Run {
    $p = $script:Proc
    if ($p -and -not $p.HasExited) {
        $p.Kill()
        Log-Line 'stop requested'
    }
}

$Win.FindName('BtnRun').Add_Click({ Start-Run })
$Win.FindName('BtnStop').Add_Click({ Stop-Run })

$Win.Add_Closed({
    $p = $script:Proc
    if ($p -and -not $p.HasExited) { $p.Kill() }
})

# The run's output, drained from the process's threads onto the window's.
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(300)
$Timer.Add_Tick({
    while ($Buffer.Count -gt 0) {
        Log-Line ([string]$Buffer[0])
        $Buffer.RemoveAt(0)
    }
    if ($script:Done) {
        $Timer.Stop()
        $p = $script:Proc
        if ($p) { Log-Line ('exited with ' + $p.ExitCode) }
        $Win.FindName('BtnRun').IsEnabled = $true
        $Win.FindName('BtnStop').IsEnabled = $false
    }
})
$Timer.Start()

[void]$Win.ShowDialog()
