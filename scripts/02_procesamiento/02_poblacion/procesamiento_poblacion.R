# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/02_procesamiento/02_poblacion/procesamiento_poblacion.R
# ROL: Procesamiento Demográfico y Cálculo de Tasas de Criminalidad (SDS)
# ENTRA: data/raw/poblacion/poblacion_localidades_raw.parquet
#        data/processed/01_delitos/delitos_localidad_anual.parquet
# PRODUCE: data/processed/02_poblacion/panel_delitos_poblacion_localidad.parquet
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
library(stringr)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.3 Rutas relativas y directorios ----
ruta_raw_pob      <- here::here("data", "raw", "poblacion")
ruta_proc_delitos <- here::here("data", "processed", "01_delitos")
ruta_proc_pob     <- here::here("data", "processed", "02_poblacion")

archivo_pob_raw   <- file.path(ruta_raw_pob, "poblacion_localidades_raw.parquet")
archivo_delitos   <- file.path(ruta_proc_delitos, "delitos_localidad_anual.parquet")
archivo_salida    <- file.path(ruta_proc_pob, "panel_delitos_poblacion_localidad.parquet")

if (!dir.exists(ruta_proc_pob)) {
  dir.create(ruta_proc_pob, recursive = TRUE, showWarnings = FALSE)
}

# 2. Carga y Verificación de Insumos ----

## 2.1 Comprobación de existencia de datos de entrada ----
if (!file.exists(archivo_pob_raw)) {
  stop("No se encontró '", archivo_pob_raw, "'. Ejecute primero: source('scripts/01_ingesta/02_poblacion/descarga_poblacion_sds.R')")
}
if (!file.exists(archivo_delitos)) {
  stop("No se encontró '", archivo_delitos, "'. Ejecute primero: source('scripts/02_procesamiento/01_delitos/procesamiento_delitos.R')")
}

df_pob_raw    <- arrow::read_parquet(archivo_pob_raw)
panel_delitos <- arrow::read_parquet(archivo_delitos)

# 3. Procesamiento y Limpieza Demográfica ----

## 3.1 Agregación anual de habitantes y homologación territorial ----
poblacion_anual <- df_pob_raw |>
  rename(
    año = ANO,
    codigo_localidad = CODIGO_LOCALIDAD,
    localidad = NOMBRE_LOCALIDAD,
    poblacion = POBLACION
  ) |>
  filter(codigo_localidad != 0) |> # Excluir total consolidado de Bogotá
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

# 4. Integración de Población y Cálculo de Tasas ----

## 4.1 Fusión de delitos con población proyectada ----
panel_indicadores <- panel_delitos |>
  left_join(poblacion_anual |> select(codigo_localidad, año, poblacion), by = c("codigo_localidad", "año")) |>
  mutate(
    tasa_hurto_personas    = round((hurto_personas / poblacion) * 100000, 2),
    tasa_hurto_residencias = round((hurto_residencias / poblacion) * 100000, 2),
    tasa_hurto_motos       = round((hurto_motos / poblacion) * 100000, 2),
    tasa_hurto_total       = round(((hurto_personas + hurto_residencias + hurto_motos) / poblacion) * 100000, 2)
  )

# 5. Control de Calidad y Almacenamiento ----

## 5.1 Comprobación de integridad del panel (19 localidades x 5 años = 95 obs) ----
stopifnot(nrow(panel_indicadores) == 95)
stopifnot(length(unique(panel_indicadores$codigo_localidad)) == 19)
stopifnot(all(!is.na(panel_indicadores$tasa_hurto_personas)))

## 5.2 Exportación a Apache Parquet ----
arrow::write_parquet(panel_indicadores, archivo_salida)
message("✔ Panel de delitos y población guardado exitosamente en: ", archivo_salida)
