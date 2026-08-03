# Dagelijkse FireMap-export voor Flourish

Dit project haalt elke dag de Europese brandpunten van FireMap.live op, zet ze
om naar een Flourish-vriendelijke CSV en bewaart de actuele bestanden in GitHub.
De gebruikte laag is dezelfde als in de VRT NWS-voorbeeldkaart:
`FireDB:modis_ba_pt_7day` (branddetecties van de laatste zeven dagen).

## Datastroom

```text
FireMap.live WFS (GeoJSON)
        ↓ ophalen + valideren
R/firemap_pipeline.R
        ↓
data/flourish_branden.csv
        ↓ publieke raw GitHub-URL
Flourish Live CSV
```

De pijplijn overschrijft de vorige geldige bestanden niet wanneer het ophalen,
inlezen van JSON of de datavalidatie mislukt. De HTTP-aanvraag gebruikt een
herkenbare identificatie, een tijdslimiet en herhaalpogingen voor tijdelijke
serverproblemen.

## Belangrijkste bestanden

| Bestand | Functie |
|---|---|
| `scripts/update_firemap.R` | Handmatige en automatische update starten |
| `R/firemap_pipeline.R` | Ophalen, transformeren, valideren en exporteren |
| `data/flourish_branden.csv` | Hoofdtabel voor een Flourish-puntenkaart |
| `data/flourish_statussamenvatting.csv` | Aantallen en hectaren per status |
| `data/firemap_bron.geojson` | Onbewerkte momentopname voor controle/hergebruik |
| `data/firemap_metagegevens.json` | Bijwerkdatum, aantallen, bron en licentie |
| `.github/workflows/update-firemap.yml` | Dagelijkse GitHub Action |

## Lokaal uitvoeren

R 4.1 of nieuwer is voldoende.

```r
install.packages(c("httr2", "jsonlite"))
source("R/firemap_pipeline.R", encoding = "UTF-8")
run_firemap_pipeline()
```

Of via de commandoregel:

```bash
Rscript tests/test_pipeline.R
Rscript scripts/update_firemap.R
Rscript scripts/check_outputs.R
```

Optionele omgevingsvariabelen zijn `FIREMAP_SOURCE_URL`,
`FIREMAP_OUTPUT_DIR`, `FIREMAP_MIN_ROWS` en `FIREMAP_TIMEOUT_SECONDS`.

## Dagelijkse GitHub-update

De workflow draait dagelijks om **06:17 in `Europe/Brussels`** en kan ook
handmatig worden gestart via **Actions → FireMap-gegevens dagelijks bijwerken →
Workflow uitvoeren** (in een Engelstalige GitHub-interface heet die laatste knop
**Run workflow**).
Hij installeert de twee R-afhankelijkheden, test de transformatie, haalt de data
op, valideert alle exports en commit alleen de map `data/`.

De workflow bevat `permissions: contents: write`. Als een organisatiebeleid dit
blokkeert, moet bij **Settings → Actions → General → Workflow permissions**
schrijftoegang voor de workflow mogelijk zijn. Geplande runs werken pas wanneer
het workflowbestand op de standaardbranch staat en kunnen bij drukte iets later
starten.

## Koppelen aan Flourish

De repository moet publiek zijn. Gebruik in Flourish onder **Data** de optie
**Import from URL** en plak deze raw URL:

```text
https://raw.githubusercontent.com/FixyDesing/260803_firemap_DSI/main/data/flourish_branden.csv
```

Kies de Flourish-template **Marker map** en gebruik deze koppelingen:

| Select columns to visualise | CSV-kolom |
|---|---|
| Latitude (Required) | `breedtegraad` |
| Longitude (Required) | `lengtegraad` |
| Marker | Leeg laten voor gewone bollen |
| Name | `weergavenaam` |
| Description | Leeg laten; de aangepaste pop-up toont de details |
| Photo | Leeg laten |
| Link | `bron_url` (optioneel) |
| Category | `status` |
| Color | `markerkleur` |
| Size | `markergrootte` |
| Info for popups | `landnaam`, `oppervlakte`, `ontstaansdatum`, `duur`, `status_bijgewerkt`, `brandgevaar`, `bron`, `bron_url` |

Gebruik de gevraagde vaste kleuren:

- Niet onder controle: `#AA3228`
- Onder controle: `#E07154`
- Uitgedoofd: `#FCD9BE`
- Onbekend: `#808080`

