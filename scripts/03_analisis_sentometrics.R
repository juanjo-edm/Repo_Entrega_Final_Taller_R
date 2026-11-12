# ==============================================================================
# PROYECTO: Hurtos y Sentimiento Mediático en Bogotá (2022-2026)
# SCRIPT: scripts/03_analisis_sentometrics.R
# ROL: Pipeline Integral de Sentometrics (Fases 1 a 4: T-01 a T-17) y Panel
# AUTORES: Juan José Echeverry, Sergio López, Olga Lucía Ramírez (Grupo 10)
# PROGRAMA: Maestría en Economía Aplicada (MECA) — Universidad de los Andes
# PRODUCE:
#   - data/processed/01_sento_corpus.rds
#   - data/processed/02_lexicons_es.rds
#   - data/processed/03_sentiment_scores.rds
#   - data/processed/04_peak_docs.rds
#   - data/processed/05_sento_measures.rds
#   - data/processed/06_measures_long.rds
#   - data/processed/07_global_index.rds
#   - data/processed/08_attributions.rds
#   - data/processed/panel_consolidado_localidad_anual.parquet
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
library(stringi)
library(data.table)
library(syuzhet)
library(sentometrics)
library(glmnet)

conflict_prefer("filter", "dplyr", quiet = TRUE)
conflict_prefer("lag",    "dplyr", quiet = TRUE)
conflict_prefer("select", "dplyr", quiet = TRUE)
conflict_prefer("first",  "dplyr", quiet = TRUE)

## 1.3 Rutas relativas ----
ruta_proc          <- here::here("data", "processed")
archivo_noticias   <- file.path(ruta_proc, "03_noticias", "noticias_procesadas.parquet")
archivo_delitos    <- file.path(ruta_proc, "02_poblacion", "panel_delitos_poblacion_localidad.parquet")
archivo_clusters   <- file.path(ruta_proc, "clusters_localidades_kmeans.parquet")

stopifnot(file.exists(archivo_noticias))
stopifnot(file.exists(archivo_delitos))

# 2. Fase 1: Corpus y Construcción de Features (T-05, T-06, T-07) ----

## 2.1 Carga de noticias depuradas y clústeres K-Means ----
df_noticias <- arrow::read_parquet(archivo_noticias)
panel_delitos <- arrow::read_parquet(archivo_delitos)

if (!file.exists(archivo_clusters)) {
  source(here::here("scripts", "04_clustering_kmeans.R"), local = new.env())
}
df_clusters <- arrow::read_parquet(archivo_clusters)

## 2.2 Función de normalización a snake_case sin guiones medios ('-') ----
normalizar_nombre_feature <- function(x) {
  x |>
    stringi::stri_trans_general("Latin-ASCII") |>
    str_to_lower() |>
    str_replace_all("[\\s\\-]+", "_") |>
    str_replace_all("[^a-z0-9_]", "")
}

## 2.3 Construcción de textos e indicadores binarios [0, 1] (Localidades, Clústeres, Temas) ----
df_base_corpus <- df_noticias |>
  select(-any_of(c("cluster_id", "cluster_nombre", "perfil_seguridad"))) |>
  left_join(
    df_clusters |> select(localidad, cluster_id, cluster_nombre),
    by = "localidad"
  ) |>
  mutate(
    id    = paste0("doc_", row_number()),
    date  = as.Date(fecha),
    texts = str_squish(paste(
      coalesce(titulo, ""),
      coalesce(resumen, ""),
      str_sub(coalesce(cuerpo, ""), 1, 800),
      sep = ". "
    )),
    txt_norm = stringi::stri_trans_general(str_to_lower(texts), "Latin-ASCII"),
    # 3 features de clústeres K-Means
    c_centro      = as.numeric(cluster_nombre == "Céntrico e Institucional"),
    c_comercial   = as.numeric(cluster_nombre == "Comercial y Automotor"),
    c_residencial = as.numeric(cluster_nombre == "Residencial y Periférico"),
    # 4 features temáticas y de modalidades DAI (SDSCJ)
    tema_hurto_personas = as.numeric(
      delito_sdscj == "Hurto a personas" |
        str_detect(txt_norm, "\\b(transmilenio|sitp|peaton|transeunte|celular|raponazo|cosquilleo|fleteo|escopolamina)\\b")
    ),
    tema_hurto_patrimonial = as.numeric(
      delito_sdscj %in% c(
        "Hurto a residencias", "Hurto a comercio", "Hurto de automotores",
        "Hurto de motocicletas", "Hurto a entidades financieras",
        "Hurto (modalidad no identificada)"
      )
    ),
    tema_violencia_vida = as.numeric(
      delito_sdscj %in% c(
        "Homicidio", "Lesiones personales", "Extorsión",
        "Delitos sexuales", "Violencia intrafamiliar"
      )
    ),
    tema_institucional = as.numeric(
      modalidad_dai %in% c("nodai_operatividad", "nodai_politica_seguridad") |
        str_detect(txt_norm, "\\b(captur|desarticul|operativ|patrullaj|incaut|megatoma|secretaria de seguridad|policia)\\b")
    )
  )

