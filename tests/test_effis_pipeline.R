#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")
source(file.path("R", "firms_pipeline.R"), encoding = "UTF-8")
source(file.path("R", "effis_pipeline.R"), encoding = "UTF-8")

fixture <- jsonlite::read_json(
  file.path("tests", "fixtures", "effis_sample.json"),
  simplifyVector = FALSE
)
retrieved_at <- as.POSIXct("2026-08-04 06:30:00", tz = "UTC")
reference_date <- as.Date("2026-08-04")
data <- parse_effis_records(
  fixture$results,
  retrieved_at = retrieved_at,
  reference_date = reference_date
)

stopifnot(nrow(data) == 4L)
stopifnot(identical(data$id, paste0("effis-ba-", 1001:1004)))
stopifnot(identical(data$actuality_nl, c(
  "Vandaag bijgewerkt",
  "Afgelopen 3 dagen bijgewerkt",
  "4–7 dagen geleden bijgewerkt",
  "Actualiteit onbekend"
)))
stopifnot(identical(data$marker_color, c(
  "#AA3228", "#E07154", "#FCD9BE", "#808080"
)))
stopifnot(identical(data$display_name, c(
  "Canedo, Vale e Vila Maior",
  "Var",
  "Navas del Rey",
  "Verbrand gebied in Testland"
)))
stopifnot(identical(data$country_name, c(
  "Portugal", "Frankrijk", "Spanje", "Testland"
)))
stopifnot(isTRUE(all.equal(data$size_ha[[1L]], 12.5)))
stopifnot(isTRUE(all.equal(data$marker_size[[1L]], 0.9)))
stopifnot(identical(data$marker_size[[3L]], 0.1))
stopifnot(all(data$data_type == "effis_brandgebied"))
stopifnot(identical(data$first_registration_utc[[1L]], "2026-08-01T12:25:00Z"))
stopifnot(identical(data$last_update_utc[[1L]], "2026-08-04T04:15:00Z"))
stopifnot(identical(data$days_since_update, c(0, 2, 5, NA_real_)))
stopifnot(identical(data$registration_days[1:3], c(2, 1, 1)))
stopifnot(identical(
  effis_actuality_details(8)$label,
  "Actualiteit onbekend"
))
validate_effis_data(data, min_rows = 4L)

firemap_fixture_path <- file.path("tests", "fixtures", "firemap_sample.geojson")
firemap_fixture <- readBin(
  firemap_fixture_path,
  what = "raw",
  n = file.info(firemap_fixture_path)$size
)
firemap_data <- parse_firemap_geojson(
  firemap_fixture,
  retrieved_at = retrieved_at
)
firemap_data$source_id <- c("1001", "1002", "1003", NA_character_)
data <- enrich_effis_with_firemap(data, firemap_data)
stopifnot(identical(data$firemap_available, c(TRUE, TRUE, TRUE, FALSE)))
stopifnot(identical(data$firemap_status_nl[1:3], c(
  "Niet onder controle", "Onder controle", "Uitgedoofd"
)))
stopifnot(identical(data$firemap_detections_24h[[1L]], 4))
stopifnot(identical(data$firemap_detections_7d[[1L]], 17))
stopifnot(identical(data$firemap_fire_weather_nl[[1L]], "Zeer hoog"))
disabled_enrichment <- download_firemap_enrichment(source_url = "")
stopifnot(!disabled_enrichment$succeeded)
stopifnot(is.null(disabled_enrichment$data))

