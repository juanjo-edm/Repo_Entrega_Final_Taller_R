# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022–septiembre de 2026)
# SCRIPT: scripts/04_clustering_kmeans.R
# ROL: Agrupamiento Territorial de Criminalidad con K-Means (K* = 3)
# AUTORES: Grupo 10 — Taller de Programación en R (MECA, Uniandes)
# PRODUCE: data/processed/clusters_localidades_kmeans.parquet
#          output/tables/tabla_clustering_kmeans_perfiles.csv
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
library(cluster)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_clean    <- here("data", "processed")
ruta_salida_tablas  <- here("output", "tables")
ruta_salida_figuras <- here("output", "figures")

if (!dir.exists(ruta_salida_tablas)) {
  dir.create(ruta_salida_tablas, recursive = TRUE, showWarnings = FALSE)
}
if (!dir.exists(ruta_salida_figuras)) {
  dir.create(ruta_salida_figuras, recursive = TRUE, showWarnings = FALSE)
}

# 2. Preparación de Matriz de Tasas Estandarizadas ----

## 2.1 Carga del panel delictivo y selección de variables ----
archivo_panel <- file.path(
  ruta_datos_clean,
  "02_poblacion",
  "panel_delitos_poblacion_localidad.parquet"
)
panel_delitos <- read_parquet(archivo_panel)

stopifnot(nrow(panel_delitos) == 95)
stopifnot(length(unique(panel_delitos$codigo_localidad)) == 19)

## 2.2 Agregación promedio anual por localidad y estandarización (Z-score) ----
matriz_localidad <- panel_delitos |>
  group_by(codigo_localidad, localidad) |>
  summarise(
    tasa_personas_prom = mean(tasa_hurto_personas, na.rm = TRUE),
    tasa_resid_prom    = mean(tasa_hurto_residencias, na.rm = TRUE),
    tasa_motos_prom    = mean(tasa_hurto_motos, na.rm = TRUE),
    tasa_total_prom    = mean(tasa_hurto_total, na.rm = TRUE),
    poblacion_prom     = mean(poblacion, na.rm = TRUE),
    .groups = "drop"
  )

# Conversión de las 3 tasas delictivas a matriz numérica y normalización Z-score
mat_num <- matriz_localidad |>
  select(tasa_personas_prom, tasa_resid_prom, tasa_motos_prom) |>
  as.matrix()

rownames(mat_num) <- matriz_localidad$localidad
matriz_scale <- scale(mat_num)

stopifnot(all(abs(colMeans(matriz_scale)) < 1e-10))
stopifnot(all(abs(apply(matriz_scale, 2, sd) - 1) < 1e-10))

# 3. Diagnóstico del Número Óptimo de Clústeres (K = 2 a 5) ----

## 3.1 Evaluación por coeficiente de silueta promedio e inercia intra-clúster ----
dist_euclidea <- dist(matriz_scale)

diagnostico_k <- tibble(
  k             = 2:5,
  silueta_media = numeric(4),
  wss           = numeric(4)
)

for (i in seq_along(2:5)) {
  k_val <- (2:5)[i]
  set.seed(20261014)
  km_temp <- kmeans(matriz_scale, centers = k_val, nstart = 50)
  sil_temp <- silhouette(km_temp$cluster, dist_euclidea)
  diagnostico_k$silueta_media[i] <- round(mean(sil_temp[, 3]), 4)
  diagnostico_k$wss[i]           <- round(km_temp$tot.withinss, 4)
}

## 3.2 Selección del modelo óptimo (K* = 3) ----
k_optimo <- diagnostico_k$k[which.max(diagnostico_k$silueta_media)]
stopifnot(k_optimo == 3L)
message(
  ">>> Modelo óptimo seleccionado según coeficiente de silueta: K* = ",
  k_optimo,
  " (silueta = ",
  max(diagnostico_k$silueta_media),
  ")"
)

# 4. Estimación de K-Means y Asignación Determinística de Perfiles ----

## 4.1 Ajuste del modelo final con 50 reinicios ----
set.seed(20261014)
km_final <- kmeans(matriz_scale, centers = k_optimo, nstart = 50)
sil_final <- silhouette(km_final$cluster, dist_euclidea)

## 4.2 Identificación determinística de etiquetas por centroides ----
centroides_df <- as_tibble(km_final$centers) |>
  mutate(cluster_raw = row_number())

id_comercial <- centroides_df |>
  slice_max(tasa_motos_prom, n = 1) |>
  pull(cluster_raw)

id_centro <- centroides_df |>
  filter(cluster_raw != id_comercial) |>
  slice_max(tasa_personas_prom, n = 1) |>
  pull(cluster_raw)

id_residencial <- setdiff(1:3, c(id_comercial, id_centro))

df_clusters <- matriz_localidad |>
  mutate(
    cluster_raw = km_final$cluster,
    silueta_localidad = round(as.numeric(sil_final[, 3]), 4),
    cluster_id = case_when(
      cluster_raw == id_centro      ~ 1L,
      cluster_raw == id_comercial   ~ 2L,
      cluster_raw == id_residencial ~ 3L
    ),
    cluster_nombre = case_when(
      cluster_id == 1L ~ "Céntrico e Institucional",
      cluster_id == 2L ~ "Comercial y Automotor",
      cluster_id == 3L ~ "Residencial y Periférico"
    ),
    perfil_seguridad = case_when(
      cluster_id == 1L ~ "Alta criticidad en hurto a personas y residencias (núcleo céntrico)",
      cluster_id == 2L ~ "Alta concentración de hurto automotor y motocicletas (corredor comercial)",
      cluster_id == 3L ~ "Tasa per cápita moderada en zonas de alta densidad residencial"
    )
  ) |>
  select(-cluster_raw) |>
  arrange(cluster_id, desc(tasa_total_prom))

stopifnot(nrow(df_clusters) == 19)
stopifnot(length(unique(df_clusters$cluster_nombre)) == 3)

# 5. Exportación de Resultados y Tablas ----

## 5.1 Guardado de asignaciones en data/processed/ ----
archivo_salida_clusters <- file.path(
  ruta_datos_clean,
  "clusters_localidades_kmeans.parquet"
)
write_parquet(df_clusters, archivo_salida_clusters)

## 5.2 Exportación de tabla resumen de clústeres ----
archivo_tabla_clusters <- file.path(
  ruta_salida_tablas,
  "tabla_clustering_kmeans_perfiles.csv"
)
write_csv(df_clusters, archivo_tabla_clusters)

message("✔ Asignaciones de clustering guardadas en: ", archivo_salida_clusters)
message("✔ Tabla de perfiles exportada en: ", archivo_tabla_clusters)
