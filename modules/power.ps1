# modules/power.ps1
# Slaapstand-schema: alleen actief tussen geconfigureerde tijden
# Standaard 22:00-06:00, per bedrijf instelbaar via powerSchedule in config

function Set-PowerSchedule {
    param([object]$Config)

    $schedule = $Config.powerSchedule

    # Fallback als powerSchedule ontbreekt in config
    if (-not $schedule) {
        $schedule = [pscustomobject]@{
            sleepEnabled = $true
            sleepStart   = "22:00"
            sleepEnd     = "06:00"
        }
    }

    if (-not $schedule.sleepEnabled) {
        # Slaapstand volledig uitschakelen
        powercfg /change standby-timeout-ac 0
        powercfg /change hibernate-timeout-ac 0
        Write-Log "Slaapstand uitgeschakeld (sleepEnabled=false)"
        # Verwijder eventuele oude taken
        Unregister-ScheduledTask -TaskName "TBI-SlaapstandAan"  -Confirm:$false -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "TBI-SlaapstandUit"  -Confirm:$false -ErrorAction SilentlyContinue
        return
    }

    $startTime = $schedule.sleepStart  # bijv. "22:00"
    $endTime   = $schedule.sleepEnd    # bijv. "06:00"

    # Verwerk tijden naar uur/minuut voor trigger
    $startH, $startM = $startTime -split ":" | ForEach-Object { [int]$_ }
    $endH,   $endM   = $endTime   -split ":" | ForEach-Object { [int]$_ }

    # ── SLAAPSTAND INSCHAKELEN NA sleepStart ─────────────────────────────────
    # Geplande taak: zet slaapstand-timeout op 5 minuten (pc slaapt snel)
    $scriptAan = @"
powercfg /change standby-timeout-ac 5
powercfg /change hibernate-timeout-ac 0
"@
    $scriptAan | Out-File "C:\KioskSetup\power-sleep-on.ps1" -Encoding UTF8

    $actionAan  = New-ScheduledTaskAction -Execute "powershell.exe" `
                      -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\KioskSetup\power-sleep-on.ps1`""
    $triggerAan = New-ScheduledTaskTrigger -Daily -At "$($startH):$($startM.ToString('D2'))"
    $principal  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

    Register-ScheduledTask -TaskName "TBI-SlaapstandAan" `
                           -Action $actionAan -Trigger $triggerAan -Principal $principal `
                           -Description "TBI Kiosk: slaapstand inschakelen ($startTime)" `
                           -Force | Out-Null

    # ── SLAAPSTAND UITSCHAKELEN NA sleepEnd ──────────────────────────────────
    # Geplande taak: zet slaapstand-timeout terug op de config-waarde (of 0)
    $screenTimeout = if ($Config.kioskUser.screenTimeoutMinutes -ne $null) {
        [int]$Config.kioskUser.screenTimeoutMinutes
    } else { 30 }

    $scriptUit = @"
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
"@
    $scriptUit | Out-File "C:\KioskSetup\power-sleep-off.ps1" -Encoding UTF8

    $actionUit  = New-ScheduledTaskAction -Execute "powershell.exe" `
                      -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\KioskSetup\power-sleep-off.ps1`""
    $triggerUit = New-ScheduledTaskTrigger -Daily -At "$($endH):$($endM.ToString('D2'))"

    Register-ScheduledTask -TaskName "TBI-SlaapstandUit" `
                           -Action $actionUit -Trigger $triggerUit -Principal $principal `
                           -Description "TBI Kiosk: slaapstand uitschakelen ($endTime)" `
                           -Force | Out-Null

    # ── HUIDIGE TIJD BEPALEN: IN OF BUITEN SLAAPVENSTER? ─────────────────────
    # Direct de juiste stand instellen op basis van huidige tijd
    $now     = [datetime]::Now
    $nowMins = $now.Hour * 60 + $now.Minute
    $sleepMins = $startH * 60 + $startM
    $wakeMins  = $endH   * 60 + $endM

    # Slaapvenster kan over middernacht lopen (bijv. 22:00-06:00)
    $inSleepWindow = if ($sleepMins -gt $wakeMins) {
        # Over middernacht: slaap als NOW >= 22:00 OF NOW < 06:00
        ($nowMins -ge $sleepMins) -or ($nowMins -lt $wakeMins)
    } else {
        # Zelfde dag: slaap als NOW tussen start en eind
        ($nowMins -ge $sleepMins) -and ($nowMins -lt $wakeMins)
    }

    if ($inSleepWindow) {
        powercfg /change standby-timeout-ac 5
        powercfg /change hibernate-timeout-ac 0
        Write-Log "Slaapstand NU actief (binnen venster $startTime-$endTime)"
    } else {
        powercfg /change standby-timeout-ac 0
        powercfg /change hibernate-timeout-ac 0
        Write-Log "Slaapstand NU inactief (buiten venster $startTime-$endTime)"
    }

    Write-Log "Slaapstand-schema ingesteld: aan om $startTime, uit om $endTime"
    Write-Log "Taken aangemaakt: TBI-SlaapstandAan / TBI-SlaapstandUit"
}
