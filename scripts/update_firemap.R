#!/usr/bin/env Rscript

source(file.path("R", "firemap_pipeline.R"), encoding = "UTF-8")

tryCatch(
  run_firemap_pipeline(),
  error = function(error) {
    message("FireMap-update mislukt: ", conditionMessage(error))
    quit(status = 1L, save = "no")
  }
)