# Añadir las 19 features binarias por localidad (prefijo loc_ sin guiones '-')
localidades_unicas <- sort(unique(df_base_corpus$localidad))
nombres_feat_loc   <- character(length(localidades_unicas))

for (i in seq_along(localidades_unicas)) {
  loc_actual <- localidades_unicas[i]
  col_feat   <- paste0("loc_", normalizar_nombre_feature(loc_actual))
  nombres_feat_loc[i] <- col_feat
  df_base_corpus[[col_feat]] <- as.numeric(df_base_corpus$localidad == loc_actual)
}

cols_features <- c(
  "c_centro", "c_comercial", "c_residencial",
  "tema_hurto_personas", "tema_hurto_patrimonial",
  "tema_violencia_vida", "tema_institucional",
  nombres_feat_loc
)

# Auditoría estricta de contrato T-01 / T-07: cero guiones '-' y cero NAs
stopifnot(!any(str_detect(cols_features, "-")))
stopifnot(all(!is.na(df_base_corpus$date)))
stopifnot(all(!is.na(df_base_corpus$texts)))

## 2.4 Creación y guardado del objeto S3 sento_corpus (T-07) ----
df_sento_input <- df_base_corpus |>
  select(id, date, texts, all_of(cols_features)) |>
  as.data.frame()

corpus_sento <- sentometrics::sento_corpus(
  corpusdf = df_sento_input,
  do.clean = FALSE
)

archivo_01_corpus <- file.path(ruta_proc, "01_sento_corpus.rds")
saveRDS(corpus_sento, archivo_01_corpus)
message("✔ [T-07] 01_sento_corpus.rds guardado con ", length(cols_features), " features.")

# 3. Fase 2: Léxicos, Modificadores de Valencia y Sentimiento (T-09, T-10, T-11) ----

## 3.1 Construcción de diccionarios de polaridad en español (nrc_es y crimen_es) ----
nrc_es_crudo <- syuzhet::get_sentiment_dictionary("nrc", language = "spanish")
lex_nrc_es <- nrc_es_crudo |>
  filter(sentiment %in% c("positive", "negative")) |>
  mutate(
    x = str_to_lower(str_trim(word)),
    y = ifelse(sentiment == "positive", 1.0, -1.0)
  ) |>
  filter(!str_detect(x, "\\s+"), nchar(x) > 1) |>
  group_by(x) |>
  summarise(y = round(mean(y), 4), .groups = "drop") |>
  filter(y != 0) |>
  as.data.frame()

