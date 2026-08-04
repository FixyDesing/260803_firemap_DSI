# Dagelijkse EFFIS-, FIRMS- en FireMap-export voor Flourish

Dit project haalt elke dag de recent bijgewerkte brandgebieden van het
**European Forest Fire Information System (EFFIS)** op. Daarnaast haalt de
R-pipeline recente actieve-branddetecties op uit **NASA FIRMS**. Daardoor kunnen
nieuwe warmtebronnen al op de kaart verschijnen voordat EFFIS er een
brandperimeter voor heeft ingetekend. Waar FireMap.live hetzelfde EFFIS-id
bevat, vult de pijplijn statusindicatie, satellietdetecties en brandgevaar aan.

EFFIS publiceert geen betrouwbare controlestatus. De kleur toont daarom hoe
recent EFFIS een gebied heeft bijgewerkt, niet of een brand onder controle of
uitgedoofd is. FIRMS-markers zijn thermische satellietdetecties en dus nog geen
bevestigde natuurbrand of gemeten brandoppervlakte. De FireMap-status staat
alleen als aanvullende indicatie in de pop-up en bepaalt de kleur niet.

## Datastroom

```text
EFFIS REST-feed ───────────────┐
FireMap.live WFS (aanvulling) ─┼─ combineren, ontdubbelen + valideren
NASA FIRMS Area API ───────────┘
        ↓
R/effis_pipeline.R
        ↓
data/flourish_effis_branden.csv
        ↓ publieke raw GitHub-URL
Flourish Live CSV
```

De export overschrijft de vorige geldige bestanden niet wanneer EFFIS of de
ingestelde FIRMS-bron mislukt. Tijdelijke serverproblemen worden automatisch
opnieuw geprobeerd. Als FireMap niet bereikbaar is, gaat de update wel door en
krijgen de aanvullende velden `Niet beschikbaar`. FIRMS-detecties met lage
betrouwbaarheid, detecties op zee, vermoedelijk permanente warmtebronnen en
detecties nabij een bestaand EFFIS-brandgebied worden weggefilterd. Nabije
detecties worden per rastercel samengevoegd tot één marker.

## Belangrijkste bestanden

| Bestand | Functie |
|---|---|
| `scripts/update_effis.R` | Handmatige en automatische gecombineerde update starten |
| `R/effis_pipeline.R` | De drie bronnen combineren, valideren en exporteren |
| `R/firms_pipeline.R` | NASA FIRMS ophalen, filteren en tot hotspotclusters samenvoegen |
| `data/flourish_effis_branden.csv` | Hoofdtabel voor de Flourish Marker map |
| `data/flourish_effis_actualiteitssamenvatting.csv` | Aantallen en hectaren per actualiteitscategorie |
| `data/effis_bronselectie.json` | Compacte selectie van de gebruikte EFFIS-records |
| `data/effis_metagegevens.json` | Bijwerkdatum, selectieperiode, bron en beperkingen |
| `.github/workflows/update-firemap.yml` | Dagelijkse GitHub Action |

De zelfstandige FireMap.live-bestanden blijven beschikbaar als referentie. De
dagelijkse hoofdexport gebruikt FireMap voortaan alleen als niet-blokkerende
aanvullende bron.

## Lokaal uitvoeren

R 4.1 of nieuwer is voldoende.

```r
install.packages(c("httr2", "jsonlite"))
source("R/firemap_pipeline.R", encoding = "UTF-8")
source("R/firms_pipeline.R", encoding = "UTF-8")
source("R/effis_pipeline.R", encoding = "UTF-8")
run_effis_pipeline()
```

Of via de commandoregel:

```bash
Rscript tests/test_effis_pipeline.R
Rscript scripts/update_effis.R
Rscript scripts/check_effis_outputs.R
```

