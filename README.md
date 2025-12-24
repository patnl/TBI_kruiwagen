# TBI Hufterproof Kiosk

## Concept
- Installatie gebeurt NA Windows 11 installatie.
- Installer zet kiosk user + autologon + scheduled task.
- Launcher start altijd eerst lokaal (hufterproof) en haalt daarna config + portal + updates uit GitHub.
- Heartbeat schrijft regels naar fleet_status.csv.

## Repo structuur
- common/config/base.json: defaults
- companies/<bedrijf>/config.json: overrides per bedrijf
- companies/HZB/module.ps1: HZB custom (Dalux detectie)
- common/portal/*: portal bestanden
- common/scripts/Setup-TBI-Kiosk.ps1: installer (draai vanaf USB of download)
- common/scripts/Bootstrap-Launch.ps1: launcher (draait bij login kiosk)

## Token
- GitHub PAT nooit in plaintext opslaan.
- Installer bewaart token DPAPI-encrypted in C:\Kiosk\github_pat.enc
