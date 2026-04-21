# modules/dalux.ps1 — Dalux Field kiosk installatie

function Install-DaluxApp {
    param([object]$Config)

    $dalux = $Config.dalux
    $installDir = "C:\Program Files\Dalux"

    # ── DETECTEER BESTAANDE INSTALLATIE ─────────────────────────────────────
    $exePath = Get-DaluxExePath
    if ($exePath -and -not $dalux.forceReinstall) {
        Write-Log "Dalux al geïnstalleerd: $exePath — versiecheck..."
        $installedVersion = (Get-Item $exePath).VersionInfo.FileVersion
        Write-Log "Geïnstalleerde versie: $installedVersion"

        if ($dalux.version -and $installedVersion -eq $dalux.version) {
            Write-Log "Dalux versie is up-to-date — installatie overgeslagen"
            return
        }
        Write-Log "Update nodig: $installedVersion → $($dalux.version)"
    }

    # ── INSTALLATIEBRON BEPALEN ──────────────────────────────────────────────
    # Optie A: Winget (aanbevolen — altijd laatste versie)
    $wingetAvail = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetAvail -and -not $dalux.installerUrl) {
        Write-Log "Dalux installeren via winget..."
        $result = winget install --id Dalux.DaluxField `
                                 --silent --accept-package-agreements `
                                 --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -or $result -match "successfully installed") {
            Write-Log "Dalux geïnstalleerd via winget"
        } else {
            Write-Log "Winget mislukt — fallback naar directe download" "WARN"
            Install-DaluxDirect -Config $Config
        }

    # Optie B: Directe installer-URL (vanuit config of GitHub assets)
    } else {
        Install-DaluxDirect -Config $Config
    }

    # ── WACHT OP EXECUTABLE ──────────────────────────────────────────────────
    $timeout = 60
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $exePath = Get-DaluxExePath
        if ($exePath) { Write-Log "Dalux executable gevonden: $exePath"; break }
        Start-Sleep -Seconds 3
        $elapsed += 3
    }

    if (-not (Get-DaluxExePath)) {
        Write-Log "Dalux executable niet gevonden na installatie" "ERROR"
        throw "Dalux installatie mislukt"
    }

    # ── DALUX LOGIN PRE-CONFIGUREREN (optioneel) ──────────────────────────────
    if ($dalux.projectCode) {
        $configDir = "$env:APPDATA\Dalux\DaluxField"
        New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        $prefs = @{
            lastProjectCode = $dalux.projectCode
            autoLogin       = $false
            language        = "nl"
        } | ConvertTo-Json
        $prefs | Out-File "$configDir\preferences.json" -Encoding UTF8
        Write-Log "Dalux projectcode vooringesteld: $($dalux.projectCode)"
    }

    Write-Log "Dalux installatie voltooid"
}

function Install-DaluxDirect {
    param([object]$Config)
    $dalux = $Config.dalux

    # Installer-URL: uit config of vanuit GitHub assets
    $installerUrl = if ($dalux.installerUrl) {
        $dalux.installerUrl
    } else {
        # Officiële Dalux download (controleer op actuele URL bij nieuwe versies)
        "https://download.dalux.com/DaluxField/DaluxField_Setup.exe"
    }

    $installerPath = "C:\KioskSetup\DaluxField_Setup.exe"
    Write-Log "Dalux downloaden van: $installerUrl"
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Log "Dalux silent installatie starten..."
    # /S = silent (NSIS-stijl installer)
    # /D = installatiepad
    Start-Process $installerPath -ArgumentList "/S /D=`"C:\Program Files\Dalux`"" -Wait
    Remove-Item $installerPath -ErrorAction SilentlyContinue
}

function Get-DaluxExePath {
    # Zoek Dalux executable op bekende locaties
    $candidates = @(
        "C:\Program Files\Dalux\DaluxField\DaluxField.exe",
        "C:\Program Files\Dalux\DaluxField.exe",
        "C:\Program Files (x86)\Dalux\DaluxField\DaluxField.exe",
        "$env:LOCALAPPDATA\Programs\Dalux\DaluxField\DaluxField.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    # Zoek via registry (fallback)
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\DaluxField.exe"
    if (Test-Path $regPath) {
        return (Get-ItemProperty -Path $regPath)."(default)"
    }
    return $null
}

function Set-DaluxKioskShell {
    param([object]$Config)
    # Wordt aangeroepen vanuit kiosk-shell.ps1 als appMode = "dalux"
    return (Get-DaluxExePath)
}
