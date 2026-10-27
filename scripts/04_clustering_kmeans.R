# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/04_clustering_kmeans.R
# ROL: Agrupamiento Territorial de Criminalidad con K-Means
# AUTORES: Juan José Echeverry, Miguelangel Palma, Sergio López (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE: data/processed/clusters_localidades_kmeans.parquet
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
library(tidyr)
library(cluster)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_clean    <- here::here("data", "processed")
ruta_salida_tablas  <- here::here("output", "tables")
ruta_salida_figuras <- here::here("output", "figures")

# 2. Preparación de Matriz de Tasas Estandarizadas ----

## 2.1 Carga del panel delictivo y selección de variables ----
archivo_panel <- file.path(ruta_datos_clean, "02_poblacion", "panel_delitos_poblacion_localidad.parquet")
panel_delitos <- arrow::read_parquet(archivo_panel)

## 2.2 Estandarización de tasas (z-score) ----
# Agregación promedio anual por localidad
matriz_localidad <- panel_delitos |>
  group_by(codigo_localidad, localidad) |>
  summarise(
    tasa_personas_prom = mean(tasa_hurto_personas, na.rm = TRUE),
    tasa_resid_prom    = mean(tasa_hurto_residencias, na.rm = TRUE),
    tasa_motos_prom    = mean(tasa_hurto_motos, na.rm = TRUE),
    .groups = "drop"
  )

matriz_scale <- scale(matriz_localidad |> select(starts_with("tasa_")))

# 3. Diagnóstico de Número Óptimo de Clústeres ----

## 3.1 Evaluación por método de silueta promedio (K = 2 a 5) ----
sil_scores <- sapply(2:5, function(k) {
  km <- kmeans(matriz_scale, centers = k, nstart = 25)
  ss <- cluster::silhouette(km$cluster, dist(matriz_scale))
  mean(ss[, 3])
})

## 3.2 Selección del modelo óptimo (K* = 3) ----
k_optimo <- 3L
message(">>> Modelo óptimo seleccionado según coeficiente de silueta: K = ", k_optimo)

# 4. Estimación de K-Means y Asignación de Perfiles ----

## 4.1 Ajuste del modelo final ----
km_final <- kmeans(matriz_scale, centers = k_optimo, nstart = 50)

## 4.2 Caracterización y perfilamiento de conglomerados ----
df_clusters <- matriz_localidad |>
  mutate(
    cluster_id = km_final$cluster,
    perfil_seguridad = case_when(
      cluster_id == 1 ~ "Alta criticidad en hurto a personas",
      cluster_id == 2 ~ "Moderada afectación residencial",
      cluster_id == 3 ~ "Baja tasa relativa general",
      TRUE ~ paste("Cluster", cluster_id)
    )
  )

# 5. Exportación de Resultados y Tablas ----

## 5.1 Guardado de asignaciones en Data Processed ----
archivo_salida_clusters <- file.path(ruta_datos_clean, "clusters_localidades_kmeans.parquet")
arrow::write_parquet(df_clusters, archivo_salida_clusters)

## 5.2 Exportación de tabla resumen de clusters ----
if (!dir.exists(ruta_salida_tablas)) dir.create(ruta_salida_tablas, recursive = TRUE)
archivo_tabla_clusters <- file.path(ruta_salida_tablas, "tabla_clustering_kmeans_perfiles.csv")
readr::write_csv(df_clusters, archivo_tabla_clusters)

message("✔ Asignaciones de clustering guardadas en: ", archivo_salida_clusters)
message("✔ Tabla de perfiles exportada en: ", archivo_tabla_clusters)
