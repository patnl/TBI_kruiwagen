<# Bootstrap-Launch.ps1 - PUBLIC GitHub (read-only) + prints
   - Start direct Edge naar lokale start.html (hufterproof)
   - Haalt latest config/portal/version op via raw.githubusercontent.com (geen token)
   - Start optioneel bedrijf-app (bijv. HZB Dalux) op basis van config/module
   - Geen heartbeat / geen writes naar GitHub
#>

$ErrorActionPreference="Stop"

$BaseDir    = "C:\Kiosk"
$UpdateDir  = "C:\Kiosk\updates"
$LogDir     = "C:\TBI\KioskLogs"
$StatusFile = "C:\Kiosk\machine_status.json"

$CacheBase   = "C:\Kiosk\base.json"
$CacheCompany= "C:\Kiosk\company.json"
$CacheModule = "C:\Kiosk\company_module.ps1"

$LocalStart  = "C:\Kiosk\start.html"
$LocalLogo   = "C:\Kiosk\Logo_TBI_RGB.png"
$LocalVer    = "C:\Kiosk\version.txt"

function Initialize-Directory($p){ if(-not(Test-Path $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log($m){ Initialize-Directory $LogDir; Add-Content (Join-Path $LogDir "launch.log") -Value ("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$m) -Encoding UTF8 }

function Info($m){ Write-Host "• $m" -ForegroundColor Cyan; Log $m }
function Ok($m){ Write-Host "✔ $m" -ForegroundColor Green; Log $m }
function Warn($m){ Write-Host "⚠ $m" -ForegroundColor Yellow; Log $m }
function Fail($m){ Write-Host "✖ $m" -ForegroundColor Red; Log $m }

function Write-FallbackStartHtml($path){
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

function Get-Status{
  try { Get-Content $StatusFile -Raw | ConvertFrom-Json }
  catch {
    [pscustomobject]@{
      Company="UNKNOWN"; Version="0.0.0"; StartupCount=0;
      Repo="patnl/TBI_kruiwagen"; Branch="main";
      RawBase="https://raw.githubusercontent.com/patnl/TBI_kruiwagen/main"
    }
  }
}
function Save-Status($s){ $s | ConvertTo-Json | Set-Content $StatusFile -Encoding UTF8 }

function Get-EdgePath {
  @(
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Start-EdgeKiosk {
  $edge = Get-EdgePath
  if(-not $edge){ Warn "Edge niet gevonden."; return }
  $url = "file:///C:/Kiosk/start.html"
  Start-Process $edge -ArgumentList "--kiosk `"$url`" --edge-kiosk-type=fullscreen --no-first-run"
  Ok "Edge gestart (kiosk) → $url"
}

function Save-RawFile {
  param([string]$RawBase,[string]$RelPath,[string]$OutFile,[switch]$Optional)
  $url = "$RawBase/$RelPath"
  try {
    Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing -TimeoutSec 20 | Out-Null
    Ok "Downloaded: $RelPath"
    return $true
  } catch {
    if($Optional){
      Warn "Skip (optional/failed): $RelPath"
      return $false
    }
    throw
  }
}


function ConvertTo-Hashtable($obj) {
  if ($null -eq $obj) { return @{} }
  if ($obj -is [System.Collections.IDictionary]) { return $obj }

  $ht = @{}
  foreach ($p in $obj.PSObject.Properties) {
    $v = $p.Value

    if ($v -is [pscustomobject]) {
      $ht[$p.Name] = ConvertTo-Hashtable $v

    } elseif ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {

      $arr = @()
      foreach ($item in $v) {
        if ($item -is [pscustomobject]) {
          $arr += ConvertTo-Hashtable $item
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
  $out=@{}; foreach($k in $Base.Keys){ $out[$k]=$Base[$k] }
  foreach($k in $Override.Keys){
    if($out[$k] -is [hashtable] -and $Override[$k] -is [hashtable]){
      $out[$k]=Merge-Hashtable -Base $out[$k] -Override $Override[$k]
    } else { $out[$k]=$Override[$k] }
  }
  $out
}

function Sync-FilesFromConfig($cfg,$Company,$RawBase){
  foreach($f in $cfg.sync){
    $rel = $f.path
    if($f.pathTemplate){ $rel = $f.pathTemplate.Replace("{Company}", $Company) }

    $dest = $f.dest
    $tmp  = Join-Path $UpdateDir ([IO.Path]::GetFileName($dest))

    try{
      Download-RawFile -RawBase $RawBase -RelPath $rel -OutFile $tmp -Optional:([bool]$f.optional) | Out-Null
      if(Test-Path $tmp -and (Get-Item $tmp).Length -gt 0){
        Copy-Item $tmp $dest -Force
      }
    } catch {
      if($f.optional -eq $true){ continue }
      throw
    }
  }
  Ok "Sync files klaar."
}

# ---- MAIN
try{
  Write-Host "==========================================" -ForegroundColor DarkGray
  Write-Host " TBI Kiosk Startup (READ ONLY)" -ForegroundColor White
  Write-Host "==========================================" -ForegroundColor DarkGray

  Ensure-Dir $BaseDir
  Ensure-Dir $UpdateDir
  Ensure-Dir $LogDir

  if(-not(Test-Path $LocalStart) -or ((Get-Item $LocalStart).Length -lt 40)){
    Write-FallbackStartHtml $LocalStart
    Warn "Fallback start.html geschreven."
  } else {
    Ok "Lokale start.html aanwezig."
  }

  # 1) DIRECT STARTEN
  Start-EdgeKiosk

  # 2) Status bijwerken
  $Status = Load-Status
  $Status.StartupCount = [int]$Status.StartupCount + 1
  Save-Status $Status
  Ok "StartupCount → $($Status.StartupCount)"

  $RawBase = $Status.RawBase
  if([string]::IsNullOrWhiteSpace($RawBase)){
    $RawBase = "https://raw.githubusercontent.com/patnl/TBI_kruiwagen/main"
    Warn "RawBase ontbrak → default gebruikt: $RawBase"
  }

  # 3) Configs updaten (best effort) → cache
  Info "Configs downloaden (best effort)..."
  Download-RawFile -RawBase $RawBase -RelPath "common/config/base.json" -OutFile $CacheBase -Optional | Out-Null
  Download-RawFile -RawBase $RawBase -RelPath ("companies/$($Status.Company)/config.json") -OutFile $CacheCompany -Optional | Out-Null

  if($Status.Company -eq "HZB"){
    Download-RawFile -RawBase $RawBase -RelPath "companies/HZB/module.ps1" -OutFile $CacheModule -Optional | Out-Null
  }

  if(-not(Test-Path $CacheBase)){
    Warn "base.json ontbreekt in cache → geen sync mogelijk (blijft bij lokale bestanden)."
    exit 0
  }

  $baseObj = Get-Content $CacheBase -Raw | ConvertFrom-Json
  if (Test-Path $CacheCompany) {
  $compObj = Get-Content $CacheCompany -Raw | ConvertFrom-Json
} else {
  $compObj = [pscustomobject]@{}
}
  $cfg = Merge-Hashtable -Base (ConvertTo-Hashtable $baseObj) -Override (ConvertTo-Hashtable $compObj)
  Ok "Config geladen (base + override)."

  # 4) Files sync (portal/version/logo) volgens config
  Info "Sync files (portal/version)..."
  Sync-FilesFromConfig -cfg $cfg -Company $Status.Company -RawBase $RawBase

  # 5) Version bijwerken uit lokale version.txt
  if(Test-Path $LocalVer){
    $Status.Version = (Get-Content $LocalVer | Select-Object -First 1).Trim()
    Save-Status $Status
    Ok "Version → $($Status.Version)"
  }

  # 6) Company app (bijv. HZB Dalux) — optioneel
  if($cfg.startup.mode -eq "app"){
    Info "Startup mode = app (company override)"

    $started=$false
    if($cfg.startup.app.useModule -and (Test-Path $CacheModule)){
      . $CacheModule
      if(Get-Command Start-CompanyApp -ErrorAction SilentlyContinue){
        $started = Start-CompanyApp -Config $cfg -Log { param($m) Log $m }
        if($started){ Ok "Company app gestart via module." }
      } else {
        Warn "Start-CompanyApp niet gevonden in module."
      }
    }

    if(-not $started -and $cfg.startup.app.exeCandidates){
      Warn "Module startte niet → exeCandidates direct proberen"
      foreach($c in $cfg.startup.app.exeCandidates){
        if($c -and (Test-Path $c)){
          try{ Start-Process -FilePath $c; $started=$true; Ok "App gestart: $c"; break } catch {}
        }
      }
    }

    if(-not $started){
      Warn "App start faalde → Edge blijft actief (fallback)."
    }
  } else {
    Ok "Startup mode = edge"
  }

  Ok "Startup klaar (read-only)."

}catch{
  Fail ("Fatal: " + $_.Exception.Message)
}
