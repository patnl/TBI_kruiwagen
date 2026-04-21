# modules/remote.ps1 — Remote toegang (RDP + ZeroTier of TeamViewer)

function Set-RemoteAccess {
    param([object]$Config)

    $remote = $Config.remoteAccess

    # ── 1. RDP INSCHAKELEN (altijd) ──────────────────────────────────────────
    # Vereis NLA (Network Level Authentication) voor veiligheid
    $tsPath = "HKLM:\System\CurrentControlSet\Control\Terminal Server"
    Set-ItemProperty -Path $tsPath -Name "fDenyTSConnections"   -Value 0
    Set-ItemProperty -Path $tsPath -Name "UserAuthentication"   -Value 1   # NLA aan

    # Firewall-regel toestaan
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "RDP Kiosk" `
                        -Direction Inbound `
                        -Protocol TCP `
                        -LocalPort 3389 `
                        -Action Allow `
                        -ErrorAction SilentlyContinue

    # Voeg kiosk-account toe aan Remote Desktop Users
    Add-LocalGroupMember -Group "Remote Desktop Users" `
                         -Member $Config.kioskUser.username `
                         -ErrorAction SilentlyContinue

    # RDP-beheerder (apart beheerdersaccount voor remote)
    if ($remote.adminUser) {
        $adminPw = ConvertTo-SecureString $remote.adminPassword -AsPlainText -Force
        if (-not (Get-LocalUser -Name $remote.adminUser -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $remote.adminUser `
                          -Password $adminPw `
                          -FullName "TBI Remote Admin" `
                          -PasswordNeverExpires | Out-Null
            Add-LocalGroupMember -Group "Administrators"       -Member $remote.adminUser
            Add-LocalGroupMember -Group "Remote Desktop Users" -Member $remote.adminUser
            Write-Log "Remote-beheerdersaccount aangemaakt: $($remote.adminUser)"
        }
    }
    Write-Log "RDP ingeschakeld (poort 3389, NLA vereist)"

    # ── 2. ZEROTIER (aanbevolen — geen open poorten nodig) ───────────────────
    if ($remote.zerotier -and $remote.zerotier.enabled) {
        Write-Log "ZeroTier installeren..."
        $ztInstaller = "C:\KioskSetup\zerotier.msi"
        Invoke-WebRequest -Uri "https://download.zerotier.com/dist/ZeroTier%20One.msi" `
                          -OutFile $ztInstaller -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i `"$ztInstaller`" /quiet /norestart" -Wait

        # Netwerk joinen
        Start-Sleep -Seconds 5
        $ztCli = "C:\Program Files (x86)\ZeroTier\One\zerotier-one_x64.exe"
        if (Test-Path $ztCli) {
            & $ztCli -q join $remote.zerotier.networkId
            Write-Log "ZeroTier joined netwerk: $($remote.zerotier.networkId)"
            Write-Log "⚠ Vergeet niet het apparaat te autoriseren in ZeroTier Central"
        }
    }

    # ── 3. TEAMVIEWER (alternatief voor ZeroTier) ────────────────────────────
    if ($remote.teamviewer -and $remote.teamviewer.enabled) {
        Write-Log "TeamViewer Host installeren..."
        $tvInstaller = "C:\KioskSetup\tvhost.exe"
        # TeamViewer Host (unattended install)
        $tvUrl = "https://download.teamviewer.com/download/TeamViewerHost.exe"
        Invoke-WebRequest -Uri $tvUrl -OutFile $tvInstaller -UseBasicParsing
        $tvArgs = "/S /AUTO /ASSIGNMENTID=$($remote.teamviewer.assignmentId)"
        Start-Process $tvInstaller -ArgumentList $tvArgs -Wait
        Write-Log "TeamViewer Host geïnstalleerd en gekoppeld aan account"
    }

    # ── 4. WAKE-ON-LAN INSCHAKELEN ───────────────────────────────────────────
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    foreach ($adapter in $adapters) {
        $pnp = $adapter | Get-PnpDevice
        try {
            Enable-NetAdapterPowerManagement -Name $adapter.Name -WakeOnMagicPacket -ErrorAction SilentlyContinue
        } catch {}
    }
    Write-Log "Wake-on-LAN ingeschakeld"
}
