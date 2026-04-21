# modules/admin-trigger.ps1
# Achtergrondproces dat luistert naar Ctrl+Alt+Shift+F12
# Bij juiste PIN → admin-menu beschikbaar vanuit kiosk-modus

function Register-AdminTrigger {
    param([object]$Config, [string]$GithubOrg, [string]$GithubRepo, [string]$BaseUrl)

    $username = $Config.kioskUser.username

    # Script dat continu draait als achtergrondproces
    $triggerScript = @'
Add-Type -AssemblyName System.Windows.Forms, PresentationFramework, PresentationCore, WindowsBase
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotKeyHelper : Form {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public const int MOD_CONTROL = 0x0002;
    public const int MOD_ALT     = 0x0001;
    public const int MOD_SHIFT   = 0x0004;
    public const int WM_HOTKEY   = 0x0312;
    public static bool Triggered = false;
    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == 9001) { Triggered = true; }
        base.WndProc(ref m);
    }
}
"@ -Language CSharp

$form = New-Object HotKeyHelper
$form.ShowInTaskbar = $false
$form.WindowState   = [System.Windows.Forms.FormWindowState]::Minimized
$form.Visible       = $false

# Registreer Ctrl+Alt+Shift+F12 (VK 0x7B = F12)
[HotKeyHelper]::RegisterHotKey($form.Handle, 9001,
    ([HotKeyHelper]::MOD_CONTROL -bor [HotKeyHelper]::MOD_ALT -bor [HotKeyHelper]::MOD_SHIFT),
    0x7B)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    [System.Windows.Forms.Application]::DoEvents()
    if ([HotKeyHelper]::Triggered) {
        [HotKeyHelper]::Triggered = $false
        Show-AdminPinDialog
    }
})
$timer.Start()
[System.Windows.Forms.Application]::Run($form)

function Show-AdminPinDialog {
    Add-Type -AssemblyName PresentationFramework
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" WindowStartupLocation="CenterScreen"
        Width="380" Height="260" ResizeMode="NoResize">
  <Border CornerRadius="8" Background="#630d80">
    <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="0" Opacity="0.7"/></Border.Effect>
    <StackPanel Margin="40,36,40,36">
      <TextBlock Text="TBI KIOSK BEHEER" FontFamily="Segoe UI" FontWeight="Bold"
                 FontSize="16" Foreground="White" HorizontalAlignment="Center"/>
      <Border Height="2" Background="#c1e62e" Margin="0,12,0,20"/>
      <TextBlock Text="Admin PIN invoeren" FontFamily="Segoe UI" FontSize="13"
                 Foreground="#cccccc" HorizontalAlignment="Center" Margin="0,0,0,12"/>
      <PasswordBox Name="pinBox" FontSize="22" Background="#4a0960" Foreground="White"
                   BorderBrush="#c1e62e" BorderThickness="0,0,0,2" Padding="8,6"
                   HorizontalContentAlignment="Center" MaxLength="12"/>
      <TextBlock Name="errorText" Text="" FontFamily="Segoe UI" FontSize="11"
                 Foreground="#f26457" HorizontalAlignment="Center" Margin="0,8,0,0" Height="18"/>
      <Grid Margin="0,16,0,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition/><ColumnDefinition Width="8"/><ColumnDefinition/>
        </Grid.ColumnDefinitions>
        <Button Name="cancelBtn" Grid.Column="0" Content="Annuleren"
                Background="#404040" Foreground="White" BorderThickness="0"
                Padding="0,10" FontFamily="Segoe UI" FontSize="13" Cursor="Hand"/>
        <Button Name="okBtn" Grid.Column="2" Content="OK"
                Background="#c1e62e" Foreground="#404040" BorderThickness="0"
                Padding="0,10" FontFamily="Segoe UI" FontSize="13" FontWeight="Bold" Cursor="Hand"/>
      </Grid>
    </StackPanel>
  </Border>
</Window>
'@
    $r = [System.Xml.XmlNodeReader]::new($xaml)
    $w = [Windows.Markup.XamlReader]::Load($r)
    $pinBox   = $w.FindName("pinBox")
    $errText  = $w.FindName("errorText")
    $okBtn    = $w.FindName("okBtn")
    $cancelBtn = $w.FindName("cancelBtn")

    $pinPath = "C:\KioskSetup\.adminpin"

    $okBtn.Add_Click({
        $entered = $pinBox.Password
        $hash    = [BitConverter]::ToString(
            [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($entered))
        ) -replace '-',''
        $stored  = if (Test-Path $pinPath) { (Get-Content $pinPath).Trim() } else { "" }
        if ($hash -eq $stored) {
            $w.Close()
            # Start admin-menu in elevated PowerShell
            $adminScript = "C:\KioskSetup\admin-menu.ps1"
            Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$adminScript`"" `
                          -Verb RunAs -WindowStyle Normal
        } else {
            $errText.Text = "Onjuiste PIN — probeer opnieuw"
            $pinBox.Clear()
            $pinBox.Focus()
        }
    })
    $cancelBtn.Add_Click({ $w.Close() })
    $pinBox.Add_KeyDown({
        if ($_.Key -eq "Return") { $okBtn.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent)) }
    })
    $pinBox.Focus()
    $w.ShowDialog() | Out-Null
}
'@

    # Admin-menu script (draait na succesvolle PIN)
    $menuScript = @"
