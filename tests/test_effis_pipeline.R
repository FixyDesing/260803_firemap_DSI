#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")
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
stopifnot(identical(calculate_marker_size(NA_real_), 0.4))

export <- build_effis_flourish_export(data)
validate_effis_flourish_export(export, min_rows = 4L)
stopifnot(identical(export$actualiteit, data$actuality_nl))
stopifnot(all(export$gegevenstype == "EFFIS-brandgebied"))
stopifnot(all(export$firms_hotspot == "Nee"))
stopifnot(!any(grepl("Satellietdetectie", export$actualiteit)))
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
stopifnot(is.null(written_metadata$firms_hotspots))
stopifnot(identical(
  as.integer(written_metadata$firemap_verrijking$aantal_gekoppeld_op_effis_id),
  3L
))

message("Alle lokale EFFIS-pipelinetests zijn geslaagd.")
