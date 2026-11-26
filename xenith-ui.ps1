# The XENITH VI launcher's window: WPF, nothing to install. Everything lives in
# xenith.ini as xenith.cmd, in a window. Windows PowerShell 5.1, WPF, nothing
# to install. The window has two views: Overview (the settings, the status and
# what changed) and a debug console (the run's whole log, a command box, and
# the log saved to any folder). The adapter is found for you (the fastest card
# is picked by the run anyway; the list here just names yours), the ray-tracing
# skip list is a choice of presets rather than raw hashes, and the upscaler row
# is where DLSS slots in. A run is scripts\play-nvidia.ps1, so its settings
# stay in one place.
#
# The window's look: a dark hero band with a warm gradient and a big PLAY
# button, a status line that says what a run would pick up, cards for the
# newest changes, and a console view with the run's log and commands.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# --- settings ------------------------------------------------------------

$IniPath = Join-Path $PSScriptRoot 'xenith.ini'
$Keys = @('GAME', 'RESOLUTION', 'ADAPTER', 'QUALITY', 'RAYTRACING', 'BUILD', 'SKIP', 'UPSCALER', 'CONSOLE', 'PRELOAD', 'CACHE_DIR', 'SAVES_DIR', 'DLSS_DIR', 'LOG_DIR')

function Read-Ini {
    $s = @{}
    foreach ($k in $Keys) { $s[$k] = '' }
    $s['QUALITY'] = 'on'
    $s['RAYTRACING'] = 'off'
    $s['BUILD'] = 'diag'
    $s['UPSCALER'] = 'fsr'
    $s['CONSOLE'] = 'S'
    $s['PRELOAD'] = 'off'
    if (Test-Path -LiteralPath $IniPath) {
        foreach ($line in Get-Content -LiteralPath $IniPath) {
            $i = $line.IndexOf('=')
            if ($i -lt 1) { continue }
            $key = $line.Substring(0, $i).Trim()
            if ($Keys -contains $key) { $s[$key] = $line.Substring($i + 1) }
        }
    }
    return $s
}

function Save-Ini {
    param([hashtable]$s)
    $lines = foreach ($k in $Keys) { '{0}={1}' -f $k, $s[$k] }
    Set-Content -LiteralPath $IniPath -Value $lines
}

function Get-GpuNames {
    $names = @()
    try {
        $names = @(Get-CimInstance Win32_VideoController | ForEach-Object { [string]$_.Name } | Where-Object { $_ })
    } catch {
        try {
            $names = @(Get-WmiObject Win32_VideoController | ForEach-Object { [string]$_.Name } | Where-Object { $_ })
        } catch { $names = @() }
    }
    $nvidia = @($names | Where-Object { $_ -match 'NVIDIA|GeForce|RTX|GTX' })
    $rest = @($names | Where-Object { $nvidia -notcontains $_ })
    return @($nvidia + $rest)
}

$script:Gpus = @(Get-GpuNames)
$script:HasNvidia = [bool]($script:Gpus | Where-Object { $_ -match 'NVIDIA|GeForce|RTX|GTX' })

