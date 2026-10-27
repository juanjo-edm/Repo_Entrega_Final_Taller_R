# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/01_ingesta/02_poblacion/descarga_poblacion_sds.R
# ROL: Ingesta Oficial de Proyecciones de Población por Localidad (SDS)
# PRODUCE: data/raw/poblacion/poblacion_localidades_raw.parquet
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías y resolución de conflictos ----
library(here)
library(conflicted)
library(httr)
library(jsonlite)
library(dplyr)
library(arrow)
library(readr)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.3 Rutas relativas de almacenamiento ----
ruta_raw_poblacion <- here::here("data", "raw", "poblacion")
ruta_salida        <- file.path(ruta_raw_poblacion, "poblacion_localidades_raw.parquet")

if (!dir.exists(ruta_raw_poblacion)) {
  dir.create(ruta_raw_poblacion, recursive = TRUE, showWarnings = FALSE)
}

# 2. Descarga de Proyecciones Demográficas ----

## 2.1 Consulta paginada a la API CKAN (datastore_search) ----
if (!file.exists(ruta_salida)) {
  message(">>> Iniciando descarga de proyecciones poblacionales SDS...")
  
  url_api <- "https://datosabiertos.bogota.gov.co/api/3/action"
  slug_dataset <- "piramide-poblacional-bogota-d-c"
  limite_pagina <- 30000
  
  poblacion_01_raw <- tryCatch({
    resp_ficha <- httr::GET(
      paste0(url_api, "/package_show"),
      query = list(id = slug_dataset),
      httr::timeout(60)
    )
    stopifnot(httr::status_code(resp_ficha) == 200)
    
    ficha <- jsonlite::fromJSON(
      httr::content(resp_ficha, as = "text", encoding = "UTF-8"),
      simplifyVector = FALSE
    )
    stopifnot(isTRUE(ficha$success))
    
    campo <- function(x, nombre) {
      if (is.null(x[[nombre]])) NA_character_ else as.character(x[[nombre]])
    }
    
    tabla_recursos <- tibble(
      id = sapply(ficha$result$resources, function(r) campo(r, "id")),
      nombre = sapply(ficha$result$resources, function(r) campo(r, "name")),
      formato = sapply(ficha$result$resources, function(r) campo(r, "format")),
      modificado = sapply(ficha$result$resources, function(r) campo(r, "last_modified")),
      datastore = sapply(ficha$result$resources, function(r) isTRUE(r$datastore_active))
    )
    
    candidatos <- tabla_recursos |>
      filter(datastore, formato == "CSV",
             grepl("Localidad", nombre, ignore.case = TRUE),
             !grepl("UPZ", nombre, ignore.case = TRUE))
    stopifnot(nrow(candidatos) >= 1)
    
    recurso_id <- candidatos |>
      arrange(desc(modificado)) |>
      slice(1) |>
      pull(id)
    
    pedir_pagina <- function(offset) {
      r <- httr::GET(
        paste0(url_api, "/datastore_search"),
        query = list(resource_id = recurso_id, limit = limite_pagina, offset = offset),
        httr::timeout(120)
      )
      stopifnot(httr::status_code(r) == 200)
      jsonlite::fromJSON(httr::content(r, as = "text", encoding = "UTF-8"))
    }
    
    primera <- pedir_pagina(0)
    total_filas <- primera$result$total
    bloques <- list(primera$result$records)
    offset <- limite_pagina
    while (offset < total_filas) {
      bloques[[length(bloques) + 1]] <- pedir_pagina(offset)$result$records
      offset <- offset + limite_pagina
    }
    bind_rows(bloques)
  }, error = function(e) {
    ## 2.2 Mecanismo de respaldo directo en CSV ----
    message("Aviso CKAN API: Descarga paginada falló. Usando recurso directo CSV de respaldo...")
    url_csv_respaldo <- "https://datosabiertos.bogota.gov.co/dataset/85bf790d-84d1-4eda-bd6f-40af62e71d95/resource/37e58cb3-c870-4608-8c37-ce45db0eb7c1/download/osb_demografia-poblacion-localidad.csv"
    readr::read_delim(url_csv_respaldo, delim = ";", show_col_types = FALSE)
  })
  
  ## 2.3 Materialización en Apache Parquet ----
  arrow::write_parquet(as.data.frame(poblacion_01_raw), ruta_salida)
  message("✔ Archivo de población guardado en: ", ruta_salida)
} else {
  message("ℹ Archivo de población ya existe en: ", ruta_salida, ". Omitiendo descarga remota.")
  poblacion_01_raw <- arrow::read_parquet(ruta_salida)
}

# 3. Verificación de Integridad y Diagnóstico ----

## 3.1 Comprobación de cobertura temporal (2005–2035) ----
stopifnot(file.exists(ruta_salida))
col_anio <- if ("ANO" %in% names(poblacion_01_raw)) "ANO" else "año"
col_loc  <- if ("CODIGO_LOCALIDAD" %in% names(poblacion_01_raw)) "CODIGO_LOCALIDAD" else "codigo_localidad"

anios_disponibles <- unique(poblacion_01_raw[[col_anio]])
stopifnot(all(2022:2026 %in% anios_disponibles))

## 3.2 Reporte de auditoría en consola ----
tamanio_kb <- round(file.info(ruta_salida)$size / 1024, 2)
message("✔ Integridad verificada: ", nrow(poblacion_01_raw), " filas, cobertura temporal ", min(anios_disponibles), " a ", max(anios_disponibles), " (", tamanio_kb, " KB).")
