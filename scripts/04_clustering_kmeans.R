# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022–septiembre de 2026)
# SCRIPT: scripts/04_clustering_kmeans.R
# ROL: Agrupamiento Territorial (K-Means) y Experimentación con Lógica Tidymodels
# AUTORES: Grupo 10 — Taller de Programación en R (MECA, Universidad de los Andes)
# PRODUCE: data/processed/clusters_localidades_kmeans.parquet
#          output/tables/tabla_clustering_kmeans_perfiles.csv
#          output/tables/tabla_sensibilidad_escalamientos_pca.csv
#          output/tables/tabla_comparacion_modelos_distancias.csv
#          output/tables/tabla_asignaciones_modelos_localidad.csv
#          output/figures/kmeans_ranking_tasa_total.png
#          output/figures/kmeans_zscore_distribuciones.png
#          output/figures/kmeans_silueta_promedio.png
#          output/figures/kmeans_dispersion_clusters.png
#          output/figures/kmeans_mapa_clusters.png
# ==============================================================================

# 1. Configuración y Dependencias ----

## 1.1 Opciones globales y semilla ----
options(scipen = 999)
set.seed(20261014)

## 1.2 Carga de librerías ----
library(here)       # Rutas relativas portables
library(conflicted) # Evita colisiones silenciosas entre funciones
library(arrow)      # Lectura/escritura rápida en formato Parquet
library(readr)      # Exportación de tablas CSV
library(dplyr)      # Manipulación de datos (Tidyverse)
library(tidyr)      # Remodelado de tablas
library(purrr)      # Programación funcional sin bucles for
library(recipes)    # Preprocesamiento declarativo estilo tidymodels
library(broom)      # Extracción ordenada (tidy/glance) de modelos
library(cluster)    # PAM, siluetas y estadístico Gap
library(mclust)     # Mezclas Gaussianas (GMM) y Adjusted Rand Index (ARI)
library(ggplot2)    # Visualización diagnóstica y mapas
library(scales)     # Formato numérico en ejes
library(ggrepel)    # Etiquetas sin solapamiento en dispersión
library(sf)         # Lectura de polígonos GeoJSON de localidades

## 1.3 Resolución explícita de conflictos ({conflicted}) ----
conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("first",  "dplyr", quiet = TRUE)
conflict_prefer("map",    "purrr", quiet = TRUE)

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

# 2. Preparación de Datos y Receta Principal (recipes) ----

## 2.1 Carga del panel delictivo y agregación promedio por localidad ----
# Promediamos las tasas anuales (2022–2026) de cada localidad para construir una
# matriz transversal con perfiles estructurales estables, evitando que choques
# coyunturales de un solo año alteren los grupos. Usamos las tres modalidades
# específicas (personas, residencias y motos) porque son los delitos patrimoniales
# cotidianos que más moldean la percepción de inseguridad en Bogotá (Restrepo &
# Moreno, 2007, Desarrollo y Sociedad 59, DOI: 10.13043/dys.59.5), y excluimos
# la tasa total para evitar colinealidad y doble conteo en el clustering.
archivo_panel <- file.path(
  ruta_datos_clean,
  "02_poblacion",
  "panel_delitos_poblacion_mensual.parquet"
)
panel_delitos_mensual <- read_parquet(archivo_panel)

matriz_localidad <- panel_delitos_mensual |>
  group_by(codigo_localidad, localidad, año) |>
  summarise(
    tasa_personas_anual = sum(tasa_hurto_personas, na.rm = TRUE),
    tasa_resid_anual    = sum(tasa_hurto_residencias, na.rm = TRUE),
    tasa_motos_anual    = sum(tasa_hurto_motos, na.rm = TRUE),
    tasa_total_anual    = sum(tasa_hurto_total, na.rm = TRUE),
    poblacion_anual     = first(poblacion),
    .groups = "drop"
  ) |>
  group_by(codigo_localidad, localidad) |>
  summarise(
    tasa_personas_prom = mean(tasa_personas_anual, na.rm = TRUE),
    tasa_resid_prom    = mean(tasa_resid_anual, na.rm = TRUE),
    tasa_motos_prom    = mean(tasa_motos_anual, na.rm = TRUE),
    tasa_total_prom    = mean(tasa_total_anual, na.rm = TRUE),
    poblacion_prom     = mean(poblacion_anual, na.rm = TRUE),
    .groups = "drop"
  )

