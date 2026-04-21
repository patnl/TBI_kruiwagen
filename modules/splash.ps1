# modules/splash.ps1 — TBI opstartscherm in huisstijl
# Volgt layout-principe: twee over elkaar schuivende vlakken (linksboven + rechtsonder)
# Logo linksboven, TBI Sans met Segoe UI fallback, letterspatiëring +0.03em

function Show-KioskSplash {
    param(
        [object]$Config,
        [string]$Version        = "onbekend",
        [string]$UpdateStatus   = "Geen update",
        [int]   $DisplaySeconds = 5
    )

    # Bepaal kleuren op basis van bedrijfshuisstijl
    $kleuren = Get-BedrijfKleurenschema -Config $Config
    $hoofd   = $kleuren.Hoofd      # #630d80 voor TBI, of #404040 voor eigen
    $accent  = $kleuren.Accent     # #c1e62e voor TBI, of #1489cc voor eigen
    $tekst   = $kleuren.Tekst

    # Logo pad (vanuit C:\KioskSetup\logos\ als die gedownload is)
    $logoLocal = "C:\KioskSetup\logos\$($Config.huisstijl ?? 'tbi')-wit.png"
    if (-not (Test-Path $logoLocal)) {
        # Fallback op TBI logo
        $logoLocal = "C:\KioskSetup\logos\tbi-wit.png"
    }

    $splashScript = @"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]`$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    Topmost="True"
    WindowStartupLocation="CenterScreen"
    Width="720" Height="420"
    ResizeMode="NoResize">
  <Window.Resources>
    <!-- TBI huisstijlkleuren -->
    <SolidColorBrush x:Key="Hoofd"  Color="HOOFD_PLACEHOLDER"/>
    <SolidColorBrush x:Key="Accent" Color="ACCENT_PLACEHOLDER"/>
    <SolidColorBrush x:Key="Tekst"  Color="TEKST_PLACEHOLDER"/>
  </Window.Resources>

  <!-- Canvas maakt de twee schuivende vlakken mogelijk -->
  <Grid>
    <!-- Buitenste container met ronde hoeken en schaduw -->
    <Border CornerRadius="6" Background="Transparent" ClipToBounds="True">
      <Border.Effect>
        <DropShadowEffect BlurRadius="40" ShadowDepth="0" Opacity="0.5" Color="#000000"/>
      </Border.Effect>

      <Grid ClipToBounds="True">
        <!-- ────────────────────────────────────────────────────────────── -->
        <!-- LAYOUT PRINCIPE: twee over elkaar schuivende vlakken            -->
        <!-- Vlak 1 (onder): TBI-paars hoofdvlak, volledig scherm            -->
        <!-- Vlak 2 (boven): accent-kleur (groen/cyaan), rechtsonder schuift  -->
        <!-- ────────────────────────────────────────────────────────────── -->

        <!-- Paars hoofdvlak -->
        <Rectangle Fill="{StaticResource Hoofd}"/>

        <!-- Accent-vlak rechtsonder (schuift vanaf rechter onderhoek) -->
        <Rectangle Fill="{StaticResource Accent}"
                   HorizontalAlignment="Right"
                   VerticalAlignment="Bottom"
                   Width="280" Height="120"/>

        <!-- Klein paars blokje in linker onderhoek als accent-dot (huisstijl) -->
        <Rectangle Fill="{StaticResource Hoofd}"
                   HorizontalAlignment="Left"
                   VerticalAlignment="Bottom"
                   Width="14" Height="14"
                   Margin="32,0,0,110"/>

        <!-- ────────────────────────────────────────────────────────────── -->
        <!-- LOGO LINKSBOVEN (volgens huisstijl: altijd hoek, nooit midden) -->
        <!-- ────────────────────────────────────────────────────────────── -->
        <Grid HorizontalAlignment="Left" VerticalAlignment="Top"
              Margin="32,28,0,0" Width="150" Height="48">
          <!-- Logo wordt dynamisch geladen -->
          <Image Name="logoImg" Stretch="Uniform" HorizontalAlignment="Left"/>
          <!-- Fallback tekst als logo niet geladen kan worden -->
          <TextBlock Name="logoFallback" Text="▸ TBI"
                     FontFamily="TBI Sans, Segoe UI" FontWeight="Bold"
                     FontSize="28" Foreground="{StaticResource Tekst}"
                     VerticalAlignment="Center"
                     Visibility="Collapsed"/>
        </Grid>

        <!-- ────────────────────────────────────────────────────────────── -->
        <!-- HOOFDCONTENT — gecentreerd, ruime marges                         -->
        <!-- ────────────────────────────────────────────────────────────── -->
        <StackPanel VerticalAlignment="Center" HorizontalAlignment="Left"
                    Margin="32,0,32,0" MaxWidth="520">

          <!-- Bedrijfsnaam — grote Titel 1 stijl -->
          <TextBlock Name="txtBedrijf" Text="BEDRIJFSNAAM"
                     FontFamily="TBI Sans, Segoe UI"
                     FontWeight="Bold"
                     FontSize="34"
                     Foreground="{StaticResource Tekst}"
                     TextTrimming="CharacterEllipsis">
            <TextBlock.Effect>
              <DropShadowEffect BlurRadius="0" ShadowDepth="0"/>
            </TextBlock.Effect>
          </TextBlock>

          <!-- Subtitle in accent kleur — TBI Sans Bold -->
          <TextBlock Text="KIOSK · INRICHTING GEREED"
                     FontFamily="TBI Sans, Segoe UI"
                     FontWeight="Bold"
                     FontSize="11"
                     Foreground="{StaticResource Accent}"
                     Margin="0,4,0,28"/>

          <!-- Info grid: versie en laatste update -->
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <StackPanel Grid.Column="0">
              <TextBlock Text="VERSIE"
                         FontFamily="TBI Sans, Segoe UI" FontWeight="Bold"
                         FontSize="10"
                         Foreground="{StaticResource Accent}"
                         Opacity="0.7"/>
              <TextBlock Name="txtVersie" Text="–"
                         FontFamily="TBI Sans, Segoe UI"
                         FontWeight="Bold" FontSize="22"
                         Foreground="{StaticResource Tekst}"
                         Margin="0,2,0,0"/>
            </StackPanel>

            <StackPanel Grid.Column="1">
              <TextBlock Text="LAATSTE UPDATE"
                         FontFamily="TBI Sans, Segoe UI" FontWeight="Bold"
                         FontSize="10"
                         Foreground="{StaticResource Accent}"
                         Opacity="0.7"/>
              <TextBlock Name="txtUpdate" Text="–"
                         FontFamily="TBI Sans, Segoe UI"
                         FontSize="14"
                         Foreground="{StaticResource Tekst}"
                         Margin="0,6,0,0"/>
            </StackPanel>
          </Grid>

          <!-- Horizontale lijn, subtiele scheiding -->
          <Border Height="1" Background="{StaticResource Tekst}"
                  Opacity="0.15" Margin="0,20,0,14"/>

          <!-- Status-regel -->
          <TextBlock Name="txtStatus" Text="Status"
                     FontFamily="TBI Sans, Segoe UI"
                     FontSize="13"
                     Foreground="{StaticResource Tekst}"
                     Opacity="0.9"/>
        </StackPanel>

        <!-- ────────────────────────────────────────────────────────────── -->
        <!-- PROGRESSIEBALK BOVENOP HET ACCENT-VLAK                          -->
        <!-- ────────────────────────────────────────────────────────────── -->
        <Grid VerticalAlignment="Bottom" HorizontalAlignment="Stretch"
              Height="60" Margin="0">
          <!-- Progress track -->
          <Border Background="{StaticResource Hoofd}" Opacity="0.25"
                  Height="3" VerticalAlignment="Bottom"/>
          <!-- Progress fill -->
          <Border Name="progressBar"
                  Background="{StaticResource Hoofd}"
                  Height="3" VerticalAlignment="Bottom"
                  HorizontalAlignment="Left" Width="0"/>
          <!-- Aftelteller rechtsonder in paars (op groen) -->
          <TextBlock Name="txtCountdown" Text="5"
                     FontFamily="TBI Sans, Segoe UI"
                     FontWeight="Bold"
                     FontSize="14"
                     Foreground="{StaticResource Hoofd}"
                     HorizontalAlignment="Right"
                     VerticalAlignment="Center"
                     Margin="0,0,32,0"/>
        </Grid>

      </Grid>
    </Border>
  </Grid>
</Window>
'@

`$reader = [System.Xml.XmlNodeReader]::new(`$xaml)
`$window = [Windows.Markup.XamlReader]::Load(`$reader)

