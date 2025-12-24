<# 
    Setup-TBI-Kiosk.ps1
    USB → run → kiosk + wifi + local admin + TeamViewer + logging per PC
    Run ALS ADMINISTRATOR
#>

# 0. Admin check
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Run dit script als Administrator." -ForegroundColor Red
    exit 1
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 1. PC-nummer vragen
$pcLabel = Read-Host "Voer PC-nummer / label in (bijv. KIOSK-001)"
if ([string]::IsNullOrWhiteSpace($pcLabel)) {
    $pcLabel = $env:COMPUTERNAME
}

# 2. Logging inrichten
$LogRoot = "C:\TBI\KioskLogs"
if (-not (Test-Path $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$LogFile   = Join-Path $LogRoot ("{0}_{1}.log" -f $pcLabel, $timestamp)

Start-Transcript -Path $LogFile -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host $Message -ForegroundColor $Color
}

Write-Log "==> TBI Kiosk deploy gestart voor: $pcLabel" "Cyan"
Write-Log "Logbestand: $LogFile"

# 3. Optioneel computernaam wijzigen
$curName = $env:COMPUTERNAME
$answer  = Read-Host "Wil je de computernaam wijzigen naar '$pcLabel'? (J/N, leeg = N)"
$rebootNeeded = $false
if ($answer -match '^(j|J)$') {
    if ($pcLabel -ne $curName) {
        Write-Log "Computernaam wordt gewijzigd van '$curName' naar '$pcLabel'..."
        Rename-Computer -NewName $pcLabel -Force
        $rebootNeeded = $true
    } else {
        Write-Log "Computernaam blijft '$curName' (gelijk aan label)."
    }
} else {
    Write-Log "Computernaam NIET gewijzigd, blijft: $curName"
}

# 4. Kiosk basis
$KioskUserName = "kiosk"
$KioskPassword = "Bouwplaats!2025"
$FinalUrl      = "https://deslimmebouwplaats.nl/"
$KioskDir      = "C:\Kiosk"
$LogoFileName  = "Logo_TBI_RGB.png"
$KioskPage     = Join-Path $KioskDir "start.html"
$TaskName      = "Start Edge Kiosk"

if (-not (Test-Path $KioskDir)) {
    New-Item -Path $KioskDir -ItemType Directory -Force | Out-Null
    Write-Log "Map $KioskDir aangemaakt."
}

# 4a. logo kopiëren van USB -> C:\Kiosk
$UsbLogo = Join-Path $ScriptRoot $LogoFileName
if (Test-Path $UsbLogo) {
    Copy-Item -Path $UsbLogo -Destination (Join-Path $KioskDir $LogoFileName) -Force
    Write-Log "Logo gekopieerd naar C:\Kiosk\$LogoFileName"
} else {
    Write-Log "LET OP: Logo '$LogoFileName' niet gevonden op USB. Splash werkt maar zonder logo." "Yellow"
}

# 4b. kiosk user aanmaken
$localUser = Get-LocalUser -Name $KioskUserName -ErrorAction SilentlyContinue
if (-not $localUser) {
    $securePwd = ConvertTo-SecureString $KioskPassword -AsPlainText -Force
    New-LocalUser -Name $KioskUserName -Password $securePwd -FullName "Edge Kiosk User" -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    Write-Log "Kiosk user '$KioskUserName' aangemaakt."
} else {
    Write-Log "Kiosk user '$KioskUserName' bestond al."
}
Add-LocalGroupMember -Group "Users" -Member $KioskUserName -ErrorAction SilentlyContinue

# 4c. autologon
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
New-ItemProperty -Path $regPath -Name "AutoAdminLogon"    -Value "1"               -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "DefaultUserName"   -Value $KioskUserName    -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "DefaultPassword"   -Value $KioskPassword    -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME -PropertyType String -Force | Out-Null
Write-Log "Autologon ingesteld voor user '$KioskUserName'."

# 4d. HTML splash
$html = @'
<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8" />
  <title>TBI | De Slimme Bouwplaats</title>
  <meta http-equiv="refresh" content="3;url=__URL__" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    :root { --bg:#0b0b12; --accent:#5b1488; --text:#fff; }
    * { box-sizing:border-box; }
    body {
      margin:0; background:radial-gradient(circle at top, #202030 0%, #0b0b12 60%, #000 100%);
      height:100vh; display:flex; align-items:center; justify-content:center;
      font-family:system-ui,-apple-system,"Segoe UI",sans-serif; color:var(--text);
    }
    .wrap { text-align:center; max-width:650px; padding:2.5rem 2rem; }
    .logo img { max-width:360px; display:block; margin:0 auto 1.5rem auto; filter:drop-shadow(0 6px 20px rgba(0,0,0,.35)); }
    h1 { margin:0 0 .6rem 0; font-weight:600; font-size:1.9rem; }
    p { margin:0; opacity:.85; }
    .loader {
      margin:2rem auto 0 auto; width:48px; height:48px;
      border:4px solid rgba(255,255,255,0.18); border-top:4px solid var(--accent);
      border-radius:50%; animation:spin 1s linear infinite;
    }
    @keyframes spin { to { transform:rotate(360deg); } }
    .small { margin-top:1.4rem; font-size:.78rem; opacity:.5; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="logo">
      <img src="__LOGO__" alt="TBI" onerror="this.style.display='none'">
    </div>
    <h1>De Slimme Bouwplaats</h1>
    <p>We starten de omgeving voor je op...</p>
    <div class="loader" aria-label="Laden..."></div>
    <div class="small">TBI SSC-ICT · kioskmodus</div>
  </div>
</body>
</html>
'@

$html = $html -replace "__URL__", $FinalUrl
$html = $html -replace "__LOGO__", $LogoFileName
Set-Content -Path $KioskPage -Value $html -Encoding UTF8
Write-Log "Splashpagina geschreven naar $KioskPage"

# 4e. Edge + taak
$edgePaths = @(
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
)
$EdgeExe = $edgePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $EdgeExe) {
    Write-Log "Microsoft Edge niet gevonden - kiosk start niet op in browser!" "Red"
} else {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    $localPage = "file:///" + $KioskPage.Replace('\','/')
    $action    = New-ScheduledTaskAction -Execute $EdgeExe -Argument "--kiosk `"$localPage`" --edge-kiosk-type=fullscreen --no-first-run"
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User $KioskUserName
    $principal = New-ScheduledTaskPrincipal -UserId $KioskUserName -LogonType Interactive -RunLevel Highest
    $task      = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal
    Register-ScheduledTask -TaskName $TaskName -InputObject $task | Out-Null
    Write-Log "Scheduled task '$TaskName' is aangemaakt."
}

# 5. Wifi tijdelijk toevoegen
$wifiTemp = Join-Path $KioskDir ("wifi-" + [guid]::NewGuid().ToString("N"))
New-Item -Path $wifiTemp -ItemType Directory -Force | Out-Null

$wifi1 = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>Mobile1</name>
    <SSIDConfig>
        <SSID><name>Mobile1</name></SSID>
        <nonBroadcast>true</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>manual</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>1ntun3G0!</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
$wifi1Path = Join-Path $wifiTemp "Mobile1.xml"
$wifi1 | Set-Content -Path $wifi1Path -Encoding UTF8

$wifi2 = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>TBI-IoT</name>
    <SSIDConfig>
        <SSID><name>TBI-IoT</name></SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>1nt3rn3t0fTh1ngs</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
$wifi2Path = Join-Path $wifiTemp "TBI-IoT.xml"
$wifi2 | Set-Content -Path $wifi2Path -Encoding UTF8

netsh wlan add profile filename="$wifi2Path" user=all | Out-Null
netsh wlan add profile filename="$wifi1Path" user=all | Out-Null
Write-Log "Wifi-profielen Mobile1 en TBI-IoT toegevoegd."

netsh wlan connect name="TBI-IoT" | Out-Null
Start-Sleep -Seconds 3
netsh wlan connect name="Mobile1" | Out-Null
Write-Log "Wifi-connect geprobeerd."

Remove-Item -Path $wifiTemp -Recurse -Force

try {
    cipher /w:$KioskDir | Out-Null
    Write-Log "Vrije ruimte in $KioskDir overschreven."
} catch {
    Write-Log "cipher /w kon niet worden uitgevoerd." "Yellow"
}

# 6. Local admin + hide + RDP
$AdminUser = "tbiadmin"
$AdminPass = "@MartenMeesweg25"
if (-not (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue)) {
    $secureAdmin = ConvertTo-SecureString $AdminPass -AsPlainText -Force
    New-LocalUser -Name $AdminUser -Password $secureAdmin -FullName "TBI Remote Admin" -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    Write-Log "Beheeraccount '$AdminUser' aangemaakt."
} else {
    $secureAdmin = ConvertTo-SecureString $AdminPass -AsPlainText -Force
    Set-LocalUser -Name $AdminUser -Password $secureAdmin
    Write-Log "Beheeraccount '$AdminUser' bestond al, wachtwoord opnieuw gezet."
}
Add-LocalGroupMember -Group "Administrators" -Member $AdminUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Remote Desktop Users" -Member $AdminUser -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" | Out-Null

$hideKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
if (-not (Test-Path $hideKey)) {
    New-Item -Path $hideKey -Force | Out-Null
}
New-ItemProperty -Path $hideKey -Name $AdminUser -Value 0 -PropertyType DWord -Force | Out-Null
Write-Log "Beheeraccount '$AdminUser' toegevoegd aan admins, RDP aan en verborgen uit logon."

# 7. TeamViewer
Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show("TeamViewer Host wordt nu geïnstalleerd (als meegeleverd).","TBI Kiosk",'OK','Information') | Out-Null

$TvExe    = Join-Path $ScriptRoot "TeamViewer_Host_Setup.exe"
$TvOpt    = Join-Path $ScriptRoot "TVSettings.tvopt"
$TvAssign = Join-Path $ScriptRoot "TV_Assignment.txt"

if (Test-Path $TvExe) {
    $tvArgs = "/S"
    if (Test-Path $TvOpt) {
        $tvArgs += " SETTINGSFILE=`"$TvOpt`""
        Write-Log "TeamViewer settingsbestand gebruikt."
    }
    Start-Process -FilePath $TvExe -ArgumentList $tvArgs -Wait
    Write-Log "TeamViewer Host geïnstalleerd."
} else {
    Write-Log "TeamViewer setup NIET gevonden op USB - overslaan." "Yellow"
}

$tvId = $null
$tvBin1 = "$env:ProgramFiles\TeamViewer\TeamViewer.exe"
$tvBin2 = "$env:ProgramFiles(x86)\TeamViewer\TeamViewer.exe"
$tvBin  = if (Test-Path $tvBin1) { $tvBin1 } elseif (Test-Path $tvBin2) { $tvBin2 } else { $null }

if ($tvBin -and (Test-Path $TvAssign)) {
    $apiToken = Get-Content $TvAssign -Raw
    $alias    = $pcLabel
    Start-Process -FilePath $tvBin -ArgumentList "assign --api-token $apiToken --alias `"$alias`" --grant-easy-access" -Wait
    Write-Log "TeamViewer assigned met alias: $alias"
}

Start-Sleep -Seconds 4
$regBase = "HKLM:\SOFTWARE\WOW6432Node\TeamViewer"
if (Test-Path $regBase) {
    $tvId = (Get-ItemProperty -Path $regBase -Name ClientID -ErrorAction SilentlyContinue).ClientID
    if (-not $tvId) {
        Get-ChildItem $regBase | ForEach-Object {
            $cid = (Get-ItemProperty -Path $_.PsPath -Name ClientID -ErrorAction SilentlyContinue).ClientID
            if ($cid) { $tvId = $cid }
        }
    }
}

if ($tvId) {
    Write-Log "TeamViewer ID: $tvId" "Green"
    [System.Windows.MessageBox]::Show("TeamViewer ID: $tvId","TBI Kiosk",'OK','Information') | Out-Null
} else {
    Write-Log "TeamViewer ID kon niet worden bepaald (service nog niet klaar). Na reboot opnieuw checken." "Yellow"
}

Write-Log "=== DEPLOY KLAAR voor $pcLabel ===" "Cyan"
if ($rebootNeeded) {
    Write-Log "LET OP: reboot nodig vanwege naamswijziging." "Yellow"
}

# 8. Stop transcript
Stop-Transcript | Out-Null

# 9. Log kopiëren naar USB:\Logs
$UsbLogs = Join-Path $ScriptRoot "Logs"
try {
    if (-not (Test-Path $UsbLogs)) {
        New-Item -Path $UsbLogs -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path $LogFile -Destination $UsbLogs -Force
    Write-Host "Log gekopieerd naar USB: $UsbLogs" -ForegroundColor Green
} catch {
    Write-Host "Kon log niet kopiëren naar USB: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 10. Alle logs zippen op de pc
try {
    $zipPath = Join-Path $LogRoot "ALL-LOGS.zip"
    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $LogRoot "*") -DestinationPath $zipPath -Force
    Write-Host "Alle logs gecomprimeerd naar: $zipPath" -ForegroundColor Green
} catch {
    Write-Host "Kon ALL-LOGS.zip niet maken: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "Klaar. Log: $LogFile"
