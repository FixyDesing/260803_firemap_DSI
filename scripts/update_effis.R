#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")
source(file.path("R", "effis_pipeline.R"), encoding = "UTF-8")

tryCatch(
  run_effis_pipeline(),
  error = function(error) {
    message("EFFIS-update mislukt: ", conditionMessage(error))
    quit(status = 1L, save = "no")
  }
)
