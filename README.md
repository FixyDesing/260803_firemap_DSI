# Dagelijkse EFFIS-export voor Flourish

Dit project haalt elke dag de recent bijgewerkte brandgebieden van het
**European Forest Fire Information System (EFFIS)** op. De R-pipeline selecteert
de laatste zeven dagen, zet elke brandperimeter om naar het door EFFIS opgegeven
centroidpunt en maakt een Nederlandstalige CSV voor Flourish.

EFFIS publiceert geen betrouwbare controlestatus. De kleur toont daarom hoe
recent EFFIS een gebied heeft bijgewerkt, niet of een brand onder controle of
uitgedoofd is.

## Datastroom

```text
EFFIS REST-feed met actuele verbrande gebieden
        ↓ ophalen + pagineren + valideren
R/effis_pipeline.R
        ↓
data/flourish_effis_branden.csv
        ↓ publieke raw GitHub-URL
Flourish Live CSV
```

De pijplijn overschrijft de vorige geldige bestanden niet wanneer het ophalen,
inlezen of valideren mislukt. Tijdelijke serverproblemen worden automatisch
opnieuw geprobeerd. De volledige polygonen worden niet dagelijks in GitHub
opgeslagen: `effis_bronselectie.json` bewaart alleen de gebruikte bronvelden en
centroidpunten. Zo blijft de repository beheersbaar.

## Belangrijkste bestanden

| Bestand | Functie |
|---|---|
| `scripts/update_effis.R` | Handmatige en automatische EFFIS-update starten |
| `R/effis_pipeline.R` | EFFIS ophalen, transformeren, valideren en exporteren |
| `data/flourish_effis_branden.csv` | Hoofdtabel voor de Flourish Marker map |
| `data/flourish_effis_actualiteitssamenvatting.csv` | Aantallen en hectaren per actualiteitscategorie |
| `data/effis_bronselectie.json` | Compacte selectie van de gebruikte EFFIS-records |
| `data/effis_metagegevens.json` | Bijwerkdatum, selectieperiode, bron en beperkingen |
| `.github/workflows/update-firemap.yml` | Dagelijkse GitHub Action |

De eerdere FireMap.live-bestanden en code blijven voorlopig ongewijzigd
beschikbaar als referentie en terugvalmogelijkheid.

## Lokaal uitvoeren

R 4.1 of nieuwer is voldoende.

```r
install.packages(c("httr2", "jsonlite"))
source("R/firemap_pipeline.R", encoding = "UTF-8")
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
`EFFIS_PAGE_SIZE` en `EFFIS_REFERENCE_DATE`.

## Dagelijkse GitHub-update

De workflow draait dagelijks om **05.23 UTC**. Dat is **07.23 uur tijdens de
Belgische zomertijd** en **06.23 uur tijdens de wintertijd**. De UTC-planning
vermijdt de tijdzoneconfiguratie die bij de eerste FireMap-planning niet
automatisch startte.

De workflow kan ook handmatig worden gestart via **Actions → EFFIS-gegevens
dagelijks bijwerken → Run workflow**. Hij installeert de R-afhankelijkheden,
voert beide lokale testbestanden uit, haalt EFFIS op, valideert de export en
commit uitsluitend de vier nieuwe EFFIS-databestanden.

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
| Category | `actualiteit` **(gewijzigd; vroeger `status`)** |
| Color | `markerkleur` |
| Size | `markergrootte` |
| Info for popups | `landnaam`, `provincie`, `oppervlakte`, `eerste_registratie`, `laatste_update`, `registratieperiode`, `bron`, `bron_url` |

De kleuren betekenen voortaan:

- Vandaag bijgewerkt: `#AA3228`
- Afgelopen 3 dagen bijgewerkt: `#E07154`
- 4–7 dagen geleden bijgewerkt: `#FCD9BE`
- Actualiteit onbekend: `#808080`

`markergrootte` zet de EFFIS-oppervlakte logaritmisch om naar een waarde van
0,1 tot en met 3. Daardoor blijven grote verschillen zichtbaar zonder dat de
grootste gebieden de kaart volledig bedekken. Voeg als bronregel toe:
**Data: EFFIS – Copernicus Emergency Management Service; bewerking: DSI**.

### Nieuwe aangepaste pop-up

Bind eerst de hierboven vermelde kolommen. Vervang daarna bij **Custom content**
de oude FireMap-HTML volledig door:

```html
<article class="brand-popup">
  <p class="brand-kicker">{{landnaam}} · {{actualiteit}}</p>
  <h3>{{weergavenaam}}</h3>
  <p class="brand-update">{{provincie}}</p>

  <p class="brand-oppervlakte">{{oppervlakte}}</p>

  <dl class="brand-feiten">
    <div><dt>Eerste registratie</dt><dd>{{eerste_registratie}}</dd></div>
    <div><dt>Laatste update</dt><dd>{{laatste_update}}</dd></div>
  </dl>

  <p class="brand-noot">Kaartregistraties; geen officiële controlestatus.</p>
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
  margin: 2px 0 2px;
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
  letter-spacing: .05em;
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
  grid-template-columns: .8fr 1.2fr;
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
.brand-noot {
  margin: 5px 0 0;
  color: #777;
  font-size: 8.5px;
  line-height: 1.2;
}
.brand-bron {
  margin: 4px 0 0;
  font-size: 8.5px;
}
.brand-bron a {
  color: #666;
  text-decoration: underline;
}
</style>
```

De kolommen `ontstaansdatum`, `duur`, `status_bijgewerkt` en `brandgevaar` uit
de oude FireMap-export worden niet meer gebruikt. EFFIS waarschuwt dat de
gerapporteerde eerste registratie en laatste update niet noodzakelijk het echte
moment van ontstaan of uitdoven zijn. Daarom noemt de pop-up ze expliciet
kaartregistraties.

Automatisch gekoppelde Live CSV-data is volgens Flourish beschikbaar op
Publisher- en Enterprise-abonnementen. Met een ander abonnement kan de CSV wel
handmatig worden geüpload, maar ververst Flourish de kaart niet automatisch.

## Bron, licentie en waarschuwing

- Viewer en bron: [EFFIS Current Situation Viewer](https://forest-fire.emergency.copernicus.eu/apps/effis.csv/)
- Technische uitleg: [EFFIS Rapid Damage Assessment](https://forest-fire.emergency.copernicus.eu/about-effis/technical-background/rapid-damage-assessment)
- Licentie: [CC BY 4.0 via de EFFIS-datalicentie](https://forest-fire.emergency.copernicus.eu/about-effis/data-license)
- Voorbeeldontwerp: [VRT NWS – Actieve bosbranden](https://interactief.vrtnws.be/kaart-bosbranden/)

De EFFIS-producten maken geen onderscheid tussen natuurbranden, gecontroleerde
branden en andere verbrande gebieden. De gegevens zijn informatief en niet
bedoeld voor evacuatie-, veiligheids- of operationele beslissingen. Raadpleeg
daarvoor altijd de bevoegde lokale diensten.

## Tijdelijke FireMap-terugval

De eerdere scripts `scripts/update_firemap.R`, `R/firemap_pipeline.R` en de
bestanden `data/flourish_branden.csv` blijven voorlopig bestaan. Ze worden niet
meer door de dagelijkse workflow bijgewerkt zodra de EFFIS-versie is
samengevoegd.