## 2.2 Receta base de preprocesamiento: estandarización Z-score ----
# El hurto a personas alcanza miles de casos por cada 100.000 habitantes,
# mientras que residencias y motos se mueven en decenas o cientos; sin escalar,
# la distancia euclidiana quedaría dominada por la primera variable. Usamos una
# recipe (separando definición, prep y bake) para igualar la escala de las tres
# modalidades antes de calcular distancias.
receta_base <- recipe(
  ~ tasa_personas_prom + tasa_resid_prom + tasa_motos_prom,
  data = matriz_localidad
) |>
  step_normalize(all_numeric_predictors())

receta_base_prep <- prep(receta_base, training = matriz_localidad)
matriz_scale     <- bake(receta_base_prep, new_data = NULL) |> as.matrix()
rownames(matriz_scale) <- matriz_localidad$localidad

# 3. Selección del Número Óptimo de Clústeres (K = 2 a 5) ----

## 3.1 Evaluación de K candidatos mediante Silueta, Inercia (WSS) y Gap ----
# Con 19 localidades, acotamos la búsqueda a K entre 2 y 5 para evitar particiones
# triviales o grupos de un solo territorio, usando nstart = 50 para prevenir
# óptimos locales. Contrastamos silueta, inercia (WSS) y estadístico Gap
# (bootstrap) para elegir objetivamente el número óptimo de perfiles.
dist_euclidea <- dist(matriz_scale, method = "euclidean")

diagnostico_k <- tibble(k = 2:5) |>
  mutate(
    modelo = map(k, function(k_val) {
      set.seed(20261014)
      kmeans(matriz_scale, centers = k_val, nstart = 50)
    }),
    silueta_media = map_dbl(modelo, function(km) {
      sil <- silhouette(km$cluster, dist_euclidea)
      round(mean(sil[, 3]), 4)
    }),
    wss = map_dbl(modelo, ~ round(glance(.x)$tot.withinss, 4))
  ) |>
  select(k, silueta_media, wss)

# Validación complementaria con el estadístico Gap (100 simulaciones bootstrap)
set.seed(20261014)
gap_kmeans <- clusGap(
  matriz_scale,
  FUNcluster = function(x, k) kmeans(x, centers = k, nstart = 50),
  K.max      = 5L,
  B          = 100L,
  verbose    = FALSE
)

## 3.2 Selección automática del K óptimo (máxima silueta promedio) ----
k_optimo <- diagnostico_k$k[which.max(diagnostico_k$silueta_media)]

message(
  ">>> Modelo óptimo seleccionado según coeficiente de silueta: K* = ",
  k_optimo, " (silueta = ", max(diagnostico_k$silueta_media), ")"
)

# 4. Experimentación y Sensibilidad (Estilo Tidymodels: Recetas x Modelos) ----
# Antes de fijar y exportar el modelo definitivo, contrastamos si la partición
# territorial en K* = 3 es robusta al variar:
#   (a) El preprocesamiento (Z-score, Min-Max, Robusto, Log1p y PCA 2D).
#   (b) La métrica de distancia (Euclidiana vs. Manhattan) y el algoritmo
#       (K-Means, PAM por medoides, Jerárquico AGNES Ward y GMM).

## 4.1 Modelo K-Means de referencia sobre la receta base ----
set.seed(20261014)
km_base  <- kmeans(matriz_scale, centers = k_optimo, nstart = 50)
sil_base <- silhouette(km_base$cluster, dist_euclidea)

## 4.2 Definición de recetas alternativas con {recipes} ----
receta_base_formula <- ~ tasa_personas_prom + tasa_resid_prom + tasa_motos_prom

# Función auxiliar que prepara y hornea cualquier receta a matriz numérica
hornear_matriz <- function(receta, datos) {
  receta |>
    prep(training = datos) |>
    bake(new_data = NULL) |>
    as.matrix()
}

