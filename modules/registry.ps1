# modules/registry.ps1
# Houdt een live device-register bij in GitHub: registry/devices.json
# Schrijft via GitHub Contents API (vereist PAT met repo-schrijfrechten)

$REGISTRY_PATH = "registry/devices.json"
$PAT_FILE      = "C:\KioskSetup\.ghpat"   # Lokaal opgeslagen, NIET in repo

# ── PAT BEHEER ───────────────────────────────────────────────────────────────

function Get-GitHubPat {
    if (Test-Path $PAT_FILE) {
        $enc = Get-Content $PAT_FILE
        try {
            # DPAPI-decryptie (alleen leesbaar op zelfde machine + account)
            $bytes = [Convert]::FromBase64String($enc)
            return [Text.Encoding]::UTF8.GetString(
                [Security.Cryptography.ProtectedData]::Unprotect(
                    $bytes, $null,
                    [Security.Cryptography.DataProtectionScope]::LocalMachine))
        } catch { return $null }
    }
    return $null
}

function Save-GitHubPat {
    param([string]$Pat)
    Add-Type -AssemblyName System.Security
    $bytes = [Text.Encoding]::UTF8.GetBytes($Pat)
    $enc   = [Security.Cryptography.ProtectedData]::Protect(
                 $bytes, $null,
                 [Security.Cryptography.DataProtectionScope]::LocalMachine)
    [Convert]::ToBase64String($enc) | Out-File $PAT_FILE -Encoding ASCII
    Write-Log "GitHub PAT opgeslagen (DPAPI-versleuteld)"
}

# ── GITHUB API HELPERS ────────────────────────────────────────────────────────

function Get-GHHeaders {
    param([string]$Pat)
    return @{
        Authorization  = "token $Pat"
        "User-Agent"   = "TBI-Kiosk/1.0"
        Accept         = "application/vnd.github.v3+json"
    }
}

function Read-GHRegistry {
    param([string]$Org, [string]$Repo, [string]$Pat)
    $url = "https://api.github.com/repos/$Org/$Repo/contents/$REGISTRY_PATH"
    try {
        $resp    = Invoke-RestMethod -Uri $url -Headers (Get-GHHeaders $Pat) -ErrorAction Stop
        $content = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($resp.content -replace '\s',''))
        return @{ data = ($content | ConvertFrom-Json); sha = $resp.sha }
    } catch {
        if ($_ -match "404") {
            # Bestand bestaat nog niet — leeg register
            return @{ data = [pscustomobject]@{ lastUpdated = ""; devices = @() }; sha = $null }
        }
        throw
    }
}

function Write-GHRegistry {
    param([string]$Org, [string]$Repo, [string]$Pat, [object]$Data, [string]$Sha, [string]$Message)
    $url     = "https://api.github.com/repos/$Org/$Repo/contents/$REGISTRY_PATH"
    $json    = $Data | ConvertTo-Json -Depth 6
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    $body    = @{ message = $Message; content = $encoded }
    if ($Sha) { $body.sha = $Sha }
    $bodyJson = $body | ConvertTo-Json
    Invoke-RestMethod -Method Put -Uri $url -Headers (Get-GHHeaders $Pat) -Body $bodyJson -ContentType "application/json" | Out-Null
}

# ── DEVICE REGISTRATIE ────────────────────────────────────────────────────────

function Register-Device {
    param([object]$Config, [string]$GithubOrg, [string]$GithubRepo, [string]$Version)

    $pat = Get-GitHubPat
    if (-not $pat) {
        Write-Log "Geen GitHub PAT — device-registratie overgeslagen" "WARN"
        return
    }

    # ZeroTier IP ophalen als beschikbaar
    $ztIp = ""
    try {
        $ztInfo = Invoke-RestMethod "http://localhost:9993/status" -ErrorAction SilentlyContinue
        if ($ztInfo) { $ztIp = $(if ($ztInfo.address -ne $null) { $ztInfo.address } else { "" }) }
    } catch {}

    $entry = [pscustomobject]@{
        hostname    = $env:COMPUTERNAME
        company     = $(if ($Config.displayName) { $Config.displayName } else { "Onbekend" })
        companyCode = ($Config.computerNamePrefix -replace "-KIOSK","").ToLower()
        appMode     = $(if ($Config.appMode) { $Config.appMode } else { "browser" })
        version     = $Version
        lastSeen    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        lastUpdate  = if ($env:KIOSK_UPDATE_ONLY -eq "1") { (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") } else { "Initiële setup" }
        ipZerotier  = $ztIp
        status      = "online"
    }

    # Retry-lus voor race conditions (twee pc's tegelijk)
    $maxRetries = 3
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $reg = Read-GHRegistry -Org $GithubOrg -Repo $GithubRepo -Pat $pat

            # Bestaand device bijwerken of nieuw toevoegen
            $devices = [System.Collections.Generic.List[object]]$(if ($reg.data.devices -ne $null) { $reg.data.devices } else { @() })
            $existing = $devices | Where-Object { $_.hostname -eq $env:COMPUTERNAME }
            if ($existing) {
                $existing.version   = $entry.version
                $existing.lastSeen  = $entry.lastSeen
                $existing.lastUpdate = $entry.lastUpdate
                $existing.status    = "online"
                $existing.ipZerotier = $ztIp
            } else {
                $devices.Add($entry)
            }

            $reg.data.lastUpdated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            $reg.data.devices     = $devices

            Write-GHRegistry -Org $GithubOrg -Repo $GithubRepo -Pat $pat `
                             -Data $reg.data -Sha $reg.sha `
                             -Message "Device update: $env:COMPUTERNAME [$($entry.version)]"

            Write-Log "Device geregistreerd in GitHub: $env:COMPUTERNAME (versie $Version)"
            return

        } catch {
            if ($attempt -lt $maxRetries -and $_ -match "409") {
                Write-Log "Registry conflict (poging $attempt) — opnieuw proberen..." "WARN"
                Start-Sleep -Seconds (2 * $attempt)
            } else {
                Write-Log "Device registratie mislukt: $_" "WARN"
                return
            }
        }
    }
}

function Set-DeviceOffline {
    param([string]$GithubOrg, [string]$GithubRepo, [string]$Hostname = $env:COMPUTERNAME)
    $pat = Get-GitHubPat
    if (-not $pat) { return }
    try {
        $reg     = Read-GHRegistry -Org $GithubOrg -Repo $GithubRepo -Pat $pat
        $device  = $reg.data.devices | Where-Object { $_.hostname -eq $Hostname }
        if ($device) {
            $device.status   = "offline"
            $device.lastSeen = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            $reg.data.lastUpdated = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            Write-GHRegistry -Org $GithubOrg -Repo $GithubRepo -Pat $pat `
                             -Data $reg.data -Sha $reg.sha `
                             -Message "Device offline: $Hostname"
        }
    } catch { Write-Log "Offline markering mislukt: $_" "WARN" }
}
