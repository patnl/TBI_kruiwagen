#Requires -RunAsAdministrator
<#
.SYNOPSIS
    TBI Kiosk PC Setup Script — GitHub-managed
.USAGE
    (Admin PowerShell, éénmalig):
    Set-ExecutionPolicy Bypass -Scope Process -Force
    irm https://raw.githubusercontent.com/patnl/TBI_kruiwagen/main/setup.ps1 | iex
#>

# ── CONFIG ────────────────────────────────────────────────────────────────────
$GITHUB_ORG    = "patnl"
$GITHUB_REPO   = "TBI_kruiwagen"
$GITHUB_BRANCH = "main"
$BASE_URL      = "https://raw.githubusercontent.com/$GITHUB_ORG/$GITHUB_REPO/$GITHUB_BRANCH"

# Vaste Gist-URL — wijzigt nooit, ook niet als de repo verplaatst
# Maak deze Gist éénmalig aan op github.com/gist en zet de URL hieronder
$REDIRECT_GIST_URL = "https://gist.githubusercontent.com/patnl/5b15d822bbfd79c915bf22494831e8aa/raw/redirect.json"

# ── WINDOWS EDITIE CONTROLE ───────────────────────────────────────────────────
$winEdition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").EditionID
$winBuild   = [int](Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").CurrentBuildNumber
$winVersion = if ($winBuild -ge 22000) { "Windows 11" } else { "Windows 10" }

if ($winEdition -like "*Core*" -or $winEdition -like "*Home*") {
    Write-Host ""
    Write-Host "  WAARSCHUWING: $winVersion Home gedetecteerd ($winEdition)" -ForegroundColor Yellow
    Write-Host "  Shell Launcher niet beschikbaar -- logon-taak wordt als fallback gebruikt." -ForegroundColor Yellow
    Write-Host "  De kiosk werkt normaal, maar Pro/Enterprise geeft betere isolatie." -ForegroundColor Yellow
    Write-Host ""
}

Write-Log "Besturingssysteem: $winVersion (build $winBuild, editie $winEdition)"

# ── LOGGING ───────────────────────────────────────────────────────────────────
$LogFile = "C:\KioskSetup\setup_$(Get-Date -f 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Force -Path "C:\KioskSetup" | Out-Null

# Sla de vaste Gist-URL op als aanwijzer voor bootstrap
if ($REDIRECT_GIST_URL -notlike "*GIST_ID_HIER*") {
    $REDIRECT_GIST_URL | Out-File "C:\KioskSetup\pointer.txt" -Encoding UTF8
    Write-Log "Redirect-pointer opgeslagen: $REDIRECT_GIST_URL"
} else {
    Write-Log "Let op: REDIRECT_GIST_URL nog niet ingesteld in setup.ps1 — redirect-check uitgeschakeld" "WARN"
}

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$(Get-Date -f 'HH:mm:ss')] [$Level] $Msg"
    Write-Host $line -ForegroundColor $(if ($Level -eq "ERROR") {"Red"} elseif ($Level -eq "WARN") {"Yellow"} else {"Cyan"})
    Add-Content -Path $LogFile -Value $line
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    Write-Log "▶ $Name"
    try { & $Action; Write-Log "✔ $Name" }
    catch { Write-Log "✘ $Name — $_" "ERROR" }
}

# ── MODE BEPALEN ──────────────────────────────────────────────────────────────
$isUpdateOnly = $env:KIOSK_UPDATE_ONLY -eq "1"
$isFirstRun   = -not (Test-Path "C:\KioskSetup\company.txt")

# ── ALLE MODULES LADEN ────────────────────────────────────────────────────────
Write-Log "Modules laden van GitHub..."
$allModules = @("huisstijl","accounts","wifi","browser","branding","remote","kiosk-shell","splash","registry","wizard","admin-trigger","dalux","updates","power")
foreach ($module in $allModules) {
    try {
        $src  = Invoke-RestMethod -Uri "$BASE_URL/modules/$module.ps1" -ErrorAction Stop
        $path = "C:\KioskSetup\$module.ps1"
        $src | Out-File -FilePath $path -Encoding UTF8
        . $path
        Write-Log "  ✔ $module"
    } catch {
        Write-Log "  ✘ $module (niet gevonden — overgeslagen)" "WARN"
    }
}

# ── BEDRIJFSKEUZE: WIZARD OF ENV-VAR ─────────────────────────────────────────
$company = $env:KIOSK_COMPANY

if (-not $company -and $isUpdateOnly) {
    # Bootstrap: lees opgeslagen bedrijfscode
    $company = ([string](Get-Content "C:\KioskSetup\company.txt" -ErrorAction SilentlyContinue)).Trim()
}