# --- window --------------------------------------------------------------

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="XENITH VI for an RTX card" Height="900" Width="1000"
        MinWidth="860" MinHeight="660" WindowStartupLocation="CenterScreen"
        Background="#0A0D16" Foreground="#E7E9F5" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <LinearGradientBrush x:Key="HeroBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#3A1030" Offset="0"/>
      <GradientStop Color="#14102C" Offset="0.45"/>
      <GradientStop Color="#0A0D16" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="PlayBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#FF8C42" Offset="0"/>
      <GradientStop Color="#FF3D5E" Offset="1"/>
    </LinearGradientBrush>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#12172A"/>
      <Setter Property="Foreground" Value="#E7E9F5"/>
      <Setter Property="BorderBrush" Value="#262E52"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CaretBrush" Value="#76B900"/>
      <Setter Property="Padding" Value="7,4"/>
      <Setter Property="MinHeight" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Style.Triggers>
        <Trigger Property="IsEnabled" Value="False">
          <Setter Property="Foreground" Value="#5A6180"/>
          <Setter Property="Background" Value="#0F1322"/>
        </Trigger>
        <Trigger Property="IsKeyboardFocusWithin" Value="True">
          <Setter Property="BorderBrush" Value="#76B900"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#E7E9F5"/>
      <Setter Property="Padding" Value="8,0,4,0"/>
      <Setter Property="MinHeight" Value="30"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="TogglePart" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="#12172A" BorderBrush="#262E52" BorderThickness="1" CornerRadius="4">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition/><ColumnDefinition Width="26"/>
                        </Grid.ColumnDefinitions>
                        <Path Grid.Column="1" Data="M0,0 L4.5,4.5 9,0" Stroke="#76B900" StrokeThickness="2"
                              HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="Background" Value="#1A2240"/>
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#3A4578"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False" Margin="{TemplateBinding Padding}"
                                VerticalAlignment="Center" HorizontalAlignment="Left"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
              <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True"
                     Placement="Bottom" PopupAnimation="Slide" Focusable="False">
                <Border Background="#12182D" BorderBrush="#262E52" BorderThickness="1" CornerRadius="6"
                        Margin="0,2,0,8" MinWidth="{TemplateBinding ActualWidth}"
                        MaxHeight="{TemplateBinding MaxDropDownHeight}">
                  <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <ItemsPresenter Margin="4"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Setter Property="ItemContainerStyle">
        <Setter.Value>
          <Style TargetType="ComboBoxItem">
            <Setter Property="Foreground" Value="#E7E9F5"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ComboBoxItem">
                  <Border x:Name="Bd" Background="Transparent" CornerRadius="3" Padding="{TemplateBinding Padding}">
                    <ContentPresenter/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsHighlighted" Value="True">
                      <Setter TargetName="Bd" Property="Background" Value="#1D2A18"/>
                      <Setter Property="Foreground" Value="#A6E22E"/>
                    </Trigger>
                    <Trigger Property="IsEnabled" Value="False">
                      <Setter Property="Foreground" Value="#5A6180"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
          </Style>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#E7E9F5"/>
      <Setter Property="Padding" Value="12,0"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#1A2036" BorderBrush="#2A3155" BorderThickness="1"
                    CornerRadius="4" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#232B4A"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3A4578"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#5A6180"/>
                <Setter Property="Cursor" Value="Arrow"/>
                <Setter TargetName="Bd" Property="Background" Value="#12162A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PlayButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="#1A0A08"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{StaticResource PlayBrush}" BorderThickness="0"
                    CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.88"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#5A6180"/>
                <Setter Property="Cursor" Value="Arrow"/>
                <Setter TargetName="Bd" Property="Background" Value="#1A2036"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="StopButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="#FFB4A6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#241417" BorderBrush="#5A2A28" BorderThickness="1"
                    CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#331A1C"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Foreground" Value="#5A6180"/>
                <Setter Property="Cursor" Value="Arrow"/>
                <Setter TargetName="Bd" Property="Background" Value="#12162A"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#2A3155"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="TabButton" TargetType="Button">
      <Setter Property="Foreground" Value="#9AA1C0"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <ContentPresenter x:Name="Cp" HorizontalAlignment="Center" VerticalAlignment="Center"
                                Margin="14,6"/>
              <Border x:Name="Under" VerticalAlignment="Bottom" Height="2" Margin="10,0"
                      Background="#76B900" CornerRadius="1" Visibility="Hidden"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="#E7E9F5"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Under" Property="Visibility" Value="Visible"/>
                <Setter Property="Foreground" Value="#E7E9F5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CardBorder" TargetType="Border">
      <Setter Property="Background" Value="#12172B"/>
      <Setter Property="BorderBrush" Value="#242C50"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="16,12"/>
    </Style>
    <Style x:Key="CardTitle" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#76B900"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#9AA1C0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0" Margin="20,14,20,6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock Text="XENITH" FontSize="20" FontWeight="Bold" Foreground="#FFFFFF"/>
        <TextBlock Text=" VI" FontSize="20" FontWeight="Bold" Foreground="#76B900"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center">
        <Button x:Name="TabOverview" Style="{StaticResource TabButton}" IsEnabled="False" Content="Overview"/>
        <Button x:Name="TabConsole" Style="{StaticResource TabButton}" Content="Debug console"/>
        <Button x:Name="TabWebsite" Style="{StaticResource TabButton}" Content="Website"/>
      </StackPanel>
      <Border Grid.Column="2" VerticalAlignment="Center" CornerRadius="10" Padding="10,4"
              Background="#12210F" BorderBrush="#76B900" BorderThickness="1">
        <TextBlock x:Name="GpuBadge" Foreground="#A6E22E" FontSize="11.5" Text="looking for the card..."/>
      </Border>
    </Grid>

    <Grid x:Name="ViewOverview" Grid.Row="2" Visibility="Visible">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <Border Grid.Row="0" Background="{StaticResource HeroBrush}" BorderBrush="#242C50" BorderThickness="1"
              CornerRadius="10" Margin="20,6,20,10" Padding="22,18">
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0" VerticalAlignment="Center">
            <TextBlock FontSize="26" FontWeight="Bold">
              <Run Text="Victory" Foreground="#FFFFFF"/><Run Text="-NVIDIA" Foreground="#FF6A5B"/>
            </TextBlock>
            <TextBlock Text="the RTX build of the VIctory compatibility runtime" Foreground="#B4B9D4" Margin="2,4,0,0"/>
            <TextBlock x:Name="StatusLine" Foreground="#8A91B4" FontSize="11.5" Margin="2,8,0,0"
                       Text="ready to play"/>
            <StackPanel Orientation="Horizontal" Margin="2,14,0,0">
              <Button x:Name="BtnRun" Style="{StaticResource PlayButton}" Content="PLAY" Width="150" Height="42" FontSize="15"/>
              <Button x:Name="BtnStop" Style="{StaticResource StopButton}" Content="Stop" Width="86" Height="42"
                      Margin="10,0,0,0" IsEnabled="False"/>
              <Button x:Name="BtnSave" Content="Save settings" Width="120" Height="42" Margin="10,0,0,0"/>
            </StackPanel>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Row="1" Style="{StaticResource CardBorder}" Margin="20,0,20,10">
        <StackPanel>
          <TextBlock Style="{StaticResource CardTitle}" Text="TITLE"/>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition/><ColumnDefinition Width="96"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="Game path"/>
            <TextBox Grid.Column="1" x:Name="TxtGame" Margin="0,3"/>
            <Button Grid.Column="2" x:Name="BtnGame" Content="Browse..." Margin="8,3,0,3"/>
          </Grid>
          <Grid Margin="0,4,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition Width="190"/><ColumnDefinition Width="30"/>
              <ColumnDefinition Width="115"/><ColumnDefinition Width="160"/><ColumnDefinition Width="30"/>
              <ColumnDefinition Width="115"/><ColumnDefinition/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="Build"/>
            <ComboBox Grid.Column="1" x:Name="CmbBuild" Margin="0,3" SelectedIndex="0">
              <ComboBoxItem Content="diag (measured build)"/>
              <ComboBoxItem Content="release (faster)"/>
            </ComboBox>
            <TextBlock Grid.Column="3" Style="{StaticResource Label}" Text="Render height"/>
            <ComboBox Grid.Column="4" x:Name="CmbRes" Margin="0,3" MaxWidth="150" HorizontalAlignment="Left" SelectedIndex="0">
              <ComboBoxItem Content="half (the script's speed pick)" Tag=""/>
              <ComboBoxItem Content="2160" Tag="2160"/><ComboBoxItem Content="1440" Tag="1440"/>
              <ComboBoxItem Content="1080" Tag="1080"/><ComboBoxItem Content="720" Tag="720"/>
              <ComboBoxItem Content="540" Tag="540"/><ComboBoxItem Content="480" Tag="480"/>
            </ComboBox>
            <TextBlock Grid.Column="6" Style="{StaticResource Label}" Text="Console"/>
            <ComboBox Grid.Column="7" x:Name="CmbConsole" Margin="0,3" MaxWidth="220" HorizontalAlignment="Left" SelectedIndex="0">
              <ComboBoxItem Content="Series S (faster)" Tag="S"/>
              <ComboBoxItem Content="Series X (full output)" Tag="X"/>
            </ComboBox>
          </Grid>
        </StackPanel>
      </Border>

      <Border Grid.Row="2" Style="{StaticResource CardBorder}" Margin="20,0,20,10">
        <StackPanel>
          <TextBlock Style="{StaticResource CardTitle}" Text="PICTURE AND CARD"/>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition/><ColumnDefinition Width="96"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="Adapter"/>
            <ComboBox Grid.Column="1" x:Name="CmbAdapter" Margin="0,3" SelectedIndex="0"/>
            <Button Grid.Column="2" x:Name="BtnDetect" Content="Detect" Margin="8,3,0,3"/>
          </Grid>
          <Grid Margin="0,4,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="Upscaler"/>
            <ComboBox Grid.Column="1" x:Name="CmbUpscaler" Width="340" HorizontalAlignment="Left" Margin="0,3" SelectedIndex="0">
              <ComboBoxItem Content="The title's own (FSR; the default)" Tag="fsr"/>
              <ComboBoxItem Content="DLSS (its own folder; see docs)" Tag="dlss"
                             ToolTip="The title runs FSR; the proxy speaks FSR to it and DLSS to the driver. The NGX DLLs (nvngx*.dll, yours to supply) live in a folder of their own - never among the game's files. Name the folder below or with VICTORY_DLSS_DIR."/>
            </ComboBox>
          </Grid>
          <Grid Margin="0,4,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="Ray tracing"/>
            <StackPanel Grid.Column="1" Margin="0,3">
              <ComboBox x:Name="CmbRt" Width="420" HorizontalAlignment="Left" SelectedIndex="0">
                <ComboBoxItem Content="Mostly off: skip the known-bad passes (recommended)" Tag="list"/>
                <ComboBoxItem Content="All passes run (rooms may go white)" Tag="none"/>
                <ComboBoxItem Content="Custom hash list" Tag="custom"/>
              </ComboBox>
              <TextBox x:Name="TxtSkip" Margin="0,6,0,0" IsEnabled="False"
                       ToolTip="comma-separated pipeline hashes, as in scripts\rt_off_hashes.txt"/>
            </StackPanel>
          </Grid>
          <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
            <CheckBox x:Name="ChkQuality" Content="Quality patches (fewer stretched bodies, rainbow skin)"
                      Foreground="#E7E9F5" Margin="0,0,24,0" IsChecked="True" VerticalAlignment="Center"/>
            <CheckBox x:Name="ChkRay" Content="Ray tracing on (lit indirect light, slower)"
                      Foreground="#E7E9F5" VerticalAlignment="Center"/>
            <CheckBox x:Name="ChkPreload" Content="Preload shaders (minutes, once)"
                      Foreground="#E7E9F5" Margin="24,0,0,0" VerticalAlignment="Center"
                      ToolTip="Translate the title's shaders into the cache and make their pipelines before the run (VICTORY_GAME_DIR is set from the game path)."/>
          </StackPanel>
        </StackPanel>
      </Border>

      <Border Grid.Row="3" Style="{StaticResource CardBorder}" Margin="20,0,20,10">
        <StackPanel>
          <TextBlock Style="{StaticResource CardTitle}" Text="FILES"/>
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition/><ColumnDefinition Width="86"/><ColumnDefinition Width="86"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="Cache folder"/>
            <TextBox Grid.Column="1" x:Name="TxtCache" Margin="0,3"
                     ToolTip="The runtime's shader translations, pipelines and images live here (VICTORY_CACHE_DIR). Empty: the victory.toml pick."/>
            <Button Grid.Column="2" x:Name="BtnCacheOpen" Content="Open" Margin="8,3,0,3"/>
            <Button Grid.Column="3" x:Name="BtnCachePick" Content="Change..." Margin="8,3,0,3"/>
          </Grid>
          <Grid Margin="0,4,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition/><ColumnDefinition Width="86"/><ColumnDefinition Width="86"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="Saves folder"/>
            <TextBox Grid.Column="1" x:Name="TxtSaves" Margin="0,3"
                     ToolTip="Where the title's saves go (VICTORY_SAVES_DIR). Empty: beside the persistent local storage."/>
            <Button Grid.Column="2" x:Name="BtnSavesOpen" Content="Open" Margin="8,3,0,3"/>
            <Button Grid.Column="3" x:Name="BtnSavesPick" Content="Change..." Margin="8,3,0,3"/>
          </Grid>
          <Grid Margin="0,4,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="120"/><ColumnDefinition/><ColumnDefinition Width="86"/><ColumnDefinition Width="86"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource Label}" Text="DLSS folder"/>
            <TextBox Grid.Column="1" x:Name="TxtDlss" Margin="0,3"
                     ToolTip="Where the NVIDIA NGX libraries (nvngx*.dll) live on their own (VICTORY_DLSS_DIR): not among the game's files. Empty: a dlss folder next to the launcher, or beside the game's exe."/>
            <Button Grid.Column="2" x:Name="BtnDlssOpen" Content="Open" Margin="8,3,0,3"/>
            <Button Grid.Column="3" x:Name="BtnDlssPick" Content="Change..." Margin="8,3,0,3"/>
          </Grid>
        </StackPanel>
      </Border>

      <UniformGrid Grid.Row="4" Columns="3" Margin="20,0,20,10">
        <Border Style="{StaticResource CardBorder}" Margin="0,0,8,0">
          <StackPanel>
            <TextBlock Style="{StaticResource CardTitle}" Text="THE DEBUG CONSOLE"/>
            <TextBlock Foreground="#9AA1C0" TextWrapping="Wrap"
                       Text="Every run's whole log is in its own tab now, with a command box and a Save that puts the log anywhere you point it."/>
          </StackPanel>
        </Border>
        <Border Style="{StaticResource CardBorder}" Margin="8,0">
          <StackPanel>
            <TextBlock Style="{StaticResource CardTitle}" Text="DLSS, A FOLDER OF ITS OWN"/>
            <TextBlock Foreground="#9AA1C0" TextWrapping="Wrap"
                       Text="The NVIDIA files stay out of the game's folder: a dlss folder next to the launcher is picked up, or name any folder with VICTORY_DLSS_DIR."/>
          </StackPanel>
        </Border>
        <Border Style="{StaticResource CardBorder}" Margin="8,0,0,0">
          <StackPanel>
            <TextBlock Style="{StaticResource CardTitle}" Text="PRELOAD THE SHADERS"/>
            <TextBlock Foreground="#9AA1C0" TextWrapping="Wrap"
                       Text="Translate and warm before the run: minutes, once - after that the play starts without the first-seen-places hitches."/>
          </StackPanel>
        </Border>
      </UniformGrid>
    </Grid>

    <Grid x:Name="ViewConsole" Grid.Row="2" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <Grid Grid.Row="0" Margin="20,4,20,8">
        <Grid.ColumnDefinitions>
          <ColumnDefinition/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Orientation="Horizontal">
          <TextBlock Style="{StaticResource Label}" Text="Save every run's log to" VerticalAlignment="Center"/>
          <TextBox x:Name="TxtLogDir" Width="330" Margin="10,0,0,0"/>
          <Button x:Name="BtnLogDirPick" Content="Change..." Margin="8,0,0,0"/>
          <Button x:Name="BtnLogDirOpen" Content="Open" Margin="8,0,0,0"/>
          <CheckBox x:Name="ChkAutoLog" Content="auto" Foreground="#E7E9F5" Margin="10,0,0,0"
                    VerticalAlignment="Center" ToolTip="Write victory-run-&lt;date&gt;.log into that folder at the end of every run."/>
        </StackPanel>
        <Button Grid.Column="1" x:Name="BtnLogSave" Content="Save log..." Margin="0,0,8,0"/>
        <Button Grid.Column="2" x:Name="BtnLogCopy" Content="Copy" Margin="0,0,8,0"/>
        <Button Grid.Column="3" x:Name="BtnLogClear" Content="Clear"/>
      </Grid>
      <Border Grid.Row="1" Background="#0B0F1E" BorderBrush="#242C50" BorderThickness="1" CornerRadius="8" Margin="20,0,20,8">
        <TextBox x:Name="LogBox" IsReadOnly="True" BorderThickness="0" Background="Transparent"
                 FontFamily="Consolas" FontSize="12" VerticalScrollBarVisibility="Auto"
                 HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" AcceptsReturn="True"/>
      </Border>
      <Grid Grid.Row="2" Margin="20,0,20,4">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/><ColumnDefinition/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Style="{StaticResource Label}" Margin="0,0,10,0" VerticalAlignment="Center"
                   Text="&gt;_"/>
        <TextBox Grid.Column="1" x:Name="TxtCommand" Margin="0,3" FontFamily="Consolas"/>
        <Button Grid.Column="2" x:Name="BtnCommand" Content="Run command" Margin="8,3,0,3" Width="110"/>
      </Grid>
    </Grid>

    <TextBlock Grid.Row="3" x:Name="LegalNote" TextWrapping="Wrap" FontSize="11.5" Foreground="#7A80A3" Margin="20,4,20,10"
               Text="Bring your own files: this runtime runs a game you already own and supplies nothing of it - no game code, assets or keys. It is a compatibility layer, not affiliated with or endorsed by Microsoft, Rockstar Games or any publisher. Code: GPL-3.0-or-later. Launcher: a copy of XENITH VI (ASsDevpile/XenithVI, GPL-3.0-or-later)."/>
  </Grid>
