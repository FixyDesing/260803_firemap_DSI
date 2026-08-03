# FireMap.live -> Flourish pipeline ------------------------------------------

FIREMAP_DEFAULT_URL <- paste0(
  "https://geo.firemap.live/geoserver/ows",
  "?service=WFS&version=1.0.0&request=GetFeature",
  "&typeName=FireDB%3Amodis_ba_pt_7day",
  "&outputFormat=application%2Fjson"
)

FIREMAP_SOURCE_PAGE <- "https://firemap.live/"
FIREMAP_DATA_LICENSE <- "https://creativecommons.org/licenses/by/4.0/"

DUTCH_MONTHS <- c(
  "januari", "februari", "maart", "april", "mei", "juni",
  "juli", "augustus", "september", "oktober", "november", "december"
)

COUNTRY_NAMES_NL <- c(
  AL = "Albanië", BA = "Bosnië en Herzegovina", BE = "België",
  BG = "Bulgarije", CH = "Zwitserland", CY = "Cyprus", DE = "Duitsland",
  DZ = "Algerije", EL = "Griekenland", ES = "Spanje", FR = "Frankrijk",
  HR = "Kroatië", HU = "Hongarije", IE = "Ierland", IL = "Israël",
  IT = "Italië", JO = "Jordanië", LB = "Libanon", MA = "Marokko",
  ME = "Montenegro", MK = "Noord-Macedonië", NO = "Noorwegen",
  PT = "Portugal", RO = "Roemenië", RS = "Servië", SE = "Zweden",
  SI = "Slovenië", SK = "Slowakije", SY = "Syrië", TN = "Tunesië",
  TR = "Turkije", UA = "Oekraïne", UK = "Verenigd Koninkrijk"
)

env_number <- function(name, default) {
  value <- Sys.getenv(name, unset = "")
  if (!nzchar(value)) {
    return(default)
  }

  parsed <- suppressWarnings(as.numeric(value))
  if (!is.finite(parsed)) {
    stop(name, " moet een eindig getal zijn.", call. = FALSE)
  }
  parsed
}

as_scalar_character <- function(value) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1L]])) {
    return(NA_character_)
  }

  value <- trimws(as.character(value[[1L]]))
  if (!nzchar(value) || value %in% c("NA", "null")) {
    return(NA_character_)
  }
  value
}

as_scalar_numeric <- function(value) {
  value <- as_scalar_character(value)
  if (is.na(value)) {
    return(NA_real_)
  }
  suppressWarnings(as.numeric(value))
}