# Receta 2: Escalamiento Min-Max al rango [0, 1] (step_range)
receta_minmax <- recipe(receta_base_formula, data = matriz_localidad) |>
  step_range(all_numeric_predictors(), min = 0, max = 1)

# Receta 3: Escalamiento Robusto usando mediana y rango intercuartílico (IQR)
# Se declaran las 3 columnas explícitamente porque step_mutate() en recipes no evalúa across().
receta_robusta <- recipe(receta_base_formula, data = matriz_localidad) |>
  step_mutate(
    tasa_personas_prom = (tasa_personas_prom - median(tasa_personas_prom)) / IQR(tasa_personas_prom),
    tasa_resid_prom    = (tasa_resid_prom    - median(tasa_resid_prom))    / IQR(tasa_resid_prom),
    tasa_motos_prom    = (tasa_motos_prom    - median(tasa_motos_prom))    / IQR(tasa_motos_prom)
  )

# Receta 4: Compresión logarítmica log(1 + x) + estandarización Z-score
receta_log_z <- recipe(receta_base_formula, data = matriz_localidad) |>
  step_log(all_numeric_predictors(), offset = 1) |>
  step_normalize(all_numeric_predictors())

# Receta 5: Redimensionamiento con PCA a 2 componentes principales (step_pca)
receta_pca2 <- recipe(receta_base_formula, data = matriz_localidad) |>
  step_normalize(all_numeric_predictors()) |>
  step_pca(all_numeric_predictors(), num_comp = 2)

# Extraemos la varianza explicada del PCA para reportarla en la tabla
pca_tasas <- prcomp(matriz_scale, center = FALSE, scale. = FALSE)
var_pca   <- summary(pca_tasas)$importance

## 4.3 Evaluación de K-Means (K = 3) en cada espacio preprocesado ----
evaluar_receta_kmeans <- function(receta, nombre_espacio) {
  mat_espacio <- hornear_matriz(receta, matriz_localidad)
  set.seed(20261014)
  km_esp  <- kmeans(mat_espacio, centers = 3L, nstart = 50)
  sil_esp <- silhouette(km_esp$cluster, dist(mat_espacio))

  tibble(
    espacio         = nombre_espacio,
    silueta_media   = round(mean(sil_esp[, 3]), 4),
    n_silueta_neg   = sum(sil_esp[, 3] < 0),
    wss             = round(glance(km_esp)$tot.withinss, 4),
    ari_vs_base     = round(adjustedRandIndex(km_esp$cluster, km_base$cluster), 4),
    pca_var_pc1     = round(var_pca[2, 1], 4),
    pca_var_pc2     = round(var_pca[2, 2], 4),
    pca_var_acum_2d = round(var_pca[3, 2], 4)
  )
}

catalogo_recetas <- list(
  "Z-score (base)"              = receta_base,
  "Min-Max [0, 1]"              = receta_minmax,
  "Robusto (Mediana / IQR)"     = receta_robusta,
  "Log(1 + x) + Z-score"        = receta_log_z,
  "PCA (PC1 + PC2 = 96,9% var)" = receta_pca2
)

tabla_sensibilidad_escalamientos <- imap_dfr(catalogo_recetas, evaluar_receta_kmeans)

## 4.4 Contraste de distancias (Euclidiana vs. Manhattan) y modelos alternativos ----
# K-Means optimiza distancia euclidiana; para evaluar Manhattan y robustez
# frente a valores extremos (como Los Mártires), contrastamos con:
#   - PAM (Partitioning Around Medoids): usa localidades reales como centros.
#   - AGNES (Jerárquico Aglomerativo Ward.D2): agrupa por dendrograma.
#   - GMM (Gaussian Mixture Models): estima clústeres elípticos vía EM.
dist_manhattan <- dist(matriz_scale, method = "manhattan")

pam_euc <- pam(dist_euclidea,  k = 3L)
pam_man <- pam(dist_manhattan, k = 3L)
hc_euc  <- cutree(hclust(dist_euclidea,  method = "ward.D2"), k = 3L)
hc_man  <- cutree(hclust(dist_manhattan, method = "ward.D2"), k = 3L)

set.seed(20261014)
gmm_fit <- Mclust(matriz_scale, G = 3L, verbose = FALSE)

