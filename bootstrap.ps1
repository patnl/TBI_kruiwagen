#Requires -RunAsAdministrator
<#
.SYNOPSIS
    TBI Kiosk Bootstrap — draait bij ELKE opstart
.DESCRIPTION
    Dit script is het enige dat éénmalig op de machine staat.
    Bij elke opstart haalt het de meest recente setup.ps1 + config
    op van GitHub en voert deze uit in update-modus.
    
    Zolang dit script op de machine staat, is GitHub de single source of truth.
    Pas config aan in GitHub → volgende boot past de pc zichzelf aan.
#>

# ── INSTELLINGEN (éénmalig vastgelegd bij initiële setup) ────────────────────
$GITHUB_ORG    = "patnl"       # ← wordt ingevuld door setup.ps1
$GITHUB_REPO   = "TBI_kruiwagen"
$GITHUB_BRANCH = "main"
$KIOSK_COMPANY = "BEDRIJF-HIER"        # ← wordt ingevuld door setup.ps1
$BASE_URL      = "https://raw.githubusercontent.com/$GITHUB_ORG/$GITHUB_REPO/$GITHUB_BRANCH"

$LogFile = "C:\KioskSetup\bootstrap_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Force -Path "C:\KioskSetup" | Out-Null

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -f 'HH:mm:ss')] [$Level] $Msg"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

# ── WACHT TOT NETWERK BESCHIKBAAR IS ────────────────────────────────────────
Write-Log "Wachten op netwerkverbinding..."
$maxWait = 120  # seconden
$waited  = 0
while ($waited -lt $maxWait) {
    try {
        $null = Invoke-WebRequest -Uri "https://raw.githubusercontent.com" `
                                  -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        Write-Log "Netwerk beschikbaar na ${waited}s"
        break
    } catch {
        Start-Sleep -Seconds 5
        $waited += 5
    }
}

if ($waited -ge $maxWait) {
    Write-Log "Geen internet na ${maxWait}s — offline opstarten met huidige inrichting" "WARN"
    exit 0   # Niet crashen — pc start gewoon op met vorige inrichting
}

# ── VERSIECHECK: alleen updaten als GitHub nieuwer is ────────────────────────
$versionUrl   = "$BASE_URL/version.txt"
$versionLocal = "C:\KioskSetup\version.txt"
$remoteVersion = $null

try {
    $remoteVersion = (Invoke-RestMethod -Uri $versionUrl -ErrorAction Stop).Trim()
    $localVersion  = if (Test-Path $versionLocal) { (Get-Content $versionLocal).Trim() } else { "0" }

    if ($remoteVersion -eq $localVersion) {
        Write-Log "Versie up-to-date ($remoteVersion) — geen update nodig"
        exit 0
    }
    Write-Log "Update beschikbaar: $localVersion → $remoteVersion"
} catch {
    Write-Log "Geen version.txt gevonden — altijd updaten (eerste run of debug)" "WARN"
}

# ── SETUP OPHALEN EN UITVOEREN ────────────────────────────────────────────────
Write-Log "setup.ps1 ophalen van GitHub..."
try {
    $setupScript = Invoke-RestMethod -Uri "$BASE_URL/setup.ps1" -ErrorAction Stop
    $setupPath   = "C:\KioskSetup\setup_latest.ps1"
    $setupScript | Out-File -FilePath $setupPath -Encoding UTF8

    Write-Log "setup.ps1 uitvoeren in update-modus voor: $KIOSK_COMPANY"
    $env:KIOSK_COMPANY     = $KIOSK_COMPANY
    $env:KIOSK_UPDATE_ONLY = "1"         # Sla destructieve stappen over (account, reboot)
    & $setupPath

    # Versie opslaan na succesvolle update
    if ($remoteVersion) { $remoteVersion | Out-File $versionLocal -Encoding UTF8 }
    Write-Log "Bootstrap voltooid — versie $remoteVersion actief"

} catch {
    Write-Log "Bootstrap mislukt: $_" "ERROR"
    # Stille fout — pc start gewoon op, geen panic
}