`markergrootte` zet de oppervlakte logaritmisch om naar een begrensde waarde van
0,1 tot en met 2. Daardoor blijven onderlinge verschillen zichtbaar, maar kunnen
zeer grote branden de kaart niet meer bedekken. In de huidige gegevens ligt de
mediaan rond 0,94. Stel de beginuitsnede in Flourish in op Europa. Voeg als
bronregel toe:
**Data: FireMap.live (EFFIS en NASA FIRMS)**.

### Aangepaste pop-up

Bind eerst alle hierboven vermelde kolommen. Kies daarna bij de pop-upinstellingen
voor **Custom content** en gebruik bijvoorbeeld:

```html
<article class="brand-popup">
  <p class="brand-kicker">{{landnaam}} · {{status}}</p>
  <h3>{{weergavenaam}}</h3>
  <p class="brand-update">Stand van {{status_bijgewerkt}}</p>

  <p class="brand-oppervlakte">{{oppervlakte}}</p>

  <dl class="brand-feiten">
    <div><dt>Ontstaan</dt><dd>{{ontstaansdatum}}</dd></div>
    <div><dt>Brandduur</dt><dd>{{duur}}</dd></div>
    <div><dt>Brandgevaar</dt><dd>{{brandgevaar}}</dd></div>
  </dl>

  <p class="brand-bron"><a href="{{bron_url}}" target="_blank">{{bron}}</a></p>
</article>

<style>
.brand-popup {
  box-sizing: border-box;
  min-width: 175px;
  max-width: 210px;
  padding: 7px 9px 6px;
  border-top: 1px solid #111;
  font-family: Arial, Helvetica, sans-serif;
  color: #121212;
}
.brand-popup h3 {
  margin: 2px 0 3px;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 16px;
  font-weight: 700;
  line-height: 1.1;
}
.brand-kicker {
  margin: 0;
  color: #555;
  font-size: 8.5px;
  font-weight: 700;
  letter-spacing: .06em;
  text-transform: uppercase;
}
.brand-update {
  margin: 0 0 6px;
  color: #777;
  font-size: 9px;
  line-height: 1.2;
}
.brand-oppervlakte {
  margin: 0 0 5px;
  font-family: Georgia, "Times New Roman", serif;
  font-size: 15px;
  font-weight: 700;
  line-height: 1.1;
}
.brand-feiten {
  margin: 0;
  border-top: 1px solid #d7d7d7;
}
.brand-feiten div {
  display: grid;
  grid-template-columns: 1fr 1.15fr;
  gap: 6px;
  padding: 3px 0;
  border-bottom: 1px solid #e6e6e6;
}
.brand-feiten dt {
  color: #666;
  font-size: 9px;
}
.brand-feiten dd {
  margin: 0;
  font-size: 9px;
  font-weight: 700;
  text-align: right;
}
.brand-bron {
  margin: 5px 0 0;
  font-size: 8.5px;
}
.brand-bron a {
  color: #666;
  text-decoration: underline;
}
</style>
```

FireMap.live levert geen afzonderlijk tijdstip waarop een brand precies onder
controle kwam. `Stand van` toont daarom het tijdstip van de laatste bronupdate
waarop de weergegeven status bekend was; ontbrekende waarden worden eerlijk als
`Niet beschikbaar` getoond.

Automatisch gekoppelde Live CSV-data is volgens Flourish alleen beschikbaar op
Publisher- en Enterprise-abonnementen. Met een ander abonnement kan dezelfde CSV
wel handmatig worden geüpload, maar ververst Flourish de gepubliceerde kaart niet
automatisch.

## Bron, licentie en waarschuwing

- Kaart en feed: [FireMap.live](https://firemap.live/)
- Achterliggende bronnen: [EFFIS](https://forest-fire.emergency.copernicus.eu/)
  en [NASA FIRMS](https://firms.modaps.eosdis.nasa.gov/)
- Voorbeeldontwerp: [VRT NWS – Actieve bosbranden](https://interactief.vrtnws.be/kaart-bosbranden/)
- FireMap.live vermeldt voor deze dataset
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); behoud daarom de
  bronvermelding in de kaart.

De gegevens zijn informatief en niet bedoeld voor evacuatie-, veiligheids- of
operationele beslissingen. Raadpleeg daarvoor altijd de bevoegde lokale diensten.
