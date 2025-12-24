<# Setup-TBI-Kiosk.ps1 (GitHub managed)
   - Maakt kiosk user + autologon + scheduled task
   - Downloadt Bootstrap-Launch.ps1 en configs/portal vanuit GitHub
   - Slaat PAT DPAPI-encrypted op als C:\Kiosk\github_pat.enc
#>

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host "Run als Administrator." -ForegroundColor Red
  exit 1
}

$ErrorActionPreference = "Stop"

# -------- Config
$Repo   = "patnl/TBI_kruiwagen"
$Branch = "main"

$BaseDir   = "C:\Kiosk"
$UpdateDir = "C:\Kiosk\updates"
$LogDir    = "C:\TBI\KioskLogs"
$StatusFile = "C:\Kiosk\machine_status.json"
$TokenFile  = "C:\Kiosk\github_pat.enc"
$BootstrapLaunch = "C:\Kiosk\Bootstrap-Launch.ps1"

$KioskUser = "kiosk"
$KioskPassPlain = "Bouwplaats!2025"
$AdminUser = "tbiadmin"
$AdminPassPlain = "@MartenMeesweg25"

function Ensure-Dir($p){ if(-not(Test-Path $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Log($m){ Ensure-Dir $LogDir; Add-Content (Join-Path $LogDir "setup.log") -Value ("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$m) -Encoding UTF8 }

function Protect-TokenLocalMachine([SecureString]$SecureToken, [string]$OutFile){
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureToken)
  try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $bytes = [Text.Encoding]::UTF8.GetBytes($plain)
    $enc = [Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
    [Convert]::ToBase64String($enc) | Set-Content -Path $OutFile -Encoding ASCII
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }
}

function Get-TokenPlain {
  $b64 = (Get-Content $TokenFile -Raw).Trim()
  $enc = [Convert]::FromBase64String($b64)
  $bytes = [Security.Cryptography.ProtectedData]::Unprotect($enc,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine)
  [Text.Encoding]::UTF8.GetString($bytes)
}

function Invoke-GH {
  param([string]$Method,[string]$Uri,[hashtable]$Headers,[string]$BodyJson=$null)
  for($i=0;$i -lt 3;$i++){
    try{
      if($BodyJson){
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $BodyJson -ContentType "application/json" -TimeoutSec 20
      } else {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec 20
      }
    } catch {
      if($i -eq 2){ throw }
      Start-Sleep -Seconds ([int][math]::Pow(2,$i))
    }
  }
}

function Get-GitHubFileTo {
  param([string]$Path,[string]$OutFile,[hashtable]$Headers)
  $uri = "https://api.github.com/repos/$Repo/contents/$Path?ref=$Branch"
  $resp = Invoke-GH -Method "GET" -Uri $uri -Headers $Headers
  $bytes = [Convert]::FromBase64String($resp.content)
  [IO.File]::WriteAllBytes($OutFile,$bytes)
}

function Ensure-LocalUser($Name,[SecureString]$Password,[switch]$IsAdmin){
  if(-not(Get-LocalUser -Name $Name -ErrorAction SilentlyContinue)){
    New-LocalUser -Name $Name -Password $Password -PasswordNeverExpires:$true -AccountNeverExpires:$true | Out-Null
    Log "User aangemaakt: $Name"
  }
  if($IsAdmin){
    try{ Add-LocalGroupMember -Group "Administrators" -Member $Name -ErrorAction Stop; Log "$Name -> Administrators" } catch {}
  }
}

function Set-AutoLogon($User,$PasswordPlain){
  $wl="HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
  Set-ItemProperty $wl "AutoAdminLogon" -Value "1" -Type String
  Set-ItemProperty $wl "DefaultUserName" -Value $User -Type String
  Set-ItemProperty $wl "DefaultPassword" -Value $PasswordPlain -Type String
  Set-ItemProperty $wl "DefaultDomainName" -Value $env:COMPUTERNAME -Type String
  Log "AutoLogon ingesteld voor $User"
}

function Register-KioskTask {
  $TaskName="TBI Kiosk Launcher"
  $ps="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $arg="-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$BootstrapLaunch`""

  if(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue){
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }
  $action=New-ScheduledTaskAction -Execute $ps -Argument $arg
  $trigger=New-ScheduledTaskTrigger -AtLogOn -User $KioskUser
  $principal=New-ScheduledTaskPrincipal -UserId $KioskUser -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
  Log "Scheduled task aangemaakt: $TaskName"
}

# -------- MAIN
try{
  Ensure-Dir $BaseDir
  Ensure-Dir $UpdateDir
  Ensure-Dir $LogDir

  $pcLabel = Read-Host "PC-nummer (bijv. KIOSK-001)"
  $bedrijven=@("HZB","ERA","JPE","CWD","KPM","TBI")
  Write-Host "Kies werkmaatschappij:"
  for($i=0;$i -lt $bedrijven.Count;$i++){ Write-Host "[$i] $($bedrijven[$i])" }
  $keuze = Read-Host "Nummer"
  if($keuze -notmatch '^\d+$' -or [int]$keuze -ge $bedrijven.Count){ throw "Ongeldige keuze." }
  $Company = $bedrijven[[int]$keuze]

  $GitHubTokenSecure = Read-Host "Voer GitHub PAT in (fine-grained, repo contents RW)" -AsSecureString
  Protect-TokenLocalMachine -SecureToken $GitHubTokenSecure -OutFile $TokenFile

  $tokenPlain = Get-TokenPlain
  $Headers=@{
    "Authorization"="Bearer $tokenPlain"
    "Accept"="application/vnd.github+json"
    "User-Agent"="TBI-Kiosk"
  }

  # Download Bootstrap-Launch vanuit GitHub
  Get-GitHubFileTo -Path "common/scripts/Bootstrap-Launch.ps1" -OutFile $BootstrapLaunch -Headers $Headers

  # Download base config + company override naar cache
  Get-GitHubFileTo -Path "common/config/base.json" -OutFile (Join-Path $BaseDir "base.json") -Headers $Headers
  Get-GitHubFileTo -Path ("companies/$Company/config.json") -OutFile (Join-Path $BaseDir "company.json") -Headers $Headers

  # Download HZB module als HZB
  if($Company -eq "HZB"){
    Get-GitHubFileTo -Path "companies/HZB/module.ps1" -OutFile (Join-Path $BaseDir "company_module.ps1") -Headers $Headers
  }

  # Status file (geen secrets)
  $status=@{
    PcLabel=$pcLabel
    Company=$Company
    Version="0.0.0"
    StartupCount=0
    Repo=$Repo
    Branch=$Branch
  }
  $status | ConvertTo-Json | Set-Content $StatusFile -Encoding UTF8

  # Users + autologon + task
  Ensure-LocalUser -Name $KioskUser -Password (ConvertTo-SecureString $KioskPassPlain -AsPlainText -Force)
  Ensure-LocalUser -Name $AdminUser -Password (ConvertTo-SecureString $AdminPassPlain -AsPlainText -Force) -IsAdmin
  try{ net user $KioskUser /passwordchg:no | Out-Null } catch {}
  Set-AutoLogon -User $KioskUser -PasswordPlain $KioskPassPlain
  Register-KioskTask

  # ACL (kort en praktisch)
  icacls $BaseDir /inheritance:r | Out-Null
  icacls $BaseDir /grant "SYSTEM:(OI)(CI)F" "Administrators:(OI)(CI)F" "$KioskUser:(OI)(CI)M" | Out-Null
  icacls $TokenFile /inheritance:r | Out-Null
  icacls $TokenFile /grant "SYSTEM:(R)" "Administrators:(R)" "$KioskUser:(R)" | Out-Null

  Write-Host "`nKlaar. Reboot: PC logt automatisch in als kiosk en start Bootstrap-Launch." -ForegroundColor Green
  Log "Setup gereed."
}catch{
  Log ("FOUT: "+$_.Exception.Message)
  Write-Host "Fout: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Zie log: $LogDir\setup.log"
  exit 1
}
