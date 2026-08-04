#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")
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
if (!identical(
  as.integer(metadata$aantal_brandgebieden),
  as.integer(nrow(fires))
)) {
  stop("Het EFFIS-aantal in de metadata klopt niet met de CSV.", call. = FALSE)
}

source_snapshot <- jsonlite::read_json(source_path, simplifyVector = FALSE)
if (!identical(
  as.integer(source_snapshot$aantal_records),
  as.integer(nrow(fires))
)) {
  stop("De EFFIS-bronselectie en CSV tellen niet evenveel rijen.", call. = FALSE)
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

message("EFFIS-outputcontrole geslaagd voor ", nrow(fires), " brandgebieden.")
