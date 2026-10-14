# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# ROL: Ingesta de Datos Abiertos de Bogotá vía API Socrata / SoQL y Parquet
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
rm(list = ls())
options(scipen = 999)
set.seed(20261014)

## 1.2 Instalación y carga de librerías ----
librerias_requeridas <- c("here", "conflicted", "httr", "jsonlite", "arrow", "readr", "dplyr", "sf")
for (pkg in librerias_requeridas) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
}

library(here)
library(conflicted)
library(httr)
library(jsonlite)
library(arrow)
library(readr)
library(dplyr)
library(sf)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_raw   <- here::here("data", "raw")
ruta_datos_clean <- here::here("data", "processed")

if (!dir.exists(ruta_datos_raw)) dir.create(ruta_datos_raw, recursive = TRUE)

# 2. Funciones Auxiliares para Consultas SoQL en Socrata ----

## 2.1 Consulta HTTP con SoQL y paginación ----
# Realiza una petición GET con parámetros SoQL codificados y retorna un tibble
consultar_socrata_soql <- function(url_endpoint, select_query = "*", where_query = NULL, limit = 50000, app_token = NULL) {
  params <- list(
    `$select` = select_query,
    `$limit`  = limit
  )
  
  if (!is.null(where_query)) {
    params[["$where"]] <- where_query
  }
  
  headers <- list()
  if (!is.null(app_token)) {
    headers[["X-App-Token"]] <- app_token
  }
  
  message(paste0(">>> Ejecutando consulta SoQL en: ", url_endpoint))
  if (!is.null(where_query)) message(paste0("    Cláusula WHERE: ", where_query))
  
  respuesta <- httr::GET(
    url = url_endpoint,
    query = params,
    do.call(httr::add_headers, headers),
    httr::timeout(60)
  )
  
  if (httr::status_code(respuesta) != 200) {
    contenido_error <- httr::content(respuesta, as = "text", encoding = "UTF-8")
    stop(paste0("Error en la consulta Socrata (HTTP ", httr::status_code(respuesta), "): ", contenido_error))
  }
  
  contenido_json <- httr::content(respuesta, as = "text", encoding = "UTF-8")
  datos <- jsonlite::fromJSON(contenido_json, flatten = TRUE) |> tibble::as_tibble()
  
  message(paste0("✔ Registros recuperados: ", format(nrow(datos), big.mark = ",")))
  return(datos)
}

# 3. Ingesta: Delitos de Alto Impacto (SDSCJ / SIEDCO) ----

## 3.1 Consulta de hurtos 2022-2025 ----
# Endpoint del conjunto oficial de Datos Abiertos Bogotá
# Se filtran modalidades: personas, residencias y motocicletas para 2022-2025
archivo_delitos_parquet <- file.path(ruta_datos_raw, "delitos_alto_impacto_raw.parquet")

if (!file.exists(archivo_delitos_parquet)) {
  endpoint_delitos <- "https://datosabiertos.bogota.gov.co/resource/delito-alto-impacto.json"
  
  # Cláusula SoQL equivalente a SQL ANSI
  soql_where_delitos <- "anio >= '2022' AND anio <= '2025'"
  
  delitos_raw <- tryCatch({
    consultar_socrata_soql(
      url_endpoint = endpoint_delitos,
      select_query = "*",
      where_query  = soql_where_delitos,
      limit        = 100000
    )
  }, error = function(e) {
    warning("Aviso API Socrata: Conexión remota falló o endpoint cambió. Usando descarga directa de respaldo.")
    # Fallback mediante recurso directo CSV de Datos Abiertos Bogotá
    url_directa <- "https://datosabiertos.bogota.gov.co/dataset/delito-de-alto-impacto-bogota-d-c/resource/delitos.csv"
    readr::read_csv(url_directa, show_col_types = FALSE)
  })
  
  # Guardado en formato Apache Parquet
  arrow::write_parquet(delitos_raw, archivo_delitos_parquet)
  message(paste0("✔ Delitos guardados en: ", archivo_delitos_parquet))
} else {
  message("ℹ Archivo de delitos ya existe en disco. Omitiendo descarga.")
}

# 4. Ingesta: Proyecciones Poblacionales (SDS) ----

## 4.1 Consulta de proyecciones demográficas por localidad ----
# Fuente: Secretaría Distrital de Salud - Pirámide Poblacional 2005-2035
archivo_poblacion_parquet <- file.path(ruta_datos_raw, "poblacion_localidades_raw.parquet")

if (!file.exists(archivo_poblacion_parquet)) {
  endpoint_poblacion <- "https://datosabiertos.bogota.gov.co/resource/piramide-poblacional.json"
  
  poblacion_raw <- tryCatch({
    consultar_socrata_soql(
      url_endpoint = endpoint_poblacion,
      select_query = "*",
      where_query  = "anio >= '2022' AND anio <= '2025'",
      limit        = 50000
    )
  }, error = function(e) {
    # Fallback si no está el endpoint JSON activo
    url_csv_pob <- "https://datosabiertos.bogota.gov.co/dataset/piramide-poblacional-bogota-d-c/resource/poblacion.csv"
    readr::read_csv(url_csv_pob, show_col_types = FALSE)
  })
  
  arrow::write_parquet(poblacion_raw, archivo_poblacion_parquet)
  message(paste0("✔ Población guardada en: ", archivo_poblacion_parquet))
} else {
  message("ℹ Archivo de población ya existe en disco. Omitiendo descarga.")
}

# 5. Ingesta: Cartografía Vectorial de Localidades (SDP) ----

## 5.1 Geometrías de las 19 localidades urbanas ----
# Fuente: Secretaría Distrital de Planeación
archivo_localidades_geojson <- file.path(ruta_datos_raw, "localidades_bogota_raw.geojson")
archivo_localidades_parquet <- file.path(ruta_datos_raw, "localidades_bogota_raw.parquet")

if (!file.exists(archivo_localidades_geojson)) {
  url_geojson <- "https://datosabiertos.bogota.gov.co/dataset/localidad-bogota-d-c/resource/localidades.geojson"
  
  tryCatch({
    download.file(url_geojson, destfile = archivo_localidades_geojson, mode = "wb", quiet = TRUE)
    localidades_sf <- sf::st_read(archivo_localidades_geojson, quiet = TRUE)
    # Guardamos también atributos en Parquet (sin la columna geométrica pesada o como WKT)
    arrow::write_parquet(as.data.frame(localidades_sf |> sf::st_drop_geometry()), archivo_localidades_parquet)
    message(paste0("✔ Geometrías oficiales guardadas en: ", archivo_localidades_geojson))
  }, error = function(e) {
    warning("No se pudo descargar el GeoJSON en este intento. Verificar conexión.")
  })
} else {
  message("ℹ Archivo cartográfico de localidades ya existe en disco.")
}

# 6. Auditoría y Control de Salidas ----

## 6.1 Validación programática de artefactos Parquet ----
archivos_ingestados <- c(archivo_delitos_parquet, archivo_poblacion_parquet)
for (f in archivos_ingestados) {
  if (file.exists(f)) {
    tamanio_mb <- round(file.info(f)$size / (1024^2), 2)
    message(paste0("✔ Insumo Parquet verificado: ", basename(f), " (", tamanio_mb, " MB)"))
  }
}

message("\n=== Ingesta de Datos Abiertos completada exitosamente. ===")
