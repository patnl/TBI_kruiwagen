# modules/kiosk-shell.ps1 — App-agnostische kiosk shell + bootstrap registratie

function Set-KioskShell {
    param([object]$Config)

    $username = $Config.kioskUser.username
    $appMode  = if ($Config.appMode) { $Config.appMode } else { "browser" }

    # ── BEPAAL UIT TE VOEREN APPLICATIE OP BASIS VAN appMode ─────────────────
    switch ($appMode) {
        "dalux" {
            $appExe  = Get-DaluxExePath
            $appArgs = ""
            if (-not $appExe) { throw "Dalux executable niet gevonden — eerst Install-DaluxApp uitvoeren" }
            Write-Log "Kiosk app: Dalux Field ($appExe)"
        }
        "browser" {
            $appExe  = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
            $primaryUrl = $Config.browser.urls[0]
            $appArgs = "--kiosk $primaryUrl --edge-kiosk-type=fullscreen --no-first-run --start-maximized"
            Write-Log "Kiosk app: Edge → $primaryUrl"
        }
        default {
            # Vrij te configureren — pad direct in config opgeven
            $appExe  = $Config.customApp.exePath
            $appArgs = $Config.customApp.arguments ?? ""
            Write-Log "Kiosk app: custom ($appExe)"
        }
    }

    # ── METHODE A: Shell Launcher (Windows 11 Pro/Enterprise) ────────────────
    $feature = Get-WindowsOptionalFeature -Online -FeatureName "Client-EmbeddedShellLauncher" `
               -ErrorAction SilentlyContinue

    if ($feature -and $feature.State -eq "Enabled") {
        Write-Log "Shell Launcher actief — kiosk-shell instellen"
        $wmi = [wmiclass]"\\.\root\standardcimv2\embedded:WESL_UserSetting"
        $sid = (New-Object System.Security.Principal.NTAccount($username)).Translate(
                    [System.Security.Principal.SecurityIdentifier]).Value
        $wmi.SetCustomShell($sid, "`"$appExe`" $appArgs", $null, $null, 0)
        $wmi.SetEnabled($true)
        Write-Log "Shell Launcher: $appExe $appArgs"

    } else {
        # ── METHODE B: Geplande taak bij logon (breed compatibel) ────────────
        Write-Log "Shell Launcher niet beschikbaar — logon-taak als fallback" "WARN"
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$env:COMPUTERNAME\$username</UserId>
      <Delay>PT5S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$env:COMPUTERNAME\$username</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <RestartOnFailure><Interval>PT30S</Interval><Count>999</Count></RestartOnFailure>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
  </Settings>
  <Actions>
    <Exec>
      <Command>"$appExe"</Command>
      <Arguments>$appArgs</Arguments>
    </Exec>
  </Actions>
</Task>
"@
        $taskXml | Out-File "C:\KioskSetup\app-start.xml" -Encoding Unicode
        Register-ScheduledTask -TaskName "TBI-KioskAppStart" `
                               -Xml (Get-Content "C:\KioskSetup\app-start.xml" -Raw) -Force | Out-Null
        Write-Log "Logon-taak aangemaakt: TBI-KioskAppStart"
    }

    # ── SYSTEEMBEVEILIGINGEN VOOR KIOSK ──────────────────────────────────────
    $pol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Set-ItemProperty -Path $pol -Name "DisableLockWorkstation" -Value 1
    Set-ItemProperty -Path $pol -Name "DisableChangePassword"  -Value 1
    Set-ItemProperty -Path $pol -Name "ShutdownWithoutLogon"   -Value 0
}

function Register-UpdateTask {
    param([string]$BaseUrl, [string]$Company, [string]$GithubOrg, [string]$GithubRepo, [string]$GithubBranch)

    $bootstrapSrc = "C:\KioskSetup\bootstrap_template.ps1"
    $bootstrapDst = "C:\KioskSetup\bootstrap.ps1"

    # ── STAP 1: Haal bootstrap.ps1 op van GitHub en vul variabelen in ────────
    try {
        $raw = Invoke-RestMethod -Uri "$BaseUrl/bootstrap.ps1" -ErrorAction Stop
        $raw = $raw -replace 'JOUW-ORG-HIER',   $GithubOrg
        $raw = $raw -replace 'kiosk-setup',      $GithubRepo
        $raw = $raw -replace 'BEDRIJF-HIER',     $Company
        $raw = $raw -replace '"main"',            "`"$GithubBranch`""
        $raw | Out-File -FilePath $bootstrapDst -Encoding UTF8
        Write-Log "Bootstrap geïnstalleerd: $bootstrapDst"
    } catch {
        Write-Log "Bootstrap download mislukt — daily-update als fallback" "WARN"
    }

    # ── STAP 2: Boot-trigger taak (elke opstart → GitHub check) ──────────────
    # Dit is de sleutel: BootTrigger zorgt dat elke opstart de laatste config trekt
    $bootTaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger>
      <Enabled>true</Enabled>
      <Delay>PT15S</Delay>
    </BootTrigger>
  </Triggers>
  <Principals>
    <Principal id="System">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <RestartOnFailure><Interval>PT2M</Interval><Count>3</Count></RestartOnFailure>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "C:\KioskSetup\bootstrap.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $bootTaskXml | Out-File "C:\KioskSetup\boot-update.xml" -Encoding Unicode
    Register-ScheduledTask -TaskName "TBI-KioskBootUpdate" `
                           -Xml (Get-Content "C:\KioskSetup\boot-update.xml" -Raw) -Force | Out-Null
    Write-Log "Boot-update taak aangemaakt (15s na elke opstart — GitHub sync)"

    # ── STAP 3: Dagelijkse taak als extra vangnet (offline gehad? 03:00 sync) ─
    $dailyTrigger    = New-ScheduledTaskTrigger -Daily -At "03:00"
    $dailyAction     = New-ScheduledTaskAction -Execute "powershell.exe" `
                       -Argument "-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File `"$bootstrapDst`""
    $dailyPrincipal  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "TBI-KioskDailyUpdate" `
                           -Trigger $dailyTrigger -Action $dailyAction -Principal $dailyPrincipal `
                           -Description "TBI Kiosk nacht-sync als vangnet bij gemiste bootrun" `
                           -Force | Out-Null
    Write-Log "Nacht-sync taak aangemaakt (03:00 — vangnet)"
}
