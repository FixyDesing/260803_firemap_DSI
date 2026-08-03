#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")

output_dir <- Sys.getenv("FIREMAP_OUTPUT_DIR", unset = "data")
fires_path <- file.path(output_dir, "flourish_branden.csv")
summary_path <- file.path(output_dir, "flourish_statussamenvatting.csv")
raw_path <- file.path(output_dir, "firemap_bron.geojson")
metadata_path <- file.path(output_dir, "firemap_metagegevens.json")
required_files <- c(fires_path, summary_path, raw_path, metadata_path)

if (any(!file.exists(required_files))) {
  stop(
    "Ontbrekende output: ",
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
validate_flourish_export(fires, min_rows = env_number("FIREMAP_MIN_ROWS", 1))

raw_geojson <- readBin(raw_path, what = "raw", n = file.info(raw_path)$size)
raw_rows <- parse_firemap_geojson(raw_geojson, retrieved_at = Sys.time())
if (nrow(raw_rows) != nrow(fires)) {
  stop("CSV en GeoJSON bevatten niet evenveel punten.", call. = FALSE)
}

metadata <- jsonlite::read_json(metadata_path, simplifyVector = TRUE)
if (!identical(
  as.integer(metadata$aantal_brandpunten),
  as.integer(nrow(fires))
)) {
  stop("Het aantal punten in de metadata klopt niet met de CSV.", call. = FALSE)
}

summary <- utils::read.csv(
  summary_path,
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8"
)
if (sum(summary$aantal) != nrow(fires)) {
  stop("De statussamenvatting telt niet op tot het totale aantal punten.", call. = FALSE)
}

message("Outputcontrole geslaagd voor ", nrow(fires), " brandpunten.")
