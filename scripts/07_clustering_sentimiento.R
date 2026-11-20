# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022–septiembre de 2026)
# SCRIPT: scripts/07_clustering_sentimiento.R
# ROL: Clustering Territorial de Sentimiento (sentometrics) y Contraste vs. Hurtos
# AUTORES: Grupo 3 — Taller de Programación en R (MECA, Universidad de los Andes)
# PRODUCE: data/processed/clusters_sentimiento_kmeans.parquet
#          output/tables/tabla_clustering_sentimiento_perfiles.csv
#          output/tables/tabla_contraste_clusters_hurto_sentimiento.csv
#          output/tables/tabla_contingencia_hurto_vs_sentimiento.csv
#          output/figures/kmeans_mapa_hurto_vs_sentimiento.png
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----
library(here)       # Rutas relativas portables desde la raíz del proyecto
library(conflicted) # Resolución explícita de colisiones entre paquetes
library(arrow)      # Lectura y escritura eficiente en Apache Parquet
library(readr)      # Exportación de tablas en formato CSV
library(dplyr)      # Manipulación declarativa de datos (Tidyverse)
library(tidyr)      # Remodelado y limpieza de valores faltantes
library(purrr)      # Programación funcional sin bucles explícitos
library(recipes)    # Estandarización Z-score estilo tidymodels
library(cluster)    # Coeficientes de silueta S(i), PAM y AGNES Ward.D2
library(mclust)     # Adjusted Rand Index (ARI) para contraste de particiones
library(ggplot2)    # Visualización y mapas comparativos
library(ggrepel)    # Etiquetas territoriales sin solapamiento
library(patchwork)  # Composición de paneles lado a lado
library(sf)         # Geometrías vectoriales oficiales de Bogotá (WGS84)

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("first",  "dplyr", quiet = TRUE)
conflict_prefer("count",  "dplyr", quiet = TRUE)
conflict_prefer("map",    "purrr", quiet = TRUE)

## 1.4 Definición de rutas relativas ({here}) ----
ruta_datos_clean    <- here("data", "processed")
ruta_datos_raw      <- here("data", "raw")
ruta_salida_tablas  <- here("output", "tables")
ruta_salida_figuras <- here("output", "figures")

if (!dir.exists(ruta_salida_tablas)) {
  dir.create(ruta_salida_tablas, recursive = TRUE, showWarnings = FALSE)
}
if (!dir.exists(ruta_salida_figuras)) {
  dir.create(ruta_salida_figuras, recursive = TRUE, showWarnings = FALSE)
}

# 2. Carga de Insumos y Construcción del Perfil Territorial de Sentimiento ----

## 2.1 Lectura de noticias enriquecidas (993 objetivo) y clústeres de hurtos ----
# Los puntajes documentales score_nrc_es, score_crimen_es y sentimiento_score
# provienen exclusivamente del texto y los léxicos de sentometrics (sin usar la
# partición de hurtos), lo que garantiza cero circularidad al agrupar el tono.
archivo_noticias <- file.path(
  ruta_datos_clean,
  "03_noticias",
  "noticias_procesadas.parquet"
)
archivo_clusters_hurto <- file.path(
  ruta_datos_clean,
  "clusters_localidades_kmeans.parquet"
)

stopifnot(
  file.exists(archivo_noticias),
  file.exists(archivo_clusters_hurto)
)

noticias_objetivo <- read_parquet(archivo_noticias) |>
  filter(es_objetivo_3mod)

clusters_hurto <- read_parquet(archivo_clusters_hurto)

stopifnot(
  nrow(noticias_objetivo) == 993L,
  nrow(clusters_hurto) == 19L
)

## 2.2 Agregación de sentimiento puro y métricas mediáticas por localidad ----
perfil_sentimiento_loc <- noticias_objetivo |>
  group_by(localidad) |>
  summarise(
    n_docs_3mod = n(),
    sent_neto   = mean(sentimiento_score, na.rm = TRUE),
    sent_nrc    = mean(score_nrc_es, na.rm = TRUE),
    sent_crimen = mean(score_crimen_es, na.rm = TRUE),
    prop_neg    = mean(sentimiento_categoria == "Negativo", na.rm = TRUE) * 100,
    prop_pos    = mean(sentimiento_categoria == "Positivo", na.rm = TRUE) * 100,
    sent_sd     = sd(sentimiento_score, na.rm = TRUE),
    .groups     = "drop"
  )

