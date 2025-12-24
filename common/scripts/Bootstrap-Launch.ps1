<# Bootstrap-Launch.ps1 (GitHub managed) + status prints
   - Start altijd direct iets lokaals (hufterproof)
   - Download base.json + company.json (cache) en synct bestanden uit GitHub
   - Per company: HZB -> Dalux (via module), others -> Edge start.html
   - Heartbeat naar fleet_status.csv
#>

$ErrorActionPreference = "Stop"

# --- Fixed local paths
$BaseDir    = "C:\Kiosk"
$UpdateDir  = "C:\Kiosk\updates"
$LogDir     = "C:\TBI\KioskLogs"
$StatusFile = "C:\Kiosk\machine_status.json"
$TokenFile  = "C:\Kiosk\github_pat.enc"

$CacheBase   = "C:\Kiosk\base.json"
$CacheCompany= "C:\Kiosk\company.json"
$CacheModule = "C:\Kiosk\company_module.ps1"

function Ensure-Dir($p) { if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null } }

function Log($m) {
  Ensure-Dir $LogDir
  Add-Content (Join-Path $LogDir "launch.log") -Value ("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m) -Encoding UTF8
}

function Info($m) { Write-Host "• $m" -ForegroundColor Cyan;  Log $m }
function Ok($m)   { Write-Host "✔ $m" -ForegroundColor Green; Log $m }
function Warn($m) { Write-Host "⚠ $m" -ForegroundColor Yellow; Log $m }
function Fail($m) { Write-Host "✖ $m" -ForegroundColor Red;    Log $m }

function Write-FallbackStartHtml($path) {
@'
<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>TBI Kiosk</title>
<style>
body{margin:0;background:#0b0b12;color:#fff;font-family:Verdana,Arial,sans-serif;height:100vh;display:flex;align-items:center;justify-content:center}
.c{max-width:900px;width:100%;padding:40px;text-align:center}
.btn{background:#630d80;padding:18px;border-radius:12px;display:inline-block;margin:8px;cursor:pointer}
h1{color:#c1e62e}
</style></head><body><div class="c">
<h1>TBI Kiosk</h1><p>Offline fallback actief</p>
<div class="btn" onclick="location.reload()">Vernieuwen</div>
</div></body></html>
'@ | Set-Content -Path $path -Encoding UTF8
}

function Load-Status {
  try { return (Get-Content $StatusFile -Raw | ConvertFrom-Json) }
  catch { return [pscustomobject]@{ Company="UNKNOWN"; Version="0.0.0"; StartupCount=0; Repo="patnl/TBI_kruiwagen"; Branch="main"; PcLabel=$env:COMPUTERNAME } }
}
function Save-Status($s) { $s | ConvertTo-Json | Set-Content $StatusFile -Encoding UTF8 }

function Get-TokenPlain {
  if (-not (Test-Path $TokenFile)) { return $null }
  try {
    $b64  = (Get-Content $TokenFile -Raw).Trim()
    $enc  = [Convert]::FromBase64String($b64)
    $bytes= [Security.Cryptography.ProtectedData]::Unprotect($enc, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
    return [Text.Encoding]::UTF8.GetString($bytes)
  } catch {
    Warn "Token decrypt faalde."
    return $null
  }
}

function Invoke-GH {
  param([string]$Method,[string]$Uri,[hashtable]$Headers,[string]$BodyJson=$null)
  for ($i=0; $i -lt 3; $i++) {
    try {
      if ($BodyJson) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $BodyJson -ContentType "application/json" -TimeoutSec 15
      } else {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec 15
      }
    } catch {
      if ($i -eq 2) { throw }
      Start-Sleep -Seconds ([int][math]::Pow(2,$i))
    }
  }
}

function Get-GitHubFileTo {
  param([string]$Repo,[string]$Branch,[string]$Path,[string]$OutFile,[hashtable]$Headers)
  $uri  = "https://api.github.com/repos/$Repo/contents/$Path?ref=$Branch"
  $resp = Invoke-GH -Method "GET" -Uri $uri -Headers $Headers
  $bytes= [Convert]::FromBase64String($resp.content)
  [IO.File]::WriteAllBytes($OutFile, $bytes)
}

function To-Hashtable($obj) {
  if ($null -eq $obj) { return @{} }
  if ($obj -is [System.Collections.IDictionary]) { return $obj }

  $ht = @{}
  foreach ($p in $obj.PSObject.Properties) {
    $v = $p.Value

    if ($v -is [pscustomobject]) {
      $ht[$p.Name] = To-Hashtable $v

    } elseif ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {

      $arr = @()
      foreach ($item in $v) {
        if ($item -is [pscustomobject]) {
          $arr += To-Hashtable $item
        } else {
          $arr += $item
        }
      }
      $ht[$p.Name] = $arr

    } else {
      $ht[$p.Name] = $v
    }
  }
  return $ht
}


function Merge-Hashtable {
  param([hashtable]$Base,[hashtable]$Override)
  $out = @{}
  foreach ($k in $Base.Keys) { $out[$k] = $Base[$k] }
  foreach ($k in $Override.Keys) {
    if ($out[$k] -is [hashtable] -and $Override[$k] -is [hashtable]) {
      $out[$k] = Merge-Hashtable -Base $out[$k] -Override $Override[$k]
    } else {
      $out[$k] = $Override[$k]
    }
  }
  return $out
}

function Get-EdgePath {
  $c = @(
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
  )
  return ($c | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

function Start-EdgeKiosk([string]$url, [string]$extraArgs) {
  $edge = Get-EdgePath
  if (-not $edge) { Warn "Edge niet gevonden."; return }
  Start-Process $edge -ArgumentList "--kiosk `"$url`" $extraArgs"
  Ok "Edge gestart (kiosk) → $url"
}

function Ensure-LocalBaseline {
  Ensure-Dir $BaseDir
  Ensure-Dir $UpdateDir
  Ensure-Dir $LogDir

  $startHtml = Join-Path $BaseDir "start.html"
  if (-not (Test-Path $startHtml) -or ((Get-Item $startHtml).Length -lt 40)) {
    Write-FallbackStartHtml $startHtml
    Warn "Fallback start.html geschreven."
  } else {
    Ok "Lokale start.html aanwezig."
  }
}

function Try-DownloadConfig($Status, $Headers) {
  # best effort: schrijf cache files als download lukt
  try {
    Get-GitHubFileTo -Repo $Status.Repo -Branch $Status.Branch -Path "common/config/base.json" -OutFile $CacheBase -Headers $Headers
    Ok "Config base.json geüpdatet."
  } catch { Warn "Kon base.json niet downloaden (cache blijft staan)." }

  try {
    Get-GitHubFileTo -Repo $Status.Repo -Branch $Status.Branch -Path ("companies/{0}/config.json" -f $Status.Company) -OutFile $CacheCompany -Headers $Headers
    Ok "Config company.json geüpdatet ($($Status.Company))."
  } catch { Warn "Kon company config niet downloaden (cache blijft staan)." }

  if ($Status.Company -eq "HZB") {
    try {
      Get-GitHubFileTo -Repo $Status.Repo -Branch $Status.Branch -Path "companies/HZB/module.ps1" -OutFile $CacheModule -Headers $Headers
      Ok "HZB module geüpdatet."
    } catch { Warn "Kon HZB module niet downloaden (cache blijft staan)." }
  }
}

function Sync-Files($cfg,$Headers,$Company) {
  foreach ($f in $cfg.sync) {

    $path = $null
    if ($f.pathTemplate) { $path = $f.pathTemplate.Replace("{Company}", $Company) }
    else { $path = $f.path }

    $dest = $f.dest
    $tmp  = Join-Path $UpdateDir ([IO.Path]::GetFileName($dest))

    try {
      Get-GitHubFileTo -Repo $cfg.repo -Branch $cfg.branch -Path $path -OutFile $tmp -Headers $Headers
      if ((Get-Item $tmp).Length -gt 0) {
        Copy-Item $tmp $dest -Force
        Ok "Synced: $path"
      }
    } catch {
      if ($f.optional -eq $true) {
        Warn "Optional sync skip: $path"
        continue
      }
      throw
    }
  }
}

function Send-Heartbeat($cfg,$Headers,$Status) {
  if (-not $cfg.heartbeat.enabled) { return }

  $csvPath = $cfg.heartbeat.csvPath
  $getUri  = "https://api.github.com/repos/$($cfg.repo)/contents/$csvPath?ref=$($cfg.branch)"

  $row = ("{0},{1},{2},{3},{4}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
          $env:COMPUTERNAME, $Status.Version, $Status.Company, $Status.StartupCount)

  $file = $null
  try { $file = Invoke-GH -Method "GET" -Uri $getUri -Headers $Headers } catch { }

  if (-not $file) {
    $csv = "Timestamp,ComputerName,Version,Company,BootCount`n$row`n"
    $body = @{
      message = "Init HB $env:COMPUTERNAME"
      content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($csv))
      branch = $cfg.branch
    } | ConvertTo-Json

    try {
      Invoke-GH -Method "PUT" -Uri ("https://api.github.com/repos/$($cfg.repo)/contents/$csvPath") -Headers $Headers -BodyJson $body | Out-Null
      Ok "Heartbeat init geschreven."
    } catch { Warn "Heartbeat init faalde." }
    return
  }

  $old = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($file.content))
  $new = ($old.TrimEnd() + "`n" + $row + "`n")

  $body2 = @{
    message = "HB $env:COMPUTERNAME"
    content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($new))
    sha = $file.sha
    branch = $cfg.branch
  } | ConvertTo-Json

  try {
    Invoke-GH -Method "PUT" -Uri ("https://api.github.com/repos/$($cfg.repo)/contents/$csvPath") -Headers $Headers -BodyJson $body2 | Out-Null
    Ok "Heartbeat geschreven."
  } catch {
    Warn "Heartbeat faalde → retry (sha conflict?)"
    try {
      $file2 = Invoke-GH -Method "GET" -Uri $getUri -Headers $Headers
      $old2 = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($file2.content))
      $new2 = ($old2.TrimEnd() + "`n" + $row + "`n")
      $body3 = @{
        message = "HB $env:COMPUTERNAME (retry)"
        content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($new2))
        sha = $file2.sha
        branch = $cfg.branch
      } | ConvertTo-Json
      Invoke-GH -Method "PUT" -Uri ("https://api.github.com/repos/$($cfg.repo)/contents/$csvPath") -Headers $Headers -BodyJson $body3 | Out-Null
      Ok "Heartbeat retry geschreven."
    } catch {
      Warn "Heartbeat retry faalde."
    }
  }
}

# ----------------------------
# MAIN FLOW
# ----------------------------
try {
  Write-Host "==========================================" -ForegroundColor DarkGray
  Write-Host " TBI Kiosk Bootstrap-Launch" -ForegroundColor White
  Write-Host "==========================================" -ForegroundColor DarkGray

  Ensure-LocalBaseline

  $Status = Load-Status
  $Status.StartupCount = [int]$Status.StartupCount + 1
  Save-Status $Status
  Ok "StartupCount verhoogd → $($Status.StartupCount)"

  # 1) DIRECT starten: altijd eerst Edge naar lokale start.html
  $localUrl = "file:///C:/Kiosk/start.html"
  Start-EdgeKiosk -url $localUrl -extraArgs "--edge-kiosk-type=fullscreen --no-first-run"

  # 2) GitHub acties alleen als token er is
  $token = Get-TokenPlain
  if (-not $token) {
    Warn "Geen token → config/sync/heartbeat overgeslagen."
    exit 0
  }
  Ok "Token aanwezig."

  $Headers = @{
    "Authorization" = "Bearer $token"
    "Accept"        = "application/vnd.github+json"
    "User-Agent"    = "TBI-Kiosk"
  }

  # 3) Configs downloaden (best effort) → cache
  Info "Download configs (best effort)..."
  Try-DownloadConfig -Status $Status -Headers $Headers

  # 4) Configs laden uit cache
  if (-not (Test-Path $CacheBase))   { throw "base.json ontbreekt in cache (C:\Kiosk\base.json)" }
  if (-not (Test-Path $CacheCompany)){ Warn "company.json ontbreekt in cache (C:\Kiosk\company.json) → base-only" }

  $baseObj = Get-Content $CacheBase -Raw | ConvertFrom-Json
  if (Test-Path $CacheCompany) {
  $compObj = Get-Content $CacheCompany -Raw | ConvertFrom-Json
} else {
  $compObj = [pscustomobject]@{}
}


  $cfg = Merge-Hashtable -Base (To-Hashtable $baseObj) -Override (To-Hashtable $compObj)
  Ok "Config geladen (base + override)."

  # 5) Bestanden syncen (portal/version) – gebruikt company portal eerst
  Info "Sync files (portal/version)..."
  try {
    Sync-Files -cfg $cfg -Headers $Headers -Company $Status.Company
    Ok "File sync klaar."
  } catch {
    Warn ("File sync faalde: " + $_.Exception.Message)
  }

  # 6) Update status.version uit lokale version.txt
  $verPath = Join-Path $BaseDir "version.txt"
  if (Test-Path $verPath) {
    $Status.Version = (Get-Content $verPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
    Save-Status $Status
    Ok "Versie gezet → $($Status.Version)"
  }

  # 7) Per bedrijf startup override (HZB → app via module)
  if ($cfg.startup.mode -eq "app") {
    Info "Company startup mode = app"

    $started = $false
    if ($cfg.startup.app.useModule -and (Test-Path $CacheModule)) {
      Info "Laad company module..."
      . $CacheModule
      if (Get-Command Start-CompanyApp -ErrorAction SilentlyContinue) {
        $started = Start-CompanyApp -Config $cfg -Log { param($m) Log $m }
        if ($started) { Ok "Company app gestart via module." }
      } else {
        Warn "Start-CompanyApp niet gevonden in module."
      }
    }

    if (-not $started -and $cfg.startup.app.exeCandidates) {
      Warn "Module startte niet → probeer exeCandidates direct"
      foreach ($c in $cfg.startup.app.exeCandidates) {
        if ($c -and (Test-Path $c)) {
          try {
            Start-Process -FilePath $c
            $started = $true
            Ok "App gestart: $c"
            break
          } catch { Warn "Start-Process faalde: $c" }
        }
      }
    }

    if (-not $started) {
      Warn "App start faalde → fallback naar Edge"
      Start-EdgeKiosk -url $cfg.startup.fallback.edge.url -extraArgs $cfg.startup.fallback.edge.args
    }
  } else {
    Ok "Startup mode = edge (default)."
  }

  # 8) Heartbeat (best effort)
  Info "Heartbeat..."
  try { Send-Heartbeat -cfg $cfg -Headers $Headers -Status $Status }
  catch { Warn ("Heartbeat exception: " + $_.Exception.Message) }

  Ok "Bootstrap-Launch klaar."

} catch {
  Fail ("Fatal: " + $_.Exception.Message)
}
