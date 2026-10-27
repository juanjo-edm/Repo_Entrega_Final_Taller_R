# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/02_procesamiento/01_delitos/procesamiento_delitos.R
# ROL: Procesamiento y Estructuración de Delitos Oficiales SDSCJ (2022-2026)
# ENTRA: data/raw/delitos/localidades_bogota_raw.geojson
# PRODUCE: data/processed/01_delitos/delitos_localidad_anual.parquet
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías y resolución de conflictos ----
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(stringr)
library(sf)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.3 Rutas relativas y directorios ----
ruta_raw_delitos  <- here::here("data", "raw", "delitos")
ruta_proc_delitos <- here::here("data", "processed", "01_delitos")
archivo_geojson   <- file.path(ruta_raw_delitos, "localidades_bogota_raw.geojson")
archivo_salida    <- file.path(ruta_proc_delitos, "delitos_localidad_anual.parquet")

if (!dir.exists(ruta_proc_delitos)) {
  dir.create(ruta_proc_delitos, recursive = TRUE, showWarnings = FALSE)
}

# 2. Carga y Validación de Datos Crudos ----

## 2.1 Lectura de la capa oficial de delitos SDSCJ ----
if (!file.exists(archivo_geojson)) {
  stop("No se encontró '", archivo_geojson, "'. Ejecute primero: source('scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R')")
}
delitos_sf <- sf::st_read(archivo_geojson, quiet = TRUE)
df_delitos_raw <- sf::st_drop_geometry(delitos_sf)

# 3. Extracción y Normalización de Modalidades Delictivas ----

## 3.1 Función vectorizada para dinamizar variables anuales ----
extraer_modalidad <- function(df, prefijo, nombre_var) {
  anios <- 22:26
  cols <- paste0(prefijo, anios, "CONT")
  df |>
    select(codigo_localidad = CMIULOCAL, localidad = CMNOMLOCAL, all_of(cols)) |>
    pivot_longer(
      cols = starts_with(prefijo),
      names_to = "año",
      names_prefix = prefijo,
      values_to = nombre_var
    ) |>
    mutate(
      año = as.integer(str_remove(año, "CONT")) + 2000,
      codigo_localidad = sprintf("%02d", as.integer(codigo_localidad)),
      localidad = str_to_title(trimws(localidad)),
      localidad = case_when(
        localidad == "Usaquen" ~ "Usaquén",
        localidad == "San Cristobal" ~ "San Cristóbal",
        localidad == "Engativa" ~ "Engativá",
        localidad == "Fontibon" ~ "Fontibón",
        localidad == "Candelaria" ~ "La Candelaria",
        localidad == "Los Martires" ~ "Los Mártires",
        localidad == "Antonio Narino" ~ "Antonio Nariño",
        localidad == "Ciudad Bolivar" ~ "Ciudad Bolívar",
        TRUE ~ localidad
      )
    )
}

## 3.2 Extracción de hurtos a personas, residencias y motos ----
df_personas    <- extraer_modalidad(df_delitos_raw, "CMHP", "hurto_personas")
df_residencias <- extraer_modalidad(df_delitos_raw, "CMHR", "hurto_residencias")
df_motos       <- extraer_modalidad(df_delitos_raw, "CMHM", "hurto_motos")

# 4. Consolidación del Panel de Delitos ----

## 4.1 Fusión de modalidades y filtro de localidades urbanas ----
panel_delitos <- df_personas |>
  left_join(df_residencias, by = c("codigo_localidad", "localidad", "año")) |>
  left_join(df_motos, by = c("codigo_localidad", "localidad", "año")) |>
  filter(!codigo_localidad %in% c("20", "99")) # Excluir Sumapaz y Sin Localización

# 5. Almacenamiento y Control de Calidad ----

## 5.1 Verificación de dimensiones (19 localidades x 5 años) ----
stopifnot(nrow(panel_delitos) == 95)
stopifnot(length(unique(panel_delitos$codigo_localidad)) == 19)

## 5.2 Exportación a Apache Parquet ----
arrow::write_parquet(panel_delitos, archivo_salida)
message("✔ Panel de delitos anual guardado en: ", archivo_salida)
