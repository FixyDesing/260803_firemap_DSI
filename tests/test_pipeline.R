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
stopifnot(identical(data$location_name[[1L]], "Brussel"))
stopifnot(identical(data$fire_weather_index[[1L]], "Very High"))
stopifnot(isTRUE(all.equal(data$size_ha[[1L]], 12.5)))
stopifnot(isTRUE(all.equal(data$marker_size[[1L]], 4.19)))
stopifnot(identical(data$marker_size[[3L]], 2))
stopifnot(identical(calculate_marker_size(1000000), 10))
stopifnot(all(data$marker_size >= 2 & data$marker_size <= 10))
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

message("Alle lokale pipelinetests zijn geslaagd.")
