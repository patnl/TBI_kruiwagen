# modules/accounts.ps1 — Kiosk-account beheer

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
    powercfg /change monitor-timeout-ac ($Config.kioskUser.screenTimeoutMinutes ?? 30)

    Write-Log "Auto-logon geconfigureerd voor: $username"
}
