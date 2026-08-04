# NASA FIRMS -> actuele satellietdetecties ----------------------------------

FIRMS_API_BASE_URL <- paste0(
  "https://firms.modaps.eosdis.nasa.gov/api/area/csv"
)
FIRMS_SOURCE_PAGE <- "https://firms.modaps.eosdis.nasa.gov/active_fire/"
FIRMS_SOURCE_LABEL <- "NASA FIRMS – actieve satellietdetecties"
FIRMS_DEFAULT_AREA <- "-25,25,45,72"
FIRMS_DEFAULT_SOURCES <- c(
  "VIIRS_NOAA21_NRT",
  "VIIRS_NOAA20_NRT"
)
FIRMS_MAX_API_DAYS <- 5L

FIRMS_MAP_COUNTRY_CODES <- c(
  Albania = "AL", Algeria = "DZ", Andorra = "AD", Armenia = "AM",
  Austria = "AT", Azerbaijan = "AZ", Belarus = "BY", Belgium = "BE",
  `Bosnia and Herzegovina` = "BA", Bulgaria = "BG", Croatia = "HR",
  Cyprus = "CY", `Czech Republic` = "CZ", Denmark = "DK", Estonia = "EE",
  Finland = "FI", France = "FR", Georgia = "GE", Germany = "DE",
  Greece = "GR", Hungary = "HU", Iceland = "IS", Ireland = "IE",
  Israel = "IL", Italy = "IT", Jordan = "JO", Latvia = "LV",
  Lebanon = "LB", Libya = "LY", Lithuania = "LT", Luxembourg = "LU",
  Macedonia = "MK", Malta = "MT", Moldova = "MD", Montenegro = "ME",
  Morocco = "MA", Netherlands = "NL", Norway = "NO", Poland = "PL",
  Portugal = "PT", Romania = "RO", Russia = "RU", Serbia = "RS",
  Slovakia = "SK", Slovenia = "SI", Spain = "ES", Sweden = "SE",
  Switzerland = "CH", Syria = "SY", Tunisia = "TN", Turkey = "TR",
  Ukraine = "UA", UK = "GB"
)

firms_sources_from_string <- function(value) {
  value <- trimws(as.character(value))
  if (!nzchar(value)) {
    return(FIRMS_DEFAULT_SOURCES)
  }
  sources <- trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
  sources[nzchar(sources)]
}

parse_firms_datetime <- function(date, time) {
  date <- as.character(date)
  time <- suppressWarnings(as.integer(as.character(time)))
  valid <- !is.na(date) & nzchar(date) & is.finite(time)
  result <- rep(as.POSIXct(NA, tz = "UTC"), length(date))
  result[valid] <- as.POSIXct(
    paste(date[valid], sprintf("%04d", time[valid])),
    format = "%Y-%m-%d %H%M",
    tz = "UTC"
  )
  result
}

read_firms_csv <- function(value, source) {
  text <- if (is.raw(value)) rawToChar(value) else as.character(value)
  if (length(text) != 1L || !nzchar(trimws(text))) {
    stop("FIRMS leverde een leeg CSV-bestand voor ", source, ".", call. = FALSE)
  }

  data <- tryCatch(
    utils::read.csv(
      text = text,
      stringsAsFactors = FALSE,
      check.names = FALSE,
      colClasses = "character"
    ),
    error = function(error) {
      stop("FIRMS leverde ongeldige CSV voor ", source, ".", call. = FALSE)
    }
  )
  required <- c(
    "latitude", "longitude", "acq_date", "acq_time", "satellite",
    "instrument", "confidence", "frp"
  )
  missing_columns <- setdiff(required, names(data))
  if (length(missing_columns) > 0L) {
    stop(
      "FIRMS-CSV voor ", source, " mist kolommen: ",
      paste(missing_columns, collapse = ", "), ".",
      call. = FALSE
    )
  }

  if (nrow(data) == 0L) {
    return(data.frame(
      latitude = numeric(), longitude = numeric(),
      acquired_at = as.POSIXct(character(), tz = "UTC"),
      satellite = character(), instrument = character(),
      confidence = character(), frp_mw = numeric(), daynight = character(),
      api_source = character(), stringsAsFactors = FALSE
    ))
  }

  data.frame(
    latitude = suppressWarnings(as.numeric(data$latitude)),
    longitude = suppressWarnings(as.numeric(data$longitude)),
    acquired_at = parse_firms_datetime(data$acq_date, data$acq_time),
    satellite = trimws(data$satellite),
    instrument = trimws(data$instrument),
    confidence = tolower(trimws(data$confidence)),
    frp_mw = suppressWarnings(as.numeric(data$frp)),
    daynight = if ("daynight" %in% names(data)) trimws(data$daynight) else NA_character_,
    api_source = source,
    stringsAsFactors = FALSE
  )
}

