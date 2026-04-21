# modules/wizard.ps1
# Interactieve setup-wizard: laadt beschikbare configs van GitHub,
# vraagt bedrijf + variant, PIN voor admin-toegang en GitHub PAT

function Invoke-SetupWizard {
    param([string]$GithubOrg, [string]$GithubRepo, [string]$BaseUrl)

    Clear-Host
    Write-Host ""
    Write-Host "  ████████╗██████╗ ██╗    ██╗" -ForegroundColor Magenta
    Write-Host "     ██╔══╝██╔══██╗██║    ██║" -ForegroundColor Magenta
    Write-Host "     ██║   ██████╔╝██║    ██║" -ForegroundColor Magenta
    Write-Host "     ██║   ██╔══██╗██║    ██║" -ForegroundColor Magenta
    Write-Host "     ██║   ██████╔╝╚██████╔╝" -ForegroundColor Magenta
    Write-Host "     ╚═╝   ╚═════╝  ╚═════╝  KIOSK SETUP" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor Gray
    Write-Host "  Datum:    $(Get-Date -f 'dd-MM-yyyy HH:mm')" -ForegroundColor Gray
    Write-Host ""

    # ── STAP 1: BESCHIKBARE CONFIGS OPHALEN VAN GITHUB ───────────────────────
    Write-Host "  Beschikbare bedrijfsconfiguraties ophalen..." -ForegroundColor Cyan
    $apiUrl  = "https://api.github.com/repos/$GithubOrg/$GithubRepo/contents/config"
    $headers = @{ "User-Agent" = "TBI-Kiosk/1.0" }

    # Probeer met PAT (voor private repos)
    $pat = Get-GitHubPat -ErrorAction SilentlyContinue
    if ($pat) { $headers.Authorization = "token $pat" }

    try {
        $configFiles = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop
        $jsonFiles   = $configFiles | Where-Object { $_.name -match '\.json$' } |
                       Select-Object -ExpandProperty name |
                       Sort-Object
    } catch {
        Write-Host "  ⚠ Kan config-lijst niet ophalen — handmatig invoeren" -ForegroundColor Yellow
        $jsonFiles = @()
    }

    # ── STAP 2: BEDRIJF KIEZEN ────────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ┌─ STAP 1 VAN 4: BEDRIJF KIEZEN ──────────────────────────┐" -ForegroundColor White

    if ($jsonFiles.Count -gt 0) {
        # Groepeer op basisnaam (voor varianten: hazenberg.json, hazenberg-site2.json)
        $baseNames = $jsonFiles | ForEach-Object { ($_ -replace '(-\w+)?\.json$','') } | Sort-Object -Unique

        Write-Host ""
        $i = 1
        $menuMap = @{}
        foreach ($name in $baseNames) {
            $label = $name.ToUpper()
            Write-Host "    [$i] $label" -ForegroundColor White
            $menuMap["$i"] = $name
            $i++
        }
        Write-Host ""
        $choice = Read-Host "  Kies een nummer"
        $baseCompany = $menuMap[$choice.Trim()]

        if (-not $baseCompany) {
            Write-Host "  Ongeldige keuze — voer naam handmatig in:" -ForegroundColor Yellow
            $baseCompany = (Read-Host "  Bedrijfscode").ToLower().Trim()
        }
    } else {
        $baseCompany = (Read-Host "  Bedrijfscode invoeren (bijv. hazenberg)").ToLower().Trim()
    }

    # ── STAP 3: VARIANT KIEZEN (als meerdere configs voor bedrijf) ────────────
    $variants = $jsonFiles | Where-Object { $_ -match "^$baseCompany" }

    $selectedConfig = $baseCompany
    if ($variants.Count -gt 1) {
        Write-Host ""
        Write-Host "  ┌─ STAP 2 VAN 4: CONFIGURATIEVARIANT ─────────────────────┐" -ForegroundColor White
        Write-Host ""
        Write-Host "  Meerdere configuraties gevonden voor '$baseCompany':" -ForegroundColor Cyan
        Write-Host ""
        $vi = 1
        $variantMap = @{}
        foreach ($v in $variants) {
            $vName = $v -replace '\.json$',''
            # Laad displayName uit elke variant
            try {
                $vCfg  = Invoke-RestMethod "$BaseUrl/config/$v" -ErrorAction SilentlyContinue
                $label = if ($vCfg.displayName) { "$($vCfg.displayName) — $($vCfg.appMode ?? 'browser')" } else { $vName }
            } catch { $label = $vName }
            Write-Host "    [$vi] $label" -ForegroundColor White
            $variantMap["$vi"] = $vName
            $vi++
        }
        Write-Host ""
        $vChoice = Read-Host "  Kies een nummer"
        $selectedConfig = $variantMap[$vChoice.Trim()] ?? $baseCompany
    } elseif ($variants.Count -eq 0) {
        $selectedConfig = $baseCompany
    }

    Write-Host ""
    Write-Host "  ✔ Geselecteerd: $selectedConfig" -ForegroundColor Green

    # ── STAP 4: ADMIN PIN INSTELLEN ───────────────────────────────────────────
    Write-Host ""
    Write-Host "  ┌─ STAP 3 VAN 4: ADMIN PIN ────────────────────────────────┐" -ForegroundColor White
    Write-Host "  (PIN is nodig om setup te starten vanuit kiosk-modus)" -ForegroundColor Gray
    Write-Host ""

    $pinPath = "C:\KioskSetup\.adminpin"
    if (Test-Path $pinPath) {
        Write-Host "  Admin PIN is al ingesteld." -ForegroundColor Green
        $resetPin = Read-Host "  Opnieuw instellen? (j/n)"
        if ($resetPin -eq "j") { Remove-Item $pinPath }
    }

    if (-not (Test-Path $pinPath)) {
        do {
            $pin1 = Read-Host "  Nieuwe PIN (minimaal 6 cijfers)"
            $pin2 = Read-Host "  PIN herhalen"
            if ($pin1 -ne $pin2)      { Write-Host "  PINs komen niet overeen — opnieuw" -ForegroundColor Red }
            if ($pin1.Length -lt 6)   { Write-Host "  PIN te kort — minimaal 6 tekens"   -ForegroundColor Red; $pin1 = "" }
        } while ($pin1 -ne $pin2 -or $pin1.Length -lt 6)

        Add-Type -AssemblyName System.Security
        $hash = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($pin1))
        $hashStr = [BitConverter]::ToString($hash) -replace '-',''
        $hashStr | Out-File $pinPath -Encoding ASCII
        Write-Host "  ✔ Admin PIN opgeslagen" -ForegroundColor Green
    }

    # ── STAP 5: GITHUB PAT INSTELLEN ─────────────────────────────────────────
    Write-Host ""
    Write-Host "  ┌─ STAP 4 VAN 4: GITHUB PAT (device-register) ─────────────┐" -ForegroundColor White
    Write-Host "  Maak een PAT aan op github.com → Settings → Developer settings" -ForegroundColor Gray
    Write-Host "  Rechten nodig: repo → Contents (read + write)" -ForegroundColor Gray
    Write-Host ""

    $existingPat = Get-GitHubPat -ErrorAction SilentlyContinue
    if ($existingPat) {
        Write-Host "  GitHub PAT is al opgeslagen." -ForegroundColor Green
        $resetPat = Read-Host "  Nieuwe PAT instellen? (j/n)"
        if ($resetPat -ne "j") { $existingPat = $existingPat }
        else { $existingPat = $null }
    }

    if (-not $existingPat) {
        $patInput = Read-Host "  GitHub PAT plakken (of Enter om over te slaan)"
        if ($patInput.Trim()) {
            Save-GitHubPat -Pat $patInput.Trim()
        } else {
            Write-Host "  Overgeslagen — device-register niet beschikbaar" -ForegroundColor Yellow
        }
    }

    # ── STAP 6: WIFI WACHTWOORDEN ─────────────────────────────────────────────
    Write-Host ""
    Write-Host "  ┌─ WIFI WACHTWOORDEN (lokaal versleuteld, niet in Git) ───┐" -ForegroundColor White
    try {
        $cfgPreview = Invoke-RestMethod "$BaseUrl/config/$selectedConfig.json" -ErrorAction Stop
        Prompt-WifiSecrets -Config $cfgPreview
    } catch {
        Write-Host "  Config niet geladen — WiFi wachtwoord later in te stellen via admin-menu" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "  Wizard voltooid — setup wordt gestart voor: $selectedConfig" -ForegroundColor Green
    Write-Host "  ════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
    Start-Sleep -Seconds 2

    return $selectedConfig
}

# Verkorte variant voor herinrichting vanuit kiosk-modus (minder stappen)
function Invoke-KioskAdminWizard {
    param([string]$GithubOrg, [string]$GithubRepo, [string]$BaseUrl, [string]$CurrentCompany)

    Clear-Host
    Write-Host ""
    Write-Host "  TBI KIOSK — BEHEER" -ForegroundColor Magenta
    Write-Host "  Computer: $env:COMPUTERNAME  |  Huidig: $CurrentCompany" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [1] Update uitvoeren (haal laatste versie op)" -ForegroundColor White
    Write-Host "  [2] Ander bedrijf / andere variant instellen" -ForegroundColor White
    Write-Host "  [3] WiFi-profielen opnieuw pushen" -ForegroundColor White
    Write-Host "  [4] Systeem herstarten" -ForegroundColor White
    Write-Host "  [5] Afsluiten (terug naar kiosk)" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "  Keuze"

    switch ($choice.Trim()) {
        "1" { return "update" }
        "2" { return "reconfig" }
        "3" { return "wifi" }
        "4" { Restart-Computer -Force }
        "5" { return "exit" }
        default { return "exit" }
    }
}
