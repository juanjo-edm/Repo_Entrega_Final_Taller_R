# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/05_export_insumos_shiny.R
# ROL: Consolidación y Exportación de Insumos para la Shiny App
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE: data/processed/datos_consolidados_shiny.rds
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Instalación y carga de librerías ----
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(sf)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_clean <- here::here("data", "processed")
ruta_app_data    <- here::here("app")

# 2. Cruce y Armonización de Paneles Procesados ----

## 2.1 Carga del panel consolidado (delitos + sentimiento) ----
archivo_panel <- file.path(ruta_datos_clean, "panel_consolidado_localidad_anual.parquet")
panel_consolidado <- arrow::read_parquet(archivo_panel)

## 2.2 Fusión con asignaciones de clústeres K-means ----
archivo_clusters <- file.path(ruta_datos_clean, "clusters_localidades_kmeans.parquet")
if (file.exists(archivo_clusters)) {
  df_clusters <- arrow::read_parquet(archivo_clusters)
  panel_con_clusters <- panel_consolidado |>
    left_join(df_clusters |> select(codigo_localidad, cluster_id, perfil_seguridad), by = "codigo_localidad")
} else {
  panel_con_clusters <- panel_consolidado |>
    mutate(cluster_id = 1L, perfil_seguridad = "General")
}

# 3. Integración con Cartografía Vectorial ----

## 3.1 Carga y simplificación de geometrías de localidades ----
archivo_geo <- here::here("data", "raw", "delitos", "localidades_bogota_raw.geojson")
if (file.exists(archivo_geo)) {
  geo_sf <- sf::st_read(archivo_geo, quiet = TRUE) |>
    filter(!CMIULOCAL %in% c("20", "99")) |>
    select(codigo_localidad = CMIULOCAL, nombre_oficial = CMNOMLOCAL) |>
    mutate(codigo_localidad = sprintf("%02d", as.integer(codigo_localidad)))
  
  # Simplificación topológica ligera para fluidez en Leaflet
  geo_simplificada <- sf::st_simplify(geo_sf, dTolerance = 0.001, preserveTopology = TRUE)
} else {
  geo_simplificada <- NULL
}

## 3.2 Unión de atributos espaciales y métricas de seguridad ----
bundle_shiny <- list(
  panel_localidades = panel_con_clusters,
  geometrias        = geo_simplificada,
  fecha_generacion  = Sys.time(),
  horizonte         = "2022-2026"
)

# 4. Exportación del Bundle Consolidado para Shiny ----

## 4.1 Serialización del artefacto optimizado (.rds) ----
archivo_bundle_rds <- file.path(ruta_datos_clean, "datos_consolidados_shiny.rds")
saveRDS(bundle_shiny, archivo_bundle_rds)

## 4.2 Reporte de integridad en consola ----
tamanio_mb <- round(file.info(archivo_bundle_rds)$size / (1024^2), 2)
message("✔ Bundle de insumos para Shiny exportado exitosamente en: ", archivo_bundle_rds, " (", tamanio_mb, " MB)")