if (-not $company) {
    # Eerste keer of handmatige run: toon volledige wizard
    Write-Log "Geen bedrijf ingesteld — wizard starten"
    $company = Invoke-SetupWizard -GithubOrg $GITHUB_ORG -GithubRepo $GITHUB_REPO -BaseUrl $BASE_URL
    $company | Out-File "C:\KioskSetup\company.txt" -Encoding UTF8
}

$company = $company.ToLower().Trim()
Write-Log "Bedrijf: $company"

# ── CONFIG LADEN VAN GITHUB ───────────────────────────────────────────────────
try {
    $cfg = Invoke-RestMethod -Uri "$BASE_URL/config/$company.json" -ErrorAction Stop
    Write-Log "Config geladen: $($cfg.displayName)"
} catch {
    Write-Log "Config niet gevonden voor '$company'" "ERROR"
    exit 1
}

$appMode        = if ($cfg.appMode) { $cfg.appMode } else { "browser" }
$currentVersion = if (Test-Path "C:\KioskSetup\version.txt") {
    (Get-Content "C:\KioskSetup\version.txt").Trim()
} else { "?" }

Write-Log "═══ $(if ($isUpdateOnly) {'UPDATE'} else {'INITIËLE SETUP'}): $($cfg.displayName) [app: $appMode] [v$currentVersion] ═══"

# ── STAPPEN DIE ALTIJD DRAAIEN ────────────────────────────────────────────────
Invoke-Step "TBI branding toepassen"        { Set-KioskBranding  -Config $cfg -BaseUrl $BASE_URL }
Invoke-Step "WiFi-profielen synchroniseren" { Sync-WifiProfiles  -Config $cfg -BaseUrl $BASE_URL }
Invoke-Step "Kiosk shell-modus instellen"   { Set-KioskShell     -Config $cfg }
Invoke-Step "Slaapstand-schema instellen"   { Set-PowerSchedule  -Config $cfg }
Invoke-Step "Automatische updates instellen" { Set-AutoUpdate     -Config $cfg }

switch ($appMode) {
    "dalux"   { Invoke-Step "Dalux installeren/updaten" { Install-DaluxApp -Config $cfg } }
    "browser" { Invoke-Step "Edge-kiosk configureren"   { Set-EdgeKiosk    -Config $cfg } }
}

$updateMsg = if ($isUpdateOnly) { "Bijgewerkt: $(Get-Date -f 'dd-MM-yyyy HH:mm')" } else { "Initiële installatie" }
Invoke-Step "Opstartscherm bijwerken" {
    Register-SplashTask -Config $cfg -Version $currentVersion -UpdateStatus $updateMsg
}

Invoke-Step "Device registreren in GitHub" {
    Register-Device -Config $cfg -GithubOrg $GITHUB_ORG -GithubRepo $GITHUB_REPO -Version $currentVersion
}

# ── STAPPEN ALLEEN BIJ INITIËLE SETUP ────────────────────────────────────────
if (-not $isUpdateOnly) {
    Invoke-Step "Kiosk-account aanmaken"   { Set-KioskAccount    -Config $cfg }
    Invoke-Step "Overtollige accounts opruimen" { Remove-StaleAccounts -Config $cfg }
    Invoke-Step "Remote access inrichten"  { Set-RemoteAccess -Config $cfg }
    Invoke-Step "Admin-trigger instellen"  {
        Register-AdminTrigger -Config $cfg -GithubOrg $GITHUB_ORG `
                              -GithubRepo $GITHUB_REPO -BaseUrl $BASE_URL
    }
    # Bewaar metadata voor bootstrap en admin-menu
    $company    | Out-File "C:\KioskSetup\company.txt" -Encoding UTF8
    $GITHUB_ORG | Out-File "C:\KioskSetup\org.txt"     -Encoding UTF8
    $GITHUB_REPO| Out-File "C:\KioskSetup\repo.txt"    -Encoding UTF8
    $BASE_URL   | Out-File "C:\KioskSetup\baseurl.txt" -Encoding UTF8

    Invoke-Step "Boot-update taak aanmaken" {
        Register-UpdateTask -BaseUrl      $BASE_URL `
                            -Company      $company `
                            -GithubOrg    $GITHUB_ORG `
                            -GithubRepo   $GITHUB_REPO `
                            -GithubBranch $GITHUB_BRANCH
    }
}

Write-Log "═══ VOLTOOID$(if (-not $isUpdateOnly) {' — herstart vereist'}) ═══"
Write-Log "Log: $LogFile"

if (-not $isUpdateOnly) {
    $restart = Read-Host "`nNu herstarten? (j/n)"
    if ($restart -eq "j") { Restart-Computer -Force }
}