# Léxico especializado en seguridad ciudadana y criminalidad urbana de Bogotá
lex_crimen_bogota <- tribble(
  ~x,                ~y,
  # Términos de alta negatividad (delitos y violencia)
  "homicidio",      -1.0,  "homicidios",     -1.0,  "asesinato",      -1.0,
  "asesinado",      -1.0,  "asesinada",      -1.0,  "sicariato",      -1.0,
  "sicario",        -1.0,  "sicarios",       -1.0,  "feminicidio",    -1.0,
  "masacre",        -1.0,  "cadaver",        -0.9,  "cadaveres",      -0.9,
  "embolsado",      -1.0,  "embolsados",     -1.0,  "balacera",       -0.9,
  "tiroteo",        -0.9,  "baleado",        -0.9,  "apunalado",      -0.9,
  "punalada",       -0.8,  "extorsion",      -0.9,  "extorsiones",    -0.9,
  "secuestro",      -1.0,  "violacion",      -1.0,  "abuso",          -0.8,
  "atraco",         -0.9,  "atracos",        -0.9,  "atracador",      -0.9,
  "atracadores",    -0.9,  "robo",           -0.8,  "robos",          -0.8,
  "robaron",        -0.8,  "hurtaron",       -0.8,  "hurto",          -0.7,
  "hurtos",         -0.7,  "asalto",         -0.8,  "asaltantes",     -0.8,
  "fleteo",         -0.9,  "fleteros",       -0.9,  "escopolamina",   -0.9,
  "burundanga",     -0.9,  "cosquilleo",     -0.7,  "raponazo",       -0.7,
  "rompevidrios",   -0.7,  "apartamenteros", -0.8,  "halado",         -0.7,
  "desguazadero",   -0.8,  "microtrafico",   -0.8,  "narcomenudeo",   -0.8,
  "delincuencia",   -0.8,  "delincuentes",   -0.8,  "criminales",     -0.8,
  "banda",          -0.6,  "bandas",         -0.6,  "inseguridad",    -0.8,
  "miedo",          -0.7,  "temor",          -0.7,  "panico",         -0.8,
  "zozobra",        -0.8,  "impunidad",      -0.8,  "victima",        -0.6,
  "victimas",       -0.6,  "herido",         -0.7,  "heridos",        -0.7,
  "lesionado",      -0.6,  "peligro",        -0.7,  "amenaza",        -0.7,
  "amenazas",       -0.7,  "denuncia",       -0.4,  "denuncias",      -0.4,
  # Términos positivos de respuesta institucional, judicialización y prevención
  "captura",         0.7,  "capturas",        0.7,  "capturado",       0.7,
  "capturados",      0.7,  "desarticulacion", 0.9,  "desarticulada",   0.9,
  "desarticulan",    0.9,  "recuperacion",    0.8,  "recuperado",      0.8,
  "recuperados",     0.8,  "incautacion",     0.7,  "incautaron",      0.7,
  "rescate",         0.8,  "rescatado",       0.8,  "judicializacion", 0.8,
  "judicializados",  0.8,  "condena",         0.6,  "condenado",       0.6,
  "esclarecimiento", 0.8,  "reduccion",       0.8,  "disminucion",     0.8,
  "disminuyo",       0.8,  "bajo",            0.4,  "prevencion",      0.7,
  "proteccion",      0.7,  "seguridad",       0.5,  "seguro",          0.7,
  "segura",          0.7,  "patrullaje",      0.6,  "operativo",       0.5,
  "operativos",      0.5,  "megatoma",        0.6,  "convivencia",     0.8,
  "tranquilidad",    0.8,  "justicia",        0.7,  "apoyo",           0.5
) |>
  group_by(x) |>
  summarise(y = mean(y), .groups = "drop") |>
  as.data.frame()

## 3.2 Tabla de modificadores de valencia en español (valenceIn: x, y, t) ----
# Convención sentometrics (list_valence_shifters):
# t = 1 (negadores, y = -1.0), t = 2 (amplificadores, y = 1.8),
# t = 3 (atenuadores, y = 0.2), t = 4 (adversativos, y = -1.0)
tabla_valence_es <- tribble(
  ~x,               ~y,   ~t,
  # Negadores (t = 1)
  "no",            -1.0,  1L,
  "nunca",         -1.0,  1L,
  "jamas",         -1.0,  1L,
  "sin",           -1.0,  1L,
  "ni",            -1.0,  1L,
  "tampoco",       -1.0,  1L,
  "ningun",        -1.0,  1L,
  "ninguna",       -1.0,  1L,
  # Amplificadores (t = 2)
  "muy",            1.8,  2L,
  "altamente",      1.8,  2L,
  "sumamente",      1.8,  2L,
  "extremadamente", 1.8,  2L,
  "demasiado",      1.8,  2L,
  "gravemente",     1.8,  2L,
  "brutalmente",    1.8,  2L,
  "masivamente",    1.8,  2L,
  "totalmente",     1.8,  2L,
  "completamente",  1.8,  2L,
  "bastante",       1.5,  2L,
  "fuerte",         1.5,  2L,
  # Atenuadores / Deamplificadores (t = 3)
  "poco",           0.2,  3L,
  "apenas",         0.2,  3L,
  "levemente",      0.2,  3L,
  "ligeramente",    0.2,  3L,
  "parcialmente",   0.2,  3L,
  "casi",           0.4,  3L,
  # Adversativos (t = 4)
  "pero",          -1.0,  4L,
  "aunque",        -1.0,  4L,
  "obstante",      -1.0,  4L,
  "embargo",       -1.0,  4L
) |>
  as.data.frame()