</Window>
'@

$Win = [Windows.Markup.XamlReader]::Parse($Xaml)
$S = Read-Ini
$script:LogText = New-Object System.Text.StringBuilder

function Log-Line {
    param([string]$line)
    $line = ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $line)
    [void]$script:LogText.AppendLine($line)
    $Box = $Win.FindName('LogBox')
    [void]$Box.AppendText($line + [Environment]::NewLine)
    $Box.ScrollToEnd()
}

function Update-GpuBadge {
    $badge = $Win.FindName('GpuBadge')
    if ($script:Gpus.Count -eq 0) {
        $badge.Text = 'no cards found'
        $badge.Foreground = '#E0B442'
    } elseif ($script:HasNvidia) {
        $badge.Text = ($script:Gpus | Where-Object { $_ -match 'NVIDIA|GeForce|RTX|GTX' } | Select-Object -First 1)
        $badge.Foreground = '#A6E22E'
    } else {
        $badge.Text = 'no NVIDIA card found - ' + $script:Gpus[0]
        $badge.Foreground = '#E0B442'
    }
}

function Fill-AdapterCombo {
    param([string]$picked)
    $combo = $Win.FindName('CmbAdapter')
    $combo.Items.Clear()
    $auto = New-Object System.Windows.Controls.ComboBoxItem
    $auto.Content = 'Auto: the run picks the fastest card'
    $auto.Tag = ''
    [void]$combo.Items.Add($auto)
    foreach ($g in $script:Gpus) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = $g
        $item.Tag = $g
        [void]$combo.Items.Add($item)
    }
    $idx = 0
    if ($picked) {
        for ($i = 1; $i -lt $combo.Items.Count; $i++) {
            if ([string]$combo.Items[$i].Tag -like "*$picked*") { $idx = $i; break }
        }
    }
    $combo.SelectedIndex = $idx
}