# Cobertura y tono por modalidad para evaluar el espejo 3-mod (E) y control (F)
resumen_modalidad_loc <- noticias_objetivo |>
  group_by(localidad, delito_sdscj) |>
  summarise(
    n_notas = n(),
    s_mean  = mean(sentimiento_score, na.rm = TRUE),
    .groups = "drop"
  ) |>
  pivot_wider(
    names_from  = delito_sdscj,
    values_from = c(n_notas, s_mean),
    values_fill = list(n_notas = 0L)
  ) |>
  rename(
    n_noti_personas    = `n_notas_Hurto a personas`,
    n_noti_residencias = `n_notas_Hurto a residencias`,
    n_noti_motos       = `n_notas_Hurto de motocicletas`,
    sent_personas      = `s_mean_Hurto a personas`,
    sent_residencias   = `s_mean_Hurto a residencias`,
    sent_motos         = `s_mean_Hurto de motocicletas`
  )

matriz_sentimiento_loc <- clusters_hurto |>
  select(
    codigo_localidad,
    localidad,
    poblacion_prom,
    tasa_personas_prom,
    tasa_resid_prom,
    tasa_motos_prom,
    tasa_total_prom,
    cluster_hurto_id     = cluster_id,
    cluster_hurto_nombre = cluster_nombre,
    silueta_hurto        = silueta_localidad
  ) |>
  left_join(perfil_sentimiento_loc, by = "localidad") |>
  left_join(resumen_modalidad_loc, by = "localidad") |>
  mutate(
    tasa_noti_100k     = (n_docs_3mod / poblacion_prom) * 100000 / 5,
    tasa_noti_personas = (n_noti_personas / poblacion_prom) * 100000 / 5,
    tasa_noti_resid    = (n_noti_residencias / poblacion_prom) * 100000 / 5,
    tasa_noti_motos    = (n_noti_motos / poblacion_prom) * 100000 / 5
  ) |>
  arrange(codigo_localidad)

# Control de auditoría: exactamente 19 localidades completas en sentimiento puro
stopifnot(
  nrow(matriz_sentimiento_loc) == 19L,
  all(!is.na(matriz_sentimiento_loc$sent_nrc)),
  all(!is.na(matriz_sentimiento_loc$sent_crimen)),
  all(!is.na(matriz_sentimiento_loc$prop_neg))
)

# 3. Funciones Auxiliares de Estandarización, NMI y Mantel ----

## 3.1 Estandarización Z-score declarativa con {recipes} ----
escalar_zscore_recipes <- function(df_entrada, columnas) {
  receta_z <- recipe(~ ., data = df_entrada |> select(all_of(columnas))) |>
    step_normalize(all_numeric_predictors())

  matriz_z <- prep(receta_z) |>
    bake(new_data = NULL) |>
    as.matrix()

  rownames(matriz_z) <- df_entrada$localidad
  matriz_z
}

## 3.2 Información Mutua Normalizada (NMI) entre dos particiones ----
calcular_nmi <- function(particion_a, particion_b) {
  tabla_conj <- table(particion_a, particion_b)
  prob_conj  <- tabla_conj / sum(tabla_conj)
  prob_a     <- rowSums(prob_conj)
  prob_b     <- colSums(prob_conj)

  entropia_a <- -sum(prob_a[prob_a > 0] * log(prob_a[prob_a > 0]))
  entropia_b <- -sum(prob_b[prob_b > 0] * log(prob_b[prob_b > 0]))

  info_mutua <- 0
  for (i in seq_len(nrow(prob_conj))) {
    for (j in seq_len(ncol(prob_conj))) {
      if (prob_conj[i, j] > 0) {
        info_mutua <- info_mutua +
          prob_conj[i, j] * log(prob_conj[i, j] / (prob_a[i] * prob_b[j]))
      }
    }
  }

  info_mutua / sqrt(entropia_a * entropia_b)
}

## 3.3 Prueba de permutación de Mantel sobre matrices de distancia ----
calcular_mantel_permutacion <- function(dist_a, dist_b, n_perm = 9999L) {
  mat_a  <- as.matrix(dist_a)
  mat_b  <- as.matrix(dist_b)
  vec_a  <- mat_a[lower.tri(mat_a)]
  vec_b  <- mat_b[lower.tri(mat_b)]
  r_obs  <- stats::cor(vec_a, vec_b)

  set.seed(20261014)
  n_obs <- nrow(mat_a)
  r_perm <- replicate(n_perm, {
    idx <- sample.int(n_obs)
    stats::cor(vec_a, mat_b[idx, idx][lower.tri(mat_b)])
  })

  p_valor <- mean(abs(r_perm) >= abs(r_obs))
  list(r = r_obs, p = p_valor)
}

