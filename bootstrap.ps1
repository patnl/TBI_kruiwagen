#Requires -RunAsAdministrator
<#
.SYNOPSIS
    TBI Kiosk Bootstrap — draait bij ELKE opstart
.DESCRIPTION
    Dit script is het enige dat éénmalig op de machine staat.
    Bij elke opstart:
      1. Leest de vaste redirect-URL (Gist) om de actuele repo-locatie te weten
      2. Als de repo verhuisd is: herstelt zichzelf automatisch met het nieuwe adres
      3. Haalt setup.ps1 op van de actuele repo en voert deze uit in update-modus

    Vaste aanwijzer (wijzigt nooit):
      C:\KioskSetup\pointer.txt — bevat de Gist-URL naar redirect.json
    
    Repo verplaatst? Pas redirect.json in de Gist aan — alle kiosks
    herstellen zichzelf bij de volgende opstart automatisch.
#>

# ── INSTELLINGEN (ingevuld door setup.ps1 bij initiële installatie) ──────────
$GITHUB_ORG    = "patnl"
$GITHUB_REPO   = "TBI_kruiwagen"
$GITHUB_BRANCH = "main"
$KIOSK_COMPANY = "BEDRIJF-HIER"
$BASE_URL      = "https://raw.githubusercontent.com/$GITHUB_ORG/$GITHUB_REPO/$GITHUB_BRANCH"

# ── CONSTANTEN ────────────────────────────────────────────────────────────────
$KioskDir    = "C:\KioskSetup"
$PointerFile = "$KioskDir\pointer.txt"
$LogFile     = "$KioskDir\bootstrap_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Force -Path $KioskDir | Out-Null

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -f 'HH:mm:ss')] [$Level] $Msg"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

# ── WACHT TOT NETWERK BESCHIKBAAR IS ─────────────────────────────────────────
Write-Log "Wachten op netwerkverbinding..."
$maxWait = 120
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
    exit 0
}

# ── STAP 1: REDIRECT CONTROLEREN VIA VASTE GIST-URL ─────────────────────────
# pointer.txt bevat de Gist-URL — die URL verandert nooit, ook niet als repo verhuist
$pointerUrl = if (Test-Path $PointerFile) {
    ([string](Get-Content $PointerFile -ErrorAction SilentlyContinue)).Trim()
} else { $null }

if ($pointerUrl) {
    try {
        Write-Log "Redirect controleren via: $pointerUrl"
        $redirect = Invoke-RestMethod -Uri $pointerUrl -ErrorAction Stop

        $newOrg    = $redirect.org.Trim()
        $newRepo   = $redirect.repo.Trim()
        $newBranch = $redirect.branch.Trim()
        $newBase   = "https://raw.githubusercontent.com/$newOrg/$newRepo/$newBranch"

        if ($newBase -ne $BASE_URL) {
            Write-Log "Repo verplaatst! Oud: $BASE_URL" "WARN"
            Write-Log "Nieuw adres: $newBase" "WARN"

            # Zichzelf herstellen: bootstrap.ps1 op schijf bijwerken met nieuw adres
            $selfPath = $MyInvocation.MyCommand.Path
            if ($selfPath -and (Test-Path $selfPath)) {
                $content = Get-Content $selfPath -Raw
                $content = $content -replace [regex]::Escape($GITHUB_ORG),    $newOrg
                $content = $content -replace [regex]::Escape($GITHUB_REPO),   $newRepo
                $content = $content -replace [regex]::Escape($GITHUB_BRANCH), $newBranch
                $content | Out-File $selfPath -Encoding UTF8 -Force
                Write-Log "bootstrap.ps1 bijgewerkt met nieuw repo-adres"
            }

            # Gebruik voortaan het nieuwe adres
            $BASE_URL      = $newBase
            $GITHUB_ORG    = $newOrg
            $GITHUB_REPO   = $newRepo
            $GITHUB_BRANCH = $newBranch

            # Sla nieuwe URL ook op in lokale bestanden
            $newOrg    | Out-File "$KioskDir\org.txt"    -Encoding UTF8
            $newRepo   | Out-File "$KioskDir\repo.txt"   -Encoding UTF8
            $newBase   | Out-File "$KioskDir\baseurl.txt" -Encoding UTF8
        } else {
            Write-Log "Repo-locatie ongewijzigd — $BASE_URL"
        }
    } catch {
        Write-Log "Redirect-check mislukt (Gist niet bereikbaar?) — huidig adres gebruiken" "WARN"
        Write-Log "  $_" "WARN"
    }
} else {
    Write-Log "Geen pointer.txt gevonden — vaste BASE_URL gebruiken (geen redirect-check)" "WARN"
}

# ── STAP 2: REINSTALL-SIGNAAL CONTROLEREN ────────────────────────────────────
# Kijk of er een herinstallatie-signaal staat in de repo voor deze machine of ALL
$computerName   = $env:COMPUTERNAME
$reinstallFlag  = "$KioskDir\reinstall-done.txt"
$reinstallUrls  = @(
    "$BASE_URL/reinstall/$computerName",
    "$BASE_URL/reinstall/ALL"
)

$reinstallTriggered = $false
$reinstallTarget    = $null