#Requires -RunAsAdministrator
Set-ExecutionPolicy Bypass -Scope Process -Force
`$company = (Get-Content 'C:\KioskSetup\company.txt' -ErrorAction SilentlyContinue)?.Trim()
`$baseUrl  = (Get-Content 'C:\KioskSetup\baseurl.txt' -ErrorAction SilentlyContinue)?.Trim()
`$org      = (Get-Content 'C:\KioskSetup\org.txt'     -ErrorAction SilentlyContinue)?.Trim()
`$repo     = (Get-Content 'C:\KioskSetup\repo.txt'    -ErrorAction SilentlyContinue)?.Trim()

# Laad wizard module
`$wiz = Invoke-RestMethod "`$baseUrl/modules/wizard.ps1" -ErrorAction SilentlyContinue
if (`$wiz) { `$wiz | Out-File 'C:\KioskSetup\wizard.ps1' -Encoding UTF8; . 'C:\KioskSetup\wizard.ps1' }

Clear-Host
Write-Host ''
Write-Host '  TBI KIOSK — BEHEER' -ForegroundColor Magenta
Write-Host "  Computer: `$env:COMPUTERNAME  |  Huidig: `$company" -ForegroundColor Gray
Write-Host ''
Write-Host '  [1] Update uitvoeren (haal laatste GitHub-versie op)' -ForegroundColor White
Write-Host '  [2] Ander bedrijf / variant instellen' -ForegroundColor White
Write-Host '  [3] WiFi-profielen opnieuw pushen' -ForegroundColor White
Write-Host '  [4] Device verwijderen uit register' -ForegroundColor White
Write-Host '  [5] Logbestanden openen' -ForegroundColor White
Write-Host '  [6] Systeem herstarten' -ForegroundColor White
Write-Host '  [7] Sluiten' -ForegroundColor White
Write-Host ''
`$keuze = Read-Host '  Keuze'

switch (`$keuze.Trim()) {
    '1' {
        Write-Host '  Update wordt uitgevoerd...' -ForegroundColor Cyan
        `$env:KIOSK_COMPANY = `$company
        `$env:KIOSK_UPDATE_ONLY = '1'
        irm "`$baseUrl/setup.ps1" | iex
    }
    '2' {
        `$newCompany = Invoke-SetupWizard -GithubOrg `$org -GithubRepo `$repo -BaseUrl `$baseUrl
        `$newCompany | Out-File 'C:\KioskSetup\company.txt' -Encoding UTF8
        `$env:KIOSK_COMPANY = `$newCompany
        irm "`$baseUrl/setup.ps1" | iex
    }
    '3' {
        `$env:KIOSK_COMPANY = `$company
        `$env:KIOSK_UPDATE_ONLY = '1'
        irm "`$baseUrl/setup.ps1" | iex
    }
    '5' {
        Start-Process explorer.exe 'C:\KioskSetup'
    }
    '6' {
        Restart-Computer -Force
    }
}
Read-Host 'Druk Enter om te sluiten'
"@

    $triggerPath = "C:\KioskSetup\hotkey-listener.ps1"
    $menuPath    = "C:\KioskSetup\admin-menu.ps1"

    # Bewaar org/repo/baseurl voor gebruik in admin-menu
    $GithubOrg  | Out-File "C:\KioskSetup\org.txt"     -Encoding UTF8
    $GithubRepo | Out-File "C:\KioskSetup\repo.txt"    -Encoding UTF8
    $BaseUrl    | Out-File "C:\KioskSetup\baseurl.txt" -Encoding UTF8

    $triggerScript | Out-File $triggerPath -Encoding UTF8
    $menuScript    | Out-File $menuPath    -Encoding UTF8

    # Logon-taak voor hotkey-listener (draait als kiosk-gebruiker)
    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$env:COMPUTERNAME\$username</UserId>
      <Delay>PT8S</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$env:COMPUTERNAME\$username</UserId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <RestartOnFailure><Interval>PT1M</Interval><Count>99</Count></RestartOnFailure>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\KioskSetup\hotkey-listener.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    $taskXml | Out-File "C:\KioskSetup\hotkey-task.xml" -Encoding Unicode
    Register-ScheduledTask -TaskName "TBI-KioskHotkey" `
                           -Xml (Get-Content "C:\KioskSetup\hotkey-task.xml" -Raw) -Force | Out-Null

    Write-Log "Admin-trigger geregistreerd: Ctrl+Alt+Shift+F12 → PIN-dialoog"
    Write-Log "Admin-menu script: C:\KioskSetup\admin-menu.ps1"
}
