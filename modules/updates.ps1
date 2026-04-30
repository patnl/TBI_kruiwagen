# modules/updates.ps1
# Automatische updates: Windows Update + Lenovo/HP fabrikantstooling
# Fabrikant wordt automatisch gedetecteerd via WMI — geen handmatige invoer nodig

function Set-AutoUpdate {
    param([object]$Config)

    # ── 1. FABRIKANT DETECTEREN ───────────────────────────────────────────────
    $manufacturer = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer
    $model        = (Get-WmiObject Win32_ComputerSystem -ErrorAction SilentlyContinue).Model

    if (-not $manufacturer) {
        Write-Log "Fabrikant niet detecteerbaar — OEM-tooling overgeslagen" "WARN"
        $manufacturer = "Onbekend"
    }

    Write-Log "Hardware: $manufacturer — $model"

    # ── 2. WINDOWS UPDATE INSTELLEN (automatisch, 's nachts) ─────────────────
    $wuPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    New-Item -Path $wuPath -Force | Out-Null

    # AUOptions 4 = Automatisch downloaden en installeren
    Set-ItemProperty -Path $wuPath -Name "NoAutoUpdate"               -Value 0
    Set-ItemProperty -Path $wuPath -Name "AUOptions"                  -Value 4
    Set-ItemProperty -Path $wuPath -Name "AutoInstallMinorUpdates"    -Value 1
    Set-ItemProperty -Path $wuPath -Name "ScheduledInstallDay"        -Value 0   # Elke dag
    Set-ItemProperty -Path $wuPath -Name "ScheduledInstallTime"       -Value 3   # 03:00
    Set-ItemProperty -Path $wuPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 0
    Set-ItemProperty -Path $wuPath -Name "RebootWarningTimeoutEnabled" -Value 1
    Set-ItemProperty -Path $wuPath -Name "RebootWarningTimeout"        -Value 5  # 5 min waarschuwing

    # Windows Update service op automatisch zetten
    Set-Service -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue

    Write-Log "Windows Update: automatisch ingesteld (dagelijks 03:00)"

    # ── 3. OEM-TOOLING ────────────────────────────────────────────────────────
    $isLenovo = $manufacturer -match "Lenovo"
    $isHP     = $manufacturer -match "HP|Hewlett"
    $isDell   = $manufacturer -match "Dell"

    if ($isLenovo) {
        Install-LenovoSystemUpdate
    } elseif ($isHP) {
        Install-HPSupportAssistant
    } elseif ($isDell) {
        Install-DellCommandUpdate
    } else {
        Write-Log "Fabrikant '$manufacturer' — geen specifieke OEM-tooling beschikbaar"
    }
}

function Install-LenovoSystemUpdate {
    Write-Log "Lenovo gedetecteerd — Lenovo System Update installeren..."

    # Controleer of al geinstalleerd
    $lsuPath = "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe"
    if (Test-Path $lsuPath) {
        Write-Log "Lenovo System Update al aanwezig — update uitvoeren"
        Start-Process $lsuPath -ArgumentList "/CM -search A -action INSTALL -includerebootpackages 3 -noreboot" `
                      -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Log "Lenovo System Update: scan voltooid"
        return
    }

    # Installeren via winget
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Log "Installeren via winget: Lenovo.SystemUpdate"
        $result = winget install --id Lenovo.SystemUpdate --silent --accept-package-agreements `
                                 --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -or $result -match "successfully") {
            Write-Log "Lenovo System Update geinstalleerd"
        } else {
            Write-Log "Winget installatie mislukt — directe download proberen" "WARN"
            Install-LenovoSystemUpdateDirect
        }
    } else {
        Install-LenovoSystemUpdateDirect
    }

    # Geplande taak: Lenovo updates wekelijks op maandag 22:00
    $action    = New-ScheduledTaskAction -Execute "C:\Program Files (x86)\Lenovo\System Update\tvsu.exe" `
                     -Argument "/CM -search A -action INSTALL -includerebootpackages 3 -noreboot"
    $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "22:00"
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "TBI-LenovoSystemUpdate" `
                           -Action $action -Trigger $trigger -Principal $principal `
                           -Description "Wekelijkse Lenovo System Update — TBI Kiosk" `
                           -Force | Out-Null
    Write-Log "Geplande taak aangemaakt: TBI-LenovoSystemUpdate (maandag 22:00)"
}

function Install-LenovoSystemUpdateDirect {
    # Directe download van Lenovo
    $url  = "https://download.lenovo.com/pccbbs/thinkvantage_en/system_update_5.08.01.18.exe"
    $dest = "C:\KioskSetup\LenovoSystemUpdate_Setup.exe"
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Start-Process $dest -ArgumentList "/VERYSILENT /NORESTART" -Wait
        Remove-Item $dest -ErrorAction SilentlyContinue
        Write-Log "Lenovo System Update geinstalleerd via directe download"
    } catch {
        Write-Log "Lenovo System Update download mislukt: $_" "WARN"
    }
}

