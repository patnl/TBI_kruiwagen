# Migratie: oude TBI_kruiwagen → nieuwe opzet

Dit document beschrijft hoe je de bestaande repo vervangt door de nieuwe modulaire opzet.

## Wat er verandert

| Oud | Nieuw | Reden |
|-----|-------|-------|
| `common/scripts/Setup-TBI-Kiosk.ps1` | `setup.ps1` (root) | Eén entrypoint, direct aanroepbaar via `irm` |
| `common/scripts/Bootstrap-Launch.ps1` | `bootstrap.ps1` (root) | Auto-update bij elke boot |
| `common/config/base.json` | defaults in `modules/*.ps1` | Minder indirectie |
| `companies/HZB/config.json` | `config/hazenberg.json` | Platte structuur, volledige naam zichtbaar in wizard |
| `companies/HZB/module.ps1` | `modules/dalux.ps1` (gedeeld) | Dalux-logica herbruikbaar voor andere bedrijven |
| `fleet_status.csv` | `registry/devices.json` + `registry/dashboard.html` | Concurrent-write-safe via GitHub API + live dashboard |
| `TeamViewer_Host_Setup.exe` | config-driven download | Geen 20MB binary in Git |
| `TVSettings.tvopt` | → `assets/teamviewer/TVSettings.tvopt` | Bij assets waar hij hoort |
| `common/portal/*` | *(nog niet gemigreerd — zie hieronder)* | Kan als extra module worden toegevoegd |
| `version.txt` | `version.txt` (ongewijzigd) | — |

## Wat er blijft

- **Hufterproof-principe**: bootstrap draait eerst lokaal, pakt alleen updates mee als netwerk + GitHub bereikbaar zijn
- **DPAPI-encrypted PAT**: zelfde methode, nieuwe locatie `C:\KioskSetup\.ghpat`
- **Per-bedrijf configuratie**: alleen de structuur is platter
- **TeamViewer als remote tool**: nu een keuze naast ZeroTier/RDP, configureerbaar per bedrijf

## Migratiestappen

### 1. Backup van huidige repo

```bash
git clone https://github.com/patnl/TBI_kruiwagen.git TBI_kruiwagen_backup
```

### 2. Clear en vervang

```bash
cd TBI_kruiwagen
git rm -r common/ companies/ fleet_status.csv TeamViewer_Host_Setup.exe TVSettings.tvopt "Nieuw - Tekstdocument.txt" ".DS_Store" "powershell -ExecutionPolicy Bypass.txt"
git commit -m "Opschonen oude structuur voor migratie"
```

### 3. Kopieer nieuwe bestanden naar root

Pak de zip uit en commit de inhoud naar root van `TBI_kruiwagen`:

```
TBI_kruiwagen/
├── setup.ps1
├── bootstrap.ps1
├── version.txt
├── README.md
├── config/
│   ├── hazenberg.json    (voorheen companies/HZB/config.json)
│   ├── tbi.json
│   └── ... (12 bedrijfsconfigs)
├── modules/
│   ├── accounts.ps1
│   ├── admin-trigger.ps1
│   ├── branding.ps1
│   ├── browser.ps1
│   ├── dalux.ps1          (voorheen companies/HZB/module.ps1, nu hergebruikt)
│   ├── kiosk-shell.ps1
│   ├── registry.ps1
│   ├── remote.ps1
│   ├── splash.ps1
│   ├── wifi.ps1
│   └── wizard.ps1
├── registry/
│   ├── devices.json       (vervangt fleet_status.csv)
│   └── dashboard.html
└── assets/                (nieuw — hier komen WiFi-profielen, TV-settings, lockscreen)
    ├── wifi/
    ├── teamviewer/
    └── lockscreen.jpg
```

### 4. TeamViewer-settings migreren

Je bestaande `TVSettings.tvopt` bewaar je, maar niet in root:

```bash
mkdir -p assets/teamviewer
mv /pad/naar/TVSettings.tvopt assets/teamviewer/
```

In `modules/remote.ps1` kan de TV-sectie dit bestand binnenhalen bij installatie — script is al voorbereid op dat pad.

### 5. PAT-locatie aanpassen (bestaande installaties)

Oude locatie: `C:\Kiosk\github_pat.enc`
Nieuwe locatie: `C:\KioskSetup\.ghpat`

Eenmalig migratiescriptje voor bestaande kiosks:

```powershell
if (Test-Path "C:\Kiosk\github_pat.enc" -and -not (Test-Path "C:\KioskSetup\.ghpat")) {
    New-Item -ItemType Directory -Force -Path "C:\KioskSetup" | Out-Null
    Move-Item "C:\Kiosk\github_pat.enc" "C:\KioskSetup\.ghpat"
}
```

### 6. GitHub Pages inschakelen

Settings → Pages → Source: `main` / `(root)` → Save.
Dashboard wordt beschikbaar op:
```
https://patnl.github.io/TBI_kruiwagen/registry/dashboard.html
```

### 7. Eerste installatie op een testmachine

```powershell
# Op een nieuwe/test Windows 11 machine:
Set-ExecutionPolicy Bypass -Scope Process -Force
irm https://raw.githubusercontent.com/patnl/TBI_kruiwagen/main/setup.ps1 | iex
```

De wizard start, je kiest een bedrijf, stelt PIN in, plakt PAT, en bij de volgende reboot staat het apparaat in de live registry.

## Tegenwoordige repo-bestanden die weg kunnen

- `.DS_Store` (macOS rommel)
- `Nieuw - Tekstdocument.txt` (leeg test-bestand)
- `powershell -ExecutionPolicy Bypass.txt` (los notitie-bestand)
- `TeamViewer_Host_Setup.exe` (20MB binary — kan via winget of URL)

Gebruik de meegeleverde `.gitignore` om dit in de toekomst te voorkomen.

## Portal migreren (optioneel, later)

Je `common/portal/*` bestanden waren een extra HTML-interface voor de kiosk. Als je daar nog iets mee wilt: maak er een `modules/portal.ps1` van die de portal-bestanden ophaalt naar `C:\KioskSetup\portal\` en een shortcut op het bureaublad zet. Laat weten of je wilt dat ik die module erbij bouw.