function Show-View {
    param([string]$which)
    $Win.FindName('TabOverview').IsEnabled = ($which -eq 'Console')
    $Win.FindName('TabConsole').IsEnabled = ($which -eq 'Overview')
    $Win.FindName('ViewOverview').Visibility = $(if ($which -eq 'Overview') { 'Visible' } else { 'Collapsed' })
    $Win.FindName('ViewConsole').Visibility = $(if ($which -eq 'Console') { 'Visible' } else { 'Collapsed' })
}

$Win.FindName('TabOverview').Add_Click({ Show-View 'Overview' })
$Win.FindName('TabConsole').Add_Click({ Show-View 'Console' })
$Win.FindName('TabWebsite').Add_Click({
    $page = Join-Path $PSScriptRoot 'docs\index.html'
    if (Test-Path -LiteralPath $page) { Start-Process $page }
    else {
        Log-Line 'no docs\index.html here; the website is at github.com/ASsDevpile/VIctory-NVIDIA'
        Show-View 'Console'
    }
})

$Win.Add_Loaded({
    Update-GpuBadge
    Fill-AdapterCombo $S['ADAPTER']
    Log-Line 'XENITH VI ready; the commands are in the console tab (help).'
})

# --- restoring, collecting and the status line ---------------------------

$resTags = @('', '2160', '1440', '1080', '720', '540', '480')
$Win.FindName('TxtGame').Text = $S['GAME']
$Win.FindName('ChkQuality').IsChecked = ($S['QUALITY'] -ieq 'on')
$Win.FindName('ChkRay').IsChecked = ($S['RAYTRACING'] -ieq 'on')
$Win.FindName('CmbRes').SelectedIndex = [Math]::Max(0, $resTags.IndexOf($S['RESOLUTION']))
$Win.FindName('CmbBuild').SelectedIndex = [Math]::Max(0, @('diag', 'release').IndexOf($S['BUILD']))
$Win.FindName('CmbConsole').SelectedIndex = [Math]::Max(0, @('S', 'X').IndexOf($S['CONSOLE'].ToUpper()))
$Win.FindName('TxtCache').Text = $S['CACHE_DIR']
$Win.FindName('TxtSaves').Text = $S['SAVES_DIR']
$Win.FindName('TxtDlss').Text = $S['DLSS_DIR']
$Win.FindName('TxtLogDir').Text = $S['LOG_DIR']
$Win.FindName('ChkPreload').IsChecked = ($S['PRELOAD'] -ieq 'on')
if ($S['UPSCALER'] -ieq 'dlss') { $Win.FindName('CmbUpscaler').SelectedIndex = 0 }
$Win.FindName('CmbRt').SelectedIndex = 0
if ($S['SKIP'] -eq 'none') { $Win.FindName('CmbRt').SelectedIndex = 1 }
elseif ($S['SKIP']) {
    $Win.FindName('CmbRt').SelectedIndex = 2
    $Win.FindName('TxtSkip').IsEnabled = $true
}