# 4. Clustering Principal de Sentimiento (Especificación A) y Contraste ----

## 4.1 Matriz Z-score de hurtos (referencia) y sentimiento puro (A) ----
vars_hurto     <- c("tasa_personas_prom", "tasa_resid_prom", "tasa_motos_prom")
vars_sent_puro <- c("sent_nrc", "sent_crimen", "prop_neg")

matriz_hurto_z <- escalar_zscore_recipes(matriz_sentimiento_loc, vars_hurto)
dist_hurto_z   <- stats::dist(matriz_hurto_z, method = "euclidean")

matriz_sent_z  <- escalar_zscore_recipes(matriz_sentimiento_loc, vars_sent_puro)
dist_sent_z    <- stats::dist(matriz_sent_z, method = "euclidean")

stopifnot(
  all(abs(colMeans(matriz_sent_z)) < 1e-10),
  all(abs(apply(matriz_sent_z, 2, sd) - 1) < 1e-10)
)

## 4.2 Ajuste K-Means (K = 2 óptimo por silueta y K = 3 comparación directa) ----
set.seed(20261014)
km_sent_k2 <- stats::kmeans(matriz_sent_z, centers = 2L, nstart = 50, iter.max = 100)
sil_sent_k2 <- cluster::silhouette(km_sent_k2$cluster, dist_sent_z)

set.seed(20261014)
km_sent_k3 <- stats::kmeans(matriz_sent_z, centers = 3L, nstart = 50, iter.max = 100)
sil_sent_k3 <- cluster::silhouette(km_sent_k3$cluster, dist_sent_z)

# Etiquetado determinístico de K = 3 según la posición de los centroides:
# 1) Mayor % de notas negativas y peor nrc_es -> "Tono muy adverso (doble léxico)"
# 2) De los restantes, crimen_es más negativo -> "Tono adverso criminológico"
# 3) Restante (menor negatividad por capturas) -> "Tono moderado (balance operativo)"
centroides_sent_k3 <- matriz_sentimiento_loc |>
  mutate(cluster_raw = km_sent_k3$cluster) |>
  group_by(cluster_raw) |>
  summarise(
    prop_neg_med    = mean(prop_neg),
    sent_nrc_med    = mean(sent_nrc),
    sent_crimen_med = mean(sent_crimen),
    .groups         = "drop"
  )

id_muy_adverso <- centroides_sent_k3 |>
  slice_max(prop_neg_med, n = 1, with_ties = FALSE) |>
  pull(cluster_raw)

id_criminologico <- centroides_sent_k3 |>
  filter(cluster_raw != id_muy_adverso) |>
  slice_min(sent_crimen_med, n = 1, with_ties = FALSE) |>
  pull(cluster_raw)

id_moderado <- setdiff(centroides_sent_k3$cluster_raw, c(id_muy_adverso, id_criminologico))

# Etiquetado determinístico de K = 2 según % de notas negativas
centroides_sent_k2 <- matriz_sentimiento_loc |>
  mutate(cluster_raw_k2 = km_sent_k2$cluster) |>
  group_by(cluster_raw_k2) |>
  summarise(prop_neg_med = mean(prop_neg), .groups = "drop")

id_k2_severo <- centroides_sent_k2 |>
  slice_max(prop_neg_med, n = 1, with_ties = FALSE) |>
  pull(cluster_raw_k2)

df_clusters_sentimiento <- matriz_sentimiento_loc |>
  mutate(
    cluster_sent_k2_id = if_else(km_sent_k2$cluster == id_k2_severo, 1L, 2L),
    cluster_sent_k2_nombre = if_else(
      cluster_sent_k2_id == 1L,
      "Tono severo",
      "Tono moderado"
    ),
    silueta_sent_k2 = round(as.numeric(sil_sent_k2[, 3]), 4),
    cluster_sent_id = case_when(
      km_sent_k3$cluster == id_muy_adverso   ~ 1L,
      km_sent_k3$cluster == id_criminologico ~ 2L,
      km_sent_k3$cluster == id_moderado      ~ 3L
    ),
    cluster_sent_nombre = case_when(
      cluster_sent_id == 1L ~ "Tono muy adverso (doble léxico)",
      cluster_sent_id == 2L ~ "Tono adverso criminológico",
      cluster_sent_id == 3L ~ "Tono moderado (balance operativo)"
    ),
    silueta_sentimiento = round(as.numeric(sil_sent_k3[, 3]), 4)
  ) |>
  arrange(cluster_sent_id, sent_neto)

