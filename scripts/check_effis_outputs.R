#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")
source(file.path("R", "firms_pipeline.R"), encoding = "UTF-8")
source(file.path("R", "effis_pipeline.R"), encoding = "UTF-8")

output_dir <- Sys.getenv("EFFIS_OUTPUT_DIR", unset = "data")
fires_path <- file.path(output_dir, "flourish_effis_branden.csv")
summary_path <- file.path(
  output_dir,
  "flourish_effis_actualiteitssamenvatting.csv"
)
source_path <- file.path(output_dir, "effis_bronselectie.json")
metadata_path <- file.path(output_dir, "effis_metagegevens.json")
required_files <- c(fires_path, summary_path, source_path, metadata_path)

if (any(!file.exists(required_files))) {
  stop(
    "Ontbrekende EFFIS-output: ",
    paste(required_files[!file.exists(required_files)], collapse = ", "),
    call. = FALSE
  )
}

fires <- utils::read.csv(
  fires_path,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8"
)
validate_effis_flourish_export(
  fires,
  min_rows = env_number("EFFIS_MIN_ROWS", 10)
)

metadata <- jsonlite::read_json(metadata_path, simplifyVector = TRUE)
if (!identical(as.integer(metadata$aantal_markers), as.integer(nrow(fires)))) {
  stop("Het aantal markers in de metadata klopt niet met de CSV.", call. = FALSE)
}

source_snapshot <- jsonlite::read_json(source_path, simplifyVector = FALSE)
effis_rows <- fires$gegevenstype == "EFFIS-brandgebied"
firms_rows <- fires$gegevenstype == "Actieve satellietdetectie"
if (!identical(as.integer(source_snapshot$aantal_records), sum(effis_rows))) {
  stop("De EFFIS-bronselectie en CSV tellen niet evenveel gebieden.", call. = FALSE)
}
if (!identical(as.integer(metadata$aantal_brandgebieden), sum(effis_rows)) ||
    !identical(as.integer(metadata$aantal_firms_hotspotclusters), sum(firms_rows))) {
  stop("De aantallen per gegevenstype kloppen niet.", call. = FALSE)
}

summary <- utils::read.csv(
  summary_path,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8"
)
if (sum(summary$aantal) != nrow(fires)) {
  stop(
    "De EFFIS-actualiteitssamenvatting telt niet op tot het totaal.",
    call. = FALSE
  )
}
if (!identical(unique(fires$opgehaald_utc), metadata$opgehaald_utc)) {
  stop("De ophaaltijd verschilt tussen de EFFIS-bestanden.", call. = FALSE)
}
if (any(!fires$firemap_beschikbaar %in% c("Ja", "Nee"))) {
  stop("Ongeldige FireMap-beschikbaarheidswaarde in de CSV.", call. = FALSE)
}
linked_count <- sum(fires$firemap_beschikbaar == "Ja")
if (!identical(
  as.integer(metadata$firemap_verrijking$aantal_gekoppeld_op_effis_id),
  as.integer(linked_count)
)) {
  stop("Het aantal FireMap-koppelingen klopt niet met de metadata.", call. = FALSE)
}
if (any(!nzchar(fires$regio)) || any(!nzchar(fires$statusindicatie))) {
  stop("Minstens één tooltipveld is leeg.", call. = FALSE)
}

message(
  "Uitvoercontrole geslaagd voor ", sum(effis_rows),
  " EFFIS-brandgebieden en ", sum(firms_rows),
  " FIRMS-hotspotclusters; ", linked_count, " gekoppeld aan FireMap."
)
