#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")

fixture_path <- file.path("tests", "fixtures", "firemap_sample.geojson")
fixture <- readBin(fixture_path, what = "raw", n = file.info(fixture_path)$size)
data <- parse_firemap_geojson(
  fixture,
  retrieved_at = as.POSIXct("2026-08-03 07:00:00", tz = "UTC")
)

stopifnot(nrow(data) == 4L)
stopifnot(identical(data$status_nl, c(
  "Niet onder controle", "Onder controle", "Uitgedoofd", "Onbekend"
)))
stopifnot(identical(data$marker_color, c(
  "#AA3228", "#E07154", "#FCD9BE", "#808080"
)))
stopifnot(identical(data$country_code[1:3], c("BE", "FR", "PT")))
stopifnot(identical(data$source_id[1:3], c("BE-1", "FR-2", "PT-3")))
stopifnot(identical(data$location_name[[1L]], "Brussel"))
stopifnot(identical(data$display_name[[1L]], "Brussel"))
stopifnot(identical(data$display_name[[4L]], "Bosbrand"))
stopifnot(is.na(parse_fire_name("EL • 2026-08-02")$location_name))
stopifnot(identical(data$fire_weather_index[[1L]], "Very High"))
stopifnot(identical(data$detections_24h[[1L]], 4))
stopifnot(identical(data$detections_7d[[1L]], 17))
stopifnot(isTRUE(all.equal(data$size_ha[[1L]], 12.5)))
stopifnot(isTRUE(all.equal(data$marker_size[[1L]], 0.9)))
stopifnot(identical(data$marker_size[[3L]], 0.66))
stopifnot(identical(calculate_marker_size(1000000), 3))
stopifnot(identical(calculate_marker_size(NA_real_), 0.66))
stopifnot(all(data$marker_size >= 0.1 & data$marker_size <= 3))
stopifnot(identical(data$retrieved_at_utc[[1L]], "2026-08-03T07:00:00Z"))
stopifnot(identical(source_last_updated(data), "2026-08-03T06:05:00Z"))
validate_fire_data(data, min_rows = 4L)

temporary_output <- tempfile("firemap-test-")
dir.create(temporary_output)
on.exit(unlink(temporary_output, recursive = TRUE, force = TRUE), add = TRUE)
write_firemap_outputs(data, fixture, temporary_output, FIREMAP_DEFAULT_URL)
stopifnot(all(file.exists(file.path(
  temporary_output,
  c(
    "flourish_branden.csv",
    "flourish_statussamenvatting.csv",
    "firemap_bron.geojson",
    "firemap_metagegevens.json"
  )
))))

export <- utils::read.csv(
  file.path(temporary_output, "flourish_branden.csv"),
  stringsAsFactors = FALSE,
  check.names = FALSE,
  fileEncoding = "UTF-8"
)
validate_flourish_export(export, min_rows = 4L)
stopifnot(identical(export$actief, c("Ja", "Ja", "Nee", "Onbekend")))
stopifnot(identical(export$status, data$status_nl))
stopifnot(identical(export$brandgevaar[[1L]], "Zeer hoog"))
stopifnot(identical(
  export$landnaam,
  c("België", "Frankrijk", "Portugal", "Onbekend land")
))
stopifnot(identical(export$oppervlakte[[1L]], "12,5 hectare"))
stopifnot(identical(export$oppervlakte[[3L]], "Niet beschikbaar"))
stopifnot(identical(export$ontstaansdatum[[1L]], "2 augustus 2026"))
stopifnot(identical(export$duur[[1L]], "1 dag"))
stopifnot(identical(
  export$status_bijgewerkt[[1L]],
  "3 augustus 2026 om 08:00"
))
stopifnot(identical(format_area_nl(1234.5), "1.234,5 hectare"))

message("Alle lokale pipelinetests zijn geslaagd.")
