# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/05_export_insumos_shiny.R
# ROL: Consolidación y Empaquetado de Insumos para la Aplicación R Shiny
# AUTORES: Juan José Echeverry, Sergio López, Olga Lucía Ramírez (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE: data/processed/datos_consolidados_shiny.rds
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----
library(here)
library(conflicted)
library(arrow)
library(readr)
library(dplyr)
library(tidyr)
library(sf)
library(sentometrics)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_clean <- here::here("data", "processed")

# 2. Cruce y Armonización de Paneles Territoriales y K-Means ----

## 2.1 Carga del panel consolidado anual (delitos + población + sentimiento) ----
archivo_panel <- file.path(ruta_datos_clean, "panel_consolidado_localidad_anual.parquet")
panel_consolidado <- arrow::read_parquet(archivo_panel)

## 2.2 Fusión con asignaciones de clústeres K-Means ----
archivo_clusters <- file.path(ruta_datos_clean, "clusters_localidades_kmeans.parquet")
df_clusters <- arrow::read_parquet(archivo_clusters)

panel_con_clusters <- panel_consolidado |>
  select(-any_of(c("cluster_id", "cluster_nombre", "perfil_seguridad", "silueta_localidad"))) |>
  left_join(
    df_clusters |>
      select(codigo_localidad, cluster_id, cluster_nombre, perfil_seguridad, silueta_localidad),
    by = "codigo_localidad"
  )

# 3. Integración con Cartografía Vectorial (WGS84 para Leaflet) ----

## 3.1 Carga, homologación y transformación CRS de polígonos ----
archivo_geo <- here::here("data", "raw", "delitos", "localidades_bogota_raw.geojson")
if (file.exists(archivo_geo)) {
  geo_sf <- sf::st_read(archivo_geo, quiet = TRUE) |>
    filter(!CMIULOCAL %in% c("20", "99")) |>
    transmute(
      codigo_localidad = sprintf("%02d", as.integer(CMIULOCAL)),
      nombre_oficial   = CMNOMLOCAL
    ) |>
    sf::st_transform(crs = 4326)

  geo_simplificada <- sf::st_simplify(
    geo_sf,
    dTolerance       = 0.0005,
    preserveTopology = TRUE
  ) |>
    left_join(df_clusters, by = "codigo_localidad")
} else {
  geo_simplificada <- NULL
}

# 4. Carga de los 8 Artefactos S3 de Sentometrics (T-07 a T-17) ----

corpus_sento      <- readRDS(file.path(ruta_datos_clean, "01_sento_corpus.rds"))
lexicons_es       <- readRDS(file.path(ruta_datos_clean, "02_lexicons_es.rds"))
sentiment_scores  <- readRDS(file.path(ruta_datos_clean, "03_sentiment_scores.rds"))
peak_docs_obj     <- readRDS(file.path(ruta_datos_clean, "04_peak_docs.rds"))
measures_long_obj <- readRDS(file.path(ruta_datos_clean, "06_measures_long.rds"))
global_index_obj  <- readRDS(file.path(ruta_datos_clean, "07_global_index.rds"))
attributions_obj  <- readRDS(file.path(ruta_datos_clean, "08_attributions.rds"))

## 4.1 Estadísticos de evolución del corpus (T-08: corpus_summarize) ----
resumen_corpus_mes  <- suppressWarnings(sentometrics::corpus_summarize(corpus_sento, by = "month"))
resumen_corpus_anio <- suppressWarnings(sentometrics::corpus_summarize(corpus_sento, by = "year"))

## 4.2 Resumen de léxicos y modificadores de valencia (T-09 y T-10) ----
lexicos_info <- list(
  nrc_es             = as_tibble(lexicons_es$nrc_es),
  crimen_es          = as_tibble(lexicons_es$crimen_es),
  valence_shifters   = as_tibble(attr(lexicons_es, "valence_table_full")),
  comparacion_metodo = attr(sentiment_scores, "comparacion_metodologica")
)

# 5. Empaquetado y Serialización del Bundle Consolidado ----

bundle_shiny <- list(
  panel_localidades = panel_con_clusters,
  clusters_perfiles = df_clusters,
  geometrias        = geo_simplificada,
  corpus_stats_mes  = as_tibble(resumen_corpus_mes$stats),
  corpus_stats_anio = as_tibble(resumen_corpus_anio$stats),
  lexicos_info      = lexicos_info,
  peak_docs         = peak_docs_obj,
  measures_long     = as_tibble(measures_long_obj$long),
  global_index      = global_index_obj,
  attributions      = list(
    attr_long_raw   = as_tibble(attributions_obj$attr_long_raw),
    attr_long_norm  = as_tibble(attributions_obj$attr_long_norm),
    ajuste_temporal = attributions_obj$ajuste_temporal,
    coeficientes    = attributions_obj$coeficientes,
    metricas_modelo = attributions_obj$metricas_modelo
  ),
  fecha_generacion  = Sys.time(),
  horizonte         = "2022-2026"
)

archivo_bundle_rds <- file.path(ruta_datos_clean, "datos_consolidados_shiny.rds")
saveRDS(bundle_shiny, archivo_bundle_rds)

tamanio_mb <- round(file.info(archivo_bundle_rds)$size / (1024^2), 2)
message(
  "✔ Bundle de insumos para Shiny exportado exitosamente en: ",
  archivo_bundle_rds,
  " (",
  tamanio_mb,
  " MB)"
)
