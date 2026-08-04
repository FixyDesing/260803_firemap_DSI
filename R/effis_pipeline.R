# EFFIS -> Flourish pipeline -------------------------------------------------

EFFIS_DEFAULT_URL <- paste0(
  "https://api.effis.emergency.copernicus.eu/",
  "rest/2/burntareas/current"
)
EFFIS_SOURCE_PAGE <- paste0(
  "https://forest-fire.emergency.copernicus.eu/apps/effis.csv/"
)
EFFIS_DATA_LICENSE <- paste0(
  "https://forest-fire.emergency.copernicus.eu/about-effis/data-license"
)
EFFIS_SOURCE_LABEL <- "EFFIS – Copernicus Emergency Management Service"
EFFIS_TIMEZONE <- "Europe/Brussels"

clean_effis_text <- function(value) {
  value <- as_scalar_character(value)
  if (is.na(value) || toupper(value) %in% c("N.A.", "N/A", "UNKNOWN")) {
    return(NA_character_)
  }
  value
}

parse_effis_datetime <- function(value) {
  value <- as_scalar_character(value)
  if (is.na(value)) {
    return(as.POSIXct(NA, tz = "UTC"))
  }

  normalized <- sub(
    "([+-][0-9]{2}):([0-9]{2})$",
    "\\1\\2",
    value
  )
  parsed <- suppressWarnings(as.POSIXct(
    normalized,
    format = "%Y-%m-%dT%H:%M:%OS%z",
    tz = "UTC"
  ))

  if (is.na(parsed) && grepl("Z$", value)) {
    parsed <- suppressWarnings(as.POSIXct(
      value,
      format = "%Y-%m-%dT%H:%M:%OSZ",
      tz = "UTC"
    ))
  }
  parsed
}

format_effis_datetime_utc <- function(value) {
  parsed <- parse_effis_datetime(value)
  if (is.na(parsed)) NA_character_ else format_utc(parsed)
}

format_effis_datetime_nl <- function(value) {
  parsed <- parse_effis_datetime(value)
  if (is.na(parsed)) {
    return("Niet beschikbaar")
  }
  format_datetime_nl(format_utc(parsed), timezone = EFFIS_TIMEZONE)
}

effis_local_date <- function(value) {
  parsed <- parse_effis_datetime(value)
  if (is.na(parsed)) {
    return(as.Date(NA))
  }
  as.Date(format(parsed, "%Y-%m-%d", tz = EFFIS_TIMEZONE))
}

effis_country_name_nl <- function(country_code, source_name = NA_character_) {
  country_code <- clean_effis_text(country_code)
  source_name <- clean_effis_text(source_name)

  if (!is.na(country_code)) {
    translated <- country_name_nl(country_code)
    if (!identical(translated, country_code)) {
      return(translated)
    }
  }
  if (!is.na(source_name)) source_name else "Onbekend land"
}

effis_actuality_details <- function(days_since_update) {
  if (!is.finite(days_since_update) || days_since_update < 0) {
    return(list(
      label = "Actualiteit onbekend",
      explanation = "De datum van de laatste EFFIS-update is niet beschikbaar.",
      color = "#808080",
      order = 4L
    ))
  }
  if (days_since_update == 0) {
    return(list(
      label = "Vandaag bijgewerkt",
      explanation = "EFFIS heeft dit gebied vandaag bijgewerkt.",
      color = "#AA3228",
      order = 1L
    ))
  }
  if (days_since_update <= 3) {
    return(list(
      label = "Afgelopen 3 dagen bijgewerkt",
      explanation = paste(
        "EFFIS heeft dit gebied één tot drie dagen geleden bijgewerkt."
      ),
      color = "#E07154",
      order = 2L
    ))
  }
  if (days_since_update <= 7) {
    return(list(
      label = "4–7 dagen geleden bijgewerkt",
      explanation = paste(
        "EFFIS heeft dit gebied vier tot zeven dagen geleden bijgewerkt."
      ),
      color = "#FCD9BE",
      order = 3L
    ))
  }

  list(
    label = "Actualiteit onbekend",
    explanation = paste(
      "De laatste EFFIS-update valt buiten het geselecteerde venster",
      "van zeven dagen."
    ),
    color = "#808080",
    order = 4L
  )
}

format_registration_period_nl <- function(days) {
  if (!is.finite(days) || days < 0) {
    return("Niet beschikbaar")
  }
  if (days == 0) {
    return("Minder dan één dag tussen registraties")
  }
  if (days == 1) {
    return("1 dag tussen registraties")
  }
  paste0(round(days), " dagen tussen registraties")
}

format_effis_date_nl <- function(value) {
  parsed <- parse_effis_datetime(value)
  if (is.na(parsed)) {
    return("Niet beschikbaar")
  }
  format_date_nl(format(parsed, "%Y-%m-%d", tz = EFFIS_TIMEZONE))
}

format_firemap_count_nl <- function(value) {
  if (!is.finite(value) || value < 0) {
    return("Niet beschikbaar")
  }
  formatC(
    round(value),
    format = "f",
    digits = 0,
    big.mark = ".",
    decimal.mark = ","
  )
}

