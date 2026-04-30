# modules/branding.ps1 — TBI visuele branding

function Set-KioskBranding {
    param([object]$Config, [string]$BaseUrl)

    # ── 1. VERGRENDELSCHERM ACHTERGROND (TBI LOGO) ──────────────────────────
    $brandingDir = "C:\Windows\System32\oobe\info\backgrounds"
    New-Item -ItemType Directory -Force -Path $brandingDir | Out-Null

    # Download TBI lockscreen afbeelding van GitHub (assets/lockscreen.jpg)
    $lockscreenUrl  = "$BaseUrl/assets/lockscreen.jpg"
    $lockscreenPath = "$brandingDir\backgroundDefault.jpg"
    try {
        Invoke-WebRequest -Uri $lockscreenUrl -OutFile $lockscreenPath
        Write-Log "Vergrendelscherm afbeelding geïnstalleerd"
    } catch {
        Write-Log "Lockscreen afbeelding niet gevonden op GitHub — standaard behouden" "WARN"
    }

    # Activeer aangepast vergrendelscherm via policy
    $personalizationPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    New-Item -Path $personalizationPath -Force | Out-Null
    Set-ItemProperty -Path $personalizationPath -Name "LockScreenImage"          -Value $lockscreenPath
    Set-ItemProperty -Path $personalizationPath -Name "LockScreenOverlaysDisabled" -Value 1
    Set-ItemProperty -Path $personalizationPath -Name "NoChangingLockScreen"     -Value 1

    # ── 2. OEM-LOGO IN SYSTEEMINFORMATIE ────────────────────────────────────
    # Zichtbaar via: Instellingen → Systeem → Info
    $oemDir  = "C:\Windows\System32\oobe"
    $logoUrl = "$BaseUrl/assets/oem-logo.png"
    $logoPath = "$oemDir\tbi-oem.png"
    try {
        Invoke-WebRequest -Uri $logoUrl -OutFile $logoPath
    } catch {
        Write-Log "OEM-logo niet gevonden — overgeslagen" "WARN"
        $logoPath = $null
    }

    $oemRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
    New-Item -Path $oemRegPath -Force | Out-Null
    Set-ItemProperty -Path $oemRegPath -Name "Manufacturer"  -Value "TBI Holdings / SSC ICT"
    Set-ItemProperty -Path $oemRegPath -Name "SupportHours"  -Value "Ma-Vr 08:00-17:00"
    Set-ItemProperty -Path $oemRegPath -Name "SupportPhone"  -Value "+31 (0)70 xxx xxxx"
    Set-ItemProperty -Path $oemRegPath -Name "SupportURL"    -Value "https://www.tbi.nl"
    Set-ItemProperty -Path $oemRegPath -Name "Model"         -Value "TBI Kiosk — $($Config.displayName)"
    if ($logoPath) {
        Set-ItemProperty -Path $oemRegPath -Name "Logo" -Value $logoPath
    }

    # ── 3. COMPUTERNAAM INSTELLEN ────────────────────────────────────────────
    if ($Config.computerNamePrefix) {
        $ctbPath = "C:\KioskSetup\ctbnumber.txt"
        if (Test-Path $ctbPath) {
            $ctb = ([string](Get-Content $ctbPath -ErrorAction SilentlyContinue)).Trim().ToUpper() -replace '[^A-Z0-9\-]', ''
        } else {
            $ctb = $null
        }

        if ($ctb) {
            $newName = "$($Config.computerNamePrefix)-$ctb"
            # Max 15 tekens (NetBIOS-limiet)
            if ($newName.Length -gt 15) { $newName = $newName.Substring(0, 15) }
        } else {
            $suffix  = -join ((65..90) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
            $newName = "$($Config.computerNamePrefix)-$suffix"
        }

        Rename-Computer -NewName $newName -Force -ErrorAction SilentlyContinue
        Write-Log "Computernaam ingesteld: $newName$(if ($ctb) { ' (CTB: ' + $ctb + ')' })"
    }

    # ── 4. TAAKBALK & STARTMENU OPSCHONEN ────────────────────────────────────
    # Verberg zoekbalk, taakweergave, widgets op taakbalk
    $taskbarPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $taskbarPath -Name "ShowTaskViewButton" -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $taskbarPath -Name "TaskbarDa"          -Value 0 -ErrorAction SilentlyContinue  # Widgets

    $searchPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
    Set-ItemProperty -Path $searchPath -Name "SearchboxTaskbarMode" -Value 0 -ErrorAction SilentlyContinue

    Write-Log "Branding volledig toegepast voor: $($Config.displayName)"
}
