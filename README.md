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

Kies een punten- of markermap en koppel minimaal:

| Flourish-instelling | CSV-kolom |
|---|---|
| Breedtegraad | `breedtegraad` |
| Lengtegraad | `lengtegraad` |
| Naam/label | `weergavenaam` |
| Categorie/kleur | `status` |
| Grootte | `markergrootte` |
| Informatievenster | `oppervlakte_ha`, `ontstaansdatum`, `duur_dagen`, `brandgevaar` |

Gebruik voor een VRT-achtige weergave deze vaste kleuren:

- Niet onder controle: `#FF7882`
- Onder controle: `#F5A623`
- Uitgedoofd: `#7766ED`
- Onbekend: `#808080`

`markergrootte` gebruikt het aantal hectare en valt bij een ontbrekende oppervlakte
terug op `1`, zodat ieder punt zichtbaar blijft. Stel de beginuitsnede in
Flourish in op Europa. Voeg als bronregel toe:
**Data: FireMap.live (EFFIS en NASA FIRMS)**.

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
