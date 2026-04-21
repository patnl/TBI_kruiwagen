# WiFi-inventaris TBI Kruiwagen

Overzicht welke WiFi-gegevens per bedrijf bekend zijn en waar nog informatie ontbreekt.

## Bekende netwerken

| Bedrijf | Config | SSID | Status |
|---------|--------|------|--------|
| Jeroen's testnetwerk | `test.json` | `Mobile1` | ✅ **Verborgen netwerk** (hidden SSID) — `"hidden": true` in config |
| TBI SSC ICT (Jeroen IoT) | `tbi.json` | `TBI-IoT` | ✅ Apart VLAN voor IoT/kiosks — goede segregatie |

## Nog in te vullen

Voor deze bedrijven moet nog ophelderd worden welk WiFi-netwerk gebruikt wordt.
Contacteer per bedrijf de lokale IT-verantwoordelijke.

| Bedrijf | Code | Status | Contact | SSID | Notities |
|---------|------|--------|---------|------|----------|
| TBI Holdings | `holding` | ⏳ | | | |
| Comfort Partners | `comfort` | ⏳ | | | |
| Croonwolter&dros | `croon` | ⏳ | | | |
| Eekels Technology | `eekels` | ⏳ | | | |
| ERA Contour | `era` | ⏳ | | | |
| Hazenberg Bouw | `hazenberg` | ⏳ | Alexander Hoos (Hanab) | | Pilot-bedrijf — eerst regelen |
| JP van Eesteren | `jpvaneesteren` | ⏳ | | | |
| Koopmans Bouwgroep | `koopmans` | ⏳ | | | |
| MDB | `mdb` | ⏳ | | | |
| Nico de Bont | `nicodebont` | ⏳ | | | |
| geWOONhout | `gewoonhout` | ⏳ | | | Op HOLD sinds oktober |
| Mobilis | `mobilis` | ⏳ | | | |
| Giesbers InstallatieGroep | `giesbers` | ⏳ | | | Eigen huisstijl |
| Soltegro | `soltegro` | ⏳ | | | Eigen huisstijl |
| WTH Vloerverwarming | `wth` | ⏳ | | | Eigen huisstijl |
| HEVO | `hevo` | ⏳ | | | Eigen huisstijl |
| Rutges Vernieuwt | `rutges` | ⏳ | | | Eigen huisstijl |
| Synchroon | `synchroon` | ⏳ | | | Eigen huisstijl |
| Voorbij Prefab | `voorbij` | ⏳ | | | Eigen huisstijl |
| Struijk | `struijk` | ⏳ | | | Eigen huisstijl |
| Voorbij Funderingstechniek | `voorbijfund` | ⏳ | | | Eigen huisstijl |
| Voton | `voton` | ⏳ | | | Eigen huisstijl |

## Per-bedrijf vragenlijst voor lokaal IT

1. **SSID** — Wat is de exacte netwerknaam waarmee de kiosk moet verbinden?
2. **Beveiligingstype** — WPA2-Personal (wachtwoord), WPA2-Enterprise (802.1X domein), of open?
3. **Wachtwoord/credentials** — Liever niet per mail. Voorkeur: direct invoeren op de kiosk bij setup
4. **Hidden network?** — Is het netwerk verborgen (niet-broadcast)?
5. **VLAN-beperkingen** — Moet de kiosk in een specifieke VLAN/subnet zitten?
6. **Internet-toegang** — Heeft het netwerk onbeperkte internet (voor Dalux-licentie, Microsoft-updates, GitHub sync)?

## Hoe wachtwoorden veilig invoeren

De setup-wizard vraagt bij eerste installatie om het WiFi-wachtwoord. Dit wordt:
- **DPAPI-versleuteld** met scope `LocalMachine`
- Opgeslagen in `C:\KioskSetup\.wifi-secrets.json`
- **Nooit** naar GitHub gepusht (staat in `.gitignore`)
- Alleen leesbaar op dezelfde machine, niet overdraagbaar

## Config aanpassen wanneer SSID bekend is

Open `config/[bedrijf].json` en pas aan:

```json
"wifi": [{
  "ssid": "DE-ECHTE-SSID",
  "primary": true
}]
```

Voor WPA2-Enterprise (domein-auth):
```json
"wifi": [{
  "ssid": "BEDRIJF-ENT",
  "enterprise": true,
  "primary": true
}]
```

Commit en push — kiosk-machines pikken de nieuwe SSID op bij volgende boot. Het wachtwoord wordt dan gevraagd via de admin-hotkey (Ctrl+Alt+Shift+F12).
