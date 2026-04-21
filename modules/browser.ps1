# modules/browser.ps1 — Edge kiosk configuratie

function Set-EdgeKiosk {
    param([object]$Config)

    $urls    = $Config.browser.urls      # Array van URLs
    $primary = $urls[0]                   # Primaire kiosk-URL

    # ── EDGE POLICIES VIA REGISTRY ──────────────────────────────────────────
    $policyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    New-Item -Path $policyPath -Force | Out-Null

    # Startpagina's (alle URLs als tabbladgroep)
    Set-ItemProperty -Path $policyPath -Name "HomepageLocation"         -Value $primary
    Set-ItemProperty -Path $policyPath -Name "HomepageIsNewTabPage"     -Value 0
    Set-ItemProperty -Path $policyPath -Name "NewTabPageLocation"       -Value $primary
    Set-ItemProperty -Path $policyPath -Name "RestoreOnStartup"         -Value 4  # Open specifieke pagina's

    # Startpagina's als meerdere tabbladen
    $startupPath = "$policyPath\RestoreOnStartupURLs"
    New-Item -Path $startupPath -Force | Out-Null
    for ($i = 0; $i -lt $urls.Count; $i++) {
        Set-ItemProperty -Path $startupPath -Name ($i + 1).ToString() -Value $urls[$i]
    }

    # Kiosk-beperkingen
    Set-ItemProperty -Path $policyPath -Name "BrowserAddProfileEnabled"      -Value 0
    Set-ItemProperty -Path $policyPath -Name "BrowserGuestModeEnabled"       -Value 0
    Set-ItemProperty -Path $policyPath -Name "DownloadRestrictions"          -Value 3  # Geen downloads
    Set-ItemProperty -Path $policyPath -Name "PrintingEnabled"               -Value 0
    Set-ItemProperty -Path $policyPath -Name "DeveloperToolsAvailability"    -Value 2  # Uitgeschakeld
    Set-ItemProperty -Path $policyPath -Name "PasswordManagerEnabled"        -Value 0
    Set-ItemProperty -Path $policyPath -Name "AutofillAddressEnabled"        -Value 0
    Set-ItemProperty -Path $policyPath -Name "AutofillCreditCardEnabled"     -Value 0
    Set-ItemProperty -Path $policyPath -Name "SignInAllowed"                 -Value 0  # Geen MS-account
    Set-ItemProperty -Path $policyPath -Name "HideFirstRunExperience"        -Value 1
    Set-ItemProperty -Path $policyPath -Name "SyncDisabled"                  -Value 1

    # Volledig scherm bij opstarten (kiosk-modus)
    if ($Config.browser.fullscreen) {
        Set-ItemProperty -Path $policyPath -Name "FullscreenAllowed" -Value 1
    }

    # URL-blokkering (optioneel — alles buiten whitelist blokkeren)
    if ($Config.browser.urlWhitelist) {
        $blockPath = "$policyPath\URLBlocklist"
        New-Item -Path $blockPath -Force | Out-Null
        Set-ItemProperty -Path $blockPath -Name "1" -Value "*"

        $allowPath = "$policyPath\URLAllowlist"
        New-Item -Path $allowPath -Force | Out-Null
        for ($i = 0; $i -lt $Config.browser.urlWhitelist.Count; $i++) {
            Set-ItemProperty -Path $allowPath -Name ($i + 1).ToString() -Value $Config.browser.urlWhitelist[$i]
        }
        Write-Log "URL-whitelist ingesteld: $($Config.browser.urlWhitelist -join ', ')"
    }

    # ── SNELKOPPELING OP BUREAUBLAD (PUBLIC) ────────────────────────────────
    $desktopPath = "C:\Users\Public\Desktop"
    $shortcutPath = "$desktopPath\$($Config.displayName).lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($shortcutPath)
    $sc.TargetPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $sc.Arguments  = "--kiosk $primary --edge-kiosk-type=fullscreen --no-first-run"
    $sc.IconLocation = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $sc.Save()

    Write-Log "Edge geconfigureerd — $($urls.Count) URL(s): $($urls -join ' | ')"
}