function Collect-Settings {
    $S['GAME'] = $Win.FindName('TxtGame').Text.Trim()
    $S['ADAPTER'] = [string](($Win.FindName('CmbAdapter').SelectedItem).Tag)
    $S['SKIP'] = ''
    switch ([string](($Win.FindName('CmbRt').SelectedItem).Tag)) {
        'none' { $S['SKIP'] = 'none' }
        'custom' { $S['SKIP'] = $Win.FindName('TxtSkip').Text.Trim() }
    }
    $S['UPSCALER'] = [string](($Win.FindName('CmbUpscaler').SelectedItem).Tag)
    $S['CONSOLE'] = [string](($Win.FindName('CmbConsole').SelectedItem).Tag)
    $S['PRELOAD'] = $(if ($Win.FindName('ChkPreload').IsChecked) { 'on' } else { 'off' })
    $S['CACHE_DIR'] = $Win.FindName('TxtCache').Text.Trim()
    $S['SAVES_DIR'] = $Win.FindName('TxtSaves').Text.Trim()
    $S['DLSS_DIR'] = $Win.FindName('TxtDlss').Text.Trim()
    $S['LOG_DIR'] = $Win.FindName('TxtLogDir').Text.Trim()
    $S['QUALITY'] = $(if ($Win.FindName('ChkQuality').IsChecked) { 'on' } else { 'off' })
    $S['RAYTRACING'] = $(if ($Win.FindName('ChkRay').IsChecked) { 'on' } else { 'off' })
    $S['RESOLUTION'] = $resTags[$Win.FindName('CmbRes').SelectedIndex]
    $S['BUILD'] = @('diag', 'release')[$Win.FindName('CmbBuild').SelectedIndex]
}

