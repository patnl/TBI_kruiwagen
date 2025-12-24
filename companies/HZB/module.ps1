function Get-DaluxExePath {
  param([string[]]$ExeCandidates)

  # 1) Candidates uit config
  foreach ($c in $ExeCandidates) {
    if ($c -and (Test-Path $c)) { return $c }
  }

  # 2) Uninstall registry (DisplayIcon / InstallLocation)
  $roots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )

  foreach ($root in $roots) {
    try {
      $apps = Get-ItemProperty $root -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Dalux" }
      foreach ($app in $apps) {
        $cands = @()
        if ($app.InstallLocation) {
          $cands += Join-Path $app.InstallLocation "Dalux.exe"
          $cands += Join-Path $app.InstallLocation "Dalux\Dalux.exe"
        }
        if ($app.DisplayIcon) {
          $icon = ($app.DisplayIcon -split ",")[0].Trim('"')
          $cands += $icon
        }
        $hit = $cands | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if ($hit) { return $hit }
      }
    } catch {}
  }

  return $null
}

function Start-CompanyApp {
  param($Config, [scriptblock]$Log)

  # Verwacht: $Config.startup.app.exeCandidates
  $exe = Get-DaluxExePath -ExeCandidates $Config.startup.app.exeCandidates
  if ($exe) {
    & $Log "HZB module: Dalux starten: $exe"
    Start-Process -FilePath $exe
    return $true
  }

  & $Log "HZB module: Dalux niet gevonden."
  return $false
}
