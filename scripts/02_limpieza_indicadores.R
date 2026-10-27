# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2025)
# SCRIPT: scripts/02_limpieza_indicadores.R
# ROL: Ingesta y Limpieza de Delitos, Población y Construcción de Panel
# ==============================================================================

options(scipen = 999)
set.seed(20261014)

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

ruta_raw_delitos   <- here::here("data", "raw", "delitos")
ruta_raw_poblacion <- here::here("data", "raw", "poblacion")
ruta_proc          <- here::here("data", "processed")

if (!dir.exists(ruta_proc)) dir.create(ruta_proc, recursive = TRUE)

# 1. Carga de Delitos de Alto Impacto Oficiales (SDSCJ) ----
archivo_geojson <- file.path(ruta_raw_delitos, "localidades_bogota_raw.geojson")
if (!file.exists(archivo_geojson)) {
  stop("No se encontró '", archivo_geojson, "'. Ejecute primero: source('scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R')")
}
delitos_sf <- sf::st_read(archivo_geojson, quiet = TRUE)
df_delitos_raw <- sf::st_drop_geometry(delitos_sf)

# 2. Carga de Población Proyectada (SDS) ----
archivo_pob_raw <- file.path(ruta_raw_poblacion, "poblacion_localidades_raw.parquet")
if (!file.exists(archivo_pob_raw)) {
  stop("No se encontró '", archivo_pob_raw, "'. Ejecute primero: source('scripts/01_ingesta/02_poblacion/descarga_poblacion_sds.R')")
}
df_pob_raw <- arrow::read_parquet(archivo_pob_raw)

# 3. Procesamiento y Limpieza de Población por Localidad y Año ----
poblacion_anual <- df_pob_raw |>
  rename(
    año = ANO,
    codigo_localidad = CODIGO_LOCALIDAD,
    localidad = NOMBRE_LOCALIDAD,
    poblacion = POBLACION
  ) |>
  filter(codigo_localidad != 0) |> # Excluir total Bogotá consolidado
  group_by(codigo_localidad, localidad, año) |>
  summarise(poblacion = sum(poblacion, na.rm = TRUE), .groups = "drop") |>
  mutate(
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

# 4. Procesamiento de Hurtos Oficiales 2022-2026 ----
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

df_personas <- extraer_modalidad(df_delitos_raw, "CMHP", "hurto_personas")
df_residencias <- extraer_modalidad(df_delitos_raw, "CMHR", "hurto_residencias")
df_motos <- extraer_modalidad(df_delitos_raw, "CMHM", "hurto_motos")

panel_delitos <- df_personas |>
  left_join(df_residencias, by = c("codigo_localidad", "localidad", "año")) |>
  left_join(df_motos, by = c("codigo_localidad", "localidad", "año")) |>
  filter(!codigo_localidad %in% c("20", "99")) # Excluir Sumapaz (rural) y Sin Localización

# 5. Fusión con Población y Cálculo de Tasas por 100k Habitantes ----
panel_indicadores <- panel_delitos |>
  left_join(poblacion_anual |> select(codigo_localidad, año, poblacion), by = c("codigo_localidad", "año")) |>
  mutate(
    tasa_hurto_personas    = round((hurto_personas / poblacion) * 100000, 2),
    tasa_hurto_residencias = round((hurto_residencias / poblacion) * 100000, 2),
    tasa_hurto_motos       = round((hurto_motos / poblacion) * 100000, 2),
    tasa_hurto_total       = round(((hurto_personas + hurto_residencias + hurto_motos) / poblacion) * 100000, 2)
  )

# Control de auditoría: 19 localidades x 5 años = 95 observaciones
stopifnot(nrow(panel_indicadores) == 95)
stopifnot(length(unique(panel_indicadores$codigo_localidad)) == 19)

ruta_hurtos_proc <- file.path(ruta_proc, "hurtos")
if (!dir.exists(ruta_hurtos_proc)) dir.create(ruta_hurtos_proc, recursive = TRUE)

archivo_panel_parquet <- file.path(ruta_hurtos_proc, "panel_delitos_poblacion_localidad.parquet")
arrow::write_parquet(panel_indicadores, archivo_panel_parquet)
message("✔ Panel de delitos y población guardado exitosamente en: ", archivo_panel_parquet)