stopifnot(
  nrow(df_clusters_sentimiento) == 19L,
  sum(df_clusters_sentimiento$silueta_sentimiento < 0) == 0L
)

## 4.3 Batería comparativa de 5 especificaciones (A, B, D, E y control F) ----
evaluar_especificacion_contraste <- function(df_base, codigo, etiqueta, vars, k_eval) {
  sub_df <- df_base |>
    select(localidad, cluster_hurto_id, cluster_hurto_nombre, all_of(vars_hurto), all_of(vars)) |>
    drop_na()

  mat_med <- escalar_zscore_recipes(sub_df, vars)
  dist_med <- stats::dist(mat_med, method = "euclidean")

  mat_hur_sub  <- escalar_zscore_recipes(sub_df, vars_hurto)
  dist_hur_sub <- stats::dist(mat_hur_sub, method = "euclidean")

  mantel_res <- calcular_mantel_permutacion(dist_hur_sub, dist_med, n_perm = 9999L)

  map_dfr(k_eval, function(k_val) {
    set.seed(20261014)
    km_fit  <- stats::kmeans(mat_med, centers = k_val, nstart = 50, iter.max = 100)
    sil_obj <- cluster::silhouette(km_fit$cluster, dist_med)
    pam_fit <- cluster::pam(dist_med, k = k_val)
    agn_fit <- stats::cutree(stats::as.hclust(cluster::agnes(dist_med, method = "ward")), k = k_val)

    tab_cont <- table(km_fit$cluster, sub_df$cluster_hurto_nombre)
    fisher_p <- stats::fisher.test(tab_cont)$p.value

    tibble(
      codigo             = codigo,
      especificacion     = etiqueta,
      localidades        = nrow(sub_df),
      k                  = k_val,
      silueta_media      = round(mean(sil_obj[, 3]), 4),
      siluetas_negativas = sum(sil_obj[, 3] < 0),
      ari_vs_hurtos      = round(mclust::adjustedRandIndex(km_fit$cluster, sub_df$cluster_hurto_id), 4),
      nmi_vs_hurtos      = round(calcular_nmi(km_fit$cluster, sub_df$cluster_hurto_id), 4),
      fisher_p           = round(fisher_p, 4),
      mantel_r           = round(mantel_res$r, 4),
      mantel_p           = round(mantel_res$p, 4),
      ari_km_vs_pam      = round(mclust::adjustedRandIndex(km_fit$cluster, pam_fit$clustering), 4),
      ari_km_vs_agnes    = round(mclust::adjustedRandIndex(km_fit$cluster, agn_fit), 4)
    )
  })
}

tabla_contraste_clusters <- bind_rows(
  evaluar_especificacion_contraste(
    matriz_sentimiento_loc,
    codigo   = "A",
    etiqueta = "Sentimiento puro (nrc_es + crimen_es + % neg.)",
    vars     = c("sent_nrc", "sent_crimen", "prop_neg"),
    k_eval   = c(2L, 3L)
  ),
  evaluar_especificacion_contraste(
    matriz_sentimiento_loc,
    codigo   = "B",
    etiqueta = "Dos léxicos puros (nrc_es + crimen_es)",
    vars     = c("sent_nrc", "sent_crimen"),
    k_eval   = c(2L, 3L)
  ),
  evaluar_especificacion_contraste(
    matriz_sentimiento_loc,
    codigo   = "D",
    etiqueta = "Sentimiento + tasa de cobertura (/100k hab.)",
    vars     = c("sent_nrc", "sent_crimen", "prop_neg", "tasa_noti_100k"),
    k_eval   = c(3L)
  ),
  evaluar_especificacion_contraste(
    matriz_sentimiento_loc,
    codigo   = "E",
    etiqueta = "Sentimiento por 3 modalidades (18 loc., Usme = NA)",
    vars     = c("sent_personas", "sent_residencias", "sent_motos"),
    k_eval   = c(2L, 3L)
  ),
  evaluar_especificacion_contraste(
    matriz_sentimiento_loc,
    codigo   = "F",
    etiqueta = "Control: tasas de cobertura 3 modalidades (/100k)",
    vars     = c("tasa_noti_personas", "tasa_noti_resid", "tasa_noti_motos"),
    k_eval   = c(3L)
  )
)

