# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R
# ROL: Ingesta Oficial de Delitos de Alto Impacto y Cartografía (SDSCJ)
# PRODUCE: data/raw/delitos/localidades_bogota_raw.geojson
# ==============================================================================

# 1. Configuración y Dependencias ----
# rm(list = ls())
options(scipen = 999)
set.seed(20261014)

library(here)
library(conflicted)
library(sf)
library(dplyr)
library(httr)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.1 Rutas de salida ----
ruta_raw_delitos <- here::here("data", "raw", "delitos")
archivo_salida   <- file.path(ruta_raw_delitos, "localidades_bogota_raw.geojson")

if (!dir.exists(ruta_raw_delitos)) {
  dir.create(ruta_raw_delitos, recursive = TRUE, showWarnings = FALSE)
}

# 2. Descarga de Capa Oficial SDSCJ ----
url_zip_sdscj <- "https://datosabiertos.bogota.gov.co/dataset/7b270013-42ca-436b-9c1e-3bcb7d280c6b/resource/aba0e25d-d407-45f4-9a98-327493b538bd/download/dai_geojson.zip"

message(">>> Iniciando descarga de Delitos de Alto Impacto (SDSCJ)...")

descargar_delitos <- function() {
  tmp_zip <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp_zip), add = TRUE)
  
  resp <- httr::GET(url_zip_sdscj, httr::write_disk(tmp_zip, overwrite = TRUE), httr::timeout(120))
  if (httr::status_code(resp) != 200) {
    stop("Error al conectar con Datos Abiertos Bogotá (HTTP ", httr::status_code(resp), ").")
  }
  
  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  
  unzip(tmp_zip, exdir = tmp_dir)
  archivos_geo <- list.files(tmp_dir, pattern = "\\.geojson$", full.names = TRUE)
  if (length(archivos_geo) == 0) {
    stop("No se encontró ningún archivo GeoJSON dentro del paquete ZIP descargado.")
  }
  
  delitos_sf <- sf::st_read(archivos_geo[1], quiet = TRUE)
  sf::st_write(delitos_sf, archivo_salida, delete_dsn = TRUE, quiet = TRUE)
  message("✔ Archivo guardado correctamente en: ", archivo_salida)
}

if (!file.exists(archivo_salida)) {
  tryCatch({
    descargar_delitos()
  }, error = function(e) {
    stop("Fallo en la descarga de delitos SDSCJ: ", conditionMessage(e))
  })
} else {
  message("ℹ Archivo ya existe en: ", archivo_salida, ". Omitiendo descarga remota.")
}

# 3. Verificación de Integridad ----
stopifnot(file.exists(archivo_salida))
delitos_check <- sf::st_read(archivo_salida, quiet = TRUE)

# Comprobar presencia de columnas de 2026 y geometrías
cols_2026 <- grep("26CONT", names(delitos_check), value = TRUE)
stopifnot(length(cols_2026) > 0)
stopifnot("CMHP26CONT" %in% names(delitos_check))
stopifnot(nrow(delitos_check) >= 20)

tamanio_mb <- round(file.info(archivo_salida)$size / (1024^2), 2)
message("✔ Integridad verificada: ", nrow(delitos_check), " geometrías, corte temporal con ", length(cols_2026), " variables de 2026 (", tamanio_mb, " MB).")
