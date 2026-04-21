# modules/huisstijl.ps1 — Centrale TBI huisstijl definities
# Gebruikt door splash, admin-trigger, dashboard — één bron van waarheid

$script:TBI_HUISSTIJL = @{
    # ── GROEPSKLEUREN ────────────────────────────────────────────────────────
    Paars     = "#630d80"     # TBI paars (PMS 2607C, RGB 99,13,128)
    Groen     = "#c1e62e"     # TBI groen (PMS 381U, RGB 193,230,46)
    CallToAction = "#a816d9"  # Alleen voor beeldscherm — buttons

    # ── STEUNKLEUREN (voor interne communicatie / binnenwerken) ──────────────
    Blauw     = "#1489cc"
    Cyaan     = "#2fb2eb"
    Aqua      = "#26bdbd"
    Koudgrijs = "#768694"
    Blauwgrijs= "#869eb3"
    Warmgrijs = "#b3a69d"
    Magenta   = "#e070b2"
    Rood      = "#f26457"
    Warmgeel  = "#ffae0d"

    # ── ONDERSTEUNENDE KLEUREN ───────────────────────────────────────────────
    Zwart      = "#404040"
    Donkergrijs= "#999999"
    Middengrijs= "#cccccc"
    Lichtgrijs = "#f5f5f5"

    # ── TYPOGRAFIE ───────────────────────────────────────────────────────────
    # TBI Sans is de primaire font — aanwezig op SSC-ICT beheerde pc's
    # Segoe UI als fallback (standaard Windows 11)
    FontFamily        = "TBI Sans, Segoe UI"
    FontFallback      = "Segoe UI"
    FontKantoor       = "Verdana"   # Voor kantoordocumenten/compatibiliteit
    LetterSpacing     = "0.03em"    # 3 eenheden spatiëring

    # ── LAYOUT PRINCIPE ──────────────────────────────────────────────────────
    # "Twee over elkaar schuivende vlakken"
    # Hoofdvlak: linkerbovenhoek + rechter onderhoek
    # Logo: altijd linksboven ÓF rechtsonder (nooit andere hoek)
    LogoHoek  = "linksboven"        # of "rechtsonder"

    # ── BOUNDING BOX rond logo (1/3 hoogte marge volgens huisstijl) ─────────
    LogoMarge = 32                  # Pixels in WPF voor standaard splash
}

function Get-TBIKleur {
    param([string]$Naam)
    return $script:TBI_HUISSTIJL[$Naam]
}

# Bepaal kleurenschema per bedrijf
# Bedrijven met TBI groen-paars huisstijl vs bedrijven met eigen huisstijl
function Get-BedrijfKleurenschema {
    param([object]$Config)

    # Bedrijf kan in config aangeven: "huisstijl": "tbi" (standaard) of "eigen"
    $schema = if ($Config.huisstijl) { $Config.huisstijl } else { "tbi" }

    switch ($schema) {
        "tbi" {
            # Standaard TBI groen-paars (voor corporate/formeel)
            return @{
                Hoofd    = $script:TBI_HUISSTIJL.Paars
                Accent   = $script:TBI_HUISSTIJL.Groen
                Tekst    = "#ffffff"
                Secundair= $script:TBI_HUISSTIJL.Groen
                LogoPad  = "assets/logos/tbi-wit.png"
            }
        }
        "eigen" {
            # Bedrijven met eigen huisstijl — neutraal met blauw accent
            # (WTH, Voorbij Prefab, Giesbers, Soltegro, HEVO, Rutges, Synchroon, Struijk, Voton, Voorbij Funderingstechniek)
            return @{
                Hoofd    = $script:TBI_HUISSTIJL.Zwart
                Accent   = $script:TBI_HUISSTIJL.Blauw
                Tekst    = "#ffffff"
                Secundair= $script:TBI_HUISSTIJL.Cyaan
                LogoPad  = ""   # Bedrijf levert eigen logo in assets/logos/[code].png
            }
        }
        default {
            return Get-BedrijfKleurenschema -Config @{ huisstijl = "tbi" }
        }
    }
}