## 4.4 Matriz de contingencia 3 x 3 (Clústeres de hurtos vs. sentimiento) ----
orden_hurto <- c(
  "Céntrico e Institucional",
  "Comercial y Automotor",
  "Residencial y Periférico"
)
orden_sentimiento <- c(
  "Tono muy adverso (doble léxico)",
  "Tono adverso criminológico",
  "Tono moderado (balance operativo)"
)

tabla_contingencia <- df_clusters_sentimiento |>
  mutate(
    cluster_sent_nombre  = factor(cluster_sent_nombre, levels = orden_sentimiento),
    cluster_hurto_nombre = factor(cluster_hurto_nombre, levels = orden_hurto)
  ) |>
  count(cluster_sent_nombre, cluster_hurto_nombre, .drop = FALSE) |>
  pivot_wider(
    names_from  = cluster_hurto_nombre,
    values_from = n,
    values_fill = 0L
  ) |>
  mutate(
    Total = `Céntrico e Institucional` +
      `Comercial y Automotor` +
      `Residencial y Periférico`
  ) |>
  rename(`Clúster de sentimiento (K = 3)` = cluster_sent_nombre)

stopifnot(sum(tabla_contingencia$Total) == 19L)

# 5. Exportación de Artefactos Procesados y Tablas ----

## 5.1 Guardado de Parquet y tablas CSV ----
archivo_parquet_sent <- file.path(ruta_datos_clean, "clusters_sentimiento_kmeans.parquet")
archivo_csv_perfiles <- file.path(ruta_salida_tablas, "tabla_clustering_sentimiento_perfiles.csv")
archivo_csv_contraste <- file.path(ruta_salida_tablas, "tabla_contraste_clusters_hurto_sentimiento.csv")
archivo_csv_contingencia <- file.path(ruta_salida_tablas, "tabla_contingencia_hurto_vs_sentimiento.csv")

write_parquet(df_clusters_sentimiento, archivo_parquet_sent)
write_csv(df_clusters_sentimiento, archivo_csv_perfiles)
write_csv(tabla_contraste_clusters, archivo_csv_contraste)
write_csv(tabla_contingencia, archivo_csv_contingencia)

message("✔ Clústeres de sentimiento guardados en: ", archivo_parquet_sent)
message("✔ Tablas de contraste y contingencia guardadas en: ", ruta_salida_tablas)

# 6. Mapa Comparativo Lado a Lado: Clústeres de Hurtos vs. Sentimiento ----

## 6.1 Carga de polígonos oficiales y etiquetas sin solapamiento ----
archivo_geo <- file.path(ruta_datos_raw, "delitos", "localidades_bogota_raw.geojson")
stopifnot(file.exists(archivo_geo))

geo_contraste <- st_read(archivo_geo, quiet = TRUE) |>
  filter(!CMIULOCAL %in% c("20", "99")) |>
  mutate(codigo_localidad = sprintf("%02d", as.integer(CMIULOCAL))) |>
  left_join(df_clusters_sentimiento, by = "codigo_localidad") |>
  mutate(
    cluster_hurto_nombre = factor(cluster_hurto_nombre, levels = orden_hurto),
    cluster_sent_nombre  = factor(cluster_sent_nombre, levels = orden_sentimiento)
  )

pts_etiqueta <- suppressWarnings(st_point_on_surface(geo_contraste))
coords_etq   <- st_coordinates(pts_etiqueta)
geo_etiquetas <- st_drop_geometry(geo_contraste) |>
  mutate(lon = coords_etq[, 1], lat = coords_etq[, 2])

paleta_hurto <- c(
  "Céntrico e Institucional" = "#D97706",
  "Comercial y Automotor"    = "#B91C1C",
  "Residencial y Periférico" = "#1B365D"
)

paleta_sentimiento <- c(
  "Tono muy adverso (doble léxico)"   = "#991B1B",
  "Tono adverso criminológico"        = "#2563EB",
  "Tono moderado (balance operativo)" = "#0F766E"
)

fila_a3 <- tabla_contraste_clusters |> filter(codigo == "A", k == 3L)
fila_f3 <- tabla_contraste_clusters |> filter(codigo == "F", k == 3L)

tema_mapa_contraste <- theme_void(base_size = 9.5) +
  theme(
    legend.position = "bottom",
    legend.direction = "vertical",
    legend.title = element_text(face = "bold", size = 8.6),
    legend.text = element_text(size = 8.2),
    plot.title = element_text(face = "bold", size = 10.6, hjust = 0.5, color = "#0F172A"),
    plot.subtitle = element_text(size = 8.4, hjust = 0.5, color = "#475569", margin = margin(b = 6)),
    plot.margin = margin(8, 16, 6, 16)
  )