# Vul dynamische waarden in
`$window.FindName("txtBedrijf").Text = "BEDRIJF_PLACEHOLDER"
`$window.FindName("txtVersie").Text  = "VERSIE_PLACEHOLDER"
`$window.FindName("txtUpdate").Text  = "UPDATE_PLACEHOLDER"
`$window.FindName("txtStatus").Text  = "STATUS_PLACEHOLDER"

# Probeer logo te laden
`$logoPath = "LOGO_PLACEHOLDER"
if (Test-Path `$logoPath) {
    try {
        `$bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        `$bmp.BeginInit()
        `$bmp.UriSource = [Uri]`$logoPath
        `$bmp.CacheOption = "OnLoad"
        `$bmp.EndInit()
        `$window.FindName("logoImg").Source = `$bmp
    } catch {
        `$window.FindName("logoImg").Visibility = "Collapsed"
        `$window.FindName("logoFallback").Visibility = "Visible"
    }
} else {
    `$window.FindName("logoImg").Visibility = "Collapsed"
    `$window.FindName("logoFallback").Visibility = "Visible"
}

# Progressiebalk timer
`$totalMs   = DUUR_PLACEHOLDER * 1000
`$startTime = [datetime]::Now
`$progBar   = `$window.FindName("progressBar")
`$countdown = `$window.FindName("txtCountdown")
`$maxWidth  = 720   # Volledige breedte van window

`$timer = [System.Windows.Threading.DispatcherTimer]::new()
`$timer.Interval = [timespan]::FromMilliseconds(50)
`$timer.Add_Tick({
    `$elapsed = ([datetime]::Now - `$startTime).TotalMilliseconds
    `$ratio   = [Math]::Min(`$elapsed / `$totalMs, 1.0)
    `$progBar.Width = `$maxWidth * `$ratio
    `$secsLeft = [Math]::Ceiling(((`$totalMs - `$elapsed) / 1000))
    `$countdown.Text = if (`$secsLeft -gt 0) { `$secsLeft.ToString() } else { "" }
    if (`$elapsed -ge `$totalMs) {
        `$timer.Stop()
        `$window.Close()
    }
})
`$timer.Start()
`$window.ShowDialog() | Out-Null
"@

    # Bereken laatste update-datum
    $lastUpdate = if (Test-Path "C:\KioskSetup\version.txt") {
        $vFile = Get-Item "C:\KioskSetup\version.txt"
        $vFile.LastWriteTime.ToString("dd-MM-yyyy HH:mm")
    } else { "Onbekend" }

    # Converteer hex naar WPF-compatibele vorm (#RRGGBB blijft geldig)
    $splashScript = $splashScript `
        -replace "BEDRIJF_PLACEHOLDER",  $Config.displayName `
        -replace "VERSIE_PLACEHOLDER",   $Version `
        -replace "UPDATE_PLACEHOLDER",   $lastUpdate `
        -replace "STATUS_PLACEHOLDER",   $UpdateStatus `
        -replace "DUUR_PLACEHOLDER",     $DisplaySeconds `
        -replace "HOOFD_PLACEHOLDER",    $hoofd `
        -replace "ACCENT_PLACEHOLDER",   $accent `
        -replace "TEKST_PLACEHOLDER",    $tekst `
        -replace "LOGO_PLACEHOLDER",     ($logoLocal -replace '\\','\\')

    $scriptPath = "C:\KioskSetup\splash.ps1"
    $splashScript | Out-File -FilePath $scriptPath -Encoding UTF8
    Write-Log "Splash script geschreven met huisstijl: $($Config.huisstijl ?? 'tbi')"
}

function Register-SplashTask {
    param([object]$Config, [string]$Version, [string]$UpdateStatus)

    $username = $Config.kioskUser.username

    # Zorg dat logo's lokaal beschikbaar zijn (gedownload van GitHub bij eerste setup)
    Sync-LogoAssets -Config $Config

    Show-KioskSplash -Config $Config -Version $Version -UpdateStatus $UpdateStatus

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$env:COMPUTERNAME\$username</UserId>
      <Delay>PT2S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$env:COMPUTERNAME\$username</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <ExecutionTimeLimit>PT1M</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\KioskSetup\splash.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $taskXml | Out-File "C:\KioskSetup\splash-task.xml" -Encoding Unicode
    Register-ScheduledTask -TaskName "TBI-KioskSplash" `
                           -Xml (Get-Content "C:\KioskSetup\splash-task.xml" -Raw) -Force | Out-Null
    Write-Log "Splash-taak geregistreerd voor: $username"
}

function Sync-LogoAssets {
    param([object]$Config)
    $logoDir = "C:\KioskSetup\logos"
    New-Item -ItemType Directory -Force -Path $logoDir | Out-Null

    # Download logos die we altijd nodig hebben
    $logos = @("tbi-wit.png", "tbi-paars.png")

    # Bedrijfsspecifiek logo toevoegen indien aanwezig
    $code = ($Config.computerNamePrefix -replace "-KIOSK","").ToLower()
    $logos += "$code-wit.png"

    $baseUrl = (Get-Content "C:\KioskSetup\baseurl.txt" -ErrorAction SilentlyContinue)?.Trim()
    if (-not $baseUrl) { return }

    foreach ($logo in $logos) {
        $dest = "$logoDir\$logo"
        if (-not (Test-Path $dest)) {
            try {
                Invoke-WebRequest -Uri "$baseUrl/assets/logos/$logo" `
                                  -OutFile $dest -UseBasicParsing -ErrorAction Stop
                Write-Log "Logo gedownload: $logo"
            } catch {
                # Geen probleem als bedrijfsspecifiek logo ontbreekt
            }
        }
    }
}