firms_fixture <- paste(
  readLines(file.path("tests", "fixtures", "firms_sample.csv"), encoding = "UTF-8"),
  collapse = "\n"
)
firms_data <- read_firms_csv(firms_fixture, "VIIRS_NOAA21_NRT")
firms_data <- filter_firms_detections(
  firms_data,
  as.Date("2026-07-29"),
  reference_date
)
stopifnot(nrow(firms_data) == 4L)
stopifnot(identical(calculate_marker_size(NA_real_), 0.66))
stopifnot(identical(FIRMS_DEFAULT_SOURCES, c(
  "VIIRS_NOAA21_NRT", "VIIRS_NOAA20_NRT"
)))
mock_firms_download <- function(
  map_key,
  source,
  area,
  from_date,
  days,
  timeout_seconds,
  max_tries
) {
  if (identical(source, "TIJDELIJK_NIET_BESCHIKBAAR")) {
    stop("Gesimuleerde bronstoring.", call. = FALSE)
  }
  read_firms_csv(firms_fixture, source)
}
partial_firms <- download_firms_hotspots(
  map_key = "testkeyzonderproductiewaarde",
  reference_date = reference_date,
  window_days = 7L,
  sources = c("TIJDELIJK_NIET_BESCHIKBAAR", "VIIRS_NOAA21_NRT"),
  timeout_seconds = 1,
  max_tries = 1L,
  retrieved_at = retrieved_at,
  download_function = mock_firms_download
)
stopifnot(partial_firms$succeeded)
stopifnot(identical(partial_firms$successful_sources, "VIIRS_NOAA21_NRT"))
stopifnot(identical(
  partial_firms$failed_sources,
  "TIJDELIJK_NIET_BESCHIKBAAR"
))
stopifnot(length(partial_firms$warnings) == 1L)
stopifnot(nrow(partial_firms$data) == 4L)
all_failed_message <- tryCatch(
  {
    download_firms_hotspots(
      map_key = "testkeyzonderproductiewaarde",
      reference_date = reference_date,
      sources = "TIJDELIJK_NIET_BESCHIKBAAR",
      timeout_seconds = 1,
      max_tries = 1L,
      download_function = mock_firms_download
    )
    NA_character_
  },
  error = function(error) conditionMessage(error)
)
stopifnot(grepl("Geen enkele ingestelde FIRMS-sensorbron", all_failed_message))
firms_clusters <- cluster_firms_detections(
  firms_data,
  retrieved_at = retrieved_at,
  recent_hours = 48,
  grid_degrees = 0.1
)
stopifnot(nrow(firms_clusters) == 2L)
netherlands_cluster <- firms_clusters[firms_clusters$country_code == "NL", ]
stopifnot(nrow(netherlands_cluster) == 1L)
stopifnot(identical(netherlands_cluster$country_name, "Nederland"))
stopifnot(identical(netherlands_cluster$detections_24h, 3L))
stopifnot(identical(netherlands_cluster$detections_7d, 3L))
stopifnot(identical(netherlands_cluster$detection_days_7d, 2L))
static_example <- netherlands_cluster
static_example$detections_7d <- 20L
static_example$detection_days_7d <- 4L
stopifnot(nrow(remove_likely_static_firms_clusters(static_example)) == 0L)
firms_clusters <- remove_firms_clusters_near_effis(firms_clusters, data)
stopifnot(nrow(firms_clusters) == 1L)
stopifnot(identical(firms_clusters$country_code, "NL"))
firms_rows <- firms_clusters_to_rows(firms_clusters, format_utc(retrieved_at))
stopifnot(identical(firms_rows$marker_color, "#F7CF8E"))
stopifnot(identical(firms_rows$marker_size, 0.66))
combined_data <- rbind(data, firms_rows)
validate_effis_data(combined_data, min_rows = 5L)
combined_summary <- build_effis_actuality_summary(combined_data)
stopifnot(all(
  combined_summary$markerkleur[
    grepl("^Satellietdetectie", combined_summary$actualiteit)
  ] == "#F7CF8E"
))
combined_export <- build_effis_flourish_export(combined_data)
validate_effis_flourish_export(combined_export, min_rows = 5L)
hotspot_export <- combined_export[combined_export$firms_hotspot == "Ja", ]
stopifnot(nrow(hotspot_export) == 1L)
stopifnot(identical(hotspot_export$regio, "Nederland"))
stopifnot(identical(hotspot_export$oppervlakte, "Nog niet vastgesteld"))
stopifnot(identical(
  hotspot_export$statusindicatie,
  "Satellietdetectie, nog niet bevestigd"
))
stopifnot(identical(hotspot_export$markerkleur, "#F7CF8E"))
stopifnot(identical(hotspot_export$markergrootte, 0.66))
stopifnot(identical(hotspot_export$detecties_24u, "3"))
stopifnot(identical(hotspot_export$eerste_registratiedatum, "3 augustus 2026"))