function Update-StatusLine {
    $Win.FindName('StatusLine').Text = (
        'ready - ' + $(if ($S['CONSOLE'] -ieq 'X') { 'Series X' } else { 'Series S' }) +
        ', ' + $S['BUILD'] + ' build, upscaler ' + $S['UPSCALER'] +
        ', ' + $(if ($S['PRELOAD'] -ieq 'on') { 'shaders preloaded before the run' } else { 'no preload' }) +
        ', log ' + $(if ($Win.FindName('ChkAutoLog').IsChecked -and $S['LOG_DIR']) { 'saved to a file' } else { 'in the console tab' })
    )
}

$Win.FindName('CmbRt').Add_SelectionChanged({
    $Win.FindName('TxtSkip').IsEnabled = ([string](($Win.FindName('CmbRt').SelectedItem).Tag) -eq 'custom')
})
$Win.FindName('CmbConsole').Add_SelectionChanged({ Update-StatusLine })
$Win.FindName('CmbBuild').Add_SelectionChanged({ Update-StatusLine })
$Win.FindName('CmbRes').Add_SelectionChanged({ Update-StatusLine })
$Win.FindName('ChkPreload').Add_Click({ Update-StatusLine })
$Win.FindName('ChkAutoLog').Add_Click({ Update-StatusLine })