lexicons_es <- sentometrics::sento_lexicons(
  lexiconsIn = list(
    nrc_es    = lex_nrc_es,
    crimen_es = lex_crimen_bogota
  ),
  valenceIn = tabla_valence_es
)
attr(lexicons_es, "valence_table_full") <- tabla_valence_es

archivo_02_lexicons <- file.path(ruta_proc, "02_lexicons_es.rds")
saveRDS(lexicons_es, archivo_02_lexicons)
message("✔ [T-09] 02_lexicons_es.rds guardado (nrc_es + crimen_es + valenceIn).")

## 3.3 Cómputo de sentimiento a nivel documento: proportionalPol vs TFIDF (T-10) ----
sentiment_scores <- sentometrics::compute_sentiment(
  x           = corpus_sento,
  lexicons    = lexicons_es,
  how         = "proportionalPol",
  do.sentence = FALSE
)

sentiment_tfidf <- sentometrics::compute_sentiment(
  x           = corpus_sento,
  lexicons    = lexicons_es,
  how         = "TFIDF",
  do.sentence = FALSE
)

# Cálculo exacto del puntaje documental por léxico (los 3 clústeres son exhaustivos y excluyentes)
df_sent_doc <- as_tibble(sentiment_scores) |>
  transmute(
    id = id,
    word_count = word_count,
    score_nrc_es = round(
      `nrc_es--c_centro` + `nrc_es--c_comercial` + `nrc_es--c_residencial`,
      4
    ),
    score_crimen_es = round(
      `crimen_es--c_centro` + `crimen_es--c_comercial` + `crimen_es--c_residencial`,
      4
    ),
    sentimiento_score = round(0.5 * score_nrc_es + 0.5 * score_crimen_es, 4)
  ) |>
  left_join(
    as_tibble(sentiment_tfidf) |>
      transmute(
        id = id,
        score_tfidf_compuesto = round(
          0.5 * (`nrc_es--c_centro` + `nrc_es--c_comercial` + `nrc_es--c_residencial`) +
            0.5 * (`crimen_es--c_centro` + `crimen_es--c_comercial` + `crimen_es--c_residencial`),
          4
        )
      ),
    by = "id"
  )

attr(sentiment_scores, "comparacion_metodologica") <- list(
  correlacion_propPol_tfidf = cor(
    df_sent_doc$sentimiento_score,
    df_sent_doc$score_tfidf_compuesto,
    use = "complete.obs"
  ),
  media_nrc_es      = mean(df_sent_doc$score_nrc_es, na.rm = TRUE),
  media_crimen_es   = mean(df_sent_doc$score_crimen_es, na.rm = TRUE),
  media_combinada   = mean(df_sent_doc$sentimiento_score, na.rm = TRUE)
)

archivo_03_scores <- file.path(ruta_proc, "03_sentiment_scores.rds")
saveRDS(sentiment_scores, archivo_03_scores)
message("✔ [T-10] 03_sentiment_scores.rds guardado (how = 'proportionalPol').")

## 3.4 Enriquecimiento del dataset de noticias y extracción de peakdocs (T-11) ----
df_noticias_enriquecida <- df_noticias |>
  select(-any_of(c(
    "id", "word_count", "score_nrc_es", "score_crimen_es",
    "score_tfidf_compuesto", "sentimiento_score", "sentimiento_categoria",
    "cluster_id", "cluster_nombre", "perfil_seguridad"
  ))) |>
  mutate(id = paste0("doc_", row_number())) |>
  left_join(df_sent_doc, by = "id") |>
  left_join(
    df_clusters |> select(localidad, cluster_id, cluster_nombre, perfil_seguridad),
    by = "localidad"
  ) |>
  mutate(
    sentimiento_categoria = case_when(
      sentimiento_score < -0.02 ~ "Negativo",
      sentimiento_score >  0.02 ~ "Positivo",
      TRUE                      ~ "Neutro"
    )
  )

arrow::write_parquet(df_noticias_enriquecida, archivo_noticias)
message("✔ Corpus de noticias enriquecido guardado en: ", archivo_noticias)