age_boundary_data <- firms_data[rep(1L, 2L), , drop = FALSE]
age_boundary_data$latitude <- c(52.0, 52.2)
age_boundary_data$longitude <- c(5.0, 5.2)
age_boundary_data$acquired_at <- c(
  retrieved_at - 48 * 3600,
  retrieved_at - 48 * 3600 - 1
)
age_boundary_clusters <- cluster_firms_detections(
  age_boundary_data,
  retrieved_at = retrieved_at,
  recent_hours = 48,
  grid_degrees = 0.1
)
stopifnot(nrow(age_boundary_clusters) == 1L)
stopifnot(identical(
  age_boundary_clusters$last_detection_utc,
  format_utc(retrieved_at - 48 * 3600)
))

export <- build_effis_flourish_export(data)
validate_effis_flourish_export(export, min_rows = 4L)
stopifnot(identical(export$actualiteit, data$actuality_nl))
stopifnot(all(export$gegevenstype == "EFFIS-brandgebied"))
stopifnot(identical(export$oppervlakte[[1L]], "12,5 hectare"))
stopifnot(identical(
  export$regio[[1L]],
  "Portugal, Área Metropolitana do Porto"
))
stopifnot(identical(export$eerste_registratie[[1L]], "1 augustus 2026 om 14:25"))
stopifnot(identical(export$eerste_registratiedatum[[1L]], "1 augustus 2026"))
stopifnot(identical(export$laatste_update[[1L]], "4 augustus 2026 om 06:15"))
stopifnot(identical(export$registratieperiode[[1L]], "2 dagen tussen registraties"))
stopifnot(identical(export$statusindicatie[[1L]], "Niet onder controle"))
stopifnot(identical(export$detecties_24u[[1L]], "4"))
stopifnot(identical(export$detecties_7d[[1L]], "17"))
stopifnot(identical(export$brandgevaar[[1L]], "Zeer hoog"))
stopifnot(identical(export$statusindicatie[[4L]], "Niet beschikbaar"))

download <- list(
  results = fixture$results,
  count = fixture$count,
  from_date = as.Date("2026-07-29"),
  to_date = reference_date,
  query_url = build_effis_query_url(
    EFFIS_DEFAULT_URL,
    as.Date("2026-07-29"),
    reference_date,
    1000L
  )
)
download$firemap_enrichment <- list(
  succeeded = TRUE,
  record_count = nrow(firemap_data),
  source_url = FIREMAP_DEFAULT_URL,
  error = NA_character_
)
download$firms_hotspots <- list(
  succeeded = TRUE,
  record_count = 0L,
  cluster_count_before_deduplication = 0L,
  cluster_count = 0L,
  area = FIRMS_DEFAULT_AREA,
  sources = FIRMS_DEFAULT_SOURCES,
  query_descriptions = character(),
  error = NA_character_
)
temporary_output <- tempfile("effis-test-")
dir.create(temporary_output)
on.exit(unlink(temporary_output, recursive = TRUE, force = TRUE), add = TRUE)
write_effis_outputs(data, download, temporary_output)
expected_files <- c(
  "flourish_effis_branden.csv",
  "flourish_effis_actualiteitssamenvatting.csv",
  "effis_bronselectie.json",
  "effis_metagegevens.json"
)
stopifnot(all(file.exists(file.path(temporary_output, expected_files))))

written_export <- utils::read.csv(
  file.path(temporary_output, "flourish_effis_branden.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8"
)
validate_effis_flourish_export(written_export, min_rows = 4L)
written_metadata <- jsonlite::read_json(
  file.path(temporary_output, "effis_metagegevens.json"),
  simplifyVector = TRUE
)
stopifnot(identical(as.integer(written_metadata$aantal_brandgebieden), 4L))
stopifnot(identical(written_metadata$venster_vanaf, "2026-07-29"))
stopifnot(identical(as.integer(written_metadata$aantal_markers), 4L))
stopifnot(identical(
  as.integer(written_metadata$firemap_verrijking$aantal_gekoppeld_op_effis_id),
  3L
))

message("Alle lokale EFFIS-pipelinetests zijn geslaagd.")
