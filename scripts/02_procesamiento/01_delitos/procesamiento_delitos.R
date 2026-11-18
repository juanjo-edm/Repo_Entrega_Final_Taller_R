# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/02_procesamiento/01_delitos/procesamiento_delitos.R
# ROL: Procesamiento Mensual de Microdatos SIEDCO (2022-sep. 2026)
# FUENTE: Observatorio de Seguridad, Convivencia y Justicia (OAIEE / SDSCJ)
#         https://oaiee.scj.gov.co/DatosDescarga/SIEDCO.csv
# ENTRA: data/raw/delitos/SIEDCO.csv
# PRODUCE: data/processed/01_delitos/delitos_localidad_mensual.parquet
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías y resolución de conflictos ----
library(here)
library(conflicted)
library(arrow)
library(data.table)
library(dplyr)
library(tidyr)
library(stringr)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.3 Rutas relativas y directorios ----
ruta_raw_delitos  <- here::here("data", "raw", "delitos")
ruta_proc_delitos <- here::here("data", "processed", "01_delitos")
archivo_siedco    <- file.path(ruta_raw_delitos, "SIEDCO.csv")
archivo_mensual   <- file.path(ruta_proc_delitos, "delitos_localidad_mensual.parquet")

if (!dir.exists(ruta_proc_delitos)) {
  dir.create(ruta_proc_delitos, recursive = TRUE, showWarnings = FALSE)
}

# 2. Carga y Validación de Microdatos Crudos ----

## 2.1 Lectura de SIEDCO.csv (2022-2026, 19 localidades urbanas) ----
if (!file.exists(archivo_siedco)) {
  stop("No se encontró '", archivo_siedco, "'. Ejecute primero: source('scripts/01_ingesta/01_delitos/descarga_delitos_sdscj.R')")
}

siedco_raw <- data.table::fread(
  archivo_siedco,
  sep = ";",
  encoding = "UTF-8",
  select = c("ANIO", "MES", "HECHO", "LOCALIDAD", "COD_LOCALIDAD", "CANTIDAD")
) |>
  as_tibble()

# Elegimos estas 3 modalidades entre los 12 hechos de SIEDCO porque son los delitos
# cotidianos de mayor exposición que más deterioran la percepción de inseguridad
# en Bogotá (Restrepo & Moreno, 2007, Desarrollo y Sociedad 59; CCB EPV; DANE ECSC).
modalidades_objetivo <- c(
  "HURTO A PERSONAS"    = "hurto_personas",
  "HURTO A RESIDENCIAS" = "hurto_residencias",
  "HURTO MOTOCICLETAS"  = "hurto_motos"
)

# 3. Agregación Mensual por Localidad y Homologación ----

## 3.1 Filtrado, estandarización de tildes y pivoteo mensual ----
df_siedco_filtrado <- siedco_raw |>
  filter(
    ANIO %in% 2022:2026,
    COD_LOCALIDAD %in% 1:19, # Excluir Sumapaz (20) y Sin Localización (99)
    HECHO %in% names(modalidades_objetivo)
  ) |>
  mutate(
    codigo_localidad = sprintf("%02d", as.integer(COD_LOCALIDAD)),
    año              = as.integer(ANIO),
    mes              = as.integer(MES),
    fecha_mes        = as.Date(sprintf("%04d-%02d-01", año, mes)),
    modalidad        = unname(modalidades_objetivo[HECHO]),
    localidad        = str_to_title(trimws(LOCALIDAD)),
    localidad        = case_when(
      localidad == "Usaquen"            ~ "Usaquén",
      localidad == "San Cristobal"      ~ "San Cristóbal",
      localidad == "Engativa"           ~ "Engativá",
      localidad == "Fontibon"           ~ "Fontibón",
      localidad %in% c("Candelaria", "La Candelaria") ~ "La Candelaria",
      localidad == "Los Martires"       ~ "Los Mártires",
      localidad == "Antonio Narino"     ~ "Antonio Nariño",
      localidad == "Ciudad Bolivar"     ~ "Ciudad Bolívar",
      TRUE                              ~ localidad
    )
  ) |>
  filter(fecha_mes <= as.Date("2026-09-01"))

catalogo_locs <- df_siedco_filtrado |>
  distinct(codigo_localidad, localidad) |>
  arrange(codigo_localidad)

malla_mensual <- expand_grid(
  codigo_localidad = catalogo_locs$codigo_localidad,
  fecha_mes        = seq.Date(as.Date("2022-01-01"), as.Date("2026-09-01"), by = "month")
) |>
  left_join(catalogo_locs, by = "codigo_localidad") |>
  mutate(
    año = as.integer(format(fecha_mes, "%Y")),
    mes = as.integer(format(fecha_mes, "%m"))
  )

conteos_mensuales <- df_siedco_filtrado |>
  group_by(codigo_localidad, fecha_mes, modalidad) |>
  summarise(casos = sum(CANTIDAD, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = modalidad, values_from = casos, values_fill = 0L)

panel_delitos_mensual <- malla_mensual |>
  left_join(conteos_mensuales, by = c("codigo_localidad", "fecha_mes")) |>
  mutate(
    hurto_personas    = coalesce(as.integer(hurto_personas), 0L),
    hurto_residencias = coalesce(as.integer(hurto_residencias), 0L),
    hurto_motos       = coalesce(as.integer(hurto_motos), 0L)
  ) |>
  select(
    codigo_localidad, localidad, año, mes, fecha_mes,
    hurto_personas, hurto_residencias, hurto_motos
  ) |>
  arrange(codigo_localidad, fecha_mes)

# 4. Almacenamiento y Control de Calidad ----

## 4.1 Verificación de dimensiones (19 localidades x 57 meses = 1.083 filas) ----
stopifnot(nrow(panel_delitos_mensual) == 19L * 57L)
stopifnot(length(unique(panel_delitos_mensual$codigo_localidad)) == 19L)

## 4.2 Exportación a Apache Parquet ----
arrow::write_parquet(panel_delitos_mensual, archivo_mensual)
message("✔ Panel mensual guardado en: ", archivo_mensual, " (", nrow(panel_delitos_mensual), " filas)")