# Extracción oficial con peakdocs() (T-11)
ids_peak_both <- sentometrics::peakdocs(sentiment_scores, n = 25, type = "both")
ids_peak_neg  <- sentometrics::peakdocs(sentiment_scores, n = 25, type = "neg")
ids_peak_pos  <- sentometrics::peakdocs(sentiment_scores, n = 25, type = "pos")

# Tabla de consulta de documentos pico globales y por localidad
peak_por_localidad <- df_noticias_enriquecida |>
  group_by(localidad) |>
   arrange(sentimiento_score) |>
  slice(unique(c(1:5, (n() - 4):n()))) |>
  ungroup()

tabla_peak_docs <- df_noticias_enriquecida |>
  mutate(
    es_pico_global = id %in% unique(c(ids_peak_both, ids_peak_neg, ids_peak_pos)),
    tipo_pico = case_when(
      id %in% ids_peak_neg ~ "Pico Negativo Global",
      id %in% ids_peak_pos ~ "Pico Positivo Global",
      id %in% peak_por_localidad$id & sentimiento_score < 0 ~ "Extremo Negativo Local",
      id %in% peak_por_localidad$id & sentimiento_score > 0 ~ "Extremo Positivo Local",
      TRUE ~ "Regular"
    )
  ) |>
  select(
    id, fecha, año, mes, localidad, cluster_nombre, fuente,
    delito_sdscj, modalidad_dai, es_dai_estricto, confianza_dai,
    titulo, resumen, enlace, word_count,
    score_nrc_es, score_crimen_es, sentimiento_score,
    sentimiento_categoria, es_pico_global, tipo_pico
  ) |>
  arrange(sentimiento_score)

objeto_04_peak_docs <- list(
  peak_ids_both   = ids_peak_both,
  peak_ids_neg    = ids_peak_neg,
  peak_ids_pos    = ids_peak_pos,
  tabla_completa  = as.data.table(tabla_peak_docs),
  top_criticas    = as.data.table(tabla_peak_docs |> filter(tipo_pico != "Regular"))
)

archivo_04_peaks <- file.path(ruta_proc, "04_peak_docs.rds")
saveRDS(objeto_04_peak_docs, archivo_04_peaks)
message("✔ [T-11] 04_peak_docs.rds guardado con noticias pico y catálogo filtrable.")

# 4. Fase 3: Series de Tiempo Multidimensionales (T-13, T-14, T-15) ----

## 4.1 Configuración de ctr_agg y cálculo de sento_measures (T-13) ----
control_agg <- sentometrics::ctr_agg(
  howWithin      = "proportionalPol",
  howDocs        = "proportional",
  howTime        = c("linear", "exponential", "beta"),
  by             = "month",
  lag            = 6,
  alphasExp      = c(0.2, 0.5),
  aBeta          = c(1, 2),
  bBeta          = c(2, 3),
  do.ignoreZeros = TRUE,
  fill           = "zero"
)

medidas_sento <- sentometrics::sento_measures(
  sento_corpus = corpus_sento,
  lexicons     = lexicons_es,
  ctr          = control_agg
)

medidas_sento <- sentometrics::measures_fill(medidas_sento, fill = "zero")

archivo_05_measures <- file.path(ruta_proc, "05_sento_measures.rds")
saveRDS(medidas_sento, archivo_05_measures)
message("✔ [T-13] 05_sento_measures.rds guardado (", ncol(medidas_sento$measures) - 1, " series mensuales).")

## 4.2 Remodelado en formato Long y Wide para Shiny (T-14) ----
dt_measures_wide <- data.table::as.data.table(medidas_sento)

# Diccionario de etiquetas legibles para features
mapa_etiquetas_features <- c(
  c_centro               = "Clúster: Céntrico e Institucional",
  c_comercial            = "Clúster: Comercial y Automotor",
  c_residencial          = "Clúster: Residencial y Periférico",
  tema_hurto_personas    = "Tema: Hurto a Personas y Transporte",
  tema_hurto_patrimonial = "Tema: Hurto Patrimonial y Vehículos",
  tema_violencia_vida    = "Tema: Violencia, Homicidio y Extorsión",
  tema_institucional     = "Tema: Operatividad y Política de Seguridad"
)
for (i in seq_along(localidades_unicas)) {
  mapa_etiquetas_features[nombres_feat_loc[i]] <- localidades_unicas[i]
}