format_firemap_status_nl <- function(value) {
  value <- clean_effis_text(value)
  if (is.na(value) || identical(value, "Onbekend")) {
    "Niet beschikbaar"
  } else {
    value
  }
}

format_firemap_danger_nl <- function(value) {
  value <- clean_effis_text(value)
  if (is.na(value) || identical(value, "Onbekend")) {
    "Niet beschikbaar"
  } else {
    value
  }
}

effis_region_nl <- function(country_name, province) {
  country_name <- clean_effis_text(country_name)
  province <- clean_effis_text(province)
  if (is.na(country_name)) country_name <- "Onbekend land"
  if (is.na(province)) country_name else paste(country_name, province, sep = ", ")
}

effis_record_to_row <- function(
  record,
  row_number,
  retrieved_at_utc,
  reference_date
) {
  centroid <- record$centroid
  if (is.null(centroid) || !identical(centroid$type, "Point")) {
    stop("EFFIS-record ", row_number, " heeft geen Point-centroid.", call. = FALSE)
  }

  coordinates <- suppressWarnings(as.numeric(unlist(
    centroid$coordinates,
    use.names = FALSE
  )))
  if (length(coordinates) < 2L || any(!is.finite(coordinates[1:2]))) {
    stop("EFFIS-record ", row_number, " heeft ongeldige coördinaten.", call. = FALSE)
  }

  source_id <- as_scalar_character(record$id)
  if (is.na(source_id)) {
    stop("EFFIS-record ", row_number, " heeft geen id.", call. = FALSE)
  }

  commune <- clean_effis_text(record$commune)
  province <- clean_effis_text(record$province)
  country_code <- clean_effis_text(record$country)
  country_name <- effis_country_name_nl(country_code, record$countryful)
  display_name <- if (!is.na(commune)) {
    commune
  } else if (!is.na(province)) {
    province
  } else {
    paste("Verbrand gebied in", country_name)
  }

  size_ha <- as_scalar_numeric(record$area_ha)
  first_registration <- parse_effis_datetime(record$firedate)
  last_update <- parse_effis_datetime(record$lastupdate)
  last_update_date <- effis_local_date(record$lastupdate)
  days_since_update <- if (is.na(last_update_date)) {
    NA_real_
  } else {
    max(0, as.numeric(reference_date - last_update_date))
  }
  registration_days <- if (is.na(first_registration) || is.na(last_update)) {
    NA_real_
  } else {
    max(0, floor(as.numeric(difftime(
      last_update,
      first_registration,
      units = "days"
    ))))
  }
  actuality <- effis_actuality_details(days_since_update)

  data.frame(
    id = paste0("effis-ba-", source_id),
    data_type = "effis_brandgebied",
    source_id = source_id,
    latitude = coordinates[[2L]],
    longitude = coordinates[[1L]],
    display_name = display_name,
    commune = commune,
    province = province,
    country_code = country_code,
    country_name = country_name,
    actuality_nl = actuality$label,
    actuality_explanation_nl = actuality$explanation,
    actuality_order = actuality$order,
    marker_color = actuality$color,
    size_ha = size_ha,
    marker_size = calculate_marker_size(size_ha),
    first_registration_utc = if (is.na(first_registration)) {
      NA_character_
    } else {
      format_utc(first_registration)
    },
    last_update_utc = if (is.na(last_update)) {
      NA_character_
    } else {
      format_utc(last_update)
    },
    days_since_update = days_since_update,
    registration_days = registration_days,
    retrieved_at_utc = retrieved_at_utc,
    source = EFFIS_SOURCE_LABEL,
    source_url = EFFIS_SOURCE_PAGE,
    firemap_available = FALSE,
    firemap_status_nl = NA_character_,
    firemap_detections_24h = NA_real_,
    firemap_detections_7d = NA_real_,
    firemap_fire_weather_nl = NA_character_,
    firemap_source_updated_at_utc = NA_character_,
    firemap_retrieved_at_utc = NA_character_,
    firms_satellites = NA_character_,
    firms_instruments = NA_character_,
    firms_max_frp_mw = NA_real_,
    firms_detection_days_7d = NA_real_,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

parse_effis_records <- function(
  records,
  retrieved_at = Sys.time(),
  reference_date = as.Date(format(
    retrieved_at,
    "%Y-%m-%d",
    tz = EFFIS_TIMEZONE
  ))
) {
  if (is.null(records) || !is.list(records)) {
    stop("De EFFIS-response bevat geen geldige recordlijst.", call. = FALSE)
  }
  if (length(records) == 0L) {
    return(data.frame())
  }

  retrieved_at_utc <- format_utc(retrieved_at)
  rows <- lapply(
    seq_along(records),
    function(index) effis_record_to_row(
      records[[index]],
      index,
      retrieved_at_utc,
      as.Date(reference_date)
    )
  )
  data <- do.call(rbind, rows)
  rownames(data) <- NULL
  data
}

enrich_effis_with_firemap <- function(effis_data, firemap_data = NULL) {
  if (is.null(firemap_data) || !is.data.frame(firemap_data) ||
      nrow(firemap_data) == 0L) {
    return(effis_data)
  }
  if (!"source_id" %in% names(firemap_data)) {
    stop("De FireMap-verrijking bevat geen EFFIS-bron-id.", call. = FALSE)
  }

  usable <- !is.na(firemap_data$source_id) & nzchar(firemap_data$source_id)
  enrichment <- firemap_data[usable, , drop = FALSE]
  enrichment <- enrichment[!duplicated(enrichment$source_id), , drop = FALSE]
  matched_index <- match(effis_data$source_id, enrichment$source_id)
  matched <- !is.na(matched_index)
  if (!any(matched)) {
    return(effis_data)
  }

  source_rows <- matched_index[matched]
  effis_data$firemap_available[matched] <- TRUE
  effis_data$firemap_status_nl[matched] <- enrichment$status_nl[source_rows]
  effis_data$firemap_detections_24h[matched] <- enrichment$detections_24h[source_rows]
  effis_data$firemap_detections_7d[matched] <- enrichment$detections_7d[source_rows]
  effis_data$firemap_fire_weather_nl[matched] <- translate_fire_weather_index(
    enrichment$fire_weather_index[source_rows]
  )
  effis_data$firemap_source_updated_at_utc[matched] <-
    enrichment$source_updated_at_utc[source_rows]
  effis_data$firemap_retrieved_at_utc[matched] <-
    enrichment$retrieved_at_utc[source_rows]
  effis_data
}

firms_clusters_to_rows <- function(clusters, retrieved_at_utc) {
  if (!is.data.frame(clusters) || nrow(clusters) == 0L) {
    return(data.frame())
  }

  first_detection <- as.POSIXct(
    clusters$first_detection_utc,
    format = "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
  last_detection <- as.POSIXct(
    clusters$last_detection_utc,
    format = "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  )
  registration_days <- pmax(0, floor(as.numeric(difftime(
    last_detection,
    first_detection,
    units = "days"
  ))))
  labels <- ifelse(
    clusters$detections_24h > 0,
    "Satellietdetectie laatste 24 uur",
    "Satellietdetectie laatste 48 uur"
  )
  explanations <- ifelse(
    clusters$detections_24h > 0,
    paste(
      "NASA FIRMS registreerde hier de afgelopen 24 uur een warmtebron.",
      "Dit is nog geen door EFFIS ingetekend brandgebied."
    ),
    paste(
      "NASA FIRMS registreerde hier de afgelopen 48 uur een warmtebron.",
      "Dit is nog geen door EFFIS ingetekend brandgebied."
    )
  )

  data.frame(
    id = clusters$cluster_id,
    data_type = "firms_hotspot",
    source_id = clusters$cluster_id,
    latitude = clusters$latitude,
    longitude = clusters$longitude,
    display_name = "Actieve satellietdetectie",
    commune = NA_character_,
    province = NA_character_,
    country_code = clusters$country_code,
    country_name = clusters$country_name,
    actuality_nl = labels,
    actuality_explanation_nl = explanations,
    actuality_order = 0L,
    marker_color = "#AA3228",
    size_ha = NA_real_,
    marker_size = round(pmin(
      1.5,
      0.8 + 0.2 * log10(pmax(1, clusters$detections_7d) + 1)
    ), 2),
    first_registration_utc = clusters$first_detection_utc,
    last_update_utc = clusters$last_detection_utc,
    days_since_update = pmax(0, as.numeric(difftime(
      as.POSIXct(retrieved_at_utc, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      last_detection,
      units = "days"
    ))),
    registration_days = registration_days,
    retrieved_at_utc = retrieved_at_utc,
    source = FIRMS_SOURCE_LABEL,
    source_url = FIRMS_SOURCE_PAGE,
    firemap_available = FALSE,
    firemap_status_nl = "Satellietdetectie – nog niet bevestigd",
    firemap_detections_24h = clusters$detections_24h,
    firemap_detections_7d = clusters$detections_7d,
    firemap_fire_weather_nl = NA_character_,
    firemap_source_updated_at_utc = NA_character_,
    firemap_retrieved_at_utc = NA_character_,
    firms_satellites = clusters$satellites,
    firms_instruments = clusters$instruments,
    firms_max_frp_mw = clusters$max_frp_mw,
    firms_detection_days_7d = clusters$detection_days_7d,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

validate_effis_data <- function(data, min_rows = 1L) {
  min_rows <- as.integer(min_rows)
  if (!is.data.frame(data) || nrow(data) < min_rows) {
    stop(
      "EFFIS-validatie mislukt: ", nrow(data),
      " rijen ontvangen; minimaal ", min_rows, " verwacht.",
      call. = FALSE
    )
  }

  required <- c(
    "id", "latitude", "longitude", "display_name", "actuality_nl",
    "marker_color", "size_ha", "last_update_utc", "retrieved_at_utc"
  )
  missing_columns <- setdiff(required, names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "EFFIS-validatie mislukt: ontbrekende kolommen: ",
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
      "EFFIS-validatie mislukt: ", sum(invalid_coordinates),
      " punten hebben ongeldige coördinaten.",
      call. = FALSE
    )
  }
  if (anyNA(data$id) || any(!nzchar(data$id)) || anyDuplicated(data$id)) {
    stop(
      "EFFIS-validatie mislukt: ontbrekende of dubbele id's.",
      call. = FALSE
    )
  }
  if (any(is.finite(data$size_ha) & data$size_ha < 0)) {
    stop("EFFIS-validatie mislukt: negatieve oppervlaktes.", call. = FALSE)
  }
  if (any(data$marker_size < 0.1 | data$marker_size > 3, na.rm = TRUE)) {
    stop("EFFIS-validatie mislukt: markergrootte buiten 0,1–3.", call. = FALSE)
  }

  invisible(data)
}

effis_last_updated <- function(data) {
  if ("data_type" %in% names(data)) {
    data <- data[data$data_type == "effis_brandgebied", , drop = FALSE]
  }
  values <- data$last_update_utc
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
  if (length(parsed) == 0L) NA_character_ else format_utc(max(parsed))
}

build_effis_flourish_export <- function(data) {
  data.frame(
    id = data$id,
    gegevenstype = ifelse(
      data$data_type == "firms_hotspot",
      "Actieve satellietdetectie",
      "EFFIS-brandgebied"
    ),
    breedtegraad = data$latitude,
    lengtegraad = data$longitude,
    weergavenaam = data$display_name,
    plaatsnaam = ifelse(is.na(data$commune), "Niet beschikbaar", data$commune),
    provincie = ifelse(is.na(data$province), "Niet beschikbaar", data$province),
    landcode = data$country_code,
    landnaam = data$country_name,
    regio = mapply(
      effis_region_nl,
      data$country_name,
      data$province,
      USE.NAMES = FALSE
    ),
    actualiteit = data$actuality_nl,
    actualiteit_uitleg = data$actuality_explanation_nl,
    actualiteitvolgorde = data$actuality_order,
    markerkleur = data$marker_color,
    oppervlakte_ha = data$size_ha,
    oppervlakte = ifelse(
      data$data_type == "firms_hotspot",
      "Nog niet vastgesteld",
      vapply(
        data$size_ha,
        format_area_nl,
        character(1),
        USE.NAMES = FALSE
      )
    ),
    markergrootte = data$marker_size,
    eerste_registratie = vapply(
      data$first_registration_utc,
      format_datetime_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    eerste_registratiedatum = vapply(
      data$first_registration_utc,
      format_effis_date_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    eerste_registratie_utc = data$first_registration_utc,
    laatste_update = vapply(
      data$last_update_utc,
      format_datetime_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    laatste_update_utc = data$last_update_utc,
    dagen_sinds_update = data$days_since_update,
    registratieperiode = vapply(
      data$registration_days,
      format_registration_period_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    statusindicatie = vapply(
      data$firemap_status_nl,
      format_firemap_status_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    detecties_24u = vapply(
      data$firemap_detections_24h,
      format_firemap_count_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    detecties_7d = vapply(
      data$firemap_detections_7d,
      format_firemap_count_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    brandgevaar = vapply(
      data$firemap_fire_weather_nl,
      format_firemap_danger_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    firemap_beschikbaar = ifelse(data$firemap_available, "Ja", "Nee"),
    firemap_bijgewerkt = vapply(
      data$firemap_source_updated_at_utc,
      format_datetime_nl,
      character(1),
      USE.NAMES = FALSE
    ),
    firemap_bijgewerkt_utc = data$firemap_source_updated_at_utc,
    firemap_opgehaald_utc = data$firemap_retrieved_at_utc,
    firms_hotspot = ifelse(data$data_type == "firms_hotspot", "Ja", "Nee"),
    satellieten = ifelse(
      is.na(data$firms_satellites),
      "Niet beschikbaar",
      data$firms_satellites
    ),
    instrumenten = ifelse(
      is.na(data$firms_instruments),
      "Niet beschikbaar",
      data$firms_instruments
    ),
    maximale_stralingskracht_mw = data$firms_max_frp_mw,
    detectiedagen_7d = data$firms_detection_days_7d,
    opgehaald_utc = data$retrieved_at_utc,
    bron = data$source,
    bron_url = data$source_url,
    aanvullende_bron = ifelse(
      data$firemap_available,
      "FireMap.live (EFFIS en NASA FIRMS)",
      ""
    ),
    aanvullende_bron_url = ifelse(
      data$firemap_available,
      FIREMAP_SOURCE_PAGE,
      ""
    ),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

validate_effis_flourish_export <- function(data, min_rows = 1L) {
  min_rows <- as.integer(min_rows)
  if (!is.data.frame(data) || nrow(data) < min_rows) {
    stop("De EFFIS-Flourish-export bevat te weinig rijen.", call. = FALSE)
  }
  required <- c(
    "id", "gegevenstype", "breedtegraad", "lengtegraad", "weergavenaam", "regio",
    "actualiteit", "markerkleur", "oppervlakte", "markergrootte",
    "eerste_registratie", "eerste_registratiedatum", "laatste_update",
    "registratieperiode", "statusindicatie", "detecties_24u",
    "detecties_7d", "brandgevaar", "firemap_beschikbaar", "bron", "bron_url"
  )
  missing_columns <- setdiff(required, names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "Ontbrekende EFFIS-Flourish-kolommen: ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  if (anyNA(data$id) || any(!nzchar(data$id)) || anyDuplicated(data$id)) {
    stop("De EFFIS-Flourish-export bevat ongeldige id's.", call. = FALSE)
  }
  invalid_coordinates <- !is.finite(data$breedtegraad) |
    !is.finite(data$lengtegraad) |
    data$breedtegraad < -90 |
    data$breedtegraad > 90 |
    data$lengtegraad < -180 |
    data$lengtegraad > 180
  if (any(invalid_coordinates)) {
    stop("De EFFIS-Flourish-export bevat ongeldige coördinaten.", call. = FALSE)
  }
  invisible(data)
}

build_effis_actuality_summary <- function(data) {
  categories <- data.frame(
    actualiteit = c(
      "Satellietdetectie laatste 24 uur",
      "Satellietdetectie laatste 48 uur",
      "Vandaag bijgewerkt",
      "Afgelopen 3 dagen bijgewerkt",
      "4–7 dagen geleden bijgewerkt",
      "Actualiteit onbekend"
    ),
    actualiteitvolgorde = c(0L, 0L, 1L, 2L, 3L, 4L),
    markerkleur = c(
      "#AA3228", "#AA3228", "#AA3228", "#E07154", "#FCD9BE", "#808080"
    ),
    stringsAsFactors = FALSE
  )
  categories$aantal <- vapply(
    categories$actualiteit,
    function(label) sum(data$actuality_nl == label, na.rm = TRUE),
    numeric(1)
  )
  categories$totale_oppervlakte_ha <- vapply(
    categories$actualiteit,
    function(label) sum(data$size_ha[data$actuality_nl == label], na.rm = TRUE),
    numeric(1)
  )
  categories$opgehaald_utc <- data$retrieved_at_utc[[1L]]
  categories$bron_bijgewerkt_utc <- effis_last_updated(data)
  categories$bron <- ifelse(
    grepl("^Satellietdetectie", categories$actualiteit),
    FIRMS_SOURCE_LABEL,
    EFFIS_SOURCE_LABEL
  )
  categories
}

build_effis_query_url <- function(source_url, from_date, to_date, page_size) {
  paste0(
    source_url,
    "?lastupdate__gte=", from_date, "T00%3A00%3A00",
    "&lastupdate__lte=", to_date, "T23%3A59%3A59",
    "&ordering=-lastupdate%2C-area_ha",
    "&limit=", as.integer(page_size)
  )
}

build_effis_metadata <- function(data, download) {
  summary <- build_effis_actuality_summary(data)
  enrichment <- download$firemap_enrichment
  firms <- download$firms_hotspots
  is_effis <- data$data_type == "effis_brandgebied"
  is_firms <- data$data_type == "firms_hotspot"
  firemap_records <- if (is.null(enrichment$record_count)) {
    0L
  } else {
    as.integer(enrichment$record_count)
  }
  firemap_error <- if (is.null(enrichment$error)) {
    NA_character_
  } else {
    as.character(enrichment$error)
  }
  count_for <- function(label) {
    value <- summary$aantal[summary$actualiteit == label]
    if (length(value) == 0L) 0 else value[[1L]]
  }

  list(
    schemaversie = "1.1",
    opgehaald_utc = data$retrieved_at_utc[[1L]],
    bron_bijgewerkt_utc = effis_last_updated(data),
    venster_vanaf = as.character(download$from_date),
    venster_tot_en_met = as.character(download$to_date),
    aantal_markers = nrow(data),
    aantal_brandgebieden = sum(is_effis),
    aantal_firms_hotspotclusters = sum(is_firms),
    totale_oppervlakte_ha = sum(data$size_ha[is_effis], na.rm = TRUE),
    aantallen_per_actualiteit = list(
      vandaag = count_for("Vandaag bijgewerkt"),
      afgelopen_drie_dagen = count_for("Afgelopen 3 dagen bijgewerkt"),
      vier_tot_zeven_dagen = count_for("4–7 dagen geleden bijgewerkt"),
      onbekend = count_for("Actualiteit onbekend")
    ),
    brondata_url = download$query_url,
    bronpagina = EFFIS_SOURCE_PAGE,
    datalicentie = EFFIS_DATA_LICENSE,
    bronvermelding = EFFIS_SOURCE_LABEL,
    firemap_verrijking = list(
      bron = "FireMap.live (EFFIS en NASA FIRMS)",
      bron_url = FIREMAP_SOURCE_PAGE,
      brondata_url = if (is.null(enrichment$source_url)) {
        FIREMAP_DEFAULT_URL
      } else {
        enrichment$source_url
      },
      ophalen_geslaagd = isTRUE(enrichment$succeeded),
      aantal_firemap_records = firemap_records,
      aantal_gekoppeld_op_effis_id = sum(data$firemap_available[is_effis]),
      aandeel_effis_verrijkt = round(
        100 * mean(data$firemap_available[is_effis]),
        1
      ),
      foutmelding = firemap_error
    ),
    firms_hotspots = list(
      bron = FIRMS_SOURCE_LABEL,
      bron_url = FIRMS_SOURCE_PAGE,
      ophalen_geslaagd = isTRUE(firms$succeeded),
      aantal_detecties_na_filtering = if (is.null(firms$record_count)) {
        0L
      } else {
        as.integer(firms$record_count)
      },
      aantal_clusters_voor_effis_ontdubbeling = if (
        is.null(firms$cluster_count_before_deduplication)
      ) {
        0L
      } else {
        as.integer(firms$cluster_count_before_deduplication)
      },
      aantal_clusters_voor_filter_permanente_warmtebronnen = if (
        is.null(firms$cluster_count_before_static_filter)
      ) {
        0L
      } else {
        as.integer(firms$cluster_count_before_static_filter)
      },
      aantal_clusters_in_export = sum(is_firms),
      zoekgebied = if (is.null(firms$area)) FIRMS_DEFAULT_AREA else firms$area,
      sensorbronnen = if (is.null(firms$sources)) {
        FIRMS_DEFAULT_SOURCES
      } else {
        firms$sources
      },
      bronqueries_zonder_sleutel = if (is.null(firms$query_descriptions)) {
        character()
      } else {
        firms$query_descriptions
      },
      foutmelding = if (is.null(firms$error)) NA_character_ else firms$error
    ),
    uitgevoerde_aanpassingen = paste(
      "Selectie op laatste EFFIS-update van zeven dagen;",
      "brandperimeters weergegeven als centroidpunten;",
      "actualiteitscategorieën en Nederlandse labels toegevoegd;",
      "beschikbare FireMap-velden gekoppeld via het oorspronkelijke EFFIS-id;",
      "recente FIRMS-detecties op land per rastercel samengevoegd en",
      "ontdubbeld tegen nabijgelegen EFFIS-brandgebieden."
    ),
    belangrijke_beperking = paste(
      "EFFIS-datums zijn kaartregistraties. FIRMS-detecties zijn thermische",
      "anomalieën en vormen zonder EFFIS-perimeter nog geen bevestiging van",
      "een natuurbrand of van de verbrande oppervlakte."
    )
  )
}

select_effis_source_fields <- function(record) {
  keep <- c(
    "id", "centroid", "country", "countryful", "province", "commune",
    "firedate", "area_ha", "lastupdate", "lastfiredate"
  )
  record[intersect(keep, names(record))]
}

build_effis_source_snapshot <- function(download, retrieved_at_utc) {
  list(
    schemaversie = "1.0",
    opgehaald_utc = retrieved_at_utc,
    brondata_url = download$query_url,
    venster_vanaf = as.character(download$from_date),
    venster_tot_en_met = as.character(download$to_date),
    aantal_records = length(download$results),
    opmerking = paste(
      "Compacte bronselectie zonder polygonen; de originele EFFIS-response",
      "bevat ook volledige brandperimeters."
    ),
    resultaten = lapply(download$results, select_effis_source_fields)
  )
}

write_effis_outputs <- function(data, download, output_dir) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  stage_dir <- tempfile(pattern = ".effis-stage-", tmpdir = output_dir)
  dir.create(stage_dir)
  on.exit(unlink(stage_dir, recursive = TRUE, force = TRUE), add = TRUE)

  fires_path <- file.path(stage_dir, "flourish_effis_branden.csv")
  summary_path <- file.path(
    stage_dir,
    "flourish_effis_actualiteitssamenvatting.csv"
  )
  source_path <- file.path(stage_dir, "effis_bronselectie.json")
  metadata_path <- file.path(stage_dir, "effis_metagegevens.json")

  utils::write.csv(
    build_effis_flourish_export(data),
    fires_path,
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
  utils::write.csv(
    build_effis_actuality_summary(data),
    summary_path,
    row.names = FALSE,
    na = "",
    fileEncoding = "UTF-8"
  )
  jsonlite::write_json(
    build_effis_source_snapshot(download, data$retrieved_at_utc[[1L]]),
    source_path,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null"
  )
  jsonlite::write_json(
    build_effis_metadata(data, download),
    metadata_path,
    auto_unbox = TRUE,
    pretty = TRUE,
    na = "null"
  )

  staged_files <- c(fires_path, summary_path, source_path, metadata_path)
  if (any(!file.exists(staged_files)) || any(file.info(staged_files)$size == 0L)) {
    stop("Minstens één EFFIS-uitvoerbestand is leeg of ontbreekt.", call. = FALSE)
  }
  for (staged_path in staged_files) {
    replace_file(staged_path, file.path(output_dir, basename(staged_path)))
  }

  invisible(file.path(output_dir, basename(staged_files)))
}

download_effis_page <- function(
  source_url,
  from_date,
  to_date,
  limit,
  offset,
  timeout_seconds,
  max_tries
) {
  request <- httr2::request(source_url) |>
    httr2::req_url_query(
      lastupdate__gte = paste0(from_date, "T00:00:00"),
      lastupdate__lte = paste0(to_date, "T23:59:59"),
      ordering = "-lastupdate,-area_ha",
      limit = as.integer(limit),
      offset = as.integer(offset)
    ) |>
    httr2::req_user_agent(paste0(
      "effis-flourish-pipeline/1.0 ",
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
  tryCatch(
    httr2::resp_body_json(response, simplifyVector = FALSE),
    error = function(error) {
      stop("Ongeldige JSON van EFFIS: ", conditionMessage(error), call. = FALSE)
    }
  )
}

download_effis_burnt_areas <- function(
  source_url = EFFIS_DEFAULT_URL,
  from_date,
  to_date,
  page_size = 1000L,
  timeout_seconds = 90,
  max_tries = 4L,
  max_pages = 20L
) {
  from_date <- as.Date(from_date)
  to_date <- as.Date(to_date)
  if (is.na(from_date) || is.na(to_date) || from_date > to_date) {
    stop("Het EFFIS-datumbereik is ongeldig.", call. = FALSE)
  }

  page_size <- as.integer(page_size)
  offset <- 0L
  page_number <- 0L
  total_count <- NA_integer_
  results <- list()

  repeat {
    page_number <- page_number + 1L
    if (page_number > as.integer(max_pages)) {
      stop("EFFIS-paginering overschrijdt de ingestelde limiet.", call. = FALSE)
    }

    document <- download_effis_page(
      source_url,
      from_date,
      to_date,
      page_size,
      offset,
      timeout_seconds,
      max_tries
    )
    if (is.null(document$results) || !is.list(document$results)) {
      stop("De EFFIS-response bevat geen resultatenlijst.", call. = FALSE)
    }
    if (is.na(total_count)) {
      total_count <- suppressWarnings(as.integer(document$count))
      if (is.na(total_count) || total_count < 0) {
        stop("De EFFIS-response bevat geen geldig totaal aantal.", call. = FALSE)
      }
    }

    page_results <- document$results
    results <- c(results, page_results)
    offset <- length(results)
    if (offset >= total_count) break
    if (length(page_results) == 0L) {
      stop("EFFIS-paginering stopte vóór alle records waren opgehaald.", call. = FALSE)
    }
  }

  if (length(results) != total_count) {
    stop(
      "EFFIS meldde ", total_count, " records, maar leverde er ",
      length(results), ".",
      call. = FALSE
    )
  }

  list(
    results = results,
    count = total_count,
    from_date = from_date,
    to_date = to_date,
    query_url = build_effis_query_url(
      source_url,
      from_date,
      to_date,
      page_size
    )
  )
}

download_firemap_enrichment <- function(
  source_url = FIREMAP_DEFAULT_URL,
  timeout_seconds = 60,
  max_tries = 4L
) {
  if (!nzchar(source_url)) {
    return(list(
      data = NULL,
      succeeded = FALSE,
      record_count = 0L,
      source_url = source_url,
      error = "FireMap-verrijking is uitgeschakeld."
    ))
  }

  tryCatch(
    {
      raw_geojson <- download_firemap_geojson(
        source_url = source_url,
        timeout_seconds = timeout_seconds,
        max_tries = max_tries
      )
      retrieved_at <- Sys.time()
      data <- parse_firemap_geojson(raw_geojson, retrieved_at = retrieved_at)
      validate_fire_data(data, min_rows = 1L)
      list(
        data = data,
        succeeded = TRUE,
        record_count = nrow(data),
        source_url = source_url,
        error = NA_character_
      )
    },
    error = function(error) {
      list(
        data = NULL,
        succeeded = FALSE,
        record_count = 0L,
        source_url = source_url,
        error = conditionMessage(error)
      )
    }
  )
}

run_effis_pipeline <- function(
  source_url = Sys.getenv("EFFIS_SOURCE_URL", unset = EFFIS_DEFAULT_URL),
  firemap_source_url = Sys.getenv(
    "EFFIS_FIREMAP_SOURCE_URL",
    unset = FIREMAP_DEFAULT_URL
  ),
  output_dir = Sys.getenv("EFFIS_OUTPUT_DIR", unset = "data"),
  window_days = env_number("EFFIS_WINDOW_DAYS", 7),
  min_rows = env_number("EFFIS_MIN_ROWS", 10),
  timeout_seconds = env_number("EFFIS_TIMEOUT_SECONDS", 90),
  firemap_timeout_seconds = env_number(
    "EFFIS_FIREMAP_TIMEOUT_SECONDS",
    60
  ),
  firms_map_key = Sys.getenv("FIRMS_MAP_KEY", unset = ""),
  firms_sources = firms_sources_from_string(Sys.getenv(
    "FIRMS_SOURCES",
    unset = paste(FIRMS_DEFAULT_SOURCES, collapse = ",")
  )),
  firms_area = Sys.getenv("FIRMS_AREA", unset = FIRMS_DEFAULT_AREA),
  firms_recent_hours = env_number("FIRMS_RECENT_HOURS", 24),
  firms_cluster_degrees = env_number("FIRMS_CLUSTER_DEGREES", 0.1),
  firms_timeout_seconds = env_number("FIRMS_TIMEOUT_SECONDS", 90),
  page_size = env_number("EFFIS_PAGE_SIZE", 1000),
  reference_date = Sys.getenv("EFFIS_REFERENCE_DATE", unset = "")
) {
  if (!nzchar(reference_date)) {
    reference_date <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = EFFIS_TIMEZONE))
  } else {
    reference_date <- as.Date(reference_date)
  }
  if (is.na(reference_date)) {
    stop("EFFIS_REFERENCE_DATE moet YYYY-MM-DD zijn.", call. = FALSE)
  }

  window_days <- as.integer(window_days)
  if (window_days < 1L) {
    stop("EFFIS_WINDOW_DAYS moet minstens 1 zijn.", call. = FALSE)
  }
  from_date <- reference_date - (window_days - 1L)

  message(
    "EFFIS-gebieden ophalen van ", from_date,
    " tot en met ", reference_date, "..."
  )
  download <- download_effis_burnt_areas(
    source_url = source_url,
    from_date = from_date,
    to_date = reference_date,
    page_size = page_size,
    timeout_seconds = timeout_seconds
  )
  retrieved_at <- Sys.time()
  data <- parse_effis_records(
    download$results,
    retrieved_at = retrieved_at,
    reference_date = reference_date
  )
  validate_effis_data(data, min_rows = min_rows)

  message("Aanvullende FireMap-informatie ophalen...")
  firemap_enrichment <- download_firemap_enrichment(
    source_url = firemap_source_url,
    timeout_seconds = firemap_timeout_seconds
  )
  if (!isTRUE(firemap_enrichment$succeeded)) {
    message(
      "FireMap-verrijking niet beschikbaar; EFFIS-update gaat door: ",
      firemap_enrichment$error
    )
  }
  data <- enrich_effis_with_firemap(data, firemap_enrichment$data)
  download$firemap_enrichment <- firemap_enrichment

  message("Recente NASA FIRMS-satellietdetecties ophalen...")
  firms_hotspots <- tryCatch(
    download_firms_hotspots(
      map_key = firms_map_key,
      reference_date = reference_date,
      window_days = window_days,
      sources = firms_sources,
      area = firms_area,
      timeout_seconds = firms_timeout_seconds,
      retrieved_at = retrieved_at
    ),
    error = function(error) {
      list(
        data = NULL,
        clusters = NULL,
        succeeded = FALSE,
        record_count = 0L,
        cluster_count = 0L,
        source_url = FIRMS_SOURCE_PAGE,
        query_descriptions = character(),
        area = firms_area,
        sources = firms_sources,
        error = conditionMessage(error)
      )
    }
  )
  firms_hotspots$area <- firms_area
  firms_hotspots$sources <- firms_sources
  if (nzchar(firms_map_key) && !isTRUE(firms_hotspots$succeeded)) {
    stop(
      "FIRMS-update mislukt; de vorige geldige uitvoer blijft behouden: ",
      firms_hotspots$error,
      call. = FALSE
    )
  }

  firms_clusters <- data.frame()
  if (isTRUE(firms_hotspots$succeeded)) {
    firms_clusters <- cluster_firms_detections(
      firms_hotspots$data,
      retrieved_at = retrieved_at,
      recent_hours = firms_recent_hours,
      grid_degrees = firms_cluster_degrees
    )
    firms_hotspots$cluster_count_before_deduplication <- nrow(firms_clusters)
    firms_clusters <- remove_firms_clusters_near_effis(firms_clusters, data)
    firms_hotspots$cluster_count_before_static_filter <- nrow(firms_clusters)
    firms_clusters <- remove_likely_static_firms_clusters(firms_clusters)
    firms_hotspots$cluster_count <- nrow(firms_clusters)
    firms_hotspots$clusters <- firms_clusters

    firms_rows <- firms_clusters_to_rows(
      firms_clusters,
      retrieved_at_utc = format_utc(retrieved_at)
    )
    if (nrow(firms_rows) > 0L) {
      data <- rbind(data, firms_rows)
      rownames(data) <- NULL
    }
  } else {
    firms_hotspots$cluster_count_before_deduplication <- 0L
    message(firms_hotspots$error)
  }
  download$firms_hotspots <- firms_hotspots
  validate_effis_data(data, min_rows = min_rows)
  write_effis_outputs(data, download, output_dir)

  message(
    "Klaar: ", sum(data$data_type == "effis_brandgebied"),
    " EFFIS-brandgebieden en ", sum(data$data_type == "firms_hotspot"),
    " FIRMS-hotspotclusters weggeschreven naar ",
    normalizePath(output_dir, mustWork = TRUE), "; ",
    sum(data$firemap_available), " EFFIS-records gekoppeld aan FireMap."
  )
  invisible(data)
}