Optionele omgevingsvariabelen zijn `EFFIS_SOURCE_URL`, `EFFIS_OUTPUT_DIR`,
`EFFIS_WINDOW_DAYS`, `EFFIS_MIN_ROWS`, `EFFIS_TIMEOUT_SECONDS`,
`EFFIS_PAGE_SIZE`, `EFFIS_REFERENCE_DATE`, `EFFIS_FIREMAP_SOURCE_URL`,
`EFFIS_FIREMAP_TIMEOUT_SECONDS`, `FIRMS_MAP_KEY`, `FIRMS_SOURCES`, `FIRMS_AREA`,
`FIRMS_RECENT_HOURS`, `FIRMS_CLUSTER_DEGREES`, `FIRMS_TIMEOUT_SECONDS` en
`FIRMS_MAX_TRIES`.

## Dagelijkse GitHub-update

De workflow draait dagelijks om **05.23 UTC**. Dat is **07.23 uur tijdens de
Belgische zomertijd** en **06.23 uur tijdens de wintertijd**. De UTC-planning
vermijdt de tijdzoneconfiguratie die bij de eerste FireMap-planning niet
automatisch startte.

De workflow kan ook handmatig worden gestart via **Actions → EFFIS-, FIRMS- en
FireMap-gegevens dagelijks bijwerken → Run workflow**. Hij installeert de
R-afhankelijkheden, voert beide lokale testbestanden uit, haalt de drie bronnen
op, valideert de export en commit uitsluitend de vier hoofdgegevensbestanden.
Standaard gebruikt de workflow de VIIRS-feeds van NOAA-21 en NOAA-20. Als één
van beide tijdelijk niet antwoordt, gaat de update verder met de andere feed;
alleen wanneer beide mislukken blijft de vorige geldige CSV behouden.
Een onbevestigde satellietdetectie blijft maximaal 48 uur na de laatste
detectie op de kaart staan.

NASA vereist een gratis API-sleutel. Die staat niet in de code, maar moet in de
repository als Actions-secret `FIRMS_MAP_KEY` worden bewaard. Dat kan via
**Settings → Secrets and variables → Actions → New repository secret**, of met:

```bash
gh secret set FIRMS_MAP_KEY
```

De workflow gebruikt `permissions: contents: write`. Als een GitHub-beleid dit
blokkeert, moet bij **Settings → Actions → General → Workflow permissions**
schrijftoegang mogelijk zijn.

## Koppelen aan Flourish

Gebruik in Flourish onder **Data** de optie **Import from URL** en plak na het
samenvoegen van de EFFIS-PR deze raw URL:

```text
https://raw.githubusercontent.com/FixyDesing/260803_firemap_DSI/main/data/flourish_effis_branden.csv
```

Kies de Flourish-template **Marker map** en gebruik deze koppelingen:

| Select columns to visualise | Nieuwe CSV-kolom |
|---|---|
| Latitude (Required) | `breedtegraad` |
| Longitude (Required) | `lengtegraad` |
| Marker | Leeg laten voor gewone bollen |
| Name | `weergavenaam` |
| Description | Leeg laten; de aangepaste pop-up toont de details |
| Photo | Leeg laten |
| Link | `bron_url` (optioneel) |
| Category | `actualiteit` |
| Color | `markerkleur` |
| Size | `markergrootte` |
| Info for popups | `regio`, `weergavenaam`, `oppervlakte`, `statusindicatie`, `detecties_24u`, `detecties_7d`, `brandgevaar`, `eerste_registratiedatum` |

De kleuren betekenen voortaan:

- Actieve satellietdetectie: `#F7CF8E`
- Vandaag bijgewerkt: `#AA3228`
- Afgelopen 3 dagen bijgewerkt: `#E07154`
- 4–7 dagen geleden bijgewerkt: `#FCD9BE`
- Actualiteit onbekend: `#808080`

`markergrootte` zet de EFFIS-oppervlakte logaritmisch om naar een waarde van
0,1 tot en met 3. Daardoor blijven grote verschillen zichtbaar zonder dat de
grootste gebieden de kaart volledig bedekken. Als de oppervlakte niet bekend
is, waaronder bij FIRMS-detecties, is de markergrootte altijd `0,66`. Voeg als
bronregel toe:
**Data: EFFIS – Copernicus Emergency Management Service, NASA FIRMS en FireMap.live;
bewerking: DSI**.

### Nieuwe aangepaste pop-up

Bind eerst de hierboven vermelde kolommen. Vervang daarna bij **Custom content**
de oude FireMap-HTML volledig door:

