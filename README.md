# TBI Kruiwagen — Kiosk-inrichting voor Windows 11

> Volledig geautomatiseerde kiosk-inrichting voor alle TBI-ondernemingen,
> beheerd en bijgewerkt vanuit deze GitHub repo. Hufterproof: bij
> wegvallen van internet start de kiosk op met de laatste werkende configuratie.
> Opstartscherm, dashboard en dialogen volgen de officiële TBI-huisstijl.

---

## Eerste installatie

Op een verse Windows 11 machine, PowerShell als Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm https://raw.githubusercontent.com/patnl/TBI_kruiwagen/main/setup.ps1 | iex
```

De wizard vraagt: **bedrijf**, **variant** (indien meer), **admin-PIN**, **GitHub PAT**.

---

## Alle TBI-ondernemingen

Onderverdeeld volgens het TBI merkportaal (groen-paarse huisstijl vs eigen huisstijl):

### Groen-paarse TBI-huisstijl

| Code | Bedrijf | Sector | App |
|------|---------|--------|-----|
| `tbi` | TBI SSC ICT | Holding | Edge |
| `holding` | TBI Holdings | Holding | Edge |
| `comfort` | Comfort Partners | Techniek | Edge |
| `croon` | Croonwolter&dros | Techniek | Edge |
| `eekels` | Eekels Technology | Techniek | Edge |
| `era` | ERA Contour | Bouw | Dalux |
| `hazenberg` | Hazenberg Bouw | Bouw | Dalux |
| `jpvaneesteren` | JP van Eesteren | Bouw | Dalux |
| `koopmans` | Koopmans Bouwgroep | Bouw | Dalux |
| `mdb` | MDB | Bouw | Dalux |
| `nicodebont` | Nico de Bont | Bouw | Dalux |
| `gewoonhout` | geWOONhout | Bouw | Dalux |
| `mobilis` | Mobilis | Infra | Dalux |

### Eigen huisstijl (neutrale inrichting)

| Code | Bedrijf | Sector |
|------|---------|--------|
| `giesbers` | Giesbers InstallatieGroep | Techniek |
| `soltegro` | Soltegro | Techniek |
| `wth` | WTH Vloerverwarming | Techniek |
| `hevo` | HEVO | Bouw |
| `rutges` | Rutges Vernieuwt | Bouw |
| `synchroon` | Synchroon | Bouw |
| `voorbij` | Voorbij Prefab | Bouw |
| `struijk` | Struijk | Infra |
| `voorbijfund` | Voorbij Funderingstechniek | Infra |
| `voton` | Voton | Infra |

**Nieuw bedrijf toevoegen** → kopieer een bestaande config in `config/`, pas `huisstijl` aan (`"tbi"` of `"eigen"`), push.

---

## TBI Huisstijl in scripts

Het opstartscherm, het admin-dialoog en het device-dashboard volgen de officiële TBI-huisstijl uit het merkportaal:

- **Groepskleuren** — TBI paars `#630d80`, TBI groen `#c1e62e`
- **Typografie** — TBI Sans (primair), Segoe UI/Verdana als fallback, letterspatiëring +0.03em
- **Layout-principe** — twee over elkaar schuivende vlakken (paars hoofdvlak + groen accent rechtsonder)
- **Logo** — linksboven óf rechtsonder, nooit in andere hoek; wit logo op paars, paars logo op wit
- **Bedrijven met eigen huisstijl** krijgen een neutrale variant (zwart-blauw)

Alle huisstijl-definities zitten in één plek: `modules/huisstijl.ps1`. Pas daar een kleur of regel aan en alle schermen volgen automatisch.

---

## Architectuur in één oogopslag

```
┌──────────────────────────────────────────────────────────────┐
│                  GitHub: patnl/TBI_kruiwagen                 │
│                                                              │
│  setup.ps1  ← bootstrap.ps1 bij elke boot                    │
│  ├─ modules/ (12 modules inclusief huisstijl)                │
│  ├─ config/  (23 bedrijfsconfigs)                            │
│  ├─ assets/  (logos, wifi-profielen, lockscreens)            │
│  └─ registry/ (live dashboard op GitHub Pages)               │
└──────────────────────────────────────────────────────────────┘
        ↓ irm | iex                    ↑ schrijft status
┌──────────────────────────────────────────────────────────────┐
│  Kiosk PC                                                    │
│  ├─ Boot-trigger: 15s na boot → versie-check + update        │
│  ├─ Splash: 5s bij elke logon (TBI huisstijl)                │
│  ├─ Admin-hotkey: Ctrl+Alt+Shift+F12 → PIN → menu            │
│  └─ Shell: Edge kiosk / Dalux / custom                       │
└──────────────────────────────────────────────────────────────┘
```

---

## Repo-structuur

```
TBI_kruiwagen/
├── setup.ps1, bootstrap.ps1, version.txt
├── README.md, MIGRATIE.md, .gitignore
├── config/                    23 bedrijfs-JSONs
├── modules/
│   ├── huisstijl.ps1          ⬅ Centrale TBI kleuren, fonts, layout
│   ├── accounts.ps1, admin-trigger.ps1
│   ├── branding.ps1, browser.ps1, dalux.ps1
│   ├── kiosk-shell.ps1, registry.ps1, remote.ps1
│   ├── splash.ps1, wifi.ps1, wizard.ps1
├── assets/
│   ├── logos/                 TBI en bedrijfslogo's (wit + paars)
│   ├── wifi/                  WiFi XML-profielen
│   └── teamviewer/            TVSettings.tvopt
└── registry/
    ├── devices.json           Live register (geschreven door kiosks)
    └── dashboard.html         Live dashboard (GitHub Pages)
```

---

## ZeroTier netwerkgroep

De inrichting gebruikt de ZeroTier Network Group **TBI-KRUIWAGENS-01**.
Per bedrijfsconfig vul je de specifieke network-ID in onder `remoteAccess.zerotier.networkId`.
Nieuwe devices moeten handmatig worden geautoriseerd in ZeroTier Central.

---

## Dagelijks beheer

- **Config wijzigen** → JSON aanpassen, `version.txt` ophogen, push. Alle kiosks van dat bedrijf volgen bij volgende boot.
- **WiFi-wachtwoord** → in config of XML aanpassen, oude profiel wordt automatisch vervangen.
- **Remote onderhoud** → ZeroTier IP via dashboard, RDP met admin-account, of hotkey fysiek bij de kiosk.
- **Device-overzicht** → `https://patnl.github.io/TBI_kruiwagen/registry/dashboard.html`

Zie [MIGRATIE.md](./MIGRATIE.md) voor overstap vanuit de oude `common/` + `companies/HZB/` structuur.