format_utc <- function(value = Sys.time()) {
  format(as.POSIXct(value, tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

country_name_nl <- function(country_code) {
  country_code <- as_scalar_character(country_code)
  if (is.na(country_code)) {
    return("Onbekend land")
  }

  translated <- unname(COUNTRY_NAMES_NL[country_code])
  if (is.na(translated)) country_code else translated
}

format_date_nl <- function(value) {
  value <- as_scalar_character(value)
  if (is.na(value)) {
    return("Niet beschikbaar")
  }

  parsed <- suppressWarnings(as.Date(value, format = "%Y-%m-%d"))
  if (is.na(parsed)) {
    return("Niet beschikbaar")
  }

  paste(
    as.integer(format(parsed, "%d")),
    DUTCH_MONTHS[[as.integer(format(parsed, "%m"))]],
    format(parsed, "%Y")
  )
}

format_datetime_nl <- function(value, timezone = "Europe/Brussels") {
  value <- as_scalar_character(value)
  if (is.na(value)) {
    return("Niet beschikbaar")
  }

  parsed <- suppressWarnings(as.POSIXct(
    value,
    format = "%Y-%m-%dT%H:%M:%OSZ",
    tz = "UTC"
  ))
  if (is.na(parsed)) {
    return("Niet beschikbaar")
  }

  local <- as.POSIXlt(parsed, tz = timezone)
  sprintf(
    "%d %s %d om %02d:%02d",
    local$mday,
    DUTCH_MONTHS[[local$mon + 1L]],
    local$year + 1900L,
    local$hour,
    local$min
  )
}

format_area_nl <- function(size_ha) {
  if (!is.finite(size_ha) || size_ha < 0) {
    return("Niet beschikbaar")
  }

  digits <- if (abs(size_ha - round(size_ha)) < 1e-9) 0L else 1L
  paste0(
    formatC(
      size_ha,
      format = "f",
      digits = digits,
      big.mark = ".",
      decimal.mark = ","
    ),
    " hectare"
  )
}

format_duration_nl <- function(duration_days) {
  if (!is.finite(duration_days) || duration_days < 0) {
    return("Niet beschikbaar")
  }
  if (duration_days == 0) {
    return("Minder dan één dag")
  }
  if (duration_days == 1) {
    return("1 dag")
  }
  paste0(round(duration_days), " dagen")
}

status_explanation_nl <- function(status) {
  switch(
    status,
    "Niet onder controle" = paste(
      "Volgens de laatste beschikbare bronupdate was deze brand nog niet",
      "onder controle."
    ),
    "Onder controle" = paste(
      "Volgens de laatste beschikbare bronupdate stond deze brand onder",
      "controle."
    ),
    "Uitgedoofd" = paste(
      "Volgens de laatste beschikbare bronupdate was deze brand uitgedoofd."
    ),
    "De actuele status van deze brand is niet beschikbaar."
  )
}

status_details <- function(status) {
  status <- as_scalar_character(status)

  if (is.na(status)) {
    return(list(
      label = "Onbekend",
      color = "#808080",
      order = 4L,
      active = NA
    ))
  }

  if (status %in% c("Out of Control", "Fire of Note")) {
    return(list(
      label = "Niet onder controle",
      color = "#AA3228",
      order = 1L,
      active = TRUE
    ))
  }

  if (status %in% c("Being Held", "Under Control")) {
    return(list(
      label = "Onder controle",
      color = "#E07154",
      order = 2L,
      active = TRUE
    ))
  }

  if (identical(status, "Out")) {
    return(list(
      label = "Uitgedoofd",
      color = "#FCD9BE",
      order = 3L,
      active = FALSE
    ))
  }

  list(
    label = "Onbekend",
    color = "#808080",
    order = 4L,
    active = NA
  )
}

calculate_marker_size <- function(size_ha) {
  if (!is.finite(size_ha) || size_ha <= 0) {
    return(0.1)
  }

  # Een logaritmische schaal houdt zeer grote branden zichtbaar zonder dat
  # hun markeringen de kaart bedekken: 1 ha = 0,1 en 10.000 ha = 2.
  round(min(2, max(0.1, 0.1 + 0.475 * log10(size_ha))), 2)
}

parse_fire_name <- function(fire_name) {
  fire_name <- as_scalar_character(fire_name)
  if (is.na(fire_name)) {
    return(list(country_code = NA_character_, location_name = NA_character_))
  }

  parts <- trimws(strsplit(fire_name, "\u2022", fixed = TRUE)[[1L]])
  country_code <- if (
    length(parts) >= 1L && grepl("^[A-Z]{2}$", parts[[1L]])
  ) {
    parts[[1L]]
  } else {
    NA_character_
  }

  location_candidate <- if (length(parts) >= 2L) parts[[2L]] else fire_name
  location_name <- if (
    grepl("^\\d{4}-\\d{2}-\\d{2}$", location_candidate)
  ) {
    NA_character_
  } else {
    location_candidate
  }
  list(country_code = country_code, location_name = location_name)
}

feature_to_row <- function(feature, row_number, retrieved_at_utc) {
  geometry <- feature$geometry
  if (is.null(geometry) || !identical(geometry$type, "Point")) {
    stop("Feature ", row_number, " heeft geen Point-geometrie.", call. = FALSE)
  }

  coordinates <- unlist(geometry$coordinates, use.names = FALSE)
  if (length(coordinates) < 2L) {
    stop("Feature ", row_number, " heeft geen geldige coördinaten.", call. = FALSE)
  }

  longitude <- suppressWarnings(as.numeric(coordinates[[1L]]))
  latitude <- suppressWarnings(as.numeric(coordinates[[2L]]))
  properties <- feature$properties
  if (is.null(properties)) {
    properties <- list()
  }

  source_id <- as_scalar_character(properties$fire_id_source)
  feature_id <- as_scalar_character(feature$id)
  id <- if (!is.na(source_id)) source_id else feature_id
  if (is.na(id)) {
    id <- sprintf("point-%.5f-%.5f", longitude, latitude)
  }

  original_status <- as_scalar_character(properties$fire_status)
  status <- status_details(original_status)
  fire_name <- as_scalar_character(properties$fire_name)
  name_parts <- parse_fire_name(fire_name)
  size_ha <- as_scalar_numeric(properties$size_ha)
  duration_days <- as_scalar_numeric(properties$duration_days)
  detections_24h <- as_scalar_numeric(properties$active24hr)
  detections_7d <- as_scalar_numeric(properties$active7d)
  last_update_hours <- as_scalar_numeric(properties$lastupdate_hours)
  ignition_date <- as_scalar_character(properties$ignition_date)
  source_updated_at <- as_scalar_character(properties$datetimenow)
  fire_weather_index <- as_scalar_character(properties$fwi_daily)

  display_name <- if (!is.na(name_parts$location_name)) {
    name_parts$location_name
  } else if (!is.na(name_parts$country_code)) {
    paste("Bosbrand in", country_name_nl(name_parts$country_code))
  } else {
    "Bosbrand"
  }

  data.frame(
    id = id,
    latitude = latitude,
    longitude = longitude,
    display_name = display_name,
    location_name = name_parts$location_name,
    country_code = name_parts$country_code,
    status_nl = status$label,
    status_original = original_status,
    status_order = status$order,
    marker_color = status$color,
    is_active = status$active,
    size_ha = size_ha,
    marker_size = calculate_marker_size(size_ha),
    ignition_date = ignition_date,
    duration_days = duration_days,
    detections_24h = detections_24h,
    detections_7d = detections_7d,
    last_update_hours = last_update_hours,
    fire_weather_index = fire_weather_index,
    source_updated_at_utc = source_updated_at,
    retrieved_at_utc = retrieved_at_utc,
    source = "FireMap.live (EFFIS en NASA FIRMS)",
    source_url = FIREMAP_SOURCE_PAGE,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

parse_firemap_geojson <- function(raw_geojson, retrieved_at = Sys.time()) {
  if (!is.raw(raw_geojson) || length(raw_geojson) == 0L) {
    stop("De GeoJSON-response is leeg of niet binair ingelezen.", call. = FALSE)
  }

  document <- tryCatch(
    jsonlite::fromJSON(rawToChar(raw_geojson), simplifyVector = FALSE),
    error = function(error) {
      stop("Ongeldige JSON van FireMap.live: ", conditionMessage(error), call. = FALSE)
    }
  )

  if (!identical(document$type, "FeatureCollection")) {
    stop("De bronresponse is geen GeoJSON FeatureCollection.", call. = FALSE)
  }
  if (is.null(document$features) || !is.list(document$features)) {
    stop("De GeoJSON-response bevat geen featurelijst.", call. = FALSE)
  }

  retrieved_at_utc <- format_utc(retrieved_at)
  rows <- lapply(
    seq_along(document$features),
    function(index) feature_to_row(document$features[[index]], index, retrieved_at_utc)
  )

  if (length(rows) == 0L) {
    return(data.frame())
  }
  data <- do.call(rbind, rows)
  rownames(data) <- NULL
  data
}

validate_fire_data <- function(data, min_rows = 1L) {
  min_rows <- as.integer(min_rows)
  if (!is.data.frame(data) || nrow(data) < min_rows) {
    stop(
      "Validatie mislukt: ", nrow(data),
      " rijen ontvangen; minimaal ", min_rows, " verwacht.",
      call. = FALSE
    )
  }

  required <- c(
    "id", "latitude", "longitude", "status_nl", "marker_color",
    "retrieved_at_utc"
  )
  missing_columns <- setdiff(required, names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "Validatie mislukt: ontbrekende kolommen: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  invalid_coordinates <- !is.finite(data$latitude) |
    !is.finite(data$longitude) |
    data$latitude < -90 |
    data$latitude > 90 |
    data$longitude < -180 |
    data$longitude > 180

  if (any(invalid_coordinates)) {
    stop(
      "Validatie mislukt: ", sum(invalid_coordinates),
      " punten hebben ongeldige coördinaten.",
      call. = FALSE
    )
  }

  if (anyNA(data$id) || any(!nzchar(data$id))) {
    stop("Validatie mislukt: minstens één punt heeft geen id.", call. = FALSE)
  }
  if (anyDuplicated(data$id)) {
    stop("Validatie mislukt: dubbele punt-id's gevonden.", call. = FALSE)
  }

  invisible(data)
}

source_last_updated <- function(data) {
  values <- data$source_updated_at_utc
  values <- values[!is.na(values) & nzchar(values)]
  if (length(values) == 0L) {
    return(NA_character_)
  }

  parsed <- suppressWarnings(as.POSIXct(
    values,
    format = "%Y-%m-%dT%H:%M:%OSZ",
    tz = "UTC"
  ))
  parsed <- parsed[!is.na(parsed)]
  if (length(parsed) == 0L) {
    return(max(values))
  }
  format_utc(max(parsed))
}

build_status_summary <- function(data) {
  categories <- data.frame(
    status_nl = c(
      "Niet onder controle", "Onder controle", "Uitgedoofd", "Onbekend"
    ),
    status_order = 1:4,
    marker_color = c("#AA3228", "#E07154", "#FCD9BE", "#808080"),
    stringsAsFactors = FALSE
  )

  categories$count <- vapply(
    categories$status_nl,
    function(status) sum(data$status_nl == status, na.rm = TRUE),
    numeric(1)
  )
  categories$total_size_ha <- vapply(
    categories$status_nl,
    function(status) {
      sum(data$size_ha[data$status_nl == status], na.rm = TRUE)
    },
    numeric(1)
  )
  categories$retrieved_at_utc <- data$retrieved_at_utc[[1L]]
  categories$source_updated_at_utc <- source_last_updated(data)
  categories$source <- "FireMap.live (EFFIS en NASA FIRMS)"
  categories
}

translate_fire_weather_index <- function(value) {
  translation <- c(
    "Extreme" = "Extreem",
    "Very High" = "Zeer hoog",
    "High" = "Hoog",
    "Moderate" = "Gemiddeld",
    "Low" = "Laag",
    "Very Low" = "Zeer laag"
  )
  translated <- unname(translation[value])
  translated[is.na(value) | !nzchar(value)] <- "Onbekend"
  translated[is.na(translated)] <- "Onbekend"
  translated
}

build_flourish_export <- function(data) {
  actief <- ifelse(
    is.na(data$is_active),
    "Onbekend",
    ifelse(data$is_active, "Ja", "Nee")
  )

  data.frame(
    id = data$id,
    breedtegraad = data$latitude,
    lengtegraad = data$longitude,
    weergavenaam = data$display_name,
    plaatsnaam = data$location_name,
    landcode = data$country_code,
    landnaam = vapply(
      data$country_code,
      country_name_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    status = data$status_nl,
    status_uitleg = vapply(
      data$status_nl,
      status_explanation_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    statusvolgorde = data$status_order,
    markerkleur = data$marker_color,
    actief = actief,
    oppervlakte_ha = data$size_ha,
    oppervlakte = vapply(
      data$size_ha,
      format_area_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    markergrootte = data$marker_size,
    ontstaansdatum = vapply(
      data$ignition_date,
      format_date_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    ontstaansdatum_iso = data$ignition_date,
    duur_dagen = data$duration_days,
    duur = vapply(
      data$duration_days,
      format_duration_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    detecties_24u = data$detections_24h,
    detecties_7d = data$detections_7d,
    uren_sinds_update = data$last_update_hours,
    brandgevaar = translate_fire_weather_index(data$fire_weather_index),
    status_bijgewerkt = vapply(
      data$source_updated_at_utc,
      format_datetime_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    bron_bijgewerkt_utc = data$source_updated_at_utc,
    opgehaald_utc = data$retrieved_at_utc,
    bron = data$source,
    bron_url = data$source_url,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

validate_flourish_export <- function(data, min_rows = 1L) {
  min_rows <- as.integer(min_rows)
  if (!is.data.frame(data) || nrow(data) < min_rows) {
    stop(
      "Validatie mislukt: de Flourish-export bevat te weinig rijen.",
      call. = FALSE
    )
  }

  required <- c(
    "id", "breedtegraad", "lengtegraad", "weergavenaam", "status",
    "landnaam", "status_uitleg", "markerkleur", "oppervlakte",
    "markergrootte", "ontstaansdatum", "duur", "status_bijgewerkt",
    "opgehaald_utc", "bron"
  )
  missing_columns <- setdiff(required, names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "Validatie mislukt: ontbrekende Nederlandse Flourish-kolommen: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }

  invalid_coordinates <- !is.finite(data$breedtegraad) |
    !is.finite(data$lengtegraad) |
    data$breedtegraad < -90 |
    data$breedtegraad > 90 |
    data$lengtegraad < -180 |
    data$lengtegraad > 180
  if (any(invalid_coordinates)) {
    stop(
      "Validatie mislukt: de Flourish-export bevat ongeldige coördinaten.",
      call. = FALSE
    )
  }
  if (anyNA(data$id) || any(!nzchar(data$id)) || anyDuplicated(data$id)) {
    stop(
      "Validatie mislukt: de Flourish-export bevat ontbrekende of dubbele id's.",
      call. = FALSE
    )
  }

  invisible(data)
}

build_status_summary_export <- function(data) {
  summary <- build_status_summary(data)
  data.frame(
    status = summary$status_nl,
    statusvolgorde = summary$status_order,
    markerkleur = summary$marker_color,
    aantal = summary$count,
    totale_oppervlakte_ha = summary$total_size_ha,
    opgehaald_utc = summary$retrieved_at_utc,
    bron_bijgewerkt_utc = summary$source_updated_at_utc,
    bron = summary$source,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

build_metadata <- function(data, source_url) {
  status_counts <- build_status_summary(data)
  count_for <- function(status) {
    status_counts$count[status_counts$status_nl == status][[1L]]
  }

  list(
    schemaversie = "1.0",
    opgehaald_utc = data$retrieved_at_utc[[1L]],
    bron_bijgewerkt_utc = source_last_updated(data),
    aantal_brandpunten = nrow(data),
    aantal_actief = sum(data$is_active %in% TRUE, na.rm = TRUE),
    aantal_uitgedoofd = sum(data$is_active %in% FALSE, na.rm = TRUE),
    aantal_status_onbekend = count_for("Onbekend"),
    aantallen_per_status = list(
      niet_onder_controle = count_for("Niet onder controle"),
      onder_controle = count_for("Onder controle"),
      uitgedoofd = count_for("Uitgedoofd"),
      onbekend = count_for("Onbekend")
    ),
    brondata_url = source_url,
    bronpagina = FIREMAP_SOURCE_PAGE,
    datalicentie = FIREMAP_DATA_LICENSE,
    bronvermelding = "FireMap.live (EFFIS en NASA FIRMS)"
  )
}

replace_file <- function(staged_path, target_path) {
  if (.Platform$OS.type == "windows" && file.exists(target_path)) {
    if (!file.remove(target_path)) {
      stop("Kon bestaand bestand niet vervangen: ", target_path, call. = FALSE)
    }
  }

  if (!file.rename(staged_path, target_path)) {
    stop("Kon bestand niet atomair plaatsen: ", target_path, call. = FALSE)
  }
  invisible(target_path)
}

write_firemap_outputs <- function(data, raw_geojson, output_dir, source_url) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  stage_dir <- tempfile(pattern = ".firemap-stage-", tmpdir = output_dir)
  dir.create(stage_dir)
  on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)

  fires_path <- file.path(stage_dir, "flourish_branden.csv")
  summary_path <- file.path(stage_dir, "flourish_statussamenvatting.csv")
  raw_path <- file.path(stage_dir, "firemap_bron.geojson")
  metadata_path <- file.path(stage_dir, "firemap_metagegevens.json")

  utils::write.csv(
    build_flourish_export(data),
    fires_path,
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
  utils::write.csv(
    build_status_summary_export(data),
    summary_path,
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
  writeBin(raw_geojson, raw_path)
  jsonlite::write_json(
    build_metadata(data, source_url),
    metadata_path,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null"
  )

  staged_files <- c(fires_path, summary_path, raw_path, metadata_path)
  if (any(!file.exists(staged_files)) || any(file.info(staged_files)$size == 0L)) {
    stop("Minstens één uitvoerbestand is leeg of ontbreekt.", call. = FALSE)
  }

  for (staged_path in staged_files) {
    replace_file(staged_path, file.path(output_dir, basename(staged_path)))
  }

  invisible(file.path(output_dir, basename(staged_files)))
}

download_firemap_geojson <- function(
  source_url,
  timeout_seconds = 60,
  max_tries = 4L
) {
  request <- httr2::request(source_url) |>
    httr2::req_user_agent(paste0(
      "firemap-flourish-pipeline/1.0 ",
      "(+https://github.com/FixyDesing/260803_firemap_DSI)"
    )) |>
    httr2::req_timeout(timeout_seconds) |>
    httr2::req_retry(
      max_tries = max_tries,
      max_seconds = timeout_seconds * max_tries,
      retry_on_failure = TRUE,
      is_transient = function(response) {
        httr2::resp_status(response) %in% c(408, 425, 429, 500, 502, 503, 504)
      }
    )

  response <- httr2::req_perform(request)
  body <- httr2::resp_body_raw(response)
  if (length(body) == 0L) {
    stop("FireMap.live antwoordde met een lege response.", call. = FALSE)
  }
  body
}

run_firemap_pipeline <- function(
  source_url = Sys.getenv("FIREMAP_SOURCE_URL", unset = FIREMAP_DEFAULT_URL),
  output_dir = Sys.getenv("FIREMAP_OUTPUT_DIR", unset = "data"),
  min_rows = env_number("FIREMAP_MIN_ROWS", 1),
  timeout_seconds = env_number("FIREMAP_TIMEOUT_SECONDS", 60)
) {
  message("FireMap-data ophalen...")
  raw_geojson <- download_firemap_geojson(
    source_url = source_url,
    timeout_seconds = timeout_seconds
  )

  retrieved_at <- Sys.time()
  data <- parse_firemap_geojson(raw_geojson, retrieved_at = retrieved_at)
  validate_fire_data(data, min_rows = min_rows)
  write_firemap_outputs(data, raw_geojson, output_dir, source_url)

  message(
    "Klaar: ", nrow(data), " brandpunten weggeschreven naar ",
    normalizePath(output_dir, mustWork = TRUE), "."
  )
  invisible(data)
}