```html
<article class="brand-popup">
  <p class="brand-kicker">{{regio}}</p>
  <h3>{{weergavenaam}}</h3>
  <p class="brand-oppervlakte">{{oppervlakte}}</p>

  <dl class="brand-feiten">
    <div><dt>Statusindicatie</dt><dd>{{statusindicatie}}</dd></div>
    <div><dt>Detecties laatste 24u</dt><dd>{{detecties_24u}}</dd></div>
    <div><dt>Detecties laatste 7d</dt><dd>{{detecties_7d}}</dd></div>
    <div><dt>Brandgevaar</dt><dd>{{brandgevaar}}</dd></div>
    <div><dt>Eerste registratie</dt><dd>{{eerste_registratiedatum}}</dd></div>
  </dl>
</article>

<style>
.brand-popup {
  box-sizing: border-box;
  min-width: 175px;
  max-width: 210px;
}
.brand-popup h3 {
  margin: 2px 0 2px;
  font-size: 16px;
  font-weight: 700;
  line-height: 1.1;
}
.brand-kicker {
  margin: 0;
  color: #555;
  font-size: 8.5px;
  font-weight: 700;
  letter-spacing: .05em;
  text-transform: uppercase;
}
.brand-oppervlakte {
  margin: 0 0 5px;
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
  grid-template-columns: 1fr 1fr;
  gap: 6px;
  padding: 3px 0;
  border-bottom: 1px solid #e6e6e6;
}
.brand-feiten dt,
.brand-feiten dd {
  font-size: 9px;
  line-height: 1.2;
}
.brand-feiten dt {
  color: #666;
}
.brand-feiten dd {
  margin: 0;
  font-weight: 700;
  text-align: right;
}
</style>
```

`statusindicatie`, `detecties_24u`, `detecties_7d` en `brandgevaar` komen uit
FireMap. Als een EFFIS-gebied niet op het bron-id kan worden gekoppeld, tonen ze
`Niet beschikbaar`. `eerste_registratiedatum` komt uit EFFIS en is niet
noodzakelijk de echte ontstaansdatum van de brand.

Voor een FIRMS-marker blijven dezelfde HTML en kolomkoppelingen werken. De
pop-up toont dan `Actieve satellietdetectie`, `Nog niet vastgesteld` als
oppervlakte en `Satellietdetectie, nog niet bevestigd` als status. De
detectieaantallen en eerste registratiedatum komen rechtstreeks uit FIRMS.

Automatisch gekoppelde Live CSV-data is volgens Flourish beschikbaar op
Publisher- en Enterprise-abonnementen. Met een ander abonnement kan de CSV wel
handmatig worden geüpload, maar ververst Flourish de kaart niet automatisch.

## Bron, licentie en waarschuwing

- Viewer en bron: [EFFIS Current Situation Viewer](https://forest-fire.emergency.copernicus.eu/apps/effis.csv/)
- Actieve satellietdetecties: [NASA FIRMS](https://firms.modaps.eosdis.nasa.gov/active_fire/)
- Aanvullende bron: [FireMap.live](https://firemap.live/)
- Technische uitleg: [EFFIS Rapid Damage Assessment](https://forest-fire.emergency.copernicus.eu/about-effis/technical-background/rapid-damage-assessment)
- Licentie: [CC BY 4.0 via de EFFIS-datalicentie](https://forest-fire.emergency.copernicus.eu/about-effis/data-license)
- Voorbeeldontwerp: [VRT NWS – Actieve bosbranden](https://interactief.vrtnws.be/kaart-bosbranden/)

De EFFIS-producten maken geen onderscheid tussen natuurbranden, gecontroleerde
branden en andere verbrande gebieden. De gegevens zijn informatief en niet
bedoeld voor evacuatie-, veiligheids- of operationele beslissingen. Raadpleeg
daarvoor altijd de bevoegde lokale diensten.

## Zelfstandige FireMap-terugval

De eerdere scripts `scripts/update_firemap.R`, `R/firemap_pipeline.R` en de
bestanden `data/flourish_branden.csv` blijven voorlopig bestaan. De dagelijkse
workflow werkt alleen de gecombineerde EFFIS-hoofdexport bij.