bbox_map <- st_bbox(geo_contraste)
x_pad    <- (bbox_map["xmax"] - bbox_map["xmin"]) * 0.48
xlim_map <- c(bbox_map["xmin"] - x_pad, bbox_map["xmax"] + x_pad)

p_mapa_hurto <- ggplot(geo_contraste) +
  geom_sf(aes(fill = cluster_hurto_nombre), color = "white", linewidth = 0.35) +
  geom_label_repel(
    data = geo_etiquetas,
    aes(x = lon, y = lat, label = localidad),
    size = 2.15, fontface = "bold", color = "#0F172A",
    fill = alpha("white", 0.90), label.size = 0.16,
    label.padding = unit(0.11, "lines"),
    box.padding = 0.24, point.padding = 0.10,
    force = 2.2,
    segment.color = "#475569", segment.size = 0.25,
    max.overlaps = Inf, seed = 20261014
  ) +
  coord_sf(xlim = xlim_map, expand = FALSE) +
  scale_fill_manual(values = paleta_hurto, name = "Perfil SIEDCO (hurtos)") +
  labs(
    title = "A. Clústeres de hurtos SIEDCO (K* = 3)",
    subtitle = "Silueta = 0,521 · 0 negativas (13 / 5 / 1)"
  ) +
  tema_mapa_contraste

p_mapa_sent <- ggplot(geo_contraste) +
  geom_sf(aes(fill = cluster_sent_nombre), color = "white", linewidth = 0.35) +
  geom_label_repel(
    data = geo_etiquetas,
    aes(x = lon, y = lat, label = localidad),
    size = 2.15, fontface = "bold", color = "#0F172A",
    fill = alpha("white", 0.90), label.size = 0.16,
    label.padding = unit(0.11, "lines"),
    box.padding = 0.24, point.padding = 0.10,
    force = 2.2,
    segment.color = "#475569", segment.size = 0.25,
    max.overlaps = Inf, seed = 20261014
  ) +
  coord_sf(xlim = xlim_map, expand = FALSE) +
  scale_fill_manual(values = paleta_sentimiento, name = "Perfil sentometrics (tono puro)") +
  labs(
    title = "B. Clústeres de sentimiento (K = 3)",
    subtitle = sprintf(
      "Silueta = %s · 0 negativas (10 / 6 / 3)",
      format(round(fila_a3$silueta_media, 3), decimal.mark = ",")
    )
  ) +
  tema_mapa_contraste

p_contraste_mapas <- (p_mapa_hurto | p_mapa_sent) +
  plot_annotation(
    title = "Contraste espacial: clústeres de hurtos (SIEDCO) vs. sentimiento mediático (sentometrics)",
    subtitle = sprintf(
      "Sentimiento puro vs. hurtos: ARI = %s, Fisher p = %s, Mantel r = %s (independientes) | Control cobertura/100k: ARI = +%s (p = %s)",
      format(round(fila_a3$ari_vs_hurtos, 3), decimal.mark = ","),
      format(round(fila_a3$fisher_p, 3), decimal.mark = ","),
      format(round(fila_a3$mantel_r, 3), decimal.mark = ","),
      format(round(fila_f3$ari_vs_hurtos, 3), decimal.mark = ","),
      format(round(fila_f3$fisher_p, 4), decimal.mark = ",")
    ),
    caption = "Fuente: SIEDCO (SDSCJ), SDS y sentometrics (993 notas objetivo, ene. 2022 - sept. 2026). K-Means Z-score ({recipes}, nstart = 50).",
    theme = theme(
      plot.title = element_text(face = "bold", size = 12.0, hjust = 0.5, color = "#0F172A"),
      plot.subtitle = element_text(size = 8.8, hjust = 0.5, color = "#334155", margin = margin(t = 2, b = 8)),
      plot.caption = element_text(size = 8.0, hjust = 0.5, color = "#64748B", margin = margin(t = 6)),
      plot.margin = margin(10, 12, 8, 12)
    )
  )

archivo_mapa_contraste <- file.path(ruta_salida_figuras, "kmeans_mapa_hurto_vs_sentimiento.png")
ggsave(
  archivo_mapa_contraste,
  p_contraste_mapas,
  width = 10.6,
  height = 6.8,
  dpi = 300,
  bg = "white"
)

message("✔ Mapa comparativo Hurtos vs. Sentimiento exportado en: ", archivo_mapa_contraste)