function Install-HPSupportAssistant {
    Write-Log "HP gedetecteerd — HP Support Assistant controleren..."

    # Controleer of al geinstalleerd
    $hpsaPath = "${env:ProgramFiles(x86)}\HP\HP Support Framework\HPSF.exe"
    $hpsaPath2 = "$env:ProgramFiles\HP\HP Support Framework\HPSF.exe"
    if ((Test-Path $hpsaPath) -or (Test-Path $hpsaPath2)) {
        Write-Log "HP Support Assistant al aanwezig"
        # Stille scan uitvoeren
        $exe = if (Test-Path $hpsaPath) { $hpsaPath } else { $hpsaPath2 }
        Start-Process $exe -ArgumentList "/s /a /f2C:\KioskSetup\hpsa_install.log" `
                      -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Log "HP Support Assistant: aanwezig en geconfigureerd"
        return
    }

    # Installeren via winget
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Log "Installeren via winget: HP.HPSupportAssistant"
        $result = winget install --id HP.HPSupportAssistant --silent --accept-package-agreements `
                                 --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -or $result -match "successfully") {
            Write-Log "HP Support Assistant geinstalleerd"
        } else {
            Write-Log "Winget installatie mislukt — directe download proberen" "WARN"
            Install-HPSupportAssistantDirect
        }
    } else {
        Install-HPSupportAssistantDirect
    }

    # Geplande taak: HP updates wekelijks op maandag 22:00
    $hpExe  = if (Test-Path $hpsaPath) { $hpsaPath } else { $hpsaPath2 }
    if (Test-Path $hpExe) {
        $action    = New-ScheduledTaskAction -Execute $hpExe -Argument "/s /a"
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "22:00"
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        Register-ScheduledTask -TaskName "TBI-HPSupportAssistant" `
                               -Action $action -Trigger $trigger -Principal $principal `
                               -Description "Wekelijkse HP updates — TBI Kiosk" `
                               -Force | Out-Null
        Write-Log "Geplande taak aangemaakt: TBI-HPSupportAssistant (maandag 22:00)"
    }
}

function Install-HPSupportAssistantDirect {
    $url  = "https://ftp.hp.com/pub/caps-softpaq/cmit/HPSA_Setup_Assistant.exe"
    $dest = "C:\KioskSetup\HPSupportAssistant_Setup.exe"
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Start-Process $dest -ArgumentList "/s /a /f2C:\KioskSetup\hpsa_install.log" -Wait
        Remove-Item $dest -ErrorAction SilentlyContinue
        Write-Log "HP Support Assistant geinstalleerd via directe download"
    } catch {
        Write-Log "HP Support Assistant download mislukt: $_" "WARN"
    }
}

function Install-DellCommandUpdate {
    Write-Log "Dell gedetecteerd — Dell Command Update installeren..."

    # Controleer of al geinstalleerd
    $dcuPaths = @(
        "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe",
        "C:\Program Files (x86)\Dell\CommandUpdate\dcu-cli.exe"
    )
    $dcuExe = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($dcuExe) {
        Write-Log "Dell Command Update al aanwezig — scan uitvoeren"
        Start-Process $dcuExe -ArgumentList "/applyUpdates -autoSuspendBitLocker=enable -reboot=disable" `
                      -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Log "Dell Command Update: scan voltooid"
    } else {
        # Installeren via winget
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Log "Installeren via winget: Dell.CommandUpdate"
            $result = winget install --id Dell.CommandUpdate --silent --accept-package-agreements `
                                     --accept-source-agreements 2>&1
            if ($LASTEXITCODE -eq 0 -or $result -match "successfully") {
                Write-Log "Dell Command Update geinstalleerd"
                $dcuExe = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            } else {
                Write-Log "Winget installatie mislukt — directe download proberen" "WARN"
                Install-DellCommandUpdateDirect
                $dcuExe = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            }
        } else {
            Install-DellCommandUpdateDirect
            $dcuExe = $dcuPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        }
    }

    # Geplande taak: Dell updates wekelijks op maandag 22:00
    if ($dcuExe) {
        $action    = New-ScheduledTaskAction -Execute $dcuExe `
                         -Argument "/applyUpdates -autoSuspendBitLocker=enable -reboot=disable"
        $trigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "22:00"
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
        Register-ScheduledTask -TaskName "TBI-DellCommandUpdate" `
                               -Action $action -Trigger $trigger -Principal $principal `
                               -Description "Wekelijkse Dell updates — TBI Kiosk" `
                               -Force | Out-Null
        Write-Log "Geplande taak aangemaakt: TBI-DellCommandUpdate (maandag 22:00)"
    }
}

function Install-DellCommandUpdateDirect {
    # Dell Command Update directe download (controleer URL bij nieuwe versies)
    $url  = "https://dl.dell.com/FOLDER11452429M/1/Dell-Command-Update-Application_XXXXX.EXE"
    $dest = "C:\KioskSetup\DellCommandUpdate_Setup.exe"
    Write-Log "Dell Command Update directe download — URL controleren op dell.com/support" "WARN"
    # Winget verdient de voorkeur; directe URL wijzigt per versie
    # Zie: https://www.dell.com/support/kbdoc/nl-nl/000177325
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Start-Process $dest -ArgumentList "/s" -Wait
        Remove-Item $dest -ErrorAction SilentlyContinue
        Write-Log "Dell Command Update geinstalleerd via directe download"
    } catch {
        Write-Log "Dell Command Update download mislukt — installeer handmatig via dell.com/support" "WARN"
    }
}