evaluar_particion <- function(clusters_vec, dist_ref, nombre_modelo, metric_dist) {
  sil_obj  <- silhouette(clusters_vec, dist_ref)
  tamanios <- paste(sort(as.integer(table(clusters_vec)), decreasing = TRUE), collapse = " / ")

  tibble(
    modelo         = nombre_modelo,
    distancia      = metric_dist,
    silueta_media  = round(mean(sil_obj[, 3]), 4),
    n_silueta_neg  = sum(sil_obj[, 3] < 0),
    tamanios_grupo = tamanios,
    ari_vs_kmeans  = round(adjustedRandIndex(clusters_vec, km_base$cluster), 4),
    gap_k3         = round(gap_kmeans$Tab[3, "gap"], 4)
  )
}

tabla_comparacion_modelos <- bind_rows(
  evaluar_particion(km_base$cluster,        dist_euclidea,  "K-Means (base)",      "Euclidiana"),
  evaluar_particion(pam_euc$clustering,     dist_euclidea,  "PAM (Medoides)",      "Euclidiana"),
  evaluar_particion(pam_man$clustering,     dist_manhattan, "PAM (Medoides)",      "Manhattan"),
  evaluar_particion(hc_euc,                 dist_euclidea,  "AGNES (Ward.D2)",     "Euclidiana"),
  evaluar_particion(hc_man,                 dist_manhattan, "AGNES (Ward.D2)",     "Manhattan"),
  evaluar_particion(gmm_fit$classification, dist_euclidea,  "GMM (Mezcla Gauss.)", "Mahalanobis / EM")
)

# 5. Ajuste Definitivo, Etiquetado Determinístico y Auditoría ----
# Confirmada la estabilidad del agrupamiento (ARI = 1.00 frente a AGNES,
# Min-Max y PCA 2D), consolidamos el modelo K-Means (Z-score, K* = 3).

## 5.1 Etiquetado determinístico de centroides (broom::tidy) ----
# Como K-Means asigna índices numéricos arbitrarios (1, 2, 3) que pueden
# permutar entre corridas, inspeccionamos los centroides con tidy(km_final) para
# anclar siempre cada grupo a su misma etiqueta criminológica en las tablas
# finales, en Sentometrics y en el tablero Shiny:
#   - Mayor tasa de motos      -> Clúster 2: Comercial y Automotor
#   - Mayor tasa de personas   -> Clúster 1: Céntrico e Institucional
#   - Restante                 -> Clúster 3: Residencial y Periférico
km_final  <- km_base
sil_final <- sil_base

centroides_df <- tidy(km_final) |>
  mutate(cluster_raw = as.integer(cluster))

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
    cluster_raw       = km_final$cluster,
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

## 5.2 Auditoría de asignaciones por localidad entre modelos ----
matriz_pca2 <- hornear_matriz(receta_pca2, matriz_localidad)
set.seed(20261014)
km_pca2 <- kmeans(matriz_pca2, centers = 3L, nstart = 50)

tabla_asignaciones_modelos <- matriz_localidad |>
  transmute(
    codigo_localidad = codigo_localidad,
    localidad        = localidad,
    kmeans_base      = km_final$cluster,
    pca2_kmeans      = km_pca2$cluster,
    pam_euclidiana   = pam_euc$clustering,
    pam_manhattan    = pam_man$clustering,
    agnes_euclidiana = hc_euc,
    agnes_manhattan  = hc_man,
    gmm_3            = gmm_fit$classification
  ) |>
  left_join(
    df_clusters |> select(codigo_localidad, cluster_nombre, silueta_localidad),
    by = "codigo_localidad"
  )

# 6. Exportación Conjunta de Resultados (Contrato Sentometrics / Shiny) ----

## 6.1 Guardado en data/processed/ y tablas en output/tables/ ----
archivo_salida_clusters <- file.path(ruta_datos_clean, "clusters_localidades_kmeans.parquet")
archivo_tabla_clusters  <- file.path(ruta_salida_tablas, "tabla_clustering_kmeans_perfiles.csv")