function Info-Or-Error {
    param([string]$text)
    [void][System.Windows.MessageBox]::Show($Win, $text, 'XENITH VI')
}

# --- browsing and detecting ----------------------------------------------

$Win.FindName('BtnGame').Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Executables (*.exe)|*.exe|All files (*.*)|*.*'
    if ($dlg.ShowDialog($Win)) {
        $Win.FindName('TxtGame').Text = $dlg.FileName
        Collect-Settings
        Update-StatusLine
    }
})

$Win.FindName('BtnDetect').Add_Click({
    $script:Gpus = @(Get-GpuNames)
    $script:HasNvidia = [bool]($script:Gpus | Where-Object { $_ -match 'NVIDIA|GeForce|RTX|GTX' })
    Update-GpuBadge
    Fill-AdapterCombo ''
    Log-Line ('cards found: ' + $(if ($script:Gpus) { $script:Gpus -join '; ' } else { 'none' }))
})

function Pick-Folder {
    param([string]$target)
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'XENITH VI'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Win.FindName($target).Text = $dlg.SelectedPath
    }
}

function Open-Folder {
    param([string]$target)
    $path = $Win.FindName($target).Text.Trim()
    if (-not $path) { Info-Or-Error 'The folder is unset, so the run uses the victory.toml pick.'; return }
    if (-not (Test-Path -LiteralPath $path)) { [void][System.IO.Directory]::CreateDirectory($path) }
    Start-Process explorer.exe -ArgumentList ('"' + $path + '"')
}

$Win.FindName('BtnCachePick').Add_Click({ Pick-Folder 'TxtCache' })
$Win.FindName('BtnSavesPick').Add_Click({ Pick-Folder 'TxtSaves' })
$Win.FindName('BtnDlssPick').Add_Click({ Pick-Folder 'TxtDlss' })
$Win.FindName('BtnLogDirPick').Add_Click({ Pick-Folder 'TxtLogDir'; Update-StatusLine })
$Win.FindName('BtnCacheOpen').Add_Click({ Open-Folder 'TxtCache' })
$Win.FindName('BtnSavesOpen').Add_Click({ Open-Folder 'TxtSaves' })
$Win.FindName('BtnDlssOpen').Add_Click({ Open-Folder 'TxtDlss' })
$Win.FindName('BtnLogDirOpen').Add_Click({ Open-Folder 'TxtLogDir' })

# --- the log -------------------------------------------------------------

function Save-LogTo {
    param([string]$path)
    if (-not $path) { Info-Or-Error 'No file for the log.'; return }
    try {
        [System.IO.File]::WriteAllText($path, $script:LogText.ToString())
        Log-Line ('log saved to ' + $path)
    } catch {
        Log-Line ('the log could not be written: ' + $_.Exception.Message)
    }
}