df_measures_long <- as_tibble(dt_measures_wide) |>
  pivot_longer(
    cols      = -date,
    names_to  = "serie_id",
    values_to = "valor"
  ) |>
  separate(
    col    = serie_id,
    into   = c("lexicon", "feature", "time"),
    sep    = "--",
    remove = FALSE
  ) |>
  mutate(
    grupo_feature = case_when(
      str_starts(feature, "c_")    ~ "Clúster Territorial",
      str_starts(feature, "tema_") ~ "Tópico / Modalidad DAI",
      str_starts(feature, "loc_")  ~ "Localidad",
      TRUE                         ~ "Otro"
    ),
    feature_label = coalesce(unname(mapa_etiquetas_features[feature]), feature),
    lexicon_label = case_when(
      lexicon == "nrc_es"    ~ "Léxico General (NRC Español)",
      lexicon == "crimen_es" ~ "Léxico Seguridad y Crimen Bogotá",
      TRUE                   ~ lexicon
    )
  )

# Control de auditoría: verificar que todas las series tengan grupo_feature válido
stopifnot(all(df_measures_long$grupo_feature != "Otro"))

objeto_06_measures_long <- list(
  long = as.data.table(df_measures_long),
  wide = dt_measures_wide
)

archivo_06_long <- file.path(ruta_proc, "06_measures_long.rds")
saveRDS(objeto_06_measures_long, archivo_06_long)
archivo_06_wide <- file.path(ruta_proc, "06_measures_wide.rds")
saveRDS(dt_measures_wide, archivo_06_wide)
message("✔ [T-14] 06_measures_long.rds guardado (", nrow(df_measures_long), " filas en formato long).")

## 4.3 Índice global ponderado y fechas pico con peakdates() (T-15) ----
medidas_global_dt <- stats::aggregate(medidas_sento, do.global = TRUE)
fechas_pico_ambas <- sentometrics::peakdates(medidas_sento, n = 8, type = "both")
fechas_pico_neg   <- sentometrics::peakdates(medidas_sento, n = 8, type = "neg")
fechas_pico_pos   <- sentometrics::peakdates(medidas_sento, n = 8, type = "pos")

df_global_index <- as_tibble(medidas_global_dt) |>
  mutate(
    date      = as.Date(date),
    es_pico   = date %in% as.Date(c(fechas_pico_ambas, fechas_pico_neg)),
    tipo_pico = case_when(
      date %in% as.Date(fechas_pico_neg) ~ "Pico de Alarma / Negatividad",
      date %in% as.Date(fechas_pico_pos) ~ "Pico Positivo / Operatividad",
      TRUE                               ~ "Normal"
    )
  )

objeto_07_global_index <- list(
  serie_global      = as.data.table(df_global_index),
  peakdates_both    = as.Date(fechas_pico_ambas),
  peakdates_neg     = as.Date(fechas_pico_neg),
  peakdates_pos     = as.Date(fechas_pico_pos)
)

archivo_07_global <- file.path(ruta_proc, "07_global_index.rds")
saveRDS(objeto_07_global_index, archivo_07_global)
message("✔ [T-15] 07_global_index.rds guardado con índice global y peakdates.")

# 5. Fase 4: Modelado Econométrico Elastic Net y Atribuciones (T-17) ----

## 5.1 Construcción de la serie mensual empírica real de intensidad delictiva (y_t) ----
# Desagregamos las tasas anuales oficiales de SIEDCO/SDS utilizando la participación
# mensual observada de hechos delictivos de alto impacto (es_dai_estricto) en cada año.
tasas_anuales_distrito <- panel_delitos |>
  group_by(año) |>
  summarise(
    hurto_personas_total = sum(hurto_personas, na.rm = TRUE),
    hurto_total_denuncias = sum(hurto_personas + hurto_residencias + hurto_motos, na.rm = TRUE),
    poblacion_distrito   = sum(poblacion, na.rm = TRUE),
    tasa_anual_personas  = (hurto_personas_total / poblacion_distrito) * 100000,
    tasa_anual_total     = (hurto_total_denuncias / poblacion_distrito) * 100000,
    .groups = "drop"
  )