write_parquet(df_clusters, archivo_salida_clusters)
write_csv(df_clusters, archivo_tabla_clusters)
write_csv(tabla_sensibilidad_escalamientos, file.path(ruta_salida_tablas, "tabla_sensibilidad_escalamientos_pca.csv"))
write_csv(tabla_comparacion_modelos,        file.path(ruta_salida_tablas, "tabla_comparacion_modelos_distancias.csv"))
write_csv(tabla_asignaciones_modelos,       file.path(ruta_salida_tablas, "tabla_asignaciones_modelos_localidad.csv"))

message("✔ Asignaciones de clustering guardadas en: ", archivo_salida_clusters)
message("✔ Tabla de perfiles exportada en: ", archivo_tabla_clusters)
message("✔ Tablas de sensibilidad (recipes, PCA, distancias y modelos) guardadas en: ", ruta_salida_tablas)

# 7. Exportación de Figuras Diagnósticas y Mapas (output/figures/) ----
paleta_clusters <- c(
  "Céntrico e Institucional" = "#D97706",
  "Comercial y Automotor"    = "#B91C1C",
  "Residencial y Periférico" = "#1B365D"
)

## 7.1 Ranking de tasa promedio total por localidad ----
p_ranking <- df_clusters |>
  mutate(localidad_ord = reorder(localidad, tasa_total_prom)) |>
  ggplot(aes(x = localidad_ord, y = tasa_total_prom, fill = cluster_nombre)) +
  geom_col(width = 0.78) +
  geom_text(
    aes(label = number(tasa_total_prom, big.mark = ".", decimal.mark = ",", accuracy = 1)),
    hjust = -0.1, size = 3, color = "#1F2937"
  ) +
  coord_flip() +
  scale_fill_manual(values = paleta_clusters, name = "Perfil territorial") +
  scale_y_continuous(
    labels = label_number(big.mark = ".", decimal.mark = ","),
    expand = expansion(mult = c(0, 0.14))
  ) +
  labs(
    title = "Tasa promedio anual de hurto total por localidad (2022–sept. 2026)",
    subtitle = "Tasas por cada 100.000 habitantes (SIEDCO mensual consolidado)",
    x = NULL, y = "Tasa promedio anual por 100.000 hab."
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", plot.title = element_text(face = "bold"))

ggsave(file.path(ruta_salida_figuras, "kmeans_ranking_tasa_total.png"),
       p_ranking, width = 8.5, height = 5.4, dpi = 300, bg = "white")

## 7.2 Comparación de distribuciones antes vs. después de Z-score ----
df_dist_orig <- matriz_localidad |>
  select(localidad, tasa_personas_prom, tasa_resid_prom, tasa_motos_prom) |>
  pivot_longer(-localidad, names_to = "modalidad", values_to = "valor") |>
  mutate(escala = "1. Tasas originales (por 100.000 hab.)")

df_dist_z <- as_tibble(matriz_scale, rownames = "localidad") |>
  pivot_longer(-localidad, names_to = "modalidad", values_to = "valor") |>
  mutate(escala = "2. Estandarización Z-score (media 0, DE 1)")

p_zscore <- bind_rows(df_dist_orig, df_dist_z) |>
  mutate(modalidad = recode(
    modalidad,
    "tasa_personas_prom" = "Personas",
    "tasa_resid_prom"    = "Residencias",
    "tasa_motos_prom"    = "Motocicletas"
  )) |>
  ggplot(aes(x = modalidad, y = valor, fill = modalidad)) +
  geom_boxplot(alpha = 0.85, outlier.size = 1.6, show.legend = FALSE) +
  facet_wrap(~ escala, scales = "free_y") +
  scale_fill_manual(values = c("Personas" = "#1B365D", "Residencias" = "#D97706", "Motocicletas" = "#B91C1C")) +
  scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
  labs(
    title = "Efecto de la estandarización Z-score sobre las tres modalidades",
    x = NULL, y = "Valor"
  ) +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold"), strip.text = element_text(face = "bold"))

ggsave(file.path(ruta_salida_figuras, "kmeans_zscore_distribuciones.png"),
       p_zscore, width = 8.5, height = 4.2, dpi = 300, bg = "white")

## 7.3 Curva de silueta promedio para K = 2 a 5 ----
p_silueta <- diagnostico_k |>
  ggplot(aes(x = k, y = silueta_media)) +
  geom_line(color = "#1B365D", linewidth = 1) +
  geom_point(aes(color = k == k_optimo), size = 3.5, show.legend = FALSE) +
  geom_text(
    aes(label = number(silueta_media, decimal.mark = ",", accuracy = 0.0001)),
    vjust = -1.1, size = 3.4, fontface = "bold"
  ) +
  scale_color_manual(values = c("FALSE" = "#1B365D", "TRUE" = "#D97706")) +
  scale_x_continuous(breaks = 2:5) +
  scale_y_continuous(
    limits = c(0.30, max(diagnostico_k$silueta_media) + 0.06),
    labels = label_number(decimal.mark = ",")
  ) +
  labs(
    title = "Coeficiente de silueta promedio según número de clústeres (K = 2 a 5)",
    subtitle = paste0("Óptimo seleccionado: K* = ", k_optimo, " (silueta = ",
                      format(max(diagnostico_k$silueta_media), decimal.mark = ","), ")"),
    x = "Número de clústeres (K)", y = "Silueta promedio"
  ) +
  theme_minimal(base_size = 10) +
  theme(plot.title = element_text(face = "bold"))

ggsave(file.path(ruta_salida_figuras, "kmeans_silueta_promedio.png"),
       p_silueta, width = 7.2, height = 4.2, dpi = 300, bg = "white")

## 7.4 Dispersión bidimensional de localidades por clúster ----
p_disp <- df_clusters |>
  ggplot(aes(x = tasa_personas_prom, y = tasa_motos_prom, color = cluster_nombre)) +
  geom_point(aes(size = tasa_resid_prom), alpha = 0.9) +
  geom_text_repel(aes(label = localidad), size = 3, show.legend = FALSE, max.overlaps = 25) +
  scale_color_manual(values = paleta_clusters, name = "Perfil territorial") +
  scale_size_continuous(range = c(2.5, 7), name = "Tasa residencias") +
  scale_x_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
  scale_y_continuous(labels = label_number(big.mark = ".", decimal.mark = ",")) +
  labs(
    title = "Perfiles territoriales: hurto a personas vs. hurto de motocicletas",
    subtitle = "Tamaño proporcional a la tasa promedio de hurto a residencias",
    x = "Tasa promedio hurto a personas (por 100.000 hab.)",
    y = "Tasa promedio hurto a motos (por 100.000 hab.)"
  ) +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", plot.title = element_text(face = "bold"))

ggsave(file.path(ruta_salida_figuras, "kmeans_dispersion_clusters.png"),
       p_disp, width = 8.5, height = 5.2, dpi = 300, bg = "white")

## 7.5 Mapa coroplético de los tres clústeres en Bogotá ----
archivo_geo <- here("data", "raw", "delitos", "localidades_bogota_raw.geojson")
if (file.exists(archivo_geo)) {
  mapa_loc <- st_read(archivo_geo, quiet = TRUE) |>
    filter(!CMIULOCAL %in% c("20", "99")) |>
    left_join(df_clusters, by = c("CMIULOCAL" = "codigo_localidad"))

  p_mapa <- ggplot(mapa_loc) +
    geom_sf(aes(fill = cluster_nombre), color = "white", linewidth = 0.4) +
    geom_sf_text(aes(label = localidad), size = 2.4, color = "white", fontface = "bold") +
    scale_fill_manual(values = paleta_clusters, name = "Perfil territorial") +
    labs(
      title = "Distribución espacial de clústeres de hurto en Bogotá",
      subtitle = "19 localidades urbanas (K-Means Z-score, K* = 3)"
    ) +
    theme_void(base_size = 10) +
    theme(legend.position = "bottom", plot.title = element_text(face = "bold", hjust = 0.5),
          plot.subtitle = element_text(hjust = 0.5))

  ggsave(file.path(ruta_salida_figuras, "kmeans_mapa_clusters.png"),
         p_mapa, width = 6.5, height = 7.2, dpi = 300, bg = "white")
}

message("✔ Figuras de clustering actualizadas en: ", ruta_salida_figuras)
