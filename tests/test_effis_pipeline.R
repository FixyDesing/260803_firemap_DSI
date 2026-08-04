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
stopifnot(identical(data$first_registration_utc[[1L]], "2026-08-01T12:25:00Z"))
stopifnot(identical(data$last_update_utc[[1L]], "2026-08-04T04:15:00Z"))
stopifnot(identical(data$days_since_update, c(0, 2, 5, NA_real_)))
stopifnot(identical(data$registration_days[1:3], c(2, 1, 1)))
stopifnot(identical(
  effis_actuality_details(8)$label,
  "Actualiteit onbekend"
))
validate_effis_data(data, min_rows = 4L)

export <- build_effis_flourish_export(data)
validate_effis_flourish_export(export, min_rows = 4L)
stopifnot(identical(export$actualiteit, data$actuality_nl))
stopifnot(identical(export$oppervlakte[[1L]], "12,5 hectare"))
stopifnot(identical(export$eerste_registratie[[1L]], "1 augustus 2026 om 14:25"))
stopifnot(identical(export$laatste_update[[1L]], "4 augustus 2026 om 06:15"))
stopifnot(identical(export$registratieperiode[[1L]], "2 dagen tussen registraties"))

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

message("Alle lokale EFFIS-pipelinetests zijn geslaagd.")