function Save-LogAs {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'Log files (*.log)|*.log|Text files (*.txt)|*.txt|All files (*.*)|*.*'
    $dlg.FileName = ('victory-run-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $dlg.Title = 'XENITH VI: save the run log anywhere'
    if ($dlg.ShowDialog($Win)) { Save-LogTo $dlg.FileName }
}

$Win.FindName('BtnLogSave').Add_Click({ Save-LogAs })
$Win.FindName('BtnLogCopy').Add_Click({
    [System.Windows.Clipboard]::SetText($script:LogText.ToString())
    Log-Line 'the log is on the clipboard'
})
$Win.FindName('BtnLogClear').Add_Click({
    $Win.FindName('LogBox').Clear()
    [void]$script:LogText.Clear()
})

function Auto-SaveLog {
    if (-not $Win.FindName('ChkAutoLog').IsChecked) { return }
    $dir = $Win.FindName('TxtLogDir').Text.Trim()
    if (-not $dir) { return }
    try { [void][System.IO.Directory]::CreateDirectory($dir) } catch { }
    Save-LogTo (Join-Path $dir ('victory-run-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
}

# --- the console ---------------------------------------------------------

function Console-Status {
    $set = $S.GetEnumerator() | Sort-Object Name | ForEach-Object { if ($_.Value) { '{0}={1}' -f $_.Key, $_.Value } }
    Log-Line ('setting   ' + $($set -join '; '))
    $extra = @(Get-ChildItem Env:VICTORY_* | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value })
    Log-Line ('env       ' + $(if ($extra) { $extra -join '; ' } else { 'none set' }))
    $p = $script:Proc
    Log-Line ('run       ' + $(if ($p -and -not $p.HasExited) { 'going (process ' + $p.Id + ')' } else { 'not going' }))
}

function Run-Command {
    param([string]$text)
    $parts = $text.Trim() -split '\s+', 2
    $cmd = $parts[0].ToLowerInvariant()
    $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
    switch ($cmd) {
        'help' {
            Log-Line 'the commands:'
            Log-Line '  play            start the run, as PLAY does'
            Log-Line '  stop            stop the run'
            Log-Line '  status          the settings, the VICTORY_ env and the run'
            Log-Line '  cards           list the cards again (and re-fill the picker)'
            Log-Line '  open cache|saves|dlss|game|logs   open a folder in the shell'
            Log-Line '  save <path>     save the log there'
            Log-Line '  clear           empty the console'
            Log-Line '  anything else   echoed, nothing done'
        }
        'play' { Start-Run }
        'stop' { Stop-Run }
        'status' { Console-Status }
        'cards' {
            $script:Gpus = @(Get-GpuNames)
            $script:HasNvidia = [bool]($script:Gpus | Where-Object { $_ -match 'NVIDIA|GeForce|RTX|GTX' })
            Update-GpuBadge
            Fill-AdapterCombo $S['ADAPTER']
            Log-Line ('cards: ' + $(if ($script:Gpus) { $script:Gpus -join '; ' } else { 'none' }))
        }
        'open' {
            switch -Regex ($arg) {
                'cache' { Open-Folder 'TxtCache' }
                'saves' { Open-Folder 'TxtSaves' }
                'dlss' { Open-Folder 'TxtDlss' }
                'log' { Open-Folder 'TxtLogDir' }
                'game' {
                    $dir = Split-Path $S['GAME'] -Parent
                    if ($S['GAME'] -and (Test-Path -LiteralPath $dir)) {
                        Start-Process explorer.exe -ArgumentList ('"' + $dir + '"')
                    } else { Log-Line 'no game path set' }
                }
                default { Log-Line 'open what? cache, saves, dlss, game or logs' }
            }
        }
        'save' { Save-LogTo $arg }
        'clear' { $Win.FindName('LogBox').Clear(); [void]$script:LogText.Clear() }
        default { Log-Line ($text + '   (no such command; try help)') }
    }
}

$Win.FindName('BtnCommand').Add_Click({
    $t = $Win.FindName('TxtCommand').Text
    $Win.FindName('TxtCommand').Clear()
    if ($t.Trim()) { Run-Command $t }
})
$Win.FindName('TxtCommand').Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq 'Enter') {
        $t = $Win.FindName('TxtCommand').Text
        $Win.FindName('TxtCommand').Clear()
        if ($t.Trim()) { Run-Command $t }
    }
})

# --- running -------------------------------------------------------------

$script:Proc = $null
$script:Done = $true
$Buffer = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

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
    if ($S['CONSOLE'] -ieq 'X') { $argList.Add('-Console'); $argList.Add('X') }
    if ($S['UPSCALER'] -ieq 'dlss') { $argList.Add('-Upscaler'); $argList.Add('dlss') }
    if ($S['PRELOAD'] -ieq 'on') { $argList.Add('-Preload') }
    if ($S['CACHE_DIR']) { $env:VICTORY_CACHE_DIR = $S['CACHE_DIR'] }
    if ($S['SAVES_DIR']) { $env:VICTORY_SAVES_DIR = $S['SAVES_DIR'] }
    if ($S['DLSS_DIR']) { $env:VICTORY_DLSS_DIR = $S['DLSS_DIR'] }

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
    Log-Line ('build ' + $S['BUILD'] + ', ' + $(if ($S['CONSOLE'] -ieq 'X') { 'Series X' } else { 'Series S' }) +
              ', upscaler ' + $S['UPSCALER'] + ', preload ' + $S['PRELOAD'])
    Log-Line ('adapter ' + $(if ($S['ADAPTER']) { $S['ADAPTER'] } else { 'auto' }) +
              ', cache ' + $(if ($S['CACHE_DIR']) { $S['CACHE_DIR'] } else { 'the default' }) +
              ', saves ' + $(if ($S['SAVES_DIR']) { $S['SAVES_DIR'] } else { 'the default' }) +
              ', dlss ' + $(if ($S['DLSS_DIR']) { $S['DLSS_DIR'] } else { 'the default' }) +
              ', log ' + $(if ($Win.FindName('ChkAutoLog').IsChecked -and $S['LOG_DIR']) { $S['LOG_DIR'] } else { 'in this console only' }))
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
        if ($p) {
            Log-Line ('exited with ' + $p.ExitCode)
            Auto-SaveLog
        }
        $Win.FindName('BtnRun').IsEnabled = $true
        $Win.FindName('BtnStop').IsEnabled = $false
    }
})
$Timer.Start()

Update-StatusLine
[void]$Win.ShowDialog()