pesos_mensuales_dai <- df_noticias_enriquecida |>
  mutate(
    date_mes = as.Date(format(as.Date(fecha), "%Y-%m-01")),
    año      = as.integer(format(date_mes, "%Y"))
  ) |>
  group_by(año, date_mes) |>
  summarise(
    n_noticias_mes = n(),
    n_dai_mes      = sum(es_dai_estricto, na.rm = TRUE),
    .groups = "drop"
  ) |>
  group_by(año) |>
  mutate(
    prop_mensual_dai = (n_dai_mes + 1) / sum(n_dai_mes + 1)
  ) |>
  ungroup()

fechas_medidas <- as.Date(sentometrics::get_dates(medidas_sento))

serie_objetivo_mensual <- tibble(
  date     = fechas_medidas,
  date_mes = as.Date(format(fechas_medidas, "%Y-%m-01")),
  año      = as.integer(format(fechas_medidas, "%Y"))
) |>
  left_join(tasas_anuales_distrito, by = "año") |>
  left_join(pesos_mensuales_dai, by = c("año", "date_mes")) |>
  mutate(
    prop_mensual_dai     = coalesce(prop_mensual_dai, 1 / 12),
    # Tasa mensualizada equivalente por cada 100.000 habitantes
    y_tasa_hurto_mensual = round(tasa_anual_total * prop_mensual_dai, 2),
    y_tasa_pers_mensual  = round(tasa_anual_personas * prop_mensual_dai, 2)
  )

y_vector <- serie_objetivo_mensual$y_tasa_hurto_mensual
stopifnot(length(y_vector) == nrow(medidas_sento$measures))
stopifnot(all(!is.na(y_vector)))

## 5.2 Estimación de sento_model con penalización Elastic Net (h = 1 y contemporáneo) ----
control_modelo <- sentometrics::ctr_model(
  model        = "gaussian",
  type         = "BIC",
  alphas       = c(0.2, 0.5, 0.8),
  h            = 1,
  do.iter      = FALSE,
  do.progress  = FALSE
)

modelo_elasticnet <- sentometrics::sento_model(
  sento_measures = medidas_sento,
  y              = y_vector,
  ctr            = control_modelo
)

## 5.3 Cálculo de atribuciones multidimensionales (features, lexicons, time) ----
atribuciones_raw  <- sentometrics::attributions(
  model          = modelo_elasticnet,
  sento_measures = medidas_sento,
  do.lags        = TRUE,
  do.normalize   = FALSE
)

atribuciones_norm <- sentometrics::attributions(
  model          = modelo_elasticnet,
  sento_measures = medidas_sento,
  do.lags        = TRUE,
  do.normalize   = TRUE
)

# Extracción de valores ajustados y residuales para visualización en Shiny
n_total_m <- nrow(medidas_sento$measures)
idx_x     <- 1:(n_total_m - control_modelo$h)
idx_y     <- (1 + control_modelo$h):n_total_m

mat_x_alineada   <- as.matrix(medidas_sento$measures[idx_x, -1])
y_alineado       <- y_vector[idx_y]
fechas_alineadas <- fechas_medidas[idx_y]

pred_matriz <- as.numeric(predict(
  modelo_elasticnet,
  newx = mat_x_alineada
))

df_ajuste_modelo <- tibble(
  date       = fechas_alineadas,
  observado  = y_alineado,
  predicho   = round(pred_matriz, 2),
  residual   = round(y_alineado - pred_matriz, 2)
)

# Extracción de coeficientes distintos de cero
coefs_sparse <- coef(modelo_elasticnet$reg)
df_coeficientes <- tibble(
  variable    = rownames(coefs_sparse),
  coeficiente = as.numeric(coefs_sparse[, 1])
) |>
  filter(variable != "(Intercept)", abs(coeficiente) > 1e-8) |>
  arrange(desc(abs(coeficiente)))

# Formateo tidy de atribuciones para Plotly en Shiny
convertir_attr_long <- function(attr_obj, dimension) {
  dt_dim <- attr_obj[[dimension]]
  if (is.null(dt_dim)) return(tibble())
  as_tibble(dt_dim) |>
    mutate(date = as.Date(date)) |>
    pivot_longer(
      cols      = -date,
      names_to  = "componente",
      values_to = "atribucion"
    ) |>
    mutate(
      dimension        = dimension,
      componente_label = coalesce(unname(mapa_etiquetas_features[componente]), componente)
    )
}