firms_confidence_is_usable <- function(value) {
  value <- tolower(trimws(as.character(value)))
  numeric_value <- suppressWarnings(as.numeric(value))
  textual <- value %in% c("n", "nominal", "h", "high")
  numeric <- is.finite(numeric_value) & numeric_value >= 30
  textual | numeric
}

filter_firms_detections <- function(data, from_date, to_date) {
  if (!is.data.frame(data) || nrow(data) == 0L) {
    return(data)
  }
  from_time <- as.POSIXct(paste(from_date, "00:00:00"), tz = "UTC")
  to_time <- as.POSIXct(paste(to_date, "23:59:59"), tz = "UTC")
  keep <- is.finite(data$latitude) & is.finite(data$longitude) &
    data$latitude >= -90 & data$latitude <= 90 &
    data$longitude >= -180 & data$longitude <= 180 &
    !is.na(data$acquired_at) & data$acquired_at >= from_time &
    data$acquired_at <= to_time &
    firms_confidence_is_usable(data$confidence)
  filtered <- data[keep, , drop = FALSE]
  if (nrow(filtered) == 0L) {
    return(filtered)
  }

  duplicate_key <- paste(
    sprintf("%.5f", filtered$latitude),
    sprintf("%.5f", filtered$longitude),
    format(filtered$acquired_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    filtered$satellite,
    filtered$instrument,
    sep = "|"
  )
  filtered[!duplicated(duplicate_key), , drop = FALSE]
}

firms_country_details <- function(longitude, latitude) {
  map_names <- maps::map.where("world", longitude, latitude)
  base_names <- sub(":.*$", "", map_names)
  codes <- unname(FIRMS_MAP_COUNTRY_CODES[base_names])
  country_names <- vapply(
    seq_along(base_names),
    function(index) {
      if (!is.na(codes[[index]])) {
        country_name_nl(codes[[index]])
      } else if (!is.na(base_names[[index]]) && nzchar(base_names[[index]])) {
        base_names[[index]]
      } else {
        "Onbekend land"
      }
    },
    character(1)
  )
  data.frame(
    country_code = codes,
    country_name = country_names,
    on_land = !is.na(map_names),
    stringsAsFactors = FALSE
  )
}

cluster_firms_detections <- function(
  data,
  retrieved_at = Sys.time(),
  recent_hours = 48,
  grid_degrees = 0.1
) {
  if (!is.data.frame(data) || nrow(data) == 0L) {
    return(data.frame())
  }
  if (!is.finite(recent_hours) || recent_hours < 1) {
    stop("FIRMS_RECENT_HOURS moet minstens 1 zijn.", call. = FALSE)
  }
  if (!is.finite(grid_degrees) || grid_degrees <= 0 || grid_degrees > 1) {
    stop("FIRMS_CLUSTER_DEGREES moet tussen 0 en 1 liggen.", call. = FALSE)
  }

  country <- firms_country_details(data$longitude, data$latitude)
  data <- data[country$on_land, , drop = FALSE]
  country <- country[country$on_land, , drop = FALSE]
  if (nrow(data) == 0L) {
    return(data.frame())
  }
  data$country_code <- country$country_code
  data$country_name <- country$country_name

  lat_cell <- floor((data$latitude + 90) / grid_degrees)
  lon_cell <- floor((data$longitude + 180) / grid_degrees)
  data$cluster_key <- paste(lat_cell, lon_cell, sep = "-")
  split_rows <- split(seq_len(nrow(data)), data$cluster_key)
  recent_cutoff <- as.POSIXct(retrieved_at, tz = "UTC") - recent_hours * 3600
  cutoff_24h <- as.POSIXct(retrieved_at, tz = "UTC") - 24 * 3600

  rows <- lapply(names(split_rows), function(key) {
    indices <- split_rows[[key]]
    part <- data[indices, , drop = FALSE]
    last_detection <- max(part$acquired_at)
    if (last_detection < recent_cutoff) {
      return(NULL)
    }
    country_name <- names(sort(table(part$country_name), decreasing = TRUE))[[1L]]
    country_codes <- part$country_code[part$country_name == country_name]
    country_codes <- country_codes[!is.na(country_codes)]
    country_code <- if (length(country_codes) == 0L) {
      NA_character_
    } else {
      names(sort(table(country_codes), decreasing = TRUE))[[1L]]
    }
    data.frame(
      cluster_id = paste0("firms-hs-", key),
      latitude = mean(part$latitude),
      longitude = mean(part$longitude),
      country_code = country_code,
      country_name = country_name,
      first_detection_utc = format_utc(min(part$acquired_at)),
      last_detection_utc = format_utc(last_detection),
      detections_24h = sum(part$acquired_at >= cutoff_24h),
      detections_7d = nrow(part),
      detection_days_7d = length(unique(as.Date(part$acquired_at, tz = "UTC"))),
      satellites = paste(sort(unique(part$satellite)), collapse = ", "),
      instruments = paste(sort(unique(part$instrument)), collapse = ", "),
      max_frp_mw = if (all(is.na(part$frp_mw))) NA_real_ else max(part$frp_mw, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) {
    return(data.frame())
  }
  clusters <- do.call(rbind, rows)
  rownames(clusters) <- NULL
  clusters[order(clusters$last_detection_utc, decreasing = TRUE), , drop = FALSE]
}

remove_likely_static_firms_clusters <- function(clusters) {
  if (!is.data.frame(clusters) || nrow(clusters) == 0L) {
    return(clusters)
  }
  likely_static <- clusters$detection_days_7d >= 3L &
    clusters$detections_7d >= 10L
  clusters[!likely_static, , drop = FALSE]
}

haversine_distance_km <- function(lon1, lat1, lon2, lat2) {
  radians <- pi / 180
  delta_lat <- (lat2 - lat1) * radians
  delta_lon <- (lon2 - lon1) * radians
  a <- sin(delta_lat / 2)^2 +
    cos(lat1 * radians) * cos(lat2 * radians) * sin(delta_lon / 2)^2
  6371.0088 * 2 * atan2(sqrt(a), sqrt(pmax(0, 1 - a)))
}

remove_firms_clusters_near_effis <- function(clusters, effis_data) {
  if (!is.data.frame(clusters) || nrow(clusters) == 0L ||
      !is.data.frame(effis_data) || nrow(effis_data) == 0L) {
    return(clusters)
  }

  effis_radius_km <- sqrt(pmax(effis_data$size_ha, 0) / (100 * pi)) + 5
  effis_radius_km[!is.finite(effis_radius_km)] <- 5
  effis_radius_km <- pmin(25, pmax(5, effis_radius_km))
  overlaps <- vapply(seq_len(nrow(clusters)), function(index) {
    distances <- haversine_distance_km(
      clusters$longitude[[index]], clusters$latitude[[index]],
      effis_data$longitude, effis_data$latitude
    )
    any(distances <= effis_radius_km)
  }, logical(1))
  clusters[!overlaps, , drop = FALSE]
}

firms_safe_query_description <- function(source, area, from_date, days) {
  paste0(
    FIRMS_API_BASE_URL, "/{MAP_KEY}/", source, "/", area, "/",
    as.integer(days), "/", as.character(from_date)
  )
}

download_firms_period <- function(
  map_key,
  source,
  area,
  from_date,
  days,
  timeout_seconds = 45,
  max_tries = 2L
) {
  request_url <- paste(
    FIRMS_API_BASE_URL,
    utils::URLencode(map_key, reserved = TRUE),
    source,
    area,
    as.integer(days),
    as.character(from_date),
    sep = "/"
  )
  response <- tryCatch(
    {
      request <- httr2::request(request_url) |>
        httr2::req_user_agent(paste0(
          "effis-firms-flourish-pipeline/1.0 ",
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
      httr2::req_perform(request)
    },
    error = function(error) {
      stop(
        "FIRMS kon ", source, " niet ophalen; de sleutel is niet gelogd.",
        call. = FALSE
      )
    }
  )
  read_firms_csv(httr2::resp_body_string(response), source)
}

download_firms_hotspots <- function(
  map_key,
  reference_date,
  window_days = 7L,
  sources = FIRMS_DEFAULT_SOURCES,
  area = FIRMS_DEFAULT_AREA,
  timeout_seconds = 45,
  max_tries = 2L,
  retrieved_at = Sys.time(),
  download_function = download_firms_period
) {
  if (!nzchar(map_key)) {
    return(list(
      data = NULL, clusters = NULL, succeeded = FALSE,
      record_count = 0L, cluster_count = 0L,
      source_url = FIRMS_SOURCE_PAGE,
      query_descriptions = character(),
      successful_sources = character(),
      failed_sources = character(),
      warnings = character(),
      error = "FIRMS is uitgeschakeld: FIRMS_MAP_KEY ontbreekt."
    ))
  }
  if (!grepl("^[A-Za-z0-9_-]{16,}$", map_key)) {
    stop("FIRMS_MAP_KEY heeft geen geldig formaat.", call. = FALSE)
  }

  reference_date <- as.Date(reference_date)
  window_days <- as.integer(window_days)
  if (is.na(reference_date) || window_days < 1L || window_days > 30L) {
    stop("Het FIRMS-datumbereik is ongeldig.", call. = FALSE)
  }
  sources <- unique(sources[nzchar(sources)])
  if (length(sources) == 0L) {
    stop("Er zijn geen FIRMS-sensorbronnen ingesteld.", call. = FALSE)
  }
  max_tries <- as.integer(max_tries)
  if (!is.finite(timeout_seconds) || timeout_seconds < 1 ||
      is.na(max_tries) || max_tries < 1L) {
    stop("De FIRMS-time-out of het aantal pogingen is ongeldig.", call. = FALSE)
  }

  period_start <- reference_date - (window_days - 1L)
  chunks <- list()
  chunk_start <- period_start
  while (chunk_start <= reference_date) {
    days <- min(FIRMS_MAX_API_DAYS, as.integer(reference_date - chunk_start) + 1L)
    chunks[[length(chunks) + 1L]] <- list(start = chunk_start, days = days)
    chunk_start <- chunk_start + days
  }

  downloads <- list()
  descriptions <- character()
  successful_sources <- character()
  failed_sources <- character()
  warnings <- character()
  for (source in sources) {
    source_downloads <- list()
    source_descriptions <- character()
    source_error <- tryCatch(
      {
        for (chunk in chunks) {
          source_downloads[[length(source_downloads) + 1L]] <- download_function(
            map_key = map_key,
            source = source,
            area = area,
            from_date = chunk$start,
            days = chunk$days,
            timeout_seconds = timeout_seconds,
            max_tries = max_tries
          )
          source_descriptions <- c(
            source_descriptions,
            firms_safe_query_description(source, area, chunk$start, chunk$days)
          )
        }
        NA_character_
      },
      error = function(error) conditionMessage(error)
    )

    if (is.na(source_error)) {
      downloads <- c(downloads, source_downloads)
      descriptions <- c(descriptions, source_descriptions)
      successful_sources <- c(successful_sources, source)
    } else {
      failed_sources <- c(failed_sources, source)
      warnings <- c(warnings, paste0(source, ": ", source_error))
    }
  }

  if (length(successful_sources) == 0L) {
    stop(
      "Geen enkele ingestelde FIRMS-sensorbron kon worden opgehaald.",
      call. = FALSE
    )
  }

  data <- do.call(rbind, downloads)
  rownames(data) <- NULL
  data <- filter_firms_detections(data, period_start, reference_date)
  list(
    data = data,
    clusters = NULL,
    succeeded = TRUE,
    record_count = nrow(data),
    cluster_count = 0L,
    source_url = FIRMS_SOURCE_PAGE,
    query_descriptions = descriptions,
    successful_sources = successful_sources,
    failed_sources = failed_sources,
    warnings = warnings,
    retrieved_at_utc = format_utc(retrieved_at),
    from_date = period_start,
    to_date = reference_date,
    error = NA_character_
  )
}
