# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R
# ROL: Ingesta Oficial de Microdatos Mensuales SIEDCO y Cartografía (SDSCJ)
# FUENTE: Observatorio de Seguridad, Convivencia y Justicia (OAIEE / SDSCJ)
#         Microdatos SIEDCO: https://oaiee.scj.gov.co/DatosDescarga/SIEDCO.csv
#         Cartografía GeoJSON: Datos Abiertos Bogotá (dai_geojson.zip)
# PRODUCE: data/raw/delitos/SIEDCO.csv
#          data/raw/delitos/localidades_bogota_raw.geojson
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías y resolución de conflictos ----
library(here)
library(conflicted)
library(sf)
library(dplyr)
library(httr)
library(data.table)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.3 Rutas relativas de almacenamiento ----
ruta_raw_delitos <- here("data", "raw", "delitos")
archivo_siedco   <- file.path(ruta_raw_delitos, "SIEDCO.csv")
archivo_geojson  <- file.path(ruta_raw_delitos, "localidades_bogota_raw.geojson")

if (!dir.exists(ruta_raw_delitos)) {
  dir.create(ruta_raw_delitos, recursive = TRUE, showWarnings = FALSE)
}

# 2. Descarga Oficial de Microdatos Mensuales (SIEDCO.csv) y Cartografía ----

## 2.1 Descarga directa de SIEDCO.csv desde el Observatorio SCJ ----
url_siedco_csv <- "https://oaiee.scj.gov.co/DatosDescarga/SIEDCO.csv"
url_zip_sdscj  <- "https://datosabiertos.bogota.gov.co/dataset/7b270013-42ca-436b-9c1e-3bcb7d280c6b/resource/aba0e25d-d407-45f4-9a98-327493b538bd/download/dai_geojson.zip"

descargar_siedco_csv <- function() {
  resp <- GET(
    url_siedco_csv,
    user_agent("Mozilla/5.0"),
    write_disk(archivo_siedco, overwrite = TRUE),
    timeout(180)
  )
  if (status_code(resp) != 200) {
    stop("Error al descargar SIEDCO.csv (HTTP ", status_code(resp), ").")
  }
  message("✔ Microdatos SIEDCO.csv guardados en: ", archivo_siedco)
}

descargar_geojson <- function() {
  tmp_zip <- tempfile(fileext = ".zip")
  on.exit(unlink(tmp_zip), add = TRUE)

  resp <- GET(url_zip_sdscj, write_disk(tmp_zip, overwrite = TRUE), timeout(120))
  if (status_code(resp) != 200) {
    stop("Error al conectar con Datos Abiertos Bogotá (HTTP ", status_code(resp), ").")
  }

  tmp_dir <- tempfile()
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  unzip(tmp_zip, exdir = tmp_dir)
  archivos_geo <- list.files(tmp_dir, pattern = "\\.geojson$", full.names = TRUE)
  if (length(archivos_geo) == 0) {
    stop("No se encontró ningún archivo GeoJSON dentro del paquete ZIP descargado.")
  }

  delitos_sf <- st_read(archivos_geo[1], quiet = TRUE)
  st_write(delitos_sf, archivo_geojson, delete_dsn = TRUE, quiet = TRUE)
  message("✔ Capa cartográfica GeoJSON guardada en: ", archivo_geojson)
}

## 2.2 Ejecución controlada con caché local ----
message(">>> Verificando insumos crudos de delitos (SIEDCO mensual + GeoJSON)...")

if (!file.exists(archivo_siedco)) {
  tryCatch(descargar_siedco_csv(), error = function(e) {
    stop("Fallo en descarga de SIEDCO.csv: ", conditionMessage(e))
  })
} else {
  message("ℹ SIEDCO.csv ya existe en: ", archivo_siedco, ". Omitiendo descarga remota.")
}

if (!file.exists(archivo_geojson)) {
  tryCatch(descargar_geojson(), error = function(e) {
    stop("Fallo en descarga de GeoJSON SDSCJ: ", conditionMessage(e))
  })
} else {
  message("ℹ GeoJSON ya existe en: ", archivo_geojson, ". Omitiendo descarga remota.")
}

# 3. Verificación de Integridad y Diagnóstico ----

## 3.1 Comprobación de cobertura mensual 2022-2026 y geometrías ----
stopifnot(file.exists(archivo_siedco), file.exists(archivo_geojson))

siedco_head <- fread(archivo_siedco, sep = ";", encoding = "UTF-8", select = c("ANIO", "MES", "HECHO", "COD_LOCALIDAD"))
stopifnot(all(2022:2026 %in% unique(siedco_head$ANIO)))
stopifnot(9L %in% unique(siedco_head$MES[siedco_head$ANIO == 2026L]))
stopifnot(all(c("HURTO A PERSONAS", "HURTO A RESIDENCIAS", "HURTO MOTOCICLETAS") %in% unique(siedco_head$HECHO)))

delitos_geo <- st_read(archivo_geojson, quiet = TRUE)
stopifnot(nrow(delitos_geo) >= 20)

## 3.2 Reporte de auditoría en consola ----
tam_csv_mb <- round(file.info(archivo_siedco)$size / (1024^2), 2)
message("✔ Integridad verificada: SIEDCO.csv (", nrow(siedco_head), " registros, ", tam_csv_mb, " MB, corte sep-2026) y ", nrow(delitos_geo), " polígonos.")