df_attr_long_raw <- bind_rows(
  convertir_attr_long(atribuciones_raw, "features"),
  convertir_attr_long(atribuciones_raw, "lexicons"),
  convertir_attr_long(atribuciones_raw, "time")
)

df_attr_long_norm <- bind_rows(
  convertir_attr_long(atribuciones_norm, "features"),
  convertir_attr_long(atribuciones_norm, "lexicons"),
  convertir_attr_long(atribuciones_norm, "time")
)

objeto_08_attributions <- list(
  modelo            = modelo_elasticnet,
  attributions_raw  = atribuciones_raw,
  attributions_norm = atribuciones_norm,
  attr_long_raw     = as.data.table(df_attr_long_raw),
  attr_long_norm    = as.data.table(df_attr_long_norm),
  ajuste_temporal   = df_ajuste_modelo,
  coeficientes      = df_coeficientes,
  metricas_modelo   = list(
    alpha_optimo    = modelo_elasticnet$alpha,
    lambda_optimo   = modelo_elasticnet$lambda,
    horizonte_h     = control_modelo$h,
    criterio        = control_modelo$type,
    r2_in_sample    = round(cor(df_ajuste_modelo$observado, df_ajuste_modelo$predicho)^2, 4),
    rmse            = round(sqrt(mean(df_ajuste_modelo$residual^2)), 3),
    n_observaciones = nrow(df_ajuste_modelo),
    n_predictores   = sum(modelo_elasticnet$nVar),
    n_activos       = nrow(df_coeficientes)
  )
)

archivo_08_attr <- file.path(ruta_proc, "08_attributions.rds")
saveRDS(objeto_08_attributions, archivo_08_attr)
message("✔ [T-17] 08_attributions.rds guardado (Elastic Net alpha = ", modelo_elasticnet$alpha, ", R2 = ", objeto_08_attributions$metricas_modelo$r2_in_sample, ").")

# 6. Fase 5: Consolidación del Panel Anual Localidad × Año (2022–2026) ----

## 6.1 Agregación anual de sentimiento y cobertura por localidad ----
noticias_agg <- df_noticias_enriquecida |>
  filter(año >= 2022 & año <= 2026) |>
  group_by(localidad, año) |>
  summarise(
    noticias_conteo      = n(),
    noticias_dai_conteo  = sum(es_dai_estricto, na.rm = TRUE),
    sentimiento_promedio = round(mean(sentimiento_score, na.rm = TRUE), 4),
    sentimiento_nrc      = round(mean(score_nrc_es, na.rm = TRUE), 4),
    sentimiento_crimen   = round(mean(score_crimen_es, na.rm = TRUE), 4),
    sentimiento_mediana  = round(median(sentimiento_score, na.rm = TRUE), 4),
    prop_negativas       = round(mean(sentimiento_categoria == "Negativo", na.rm = TRUE) * 100, 2),
    prop_positivas       = round(mean(sentimiento_categoria == "Positivo", na.rm = TRUE) * 100, 2),
    prop_neutras         = round(mean(sentimiento_categoria == "Neutro", na.rm = TRUE) * 100, 2),
    .groups = "drop"
  )

## 6.2 Fusión con el panel delictivo y demográfico oficial ----
panel_consolidado <- panel_delitos |>
  left_join(noticias_agg, by = c("localidad", "año")) |>
  mutate(
    noticias_conteo      = replace_na(noticias_conteo, 0L),
    noticias_dai_conteo  = replace_na(noticias_dai_conteo, 0L),
    sentimiento_promedio = replace_na(sentimiento_promedio, 0),
    sentimiento_nrc      = replace_na(sentimiento_nrc, 0),
    sentimiento_crimen   = replace_na(sentimiento_crimen, 0),
    sentimiento_mediana  = replace_na(sentimiento_mediana, 0),
    prop_negativas       = replace_na(prop_negativas, 0),
    prop_positivas       = replace_na(prop_positivas, 0),
    prop_neutras         = replace_na(prop_neutras, 0)
  )

stopifnot(nrow(panel_consolidado) == 95)

archivo_panel_final <- file.path(ruta_proc, "panel_consolidado_localidad_anual.parquet")
arrow::write_parquet(panel_consolidado, archivo_panel_final)
message("✔ Panel consolidado anual guardado en: ", archivo_panel_final)
