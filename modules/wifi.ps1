# modules/wifi.ps1 — WiFi met lokale secrets (nooit wachtwoorden in GitHub)
# Wachtwoorden staan in C:\KioskSetup\.wifi-secrets.json (DPAPI-versleuteld)
# De repo bevat alleen SSIDs

$script:WIFI_SECRETS_FILE = "C:\KioskSetup\.wifi-secrets.json"

# ── SECRETS BEHEER (lokaal, versleuteld, nooit in Git) ────────────────────────

function Get-WifiSecret {
    param([string]$Ssid)
    if (-not (Test-Path $script:WIFI_SECRETS_FILE)) { return $null }

    try {
        Add-Type -AssemblyName System.Security
        $enc   = Get-Content $script:WIFI_SECRETS_FILE -Raw
        $bytes = [Convert]::FromBase64String($enc)
        $json  = [Text.Encoding]::UTF8.GetString(
            [Security.Cryptography.ProtectedData]::Unprotect(
                $bytes, $null,
                [Security.Cryptography.DataProtectionScope]::LocalMachine))
        $secrets = $json | ConvertFrom-Json
        return $secrets.$Ssid
    } catch {
        Write-Log "Kon wifi-secrets niet uitlezen: $_" "WARN"
        return $null
    }
}

function Save-WifiSecret {
    param([string]$Ssid, [string]$Password)

    Add-Type -AssemblyName System.Security
    $current = @{}

    # Lees bestaande secrets indien aanwezig
    if (Test-Path $script:WIFI_SECRETS_FILE) {
        try {
            $enc   = Get-Content $script:WIFI_SECRETS_FILE -Raw
            $bytes = [Convert]::FromBase64String($enc)
            $json  = [Text.Encoding]::UTF8.GetString(
                [Security.Cryptography.ProtectedData]::Unprotect(
                    $bytes, $null,
                    [Security.Cryptography.DataProtectionScope]::LocalMachine))
            $obj = $json | ConvertFrom-Json
            foreach ($prop in $obj.PSObject.Properties) {
                $current[$prop.Name] = $prop.Value
            }
        } catch { Write-Log "Kon bestaande secrets niet lezen — nieuwe file" "WARN" }
    }

    $current[$Ssid] = $Password

    $newJson  = $current | ConvertTo-Json -Compress
    $plain    = [Text.Encoding]::UTF8.GetBytes($newJson)
    $enc      = [Security.Cryptography.ProtectedData]::Protect(
                    $plain, $null,
                    [Security.Cryptography.DataProtectionScope]::LocalMachine)
    [Convert]::ToBase64String($enc) | Out-File $script:WIFI_SECRETS_FILE -Encoding ASCII

    Write-Log "WiFi-wachtwoord opgeslagen voor SSID: $Ssid"
}

function Prompt-WifiSecrets {
    param([object]$Config)
    # Interactieve prompt bij eerste setup voor ontbrekende wachtwoorden
    if (-not $Config.wifi) { return }

    foreach ($profile in $Config.wifi) {
        if ($profile.profileXmlPath) { continue }  # XML heeft al wachtwoord
        if ($profile.enterprise)     { continue }  # Enterprise = geen passphrase

        $existing = Get-WifiSecret -Ssid $profile.ssid
        if ($existing) {
            Write-Host "  ✔ WiFi-wachtwoord bekend: $($profile.ssid)" -ForegroundColor Green
            continue
        }

        Write-Host ""
        Write-Host "  WiFi-wachtwoord nodig voor SSID: $($profile.ssid)" -ForegroundColor Yellow
        $secureInput = Read-Host "  Wachtwoord (wordt lokaal versleuteld opgeslagen)" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

        if ($plain) { Save-WifiSecret -Ssid $profile.ssid -Password $plain }
    }
}

# ── WIFI PROFIEL SYNCHRONISATIE (bij elke boot) ───────────────────────────────

function Sync-WifiProfiles {
    param([object]$Config, [string]$BaseUrl)

    if (-not $Config.wifi -or $Config.wifi.Count -eq 0) {
        Write-Log "Geen WiFi-profielen geconfigureerd"
        return
    }

    foreach ($profile in $Config.wifi) {
        Write-Log "WiFi sync: $($profile.ssid)"
        $xmlPath = "C:\KioskSetup\wifi_$($profile.ssid -replace '[^a-zA-Z0-9]','_').xml"

        # ── BRON A: XML-profiel uit GitHub assets ────────────────────────────
        if ($profile.profileXmlPath) {
            try {
                Invoke-WebRequest -Uri "$BaseUrl/$($profile.profileXmlPath)" `
                                  -OutFile $xmlPath -UseBasicParsing -ErrorAction Stop
                Push-WifiXml -XmlPath $xmlPath -Ssid $profile.ssid -KeepFile $true
            } catch {
                Write-Log "WiFi XML niet bereikbaar voor '$($profile.ssid)': $_" "WARN"
            }

        # ── BRON B: Lokaal secret (voorkeur — nooit in Git) ──────────────────
        } else {
            $password = Get-WifiSecret -Ssid $profile.ssid
            if (-not $password) {
                Write-Log "Geen wachtwoord gevonden voor '$($profile.ssid)' in lokale secrets" "WARN"
                Write-Log "  → Tip: voer 'Prompt-WifiSecrets -Config \$cfg' uit om in te stellen" "WARN"
                continue
            }

            $xml = Build-WifiXml -Ssid $profile.ssid `
                                 -Password $password `
                                 -Security $(if ($profile.security) { $profile.security } else { "WPA2PSK" }) `
                                 -Hidden   $(if ($profile.hidden -ne $null) { $profile.hidden } else { $false })
            $xml | Out-File -FilePath $xmlPath -Encoding UTF8
            Push-WifiXml -XmlPath $xmlPath -Ssid $profile.ssid -KeepFile $false
        }

        if ($profile.primary -eq $true) {
            netsh wlan connect name="$($profile.ssid)" | Out-Null
            Write-Log "Verbinding gestart met primair netwerk: $($profile.ssid)"
        }
    }
}

function Push-WifiXml {
    param([string]$XmlPath, [string]$Ssid, [bool]$KeepFile = $false)
    netsh wlan delete profile name="$Ssid" | Out-Null
    $result = netsh wlan add profile filename="$XmlPath" user=all
    if ($LASTEXITCODE -eq 0 -or $result -match "added") {
        Write-Log "WiFi profiel gepushed: $Ssid"
    } else {
        Write-Log "WiFi profiel mislukt voor $Ssid — $result" "WARN"
    }
    if (-not $KeepFile) { Remove-Item $XmlPath -ErrorAction SilentlyContinue }
}

function Build-WifiXml {
    param([string]$Ssid, [string]$Password, [string]$Security = "WPA2PSK", [bool]$Hidden = $false)
    $ssidHex = ($Ssid.ToCharArray() | ForEach-Object { '{0:X2}' -f [int]$_ }) -join ''
    return @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <n>$Ssid</n>
    <SSIDConfig>
        <SSID><hex>$ssidHex</hex><n>$Ssid</n></SSID>
        <nonBroadcast>$(if ($Hidden) {'true'} else {'false'})</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>$Security</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$Password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
}

# Backwards-compat alias
function Install-WifiProfile {
    param([object]$Config, [string]$BaseUrl)
    Sync-WifiProfiles -Config $Config -BaseUrl $BaseUrl
}