foreach ($url in $reinstallUrls) {
    try {
        $null = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $reinstallTarget = $url
        $reinstallTriggered = $true
        Write-Log "Reinstall-signaal gevonden: $url" "WARN"
        break
    } catch {
        # 404 = geen signaal, doorgaan
    }
}

if ($reinstallTriggered) {
    # Voorkom herhaalde reinstall als het signaalbestand niet verwijderd kon worden
    $doneContent = if (Test-Path $reinstallFlag) { Get-Content $reinstallFlag } else { "" }
    if ($doneContent -eq $reinstallTarget) {
        Write-Log "Reinstall al uitgevoerd voor dit signaal — overgeslagen"
    } else {
        Write-Log "Volledige herinstallatie starten..." "WARN"

        # Bewaar company en pointer — rest weggooien
        $company = if (Test-Path "$KioskDir\company.txt") { Get-Content "$KioskDir\company.txt" } else { $KIOSK_COMPANY }
        $pointer = if (Test-Path "$KioskDir\pointer.txt") { Get-Content "$KioskDir\pointer.txt" } else { $null }

        # Verwijder volledige KioskSetup map
        Get-ChildItem $KioskDir -Exclude "bootstrap*.ps1","bootstrap*.log" |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        # Herstel essentials
        New-Item -ItemType Directory -Force -Path $KioskDir | Out-Null
        if ($pointer) { $pointer | Out-File "$KioskDir\pointer.txt" -Encoding UTF8 }

        # Ophalen en uitvoeren als volledige setup (NIET update-modus)
        $setupScript = Invoke-RestMethod -Uri "$BASE_URL/setup.ps1" -ErrorAction Stop
        $setupPath   = "$KioskDir\setup_latest.ps1"
        $setupScript | Out-File $setupPath -Encoding UTF8

        Write-Log "setup.ps1 uitvoeren als VOLLEDIGE herinstallatie voor: $company"
        $env:KIOSK_COMPANY     = $company
        $env:KIOSK_UPDATE_ONLY = ""   # Leeg = volledige setup inclusief accounts, reboot etc.
        & $setupPath

        # Markeer lokaal dat dit signaal al verwerkt is
        $reinstallTarget | Out-File $reinstallFlag -Encoding UTF8

        # Probeer het signaalbestand te verwijderen via GitHub API (vereist PAT)
        $patFile = "$KioskDir\.ghpat"
        if (Test-Path $patFile) {
            try {
                $pat     = [System.Text.Encoding]::UTF8.GetString(
                               [System.Security.Cryptography.ProtectedData]::Unprotect(
                                   [System.Convert]::FromBase64String((Get-Content $patFile)),
                                   $null,
                                   [System.Security.Cryptography.DataProtectionScope]::LocalMachine))
                $apiBase = "https://api.github.com/repos/$GITHUB_ORG/$GITHUB_REPO/contents"
                $signal  = $reinstallTarget -replace ".*reinstall/", "reinstall/"
                $fileInfo = Invoke-RestMethod -Uri "$apiBase/$signal" `
                                -Headers @{ Authorization = "token $pat"; "User-Agent" = "TBI-Kiosk" } `
                                -ErrorAction Stop
                $body = @{ message = "Reinstall voltooid: $computerName"; sha = $fileInfo.sha } | ConvertTo-Json
                Invoke-RestMethod -Uri "$apiBase/$signal" -Method Delete -Body $body `
                    -Headers @{ Authorization = "token $pat"; "User-Agent" = "TBI-Kiosk"; "Content-Type" = "application/json" } `
                    -ErrorAction Stop
                Write-Log "Reinstall-signaal verwijderd van GitHub"
            } catch {
                Write-Log "Signaalbestand kon niet worden verwijderd (PAT probleem?) — lokale vlag gebruikt" "WARN"
            }
        } else {
            Write-Log "Geen PAT aanwezig — signaalbestand blijft op GitHub staan (lokale vlag voorkomt herhaling)"
        }
        exit 0
    }
}

# ── STAP 3: VERSIECHECK ───────────────────────────────────────────────────────    = "$BASE_URL/version.txt"
$versionLocal  = "$KioskDir\version.txt"
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
    Write-Log "Geen version.txt gevonden — update uitvoeren" "WARN"
}

# ── STAP 4: SETUP OPHALEN EN UITVOEREN ───────────────────────────────────────
Write-Log "setup.ps1 ophalen van $BASE_URL ..."
try {
    $setupScript = Invoke-RestMethod -Uri "$BASE_URL/setup.ps1" -ErrorAction Stop
    $setupPath   = "$KioskDir\setup_latest.ps1"
    $setupScript | Out-File -FilePath $setupPath -Encoding UTF8

    Write-Log "setup.ps1 uitvoeren in update-modus voor: $KIOSK_COMPANY"
    $env:KIOSK_COMPANY     = $KIOSK_COMPANY
    $env:KIOSK_UPDATE_ONLY = "1"
    & $setupPath

    if ($remoteVersion) { $remoteVersion | Out-File $versionLocal -Encoding UTF8 }
    Write-Log "Bootstrap voltooid — versie $remoteVersion actief"

} catch {
    Write-Log "Bootstrap mislukt: $_" "ERROR"
}
