# modules/accounts.ps1 — Kiosk-account beheer

function Remove-StaleAccounts {
    param([object]$Config)

    # Accounts die ALTIJD bewaard worden
    $keepAccounts = @(
        $Config.kioskUser.username,                  # kiosk-gebruiker
        $Config.remoteAccess.adminUser,              # remote-beheerder
        $env:USERNAME,                               # huidig ingelogde beheerder (die setup draait)
        "Administrator", "Gast", "Guest",            # ingebouwde accounts
        "DefaultAccount", "WDAGUtilityAccount"       # Windows-systeemaccounts
    ) | Where-Object { $_ } | ForEach-Object { $_.ToLower() }

    $allUsers = Get-LocalUser -ErrorAction SilentlyContinue
    $removed  = 0

    foreach ($user in $allUsers) {
        if ($keepAccounts -contains $user.Name.ToLower()) { continue }

        # Verwijder profiel van schijf als dat bestaat
        $profilePath = "C:\Users\$($user.Name)"
        if (Test-Path $profilePath) {
            try {
                # Gebruik CIM om het geregistreerde profiel te verwijderen (inclusief registry-sleutel)
                $profile = Get-CimInstance Win32_UserProfile -Filter "LocalPath='$($profilePath -replace '\\','\\\\')'" -ErrorAction SilentlyContinue
                if ($profile) { Remove-CimInstance $profile -ErrorAction SilentlyContinue }
                Remove-Item $profilePath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Profiel verwijderd: $profilePath"
            } catch {
                Write-Log "Profiel $profilePath kon niet worden verwijderd: $_" "WARN"
            }
        }

        # Verwijder het account
        try {
            Remove-LocalUser -Name $user.Name -ErrorAction Stop
            Write-Log "Account verwijderd: $($user.Name)"
            $removed++
        } catch {
            Write-Log "Account $($user.Name) kon niet worden verwijderd: $_" "WARN"
        }
    }

    if ($removed -eq 0) {
        Write-Log "Geen overtollige accounts gevonden"
    } else {
        Write-Log "$removed overtollige account(s) verwijderd"
    }
}

function Set-KioskAccount {
    param([object]$Config)

    $username = $Config.kioskUser.username
    $password = ConvertTo-SecureString $Config.kioskUser.password -AsPlainText -Force

    # Verwijder bestaand account indien aanwezig (herinstall-scenario)
    if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
        Write-Log "Account '$username' bestaat al — wordt bijgewerkt"
        Set-LocalUser -Name $username -Password $password -PasswordNeverExpires $true
    } else {
        New-LocalUser -Name $username `
                      -Password $password `
                      -FullName $Config.kioskUser.fullName `
                      -Description "TBI Kiosk Account — beheerd via GitHub" `
                      -PasswordNeverExpires `
                      -UserMayNotChangePassword | Out-Null
        Write-Log "Account aangemaakt: $username"
    }

    # Zorg dat account in juiste groep zit (Users, NIET Administrators)
    Add-LocalGroupMember -Group "Users" -Member $username -ErrorAction SilentlyContinue

    # Auto-logon instellen voor kiosk-account
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $regPath -Name "AutoAdminLogon"  -Value "1"
    Set-ItemProperty -Path $regPath -Name "DefaultUserName" -Value $username
    Set-ItemProperty -Path $regPath -Name "DefaultPassword" -Value $Config.kioskUser.password
    Set-ItemProperty -Path $regPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME

    # Schakel slaapstand en schermvergrendeling uit op kiosk-account
    powercfg /change standby-timeout-ac 0
    powercfg /change monitor-timeout-ac $(if ($Config.kioskUser.screenTimeoutMinutes -ne $null) { $Config.kioskUser.screenTimeoutMinutes } else { 30 })

    Write-Log "Auto-logon geconfigureerd voor: $username"
}
